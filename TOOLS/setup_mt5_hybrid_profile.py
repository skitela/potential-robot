#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Create/update MT5 chart profile with HybridAgent attached on all target symbols.

This script does not touch strategy logic. It only prepares MT5 workspace/profile files.
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
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple


DEFAULT_MT5_EXE = Path(r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe")
DEFAULT_PROFILE_NAME = "OANDA_HYBRID_AUTO"
SYMBOL_AUDIT_JSON = Path("RUN/symbols_audit_now.json")
DEFAULT_BASE_SYMBOLS = [
    "EURUSD",
    "GBPUSD",
    "USDJPY",
    "USDCHF",
    "USDCAD",
    "AUDUSD",
    "NZDUSD",
    "EURGBP",
    "XAUUSD",
    "XAGUSD",
]
GROUP_CHOICES = ("ANY", "FX", "METAL", "INDEX", "CRYPTO", "EQUITY")


@dataclass
class SetupResult:
    ok: bool
    message: str
    profile_dir: Optional[Path] = None
    symbols: Optional[List[str]] = None
    launched: bool = False


def _load_strategy_symbols(root: Path) -> List[str]:
    cfg_path = root / "CONFIG" / "strategy.json"
    if not cfg_path.exists():
        return list(DEFAULT_BASE_SYMBOLS)
    try:
        data = json.loads(cfg_path.read_text(encoding="utf-8"))
        raw = data.get("symbols_to_trade")
        if isinstance(raw, list):
            out = [str(x).strip().upper() for x in raw if str(x).strip()]
            return out or list(DEFAULT_BASE_SYMBOLS)
    except Exception:
        return list(DEFAULT_BASE_SYMBOLS)
    return list(DEFAULT_BASE_SYMBOLS)


def _guess_group(base_symbol: str) -> str:
    b = str(base_symbol or "").strip().upper()
    if not b:
        return "OTHER"
    if any(k in b for k in ("XAU", "GOLD", "XAG", "SILVER", "PLATIN", "PALLAD", "COPPER", "XPT", "XPD")):
        return "METAL"
    if any(k in b for k in ("US500", "US100", "US30", "JP225", "DE40", "EU50", "SPX", "NAS", "DAX")):
        return "INDEX"
    if any(k in b for k in ("BTC", "ETH", "LTC", "XRP", "DOGE", "SOL")):
        return "CRYPTO"
    if len(b) == 6 and b.isalpha():
        return "FX"
    return "EQUITY"


def _filter_symbols_for_focus(symbols: List[str], focus_group: str) -> List[str]:
    fg = str(focus_group or "ANY").strip().upper()
    if fg == "ANY":
        return list(symbols)
    out: List[str] = []
    for sym in symbols:
        if _guess_group(sym) == fg:
            out.append(sym)
    return out


def _find_terminal_data_dir() -> Optional[Path]:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        return None
    base = Path(appdata) / "MetaQuotes" / "Terminal"
    if not base.exists():
        return None
    candidates: List[Tuple[float, Path]] = []
    for d in base.iterdir():
        if not d.is_dir():
            continue
        marker = d / "MQL5" / "Experts" / "HybridAgent.mq5"
        if marker.exists():
            try:
                ts = marker.stat().st_mtime
            except Exception:
                ts = 0.0
            candidates.append((ts, d))
    if not candidates:
        return None
    candidates.sort(reverse=True, key=lambda x: x[0])
    return candidates[0][1]


def _extract_available_symbols(root: Path) -> List[str]:
    p = root / SYMBOL_AUDIT_JSON
    if not p.exists():
        return []
    try:
        obj = json.loads(p.read_text(encoding="utf-8"))
        rows = (obj.get("details") or {}).get("symbols") or []
        out = []
        for r in rows:
            if isinstance(r, dict) and r.get("name"):
                out.append(str(r["name"]))
        return out
    except Exception:
        return []


def _resolve_symbol(base: str, available: List[str]) -> str:
    b = str(base).strip().upper()
    av_map = {s.upper(): s for s in available}

    def _norm_case(sym: str) -> str:
        s = str(sym or "").strip()
        if s.upper().endswith(".PRO"):
            return s[:-4] + ".pro"
        return s

    # Metals aliases used by broker.
    if b == "XAUUSD":
        for cand in ("GOLD.PRO", "GOLD", "XAUUSD.PRO", "XAUUSD"):
            if cand in av_map:
                return _norm_case(av_map[cand])
        return "GOLD.pro"
    if b == "XAGUSD":
        for cand in ("SILVER.PRO", "SILVER", "XAGUSD.PRO", "XAGUSD"):
            if cand in av_map:
                return _norm_case(av_map[cand])
        return "SILVER.pro"

    for cand in (f"{b}.PRO", b):
        if cand in av_map:
            return _norm_case(av_map[cand])
    # Fallback: use .pro style (what OANDA MT5 uses in this environment).
    return f"{b}.pro"


def _description_for_symbol(symbol: str) -> str:
    s = str(symbol).strip()
    u = s.upper()
    if u.startswith("GOLD"):
        return "GOLD Spot (XAUUSD)"
    if u.startswith("SILVER"):
        return "SILVER Spot (XAGUSD)"
    base = u.replace(".PRO", "")
    if len(base) == 6 and base.isalpha():
        return f"{base[:3]}/{base[3:]}"
    return base


def _chart_template_score(chart_path: Path) -> Optional[int]:
    try:
        txt = chart_path.read_text(encoding="utf-16le")
    except Exception:
        return None
    if "name=HybridAgent" not in txt or "path=Experts\\HybridAgent.ex5" not in txt:
        return None
    if "expertmode=5" not in txt:
        return None
    return len(txt)


def _pick_source_chart(data_dir: Path, profile_name: str) -> Optional[Path]:
    candidates: List[Path] = []

    deleted = data_dir / "MQL5" / "Profiles" / "deleted"
    if deleted.exists():
        candidates.extend(sorted(deleted.glob("*.chr")))

    charts_root = data_dir / "MQL5" / "Profiles" / "Charts"
    preferred_profile = charts_root / profile_name
    if preferred_profile.exists():
        candidates.extend(sorted(preferred_profile.glob("*.chr")))

    if charts_root.exists():
        for profile_dir in sorted(charts_root.iterdir()):
            if profile_dir.is_dir() and profile_dir != preferred_profile:
                candidates.extend(sorted(profile_dir.glob("*.chr")))

    best: Optional[Tuple[int, Path]] = None
    for p in candidates:
        score = _chart_template_score(p)
        if score is None:
            continue
        if best is None or score < best[0]:
            best = (score, p)
    return best[1] if best else None


def _replace_line(txt: str, key: str, value: str) -> str:
    pat = re.compile(rf"(?mi)^{re.escape(key)}=.*$")
    if pat.search(txt):
        return pat.sub(f"{key}={value}", txt, count=1)
    # insert after <chart> if key missing
    return txt.replace("<chart>\r\n", f"<chart>\r\n{key}={value}\r\n", 1)


def _build_chart_text(template_text: str, symbol: str, description: str) -> str:
    out = template_text
    out = _replace_line(out, "symbol", symbol)
    out = _replace_line(out, "description", description)
    # Force M5 scalp chart.
    out = _replace_line(out, "period_type", "0")
    out = _replace_line(out, "period_size", "5")
    # Ensure agent block still active.
    out = _replace_line(out, "expertmode", "5")
    out = _replace_input(out, "InpEnablePythonTimeoutWatchdog", "true")
    out = _replace_input(out, "InpPolicyRuntimeReloadSec", "15")
    out = _replace_input(out, "InpPolicyRuntimeRequireFile", "true")
    return out


def _replace_input(chart_text: str, input_key: str, input_value: str) -> str:
    m = re.search(r"(?is)<inputs>\s*(.*?)\s*</inputs>", chart_text)
    if not m:
        return chart_text
    body = m.group(1)
    line = f"{input_key}={input_value}"
    pat = re.compile(rf"(?mi)^{re.escape(input_key)}=.*$")
    if pat.search(body):
        body_new = pat.sub(line, body, count=1)
    else:
        suffix = "" if body.endswith(("\n", "\r")) else "\r\n"
        body_new = f"{body}{suffix}{line}"
    return chart_text[: m.start(1)] + body_new + chart_text[m.end(1) :]


def _normalize_chart_template_text(text: str) -> str:
    # MT5 CHR templates occasionally carry duplicated BOM markers from prior writes.
    # Keep exactly one BOM in the final file payload (added at write time).
    out = (text or "").lstrip("\ufeff")
    return out


def _write_chart_text(path: Path, text: str) -> None:
    normalized = _normalize_chart_template_text(text)
    payload = codecs.BOM_UTF16_LE + normalized.encode("utf-16le")
    path.write_bytes(payload)


def _write_profile(data_dir: Path, profile_name: str, symbols: List[str], template_path: Path) -> Path:
    charts_dir = data_dir / "MQL5" / "Profiles" / "Charts" / profile_name
    backup_dir = data_dir / "MQL5" / "Profiles" / "Charts" / f"{profile_name}_backup_{int(time.time())}"

    if charts_dir.exists():
        shutil.copytree(charts_dir, backup_dir)
        shutil.rmtree(charts_dir)
    charts_dir.mkdir(parents=True, exist_ok=True)

    template_text = _normalize_chart_template_text(template_path.read_text(encoding="utf-16le"))
    for idx, sym in enumerate(symbols, start=1):
        txt = _build_chart_text(template_text, sym, _description_for_symbol(sym))
        out = charts_dir / f"chart{idx:02d}.chr"
        _write_chart_text(out, txt)
    return charts_dir


def _close_mt5_processes() -> None:
    try:
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
    except Exception:
        return


def _launch_mt5(mt5_exe: Path, profile_name: str) -> bool:
    if not mt5_exe.exists():
        return False
    try:
        subprocess.Popen([str(mt5_exe), f"/profile:{profile_name}"])
        return True
    except Exception:
        return False


def setup(root: Path, profile_name: str, mt5_exe: Path, launch: bool, focus_group: str) -> SetupResult:
    data_dir = _find_terminal_data_dir()
    if data_dir is None:
        return SetupResult(False, "Nie znaleziono katalogu danych MT5 z HybridAgent.mq5.")

    template = _pick_source_chart(data_dir, profile_name)
    if template is None:
        return SetupResult(False, "Brak źródłowego pliku .chr z HybridAgent (expertmode=5) w Profiles/deleted ani w istniejących profilach wykresow.")

    symbols_base = _load_strategy_symbols(root)
    symbols_base = _filter_symbols_for_focus(symbols_base, focus_group)
    if not symbols_base:
        return SetupResult(False, f"Brak symboli po filtrowaniu focus-group={focus_group}.")
    available = _extract_available_symbols(root)
    resolved = [_resolve_symbol(b, available) for b in symbols_base]
    # Keep deterministic order and unique values.
    seen = set()
    symbols: List[str] = []
    for s in resolved:
        k = s.upper()
        if k in seen:
            continue
        seen.add(k)
        symbols.append(s)

    profile_dir = _write_profile(data_dir, profile_name, symbols, template)

    launched = False
    if launch:
        _close_mt5_processes()
        launched = _launch_mt5(mt5_exe, profile_name)

    report = {
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ok": True,
        "profile_name": profile_name,
        "profile_dir": str(profile_dir),
        "template_used": str(template),
        "symbols": symbols,
        "focus_group": str(focus_group).upper(),
        "launched": launched,
        "mt5_exe": str(mt5_exe),
    }
    out = root / "RUN" / "mt5_profile_setup_report.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    msg = f"Profil {profile_name} zapisany: {profile_dir} ({len(symbols)} wykresów)."
    if launch:
        msg += f" MT5 restart={'OK' if launched else 'FAIL'}."
    return SetupResult(True, msg, profile_dir=profile_dir, symbols=symbols, launched=launched)


def main() -> int:
    ap = argparse.ArgumentParser(description="Setup MT5 HybridAgent profile from archived .chr templates.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]), help="Repo root.")
    ap.add_argument("--profile", default=DEFAULT_PROFILE_NAME, help="MT5 profile name under MQL5/Profiles/Charts.")
    ap.add_argument("--mt5-exe", default=str(DEFAULT_MT5_EXE), help="Path to terminal64.exe.")
    ap.add_argument("--focus-group", default="ANY", choices=GROUP_CHOICES, help="Filter symbols by group before profile write.")
    ap.add_argument("--no-launch", action="store_true", help="Do not restart/launch MT5.")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    mt5_exe = Path(args.mt5_exe)
    res = setup(root, args.profile, mt5_exe, launch=(not args.no_launch), focus_group=str(args.focus_group))
    print(res.message)
    return 0 if res.ok else 2


if __name__ == "__main__":
    raise SystemExit(main())
