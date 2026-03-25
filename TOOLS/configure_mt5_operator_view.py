#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, Optional

from pywinauto import Desktop, keyboard


def _find_main_window(process_id: int):
    for window in Desktop(backend="uia").windows():
        if window.process_id() == process_id:
            return window
    raise RuntimeError(f"Nie znaleziono okna UI dla procesu {process_id}.")


def _find_descendant(window, *, control_type: str, text_exact: Optional[str] = None):
    for control in window.descendants():
        if control.element_info.control_type != control_type:
            continue
        text = (control.window_text() or "").strip()
        if text_exact is not None and text == text_exact:
            return control
    return None


def _toolbox_visible(window, tab_name: str) -> bool:
    return _find_descendant(window, control_type="TabItem", text_exact=tab_name) is not None


def _ensure_toolbox_visible(window, toolbox_tab: str) -> bool:
    if _toolbox_visible(window, toolbox_tab):
        return True
    keyboard.send_keys("^t")
    time.sleep(1.5)
    return _toolbox_visible(window, toolbox_tab)


def _click_control(control) -> None:
    try:
        control.invoke()
        return
    except Exception:
        pass
    try:
        control.select()
        return
    except Exception:
        pass
    control.click_input()


def _activate_toolbox_tab(window, tab_name: str) -> bool:
    tab = _find_descendant(window, control_type="TabItem", text_exact=tab_name)
    if tab is None:
        return False
    _click_control(tab)
    time.sleep(0.5)
    return True


def _vps_panel_visible(window) -> bool:
    return _find_descendant(window, control_type="Text", text_exact="MetaTrader VPS") is not None


def _open_vps_panel(window) -> bool:
    if _vps_panel_visible(window):
        return True
    vps_button = _find_descendant(window, control_type="MenuItem", text_exact="VPS")
    if vps_button is None:
        return False
    _click_control(vps_button)
    time.sleep(2)
    return _vps_panel_visible(window)


def _activate_vps_tab(window, tab_name: str) -> bool:
    for control_type in ("Hyperlink", "ListItem"):
        control = _find_descendant(window, control_type=control_type, text_exact=tab_name)
        if control is None:
            continue
        _click_control(control)
        time.sleep(0.5)
        return True
    return False


def _window_title(window) -> str:
    return (window.window_text() or "").strip()


def _write_report(report: Dict[str, Any], output_json: Path, latest_json: Optional[Path], latest_md: Optional[Path]) -> None:
    output_json.parent.mkdir(parents=True, exist_ok=True)
    output_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if latest_json:
        latest_json.parent.mkdir(parents=True, exist_ok=True)
        latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if latest_md:
        latest_md.parent.mkdir(parents=True, exist_ok=True)
        lines = [
            "# Widok Operatora MT5",
            "",
            f"- OK: {report['ok']}",
            f"- Okno: {report['window_title']}",
            f"- Toolbox widoczny: {report['toolbox_visible']}",
            f"- Dolna zakładka: {report['toolbox_tab']} -> {report['toolbox_tab_selected']}",
            f"- Panel VPS widoczny: {report['vps_panel_visible']}",
            f"- Zakładka VPS: {report['vps_tab']} -> {report['vps_tab_selected']}",
            f"- Tryb: {report['mode']}",
        ]
        latest_md.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")

    parser = argparse.ArgumentParser(description="Ustaw widok operatora dla lokalnego terminala OANDA MT5.")
    parser.add_argument("--process-id", type=int, required=True)
    parser.add_argument("--toolbox-tab", default="Eksperci")
    parser.add_argument("--vps-tab", default="Eksperci")
    parser.add_argument("--open-vps-panel", action="store_true")
    parser.add_argument("--output-json", required=True)
    parser.add_argument("--latest-json")
    parser.add_argument("--latest-md")
    args = parser.parse_args()

    window = _find_main_window(args.process_id)
    try:
        window.restore()
    except Exception:
        pass
    try:
        window.set_focus()
    except Exception:
        pass
    time.sleep(0.5)

    toolbox_visible = _ensure_toolbox_visible(window, args.toolbox_tab)
    toolbox_selected = _activate_toolbox_tab(window, args.toolbox_tab) if toolbox_visible else False

    vps_visible_before = _vps_panel_visible(window)
    vps_visible = vps_visible_before
    if args.open_vps_panel:
        vps_visible = _open_vps_panel(window)
    vps_selected = False
    if vps_visible:
        vps_selected = _activate_vps_tab(window, args.vps_tab)

    report = {
        "ok": bool(toolbox_selected and (not args.open_vps_panel or vps_selected)),
        "process_id": args.process_id,
        "window_title": _window_title(window),
        "toolbox_visible": toolbox_visible,
        "toolbox_tab": args.toolbox_tab,
        "toolbox_tab_selected": toolbox_selected,
        "vps_panel_visible_before": vps_visible_before,
        "vps_panel_visible": vps_visible,
        "vps_tab": args.vps_tab,
        "vps_tab_selected": vps_selected,
        "mode": "toolbox_plus_vps" if args.open_vps_panel else "toolbox_only",
    }

    output_json = Path(args.output_json)
    latest_json = Path(args.latest_json) if args.latest_json else None
    latest_md = Path(args.latest_md) if args.latest_md else None
    _write_report(report, output_json, latest_json, latest_md)
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
