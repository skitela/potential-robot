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
import shlex
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


def _write_order_file(charts_dir: Path, chart_files: List[str]) -> None:
    order_path = charts_dir / "order.wnd"
    lines = [name for name in chart_files if name]
    payload = codecs.BOM_UTF16_LE + ("\r\n".join(lines) + "\r\n").encode("utf-16le")
    order_path.write_bytes(payload)


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


def _extract_inputs(chart_text: str) -> List[str]:
    match = re.search(r"(?is)<inputs>\s*(.*?)\s*</inputs>", chart_text)
    if not match:
        return []
    lines: List[str] = []
    for raw in match.group(1).splitlines():
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        lines.append(line)
    return lines


def _merge_input_lines(base_lines: List[str], override_lines: List[str]) -> List[str]:
    merged: List[str] = list(base_lines)
    index_by_key: Dict[str, int] = {}
    for idx, line in enumerate(merged):
        if "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        index_by_key[key] = idx

    for line in override_lines:
        if "=" not in line:
            continue
        key = line.split("=", 1)[0].strip()
        if key in index_by_key:
            merged[index_by_key[key]] = line
        else:
            index_by_key[key] = len(merged)
            merged.append(line)
    return merged


def _ensure_default_input_lines(lines: List[str], defaults: Dict[str, str]) -> List[str]:
    effective = list(lines)
    present = set()
    for line in effective:
        if "=" not in line:
            continue
        present.add(line.split("=", 1)[0].strip())
    for key, value in defaults.items():
        if key not in present:
            effective.append(f"{key}={value}")
    return effective


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


def _build_chart_text(
    template_text: str,
    item: Dict[str, Any],
    preset_lines: List[str],
    chart_id: str,
    preserve_existing_structure: bool = False,
) -> str:
    symbol = _resolve_symbol(str(item.get("broker_symbol") or item["symbol"]))
    expert = str(item["expert"])
    out = _upsert_microbot_expert_block(template_text, expert, preset_lines)
    out = _replace_line(out, "id", chart_id)
    out = _replace_line(out, "symbol", symbol)
    out = _replace_line(out, "description", _description_for_symbol(symbol))
    out = _replace_line(out, "period_type", "0")
    out = _replace_line(out, "period_size", "5")
    out = _replace_line(out, "one_click", "0")
    out = _replace_line(out, "one_click_btn", "1")
    if not preserve_existing_structure:
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


def _pick_source_chart_for_expert(data_dir: Path, expert: str, exclude_profile: Optional[str] = None) -> Optional[Path]:
    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    if not charts_root.exists():
        return None

    candidates: List[Path] = []
    for chart_path in charts_root.rglob("chart*.chr"):
        profile_name = chart_path.parent.name
        if exclude_profile:
            excluded_prefix = f"{exclude_profile}_backup_"
            if profile_name == exclude_profile or profile_name.startswith(excluded_prefix):
                continue
        try:
            text = _normalize_chart_template_text(chart_path.read_text(encoding="utf-16le"))
        except Exception:
            continue
        if f"name={expert}" in text:
            candidates.append(chart_path)

    if not candidates:
        return None
    candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return candidates[0]


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


def _list_oanda_terminal_processes(include_vps: bool = True) -> List[Dict[str, Any]]:
    command = [
        "powershell",
        "-NoProfile",
        "-Command",
        (
            "$p=Get-Process terminal64 -ErrorAction SilentlyContinue | "
            "Where-Object { $_.MainWindowTitle -like '*OANDA TMS Brokers S.A.*' }; "
            "$p | Select-Object Id,MainWindowTitle,StartTime | ConvertTo-Json -Depth 3"
        ),
    ]
    result = subprocess.run(command, check=False, capture_output=True, text=True, encoding="utf-8")
    raw = (result.stdout or "").strip()
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    rows = data if isinstance(data, list) else [data]
    if include_vps:
        return rows
    return [row for row in rows if "[VPS]" not in str(row.get("MainWindowTitle", ""))]


def _list_terminal_processes_by_exe(mt5_exe: Path) -> List[Dict[str, Any]]:
    command = [
        "powershell",
        "-NoProfile",
        "-Command",
        (
            "$exe=$args[0]; "
            "Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | "
            "Where-Object { $_.Name -eq 'terminal64.exe' -and $_.ExecutablePath -eq $exe } | "
            "Select-Object ProcessId,ExecutablePath,CommandLine | ConvertTo-Json -Depth 3"
        ),
        str(mt5_exe),
    ]
    result = subprocess.run(command, check=False, capture_output=True, text=True, encoding="utf-8")
    raw = (result.stdout or "").strip()
    if not raw:
        return []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    return data if isinstance(data, list) else [data]


