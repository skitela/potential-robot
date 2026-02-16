# -*- coding: utf-8 -*-
r"""
audit_symbols_get_mt5.py - live MT5 symbols_get() dump + naming audit for OANDA_MT5_SYSTEM.

Goal:
- Attach to MT5 terminal and dump symbol universe from `mt5.symbols_get()`.
- Audit whether core SafetyBot targets are present under broker-specific aliases.
- NO trading, NO ticks, NO order_send.

Usage (Windows):
    python -B TOOLS/audit_symbols_get_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"

Evidence:
    EVIDENCE/symbols_get_audit/<run_id>_symbols_get_audit.json
"""
from __future__ import annotations

import argparse
import json
import platform
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Sequence

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN import common_guards as cg


TARGET_BASES = ("EURUSD", "GBPUSD", "XAUUSD", "DAX40", "US500")
ALIAS_BASES: Dict[str, Sequence[str]] = {
    "EURUSD": ("EURUSD",),
    "GBPUSD": ("GBPUSD",),
    "XAUUSD": ("XAUUSD", "GOLD"),
    "DAX40": ("DAX40", "DE40", "DE30", "GER40", "GER30"),
    "US500": ("US500", "SPX500"),
}
SAFE_SYMBOL_FIELDS = (
    "name",
    "path",
    "visible",
    "select",
    "trade_mode",
    "trade_calc_mode",
    "digits",
    "spread",
    "currency_base",
    "currency_profit",
    "currency_margin",
)
SAFE_TERMINAL_FIELDS = (
    "name",
    "company",
    "connected",
    "trade_allowed",
    "tradeapi_disabled",
)


def now_id() -> str:
    return time.strftime("%Y%m%d_%H%M%S", time.gmtime())


def _norm(value: str) -> str:
    return str(value or "").strip().upper()


def _symbol_matches_alias(symbol_name: str, alias_base: str) -> bool:
    sym = _norm(symbol_name)
    alias = _norm(alias_base)
    return bool(sym == alias or sym.startswith(alias + "."))


def resolve_target_hits(symbol_names: Sequence[str]) -> Dict[str, List[str]]:
    hits: Dict[str, List[str]] = {}
    norm_names = [_norm(x) for x in symbol_names if _norm(x)]
    for target in TARGET_BASES:
        out: List[str] = []
        for sym in norm_names:
            if any(_symbol_matches_alias(sym, alias) for alias in ALIAS_BASES.get(target, (target,))):
                out.append(sym)
        hits[target] = sorted(set(out))
    return hits


def slim_symbol_row(sym: object) -> Dict[str, Any]:
    row: Dict[str, Any] = {}
    for key in SAFE_SYMBOL_FIELDS:
        if hasattr(sym, key):
            row[key] = getattr(sym, key)
    row["name"] = _norm(str(row.get("name", "")))
    return row


