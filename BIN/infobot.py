# -*- coding: utf-8 -*-
"""
INFOBOT — screen-only system status notifier.

Design:
- Read-only inputs: LOGS/, RUN/, EVIDENCE/, DIAG/
- Outputs: console + LOGS/infobot/infobot.log + RUN/infobot_heartbeat.json + RUN/infobot_alert.json
- No network, no trading, no strategy impact.
"""
from __future__ import annotations

import json
import logging
import os
import sqlite3
import shutil
import subprocess
import time
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Dict, Optional

try:
    from .runtime_root import get_runtime_root
except Exception:
    from runtime_root import get_runtime_root

try:
    from . import common_guards as cg
except Exception:
    import common_guards as cg

try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None  # type: ignore

TZ_PL = ZoneInfo("Europe/Warsaw") if ZoneInfo else None
UTC = timezone.utc

HEARTBEAT_SEC = 60
HEARTBEAT_MODE = "quiet"  # quiet|verbose
HEARTBEAT_PRINT_EVERY_SEC = 7200
WATCHDOG_SEC = 20
SUMMARY_HOUR = 20
SUMMARY_MIN = 30
DAILY_ALIVE_HOUR = 5
DAILY_ALIVE_MIN = 0
LOG_STALE_SEC = 180
GRACE_SEC = 900
ALERT_REPEAT_SEC = 3600
CONSOLE_ENABLED = False
STATE_FILE = "infobot_state.json"
HEARTBEAT_FILE = "infobot_heartbeat.json"
ALERT_FILE = "infobot_alert.json"
RECOVER_FILE = "repair_status.json"
GUI_STATUS_FILE = "infobot_gui_status.json"
DEFAULT_COLOR = "07"
ALIVE_COLOR = "0C"
FAIL_COLOR = "0C"
GUI_ENABLED = True
GUI_TITLE = "INFOBOT"
GUI_FONT = ("Consolas", 36, "bold")
GUI_MIN_SIZE = (320, 180)
GUI_AREA_SCALE = 0.387  # sqrt(0.15) ~= 0.387 => ~15% screen area
GUI_TOPMOST = False
EMAIL_ENABLED = os.environ.get("INFOBOT_EMAIL_ENABLED", "0") == "1"
EMAIL_DAILY_ENABLED = os.environ.get("INFOBOT_EMAIL_DAILY_ENABLED", "0") == "1"
EMAIL_WEEKLY_ENABLED = os.environ.get("INFOBOT_EMAIL_WEEKLY_ENABLED", "0") == "1"
EMAIL_ALIVE_ENABLED = os.environ.get("INFOBOT_EMAIL_ALIVE_ENABLED", "0") == "1"
EMAIL_ALIVE_EVERY_SEC = 0
EMAIL_SMTP_HOST = os.environ.get("INFOBOT_SMTP_HOST", "")
EMAIL_SMTP_PORT = int(os.environ.get("INFOBOT_SMTP_PORT", "587"))
EMAIL_SMTP_TLS = os.environ.get("INFOBOT_SMTP_TLS", "1") == "1"
EMAIL_SMTP_USER = os.environ.get("INFOBOT_SMTP_USER", "")
EMAIL_SMTP_PASS = os.environ.get("INFOBOT_SMTP_PASS", "")
EMAIL_FROM = os.environ.get("INFOBOT_EMAIL_FROM", EMAIL_SMTP_USER)
EMAIL_TO = os.environ.get("INFOBOT_EMAIL_TO", "skitela@gmail.com,skitela@outlook.com")
EMAIL2_SMTP_HOST = os.environ.get("INFOBOT2_SMTP_HOST", "")
EMAIL2_SMTP_PORT = int(os.environ.get("INFOBOT2_SMTP_PORT", "587"))
EMAIL2_SMTP_TLS = os.environ.get("INFOBOT2_SMTP_TLS", "1") == "1"
EMAIL2_SMTP_USER = os.environ.get("INFOBOT2_SMTP_USER", "")
EMAIL2_SMTP_PASS = os.environ.get("INFOBOT2_SMTP_PASS", "")
EMAIL2_FROM = os.environ.get("INFOBOT2_EMAIL_FROM", EMAIL2_SMTP_USER)
WEEKLY_SUMMARY_DAY = 0  # Monday
WEEKLY_SUMMARY_HOUR = 8
WEEKLY_SUMMARY_MIN = 0
AUDIT_COMMAND = os.environ.get("INFOBOT_AUDIT_CMD", "")
REPAIR_COMMAND = os.environ.get("INFOBOT_REPAIR_CMD", "")
WEEKLY_REPAIR_ENABLED = os.environ.get("INFOBOT_WEEKLY_REPAIR_ENABLED", "1") == "1"
WEEKLY_REPAIR_DAY = int(os.environ.get("INFOBOT_WEEKLY_REPAIR_DAY", "0"))
WEEKLY_REPAIR_HOUR = int(os.environ.get("INFOBOT_WEEKLY_REPAIR_HOUR", "1"))
WEEKLY_REPAIR_MIN = int(os.environ.get("INFOBOT_WEEKLY_REPAIR_MIN", "0"))
CODEX_REPAIR_STATES = {"repairing_codex", "repairing_codex_pending", "repairing_codex_running"}

