#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from BIN.kernel_config_plane import build_kernel_config_payload


def utc_iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".tmp_kernel_config_", suffix=".json", dir=str(path.parent))
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2, sort_keys=True)
            f.flush()
            os.fsync(f.fileno())
        os.replace(str(tmp_path), str(path))
    finally:
        try:
            if tmp_path.exists():
                tmp_path.unlink()
        except OSError:
            pass


def guess_group(symbol: str) -> str:
    s = str(symbol or "").strip().upper()
    if any(x in s for x in ("XAU", "XAG", "GOLD", "SILVER", "PLATIN", "PALLAD", "COPPER", "XPT", "XPD")):
        return "METAL"
    if any(x in s for x in ("US500", "US100", "US30", "EU50", "JP225", "DE40", "DAX")):
        return "INDEX"
    if any(x in s for x in ("BTC", "ETH", "LTC", "SOL", "ADA", "DOGE")):
        return "CRYPTO"
    if len(s.replace(".PRO", "")) == 6 and s.replace(".PRO", "").isalpha():
        return "FX"
    return "EQUITY"


def normalize_symbol(raw: str) -> str:
    s = str(raw or "").strip()
    if not s:
        return ""
    u = s.upper()
    if u in {"XAUUSD", "GOLD"}:
        return "GOLD.pro"
    if u in {"XAGUSD", "SILVER"}:
        return "SILVER.pro"
    if u.endswith(".PRO"):
        return u[:-4] + ".pro"
    if "." in u:
        return s
    return s + ".pro"


def build_rows_from_strategy(strategy: Dict[str, Any]) -> List[Dict[str, Any]]:
    raw_symbols = strategy.get("symbols_to_trade")
    if not isinstance(raw_symbols, list):
        raw_symbols = []

    fx_spread = float(strategy.get("fx_spread_cap_points_default", 0.0) or 0.0)
    metal_spread = float(strategy.get("metal_spread_cap_points_default", 0.0) or 0.0)

    rows: List[Dict[str, Any]] = []
    seen = set()
    for raw in raw_symbols:
        sym = normalize_symbol(str(raw))
        if not sym:
            continue
        key = sym.upper()
        if key in seen:
            continue
        seen.add(key)
        group = guess_group(sym)
        spread_cap = 0.0
        if group == "FX":
            spread_cap = fx_spread
        elif group == "METAL":
            spread_cap = metal_spread
        rows.append(
            {
                "symbol": sym,
                "group": group,
                "entry_allowed": True,
                "close_only": False,
                "halt": False,
                "reason": "PRESEED_OK",
                "spread_cap_points": max(0.0, spread_cap),
                "max_latency_ms": 0.0,
                "min_tick_rate_1s": 0,
                "min_liquidity_score": 0.0,
                "min_tradeability_score": 0.0,
                "min_setup_quality_score": 0.0,
            }
        )
    return rows


def resolve_common_path(root: Path, file_name: str) -> Path:
    appdata = os.environ.get("APPDATA")
    if not appdata:
        raise RuntimeError("APPDATA missing")
    return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files" / "OANDA_MT5_SYSTEM" / file_name


def main() -> int:
    ap = argparse.ArgumentParser(description="Preseed kernel_config_v1.json for MQL5 shadow kernel.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--file-name", default="kernel_config_v1.json")
    ap.add_argument("--out-common", default="")
    ap.add_argument("--out-meta", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    strategy_path = root / "CONFIG" / "strategy.json"
    if not strategy_path.exists():
        raise FileNotFoundError(f"Missing strategy config: {strategy_path}")

    strategy = json.loads(strategy_path.read_text(encoding="utf-8"))
    rows = build_rows_from_strategy(strategy)
    if not rows:
        raise RuntimeError("No symbols_to_trade in strategy config; cannot preseed kernel config.")

    payload = build_kernel_config_payload(
        rows,
        generated_at_utc=utc_iso_now(),
        meta={
            "source": "preseed_kernel_config",
            "rows": len(rows),
            "reason": "bootstrap_before_runtime",
        },
    )

    common_path = Path(args.out_common).resolve() if str(args.out_common).strip() else resolve_common_path(root, args.file_name)
    meta_path = Path(args.out_meta).resolve() if str(args.out_meta).strip() else (root / "META" / args.file_name).resolve()

    atomic_write_json(common_path, payload)
    atomic_write_json(meta_path, payload)

    print(
        "PRESEED_KERNEL_CONFIG_OK "
        f"rows={len(rows)} "
        f"hash={payload.get('config_hash')} "
        f"common={common_path} "
        f"meta={meta_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
