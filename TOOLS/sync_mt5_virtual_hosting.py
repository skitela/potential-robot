#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

from pywinauto import Desktop


SCOPE_MAP = {
    "all": {
        "ui_text": "Migruj wszystko:",
        "scope": "migrate_all",
        "scope_label": "Wszystko",
    },
    "experts": {
        "ui_text": "Migruj ekspertów:",
        "scope": "migrate_experts_only",
        "scope_label": "Tylko dla ekspertów",
    },
    "signal": {
        "ui_text": "Migruj sygnał:",
        "scope": "migrate_signal_only",
        "scope_label": "Tylko dla sygnału",
    },
}

AFFIRMATIVE_BUTTONS = {"tak", "yes", "ok", "migruj"}
SUCCESS_MIGRATION_LINES = {"Migracja powiodła się"}


def _find_main_window(process_id: int):
    for window in Desktop(backend="uia").windows():
        if window.process_id() == process_id:
            return window
    raise RuntimeError(f"No UI window found for process {process_id}")


def _find_descendant(
    window,
    *,
    control_type: Optional[str] = None,
    text_prefix: Optional[str] = None,
    text_exact: Optional[str] = None,
):
    for control in window.descendants():
        if control_type is not None and control.element_info.control_type != control_type:
            continue
        text = control.window_text() or ""
        if text_exact is not None and text == text_exact:
            return control
        if text_prefix is not None and text.startswith(text_prefix):
            return control
    return None


def _find_scope_control(window, text_prefix: str):
    preferred_types = ("ListItem", "Text", "Hyperlink", "MenuItem", "DataItem")
    for control_type in preferred_types:
        control = _find_descendant(window, control_type=control_type, text_prefix=text_prefix)
        if control is not None:
            return control

    normalized_prefix = text_prefix.strip().rstrip(":").lower()
    for control in window.descendants():
        text = (control.window_text() or "").strip()
        if not text:
            continue
        normalized_text = text.rstrip(":").lower()
        if normalized_text.startswith(normalized_prefix):
            return control
    return None


def _read_vps_summary(window) -> Dict[str, Any]:
    texts: list[str] = []
    for control in window.descendants():
        txt = (control.window_text() or "").strip()
        if txt:
            texts.append(txt)

    def pick(prefix: str) -> str:
        for line in texts:
            if line.startswith(prefix):
                return line
        return ""

    server_label = ""
    last_migration_line = ""
    env_line = ""
    ping_line = ""
    advantage_line = ""
    status_line = ""
    migration_result_line = ""
    roster_lines: list[str] = []

    for idx, line in enumerate(texts):
        if line == "MetaTrader VPS":
            continue
        if line.startswith("VPS "):
            server_label = line
        elif line.startswith("Ping: "):
            ping_line = line
        elif "szybciej niż obecne połączenie" in line:
            advantage_line = line
        elif (
            "wykres" in line
            and "eksper" in line
            and not line.startswith("Migruj ")
        ):
            env_line = line
        elif line == "Ostatnia migracja:" and idx + 1 < len(texts):
            last_migration_line = texts[idx + 1]
        elif line in SUCCESS_MIGRATION_LINES:
            migration_result_line = line
        elif line.lower() in {"rozpoczęto", "zakończono", "w toku"}:
            status_line = line
        elif line.startswith("MicroBot_") and " - " in line and ",M5" in line:
            roster_lines.append(line)

    if not ping_line:
        ping_line = pick("Ping: ")
    if not env_line and roster_lines:
        roster_count = len({line.strip() for line in roster_lines})
        env_line = f"{roster_count} wykresy, {roster_count} eksperci, 0 wskaźniki niestandardowe"

    return {
        "server_label": server_label,
        "ping_line": ping_line,
        "advantage_line": advantage_line,
        "environment_line": env_line,
        "last_migration_line": last_migration_line,
        "status": migration_result_line or status_line,
        "migration_result_line": migration_result_line,
        "raw_text": texts,
    }


def _open_vps_panel(window) -> None:
    vps_button = _find_descendant(window, control_type="MenuItem", text_exact="VPS")
    if vps_button is None:
        raise RuntimeError("VPS menu item not found in MT5 terminal")
    try:
        vps_button.invoke()
    except Exception:
        vps_button.click_input()
    time.sleep(2)


def _select_scope(window, scope_key: str) -> str:
    config = SCOPE_MAP[scope_key]
    item = _find_scope_control(window, config["ui_text"])
    if item is None:
        raise RuntimeError(f"Migration scope item not found: {config['ui_text']}")
    item.click_input()
    time.sleep(1)
    return item.window_text()


def _click_migrate(window) -> None:
    link = _find_descendant(window, control_type="Hyperlink", text_exact="Migruj")
    if link is None:
        raise RuntimeError("Migruj hyperlink not found in VPS panel")
    try:
        link.invoke()
    except Exception:
        link.click_input()


