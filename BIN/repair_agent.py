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
AUTO_HOTFIX = os.environ.get("REPAIR_AUTO_HOTFIX", "0") == "1"

ALERT_FILE = "infobot_alert.json"
STATUS_FILE = "repair_status.json"

TOOLS_BAT_DIR = Path(r"C:\OANDA_MT5_SYSTEM_STAGING\TOOLS_BAT")


def _now_utc() -> str:
    return datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")


def _ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def _write_json_atomic(path: Path, obj: Dict[str, object]) -> None:
    _ensure_dir(path.parent)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def _read_json(path: Path) -> Optional[Dict[str, object]]:
    if not path.exists():
        return None
    try:
        obj = json.loads(path.read_text(encoding="utf-8", errors="ignore"))
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

    sb_ok = bool(sb_pid and _pid_is_running(sb_pid)) and _log_mtime_ok(logs_dir / "safetybot.log", 180)
    sc_ok = bool(sc_pid and _pid_is_running(sc_pid)) and _log_mtime_ok(logs_dir / "scudfab02.log", 180)
    lr_ok = _log_mtime_ok(logs_dir / "learner_offline.log", 300)

    return bool(sb_ok and sc_ok and lr_ok)


def _run_cmd(cmd: str) -> Tuple[int, str]:
    try:
        cp = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return int(cp.returncode), (cp.stdout or "") + (cp.stderr or "")
    except Exception as e:
        return 1, f"EXC:{type(e).__name__}:{e}"


def _run_diag(root: Path) -> None:
    diag = root / "TOOLS" / "diag_bundle_v6.py"
    if diag.exists():
        _run_cmd(f"\"{sys.executable}\" \"{diag}\"")


def _restart_all(root: Path) -> None:
    stop_bat = TOOLS_BAT_DIR / "stop.bat"
    start_bat = TOOLS_BAT_DIR / "start.bat"
    if not stop_bat.exists():
        stop_bat = root / "stop.bat"
    if not start_bat.exists():
        start_bat = root / "start.bat"
    if stop_bat.exists():
        _run_cmd(f"\"{stop_bat}\"")
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


def main() -> int:
    root = get_runtime_root(enforce=True)
    _setup_logging(root)
    run_dir = root / "RUN"
    _ensure_dir(run_dir)
    lock_path = run_dir / "repair_agent.lock"

    if lock_path.exists():
        print("REPAIR_AGENT juz dziala.")
        return 1
    lock_path.write_text(str(os.getpid()), encoding="utf-8")

    status_path = run_dir / STATUS_FILE
    alert_path = run_dir / ALERT_FILE

    last_event = ""
    retry_count = 0

    try:
        while True:
            alert = _read_json(alert_path)
            if alert and not bool(alert.get("resolved")):
                event_id = str(alert.get("event_id") or "")
                if event_id and event_id != last_event:
                    last_event = event_id
                    retry_count = 0

                if event_id and retry_count < MAX_RETRY_PER_ALERT:
                    retry_count += 1
                    logging.warning(f"ALARM {event_id} wykryty, proba={retry_count}")
                    _write_json_atomic(status_path, {
                        "event_id": event_id,
                        "ts_utc": _now_utc(),
                        "status": "repairing",
                        "attempt": retry_count,
                    })

                    _run_diag(root)
                    _restart_all(root)
                    time.sleep(RESTART_WAIT_SEC)

                    if _component_ok(root):
                        _write_json_atomic(status_path, {
                            "event_id": event_id,
                            "ts_utc": _now_utc(),
                            "status": "recovered",
                            "attempt": retry_count,
                        })
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
                                    _write_json_atomic(status_path, {
                                        "event_id": event_id,
                                        "ts_utc": _now_utc(),
                                        "status": "recovered",
                                        "attempt": retry_count,
                                        "hotfix": "applied",
                                    })
                                    alert["resolved"] = True
                                    _write_json_atomic(alert_path, alert)
                                    logging.info("ODZYSKANO po hotfix")
                                    continue

                        _write_json_atomic(status_path, {
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
                        })
                        logging.error("NAPRAWA nieudana")
                        # Stop repeated attempts for this alert; require operator intervention
                        alert["resolved"] = True
                        _write_json_atomic(alert_path, alert)

            time.sleep(CHECK_SEC)
    finally:
        try:
            lock_path.unlink(missing_ok=True)
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
