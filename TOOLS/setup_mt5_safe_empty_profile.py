#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Build a clean MT5 profile with a single chart and no EA attached.
This is intended as a safe profile for overwriting an old MetaTrader VPS snapshot.
"""

from __future__ import annotations

import argparse
import codecs
import json
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Optional


DEFAULT_MT5_EXE = Path(r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe")
DEFAULT_TERMINAL_DATA_DIR = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
)
DEFAULT_PROFILE_NAME = "MAKRO_I_MIKRO_BOT_VPS_CLEAR"
DEFAULT_SYMBOL = "EURUSD.pro"

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


def _normalize_chart_template_text(text: str) -> str:
    return (text or "").lstrip("\ufeff")


def _write_chart_text(path: Path, text: str) -> None:
    normalized = _normalize_chart_template_text(text)
    payload = codecs.BOM_UTF16_LE + normalized.encode("utf-16le")
    path.write_bytes(payload)


def _pick_source_chart(data_dir: Path) -> Optional[Path]:
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    if not charts_root.exists():
        return None
    preferred_names = ["MAKRO_I_MIKRO_BOT_AUTO", "OANDA_HYBRID_AUTO", "Default"]
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


def _normalize_window_block(chart_text: str) -> str:
    out = re.sub(r"(?is)<window>.*?</window>\s*", "", chart_text)
    if "</chart>" in out:
        return out.replace("</chart>", MINIMAL_WINDOW_BLOCK + "</chart>", 1)
    return out.rstrip() + "\r\n" + MINIMAL_WINDOW_BLOCK


def _strip_expert_objects(chart_text: str) -> str:
    out = re.sub(r"(?is)<expert>.*?</expert>\s*", "", chart_text)
    out = re.sub(r"(?is)\s*<object>.*?</object>\s*", "\r\n", out)
    out = re.sub(r"(?mi)^objects=\d+\s*$", "objects=0", out)
    return out


def _close_mt5_processes() -> None:
    subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "$p=Get-Process terminal64 -ErrorAction SilentlyContinue | "
                "Where-Object { $_.MainWindowTitle -like '*OANDA TMS Brokers S.A.*' -and "
                "$_.MainWindowTitle -notmatch '\\[VPS\\]' }; "
                "if($p){$p|%{$_.CloseMainWindow()|Out-Null}; Start-Sleep -Seconds 2; "
                "$p=Get-Process terminal64 -ErrorAction SilentlyContinue | "
                "Where-Object { $_.MainWindowTitle -like '*OANDA TMS Brokers S.A.*' -and "
                "$_.MainWindowTitle -notmatch '\\[VPS\\]' }; "
                "if($p){$p|Stop-Process -Force}}"
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
    ap.add_argument("--symbol", default=DEFAULT_SYMBOL)
    ap.add_argument("--launch", action="store_true")
    args = ap.parse_args()

    data_dir = Path(args.terminal_data_dir)
    mt5_exe = Path(args.mt5_exe)
    template = _pick_source_chart(data_dir)
    if template is None:
        raise SystemExit("Brak bazowego pliku chart*.chr w katalogu Profiles\\Charts.")

    template_text = _normalize_chart_template_text(template.read_text(encoding="utf-16le"))
    chart_text = _strip_expert_objects(template_text)
    chart_text = _replace_line(chart_text, "id", str(max(int(time.time_ns() % 9_000_000_000_000_000_000), 1)))
    chart_text = _replace_line(chart_text, "symbol", args.symbol)
    chart_text = _replace_line(chart_text, "description", args.symbol.replace(".pro", ""))
    chart_text = _replace_line(chart_text, "period_type", "0")
    chart_text = _replace_line(chart_text, "period_size", "5")
    chart_text = _replace_line(chart_text, "one_click", "0")
    chart_text = _replace_line(chart_text, "one_click_btn", "1")
    for key, value in SAFE_WINDOW_FIELDS.items():
        chart_text = _replace_line(chart_text, key, value)
    chart_text = _normalize_window_block(chart_text)

    charts_dir = data_dir / "MQL5" / "Profiles" / "Charts" / args.profile_name
    backup_dir = data_dir / "MQL5" / "Profiles" / "Charts" / f"{args.profile_name}_backup_{int(time.time())}"
    if charts_dir.exists():
        shutil.copytree(charts_dir, backup_dir)
        shutil.rmtree(charts_dir)
    charts_dir.mkdir(parents=True, exist_ok=True)

    if args.launch:
        _close_mt5_processes()

    out_path = charts_dir / "chart01.chr"
    _write_chart_text(out_path, chart_text)

    launched = False
    if args.launch:
        launched = _launch_mt5(mt5_exe, args.profile_name)

    report = {
        "ok": True,
        "profile_name": args.profile_name,
        "charts_dir": str(charts_dir),
        "template": str(template),
        "symbol_terminal": args.symbol,
        "charts": 1,
        "experts": 0,
        "launched": launched,
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    evidence_dir = project_root / "EVIDENCE"
    evidence_dir.mkdir(parents=True, exist_ok=True)
    (evidence_dir / "mt5_vps_clear_profile_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (evidence_dir / "mt5_vps_clear_profile_report.txt").write_text(
        "\n".join(
            [
                f"ok={report['ok']}",
                f"profile_name={report['profile_name']}",
                f"charts_dir={report['charts_dir']}",
                f"template={report['template']}",
                f"symbol_terminal={report['symbol_terminal']}",
                f"charts={report['charts']}",
                f"experts={report['experts']}",
                f"launched={report['launched']}",
            ]
        ),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