# Location for operator tools moved out of release root.
TOOLS_BAT_DIR = Path(r"C:\OANDA_MT5_SYSTEM_STAGING\TOOLS_BAT")


def _now_utc() -> datetime:
    return datetime.now(tz=UTC)


def _now_pl() -> datetime:
    if TZ_PL is None:
        return _now_utc()
    return _now_utc().astimezone(TZ_PL)


def _ts_pl_hm() -> str:
    return _now_pl().strftime("%Y-%m-%d %H:%M")


def _status_text(base: str, extra: str = "") -> str:
    if extra:
        return f"{base}\n{extra}"
    return base


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
    moved = False
    last_exc: Optional[Exception] = None
    try:
        os.replace(tmp, path)
        moved = True
    except Exception as exc:
        last_exc = exc
        try:
            shutil.move(str(tmp), str(path))
            moved = True
        except Exception as exc2:
            last_exc = exc2
    if not moved:
        try:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            moved = True
        finally:
            try:
                tmp.unlink(missing_ok=True)
            except Exception:
                pass
    if not moved and last_exc is not None:
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
    log_dir = root / "LOGS" / "infobot"
    _ensure_dir(log_dir)
    log_file = log_dir / "infobot.log"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=[logging.FileHandler(str(log_file), encoding="utf-8")],
    )


def _set_console_color(code: str) -> None:
    if os.name != "nt":
        return
    try:
        os.system(f"color {code}")
    except Exception:
        pass


def _print_banner(lines: list[str], color: str) -> None:
    if not CONSOLE_ENABLED:
        return
    _set_console_color(color)
    for line in lines:
        print(line)
    _set_console_color(DEFAULT_COLOR)


def _init_gui(
    stop_cmd: Optional[str] = None,
    repair_cmd: Optional[str] = None,
    status_path: Optional[str] = None,
) -> Optional[Dict[str, object]]:
    if not GUI_ENABLED:
        return None
    try:
        import tkinter as tk
        root = tk.Tk()
        root.title(GUI_TITLE)
        sw = root.winfo_screenwidth()
        sh = root.winfo_screenheight()
        w = max(GUI_MIN_SIZE[0], int(sw * GUI_AREA_SCALE))
        h = max(GUI_MIN_SIZE[1], int(sh * GUI_AREA_SCALE))
        x = max(0, int((sw - w) / 2))
        y = max(0, int((sh - h) / 2))
        root.geometry(f"{w}x{h}+{x}+{y}")
        root.minsize(GUI_MIN_SIZE[0], GUI_MIN_SIZE[1])
        root.resizable(True, True)
        if GUI_TOPMOST:
            root.attributes("-topmost", True)
        font_size_main = max(16, int(h * 0.12))
        font_size_time = max(10, int(font_size_main * 0.5))

        main = tk.Frame(root)
        main.pack(expand=True, fill="both")
        main.pack_propagate(False)

        label_status = tk.Label(
            main,
            text="SYSTEM ZYJE",
            font=(GUI_FONT[0], font_size_main, GUI_FONT[2]),
            fg="red",
            justify="center",
        )
        label_status.configure(wraplength=int(w * 0.9))
        label_status.pack(expand=True)

        label_time = tk.Label(
            main,
            text=f"DATA I GODZINA {_ts_pl_hm()}",
            font=(GUI_FONT[0], font_size_time, "normal"),
            fg="red",
            justify="center",
        )
        label_time.pack()

        btns = tk.Frame(root)
        btns.pack(fill="x", pady=6)

        gui = {
            "root": root,
            "label_status": label_status,
            "label_time": label_time,
            "closed": False,
            "exit": False,
            "hidden": False,
            "stop_cmd": stop_cmd or "",
            "repair_cmd": repair_cmd or "",
            "status_path": status_path or "",
        }

        def _on_close():
            try:
                gui["hidden"] = True
                root.withdraw()
            except Exception:
                pass

        def _on_stop_infobot():
            try:
                _gui_action_stop_infobot(gui)
            except Exception:
                pass

        def _on_stop_system():
            try:
                _gui_action_stop_system(gui)
            except Exception:
                try:
                    _gui_action_stop_infobot(gui)
                except Exception:
                    pass

        def _on_repair():
            try:
                _gui_action_repair_now(gui)
            except Exception:
                pass

        b1 = tk.Button(btns, text="WYLACZ INFOBOTA", command=_on_stop_infobot)
        b2 = tk.Button(btns, text="WYLACZ SYSTEM", command=_on_stop_system)
        b3 = tk.Button(btns, text="NAPRAWA TERAZ", command=_on_repair)
        b1.pack(side="left", expand=True, padx=6)
        b2.pack(side="left", expand=True, padx=6)
        b3.pack(side="right", expand=True, padx=6)

        root.protocol("WM_DELETE_WINDOW", _on_close)
        return gui
    except Exception:
        return None


