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
import sqlite3
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

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
CHECKLIST_FILE = "repair_checklist_v1.json"

# Trading-functional watchdog (system is "alive" only when it effectively trades).
TRADE_IDLE_ALERT_SEC = int(os.environ.get("REPAIR_TRADE_IDLE_ALERT_SEC", "3600"))
TRADE_LOSS_WINDOW_SEC = int(os.environ.get("REPAIR_TRADE_LOSS_WINDOW_SEC", "172800"))  # 48h
TRADE_HEALTH_CHECK_SEC = int(os.environ.get("REPAIR_TRADE_HEALTH_CHECK_SEC", "30"))
TRADE_LOSS_MIN_DEALS_PER_SYMBOL = int(os.environ.get("REPAIR_TRADE_LOSS_MIN_DEALS_PER_SYMBOL", "6"))
TRADE_LOSS_RATIO_TRIGGER = float(os.environ.get("REPAIR_TRADE_LOSS_RATIO_TRIGGER", "0.70"))
TRADE_GLOBAL_MIN_SYMBOLS = int(os.environ.get("REPAIR_TRADE_GLOBAL_MIN_SYMBOLS", "3"))
TRADE_SYMBOL_SHADOW_SEC = int(os.environ.get("REPAIR_TRADE_SYMBOL_SHADOW_SEC", "172800"))  # 48h
TRADE_SYMBOL_SHADOW_REASON = "shadow_loss_48h"

DEFAULT_TARGET_SYMBOLS = ["EURUSD", "GBPUSD", "XAUUSD", "DAX40", "US500"]
SYMBOL_BASE_ALIASES = {
    "GOLD": "XAUUSD",
    "DE30": "DAX40",
    "DE40": "DAX40",
    "GER30": "DAX40",
    "GER40": "DAX40",
    "SPX500": "US500",
}

REPAIR_CHECKLIST_V1: List[Dict[str, str]] = [
    {
        "id": "C1_TRIGGER_CLASSIFY",
        "title": "Classify incident trigger",
        "description": "Distinguish crash/down, trade-idle, global-loss, and per-symbol-loss conditions.",
    },
    {
        "id": "C2_CAPITAL_PROTECT",
        "title": "Apply immediate capital protection",
        "description": "For persistent single-symbol loss activate shadow mode cooldown; for global loss prepare hard backoff.",
    },
    {
        "id": "C3_DIAG_CAPTURE",
        "title": "Collect diagnostics",
        "description": "Run DIAG bundle and persist context for deterministic postmortem and Codex escalation.",
    },
    {
        "id": "C4_TARGETED_RESTART",
        "title": "Restart critical components",
        "description": "Restart SafetyBot/SCUD execution path without killing RepairAgent itself.",
    },
    {
        "id": "C5_VERIFY_LIVENESS",
        "title": "Verify recovery liveness",
        "description": "Validate process/log heartbeat and functional trading-health checks after restart.",
    },
    {
        "id": "C6_EXTENDED_SELF_CHECK",
        "title": "Run extended self-checks when retries persist",
        "description": "Execute prelive/dependency checks before escalating to Codex.",
    },
    {
        "id": "C7_HOTFIX_APPLY_OPTIONAL",
        "title": "Apply latest approved hotfix",
        "description": "Use incoming hotfix only when enabled and retry path still failing.",
    },
    {
        "id": "C8_CODEX_ESCALATE",
        "title": "Escalate to Codex with full context",
        "description": "Create codex_repair_request with machine-readable context and run codex automation command.",
    },
    {
        "id": "C9_PERSIST_STATE",
        "title": "Persist repair state and lessons",
        "description": "Write status, resolutions and next actions into RUN files for traceability and future sessions.",
    },
]

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
                except Exception as exc:
                    logging.debug(f"Cleanup of tmp file failed: {exc}")
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


def _symbol_base(raw_symbol: str) -> str:
    raw = str(raw_symbol or "").strip().upper()
    if not raw:
        return ""
    base = raw.split(".", 1)[0]
    return str(SYMBOL_BASE_ALIASES.get(base, base))


