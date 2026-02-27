from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


WORKSPACE_ROOT = Path(r"C:\OANDA_MT5_SYSTEM")
OBS_ROOT = WORKSPACE_ROOT / "OBSERVERS_IMPLEMENTATION_CANDIDATE"
STATUS_PATH = OBS_ROOT / "outputs" / "operator" / "operator_runtime_status.json"


def clear_screen() -> None:
    if sys.platform.startswith("win"):
        __import__("os").system("cls")
    else:
        __import__("os").system("clear")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def format_status(status: dict[str, Any] | None) -> str:
    lines: list[str] = []
    lines.append("=== OANDA OBSERVERS OPERATOR CONSOLE ===")
    lines.append(f"now_utc: {utc_now()}")
    lines.append(f"status_path: {STATUS_PATH}")
    lines.append("")
    if not status:
        lines.append("service_state: NOT_AVAILABLE")
        lines.append("reason: status file missing or unreadable")
        return "\n".join(lines)

    lines.append(f"service_state: {status.get('service_state', 'UNKNOWN')}")
    lines.append(f"ts_utc: {status.get('ts_utc', 'UNKNOWN')}")
    lines.append(f"popup_enabled: {status.get('popup_enabled', 'UNKNOWN')}")
    lines.append("")

    counts = status.get("output_counts", {}) or {}
    lines.append("[COUNTS]")
    lines.append(f"reports_json: {counts.get('reports_json', 'UNKNOWN')}")
    lines.append(f"alerts_json: {counts.get('alerts_json', 'UNKNOWN')}")
    lines.append(f"tickets_json: {counts.get('tickets_json', 'UNKNOWN')}")
    lines.append("")

    lines.append("[LAST RESULTS]")
    last_results = status.get("last_results", []) or []
    if not last_results:
        lines.append("- no new cycle results in last poll")
    else:
        for row in last_results:
            agent = row.get("agent", "UNKNOWN")
            st = row.get("status", "UNKNOWN")
            err = row.get("error")
            if err:
                lines.append(f"- {agent}: {st} | error={err}")
            else:
                lines.append(f"- {agent}: {st}")
    lines.append("")

    lines.append("[ALERT POPUPS]")
    lines.append(f"new_alerts_last_poll: {status.get('new_alerts_last_poll', 'UNKNOWN')}")
    lines.append(f"high_popups_last_poll: {status.get('high_popups_last_poll', 'UNKNOWN')}")
    last_popup = status.get("last_popup", {}) or {}
    if last_popup:
        lines.append(f"last_popup_ts_utc: {last_popup.get('ts_utc', 'UNKNOWN')}")
        lines.append(f"last_popup_summary: {last_popup.get('summary', 'UNKNOWN')}")
    else:
        lines.append("last_popup: none")

    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Operator console for observers runtime service.")
    p.add_argument("--refresh-sec", type=int, default=5)
    p.add_argument("--once", action="store_true", default=False)
    return p.parse_args()


def main() -> int:
    args = parse_args()
    refresh = max(1, int(args.refresh_sec))
    while True:
        status = read_json(STATUS_PATH)
        clear_screen()
        print(format_status(status))
        if args.once:
            return 0
        time.sleep(refresh)


if __name__ == "__main__":
    raise SystemExit(main())