def _safe_terminal_info(mt5: Any) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    try:
        info = mt5.terminal_info()
        if info is None:
            return out
        for key in SAFE_TERMINAL_FIELDS:
            if hasattr(info, key):
                out[key] = getattr(info, key)
        return out
    except Exception as exc:
        cg.tlog(None, "WARN", "SYMAUD_EXC", "terminal_info() failed", exc)
        return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mt5-path", required=True, help="Path to terminal64.exe (OANDA TMS MT5 Terminal)")
    ap.add_argument("--group", default="", help="Optional symbols_get(group=...) filter")
    ap.add_argument("--limit", type=int, default=0, help="Save only first N symbols in report (0 = all)")
    ap.add_argument("--strict", action="store_true", help="Return non-zero if any target base is missing")
    ap.add_argument(
        "--offline-sim",
        action="store_true",
        help="Offline simulation mode: return DO_WERYFIKACJI_ONLINE instead of FAIL when MT5 API/live attach is unavailable.",
    )
    ap.add_argument("--out", default="", help="Optional explicit output JSON path")
    args = ap.parse_args()

    run_id = now_id()
    out = Path(args.out) if args.out else (ROOT / "EVIDENCE" / "symbols_get_audit" / f"{run_id}_symbols_get_audit.json")
    out.parent.mkdir(parents=True, exist_ok=True)

    report: Dict[str, Any] = {
        "schema_version": 1,
        "run_id": run_id,
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "mode": "mt5_symbols_get_audit_windows",
        "mt5_path": args.mt5_path,
        "group_filter": args.group,
        "strict_mode": bool(args.strict),
        "result": "SKIP",
        "details": {},
        "error": None,
    }

    if platform.system().lower() != "windows":
        report["result"] = "DO_WERYFIKACJI_ONLINE"
        report["error"] = "Not running on Windows - cannot attach to MT5 terminal here."
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 0

    try:
        import MetaTrader5 as mt5
    except Exception as exc:
        cg.tlog(None, "WARN", "SYMAUD_EXC", "Import MetaTrader5 failed", exc)
        if bool(args.offline_sim):
            report["result"] = "DO_WERYFIKACJI_ONLINE"
            report["error"] = f"Offline sim: MetaTrader5 unavailable: {exc}"
            out.write_text(json.dumps(report, indent=2), encoding="utf-8")
            return 0
        report["result"] = "FAIL"
        report["error"] = f"Import MetaTrader5 failed: {exc}"
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 1

    try:
        ok = mt5.initialize(args.mt5_path)
        if not ok:
            if bool(args.offline_sim):
                report["result"] = "DO_WERYFIKACJI_ONLINE"
                report["error"] = f"Offline sim: mt5.initialize=False, last_error={mt5.last_error()!r}"
                out.write_text(json.dumps(report, indent=2), encoding="utf-8")
                return 0
            report["result"] = "FAIL"
            report["error"] = f"mt5.initialize returned False, last_error={mt5.last_error()!r}"
            out.write_text(json.dumps(report, indent=2), encoding="utf-8")
            return 2

        symbols = mt5.symbols_get(group=args.group) if str(args.group or "").strip() else mt5.symbols_get()
        if symbols is None:
            if bool(args.offline_sim):
                report["result"] = "DO_WERYFIKACJI_ONLINE"
                report["error"] = f"Offline sim: mt5.symbols_get=None, last_error={mt5.last_error()!r}"
                out.write_text(json.dumps(report, indent=2), encoding="utf-8")
                return 0
            report["result"] = "FAIL"
            report["error"] = f"mt5.symbols_get returned None, last_error={mt5.last_error()!r}"
            out.write_text(json.dumps(report, indent=2), encoding="utf-8")
            return 3

        rows = [slim_symbol_row(sym) for sym in symbols]
        names = [str(r.get("name", "")) for r in rows if str(r.get("name", "")).strip()]
        visible_count = sum(1 for r in rows if bool(r.get("visible", False)))
        selected_count = sum(1 for r in rows if bool(r.get("select", False)))

        hits = resolve_target_hits(names)
        missing = sorted([base for base in TARGET_BASES if not hits.get(base)])

        payload_rows = rows
        if int(args.limit) > 0:
            payload_rows = rows[: int(args.limit)]

        report["details"] = {
            "version": mt5.version(),
            "terminal_info": _safe_terminal_info(mt5),
            "symbols_total": len(rows),
            "symbols_visible": int(visible_count),
            "symbols_selected": int(selected_count),
            "target_bases": list(TARGET_BASES),
            "alias_bases": {k: list(v) for k, v in ALIAS_BASES.items()},
            "target_hits": hits,
            "target_missing": missing,
            "symbols_saved": len(payload_rows),
            "symbols": payload_rows,
        }

        report["result"] = "PASS" if not missing else "WARN_MISSING_TARGETS"
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")

        if missing and bool(args.strict):
            return 4
        return 0
    except Exception as exc:
        cg.tlog(None, "WARN", "SYMAUD_EXC", "nonfatal exception swallowed", exc)
        report["result"] = "FAIL"
        report["error"] = str(exc)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 5
    finally:
        try:
            mt5.shutdown()
        except Exception as exc:
            cg.tlog(None, "WARN", "SYMAUD_EXC", "mt5.shutdown() failed", exc)


if __name__ == "__main__":
    raise SystemExit(main())