def _load_target_symbols(root: Path) -> List[str]:
    cfg_path = root / "CONFIG" / "strategy.json"
    cfg = _read_json(cfg_path)
    raw = cfg.get("symbols_to_trade") if isinstance(cfg, dict) else None
    out: List[str] = []
    if isinstance(raw, list):
        for s in raw:
            base = _symbol_base(str(s or ""))
            if base and base not in out:
                out.append(base)
    if out:
        return out
    return list(DEFAULT_TARGET_SYMBOLS)


def _db_path(root: Path) -> Path:
    return root / "DB" / "decision_events.sqlite"


def _checklist_payload() -> Dict[str, object]:
    return {
        "schema": "oanda_mt5.repair_checklist.v1",
        "version": "repair.v1",
        "ts_utc": _now_utc(),
        "steps": list(REPAIR_CHECKLIST_V1),
    }


def _write_checklist_file(run_dir: Path) -> None:
    path = run_dir / CHECKLIST_FILE
    if path.exists():
        return
    _write_json_atomic(path, _checklist_payload())


def _ensure_system_state_table(conn: sqlite3.Connection) -> None:
    conn.execute(
        """CREATE TABLE IF NOT EXISTS system_state (
            key TEXT PRIMARY KEY,
            value TEXT
        )"""
    )


def _open_state_db(db_path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(db_path), timeout=5)
    try:
        conn.execute("PRAGMA busy_timeout=5000")
    except sqlite3.Error:
        pass
    # Defensive fallback for environments where file-journal writes can fail.
    try:
        conn.execute("PRAGMA journal_mode=MEMORY")
    except sqlite3.Error:
        pass
    return conn


def _db_set_state(db_path: Path, key: str, value: str) -> None:
    conn = _open_state_db(db_path)
    try:
        _ensure_system_state_table(conn)
        conn.execute(
            "INSERT OR REPLACE INTO system_state (key, value) VALUES (?, ?)",
            (str(key), str(value)),
        )
        conn.commit()
    finally:
        conn.close()


def _db_get_state_int(db_path: Path, key: str, default: int = 0) -> int:
    if not db_path.exists():
        return int(default)
    conn = _open_state_db(db_path)
    try:
        _ensure_system_state_table(conn)
        cur = conn.cursor()
        cur.execute("SELECT value FROM system_state WHERE key=?", (str(key),))
        row = cur.fetchone()
        if not row:
            return int(default)
        try:
            return int(float(row[0]))
        except Exception:
            return int(default)
    finally:
        conn.close()


def _apply_symbol_shadow_mode(root: Path, symbol_base: str, seconds: int, reason: str) -> bool:
    dbp = _db_path(root)
    if not dbp.exists():
        return False
    sym = _symbol_base(symbol_base)
    if not sym:
        return False
    now_ts = int(time.time())
    until_ts = int(now_ts + max(1, int(seconds)))
    key_until = f"cooldown_until_ts:{sym}"
    key_reason = f"cooldown_reason:{sym}"
    prev_until = _db_get_state_int(dbp, key_until, 0)
    if int(prev_until) >= int(until_ts - 60):
        return False
    _db_set_state(dbp, key_until, str(int(until_ts)))
    _db_set_state(dbp, key_reason, str(reason or TRADE_SYMBOL_SHADOW_REASON))
    return True


