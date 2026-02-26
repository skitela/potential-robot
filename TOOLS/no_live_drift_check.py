#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate deterministic no-live-drift evidence for hard live canary."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List

_INDEX_BASES = {"JP225", "US500", "US100", "US30", "DE40", "DE30", "EU50"}
_CRYPTO_HINTS = ("BTC", "ETH", "XRP", "LTC")
_METAL_HINTS = ("XAU", "XAG", "GOLD", "SILVER")


def utc_now_z() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _norm_symbol(s: str) -> str:
    raw = str(s or "").strip()
    if not raw:
        return ""
    if "." in raw:
        b, x = raw.split(".", 1)
        b = str(b).strip().upper()
        x = str(x).strip().lower()
        return f"{b}.{x}" if x else b
    return raw.upper()


def _symbol_base(s: str) -> str:
    raw = _norm_symbol(s)
    if "." in raw:
        return raw.split(".", 1)[0]
    return raw


def _infer_group(base: str) -> str:
    b = _symbol_base(base)
    if not b:
        return "UNKNOWN"
    if any(h in b for h in _METAL_HINTS):
        return "METAL"
    if b in _INDEX_BASES:
        return "INDEX"
    if any(h in b for h in _CRYPTO_HINTS):
        return "CRYPTO"
    # Typical FX symbol format, e.g. EURUSD, USDJPY, AUDJPY.
    if len(b) == 6 and b.isalpha():
        return "FX"
    return "UNKNOWN"


def _load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        return None


def _load_strategy(path: Path) -> Dict[str, object]:
    obj = _load_json(path)
    return obj if isinstance(obj, dict) else {}


def main() -> int:
    ap = argparse.ArgumentParser(description="No live drift check")
    ap.add_argument("--root", default=".", help="Repo/runtime root")
    ap.add_argument("--strategy", default="CONFIG/strategy.json", help="Strategy config path")
    ap.add_argument("--preflight", default="EVIDENCE/asia_symbol_preflight.json", help="Asia preflight evidence")
    ap.add_argument("--out", default="EVIDENCE/no_live_drift_check.json", help="Output JSON path")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    strategy = _load_strategy((root / args.strategy).resolve())
    preflight_obj = _load_json((root / args.preflight).resolve())

    live_canary_enabled = bool(strategy.get("live_canary_enabled", False))
    module_map = strategy.get("module_live_enabled_map") if isinstance(strategy.get("module_live_enabled_map"), dict) else {}
    allowed_groups = [str(x).strip().upper() for x in (strategy.get("live_canary_allowed_groups") or []) if str(x).strip()]
    allowed_intents = [_symbol_base(str(x)) for x in (strategy.get("live_canary_allowed_symbol_intents") or []) if str(x).strip()]
    hard_groups = [str(x).strip().upper() for x in (strategy.get("hard_live_disabled_groups") or []) if str(x).strip()]
    hard_symbols = [_symbol_base(str(x)) for x in (strategy.get("hard_live_disabled_symbol_intents") or []) if str(x).strip()]
    symbol_group_map = strategy.get("symbol_group_map") if isinstance(strategy.get("symbol_group_map"), dict) else {}

    preflight_rows: List[Dict[str, object]] = []
    if isinstance(preflight_obj, dict) and isinstance(preflight_obj.get("rows"), list):
        preflight_rows = [dict(r) for r in preflight_obj.get("rows") if isinstance(r, dict)]

    out_rows: List[Dict[str, object]] = []
    for row in preflight_rows:
        canon = _norm_symbol(str(row.get("canonical_symbol") or row.get("raw_symbol") or ""))
        base = _symbol_base(canon)
        grp = str(symbol_group_map.get(base, "")).strip().upper()
        if not grp:
            grp = _infer_group(base)
        module_live = bool(module_map.get(grp, False))
        reason = "NONE"
        enabled = True
        if not live_canary_enabled:
            enabled = False
            reason = "LIVE_CANARY_DISABLED"
        elif grp in hard_groups:
            enabled = False
            reason = "HARD_LIVE_DISABLED_GROUP"
        elif base in hard_symbols:
            enabled = False
            reason = "HARD_LIVE_DISABLED_SYMBOL"
        elif allowed_groups and grp not in allowed_groups:
            enabled = False
            reason = "GROUP_NOT_IN_WAVE1"
        elif not module_live:
            enabled = False
            reason = "MODULE_LIVE_DISABLED"
        elif allowed_intents and base not in allowed_intents:
            enabled = False
            reason = "SYMBOL_NOT_IN_WAVE1"
        elif not bool(row.get("preflight_ok", False)):
            enabled = False
            reason = "ASIA_PREFLIGHT_BLOCK"
        out_rows.append(
            {
                "symbol_canonical": canon,
                "group": grp,
                "module_live_enabled": module_live,
                "symbol_live_enabled": bool(enabled),
                "reason_code": reason,
                "preflight_ok": bool(row.get("preflight_ok", False)),
            }
        )

    payload = {
        "schema_version": "HL.A1.tool",
        "ts_utc": utc_now_z(),
        "timestamp_semantics": "UTC",
        "live_canary_enabled": live_canary_enabled,
        "module_live_enabled_map": module_map,
        "live_canary_allowed_groups": allowed_groups,
        "live_canary_allowed_symbols": allowed_intents,
        "hard_live_disabled_groups": hard_groups,
        "hard_live_disabled_symbols": hard_symbols,
        "rows": out_rows,
    }

    out_path = (root / args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": "OK", "out": str(out_path), "rows": len(out_rows)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