def _is_portable_launch(mt5_exe: Path, terminal_data_dir: Path) -> bool:
    try:
        return mt5_exe.parent.resolve() == terminal_data_dir.resolve()
    except FileNotFoundError:
        return False


def _replace_or_append_ini_line(text: str, section: str, key: str, value: str) -> str:
    section_header = f"[{section}]"
    lines = text.splitlines()
    out: List[str] = []
    in_section = False
    section_found = False
    key_written = False

    for idx, raw_line in enumerate(lines):
        line = raw_line
        stripped = raw_line.strip()
        is_section = stripped.startswith("[") and stripped.endswith("]")
        if is_section:
            if in_section and not key_written:
                out.append(f"{key}={value}")
                key_written = True
            in_section = stripped == section_header
            if in_section:
                section_found = True
            out.append(line)
            continue

        if in_section and stripped.lower().startswith(f"{key.lower()}="):
            if not key_written:
                out.append(f"{key}={value}")
                key_written = True
            continue

        out.append(line)

    if in_section and not key_written:
        out.append(f"{key}={value}")
        key_written = True

    if not section_found:
        if out and out[-1].strip():
            out.append("")
        out.append(section_header)
        out.append(f"{key}={value}")
    elif not key_written:
        if out and out[-1].strip():
            out.append("")
        out.append(f"{key}={value}")

    return "\r\n".join(out) + "\r\n"


def _prime_terminal_profile(data_dir: Path, profile_name: str) -> None:
    common_ini = data_dir / "config" / "common.ini"
    if not common_ini.exists():
        return
    try:
        text = common_ini.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return
    text = _replace_or_append_ini_line(text, "Charts", "ProfileLast", profile_name)
    text = _replace_or_append_ini_line(text, "Experts", "Enabled", "1")
    common_ini.write_text(text, encoding="utf-8")


def _launch_mt5(mt5_exe: Path, profile_name: str, terminal_data_dir: Path) -> Dict[str, Any]:
    if not mt5_exe.exists():
        return {
            "requested": False,
            "launched": False,
            "launch_note": "mt5_exe_missing",
            "before": _list_oanda_terminal_processes(include_vps=True),
            "after": _list_oanda_terminal_processes(include_vps=True),
        }
    portable_launch = _is_portable_launch(mt5_exe, terminal_data_dir)
    launch_args = [str(mt5_exe)]
    if portable_launch:
        launch_args.append("/portable")
    launch_args.append(f"/profile:{profile_name}")
    before_all = _list_oanda_terminal_processes(include_vps=True)
    before_local = _list_oanda_terminal_processes(include_vps=False)
    before_portable = _list_terminal_processes_by_exe(mt5_exe) if portable_launch else []
    subprocess.Popen(launch_args)
    time.sleep(8 if portable_launch else 6)
    after_all = _list_oanda_terminal_processes(include_vps=True)
    after_local = _list_oanda_terminal_processes(include_vps=False)
    after_portable = _list_terminal_processes_by_exe(mt5_exe) if portable_launch else []
    before_ids = {int(row.get("Id", 0)) for row in before_local if row.get("Id")}
    after_ids = {int(row.get("Id", 0)) for row in after_local if row.get("Id")}
    new_local_ids = sorted(after_ids - before_ids)
    if portable_launch:
        before_portable_ids = {int(row.get("ProcessId", 0)) for row in before_portable if row.get("ProcessId")}
        after_portable_ids = {int(row.get("ProcessId", 0)) for row in after_portable if row.get("ProcessId")}
        new_local_ids = sorted(after_portable_ids - before_portable_ids)
        launched = bool(new_local_ids) or bool(after_portable)
    else:
        launched = bool(new_local_ids) or bool(after_local)
    launch_note = "local_terminal_visible"
    if portable_launch:
        if before_portable and after_portable and {int(row.get("ProcessId", 0)) for row in before_portable if row.get("ProcessId")} == {int(row.get("ProcessId", 0)) for row in after_portable if row.get("ProcessId")}:
            launch_note = "reused_existing_portable_terminal"
        elif not after_portable:
            launch_note = "portable_terminal_not_visible_after_launch"
    else:
        if before_local and after_local and before_ids == after_ids:
            launch_note = "reused_existing_local_terminal"
        elif not after_local:
            if any("[VPS]" in str(row.get("MainWindowTitle", "")) for row in after_all):
                launch_note = "blocked_by_existing_vps_instance"
            else:
                launch_note = "local_terminal_not_visible_after_launch"
    return {
        "requested": True,
        "launched": launched,
        "launch_note": launch_note,
        "portable_launch": portable_launch,
        "launch_command": " ".join(shlex.quote(arg) for arg in launch_args),
        "before": before_all,
        "after": after_all,
        "new_local_ids": new_local_ids,
        "before_portable": before_portable,
        "after_portable": after_portable,
    }