def _trade_health_snapshot(root: Path) -> Dict[str, object]:
    dbp = _db_path(root)
    out: Dict[str, object] = {
        "ok": True,
        "ts_utc": _now_utc(),
        "db_path": str(dbp),
        "reason": "",
        "last_trade_ts": None,
        "trade_idle_sec": None,
        "window_sec": int(max(60, TRADE_LOSS_WINDOW_SEC)),
        "window_start_ts": None,
        "target_symbols": _load_target_symbols(root),
        "symbol_stats": {},
        "global_pnl_net": 0.0,
        "global_deals": 0,
        "global_loss_all_active": False,
        "global_loss_active_symbols": [],
        "symbol_shadow_candidates": [],
    }
    if not dbp.exists():
        out["ok"] = False
        out["reason"] = "db_missing"
        return out
    now_ts = int(time.time())
    window_sec = int(max(60, TRADE_LOSS_WINDOW_SEC))
    start_ts = int(now_ts - window_sec)
    out["window_start_ts"] = int(start_ts)

    conn = sqlite3.connect(str(dbp), timeout=5)
    try:
        cur = conn.cursor()
        cur.execute("SELECT MAX(time) FROM deals_log")
        row = cur.fetchone()
        last_trade_ts = int(row[0]) if row and row[0] is not None else 0
        if last_trade_ts > 0:
            out["last_trade_ts"] = int(last_trade_ts)
            out["trade_idle_sec"] = int(max(0, now_ts - int(last_trade_ts)))
        else:
            out["last_trade_ts"] = None
            out["trade_idle_sec"] = None

        cur.execute(
            """SELECT symbol,
                      COUNT(*) AS deals_n,
                      COALESCE(SUM(profit + commission + swap), 0.0) AS pnl_net,
                      COALESCE(SUM(CASE WHEN (profit + commission + swap) < 0 THEN 1 ELSE 0 END), 0) AS loss_n,
                      MAX(time) AS last_ts
               FROM deals_log
               WHERE time >= ?
               GROUP BY symbol""",
            (int(start_ts),),
        )
        rows = cur.fetchall()
    except sqlite3.Error as exc:
        out["ok"] = False
        out["reason"] = f"db_error:{type(exc).__name__}"
        return out
    finally:
        conn.close()

    stats_by_base: Dict[str, Dict[str, object]] = {}
    total_pnl = 0.0
    total_deals = 0
    for row in rows:
        try:
            sym_raw = str(row[0] or "")
            deals_n = int(row[1] or 0)
            pnl = float(row[2] or 0.0)
            loss_n = int(row[3] or 0)
            lts = int(row[4] or 0)
        except Exception:
            continue
        base = _symbol_base(sym_raw)
        if not base:
            continue
        slot = stats_by_base.setdefault(
            base,
            {"deals": 0, "pnl_net": 0.0, "loss_deals": 0, "last_trade_ts": 0, "loss_ratio": 0.0},
        )
        slot["deals"] = int(slot["deals"]) + int(deals_n)
        slot["pnl_net"] = float(slot["pnl_net"]) + float(pnl)
        slot["loss_deals"] = int(slot["loss_deals"]) + int(loss_n)
        slot["last_trade_ts"] = max(int(slot["last_trade_ts"]), int(lts))
        total_pnl += float(pnl)
        total_deals += int(deals_n)

    for base, slot in stats_by_base.items():
        deals_n = int(slot["deals"])
        loss_n = int(slot["loss_deals"])
        slot["loss_ratio"] = (float(loss_n) / float(max(1, deals_n)))
        stats_by_base[base] = slot

    out["symbol_stats"] = stats_by_base
    out["global_pnl_net"] = float(total_pnl)
    out["global_deals"] = int(total_deals)

    min_deals = int(max(1, TRADE_LOSS_MIN_DEALS_PER_SYMBOL))
    loss_ratio_thr = float(max(0.0, min(1.0, TRADE_LOSS_RATIO_TRIGGER)))
    target_symbols = [str(x) for x in (out.get("target_symbols") or []) if str(x)]
    active_loss_symbols: List[str] = []
    shadow_candidates: List[str] = []

    for sym in target_symbols:
        st = stats_by_base.get(sym) or {}
        deals_n = int(st.get("deals") or 0)
        pnl = float(st.get("pnl_net") or 0.0)
        loss_ratio = float(st.get("loss_ratio") or 0.0)
        if deals_n >= min_deals and pnl < 0.0:
            active_loss_symbols.append(sym)
            if loss_ratio >= loss_ratio_thr:
                shadow_candidates.append(sym)

    out["global_loss_active_symbols"] = sorted(active_loss_symbols)
    out["symbol_shadow_candidates"] = sorted(shadow_candidates)
    out["global_loss_all_active"] = bool(
        len(active_loss_symbols) >= int(max(1, TRADE_GLOBAL_MIN_SYMBOLS))
        and len(active_loss_symbols) == len([s for s in target_symbols if int((stats_by_base.get(s) or {}).get("deals") or 0) >= min_deals])
        and float(total_pnl) < 0.0
    )
    return out


