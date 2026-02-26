#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate deterministic Asia preflight evidence from local runtime artifacts.
No strategy logic changes.
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

DEFAULT_INTENTS = ["USDJPY", "EURJPY", "AUDJPY", "NZDJPY", "JP225", "GOLD"]


def utc_now_z() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def canonical_symbol(symbol: str) -> str:
    raw = str(symbol or "").strip()
    if not raw:
        return ""
    if "." in raw:
        base, suffix = raw.split(".", 1)
        base_u = str(base).strip().upper()
        suf_l = str(suffix).strip().lower()
        return f"{base_u}.{suf_l}" if suf_l else base_u
    return raw.upper()


def _load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(obj, dict):
            return obj
    except Exception:
        return {}
    return {}


def _index_symbols(rows: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        if not name:
            continue
        out[name.upper()] = row
    return out


def _candidates(intent: str) -> List[str]:
    b = str(intent or "").strip().upper()
    if not b:
        return []
    if b == "GOLD":
        return ["GOLD.pro", "GOLD", "XAUUSD.pro", "XAUUSD"]
    if b == "SILVER":
        return ["SILVER.pro", "SILVER", "XAGUSD.pro", "XAGUSD"]
    return [f"{b}.pro", b, f"{b}.PRO"]


def _resolve_intent(intent: str, idx: Dict[str, Dict[str, Any]]) -> Tuple[str, Dict[str, Any] | None]:
    for cand in _candidates(intent):
        row = idx.get(cand.upper())
        if row is not None:
            return cand, row
    return "", None


def _trade_mode_name(mode: Any) -> str:
    try:
        m = int(mode)
    except Exception:
        return "UNKNOWN"
    if m == 0:
        return "DISABLED"
    if m == 1:
        return "LONGONLY"
    if m == 2:
        return "SHORTONLY"
    if m == 3:
        return "CLOSEONLY"
    if m == 4:
        return "FULL"
    return "UNKNOWN"


def generate(root: Path, out_path: Path, intents: List[str]) -> Dict[str, Any]:
    src = root / "RUN" / "symbols_audit_now.json"
    audit = _load_json(src)
    details = ((audit.get("details") or {}) if isinstance(audit, dict) else {})
    rows = details.get("symbols") if isinstance(details, dict) else []
    if not isinstance(rows, list):
        rows = []
    idx = _index_symbols([r for r in rows if isinstance(r, dict)])

    out_rows: List[Dict[str, Any]] = []
    for intent in intents:
        picked_name, picked_row = _resolve_intent(intent, idx)
        exists = picked_row is not None
        selected = bool((picked_row or {}).get("select", False)) if exists else False
        visible = bool((picked_row or {}).get("visible", False)) if exists else False
        trade_mode = _trade_mode_name((picked_row or {}).get("trade_mode", -1)) if exists else "UNKNOWN"
        fail_reason = ""
        if not exists:
            fail_reason = "NOT_FOUND_IN_SYMBOL_AUDIT"
        elif not selected:
            fail_reason = "NOT_SELECTED"
        elif not visible:
            fail_reason = "NOT_VISIBLE"
        elif trade_mode not in {"FULL", "LONGONLY", "SHORTONLY"}:
            fail_reason = f"TRADE_MODE_{trade_mode}"
        preflight_ok = bool(exists and selected and visible and trade_mode in {"FULL", "LONGONLY", "SHORTONLY"})
        out_rows.append(
            {
                "alias_intent": str(intent),
                "raw_symbol": str(intent),
                "canonical_symbol": str(picked_name or ""),
                "canonical_symbol_norm": canonical_symbol(picked_name),
                "exists": bool(exists),
                "selected": bool(selected),
                "visible": bool(visible),
                "tradable": str(trade_mode),
                "session_info_available": "UNKNOWN",
                "symbol_select_attempted": False,
                "symbol_select_result": "UNKNOWN",
                "preflight_ok": bool(preflight_ok),
                "fail_reason": str(fail_reason),
                "source": "RUN/symbols_audit_now.json",
                "confidence": ("HIGH" if exists else "LOW"),
            }
        )

    payload = {
        "schema_version": "2R.A1",
        "ts_utc": utc_now_z(),
        "timestamp_semantics": "UTC",
        "timezone_basis": "UTC",
        "source_list": ["RUN/symbols_audit_now.json"],
        "method": "artifact_preflight",
        "sample_size_n": int(len(out_rows)),
        "low_stat_power": bool(len(out_rows) < 5),
        "rows": out_rows,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def main() -> int:
    ap = argparse.ArgumentParser(description="Generate Asia preflight evidence artifact.")
    ap.add_argument("--root", default=".", help="Repo root")
    ap.add_argument("--out", default="EVIDENCE/asia_symbol_preflight.json", help="Output JSON path")
    ap.add_argument("--intents", nargs="*", default=DEFAULT_INTENTS, help="Alias intents to evaluate")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    out_path = (root / args.out).resolve()
    intents = [str(x).strip().upper() for x in (args.intents or []) if str(x).strip()]
    if not intents:
        intents = list(DEFAULT_INTENTS)
    payload = generate(root, out_path, intents)
    print(json.dumps({
        "status": "OK",
        "out": str(out_path),
        "sample_size_n": payload.get("sample_size_n"),
        "low_stat_power": payload.get("low_stat_power"),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
