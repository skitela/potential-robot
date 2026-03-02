from __future__ import annotations

import json
import os
import re
import sqlite3
import subprocess
import sys
import tkinter as tk
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from tkinter import messagebox, scrolledtext

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore[assignment]


WORKSPACE_ROOT = Path(r"C:\OANDA_MT5_SYSTEM")
OBS_ROOT = WORKSPACE_ROOT / "OBSERVERS_IMPLEMENTATION_CANDIDATE"
REPORTS_ROOT = OBS_ROOT / "outputs" / "reports"
ALERTS_ROOT = OBS_ROOT / "outputs" / "alerts"
TICKETS_ROOT = OBS_ROOT / "outputs" / "tickets"
OPERATOR_STATUS_PATH = OBS_ROOT / "outputs" / "operator" / "operator_runtime_status.json"
SYSTEM_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "system_control_last.json"
REPAIR_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "codex_repair_last.json"
LIVE_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "live_trade_monitor_status.json"
MT5_SESSION_GUARD_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "mt5_session_guard_status.json"
DB_PATH = WORKSPACE_ROOT / "DB" / "decision_events.sqlite"
RETENTION_DAILY_ROOT = WORKSPACE_ROOT / "EVIDENCE" / "retention" / "daily"
RETENTION_RUNS_ROOT = WORKSPACE_ROOT / "EVIDENCE" / "retention" / "runs"
RETENTION_INCIDENTS_ROOT = WORKSPACE_ROOT / "EVIDENCE" / "retention" / "incidents"
RETENTION_POLICY_PATH = WORKSPACE_ROOT / "CONFIG" / "data_retention_policy.json"
AGENT_REFRESH_SCRIPT = OBS_ROOT / "tools" / "operator_run_agent_once.py"
LAB_INSIGHTS_SCRIPT = WORKSPACE_ROOT / "TOOLS" / "lab_insights_digest.py"
LAB_INSIGHTS_POINTER_JSON = WORKSPACE_ROOT / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.json"
LAB_INSIGHTS_POINTER_TXT = WORKSPACE_ROOT / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.txt"
LAB_INSIGHTS_SEEN_PATH = WORKSPACE_ROOT / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_seen.json"
POLICY_RUNTIME_RETRY_LOOKBACK_MIN = 60
POLICY_RUNTIME_RETRY_ALERT_THRESHOLD = 5

AGENTS = {
    "Agent Informacyjny": "agent_informacyjny",
    "Agent Rozwoju Scalpingu": "agent_rozwoju_scalpingu",
    "Agent Rekomendacyjny": "agent_rekomendacyjny",
    "Straznik Spojnosci": "agent_straznik_spojnosci",
}


