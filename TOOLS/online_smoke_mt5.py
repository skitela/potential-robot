# -*- coding: utf-8 -*-
r"""
online_smoke_mt5.py — ONLINE_SMOKE (Windows) for OANDA_MT5_SYSTEM V6.2

Goal:
- Verify that Python can attach to the expected MetaTrader 5 terminal (OANDA TMS MT5) via the official MetaTrader5 Python package.
- Collect minimal, non-price evidence (version + terminal_info metadata) for audit.
- NO trading, NO symbols/ticks, NO orders.

Usage (Windows):
    python -B TOOLS/online_smoke_mt5.py --mt5-path "C:\\Program Files\\OANDA TMS MT5 Terminal\\terminal64.exe"

Evidence:
  EVIDENCE/online_smoke/<run_id>_mt5_smoke.json
"""
from __future__ import annotations

import argparse
import json
import os
import platform
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN import common_guards as cg

def now_id() -> str:
    return time.strftime("%Y%m%d_%H%M%S", time.gmtime())

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mt5-path", required=True, help="Path to terminal64.exe (OANDA TMS MT5 Terminal)")
    ap.add_argument("--out", default="", help="Optional explicit output JSON path")
    args = ap.parse_args()

    run_id = now_id()
    root = Path(__file__).resolve().parents[1]
    out = Path(args.out) if args.out else (root / "EVIDENCE" / "online_smoke" / f"{run_id}_mt5_smoke.json")
    out.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "schema_version": 1,
        "run_id": run_id,
        "ts_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "mode": "online_smoke_windows",
        "mt5_path": args.mt5_path,
        "platform": {"system": platform.system(), "release": platform.release(), "python": sys.version},
        "result": "SKIP",
        "details": {},
        "error": None,
    }

    if platform.system().lower() != "windows":
        report["result"] = "DO_WERYFIKACJI_ONLINE"
        report["error"] = "Not running on Windows — cannot attach to MT5 terminal here."
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 0

    # Import MetaTrader5
    try:
        import MetaTrader5 as mt5
    except Exception as e:
        cg.tlog(None, "WARN", "SMOKE_EXC", "nonfatal exception swallowed", e)
        report["result"] = "FAIL"
        report["error"] = f"Import MetaTrader5 failed: {e}"
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 1

    # Initialize (attach) — official API supports passing terminal path. See MQL5 docs.
    try:
        ok = mt5.initialize(args.mt5_path)
        if not ok:
            report["result"] = "FAIL"
            report["error"] = f"mt5.initialize returned False, last_error={mt5.last_error()!r}"
            out.write_text(json.dumps(report, indent=2), encoding="utf-8")
            return 2

        # Minimal non-price checks
        report["details"]["version"] = mt5.version()
        ti = mt5.terminal_info()
        if ti is not None:
            # terminal_info is a namedtuple; store only safe fields (no prices exist there).
            safe = {}
            for k in ("name", "company", "community_account", "community_connection", "connected", "trade_allowed", "tradeapi_disabled"):
                if hasattr(ti, k):
                    safe[k] = getattr(ti, k)
            report["details"]["terminal_info"] = safe

        report["result"] = "PASS"
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 0
    except Exception as e:
        cg.tlog(None, "WARN", "SMOKE_EXC", "nonfatal exception swallowed", e)
        report["result"] = "FAIL"
        report["error"] = str(e)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 3
    finally:
        try:
            mt5.shutdown()
        except Exception as e:
            cg.tlog(None, "WARN", "SMOKE_EXC", "mt5.shutdown() failed", e)

if __name__ == "__main__":
    raise SystemExit(main())
