# -*- coding: utf-8 -*-
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

try:
    from .runtime_root import get_runtime_root
except Exception:  # pragma: no cover
    from runtime_root import get_runtime_root

SCOPE_SCHEMA = "oanda_mt5.free_window_tuning_scope.v1"
SCOPE_FILE_NAME = "free_window_tuning_scope_v1.json"


def _symbol_base(raw: Any) -> str:
    s = str(raw or "").strip().upper()
    if not s:
        return ""
    if s.endswith(".PRO"):
        s = s[:-4]
    for sep in ("-", "_"):
        if sep in s and s not in {"US500", "DE30"}:
            s = s.split(sep, 1)[0]
    return s


def _safe_load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _normalize_symbol_list(rows: Any) -> List[str]:
    if not isinstance(rows, list):
        return []
    out: List[str] = []
    seen = set()
    for item in rows:
        sym = _symbol_base(item)
        if not sym or sym in seen:
            continue
        seen.add(sym)
        out.append(sym)
    return out


def _normalize_window_list(rows: Any) -> List[str]:
    if not isinstance(rows, list):
        return []
    out: List[str] = []
    seen = set()
    for item in rows:
        wid = str(item or "").strip().upper()
        if not wid or wid in seen:
            continue
        seen.add(wid)
        out.append(wid)
    return out


def load_training_scope(root: Optional[Path] = None) -> Dict[str, Any]:
    root_path = Path(root).resolve() if root is not None else get_runtime_root(enforce=True)
    path = (root_path / "CONFIG" / SCOPE_FILE_NAME).resolve()
    payload = _safe_load_json(path)

    active = _normalize_symbol_list(payload.get("active_symbols"))
    secondary = _normalize_symbol_list(payload.get("secondary_symbols"))
    shadow = _normalize_symbol_list(payload.get("shadow_only_symbols"))
    windows_raw = payload.get("windows_by_symbol") if isinstance(payload.get("windows_by_symbol"), dict) else {}
    allowed = []
    seen = set()
    for sym in active + secondary + shadow + _normalize_symbol_list(payload.get("allowed_symbols")):
        if sym in seen:
            continue
        seen.add(sym)
        allowed.append(sym)

    windows_by_symbol: Dict[str, Dict[str, List[str]]] = {}
    for raw_sym, raw_row in windows_raw.items():
        sym = _symbol_base(raw_sym)
        if not sym or not isinstance(raw_row, dict):
            continue
        windows_by_symbol[sym] = {
            "active_window_ids": _normalize_window_list(raw_row.get("active_window_ids")),
            "legacy_window_ids": _normalize_window_list(raw_row.get("legacy_window_ids")),
        }

    return {
        "schema": str(payload.get("schema") or SCOPE_SCHEMA),
        "path": str(path),
        "exists": bool(path.exists()),
        "enabled": bool(payload.get("enabled", True)),
        "strict_symbol_scope": bool(payload.get("strict_symbol_scope", True)),
        "strict_window_scope": bool(payload.get("strict_window_scope", False)),
        "active_symbols": active,
        "secondary_symbols": secondary,
        "shadow_only_symbols": shadow,
        "allowed_symbols": allowed,
        "windows_by_symbol": windows_by_symbol,
        "notes": list(payload.get("notes") or []) if isinstance(payload.get("notes"), list) else [],
    }


def is_scope_enabled(scope: Optional[Dict[str, Any]]) -> bool:
    return bool((scope or {}).get("enabled", False)) and bool((scope or {}).get("strict_symbol_scope", True))


def symbol_in_scope(scope: Optional[Dict[str, Any]], symbol: Any) -> bool:
    if not is_scope_enabled(scope):
        return True
    sym = _symbol_base(symbol)
    if not sym:
        return False
    return sym in set((scope or {}).get("allowed_symbols") or [])


def window_in_scope(scope: Optional[Dict[str, Any]], symbol: Any, window_id: Any) -> bool:
    scope_obj = scope or {}
    if not (bool(scope_obj.get("enabled", False)) and bool(scope_obj.get("strict_window_scope", False))):
        return True
    sym = _symbol_base(symbol)
    wid = str(window_id or "").strip().upper()
    if not sym:
        return False
    per_symbol = scope_obj.get("windows_by_symbol") if isinstance(scope_obj.get("windows_by_symbol"), dict) else {}
    row = per_symbol.get(sym) if isinstance(per_symbol.get(sym), dict) else {}
    allowed_windows = []
    for key in ("active_window_ids", "legacy_window_ids"):
        for item in list(row.get(key) or []):
            item_norm = str(item or "").strip().upper()
            if item_norm and item_norm not in allowed_windows:
                allowed_windows.append(item_norm)
    if not allowed_windows:
        return True
    if not wid:
        return False
    return wid in set(allowed_windows)


def row_in_scope(
    scope: Optional[Dict[str, Any]],
    row: Dict[str, Any],
    *,
    symbol_key: str = "symbol",
    window_key: Optional[str] = None,
) -> bool:
    if not isinstance(row, dict):
        return False
    sym = row.get(symbol_key)
    if not symbol_in_scope(scope, sym):
        return False
    if window_key:
        return window_in_scope(scope, sym, row.get(window_key))
    return True


def filter_rows_by_scope(
    rows: Iterable[Dict[str, Any]],
    scope: Optional[Dict[str, Any]],
    *,
    symbol_key: str = "symbol",
    window_key: Optional[str] = None,
) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for row in rows:
        if row_in_scope(scope, row, symbol_key=symbol_key, window_key=window_key):
            out.append(row)
    return out


def scope_summary(scope: Optional[Dict[str, Any]], *, rows_before: int = 0, rows_after: int = 0) -> Dict[str, Any]:
    scope_obj = scope or {}
    return {
        "enabled": bool(scope_obj.get("enabled", False)),
        "strict_symbol_scope": bool(scope_obj.get("strict_symbol_scope", True)),
        "strict_window_scope": bool(scope_obj.get("strict_window_scope", False)),
        "active_symbols": list(scope_obj.get("active_symbols") or []),
        "secondary_symbols": list(scope_obj.get("secondary_symbols") or []),
        "shadow_only_symbols": list(scope_obj.get("shadow_only_symbols") or []),
        "allowed_symbols": list(scope_obj.get("allowed_symbols") or []),
        "windows_by_symbol": dict(scope_obj.get("windows_by_symbol") or {}),
        "rows_before": int(rows_before),
        "rows_after": int(rows_after),
        "rows_dropped": int(max(0, int(rows_before) - int(rows_after))),
        "config_path": str(scope_obj.get("path") or ""),
    }