def _gui_update(gui: Optional[Dict[str, object]], text: str, color: str) -> None:
    if not gui:
        return
    try:
        if gui.get("closed"):
            return
        label_status = gui.get("label_status")
        label_time = gui.get("label_time")
        root = gui.get("root")
        if gui.get("hidden") and root is not None:
            try:
                root.deiconify()
                root.lift()
                gui["hidden"] = False
            except Exception:
                pass
        if label_status is not None:
            label_status.config(text=text, fg=color)
        if label_time is not None:
            label_time.config(text=f"DATA I GODZINA {_ts_pl_hm()}", fg=color)
        last_text = str(gui.get("last_status_text") or "")
        if text != last_text:
            logging.info(f"GUI_STATUS text={text}")
            gui["last_status_text"] = text
        _gui_status_emit(gui, text, color)
        if root is not None:
            try:
                if not root.winfo_exists():
                    return
                w = int(root.winfo_width() or 0)
                if w > 0 and label_status is not None:
                    label_status.configure(wraplength=int(w * 0.9))
            except Exception:
                pass
            root.update()
    except Exception:
        pass


def _gui_status_emit(gui: Dict[str, object], text: str, color: str) -> None:
    path_raw = str(gui.get("status_path") or "").strip()
    if not path_raw:
        return
    payload = {
        "ts_utc": _now_utc().isoformat().replace("+00:00", "Z"),
        "text": text,
        "color": color,
    }
    try:
        _write_json_atomic(Path(path_raw), payload)
    except Exception:
        pass


def _gui_pump(gui: Optional[Dict[str, object]]) -> None:
    if not gui or gui.get("closed"):
        return
    try:
        root = gui.get("root")
        if root is not None and root.winfo_exists():
            root.update()
    except Exception:
        pass


def _gui_request_exit(gui: Dict[str, object]) -> None:
    gui["closed"] = True
    gui["exit"] = True
    root = gui.get("root")
    if root is None:
        return
    try:
        root.destroy()
    except Exception:
        pass


def _gui_action_stop_infobot(gui: Dict[str, object]) -> None:
    _gui_request_exit(gui)


def _gui_action_stop_system(gui: Dict[str, object]) -> None:
    cmd = str(gui.get("stop_cmd") or "").strip()
    if cmd:
        subprocess.Popen(f"\"{cmd}\"", shell=True)
    _gui_request_exit(gui)


def _gui_action_repair_now(gui: Dict[str, object]) -> None:
    cmd = _materialize_repair_command(str(gui.get("repair_cmd") or ""), event_prefix="MANUAL")
    if not cmd:
        return
    subprocess.Popen(cmd, shell=True)


def _parse_recipients(raw: str) -> list[str]:
    parts = [p.strip() for p in (raw or "").split(",")]
    return [p for p in parts if p]


def _email_ready() -> bool:
    if not EMAIL_ENABLED:
        return False
    if not _parse_recipients(EMAIL_TO):
        return False
    if EMAIL_SMTP_HOST and EMAIL_FROM:
        return True
    if EMAIL2_SMTP_HOST and EMAIL2_FROM:
        return True
    return False


