from __future__ import annotations

import json
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import messagebox, scrolledtext


WORKSPACE_ROOT = Path(r"C:\OANDA_MT5_SYSTEM")
OBS_ROOT = WORKSPACE_ROOT / "OBSERVERS_IMPLEMENTATION_CANDIDATE"
REPORTS_ROOT = OBS_ROOT / "outputs" / "reports"
OPERATOR_STATUS_PATH = OBS_ROOT / "outputs" / "operator" / "operator_runtime_status.json"
SYSTEM_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "system_control_last.json"
REPAIR_STATUS_PATH = WORKSPACE_ROOT / "RUN" / "codex_repair_last.json"

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
        try:
            payload = json.loads(latest.read_text(encoding="utf-8"))
            body = json.dumps(payload, ensure_ascii=False, indent=2)
        except Exception as exc:
            body = f"Nie udalo sie odczytac raportu:\n{latest}\n\n{exc}"

        top = tk.Toplevel(self)
        top.title(f"{label} - ostatni raport")
        top.geometry("760x520")
        txt = scrolledtext.ScrolledText(top, wrap="word", font=("Consolas", 10))
        txt.pack(fill="both", expand=True)
        txt.insert("1.0", f"Plik: {latest}\n\n{body}")
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
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def main() -> int:
    panel = OperatorPanel()
    panel.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