def main() -> int:
    here = Path(__file__).resolve().parent
    project_root = here.parent

    ap = argparse.ArgumentParser()
    ap.add_argument("--profile-name", default=DEFAULT_PROFILE_NAME)
    ap.add_argument("--mt5-exe", default=str(DEFAULT_MT5_EXE))
    ap.add_argument("--terminal-data-dir", default=str(DEFAULT_TERMINAL_DATA_DIR))
    ap.add_argument("--chart-plan", default=str(project_root / "DOCS" / "06_MT5_CHART_ATTACHMENT_PLAN.json"))
    ap.add_argument("--preset-root", default=str(project_root / "MQL5" / "Presets"))
    ap.add_argument("--use-active-presets", action="store_true")
    ap.add_argument("--launch", action="store_true")
    args = ap.parse_args()

    data_dir = Path(args.terminal_data_dir)
    chart_plan_path = Path(args.chart_plan)
    mt5_exe = Path(args.mt5_exe)
    preset_root = Path(args.preset_root)
    active_preset_root = preset_root / "ActiveLive"

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
    chart_filenames: List[str] = []
    for idx, item in enumerate(items, start=1):
        expert_name = str(item["expert"])
        expert_template = _pick_source_chart_for_expert(data_dir, expert_name, exclude_profile=args.profile_name)
        source_template_text = template_text
        source_inputs: List[str] = []
        if expert_template is not None:
            try:
                source_template_text = _normalize_chart_template_text(expert_template.read_text(encoding="utf-16le"))
                source_inputs = _extract_inputs(source_template_text)
            except Exception:
                source_template_text = template_text
                source_inputs = []

        preset_name = str(item["preset"])
        preset_mode = "safe"
        if args.use_active_presets:
            active_preset_name = f"{Path(preset_name).stem}_ACTIVE.set"
            preset_path = active_preset_root / active_preset_name
            preset_mode = "active_live"
            if not preset_path.exists():
                raise SystemExit(f"Brak aktywnego presetu serwerowego: {preset_path}")
        else:
            preset_path = preset_root / preset_name
        if not preset_path.exists():
            raise SystemExit(f"Brak presetu: {preset_path}")
        preset_lines = _read_preset_lines(preset_path)
        effective_preset_lines = (
            _merge_input_lines(source_inputs, preset_lines)
            if len(preset_lines) <= 4 and source_inputs
            else preset_lines
        )
        if not args.use_active_presets:
            effective_preset_lines = _ensure_default_input_lines(
                effective_preset_lines,
                {
                    "InpEnableLiveEntries": "false",
                    "InpPaperCollectMode": "true",
                    "InpEnableOnnxObservation": "true",
                    "InpEnableMlRuntimeBridge": "true",
                    "InpEnableStudentDecisionGate": "false",
                },
            )
        chart_text = _build_chart_text(
            source_template_text,
            item,
            effective_preset_lines,
            str(id_seed + idx),
            preserve_existing_structure=bool(expert_template),
        )
        out_path = charts_dir / f"chart{idx:02d}.chr"
        _write_chart_text(out_path, chart_text)
        chart_filenames.append(out_path.name)
        written.append(
            {
                "chart": out_path.name,
                "symbol": item["symbol"],
                "broker_symbol": item.get("broker_symbol", item["symbol"]),
                "expert": item["expert"],
                "preset": preset_name,
                "preset_mode": preset_mode,
                "resolved_preset_path": str(preset_path),
                "source_chart": str(expert_template) if expert_template else str(template),
                "effective_input_count": len(effective_preset_lines),
                "symbol_terminal": _resolve_symbol(str(item.get("broker_symbol") or item["symbol"])),
            }
        )

    _write_order_file(charts_dir, chart_filenames)
    _prime_terminal_profile(data_dir, args.profile_name)

    launch_report: Dict[str, Any] = {
        "requested": False,
        "launched": False,
        "launch_note": "launch_not_requested",
        "before": _list_oanda_terminal_processes(include_vps=True),
        "after": _list_oanda_terminal_processes(include_vps=True),
    }
    if args.launch:
        launch_report = _launch_mt5(mt5_exe, args.profile_name, data_dir)

    report = {
        "ok": True,
        "profile_name": args.profile_name,
        "charts_dir": str(charts_dir),
        "template": str(template),
        "preset_root": str(preset_root),
        "use_active_presets": bool(args.use_active_presets),
        "launched": bool(launch_report.get("launched", False)),
        "launch_report": launch_report,
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