def _send_email_via(
    host: str,
    port: int,
    use_tls: bool,
    user: str,
    password: str,
    sender: str,
    recipients: list[str],
    subject: str,
    body: str,
) -> bool:
    if not _email_ready():
        return False
    try:
        import smtplib
        from email.message import EmailMessage

        msg = EmailMessage()
        msg["From"] = sender
        msg["To"] = ", ".join(recipients)
        msg["Subject"] = subject
        msg.set_content(body)

        with smtplib.SMTP(host, port, timeout=15) as smtp:
            if use_tls:
                smtp.starttls()
            if user and password:
                smtp.login(user, password)
            smtp.send_message(msg)
        return True
    except Exception as exc:
        logging.info(f"EMAIL send failed: {exc}")
        return False


def _send_email(subject: str, body: str) -> bool:
    if not _email_ready():
        return False
    recipients = _parse_recipients(EMAIL_TO)
    if not recipients:
        return False
    if EMAIL_SMTP_HOST and EMAIL_FROM:
        if _send_email_via(
            EMAIL_SMTP_HOST,
            EMAIL_SMTP_PORT,
            EMAIL_SMTP_TLS,
            EMAIL_SMTP_USER,
            EMAIL_SMTP_PASS,
            EMAIL_FROM,
            recipients,
            subject,
            body,
        ):
            return True
    if EMAIL2_SMTP_HOST and EMAIL2_FROM:
        if _send_email_via(
            EMAIL2_SMTP_HOST,
            EMAIL2_SMTP_PORT,
            EMAIL2_SMTP_TLS,
            EMAIL2_SMTP_USER,
            EMAIL2_SMTP_PASS,
            EMAIL2_FROM,
            recipients,
            subject,
            body,
        ):
            return True
    return False


def _pid_is_running(pid: int) -> bool:
    try:
        pid = int(pid)
    except Exception:
        return False
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            import subprocess
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


def _acquire_lock(lock_path: Path) -> None:
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if lock_path.exists():
        try:
            raw = lock_path.read_text(encoding="utf-8", errors="ignore").strip()
            pid = int(raw) if raw.isdigit() else 0
            if pid and _pid_is_running(pid):
                raise RuntimeError("ALREADY_RUNNING")
        except Exception:
            raise RuntimeError("ALREADY_RUNNING")
    lock_path.write_text(str(os.getpid()), encoding="utf-8")


def _release_lock(lock_path: Path) -> None:
    try:
        lock_path.unlink(missing_ok=True)
    except Exception:
        try:
            # Fallback for ACL layouts that allow write but deny delete.
            lock_path.write_text("", encoding="utf-8")
        except Exception:
            pass


def _log_mtime_ok(path: Path, stale_sec: int) -> bool:
    if not path.exists():
        return False
    age = time.time() - path.stat().st_mtime
    return age <= float(stale_sec)


def _component_status(root: Path) -> Dict[str, Dict[str, object]]:
    run_dir = root / "RUN"
    logs_dir = root / "LOGS"

    out: Dict[str, Dict[str, object]] = {}

    # SafetyBot: lock + log
    sb_lock = run_dir / "safetybot.lock"
    sb_log = logs_dir / "safetybot.log"
    out["safetybot"] = {
        "lock": sb_lock.exists(),
        "log_ok": _log_mtime_ok(sb_log, LOG_STALE_SEC),
        "log_path": str(sb_log).replace("\\", "/"),
    }

    # SCUD: lock + log
    sc_lock = run_dir / "scudfab02.lock"
    sc_log = logs_dir / "scudfab02.log"
    out["scudfab02"] = {
        "lock": sc_lock.exists(),
        "log_ok": _log_mtime_ok(sc_log, LOG_STALE_SEC),
        "log_path": str(sc_log).replace("\\", "/"),
    }

    # Learner: log only
    lr_log = logs_dir / "learner_offline.log"
    out["learner_offline"] = {
        "lock": False,
        "log_ok": _log_mtime_ok(lr_log, LOG_STALE_SEC),
        "log_path": str(lr_log).replace("\\", "/"),
    }

    return out


def _should_alert(status: Dict[str, Dict[str, object]]) -> Optional[str]:
    for name, st in status.items():
        if name not in ("safetybot", "scudfab02"):
            continue
        if (not st.get("lock")) and (not st.get("log_ok")):
            return "critical"
        if not st.get("lock"):
            return "critical"
        if not st.get("log_ok"):
            return "critical"
    return None


