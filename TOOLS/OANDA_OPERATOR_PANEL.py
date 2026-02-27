from __future__ import annotations

import json
import sqlite3
import subprocess
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
DB_PATH = WORKSPACE_ROOT / "DB" / "decision_events.sqlite"

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

        tk.Label(status_frame, textvariable=self.system_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.monitor_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")
        tk.Label(status_frame, textvariable=self.repair_status_var, fg="#D6E2F0", bg="#1E2430", anchor="w").pack(fill="x")

    def _run_command(self, command: list[str], description: str) -> None:
        try:
            subprocess.Popen(command, cwd=str(WORKSPACE_ROOT))
        except Exception as exc:
            messagebox.showerror("Blad", f"{description}\n\n{exc}")

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

    def _open_agent_report(self, agent_key: str, label: str) -> None:
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

        top = tk.Toplevel(self)
        top.title(f"{label} - podsumowanie")
        top.geometry("840x560")
        txt = scrolledtext.ScrolledText(top, wrap="word", font=("Consolas", 10))
        txt.pack(fill="both", expand=True)
        txt.insert("1.0", body)
        txt.configure(state="disabled")

    def _refresh_status(self) -> None:
        self.system_status_var.set(f"System: {self._read_system_status()}")
        self.monitor_status_var.set(f"Monitor: {self._read_monitor_status()}")
        self.repair_status_var.set(f"Naprawa: {self._read_repair_status()}")
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

    lines = [
        "AGENT ROZWOJU SCALPINGU - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        f"Event count: {content.get('event_count', 'UNKNOWN')}",
        f"Diagnoza: {diagnosis}",
        f"Liczba hipotez: {len(hypotheses)}",
    ]

    if isinstance(metrics.get("pnl_net_by_symbol"), dict):
        top = sorted(metrics["pnl_net_by_symbol"].items(), key=lambda x: x[1], reverse=True)[:5]
        lines.append("Top symbole wg pnl_net_by_symbol:")
        for symbol, val in top:
            lines.append(f"- {symbol}: {_fmt_money(_safe_float(val))}")

    return "\n".join(lines)


def _build_recommendation_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    recommendations = content.get("recommendations", []) if isinstance(content.get("recommendations"), list) else []

    lines = [
        "AGENT REKOMENDACYJNY - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        f"Liczba rekomendacji: {len(recommendations)}",
    ]
    for idx, rec in enumerate(recommendations[:5], start=1):
        lines.append(
            f"{idx}. [{rec.get('priority', 'UNK')}] {rec.get('problem', 'UNKNOWN')} | requires_codex={rec.get('requires_codex', 'UNKNOWN')}"
        )
    if not recommendations:
        lines.append("Brak rekomendacji w ostatnim raporcie.")
    return "\n".join(lines)


def _build_guardian_summary(payload: dict, latest_path: Path) -> str:
    content = payload.get("content", {}) if isinstance(payload.get("content"), dict) else {}
    risk_summary = content.get("risk_summary", {}) if isinstance(content.get("risk_summary"), dict) else {}
    findings = content.get("findings", {}) if isinstance(content.get("findings"), dict) else {}

    lines = [
        "STRAZNIK SPOJNOSCI - PODSUMOWANIE",
        "=" * 72,
        f"Raport plik: {latest_path}",
        f"Generated_at_utc: {payload.get('generated_at_utc', 'UNKNOWN')}",
        f"Risk status: {risk_summary.get('status', 'UNKNOWN')}",
        f"Risk score: {risk_summary.get('risk_score', 'UNKNOWN')}",
    ]

    contracts = findings.get("contracts", {}) if isinstance(findings.get("contracts"), dict) else {}
    contract_issues = contracts.get("issues", []) if isinstance(contracts.get("issues"), list) else []
    lines.append(f"Contract issues: {len(contract_issues)}")

    freshness = findings.get("artifact_freshness", {}) if isinstance(findings.get("artifact_freshness"), dict) else {}
    stale = freshness.get("stale_or_missing", []) if isinstance(freshness.get("stale_or_missing"), list) else []
    lines.append(f"Stale/missing artifacts: {len(stale)}")

    return "\n".join(lines)


def main() -> int:
    panel = OperatorPanel()
    panel.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
