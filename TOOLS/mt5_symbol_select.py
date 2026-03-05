#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Select/enable symbols in MT5 Market Watch (selection + visibility preflight helper).

No strategy logic changes. Operational utility only.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Dict, List, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MT5_EXE = r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"


def utc_now_z() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _norm_symbol(s: str) -> str:
    raw = str(s or "").strip()
    if not raw:
        return ""
    if "." not in raw:
        return raw.upper()
    base, suffix = raw.split(".", 1)
    base = base.strip().upper()
    suffix = suffix.strip().lower()
    return f"{base}.{suffix}" if suffix else base


def _candidates_for(symbol: str) -> List[str]:
    s = _norm_symbol(symbol)
    if not s:
        return []
    if "." in s:
        base = s.split(".", 1)[0]
        return [s, f"{base}.PRO", base]
    return [f"{s}.pro", f"{s}.PRO", s]


def _resolve_runtime_symbol(mt5, wanted: str) -> Optional[str]:
    rows = mt5.symbols_get()
    if rows is None:
        return None
    names = [str(getattr(r, "name", "") or "") for r in rows]
    names_u = {n.upper(): n for n in names if n}

    for cand in _candidates_for(wanted):
        hit = names_u.get(cand.upper())
        if hit:
            return hit
    return None


def _safe_symbol_info(mt5, symbol: str) -> Dict[str, object]:
    out: Dict[str, object] = {}
    info = mt5.symbol_info(symbol)
    if info is None:
        return out
    for k in ("name", "visible", "select", "trade_mode", "digits", "spread", "point", "trade_stops_level", "trade_freeze_level"):
        try:
            out[k] = getattr(info, k)
        except Exception as exc:
            _ = exc
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Ensure symbols are selected/visible in MT5.")
    ap.add_argument("--mt5-path", default=DEFAULT_MT5_EXE, help="Path to terminal64.exe")
    ap.add_argument("--symbols", nargs="+", required=True, help="Wanted symbols/aliases (e.g. AUDJPY NZDJPY)")
    ap.add_argument("--out", default=str(ROOT / "RUN" / "mt5_symbol_select_report.json"), help="Output report path")
    args = ap.parse_args()

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "schema_version": 1,
        "ts_utc": utc_now_z(),
        "mt5_path": str(args.mt5_path),
        "wanted_symbols": [str(s) for s in args.symbols],
        "result": "UNKNOWN",
        "rows": [],
        "error": None,
    }

    try:
        import MetaTrader5 as mt5
    except Exception as e:  # pragma: no cover - runtime env dependent
        report["result"] = "FAIL"
        report["error"] = f"Import MetaTrader5 failed: {type(e).__name__}:{e}"
        out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"status": "FAIL", "out": str(out_path), "error": report["error"]}, ensure_ascii=False))
        return 2

    try:
        ok_init = mt5.initialize(path=str(args.mt5_path))
    except Exception as e:  # pragma: no cover - runtime env dependent
        ok_init = False
        report["error"] = f"initialize_exception: {type(e).__name__}:{e}"

    if not ok_init:
        err = mt5.last_error()
        report["result"] = "FAIL"
        report["error"] = report.get("error") or f"initialize_failed: {err}"
        out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps({"status": "FAIL", "out": str(out_path), "error": report["error"]}, ensure_ascii=False))
        try:
            mt5.shutdown()
        except Exception as exc:
            _ = exc
        return 3

    all_ok = True
    for wanted in args.symbols:
        wanted_s = str(wanted).strip()
        runtime_name = _resolve_runtime_symbol(mt5, wanted_s)
        row: Dict[str, object] = {
            "wanted": wanted_s,
            "runtime_name": runtime_name or "",
            "resolved": bool(runtime_name),
            "select_attempted": False,
            "select_ok": False,
            "before": {},
            "after": {},
        }
        if not runtime_name:
            all_ok = False
            report["rows"].append(row)
            continue

        row["before"] = _safe_symbol_info(mt5, runtime_name)
        row["select_attempted"] = True
        try:
            row["select_ok"] = bool(mt5.symbol_select(runtime_name, True))
        except Exception:
            row["select_ok"] = False
        row["after"] = _safe_symbol_info(mt5, runtime_name)

        after = row["after"] if isinstance(row["after"], dict) else {}
        selected = bool(after.get("select", False))
        visible = bool(after.get("visible", False))
        row["preflight_ready"] = bool(selected and visible)
        if not row["preflight_ready"]:
            all_ok = False
        report["rows"].append(row)

    try:
        term = mt5.terminal_info()
        report["terminal_info"] = {
            "name": getattr(term, "name", ""),
            "company": getattr(term, "company", ""),
            "connected": bool(getattr(term, "connected", False)),
            "trade_allowed": bool(getattr(term, "trade_allowed", False)),
        }
    except Exception:
        report["terminal_info"] = {}

    report["result"] = "PASS" if all_ok else "PARTIAL"
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    try:
        mt5.shutdown()
    except Exception as exc:
        _ = exc
    print(json.dumps({"status": report["result"], "out": str(out_path), "rows": len(report["rows"])}, ensure_ascii=False))
    return 0 if all_ok else 4


if __name__ == "__main__":
    raise SystemExit(main())
