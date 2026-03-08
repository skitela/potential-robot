from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Optional, Tuple


VALID_TRADE_TRIGGER_MODES = {"BRIDGE_ACTIVE", "MQL5_SHADOW_COMPARE", "MQL5_ACTIVE"}


def resolve_trade_trigger_mode(
    requested_mode: Any,
    *,
    allow_mql5_active: bool = False,
) -> Tuple[str, str]:
    mode = str(requested_mode or "BRIDGE_ACTIVE").strip().upper()
    if mode not in VALID_TRADE_TRIGGER_MODES:
        return "BRIDGE_ACTIVE", "INVALID_MODE"
    if mode == "MQL5_ACTIVE" and not allow_mql5_active:
        return "MQL5_SHADOW_COMPARE", "MQL5_ACTIVE_NOT_CUTOVER_READY"
    return mode, "OK"


def build_mt5_common_file_path(
    *,
    enabled: bool,
    subdir: str,
    file_name: str,
    appdata: Optional[str] = None,
) -> Optional[Path]:
    if not enabled:
        return None
    base = str(appdata or os.environ.get("APPDATA") or "").strip()
    if not base:
        return None
    norm_subdir = str(subdir or "OANDA_MT5_SYSTEM").strip() or "OANDA_MT5_SYSTEM"
    norm_name = str(file_name or "").strip()
    if not norm_name:
        return None
    return Path(base) / "MetaQuotes" / "Terminal" / "Common" / "Files" / norm_subdir / norm_name


def should_emit_interval(*, now_ts: float, last_ts: float, interval_s: int) -> bool:
    safe_interval = max(1, int(interval_s))
    return (float(now_ts) - float(last_ts)) >= float(safe_interval)