def _emit_synthetic_alert(root: Path, reason: str, severity: str, details: Dict[str, object]) -> str:
    run_dir = root / "RUN"
    alert_path = run_dir / ALERT_FILE
    now_local = datetime.now().astimezone()
    event_id = f"AUTO-{uuid.uuid4().hex[:10]}"
    alert = {
        "event_id": event_id,
        "ts_utc": _now_utc(),
        "ts_pl": now_local.isoformat(),
        "reason": str(reason),
        "severity": str(severity or "CRITICAL"),
        "resolved": False,
        "source": "repair_agent_health_watchdog",
        "details": details,
    }
    _write_json_atomic(alert_path, alert)
    return str(event_id)


def _health_watchdog_actions(root: Path) -> Dict[str, object]:
    out: Dict[str, object] = {
        "snapshot": {},
        "shadow_applied": [],
        "synthetic_alert_event_id": "",
        "synthetic_alert_reason": "",
    }
    health = _trade_health_snapshot(root)
    out["snapshot"] = health
    if not bool(health.get("ok")):
        return out

    # Per-symbol 48h loss protection -> shadow mode / cooldown.
    for sym in list(health.get("symbol_shadow_candidates") or []):
        try:
            if _apply_symbol_shadow_mode(root, str(sym), TRADE_SYMBOL_SHADOW_SEC, TRADE_SYMBOL_SHADOW_REASON):
                out["shadow_applied"].append(str(sym))
                logging.warning(
                    f"REPAIR_SHADOW_APPLY symbol={sym} sec={int(TRADE_SYMBOL_SHADOW_SEC)} reason={TRADE_SYMBOL_SHADOW_REASON}"
                )
        except Exception as exc:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", exc)

    run_dir = root / "RUN"
    alert_path = run_dir / ALERT_FILE
    cur_alert = _read_json(alert_path) or {}
    unresolved_active = bool(cur_alert) and (not bool(cur_alert.get("resolved")))
    if unresolved_active:
        return out

    # Strict liveness: if system previously traded and became idle too long -> trigger repair alert.
    idle_sec = health.get("trade_idle_sec")
    last_trade_ts = health.get("last_trade_ts")
    if last_trade_ts and idle_sec is not None and float(idle_sec) >= float(max(60, TRADE_IDLE_ALERT_SEC)):
        reason = f"critical:trade_idle_sec>{int(TRADE_IDLE_ALERT_SEC)}"
        eid = _emit_synthetic_alert(root, reason, "CRITICAL", {"trade_idle_sec": int(idle_sec)})
        out["synthetic_alert_event_id"] = str(eid)
        out["synthetic_alert_reason"] = str(reason)
        logging.warning(f"REPAIR_SYNTH_ALERT event_id={eid} reason={reason}")
        return out

    # If all active symbols are losing for 48h window -> critical repair alert.
    if bool(health.get("global_loss_all_active")):
        reason = "critical:loss_all_active_symbols_48h"
        eid = _emit_synthetic_alert(
            root,
            reason,
            "CRITICAL",
            {
                "symbols": list(health.get("global_loss_active_symbols") or []),
                "window_sec": int(health.get("window_sec") or TRADE_LOSS_WINDOW_SEC),
                "global_pnl_net": float(health.get("global_pnl_net") or 0.0),
            },
        )
        out["synthetic_alert_event_id"] = str(eid)
        out["synthetic_alert_reason"] = str(reason)
        logging.warning(f"REPAIR_SYNTH_ALERT event_id={eid} reason={reason}")
        return out

    return out


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
        except Exception as exc:
            logging.debug(f"Lock unlink failed: {lock_path} {exc}")


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