class OperatorPanel(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("OANDA Panel Operatora")
        self.configure(bg="#1E2430")
        self._insights_blink_on = False
        self._set_geometry()
        self._build_widgets()
        self._refresh_status()

    def _set_geometry(self) -> None:
        screen_w = self.winfo_screenwidth()
        screen_h = self.winfo_screenheight()
        width = max(560, min(680, screen_w // 3))
        height = max(360, min(440, screen_h // 2))
        x = max(10, screen_w - width - 20)
        y = max(10, screen_h - height - 70)
        self.geometry(f"{width}x{height}+{x}+{y}")
        self.minsize(520, 340)

    def _build_widgets(self) -> None:
        title = tk.Label(
            self,
            text="OANDA MT5 - Panel Sterowania",
            font=("Segoe UI", 13, "bold"),
            fg="#F3F6FB",
            bg="#1E2430",
        )
        title.pack(pady=(10, 8))

        top_frame = tk.Frame(self, bg="#1E2430")
        top_frame.pack(fill="x", padx=10)

        tk.Button(
            top_frame,
            text="WLACZ SYSTEM",
            bg="#2E9E45",
            fg="white",
            font=("Segoe UI", 10, "bold"),
            width=18,
            height=2,
            command=self._start_system,
        ).grid(row=0, column=0, padx=6, pady=6, sticky="ew")

        tk.Button(
            top_frame,
            text="WYLACZ SYSTEM",
            bg="#C3382A",
            fg="white",
            font=("Segoe UI", 10, "bold"),
            width=18,
            height=2,
            command=self._stop_system,
        ).grid(row=0, column=1, padx=6, pady=6, sticky="ew")

        tk.Button(
            top_frame,
            text="NAPRAW SYSTEM",
            bg="#E07A16",
            fg="white",
            font=("Segoe UI", 10, "bold"),
            width=18,
            height=2,
            command=self._repair_system,
        ).grid(row=0, column=2, padx=6, pady=6, sticky="ew")

        monitor_frame = tk.Frame(self, bg="#1E2430")
        monitor_frame.pack(fill="x", padx=10)

        tk.Button(
            monitor_frame,
            text="START MONITORA AGENTOW",
            bg="#2F63C6",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._start_monitor,
        ).grid(row=0, column=0, padx=6, pady=4, sticky="ew")

        tk.Button(
            monitor_frame,
            text="STOP MONITORA AGENTOW",
            bg="#6C45B3",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._stop_monitor,
        ).grid(row=0, column=1, padx=6, pady=4, sticky="ew")

        tk.Button(
            monitor_frame,
            text="ODSWIEZ AGENTOW TERAZ",
            bg="#1F8D7E",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._refresh_all_agents_now,
        ).grid(row=1, column=0, padx=6, pady=4, sticky="ew")

        tk.Button(
            monitor_frame,
            text="DASHBOARD RETENCJI",
            bg="#4F6A2C",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._open_retention_dashboard,
        ).grid(row=1, column=1, padx=6, pady=4, sticky="ew")

        tk.Button(
            monitor_frame,
            text="AKTUALIZUJ WNIOSKI LAB",
            bg="#6D5C1E",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._refresh_lab_insights_now,
        ).grid(row=2, column=0, padx=6, pady=4, sticky="ew")

        self.lab_insights_btn = tk.Button(
            monitor_frame,
            text="WNIOSKI Z LABORATORIUM",
            bg="#3B3F48",
            fg="white",
            font=("Segoe UI", 9, "bold"),
            width=25,
            height=2,
            command=self._open_lab_insights,
        )
        self.lab_insights_btn.grid(row=2, column=1, padx=6, pady=4, sticky="ew")

        self.auto_refresh_var = tk.BooleanVar(value=True)
        tk.Checkbutton(
            monitor_frame,
            text="Auto-odswiez raport przed otwarciem agenta",
            variable=self.auto_refresh_var,
            onvalue=True,
            offvalue=False,
            fg="#D6E2F0",
            bg="#1E2430",
            selectcolor="#1E2430",
            activebackground="#1E2430",
            activeforeground="#D6E2F0",
            anchor="w",
        ).grid(row=3, column=0, columnspan=2, padx=6, pady=(2, 6), sticky="w")

        agents_frame = tk.LabelFrame(
            self,
            text="Agenci - podglad raportow",
            font=("Segoe UI", 9, "bold"),
            fg="#F3F6FB",
            bg="#1E2430",
            bd=1,
            relief="groove",
        )
        agents_frame.pack(fill="both", expand=True, padx=10, pady=8)

        row = 0
        col = 0
        for label, agent_key in AGENTS.items():
            tk.Button(
                agents_frame,
                text=label,
                bg="#34465F",
                fg="white",
                font=("Segoe UI", 9),
                width=25,
                height=2,
                command=lambda key=agent_key, lbl=label: self._open_agent_report(key, lbl),
            ).grid(row=row, column=col, padx=6, pady=6, sticky="ew")
            col += 1
            if col > 1:
                col = 0
                row += 1

        status_frame = tk.Frame(self, bg="#1E2430")
        status_frame.pack(fill="x", padx=10, pady=(0, 8))

        self.system_status_var = tk.StringVar(value="System: UNKNOWN")
        self.monitor_status_var = tk.StringVar(value="Monitor: UNKNOWN")
        self.repair_status_var = tk.StringVar(value="Naprawa: brak danych")
        self.policy_runtime_var = tk.StringVar(value="Policy runtime: brak danych")
        self.session_guard_var = tk.StringVar(value="Sesja MT5: brak danych")

        tk.Label(status_frame, textvariable=self.system_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.monitor_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.repair_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.policy_runtime_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.session_guard_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")

    def _run_command(self, command: list[str], description: str) -> None:
        try:
            subprocess.Popen(command, cwd=str(WORKSPACE_ROOT))
        except Exception as exc:
            messagebox.showerror("Blad", f"{description}\n\n{exc}")

    def _run_command_blocking(self, command: list[str], *, timeout_sec: int = 120) -> tuple[int, str, str]:
        try:
            cp = subprocess.run(
                command,
                cwd=str(WORKSPACE_ROOT),
                capture_output=True,
                text=True,
                timeout=max(15, int(timeout_sec)),
                check=False,
            )
            return int(cp.returncode), str(cp.stdout or ""), str(cp.stderr or "")
        except subprocess.TimeoutExpired as exc:
            out = str(getattr(exc, "stdout", "") or "")
            err = str(getattr(exc, "stderr", "") or "")
            return 124, out, err
        except Exception as exc:
            return 125, "", f"{type(exc).__name__}: {exc}"

    def _start_system(self) -> None:
        self._run_command(["cmd", "/c", str(WORKSPACE_ROOT / "start.bat")], "Nie udalo sie uruchomic systemu.")

    def _stop_system(self) -> None:
        self._run_command(["cmd", "/c", str(WORKSPACE_ROOT / "stop.bat")], "Nie udalo sie wylaczyc systemu.")

    def _repair_system(self) -> None:
        self._run_command(["cmd", "/c", str(WORKSPACE_ROOT / "NAPRAW_SYSTEM.bat")], "Nie udalo sie uruchomic naprawy systemu.")

    def _start_monitor(self) -> None:
        script = OBS_ROOT / "tools" / "start_operator_runtime_service.ps1"
        self._run_command(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Root", str(WORKSPACE_ROOT), "-EnablePopups"],
            "Nie udalo sie uruchomic monitora agentow.",
        )

    def _stop_monitor(self) -> None:
        script = OBS_ROOT / "tools" / "stop_operator_console.ps1"
        self._run_command(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Root", str(WORKSPACE_ROOT)],
            "Nie udalo sie zatrzymac monitora agentow.",
        )

    def _refresh_all_agents_now(self) -> None:
        result = self._run_agents_once("all")
        insights = self._run_lab_insights_update()
        if result.get("status") != "PASS":
            messagebox.showwarning(
                "Ostrzezenie",
                "Nie wszystkie agenty odswiezyly sie poprawnie.\n"
                f"Status: {result.get('status', 'UNKNOWN')}\n"
                f"Szczegoly: {result.get('error', 'sprawdz outputs/operator/agent_refresh_last.json')}\n"
                f"Wnioski LAB: {insights.get('status', 'UNKNOWN')} ({insights.get('error', insights.get('reason', ''))})",
            )
            self._refresh_lab_insights_indicator()
            return
        runs = result.get("runs", [])
        ok_count = sum(1 for r in runs if str(r.get("status")).upper() == "PASS")
        messagebox.showinfo(
            "Odswiezanie agentow",
            "Odswiezono agentow: {0}/{1}\nWnioski LAB: {2}".format(
                ok_count,
                len(runs),
                str(insights.get("status", "UNKNOWN")).upper(),
            ),
        )
        self._refresh_lab_insights_indicator()

    def _run_lab_insights_update(self) -> dict:
        if not LAB_INSIGHTS_SCRIPT.exists():
            return {"status": "FAIL", "error": f"MISSING_SCRIPT: {LAB_INSIGHTS_SCRIPT}"}
        rc, out, err = self._run_command_blocking(
            [sys.executable, str(LAB_INSIGHTS_SCRIPT), "--root", str(WORKSPACE_ROOT)],
            timeout_sec=120,
        )
        payload: dict = {}
        raw = (out or "").strip()
        if raw:
            try:
                payload = json.loads(raw.splitlines()[-1])
            except Exception:
                payload = {"status": "FAIL", "error": "INVALID_JSON_FROM_LAB_INSIGHTS", "raw": raw[:4000]}
        if rc != 0 and not payload:
            payload = {"status": "FAIL", "error": f"LAB_INSIGHTS_RC_{rc}", "stderr": (err or "")[:4000]}
        if not payload:
            payload = {"status": "FAIL", "error": "LAB_INSIGHTS_EMPTY_OUTPUT"}
        return payload

    def _refresh_lab_insights_now(self) -> None:
        result = self._run_lab_insights_update()
        self._refresh_lab_insights_indicator()
        if str(result.get("status", "")).upper() == "PASS":
            messagebox.showinfo("Wnioski LAB", "Zaktualizowano wnioski z laboratorium.")
            return
        messagebox.showwarning(
            "Wnioski LAB",
            "Nie udalo sie zaktualizowac wnioskow LAB.\n"
            f"Status: {result.get('status', 'UNKNOWN')}\n"
            f"Szczegoly: {result.get('error', result.get('reason', 'UNKNOWN'))}",
        )

    def _open_lab_insights(self) -> None:
        if bool(getattr(self, "auto_refresh_var", None) and self.auto_refresh_var.get()):
            self._run_lab_insights_update()
        payload = _read_json_safe(LAB_INSIGHTS_POINTER_JSON) or {}
        body = _build_lab_insights_text(payload)
        self._show_text_window("Wnioski z laboratorium", body)
        self._mark_lab_insights_seen(payload)
        self._refresh_lab_insights_indicator()

    def _mark_lab_insights_seen(self, payload: dict) -> None:
        ts = str(payload.get("generated_at_utc", "")).strip()
        if not ts:
            return
        LAB_INSIGHTS_SEEN_PATH.parent.mkdir(parents=True, exist_ok=True)
        LAB_INSIGHTS_SEEN_PATH.write_text(
            json.dumps({"seen_generated_at_utc": ts, "updated_at_utc": datetime.now(timezone.utc).isoformat()}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _refresh_lab_insights_indicator(self) -> None:
        btn = getattr(self, "lab_insights_btn", None)
        if btn is None:
            return
        latest = _read_json_safe(LAB_INSIGHTS_POINTER_JSON) or {}
        seen = _read_json_safe(LAB_INSIGHTS_SEEN_PATH) or {}
        latest_ts = _parse_utc(str(latest.get("generated_at_utc", "")))
        seen_ts = _parse_utc(str(seen.get("seen_generated_at_utc", "")))
        has_new = bool(latest_ts and (seen_ts is None or latest_ts > seen_ts))
        if has_new:
            self._insights_blink_on = not bool(self._insights_blink_on)
            btn.configure(bg="#E0A01C" if self._insights_blink_on else "#3B3F48")
            return
        self._insights_blink_on = False
        btn.configure(bg="#3B3F48")

    def _run_agents_once(self, agent_key: str) -> dict:
        if not AGENT_REFRESH_SCRIPT.exists():
            return {
                "status": "FAIL",
                "error": f"MISSING_SCRIPT: {AGENT_REFRESH_SCRIPT}",
            }
        rc, out, err = self._run_command_blocking(
            [sys.executable, str(AGENT_REFRESH_SCRIPT), "--root", str(WORKSPACE_ROOT), "--agent", str(agent_key)],
            timeout_sec=150,
        )
        payload: dict = {}
        raw = (out or "").strip()
        if raw:
            try:
                payload = json.loads(raw.splitlines()[-1])
            except Exception:
                payload = {"status": "FAIL", "error": "INVALID_JSON_FROM_REFRESH", "raw": raw[:4000]}
        if rc != 0 and not payload:
            payload = {"status": "FAIL", "error": f"REFRESH_RC_{rc}", "stderr": (err or "")[:4000]}
        return payload

    def _open_agent_report(self, agent_key: str, label: str) -> None:
        if bool(getattr(self, "auto_refresh_var", None) and self.auto_refresh_var.get()):
            refresh = self._run_agents_once(agent_key)
            if str(refresh.get("status", "")).upper() not in {"PASS", "PARTIAL_FAIL"}:
                messagebox.showwarning(
                    "Ostrzezenie",
                    "Nie udalo sie odswiezyc danych agenta przed podgladem.\n"
                    f"Status: {refresh.get('status', 'UNKNOWN')}\n"
                    "Pokazuje ostatni dostepny raport.",
                )

        agent_dir = REPORTS_ROOT / agent_key
        if not agent_dir.exists():
            messagebox.showinfo("Brak danych", f"Brak katalogu raportow:\n{agent_dir}")
            return
        files = sorted(agent_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
        if not files:
            messagebox.showinfo("Brak danych", f"Brak raportow dla: {label}")
            return
        latest = files[0]

        payload = _read_json_safe(latest)
        if payload is None:
            messagebox.showerror("Blad", f"Nie udalo sie odczytac raportu:\n{latest}")
            return

        if agent_key == "agent_informacyjny":
            body = _build_ops_summary(payload, latest)
        elif agent_key == "agent_rozwoju_scalpingu":
            body = _build_rd_summary(payload, latest)
        elif agent_key == "agent_rekomendacyjny":
            body = _build_recommendation_summary(payload, latest)
        else:
            body = _build_guardian_summary(payload, latest)

        self._show_text_window(f"{label} - podsumowanie", body)

    def _open_retention_dashboard(self) -> None:
        body = _build_retention_dashboard()
        metrics = _retention_dashboard_metrics()
        self._show_retention_dashboard_window("Retencja danych - dashboard", body, metrics)

    def _show_text_window(self, title: str, body: str) -> None:
        top = tk.Toplevel(self)
        top.title(title)
        top.geometry("860x580")
        txt = scrolledtext.ScrolledText(top, wrap="word", font=("Consolas", 10))
        txt.pack(fill="both", expand=True)
        txt.insert("1.0", body)
        txt.configure(state="disabled")

    def _show_retention_dashboard_window(self, title: str, body: str, metrics: dict) -> None:
        top = tk.Toplevel(self)
        top.title(title)
        top.geometry("900x620")

        cards = tk.Frame(top, bg="#1E2430")
        cards.pack(fill="x", padx=10, pady=(10, 6))

        status = str(metrics.get("status", "UNKNOWN")).upper()
        removed = int(_safe_float(metrics.get("removed_lines_today", 0)))
        reclaimed_mb = float(_safe_float(metrics.get("reclaimed_mb_today", 0.0)))
        incident_pack = bool(metrics.get("incident_pack_today", False))

        card_defs = [
            ("Status retencji", status, _retention_status_color(status)),
            ("Usuniete rekordy dzis", str(removed), "#2F63C6"),
            ("Zwolnione miejsce dzis", f"{reclaimed_mb:.2f} MB", "#1F8D7E"),
            (
                "Paczka incydentowa",
                "TAK" if incident_pack else "NIE",
                "#C2871E" if incident_pack else "#2E9E45",
            ),
        ]

        for idx, (label, value, color) in enumerate(card_defs):
            card = tk.Frame(cards, bg=color, bd=1, relief="ridge")
            card.grid(row=0, column=idx, padx=6, pady=4, sticky="nsew")
            cards.grid_columnconfigure(idx, weight=1)
            tk.Label(card, text=label, bg=color, fg="white", font=("Segoe UI", 9, "bold")).pack(
                anchor="w", padx=8, pady=(6, 0)
            )
            tk.Label(card, text=value, bg=color, fg="white", font=("Segoe UI", 12, "bold")).pack(
                anchor="w", padx=8, pady=(0, 8)
            )

        txt = scrolledtext.ScrolledText(top, wrap="word", font=("Consolas", 10))
        txt.pack(fill="both", expand=True, padx=10, pady=(0, 10))
        txt.insert("1.0", body)
        txt.configure(state="disabled")

    def _refresh_status(self) -> None:
        self.system_status_var.set(f"System: {self._read_system_status()}")
        self.monitor_status_var.set(f"Monitor: {self._read_monitor_status()}")
        self.repair_status_var.set(f"Naprawa: {self._read_repair_status()}")
        self.policy_runtime_var.set(f"Policy runtime: {self._read_policy_runtime_retry_status()}")
        self.session_guard_var.set(f"Sesja MT5: {self._read_mt5_session_guard_status()}")
        self._refresh_lab_insights_indicator()
        self.after(5000, self._refresh_status)

    def _read_system_status(self) -> str:
        payload = _read_json_safe(SYSTEM_STATUS_PATH)
        if not payload:
            return "brak statusu"
        action = str(payload.get("action", "UNKNOWN")).upper()
        status = str(payload.get("status", "UNKNOWN")).upper()
        ts = str(payload.get("ts_utc", ""))
        return f"{status} ({action}, {ts})"

    def _read_monitor_status(self) -> str:
        payload = _read_json_safe(OPERATOR_STATUS_PATH)
        if not payload:
            return "wylaczony / brak statusu"
        state = str(payload.get("service_state", "UNKNOWN")).upper()
        ts = str(payload.get("ts_utc", ""))
        counts = payload.get("output_counts", {})
        reports = counts.get("reports_json", 0)
        alerts = counts.get("alerts_json", 0)
        return f"{state} ({ts}) raporty={reports} alerty={alerts}"

    def _read_repair_status(self) -> str:
        payload = _read_json_safe(REPAIR_STATUS_PATH)
        if not payload:
            return "brak uruchomienia"
        status = str(payload.get("status", "UNKNOWN")).upper()
        ts = str(payload.get("ts_utc", ""))
        return f"{status} ({ts})"

    def _read_policy_runtime_retry_status(self) -> str:
        snapshot = _read_policy_runtime_retry_snapshot(POLICY_RUNTIME_RETRY_LOOKBACK_MIN)
        status = str(snapshot.get("status", "UNKNOWN")).upper()
        if status != "OK":
            return str(snapshot.get("message", "brak danych"))
        count = int(snapshot.get("count_lookback", 0))
        top_reason = str(snapshot.get("top_reason", "NONE"))
        last_local = str(snapshot.get("last_local", ""))
        if count >= int(POLICY_RUNTIME_RETRY_ALERT_THRESHOLD):
            return f"ALERT retry_1h={count} top={top_reason} last={last_local}"
        return f"retry_1h={count} top={top_reason} last={last_local}"

    def _read_mt5_session_guard_status(self) -> str:
        payload = _read_json_safe(MT5_SESSION_GUARD_STATUS_PATH)
        if not payload:
            return "guard OFF / brak statusu"
        connected = str(payload.get("connected_state", "UNKNOWN")).upper()
        retries = int(payload.get("policy_retry_window", 0))
        reason = str(payload.get("last_restart_reason", "NONE"))
        allow = bool(payload.get("repairs_allowed", True))
        if not allow:
            return f"{connected} repairs=OFF retry_window={retries} last={reason}"
        return f"{connected} retry_window={retries} last={reason}"


def _read_json_safe(path: Path) -> dict | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None


def _parse_utc(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def _fmt_money(value: float | None) -> str:
    if value is None:
        return "UNKNOWN"
    return f"{value:.2f}"


def _find_mt5_data_dir() -> Path | None:
    appdata = os.environ.get("APPDATA", "")
    if not appdata:
        return None
    base = Path(appdata) / "MetaQuotes" / "Terminal"
    if not base.exists():
        return None
    candidates: list[tuple[float, Path]] = []
    for d in base.iterdir():
        if not d.is_dir():
            continue
        marker_mq5 = d / "MQL5" / "Experts" / "HybridAgent.mq5"
        marker_ex5 = d / "MQL5" / "Experts" / "HybridAgent.ex5"
        marker = marker_mq5 if marker_mq5.exists() else marker_ex5
        if marker.exists():
            try:
                ts = float(marker.stat().st_mtime)
            except Exception:
                ts = 0.0
            candidates.append((ts, d))
    if not candidates:
        return None
    candidates.sort(key=lambda x: x[0], reverse=True)
    return candidates[0][1]


def _read_policy_runtime_retry_snapshot(lookback_min: int) -> dict:
    mt5_dir = _find_mt5_data_dir()
    if mt5_dir is None:
        return {"status": "NO_MT5_DIR", "message": "brak katalogu MT5"}
    logs_dir = mt5_dir / "MQL5" / "Logs"
    if not logs_dir.exists():
        return {"status": "NO_LOG_DIR", "message": "brak MQL5/Logs"}

    now_local = datetime.now()
    window_start = now_local - timedelta(minutes=max(1, int(lookback_min)))
    date_keys = {now_local.strftime("%Y%m%d"), window_start.strftime("%Y%m%d")}
    files = [logs_dir / f"{k}.log" for k in sorted(date_keys)]
    line_re = re.compile(
        r"^(?P<date>\d{4}\.\d{2}\.\d{2})\s+(?P<time>\d{2}:\d{2}:\d{2}\.\d{3}).*?POLICY_RUNTIME_OPEN_RETRY reason=(?P<reason>.+)$"
    )

    count = 0
    reasons: Counter[str] = Counter()
    last_dt: datetime | None = None
    for f in files:
        if not f.exists():
            continue
        try:
            lines = f.read_text(encoding="utf-16le", errors="ignore").splitlines()
            if len(lines) <= 1:
                lines = f.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            continue
        for line in lines:
            m = line_re.search(str(line))
            if not m:
                continue
            try:
                ts = datetime.strptime(f"{m.group('date')} {m.group('time')}", "%Y.%m.%d %H:%M:%S.%f")
            except Exception:
                continue
            if ts < window_start:
                continue
            count += 1
            reason = str(m.group("reason")).strip()
            reasons[reason] += 1
            if last_dt is None or ts > last_dt:
                last_dt = ts

    top_reason = reasons.most_common(1)[0][0] if reasons else "NONE"
    return {
        "status": "OK",
        "count_lookback": int(count),
        "top_reason": top_reason,
        "last_local": last_dt.strftime("%Y-%m-%d %H:%M:%S") if last_dt else "NONE",
        "lookback_min": int(lookback_min),
    }


def _safe_float(value: object) -> float:
    try:
        return float(value)
    except Exception:
        return 0.0


def _zone_warsaw() -> timezone:
    if ZoneInfo is None:
        return datetime.now().astimezone().tzinfo or timezone.utc
    return ZoneInfo("Europe/Warsaw")


def _load_live_snapshot() -> dict:
    payload = _read_json_safe(LIVE_STATUS_PATH)
    if not payload:
        return {
            "phase": "UNKNOWN",
            "order_executed": 0,
            "buy": 0,
            "sell": 0,
            "retcode_10017": 0,
            "events": 0,
            "top_skip_reasons": "UNKNOWN",
            "source": str(LIVE_STATUS_PATH),
            "read_status": "MISSING",
        }
    totals = payload.get("totals", {})
    return {
        "phase": str(payload.get("phase", "UNKNOWN")),
        "order_executed": int(_safe_float(totals.get("order_executed", 0))),
        "buy": int(_safe_float(totals.get("buy", 0))),
        "sell": int(_safe_float(totals.get("sell", 0))),
        "retcode_10017": int(_safe_float(totals.get("retcode_10017", 0))),
        "events": int(_safe_float(totals.get("events", 0))),
        "top_skip_reasons": str(payload.get("top_skip_reasons", "UNKNOWN")),
        "source": str(LIVE_STATUS_PATH),
        "read_status": "OK",
    }


def _load_net_pnl_summary() -> dict:
    if not DB_PATH.exists():
        return {"status": "MISSING_DB"}

    try:
        con = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
        cur = con.cursor()
        cur.execute(
            "SELECT ny_date, symbol, profit, commission, swap FROM deals_log ORDER BY time ASC"
        )
        rows = cur.fetchall()
        con.close()
    except Exception as exc:
        return {"status": "ERROR", "error": str(exc)}

    if not rows:
        return {"status": "NO_ROWS"}

    by_date: dict[str, float] = defaultdict(float)
    symbol_today: dict[str, float] = defaultdict(float)
    trades_today = 0

    dates = sorted({str(r[0]) for r in rows if r and r[0]})
    current_date = dates[-1] if dates else None
    previous_date = dates[-2] if len(dates) >= 2 else None

    for ny_date, symbol, profit, commission, swap in rows:
        date_key = str(ny_date)
        net = _safe_float(profit) + _safe_float(commission) + _safe_float(swap)
        by_date[date_key] += net
        if current_date and date_key == current_date:
            symbol_today[str(symbol)] += net
            trades_today += 1

    top_gain = None
    top_loss = None
    if symbol_today:
        top_gain = max(symbol_today.items(), key=lambda x: x[1])
        top_loss = min(symbol_today.items(), key=lambda x: x[1])

    return {
        "status": "OK",
        "current_date": current_date,
        "previous_date": previous_date,
        "current_net": by_date.get(current_date, 0.0) if current_date else None,
        "previous_net": by_date.get(previous_date, 0.0) if previous_date else None,
        "trades_today": trades_today,
        "top_gain_symbol": top_gain[0] if top_gain else "UNKNOWN",
        "top_gain_value": top_gain[1] if top_gain else None,
        "top_loss_symbol": top_loss[0] if top_loss else "UNKNOWN",
        "top_loss_value": top_loss[1] if top_loss else None,
    }


def _load_night_activity() -> dict:
    tz = _zone_warsaw()
    now_local = datetime.now(tz)
    today_local = now_local.date()

    start_local = datetime(today_local.year, today_local.month, today_local.day, 20, 0, 0, tzinfo=tz) - timedelta(days=1)
    end_default = datetime(today_local.year, today_local.month, today_local.day, 8, 0, 0, tzinfo=tz)
    end_local = min(now_local, end_default)

    report_dir = REPORTS_ROOT / "agent_informacyjny"
    report_times: list[datetime] = []
    if report_dir.exists():
        for path in report_dir.glob("*.json"):
            payload = _read_json_safe(path)
            if not payload:
                continue
            ts = _parse_utc(str(payload.get("generated_at_utc", "")))
            if ts is None:
                content = payload.get("content", {})
                if isinstance(content, dict):
                    ts = _parse_utc(str(content.get("generated_at_utc", "")))
            if ts is None:
                continue
            ts_local = ts.astimezone(tz)
            if start_local <= ts_local <= end_local:
                report_times.append(ts_local)

    report_times.sort()
    max_gap_min = None
    if len(report_times) >= 2:
        gaps = [
            (report_times[i] - report_times[i - 1]).total_seconds() / 60.0
            for i in range(1, len(report_times))
        ]
        max_gap_min = max(gaps)

    alerts_counter: Counter[str] = Counter()
    for root in (ALERTS_ROOT, TICKETS_ROOT):
        if not root.exists():
            continue
        for path in root.rglob("*.json"):
            payload = _read_json_safe(path)
            if not payload:
                continue
            ts = _parse_utc(str(payload.get("generated_at_utc", "")))
            if ts is None:
                ts = _parse_utc(str(payload.get("created_at_utc", "")))
            if ts is None:
                continue
            ts_local = ts.astimezone(tz)
            if start_local <= ts_local <= end_local:
                issue = str(payload.get("issue_type") or payload.get("type") or "UNKNOWN")
                alerts_counter[issue] += 1

    return {
        "window_start": start_local.isoformat(),
        "window_end": end_local.isoformat(),
        "report_count": len(report_times),
        "max_report_gap_min": max_gap_min,
        "night_continuity": "OK" if (len(report_times) > 0 and (max_gap_min is None or max_gap_min <= 15.0)) else "PARTIAL",
        "event_breakdown": dict(alerts_counter),
    }


def _build_ops_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    live_snapshot = _load_live_snapshot()
    pnl = _load_net_pnl_summary()
    night = _load_night_activity()

    preflight = content.get("preflight_status", {})
    preflight_status = str(preflight.get("read_status", "UNKNOWN")) if isinstance(preflight, dict) else "UNKNOWN"
    drift = content.get("drift_checks", {}) if isinstance(content, dict) else {}
    drift_status = str(drift.get("status", "UNKNOWN")) if isinstance(drift, dict) else "UNKNOWN"

    lines = [
        "AGENT INFORMACYJNY - PODSUMOWANIE OPERACYJNE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Raport generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        "",
        "[1] STAN SYSTEMU",
        f"- Trade monitor phase: {live_snapshot['phase']}",
        f"- Wykonane zlecenia (order_executed): {live_snapshot['order_executed']}",
        f"- Buy/Sell sygnaly: {live_snapshot['buy']} / {live_snapshot['sell']}",
        f"- retcode_10017: {live_snapshot['retcode_10017']}",
        f"- Suma eventow monitora: {live_snapshot['events']}",
        f"- Top skip reasons: {live_snapshot['top_skip_reasons']}",
        f"- Preflight status: {preflight_status}",
        f"- Drift status: {drift_status}",
        "",
        "[2] WYNIK NETTO (zrealizowane deal'e, deals_log)",
    ]

    if pnl.get("status") == "OK":
        lines.extend(
            [
                f"- Dzien poprzedni ({pnl['previous_date']}): {_fmt_money(pnl['previous_net'])}",
                f"- Biezacy dzien ({pnl['current_date']}): {_fmt_money(pnl['current_net'])}",
                f"- Liczba deali biezacy dzien: {pnl['trades_today']}",
                f"- Najwiekszy zysk symbol: {pnl['top_gain_symbol']} ({_fmt_money(pnl['top_gain_value'])})",
                f"- Najwieksza strata symbol: {pnl['top_loss_symbol']} ({_fmt_money(pnl['top_loss_value'])})",
            ]
        )
    else:
        lines.append(f"- Dane PnL niedostepne: {pnl.get('status', 'UNKNOWN')} ({pnl.get('error', '')})")

    lines.extend(
        [
            "",
            "[3] NOCNY MONITORING (Warsaw)",
            f"- Okno: {night['window_start']} -> {night['window_end']}",
            f"- Liczba raportow agenta informacyjnego: {night['report_count']}",
            f"- Najwieksza przerwa miedzy raportami [min]: {_fmt_money(night['max_report_gap_min']) if night['max_report_gap_min'] is not None else 'N/A'}",
            f"- Ciaglosc pracy nocnej: {night['night_continuity']}",
        ]
    )

    if night["event_breakdown"]:
        lines.append("- Zdarzenia alert/ticket w nocy:")
        for key, cnt in sorted(night["event_breakdown"].items(), key=lambda x: (-x[1], x[0])):
            lines.append(f"  * {key}: {cnt}")
    else:
        lines.append("- Zdarzenia alert/ticket w nocy: brak")

    lines.extend(
        [
            "",
            "[4] UWAGA",
            "- Dane pochodza tylko z persisted artifacts/DB (zgodnie z read-only).",
            "- Jesli jakies pole ma UNKNOWN, trzeba uzupelnic provider telemetry w observer layer.",
        ]
    )

    return "\n".join(lines)


def _build_rd_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    metrics = content.get("metrics", {}) if isinstance(content.get("metrics"), dict) else {}
    diagnosis = content.get("diagnosis", {}) if isinstance(content.get("diagnosis"), dict) else {}
    hypotheses = content.get("hypotheses", []) if isinstance(content.get("hypotheses"), list) else []
    window = content.get("analysis_window_utc", {}) if isinstance(content.get("analysis_window_utc"), dict) else {}
    event_count = content.get("event_count", "UNKNOWN")

    lines = [
        "AGENT ROZWOJU SCALPINGU - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        "",
        "[1] CO WIDZE",
        f"- Okno analizy: {window.get('start', 'UNKNOWN')} -> {window.get('end', 'UNKNOWN')}",
        f"- Przeanalizowane zdarzenia: {event_count}",
    ]

    pnl_by_symbol = metrics.get("pnl_net_by_symbol", {})
    if isinstance(pnl_by_symbol, dict) and pnl_by_symbol:
        top_gain = max(pnl_by_symbol.items(), key=lambda x: _safe_float(x[1]))
        top_loss = min(pnl_by_symbol.items(), key=lambda x: _safe_float(x[1]))
        lines.append(f"- Najmocniejszy symbol netto: {top_gain[0]} ({_fmt_money(_safe_float(top_gain[1]))})")
        lines.append(f"- Najslabszy symbol netto: {top_loss[0]} ({_fmt_money(_safe_float(top_loss[1]))})")
    else:
        lines.append("- Brak pelnych danych netto po symbolach w tym oknie.")

    block_dist = metrics.get("block_reason_distribution", {})
    if isinstance(block_dist, dict) and block_dist:
        top_block = max(block_dist.items(), key=lambda x: _safe_float(x[1]))
        lines.append(f"- Najczestszy powod blokady wejsc: {top_block[0]} ({int(_safe_float(top_block[1]))}x)")
    else:
        lines.append("- Brak dominujacego powodu blokady (za malo danych lub brak blokad).")

    signal_note = _translate_tech_text(str(diagnosis.get("signal_layer_notes", "Brak opisu.")))
    regime_note = _translate_tech_text(str(diagnosis.get("regime_layer_notes", "Brak opisu.")))
    execution_layer = diagnosis.get("execution_layer", {})

    lines.extend(
        [
            "",
            "[2] CO TO ZNACZY",
            f"- Warstwa sygnalowa: {signal_note}",
            f"- Warstwa wykonawcza: {_describe_execution_layer(execution_layer)}",
            f"- Warstwa rezimu: {regime_note}",
        ]
    )

    lines.append("")
    lines.append("[3] CO PROPONUJE")
    if hypotheses:
        for idx, hyp in enumerate(hypotheses[:5], start=1):
            statement = _translate_tech_text(str(hyp.get("statement", "Brak opisu hipotezy")))
            hyp_type = _translate_hypothesis_type(str(hyp.get("type", "UNKNOWN")))
            lines.append(
                f"{idx}. {statement} "
                f"(typ: {hyp_type})"
            )
    else:
        lines.append(
            "- Na teraz proponuje kontynuowac zbieranie danych; "
            "bez stabilnej probki nie warto zmieniac polityki."
        )

    lines.extend(
        [
            "",
            "[4] CO ZROBI SYSTEM DALEJ",
            "- Agent zapisze kolejny raport po nastepnym cyklu analizy.",
            "- Jesli ryzyko wzrosnie, eskalacje ticketu do Codex wykona Straznik Spojnosci.",
            "",
            "[5] SLOWNIK POJEC",
            "- 'wynik netto' = zysk/strata po kosztach (prowizje, swap, oplaty).",
            "- 'odrzucone wejscie' = broker lub polityka nie pozwolily otworzyc pozycji.",
            "- 'rezim rynku' = aktualny typ warunkow rynku (np. spokojny, zmienny).",
        ]
    )

    return "\n".join(lines)


def _build_recommendation_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    recommendations = content.get("recommendations", []) if isinstance(content.get("recommendations"), list) else []

    lines = [
        "AGENT REKOMENDACYJNY - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        "",
        "[1] CO WIDZE",
        f"- Liczba rekomendacji: {len(recommendations)}",
        f"- Liczba raportow zrodlowych: {content.get('input_report_counts', {})}",
    ]

    lines.append("")
    lines.append("[2] CO TO ZNACZY")
    if not recommendations:
        lines.append("- W tej chwili brak nowej rekomendacji do wdrozenia.")
    else:
        high_count = sum(1 for r in recommendations if str(r.get("priority", "")).upper() == "HIGH")
        med_count = sum(1 for r in recommendations if str(r.get("priority", "")).upper() == "MED")
        lines.append(f"- Rekomendacje HIGH: {high_count}, MED: {med_count}.")
        lines.append("- To jest lista priorytetow do przegladu, nie automatyczne zmiany.")

    lines.append("")
    lines.append("[3] CO PROPONUJE")
    for idx, rec in enumerate(recommendations[:5], start=1):
        problem = _translate_tech_text(str(rec.get("problem", "UNKNOWN")))
        evidence = _translate_tech_text(str(rec.get("evidence", "UNKNOWN")))
        impact = _translate_tech_text(str(rec.get("impact", "UNKNOWN")))
        risk = _translate_tech_text(str(rec.get("risk", "UNKNOWN")))
        verify = _translate_tech_text(str(rec.get("verify_after_change", "UNKNOWN")))
        lines.append(
            f"{idx}. [{rec.get('priority', 'UNK')}] {problem}\n"
            f"   Dlaczego: {evidence}\n"
            f"   Wplyw: {impact} | Ryzyko: {risk}\n"
            f"   Jak sprawdzic: {verify}"
        )
    if not recommendations:
        lines.append("- Kontynuowac obserwacje i czekac na mocniejsze sygnaly z raportow.")

    lines.extend(
        [
            "",
            "[4] CO ZROBI SYSTEM DALEJ",
            "- Agent zapisze kolejny raport rekomendacji po nastepnym cyklu.",
            "- Ewentualny ticket do Codex wystawia tylko Straznik Spojnosci (guardian-only).",
        ]
    )

    return "\n".join(lines)


def _build_guardian_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    risk_summary = content.get("risk_summary", {}) if isinstance(content.get("risk_summary"), dict) else {}
    findings = content.get("findings", {}) if isinstance(content.get("findings"), dict) else {}
    risk_status = str(risk_summary.get("status", "UNKNOWN"))
    high_findings = int(_safe_float(risk_summary.get("high_findings", 0)))
    medium_findings = int(_safe_float(risk_summary.get("medium_findings", 0)))

    lines = [
        "STRAZNIK SPOJNOSCI - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        "",
        "[1] CO WIDZE",
        f"- Status ryzyka: {risk_status}",
        f"- Znalezione problemy HIGH/MED: {high_findings}/{medium_findings}",
    ]

    contracts = findings.get("contracts", {}) if isinstance(findings.get("contracts"), dict) else {}
    contract_issues = contracts.get("issues", []) if isinstance(contracts.get("issues"), list) else []
    lines.append(f"- Problemy kontraktow danych: {len(contract_issues)}")

    freshness = findings.get("artifact_freshness", {}) if isinstance(findings.get("artifact_freshness"), dict) else {}
    stale_count = int(_safe_float(freshness.get("stale_count", 0)))
    lines.append(f"- Nieaktualne artefakty: {stale_count}")

    stale_paths: list[str] = []
    findings_list = freshness.get("findings", []) if isinstance(freshness.get("findings"), list) else []
    for item in findings_list:
        if isinstance(item, dict) and str(item.get("status", "")).upper() != "OK":
            stale_paths.append(str(item.get("path", "UNKNOWN")))

    lines.append("")
    lines.append("[2] CO TO ZNACZY")
    if risk_status.upper() == "ALERT":
        lines.append("- Wykryto stan alarmowy. Potrzebny pilny audyt i dzialanie naprawcze.")
    elif risk_status.upper() == "WARN":
        lines.append("- Sa niespojnosci sredniej wagi. System dziala, ale wymaga korekt.")
    else:
        lines.append("- Nie widze krytycznych niespojnosci na ten moment.")

    if stale_paths:
        lines.append("- Najwazniejsze stale artefakty:")
        for p in stale_paths[:5]:
            lines.append(f"  * {p}")
    else:
        lines.append("- Artefakty krytyczne sa swieze lub bez odchylen.")

    lines.append("")
    lines.append("[3] CO PROPONUJE")
    if contract_issues:
        lines.append("- Najpierw naprawic problemy kontraktow danych, bo utrudniaja wiarygodna diagnoze.")
    if stale_count > 0:
        lines.append("- Odswiezyc stale artefakty i ponowic skan spojnosci.")
    if not contract_issues and stale_count == 0:
        lines.append("- Utrzymac monitoring i przegladac raport co 30-60 min.")

    lines.extend(
        [
            "",
            "[4] CO ZROBI SYSTEM DALEJ",
            "- Straznik wykona kolejny skan w nastepnym cyklu.",
            "- Gdy status przejdzie na ALERT, przygotuje ticket do Codex (guardian-only).",
        ]
    )

    return "\n".join(lines)


def _translate_hypothesis_type(value: str) -> str:
    mapping = {
        "DATA_COVERAGE": "pokrycie danych",
        "EXECUTION_QUALITY": "jakosc wykonania",
        "RISK_REGIME": "ryzyko i rezim",
    }
    key = (value or "").strip().upper()
    return mapping.get(key, key or "UNKNOWN")


def _describe_execution_layer(execution_layer: object) -> str:
    if not isinstance(execution_layer, dict):
        return _translate_tech_text(str(execution_layer))
    rejects = execution_layer.get("symbols_with_rejects", [])
    reasons = execution_layer.get("reject_block_reasons", {})
    reject_count = len(rejects) if isinstance(rejects, list) else 0
    if reject_count == 0:
        return "Nie widze odrzuconych wejsc w tym oknie analizy."
    reason_desc = "brak danych o powodach"
    if isinstance(reasons, dict) and reasons:
        top_reason, top_count = max(reasons.items(), key=lambda x: _safe_float(x[1]))
        reason_desc = f"najczestszy powod: {top_reason} ({int(_safe_float(top_count))}x)"
    return (
        f"Widze odrzucone wejscia dla {reject_count} symboli; {reason_desc}."
    )


def _translate_tech_text(text: str) -> str:
    if not text:
        return "Brak opisu."
    replacements = [
        (
            "No strategy inference in draft; signal-vs-regime analysis requires richer labeled events.",
            "Agent nie ocenia jeszcze skutecznosci strategii; potrzeba wiecej oznaczonych zdarzen, aby rozdzielic sygnal od warunkow rynku.",
        ),
        (
            "Regime impact marked UNKNOWN in draft until direct regime tags are mapped.",
            "Wplyw warunkow rynku jest jeszcze nierozpoznany; trzeba dopiac bezposrednie oznaczenia rezimu rynku.",
        ),
        (
            "Persisted TRADE_CLOSED with pnl_net is sparse; improve reporting coverage before deeper R&D claims.",
            "W bazie jest za malo zamknietych transakcji z wynikiem netto; najpierw trzeba rozszerzyc pokrycie raportowania.",
        ),
        ("Both report streams present", "Oba strumienie raportow sa dostepne."),
        ("Better prioritization", "Lepsze ustawienie priorytetow zmian."),
        ("LOW", "niskie"),
        ("MED", "srednie"),
        ("HIGH", "wysokie"),
    ]
    out = text
    for src, dst in replacements:
        out = out.replace(src, dst)
    return out


def _build_lab_insights_text(payload: dict) -> str:
    if LAB_INSIGHTS_POINTER_TXT.exists():
        try:
            return LAB_INSIGHTS_POINTER_TXT.read_text(encoding="utf-8")
        except Exception:
            pass
    if not payload:
        return (
            "WNIOSEK Z LABORATORIUM\n"
            "Brak danych. Kliknij 'AKTUALIZUJ WNIOSKI LAB' i sprawdz ponownie."
        )
    snapshot = payload.get("snapshot", {}) if isinstance(payload.get("snapshot"), dict) else {}
    lines = [
        "WNIOSEK Z LABORATORIUM",
        "=" * 72,
        f"Generated UTC: {payload.get('generated_at_utc', 'UNKNOWN')}",
        f"Status: {payload.get('status', 'UNKNOWN')}",
        "",
        "[1] STAN",
        f"- Scheduler: {snapshot.get('scheduler_status', 'UNKNOWN')} ({snapshot.get('scheduler_reason', 'UNKNOWN')})",
        f"- Jakosc ingestu: {snapshot.get('ingest_quality_grade', 'UNKNOWN')}",
        f"- Wiersze pobrane/wstawione: {snapshot.get('ingest_rows_fetched_total', 0)} / {snapshot.get('ingest_rows_inserted_total', 0)}",
        "",
        "[2] UCZENIE",
        f"- Pary gotowe do shadow: {snapshot.get('pairs_ready_for_shadow', 0)} / {snapshot.get('pairs_total', 0)}",
        f"- Explore trades: {snapshot.get('explore_total_trades', 0)}",
        "",
        "[3] REKOMENDACJA",
        f"- {payload.get('recommendation', 'BRAK')}",
        "",
        f"Pelny raport: {payload.get('report_path', 'UNKNOWN')}",
    ]
    return "\n".join(lines)


def _latest_json(path: Path) -> Path | None:
    if not path.exists():
        return None
    files = [p for p in path.glob("*.json") if p.is_file()]
    if not files:
        return None
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0]


def _retention_status_color(status: str) -> str:
    key = str(status or "").strip().upper()
    if key in {"PASS", "OK"}:
        return "#2E9E45"
    if key in {"SKIP_ALREADY_RUN_TODAY", "WARN", "PARTIAL_FAIL"}:
        return "#C2871E"
    if key in {"FAIL", "ERROR", "UNKNOWN"}:
        return "#C3382A"
    return "#4D5A6A"


def _retention_dashboard_metrics() -> dict:
    policy = _read_json_safe(RETENTION_POLICY_PATH) or {}
    outputs = policy.get("outputs", {}) if isinstance(policy.get("outputs"), dict) else {}
    state_file_rel = str(outputs.get("daily_state_file", "RUN/retention_cycle_state.json"))
    state_file = WORKSPACE_ROOT / state_file_rel
    state = _read_json_safe(state_file) or {}

    latest_daily_path = _latest_json(RETENTION_DAILY_ROOT)
    latest_daily = _read_json_safe(latest_daily_path) if latest_daily_path else None

    status = str(state.get("last_status", "UNKNOWN")).upper()
    last_run_ts = str(state.get("last_run_ts_utc", "UNKNOWN"))
    removed_lines = 0
    reclaimed_mb = 0.0
    incident_pack = False
    if latest_daily and isinstance(latest_daily.get("runs"), list) and latest_daily["runs"]:
        run = latest_daily["runs"][-1]
        if isinstance(run, dict):
            summary = run.get("summary", {}) if isinstance(run.get("summary"), dict) else {}
            removed_lines = int(_safe_float(summary.get("lines_removed", 0)))
            reclaimed_mb = int(_safe_float(summary.get("bytes_reclaimed_estimate", 0))) / (1024.0 * 1024.0)
            incident_pack = bool(str(run.get("incident_pack_path", "")).strip())
            run_ts = str(run.get("ts_utc", "")).strip()
            if run_ts:
                last_run_ts = run_ts
    return {
        "status": status,
        "last_run_ts_utc": last_run_ts,
        "removed_lines_today": removed_lines,
        "reclaimed_mb_today": reclaimed_mb,
        "incident_pack_today": incident_pack,
    }


def _build_retention_dashboard() -> str:
    policy = _read_json_safe(RETENTION_POLICY_PATH) or {}
    tx = policy.get("transactional", {}) if isinstance(policy.get("transactional"), dict) else {}
    mt = policy.get("maintenance", {}) if isinstance(policy.get("maintenance"), dict) else {}
    outputs = policy.get("outputs", {}) if isinstance(policy.get("outputs"), dict) else {}
    state_file_rel = str(outputs.get("daily_state_file", "RUN/retention_cycle_state.json"))
    state_file = WORKSPACE_ROOT / state_file_rel
    state = _read_json_safe(state_file) or {}

    latest_daily_path = _latest_json(RETENTION_DAILY_ROOT)
    latest_run_path = _latest_json(RETENTION_RUNS_ROOT)
    latest_daily = _read_json_safe(latest_daily_path) if latest_daily_path else None
    latest_run = _read_json_safe(latest_run_path) if latest_run_path else None

    lines = [
        "DASHBOARD RETENCJI DANYCH",
        "=" * 72,
        "",
        "[1] CO ROBI RETENCJA",
        "- Porzadkuje dane, zeby nie bylo szumu informacyjnego.",
        "- Trzyma dlugo dane transakcyjne (do analizy strategii).",
        "- Krocej trzyma dane techniczne/serwisowe (do napraw i diagnostyki).",
        "",
        "[2] AKTYWNE ZASADY (UTC)",
        f"- Dane transakcyjne: {tx.get('execution_telemetry_days', 'UNKNOWN')} dni",
        f"- Dziennik incydentow tradingowych: {tx.get('incident_journal_days', 'UNKNOWN')} dni",
        f"- Dane techniczne (audit trail): {mt.get('audit_trail_days', 'UNKNOWN')} dni",
        f"- Paczki anomalii: {mt.get('keep_anomaly_packs_days', 'UNKNOWN')} dni",
        "",
        "[3] OSTATNI CYKL",
        f"- Czas: {state.get('last_run_ts_utc', 'UNKNOWN')}",
        f"- Status: {state.get('last_status', 'UNKNOWN')}",
    ]

    if latest_daily and isinstance(latest_daily.get("runs"), list) and latest_daily["runs"]:
        run = latest_daily["runs"][-1]
        summary = run.get("summary", {}) if isinstance(run.get("summary"), dict) else {}
        targets = run.get("targets", []) if isinstance(run.get("targets"), list) else []
        reclaimed_bytes = int(_safe_float(summary.get("bytes_reclaimed_estimate", 0)))
        reclaimed_mb = reclaimed_bytes / (1024.0 * 1024.0)
        lines.extend(
            [
                "",
                "[4] CO ZOSTALO ZROBIONE DZISIAJ",
                f"- Ostatni run: {run.get('ts_utc', 'UNKNOWN')}",
                f"- Usuniete rekordy: {int(_safe_float(summary.get('lines_removed', 0)))}",
                f"- Usuniete rekordy anomalii: {int(_safe_float(summary.get('lines_removed_anomaly', 0)))}",
                f"- Zwolnione miejsce: {reclaimed_mb:.2f} MB",
            ]
        )
        for row in targets:
            if not isinstance(row, dict):
                continue
            removed = int(_safe_float(row.get("lines_removed", 0)))
            keep_days = row.get("keep_days", "UNKNOWN")
            if removed <= 0:
                continue
            kind = str(row.get("kind", "UNKNOWN")).upper()
            if kind == "TRANSACTIONAL":
                lines.append(f"  * Dane transakcyjne: usunieto {removed} rekordow starszych niz {keep_days} dni.")
            elif kind == "MAINTENANCE":
                lines.append(f"  * Dane techniczne: usunieto {removed} rekordow starszych niz {keep_days} dni.")
            else:
                lines.append(f"  * {kind}: usunieto {removed} rekordow starszych niz {keep_days} dni.")
        incident_pack = str(run.get("incident_pack_path", "")).strip()
        lines.append(
            "- Paczka incydentowa: "
            + ("utworzona (anomalia zachowana do audytu)." if incident_pack else "brak (nie bylo anomalii do zachowania).")
        )
    else:
        lines.extend(
            [
                "",
                "[4] CO ZOSTALO ZROBIONE DZISIAJ",
                "- Brak raportu dziennego retencji lub brak runow.",
            ]
        )

    seven_day_removed_lines = 0
    seven_day_reclaimed = 0
    seven_day_runs = 0
    if RETENTION_DAILY_ROOT.exists():
        daily_files = sorted(
            [p for p in RETENTION_DAILY_ROOT.glob("retention_daily_*.json") if p.is_file()],
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )[:7]
        for dpath in daily_files:
            obj = _read_json_safe(dpath)
            if not obj:
                continue
            runs = obj.get("runs", [])
            if not isinstance(runs, list):
                continue
            for run in runs:
                if not isinstance(run, dict):
                    continue
                seven_day_runs += 1
                sm = run.get("summary", {})
                if not isinstance(sm, dict):
                    continue
                seven_day_removed_lines += int(_safe_float(sm.get("lines_removed", 0)))
                seven_day_reclaimed += int(_safe_float(sm.get("bytes_reclaimed_estimate", 0)))

    lines.extend(
        [
            "",
            "[5] OSTATNIE 7 DNI",
            f"- Liczba cykli retencji: {seven_day_runs}",
            f"- Suma usunietych rekordow: {seven_day_removed_lines}",
            f"- Suma zwolnionego miejsca: {seven_day_reclaimed / (1024.0 * 1024.0):.2f} MB",
        ]
    )

    if latest_run and isinstance(latest_run.get("report_retention_cleanup"), dict):
        cln = latest_run["report_retention_cleanup"]
        lines.extend(
            [
                "",
                "[6] SPRZATANIE STARYCH RAPORTOW RETENCJI",
                f"- Usuniete raporty cykli: {cln.get('removed_run_reports', 'UNKNOWN')}",
                f"- Usuniete raporty dzienne: {cln.get('removed_daily_reports', 'UNKNOWN')}",
                f"- Usuniete stare paczki incydentowe: {cln.get('removed_incident_packs', 'UNKNOWN')}",
            ]
        )
    else:
        lines.extend(
            [
                "",
                "[6] SPRZATANIE STARYCH RAPORTOW RETENCJI",
                "- Brak danych o ostatnim cleanup raportow retencji.",
            ]
        )

    incident_count = 0
    if RETENTION_INCIDENTS_ROOT.exists():
        incident_count = sum(1 for _ in RETENTION_INCIDENTS_ROOT.glob("incident_pack_*.json"))
    lines.extend(
        [
            "",
            "[7] STAN DANYCH RETENCYJNYCH",
            f"- Raporty dzienne: {sum(1 for _ in RETENTION_DAILY_ROOT.glob('*.json')) if RETENTION_DAILY_ROOT.exists() else 0}",
            f"- Raporty cykli: {sum(1 for _ in RETENTION_RUNS_ROOT.glob('*.json')) if RETENTION_RUNS_ROOT.exists() else 0}",
            f"- Paczki incydentowe: {incident_count}",
            "",
            "[8] DLACZEGO TO JEST WAZNE",
            "- Dashboard jest oparty o persisted reports z retencji (read-only).",
            "- To nie zmienia strategii tradingowej.",
            "- Cel: mniej szumu, szybsza analiza i lepsza jakosc danych do decyzji.",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    panel = OperatorPanel()
    panel.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
