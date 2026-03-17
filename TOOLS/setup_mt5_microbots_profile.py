#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Create/update MT5 chart profile with one MicroBot attached per chart.
"""

from __future__ import annotations

import argparse
import codecs
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


DEFAULT_MT5_EXE = Path(r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe")
DEFAULT_PROFILE_NAME = "MAKRO_I_MIKRO_BOT_AUTO"
DEFAULT_TERMINAL_DATA_DIR = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
)
SAFE_WINDOW_FIELDS = {
    "window_left": "20",
    "window_top": "20",
    "window_right": "1280",
    "window_bottom": "760",
    "window_type": "3",
    "floating": "0",
    "floating_left": "0",
    "floating_top": "0",
    "floating_right": "0",
    "floating_bottom": "0",
    "floating_type": "1",
    "floating_toolbar": "1",
    "windows_total": "1",
}
MINIMAL_WINDOW_BLOCK = (
    "<window>\r\n"
    "height=100.000000\r\n"
    "objects=0\r\n"
    "<indicator>\r\n"
    "name=Main\r\n"
    "path=\r\n"
    "apply=1\r\n"
    "show_data=1\r\n"
    "scale_inherit=0\r\n"
    "scale_line=0\r\n"
    "scale_line_percent=50\r\n"
    "scale_line_value=0.000000\r\n"
    "scale_fix_min=0\r\n"
    "scale_fix_min_val=0.000000\r\n"
    "scale_fix_max=0\r\n"
    "scale_fix_max_val=0.000000\r\n"
    "expertmode=0\r\n"
    "fixed_height=-1\r\n"
    "</indicator>\r\n"
    "</window>\r\n"
)


def _replace_line(txt: str, key: str, value: str) -> str:
    line = f"{key}={value}"
    pat = re.compile(rf"(?mi)^{re.escape(key)}=.*$")
    if pat.search(txt):
        return pat.sub(lambda _: line, txt, count=1)
    return txt.replace("<chart>\r\n", f"<chart>\r\n{line}\r\n", 1)


def _replace_input(chart_text: str, input_key: str, input_value: str) -> str:
    match = re.search(r"(?is)<inputs>\s*(.*?)\s*</inputs>", chart_text)
    if not match:
        return chart_text
    body = match.group(1)
    line = f"{input_key}={input_value}"
    pat = re.compile(rf"(?mi)^{re.escape(input_key)}=.*$")
    if pat.search(body):
        body_new = pat.sub(lambda _: line, body, count=1)
    else:
        suffix = "" if body.endswith(("\n", "\r")) else "\r\n"
        body_new = f"{body}{suffix}{line}"
    return chart_text[: match.start(1)] + body_new + chart_text[match.end(1) :]


def _normalize_window_block(chart_text: str) -> str:
    out = re.sub(r"(?is)<window>.*?</window>\s*", "", chart_text)
    if "</chart>" in out:
        return out.replace("</chart>", MINIMAL_WINDOW_BLOCK + "</chart>", 1)
    return out.rstrip() + "\r\n" + MINIMAL_WINDOW_BLOCK


def _normalize_chart_template_text(text: str) -> str:
    return (text or "").lstrip("\ufeff")


def _write_chart_text(path: Path, text: str) -> None:
    normalized = _normalize_chart_template_text(text)
    payload = codecs.BOM_UTF16_LE + normalized.encode("utf-16le")
    path.write_bytes(payload)


def _description_for_symbol(symbol: str) -> str:
    base = symbol.replace(".pro", "").upper()
    if len(base) == 6 and base.isalpha():
        return f"{base[:3]}/{base[3:]}"
    return base


def _resolve_symbol(symbol: str) -> str:
    s = symbol.strip()
    if s.lower().endswith(".pro"):
        return s
    return f"{s}.pro"


def _read_preset_lines(preset_path: Path) -> List[str]:
    lines = []
    for raw in preset_path.read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        lines.append(line)
    return lines


def _render_microbot_expert_block(expert: str, preset_lines: List[str]) -> str:
    lines = [
        "<expert>",
        f"name={expert}",
        rf"path=Experts\MicroBots\{expert}.ex5",
        "expertmode=5",
        "<inputs>",
    ]
    lines.extend(preset_lines)
    lines.extend(["</inputs>", "</expert>"])
    return "\r\n".join(lines) + "\r\n"


def _upsert_microbot_expert_block(chart_text: str, expert: str, preset_lines: List[str]) -> str:
    out = re.sub(r"(?is)<expert>.*?</expert>\s*", "", chart_text, count=1)
    block = _render_microbot_expert_block(expert, preset_lines)
    insert_at = out.lower().find("<window>")
    if insert_at >= 0:
        return out[:insert_at] + block + "\r\n" + out[insert_at:]
    return out.rstrip() + "\r\n\r\n" + block


def _build_chart_text(template_text: str, item: Dict[str, Any], preset_lines: List[str], chart_id: str) -> str:
    symbol = _resolve_symbol(str(item["symbol"]))
    expert = str(item["expert"])
    out = _upsert_microbot_expert_block(template_text, expert, preset_lines)
    out = _replace_line(out, "id", chart_id)
    out = _replace_line(out, "symbol", symbol)
    out = _replace_line(out, "description", _description_for_symbol(symbol))
    out = _replace_line(out, "period_type", "0")
    out = _replace_line(out, "period_size", "5")
    out = _replace_line(out, "one_click", "0")
    out = _replace_line(out, "one_click_btn", "1")
    for key, value in SAFE_WINDOW_FIELDS.items():
        out = _replace_line(out, key, value)
    out = re.sub(r"(?is)\s*<object>.*?</object>\s*", "\r\n", out)
    out = re.sub(r"(?mi)^objects=\d+\s*$", "objects=0", out)
    out = _normalize_window_block(out)
    return out


def _pick_source_chart(data_dir: Path) -> Optional[Path]:
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    if not charts_root.exists():
        return None

    preferred_names = [
        "OANDA_HYBRID_AUTO",
        "Default",
    ]
    for profile_name in preferred_names:
        profile_dir = charts_root / profile_name
        if profile_dir.exists():
            charts = sorted(profile_dir.glob("chart*.chr"))
            if charts:
                return charts[0]

    for profile_dir in sorted(charts_root.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True):
        charts = sorted(profile_dir.glob("chart*.chr"))
        if charts:
            return charts[0]
    return None


def _close_mt5_processes() -> None:
    subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$p=Get-Process terminal64 -ErrorAction SilentlyContinue; "
                "if($p){$p|%{$_.CloseMainWindow()|Out-Null}; Start-Sleep -Seconds 2; "
                "$p=Get-Process terminal64 -ErrorAction SilentlyContinue; if($p){$p|Stop-Process -Force}}"
            ),
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _launch_mt5(mt5_exe: Path, profile_name: str) -> bool:
    if not mt5_exe.exists():
        return False
    subprocess.Popen([str(mt5_exe), f"/profile:{profile_name}"])
    return True


def main() -> int:
    here = Path(__file__).resolve().parent
    project_root = here.parent

    ap = argparse.ArgumentParser()
    ap.add_argument("--profile-name", default=DEFAULT_PROFILE_NAME)
    ap.add_argument("--mt5-exe", default=str(DEFAULT_MT5_EXE))
    ap.add_argument("--terminal-data-dir", default=str(DEFAULT_TERMINAL_DATA_DIR))
    ap.add_argument("--chart-plan", default=str(project_root / "DOCS" / "06_MT5_CHART_ATTACHMENT_PLAN.json"))
    ap.add_argument("--launch", action="store_true")
    args = ap.parse_args()

    data_dir = Path(args.terminal_data_dir)
    chart_plan_path = Path(args.chart_plan)
    mt5_exe = Path(args.mt5_exe)

    items = json.loads(chart_plan_path.read_text(encoding="utf-8-sig"))
    template = _pick_source_chart(data_dir)
    if template is None:
        raise SystemExit("Brak bazowego pliku chart*.chr w katalogu Profiles\\Charts.")
    template_text = _normalize_chart_template_text(template.read_text(encoding="utf-16le"))

    charts_dir = data_dir / "MQL5" / "Profiles" / "Charts" / args.profile_name
    backup_dir = data_dir / "MQL5" / "Profiles" / "Charts" / f"{args.profile_name}_backup_{int(time.time())}"
    if charts_dir.exists():
        shutil.copytree(charts_dir, backup_dir)
        shutil.rmtree(charts_dir)
    charts_dir.mkdir(parents=True, exist_ok=True)

    if args.launch:
        _close_mt5_processes()

    id_seed = max(int(time.time_ns() % 9_000_000_000_000_000_000), 1)
    written: List[Dict[str, Any]] = []
    for idx, item in enumerate(items, start=1):
        preset_path = project_root / "MQL5" / "Presets" / str(item["preset"])
        preset_lines = _read_preset_lines(preset_path)
        chart_text = _build_chart_text(template_text, item, preset_lines, str(id_seed + idx))
        out_path = charts_dir / f"chart{idx:02d}.chr"
        _write_chart_text(out_path, chart_text)
        written.append(
            {
                "chart": out_path.name,
                "symbol": item["symbol"],
                "expert": item["expert"],
                "preset": item["preset"],
                "symbol_terminal": _resolve_symbol(str(item["symbol"])),
            }
        )

    launched = False
    if args.launch:
        launched = _launch_mt5(mt5_exe, args.profile_name)

    report = {
        "ok": True,
        "profile_name": args.profile_name,
        "charts_dir": str(charts_dir),
        "template": str(template),
        "launched": launched,
        "charts": written,
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    evidence_dir = project_root / "EVIDENCE"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    report_json = evidence_dir / "mt5_microbots_profile_setup_report.json"
    report_txt = evidence_dir / "mt5_microbots_profile_setup_report.txt"
    report_json.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    report_txt.write_text(
        "\n".join(
            [
                f"ok={report['ok']}",
                f"profile_name={report['profile_name']}",
                f"charts_dir={report['charts_dir']}",
                f"template={report['template']}",
                f"launched={report['launched']}",
            ]
            + [
                f"{row['chart']} | {row['symbol_terminal']} | {row['expert']} | {row['preset']}"
                for row in written
            ]
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