def _run_extended_self_checks(root: Path) -> Dict[str, object]:
    checks: Dict[str, object] = {"ts_utc": _now_utc(), "steps": []}
    commands = [
        ("prelive_go_nogo", f"\"{sys.executable}\" -B \"{root / 'TOOLS' / 'prelive_go_nogo.py'}\" --root \"{root}\""),
        (
            "dependency_hygiene",
            f"\"{sys.executable}\" \"{root / 'TOOLS' / 'dependency_hygiene.py'}\" --root \"{root}\" "
            "--fail-on-missing-requirements --fail-on-local-unresolved",
        ),
        ("secrets_scan", f"\"{sys.executable}\" \"{root / 'TOOLS' / 'secrets_scan.py'}\" --root \"{root}\""),
    ]
    for name, cmd in commands:
        rc, out = _run_cmd(cmd)
        checks["steps"].append(
            {
                "name": str(name),
                "rc": int(rc),
                "output_tail": str(out or "")[-1200:],
            }
        )
    return checks


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
    payload["repair_checklist_version"] = "repair.v1"
    payload["repair_checklist_step_ids"] = [str(x.get("id")) for x in REPAIR_CHECKLIST_V1]
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
                except Exception as exc:
                    logging.debug(f"Lock write failed: {exc}")
            # Dead PID lock: reclaim with overwrite fallback.
            if pid > 0 and (not _pid_is_running(pid)):
                try:
                    lock_path.unlink(missing_ok=True)
                except Exception as exc:
                    logging.debug(f"Lock unlink failed: {exc}")
                try:
                    lock_path.write_text(str(os.getpid()), encoding="utf-8")
                    pid = 0
                except Exception as exc:
                    logging.debug(f"Lock write failed: {exc}")
            if pid > 0 and _pid_is_running(pid):
                print("REPAIR_AGENT juz dziala.")
                return 1
        except Exception as exc:
            try:
                lock_path.write_text(str(os.getpid()), encoding="utf-8")
            except Exception as exc2:
                logging.debug(f"Lock reclaim failed: {exc} -> {exc2}")
                print("REPAIR_AGENT juz dziala.")
                return 1
    lock_path.write_text(str(os.getpid()), encoding="utf-8")

    status_path = run_dir / STATUS_FILE
    alert_path = run_dir / ALERT_FILE
    codex_request_path = run_dir / CODEX_REQUEST_FILE
    _write_checklist_file(run_dir)

    last_event = ""
    retry_count = 0
    last_health_watch: Dict[str, object] = {}
    last_health_watch_ts = 0.0

    try:
        while True:
            now_loop = time.time()
            if (now_loop - float(last_health_watch_ts)) >= float(max(5, TRADE_HEALTH_CHECK_SEC)):
                try:
                    last_health_watch = _health_watchdog_actions(root)
                except Exception as exc:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", exc)
                    last_health_watch = {"snapshot": {"ok": False, "reason": f"watchdog_error:{type(exc).__name__}"}}
                last_health_watch_ts = now_loop

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
                                    "health_watchdog": last_health_watch,
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
                                    "health_watchdog": last_health_watch,
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
                                    "health_watchdog": last_health_watch,
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
                                "health_watchdog": last_health_watch,
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
                        "health_watchdog": last_health_watch,
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
                            "health_watchdog": last_health_watch,
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
                                        "health_watchdog": last_health_watch,
                                    }))
                                    alert["resolved"] = True
                                    _write_json_atomic(alert_path, alert)
                                    logging.info("ODZYSKANO po hotfix")
                                    continue
                        extended_checks = None
                        if retry_count >= 2:
                            try:
                                extended_checks = _run_extended_self_checks(root)
                            except Exception as exc:
                                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", exc)
                                extended_checks = {
                                    "ts_utc": _now_utc(),
                                    "steps": [],
                                    "error": f"{type(exc).__name__}:{exc}",
                                }
                        _write_json_atomic(status_path, _status_payload({
                            "event_id": event_id,
                            "ts_utc": _now_utc(),
                            "status": "failed",
                            "attempt": retry_count,
                            "action_required": True,
                            "health_watchdog": last_health_watch,
                            "extended_self_checks": extended_checks,
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
                                    "health_watchdog": last_health_watch,
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
                                    "health_watchdog": last_health_watch,
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
