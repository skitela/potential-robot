# -*- coding: utf-8 -*-
"""
REPAIR_AGENT — auto-repair companion for InfoBot.

Behavior:
- Watches RUN/infobot_alert.json
- Creates DIAG bundle
- Attempts restart via stop.bat/start.bat
- Optionally applies latest HOTFIX/incoming/* (auto-repair)
- Writes RUN/repair_status.json
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Optional, Tuple

try:
    from .runtime_root import get_runtime_root
except Exception:
    from runtime_root import get_runtime_root

try:
    from . import common_guards as cg
except Exception:
    import common_guards as cg

UTC = timezone.utc

CHECK_SEC = 10
RESTART_WAIT_SEC = 15
MAX_RETRY_PER_ALERT = 3
REPAIRING_STALE_SEC = 90
ALERT_STALE_RESOLVE_SEC = 21600
LEARNER_LOG_STALE_SEC = int(os.environ.get("REPAIR_LEARNER_LOG_STALE_SEC", "7200"))
REQUIRE_LEARNER_OK = os.environ.get("REPAIR_REQUIRE_LEARNER_OK", "0") == "1"
AUTO_HOTFIX = os.environ.get("REPAIR_AUTO_HOTFIX", "0") == "1"
CODEX_ESCALATE_ENABLED = os.environ.get("REPAIR_CODEX_ENABLED", "1") == "1"
CODEX_TIMEOUT_SEC = int(os.environ.get("REPAIR_CODEX_TIMEOUT_SEC", "21600"))

ALERT_FILE = "infobot_alert.json"
STATUS_FILE = "repair_status.json"
CODEX_REQUEST_FILE = "codex_repair_request.json"

TOOLS_BAT_DIR = Path(r"C:\OANDA_MT5_SYSTEM_STAGING\TOOLS_BAT")


def _now_utc() -> str:
    return datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")


def _ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def _write_json_atomic(path: Path, obj: Dict[str, object]) -> None:
    _ensure_dir(path.parent)
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    last_exc: Optional[Exception] = None
    for i in range(3):
        tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}.{int(time.time() * 1_000_000)}.{i}")
        wrote_tmp = False
        try:
            with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            wrote_tmp = True
        except Exception as exc:
            last_exc = exc
            continue
        try:
            try:
                os.replace(tmp, path)
                return
            except Exception as exc:
                last_exc = exc
                try:
                    shutil.move(str(tmp), str(path))
                    return
                except Exception as exc2:
                    last_exc = exc2
        finally:
            if wrote_tmp:
                try:
                    tmp.unlink(missing_ok=True)
                except Exception:
                    pass
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        return
    except Exception as exc:
        last_exc = exc
    if last_exc is not None:
        raise last_exc


def _read_json(path: Path) -> Optional[Dict[str, object]]:
    if not path.exists():
        return None
    try:
        raw = path.read_text(encoding="utf-8", errors="ignore").lstrip("\ufeff")
        obj = json.loads(raw)
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def _setup_logging(root: Path) -> None:
    log_dir = root / "LOGS" / "repair_agent"
    _ensure_dir(log_dir)
    log_file = log_dir / "repair_agent.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[logging.FileHandler(str(log_file), encoding="utf-8")],
    )


def _pid_is_running(pid: int) -> bool:
    try:
        pid = int(pid)
    except Exception:
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            cp = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}"],
                capture_output=True,
                text=True,
                check=False,
                timeout=3,
            )
            return str(pid) in (cp.stdout or "")
        except Exception:
            return True
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False


def _parse_lock_pid(path: Path) -> int:
    if not path.exists():
        return 0
    raw = path.read_text(encoding="utf-8", errors="ignore").strip()
    if raw.startswith("{"):
        try:
            return int(json.loads(raw).get("pid") or 0)
        except Exception:
            return 0
    return int(raw) if raw.isdigit() else 0


def _log_mtime_ok(path: Path, stale_sec: int) -> bool:
    if not path.exists():
        return False
    age = time.time() - path.stat().st_mtime
    return age <= float(stale_sec)


def _component_ok(root: Path) -> bool:
    run_dir = root / "RUN"
    logs_dir = root / "LOGS"

    sb_pid = _parse_lock_pid(run_dir / "safetybot.lock")
    sc_pid = _parse_lock_pid(run_dir / "scudfab02.lock")

    sb_log_ok = _log_mtime_ok(logs_dir / "safetybot.log", 180)
    sc_log_ok = _log_mtime_ok(logs_dir / "scudfab02.log", 180)
    # Lock/PID check is best-effort; fresh log is authoritative for liveness.
    sb_ok = bool((sb_pid and _pid_is_running(sb_pid)) or sb_log_ok)
    sc_ok = bool((sc_pid and _pid_is_running(sc_pid)) or sc_log_ok)
    lr_ok = _log_mtime_ok(logs_dir / "learner_offline.log", max(60, int(LEARNER_LOG_STALE_SEC)))
    if REQUIRE_LEARNER_OK:
        return bool(sb_ok and sc_ok and lr_ok)
    return bool(sb_ok and sc_ok)


def _run_cmd(cmd: str) -> Tuple[int, str]:
    try:
        cp = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return int(cp.returncode), (cp.stdout or "") + (cp.stderr or "")
    except Exception as e:
        return 1, f"EXC:{type(e).__name__}:{e}"


def _kill_pid(pid: int) -> None:
    try:
        pid = int(pid)
    except Exception:
        return
    if pid <= 0:
        return
    if os.name == "nt":
        try:
            subprocess.run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                capture_output=True,
                text=True,
                check=False,
                timeout=10,
            )
            return
        except Exception:
            return
    try:
        os.kill(pid, 9)
    except Exception:
        return


def _stop_targeted_components(root: Path) -> None:
    run_dir = root / "RUN"
    for lock_name in ("safetybot.lock", "scudfab02.lock"):
        lock_path = run_dir / lock_name
        pid = _parse_lock_pid(lock_path)
        if pid > 0:
            _kill_pid(pid)
        try:
            lock_path.unlink(missing_ok=True)
        except Exception:
            pass


def _spawn_cmd(cmd: str) -> Tuple[bool, str]:
    try:
        proc = subprocess.Popen(
            cmd,
            shell=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True, str(int(proc.pid))
    except Exception as e:
        return False, f"{type(e).__name__}:{e}"


def _run_diag(root: Path) -> None:
    diag = root / "TOOLS" / "diag_bundle_v6.py"
    if diag.exists():
        _run_cmd(f"\"{sys.executable}\" \"{diag}\"")


def _restart_all(root: Path) -> None:
    # Do not call stop.bat here: it kills RepairAgent itself and leaves "repairing" stuck.
    # Instead, restart only trading-critical components and then invoke SYSTEM_CONTROL start.
    _stop_targeted_components(root)
    system_control = root / "TOOLS" / "SYSTEM_CONTROL.ps1"
    if system_control.exists():
        _run_cmd(
            f"powershell -NoProfile -ExecutionPolicy Bypass -File \"{system_control}\" "
            f"-Action start -Root \"{root}\" -Profile full"
        )
        return
    start_bat = root / "start.bat"
    if not start_bat.exists():
        start_bat = TOOLS_BAT_DIR / "start.bat"
    if start_bat.exists():
        _run_cmd(f"\"{start_bat}\"")


def _apply_latest_hotfix(root: Path) -> bool:
    incoming = root / "HOTFIX" / "incoming"
    if not incoming.exists():
        return False
    candidates = [p for p in incoming.iterdir() if p.is_dir()]
    if not candidates:
        return False
    latest = max(candidates, key=lambda p: p.stat().st_mtime)
    tool = root / "TOOLS" / "apply_hotfix_v5.py"
    if not tool.exists():
        return False
    code, _ = _run_cmd(f"\"{sys.executable}\" \"{tool}\" --root \"{root}\" --hotfix-id \"{latest.name}\"")
    return code == 0


def _default_codex_command(root: Path, event_id: str) -> str:
    template = str(os.environ.get("REPAIR_CODEX_COMMAND", "")).strip()
    if template:
        try:
            return template.format(root=str(root), event_id=str(event_id))
        except Exception:
            return template
    script = root / "RUN" / "CODEX_REPAIR_AUTOMATION.ps1"
    return (
        f"powershell -ExecutionPolicy Bypass -File \"{script}\" "
        f"-Root \"{root}\" -EventId \"{event_id}\""
    )


def _write_codex_request(path: Path, *, root: Path, event_id: str, attempt: int, alert: Dict[str, object]) -> None:
    payload = {
        "event_id": event_id,
        "ts_utc": _now_utc(),
        "status": "pending",
        "attempt_internal": int(attempt),
        "root": str(root),
        "reason": str(alert.get("reason") or ""),
        "severity": str(alert.get("severity") or "CRITICAL"),
        "source": "repair_agent",
        "llm_keys": _llm_keys_status(),
    }
    _write_json_atomic(path, payload)


def _iso_age_sec(ts_utc: str) -> Optional[float]:
    raw = str(ts_utc or "").strip()
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None
    return max(0.0, float((datetime.now(tz=UTC) - dt).total_seconds()))


def _llm_keys_status() -> Dict[str, Dict[str, object]]:
    defaults: Dict[str, Dict[str, object]] = {
        "openai": {"status": "unknown", "present": False, "rotation_due": False, "age_days": None},
        "gemini": {"status": "unknown", "present": False, "rotation_due": False, "age_days": None},
    }
    try:
        from TOOLS.secrets_dpapi import all_rotation_status  # type: ignore

        raw = all_rotation_status(rotation_days=60)
        out: Dict[str, Dict[str, object]] = {}
        for provider in ("openai", "gemini"):
            item = raw.get(provider) if isinstance(raw, dict) else None
            if isinstance(item, dict):
                out[provider] = {
                    "status": str(item.get("status") or "unknown"),
                    "present": bool(item.get("present")),
                    "rotation_due": bool(item.get("rotation_due")),
                    "age_days": item.get("age_days"),
                }
            else:
                out[provider] = dict(defaults[provider])
        return out
    except Exception:
        return defaults


def _status_payload(base: Dict[str, object]) -> Dict[str, object]:
    payload = dict(base)
    payload["llm_keys"] = _llm_keys_status()
    return payload


def main() -> int:
    root = get_runtime_root(enforce=True)
    _setup_logging(root)
    run_dir = root / "RUN"
    _ensure_dir(run_dir)
    lock_path = run_dir / "repair_agent.lock"

    if lock_path.exists():
        pid = 0
        try:
            raw = lock_path.read_text(encoding="utf-8", errors="ignore").strip()
            pid = int(raw) if raw.isdigit() else 0
            if pid and _pid_is_running(pid):
                print("REPAIR_AGENT juz dziala.")
                return 1
            # Empty/invalid lock payload is stale and should not block startup.
            if pid <= 0:
                try:
                    lock_path.write_text(str(os.getpid()), encoding="utf-8")
                    pid = 0
                except Exception:
                    pass
            # Dead PID lock: reclaim with overwrite fallback.
            if pid > 0 and (not _pid_is_running(pid)):
                try:
                    lock_path.unlink(missing_ok=True)
                except Exception:
                    pass
                try:
                    lock_path.write_text(str(os.getpid()), encoding="utf-8")
                    pid = 0
                except Exception:
                    pass
            if pid > 0 and _pid_is_running(pid):
                print("REPAIR_AGENT juz dziala.")
                return 1
        except Exception:
            try:
                lock_path.write_text(str(os.getpid()), encoding="utf-8")
            except Exception:
                print("REPAIR_AGENT juz dziala.")
                return 1
    lock_path.write_text(str(os.getpid()), encoding="utf-8")

    status_path = run_dir / STATUS_FILE
    alert_path = run_dir / ALERT_FILE
    codex_request_path = run_dir / CODEX_REQUEST_FILE

    last_event = ""
    retry_count = 0

    try:
        while True:
            status_obj = _read_json(status_path) or {}
            status_name = str(status_obj.get("status") or "")

            if status_name == "repairing":
                ts_ref = str(status_obj.get("ts_utc") or "")
                age_sec = _iso_age_sec(ts_ref)
                if age_sec is not None and age_sec > float(REPAIRING_STALE_SEC):
                    if _component_ok(root):
                        event_id = str(status_obj.get("event_id") or "")
                        _write_json_atomic(
                            status_path,
                            _status_payload(
                                {
                                    "event_id": event_id,
                                    "ts_utc": _now_utc(),
                                    "status": "recovered",
                                    "source": "repairing_stale_recheck",
                                }
                            ),
                        )
                        alert_fix = _read_json(alert_path) or {}
                        if (
                            bool(alert_fix)
                            and (not bool(alert_fix.get("resolved")))
                            and str(alert_fix.get("event_id") or "") == event_id
                        ):
                            alert_fix["resolved"] = True
                            _write_json_atomic(alert_path, alert_fix)

            if status_name.startswith("repairing_codex"):
                ts_ref = str(status_obj.get("codex_started_ts_utc") or status_obj.get("ts_utc") or "")
                age_sec = _iso_age_sec(ts_ref)
                if age_sec is not None and age_sec > float(CODEX_TIMEOUT_SEC):
                    if _component_ok(root):
                        _write_json_atomic(
                            status_path,
                            _status_payload(
                                {
                                    "event_id": str(status_obj.get("event_id") or ""),
                                    "ts_utc": _now_utc(),
                                    "status": "recovered",
                                    "source": "codex_timeout_recheck",
                                }
                            ),
                        )
                    else:
                        _write_json_atomic(
                            status_path,
                            _status_payload(
                                {
                                    "event_id": str(status_obj.get("event_id") or ""),
                                    "ts_utc": _now_utc(),
                                    "status": "failed",
                                    "reason": "codex_timeout",
                                    "attempt": int(status_obj.get("attempt") or MAX_RETRY_PER_ALERT),
                                    "action_required": True,
                                    "next_steps": [
                                        "Sprawdz RUN/codex_repair_request.json i LOGS/repair_agent/repair_agent.log",
                                        "Uruchom recznie: powershell -ExecutionPolicy Bypass -File RUN/CODEX_REPAIR_AUTOMATION.ps1",
                                        "Jesli dalej BLAD, przeprowadz AUDIT_OFFLINE i przeanalizuj EVIDENCE",
                                    ],
                                }
                            ),
                        )

            alert = _read_json(alert_path)
            if alert and not bool(alert.get("resolved")):
                try:
                    alert_age = _iso_age_sec(str(alert.get("ts_utc") or ""))
                except Exception:
                    alert_age = None
                if alert_age is not None and alert_age > float(ALERT_STALE_RESOLVE_SEC) and _component_ok(root):
                    alert["resolved"] = True
                    _write_json_atomic(alert_path, alert)
                    _write_json_atomic(
                        status_path,
                        _status_payload(
                            {
                                "event_id": str(alert.get("event_id") or ""),
                                "ts_utc": _now_utc(),
                                "status": "recovered",
                                "source": "stale_alert_autoresolve",
                            }
                        ),
                    )
                    time.sleep(CHECK_SEC)
                    continue

                event_id = str(alert.get("event_id") or "")
                if event_id and event_id != last_event:
                    last_event = event_id
                    retry_count = 0

                if event_id and retry_count < MAX_RETRY_PER_ALERT:
                    retry_count += 1
                    logging.warning(f"ALARM {event_id} wykryty, proba={retry_count}")
                    _write_json_atomic(status_path, _status_payload({
                        "event_id": event_id,
                        "ts_utc": _now_utc(),
                        "status": "repairing",
                        "attempt": retry_count,
                    }))

                    _run_diag(root)
                    _restart_all(root)
                    time.sleep(RESTART_WAIT_SEC)

                    if _component_ok(root):
                        _write_json_atomic(status_path, _status_payload({
                            "event_id": event_id,
                            "ts_utc": _now_utc(),
                            "status": "recovered",
                            "attempt": retry_count,
                        }))
                        alert["resolved"] = True
                        _write_json_atomic(alert_path, alert)
                        logging.info("ODZYSKANO system dziala")
                    else:
                        if AUTO_HOTFIX:
                            applied = _apply_latest_hotfix(root)
                            logging.warning(f"AUTO_HOTFIX zastosowany={int(applied)}")
                            if applied:
                                _restart_all(root)
                                time.sleep(RESTART_WAIT_SEC)
                                if _component_ok(root):
                                    _write_json_atomic(status_path, _status_payload({
                                        "event_id": event_id,
                                        "ts_utc": _now_utc(),
                                        "status": "recovered",
                                        "attempt": retry_count,
                                        "hotfix": "applied",
                                    }))
                                    alert["resolved"] = True
                                    _write_json_atomic(alert_path, alert)
                                    logging.info("ODZYSKANO po hotfix")
                                    continue

                        _write_json_atomic(status_path, _status_payload({
                            "event_id": event_id,
                            "ts_utc": _now_utc(),
                            "status": "failed",
                            "attempt": retry_count,
                            "action_required": True,
                            "next_steps": [
                                "Uruchom DIAG: python TOOLS\\diag_bundle_v6.py",
                                "Sprawdz LOGS\\safetybot.log i LOGS\\scudfab02.log",
                                "Zweryfikuj HOTFIX\\incoming i uruchom apply_hotfix_v5.py recznie",
                                "Jesli dalej BLAD, uruchom start.bat (TOOLS_BAT) i przeanalizuj RUN/infobot_alert.json",
                            ],
                        }))
                        logging.error("NAPRAWA nieudana")
                        if retry_count >= MAX_RETRY_PER_ALERT and CODEX_ESCALATE_ENABLED:
                            _write_codex_request(
                                codex_request_path,
                                root=root,
                                event_id=event_id,
                                attempt=retry_count,
                                alert=alert,
                            )
                            cmd = _default_codex_command(root, event_id)
                            started, pid_or_err = _spawn_cmd(cmd)
                            if started:
                                _write_json_atomic(status_path, _status_payload({
                                    "event_id": event_id,
                                    "ts_utc": _now_utc(),
                                    "status": "repairing_codex",
                                    "attempt": retry_count,
                                    "codex_started_ts_utc": _now_utc(),
                                    "codex_pid": int(pid_or_err),
                                    "codex_timeout_sec": int(CODEX_TIMEOUT_SEC),
                                    "codex_command": cmd,
                                    "action_required": False,
                                }))
                                logging.warning(f"ESCALATE CODEX | started=1 pid={pid_or_err}")
                            else:
                                _write_json_atomic(status_path, _status_payload({
                                    "event_id": event_id,
                                    "ts_utc": _now_utc(),
                                    "status": "failed",
                                    "attempt": retry_count,
                                    "reason": "codex_launch_failed",
                                    "codex_error": pid_or_err,
                                    "action_required": True,
                                    "next_steps": [
                                        "Sprawdz REPAIR_CODEX_COMMAND w ENV",
                                        "Uruchom recznie RUN/CODEX_REPAIR_AUTOMATION.ps1",
                                        "Jesli dalej BLAD, przeprowadz AUDIT_OFFLINE",
                                    ],
                                }))
                                logging.error(f"ESCALATE CODEX | started=0 err={pid_or_err}")
                            alert["resolved"] = True
                            _write_json_atomic(alert_path, alert)
                        elif retry_count >= MAX_RETRY_PER_ALERT:
                            # Max retries reached and Codex escalation disabled -> manual intervention.
                            alert["resolved"] = True
                            _write_json_atomic(alert_path, alert)
                        else:
                            # Keep alert active for internal retries up to MAX_RETRY_PER_ALERT.
                            logging.warning(
                                f"NAPRAWA nieudana | retry_pending={retry_count}/{MAX_RETRY_PER_ALERT}"
                            )

            time.sleep(CHECK_SEC)
    finally:
        try:
            lock_path.unlink(missing_ok=True)
        except Exception as exc:
            logging.warning(f"Lock unlink failed ({lock_path}): {exc}")
            try:
                lock_path.write_text("", encoding="utf-8")
            except Exception as exc2:
                logging.warning(f"Lock fallback write failed ({lock_path}): {exc2}")


if __name__ == "__main__":
    raise SystemExit(main())