def _daily_summary(root: Path, status: Dict[str, Dict[str, object]]) -> str:
    lines = []
    lines.append("INFOBOT PODSUMOWANIE DOBOWE")
    lines.append(f"czas_pl={_now_pl().isoformat()}")
    for name, st in status.items():
        lines.append(f"{name}: blokada={int(bool(st.get('lock')))} log_poprawny={int(bool(st.get('log_ok')))}")
    for line in _llm_key_status_lines():
        lines.append(line)
    return "\n".join(lines)


def _llm_key_statuses() -> Dict[str, Dict[str, object]]:
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


def _llm_key_status_lines() -> list[str]:
    out: list[str] = []
    stats = _llm_key_statuses()
    for provider in ("openai", "gemini"):
        item = stats.get(provider) or {}
        out.append(
            f"llm_key_{provider}: status={item.get('status')} "
            f"present={int(bool(item.get('present')))} "
            f"rotation_due={int(bool(item.get('rotation_due')))} "
            f"age_days={item.get('age_days')}"
        )
    return out


def _reason_pl(reason: str) -> str:
    if not reason:
        return ""
    parts = reason.split(":", 1)
    if len(parts) == 2:
        comp, code = parts[0], parts[1]
    else:
        comp, code = "", parts[0]
    mapping = {
        "no_lock_and_log_stale": "brak_lock_i_stary_log",
        "missing_lock": "brak_lock",
        "log_stale": "log_nieaktualny",
    }
    code_pl = mapping.get(code, code)
    return f"{comp}:{code_pl}" if comp else code_pl


def _repair_view(status: str, attempt: int) -> tuple[str, str]:
    st = str(status or "")
    if st in CODEX_REPAIR_STATES:
        return _status_text("SYSTEM W NAPRAWIE PRZEZ CODEX"), "orange"
    if st == "repairing":
        extra = f"NAPRAWA PROBA {attempt}/3" if attempt else "NAPRAWA W TOKU"
        return _status_text("SYSTEM W NAPRAWIE", extra), "orange"
    return _status_text("SYSTEM W NAPRAWIE"), "orange"


def _sqlite_connect_ro(db_path: Path) -> sqlite3.Connection:
    uri = f"file:{db_path.as_posix()}?mode=ro"
    return sqlite3.connect(uri, uri=True, timeout=5)