def _click_affirmative_dialog_buttons(main_process_id: int) -> list[str]:
    clicked: list[str] = []
    for window in Desktop(backend="uia").windows():
        if window.process_id() != main_process_id:
            continue
        for control in window.descendants():
            if control.element_info.control_type != "Button":
                continue
            txt = (control.window_text() or "").strip()
            if txt.lower() in AFFIRMATIVE_BUTTONS:
                try:
                    control.click_input()
                    clicked.append(txt)
                    time.sleep(0.5)
                except Exception:
                    pass
    return clicked


def _wait_for_migration(main_window, before_line: str, timeout_sec: int, process_id: int) -> Dict[str, Any]:
    deadline = time.time() + timeout_sec
    confirmations: list[str] = []
    snapshots: list[dict[str, Any]] = []
    last_summary = _read_vps_summary(main_window)

    while time.time() < deadline:
        confirmations.extend(_click_affirmative_dialog_buttons(process_id))
        time.sleep(2)
        summary = _read_vps_summary(main_window)
        snapshots.append(
            {
                "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "last_migration_line": summary["last_migration_line"],
                "status": summary["status"],
                "environment_line": summary["environment_line"],
            }
        )
        last_summary = summary
        if (
            summary["last_migration_line"]
            and (
                summary["last_migration_line"] != before_line
                or summary["last_migration_line"] in SUCCESS_MIGRATION_LINES
            )
        ):
            return {
                "ok": True,
                "confirmations": confirmations,
                "after": summary,
                "poll_samples": snapshots,
            }

    return {
        "ok": False,
        "confirmations": confirmations,
        "after": last_summary,
        "poll_samples": snapshots,
    }


def _write_outputs(report: Dict[str, Any], output_json: Path, latest_json: Optional[Path], latest_md: Optional[Path]) -> None:
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if latest_json:
        latest_json.parent.mkdir(parents=True, exist_ok=True)
        latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if latest_md:
        lines = [
            "# MT5 Virtual Hosting Sync",
            "",
            f"- OK: {report['ok']}",
            f"- Terminal: {report['terminal_window']}",
            f"- Scope: {report['migration_scope_label']}",
            f"- Method: {report['invocation_method']}",
            f"- Server: {report['server_label']}",
            f"- Ping: {report['ping_line']}",
            f"- Environment: {report['environment_line']}",
            f"- Before: {report['before_last_migration_line']}",
            f"- After: {report['last_migration_line']}",
            f"- Status: {report['status']}",
        ]
        latest_md.parent.mkdir(parents=True, exist_ok=True)
        latest_md.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(errors="replace")

    parser = argparse.ArgumentParser()
    parser.add_argument("--process-id", type=int, required=True)
    parser.add_argument("--scope", choices=tuple(SCOPE_MAP.keys()), default="experts")
    parser.add_argument("--timeout-sec", type=int, default=180)
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--latest-json")
    parser.add_argument("--latest-md")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    main_window = _find_main_window(args.process_id)
    _open_vps_panel(main_window)
    before = _read_vps_summary(main_window)
    selected_label = _select_scope(main_window, args.scope)

    result: Dict[str, Any]
    if args.dry_run:
        result = {
            "ok": True,
            "after": before,
            "confirmations": [],
            "poll_samples": [],
        }
    else:
        _click_migrate(main_window)
        result = _wait_for_migration(main_window, before["last_migration_line"], args.timeout_sec, args.process_id)

    after = result["after"]
    scope_cfg = SCOPE_MAP[args.scope]
    report: Dict[str, Any] = {
        "ok": bool(result["ok"]),
        "ts_local": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "mode": "metaquotes_virtual_hosting_sync_ui_state",
        "terminal_window": main_window.window_text(),
        "process_id": args.process_id,
        "invocation_method": "pywinauto_virtual_hosting_ui",
        "migration_scope": scope_cfg["scope"],
        "migration_scope_label": scope_cfg["scope_label"],
        "selected_scope_text": selected_label,
        "server_label": after["server_label"] or before["server_label"],
        "hosting_id": "",
        "ping_line": after["ping_line"] or before["ping_line"],
        "advantage_line": after["advantage_line"] or before["advantage_line"],
        "environment_line": after["environment_line"] or before["environment_line"],
        "before_last_migration_line": before["last_migration_line"],
        "last_migration_line": after["last_migration_line"],
        "status": after["status"] or ("dry_run" if args.dry_run else "unknown"),
        "migration_result_line": after["migration_result_line"],
        "confirmations": result["confirmations"],
        "poll_samples": result["poll_samples"],
        "source": "MT5 VPS tab UI",
        "raw_before_text": before["raw_text"],
        "raw_after_text": after["raw_text"],
    }

    output_json = Path(args.output_json)
    latest_json = Path(args.latest_json) if args.latest_json else None
    latest_md = Path(args.latest_md) if args.latest_md else None
    _write_outputs(report, output_json, latest_json, latest_md)

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