def _trade_stats(root: Path, since_iso: str) -> Dict[str, object]:
    db_path = root / "DB" / "decision_events.sqlite"
    if not db_path.exists():
        return {"signals_total": 0, "buy": 0, "sell": 0, "wins": 0, "losses": 0, "pnl_net": 0.0}
    conn = _sqlite_connect_ro(db_path)
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT signal, outcome_pnl_net
            FROM decision_events
            WHERE outcome_closed_ts_utc IS NOT NULL AND outcome_closed_ts_utc != ''
              AND outcome_closed_ts_utc >= ?
            """,
            (since_iso,)
        )
        rows = cur.fetchall()
    finally:
        try:
            conn.close()
        except Exception:
            pass

    buy = 0
    sell = 0
    wins = 0
    losses = 0
    pnl_sum = 0.0
    for sig, pnl in rows:
        s = str(sig or "").upper()
        if "BUY" in s:
            buy += 1
        if "SELL" in s:
            sell += 1
        try:
            p = float(pnl or 0.0)
        except Exception:
            p = 0.0
        pnl_sum += p
        if p > 0:
            wins += 1
        else:
            losses += 1

    return {
        "signals_total": int(len(rows)),
        "buy": int(buy),
        "sell": int(sell),
        "wins": int(wins),
        "losses": int(losses),
        "pnl_net": float(round(pnl_sum, 6)),
    }


def _default_repair_command(root: Path) -> str:
    script = root / "RUN" / "CODEX_REPAIR_AUTOMATION.ps1"
    if not script.exists():
        return ""
    return (
        f'powershell -NoProfile -ExecutionPolicy Bypass -File "{script}" '
        f'-Root "{root}" -EventId "{{event_id}}"'
    )


def _materialize_repair_command(cmd_template: str, event_prefix: str = "MANUAL") -> str:
    cmd = str(cmd_template or "").strip()
    if not cmd:
        return ""
    if "{event_id}" in cmd:
        return cmd.format(event_id=f"{event_prefix}-{uuid.uuid4().hex[:8]}")
    return cmd


def main() -> int:
    root = get_runtime_root(enforce=True)
    _setup_logging(root)
    run_dir = root / "RUN"
    _ensure_dir(run_dir)
    lock_path = run_dir / "infobot.lock"

    try:
        _acquire_lock(lock_path)
    except Exception:
        if CONSOLE_ENABLED:
            print("INFOBOT juz dziala.")
        return 1

    state_path = run_dir / STATE_FILE
    heartbeat_path = run_dir / HEARTBEAT_FILE
    alert_path = run_dir / ALERT_FILE
    recover_path = run_dir / RECOVER_FILE
    gui_status_path = run_dir / GUI_STATUS_FILE

    state = _read_json(state_path) or {}
    last_summary_date = str(state.get("last_summary_date") or "")
    last_summary_ts = str(state.get("last_summary_ts_utc") or "")
    last_recover_ts = str(state.get("last_recover_ts_utc") or "")
    last_alert_email_id = str(state.get("last_alert_email_id") or "")
    last_daily_email_date = str(state.get("last_daily_email_date") or "")
    last_weekly_email_date = str(state.get("last_weekly_email_date") or "")
    last_alive_email_date = str(state.get("last_alive_email_date") or "")
    last_weekly_repair_date = str(state.get("last_weekly_repair_date") or "")

    last_hb = 0.0
    last_hb_print = 0.0
    last_watch = 0.0
    last_recover_id = ""
    last_alert_reason = ""
    last_alert_ts = 0.0
    current_status = "alive"
    repair_cmd = REPAIR_COMMAND.strip()
    if not repair_cmd:
        repair_cmd = AUDIT_COMMAND.strip()
    if not repair_cmd:
        repair_cmd = _default_repair_command(root)

    stop_path = root / "stop.bat"
    if not stop_path.exists():
        stop_path = TOOLS_BAT_DIR / "stop.bat"

    gui = _init_gui(str(stop_path), repair_cmd, str(gui_status_path))
    if not gui:
        # Headless fallback: keep status file updates even when tkinter is unavailable.
        gui = {
            "closed": False,
            "exit": False,
            "hidden": False,
            "status_path": str(gui_status_path),
        }
    start_ts = time.time()

    try:
        while True:
            now = time.time()
            if now - last_hb >= HEARTBEAT_SEC:
                hb = {
                    "ts_utc": _now_utc().isoformat().replace("+00:00", "Z"),
                    "ts_pl": _now_pl().isoformat(),
                    "status": "alive",
                }
                _write_json_atomic(heartbeat_path, hb)
                logging.info("HEARTBEAT status=alive")
                last_hb = now
                current_status = "alive"

            if now - last_watch >= WATCHDOG_SEC:
                status = _component_status(root)
                reason = _should_alert(status)
                in_grace = (now - start_ts) < float(GRACE_SEC)
                if (not in_grace) and reason:
                    should_emit = False
                    if reason != last_alert_reason:
                        should_emit = True
                    elif (now - last_alert_ts) >= float(ALERT_REPEAT_SEC):
                        should_emit = True
                    if should_emit:
                        alert = {
                            "event_id": f"ALERT-{uuid.uuid4().hex[:8]}",
                            "ts_utc": _now_utc().isoformat().replace("+00:00", "Z"),
                            "ts_pl": _now_pl().isoformat(),
                            "reason": reason,
                            "status": status,
                            "severity": "CRITICAL",
                            "resolved": False,
                        }
                        _write_json_atomic(alert_path, alert)
                        logging.warning("ALARM krytyczny")
                        rec_probe = _read_json(recover_path) or {}
                        rec_status_probe = str(rec_probe.get("status") or "")
                        if rec_status_probe in CODEX_REPAIR_STATES:
                            txt, color = _repair_view(rec_status_probe, int(rec_probe.get("attempt") or 0))
                            _gui_update(gui, txt, color)
                            current_status = "repairing_codex"
                        else:
                            _gui_update(gui, _status_text("SYSTEM NIE DZIALA"), "red")
                            if str(alert.get("event_id") or "") != last_alert_email_id:
                                body = "\n".join([
                                    "INFOBOT ALARM",
                                    f"ts_pl={alert['ts_pl']}",
                                    "status=nie_dziala",
                                ])
                                if _send_email("INFOBOT NIE DZIALA", body):
                                    last_alert_email_id = str(alert.get("event_id") or "")
                                    state["last_alert_email_id"] = last_alert_email_id
                                    _write_json_atomic(state_path, state)
                            current_status = "alert"
                        last_alert_reason = reason
                        last_alert_ts = now
                last_watch = now

            # Recovery notification
            rec = _read_json(recover_path)
            if rec and str(rec.get("status")) == "recovered":
                rid = str(rec.get("event_id") or "")
                if rid and rid != last_recover_id:
                    _print_banner([
                        "===========================",
                        "        SYSTEM ZYJE        ",
                        "===========================",
                    ], ALIVE_COLOR)
                    logging.info("ODZYSKANO system dziala")
                    last_recover_id = rid
                    last_recover_ts = str(rec.get("ts_utc") or "")
                    state["last_recover_ts_utc"] = last_recover_ts
                    _write_json_atomic(state_path, state)
                    _gui_update(gui, _status_text("SYSTEM ZYJE"), "red")
                    _send_email("INFOBOT ODZYSKANY", "System odzyskany i dziala.")
                    current_status = "alive"

            if rec and str(rec.get("status") or "") in ({"repairing"} | CODEX_REPAIR_STATES):
                rec_status = str(rec.get("status") or "")
                attempt = int(rec.get("attempt") or 0)
                txt, color = _repair_view(rec_status, attempt)
                _gui_update(gui, txt, color)
                current_status = "repairing_codex" if rec_status in CODEX_REPAIR_STATES else "repairing"

            if rec and str(rec.get("status")) == "failed":
                rid = str(rec.get("event_id") or "")
                if rid and rid != last_recover_id:
                    steps = rec.get("next_steps") or []
                    _print_banner([
                        "============================================",
                        " SYSTEM NIE DZIALA - WYMAGANA INTERWENCJA   ",
                        "============================================",
                    ], FAIL_COLOR)
                    if isinstance(steps, list) and steps:
                        if CONSOLE_ENABLED:
                            print("KROKI: ")
                            for i, s in enumerate(steps, start=1):
                                print(f"{i}) {s}")
                    logging.error("SYSTEM DOWN - operator intervention required")
                    last_recover_id = rid
                    _gui_update(gui, _status_text("SYSTEM NIE DZIALA"), "red")
                    current_status = "down"

            # Daily summary at 20:30 PL (once per day)
            pl = _now_pl()
            if pl.hour == SUMMARY_HOUR and pl.minute >= SUMMARY_MIN:
                date_key = pl.strftime("%Y-%m-%d")
                if date_key != last_summary_date:
                    status = _component_status(root)
                    # Compute uptime since last summary (fallback 24h)
                    now_utc = _now_utc()
                    if last_summary_ts:
                        try:
                            since = datetime.fromisoformat(last_summary_ts.replace("Z", "+00:00"))
                        except Exception:
                            since = now_utc - timedelta(hours=24)
                    else:
                        since = now_utc - timedelta(hours=24)
                    uptime_h = round((now_utc - since).total_seconds() / 3600.0, 2)

                    stats = _trade_stats(root, since.isoformat().replace("+00:00", "Z"))
                    stats_24 = _trade_stats(root, (now_utc - timedelta(hours=24)).isoformat().replace("+00:00", "Z"))

                    summary = _daily_summary(root, status)
                    summary += f"\nczas_pracy_h_od_ostatniego_podsumowania={uptime_h}"
                    if last_recover_ts:
                        summary += f"\nostatnia_naprawa_ts_utc={last_recover_ts}"
                    summary += (
                        f"\nsygnaly_razem={stats['signals_total']} kupno={stats['buy']} sprzedaz={stats['sell']} "
                        f"wygrane={stats['wins']} przegrane={stats['losses']} pnl_net={stats['pnl_net']}"
                    )
                    stats_7d = _trade_stats(root, (now_utc - timedelta(days=7)).isoformat().replace("+00:00", "Z"))
                    summary += (
                        f"\nostatnie_24h_sygnaly_razem={stats_24['signals_total']} kupno={stats_24['buy']} "
                        f"sprzedaz={stats_24['sell']} wygrane={stats_24['wins']} przegrane={stats_24['losses']} "
                        f"pnl_net={stats_24['pnl_net']}"
                    )
                    summary += (
                        f"\nostatnie_7d_sygnaly_razem={stats_7d['signals_total']} kupno={stats_7d['buy']} "
                        f"sprzedaz={stats_7d['sell']} wygrane={stats_7d['wins']} przegrane={stats_7d['losses']} "
                        f"pnl_net={stats_7d['pnl_net']}"
                    )
                    logging.info(summary.replace("\n", " | "))
                    if CONSOLE_ENABLED:
                        print(summary)
                    last_summary_date = date_key
                    state["last_summary_date"] = last_summary_date
                    last_summary_ts = now_utc.isoformat().replace("+00:00", "Z")
                    state["last_summary_ts_utc"] = last_summary_ts
                    _write_json_atomic(state_path, state)

                    if EMAIL_DAILY_ENABLED and date_key != last_daily_email_date:
                        if _send_email("INFOBOT PODSUMOWANIE DOBOWE", summary):
                            last_daily_email_date = date_key
                            state["last_daily_email_date"] = last_daily_email_date
                            _write_json_atomic(state_path, state)

            if pl.weekday() == WEEKLY_SUMMARY_DAY and pl.hour == WEEKLY_SUMMARY_HOUR and pl.minute >= WEEKLY_SUMMARY_MIN:
                week_key = pl.strftime("%Y-%m-%d")
                if week_key != last_weekly_email_date:
                    status = _component_status(root)
                    now_utc = _now_utc()
                    since_week = (now_utc - timedelta(days=7)).isoformat().replace("+00:00", "Z")
                    stats_7d = _trade_stats(root, since_week)
                    weekly = _daily_summary(root, status)
                    weekly += f"\nzakres_tygodniowy_utc={since_week}..{now_utc.isoformat().replace('+00:00', 'Z')}"
                    weekly += (
                        f"\nostatnie_7d_sygnaly_razem={stats_7d['signals_total']} kupno={stats_7d['buy']} "
                        f"sprzedaz={stats_7d['sell']} wygrane={stats_7d['wins']} przegrane={stats_7d['losses']} "
                        f"pnl_net={stats_7d['pnl_net']}"
                    )
                    if EMAIL_WEEKLY_ENABLED:
                        if _send_email("INFOBOT PODSUMOWANIE TYGODNIOWE", weekly):
                            last_weekly_email_date = week_key
                            state["last_weekly_email_date"] = last_weekly_email_date
                            _write_json_atomic(state_path, state)

            # Weekly repair schedule (defaults: Monday 01:00 PL)
            if WEEKLY_REPAIR_ENABLED and repair_cmd:
                day_cfg = min(6, max(0, int(WEEKLY_REPAIR_DAY)))
                hour_cfg = min(23, max(0, int(WEEKLY_REPAIR_HOUR)))
                min_cfg = min(59, max(0, int(WEEKLY_REPAIR_MIN)))
                repair_key = pl.strftime("%Y-%m-%d")
                if pl.weekday() == day_cfg and pl.hour == hour_cfg and pl.minute >= min_cfg:
                    if repair_key != last_weekly_repair_date and current_status not in {"repairing", "repairing_codex"}:
                        cmd = _materialize_repair_command(repair_cmd, event_prefix="WEEKLY")
                        try:
                            subprocess.Popen(cmd, shell=True)
                            last_weekly_repair_date = repair_key
                            state["last_weekly_repair_date"] = last_weekly_repair_date
                            _write_json_atomic(state_path, state)
                            logging.info("WEEKLY_REPAIR triggered")
                            _gui_update(gui, _status_text("SYSTEM W NAPRAWIE", "NOCNA NAPRAWA"), "orange")
                            current_status = "repairing_codex"
                        except Exception as exc:
                            logging.error(f"WEEKLY_REPAIR launch failed: {exc}")

            # Daily alive info at 05:00 PL (once per day)
            date_key_alive = pl.strftime("%Y-%m-%d")
            if pl.hour == DAILY_ALIVE_HOUR and pl.minute >= DAILY_ALIVE_MIN:
                if date_key_alive != last_alive_email_date:
                    _gui_update(gui, _status_text("SYSTEM ZYJE"), "red")
                    if EMAIL_ALIVE_ENABLED and _email_ready():
                        body = "\n".join([
                            "INFOBOT DZIALA",
                            f"ts_pl={pl.isoformat()}",
                            "status=zyje",
                        ])
                        if _send_email("INFOBOT DZIALA", body):
                            last_alive_email_date = date_key_alive
                            state["last_alive_email_date"] = last_alive_email_date
                            _write_json_atomic(state_path, state)

            if gui and gui.get("exit"):
                break
            _gui_pump(gui)
            time.sleep(1)
    finally:
        _release_lock(lock_path)


if __name__ == "__main__":
    raise SystemExit(main())
