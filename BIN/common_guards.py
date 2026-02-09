# -*- coding: utf-8 -*-
"""
COMMON_GUARDS — shared P0 guards for OANDA_MT5 components.

Design goals:
- Deterministic (no hangs)
- Conservative: block price-like keys/values
- No substring false-positives (e.g. "mask" must NOT trigger "ask")
"""
from __future__ import annotations

import json
import logging
import re
import time
from typing import Any, Iterable, Optional, Dict, Tuple
import sys
cg = sys.modules[__name__]


# Throttled logging state (module-local).
_TLOG_LAST: Dict[Tuple[str, str], float] = {}

def tlog(logger: Optional[logging.Logger], level: str, code: str, message: str, exc: Optional[BaseException] = None,
         throttle_sec: float = 30.0, key: Optional[str] = None) -> None:
    """Throttled logger used across the project.

    Logging must never break the trading loop. This function is intentionally simple.
    """
    lg = logger or logging.getLogger("OANDA_MT5")
    lvl = (level or "WARN").upper()

    k = (key or code, (message or "")[:160])
    now = time.time()
    last = _TLOG_LAST.get(k, 0.0)
    if throttle_sec and (now - last) < float(throttle_sec):
        return
    _TLOG_LAST[k] = now

    extra = ""
    if exc is not None:
        extra = f" | exc={type(exc).__name__}:{exc}"

    line = f"{code} | {message}{extra}"

    if lvl == "DEBUG":
        lg.debug(line)
    elif lvl == "INFO":
        lg.info(line)
    elif lvl in ("WARN", "WARNING"):
        lg.warning(line)
    else:
        lg.error(line)

BANNED_TOKENS = {
    "bid","ask",
    "ohlc",
    "open","high","low","close",
    "price","prices",
    "rate","rates",
    "tick","ticks",
    "quote","quotes",
    "spread",
}

# If a segment starts with a banned token, treat it as banned too (e.g. askprice, bidpx).
# We DO NOT check "endswith" to avoid false positives like "forbid".
def _seg_is_banned(seg: str) -> bool:
    s = seg.lower()
    if s in BANNED_TOKENS:
        return True
    for tok in BANNED_TOKENS:
        if len(s) > len(tok) and s.startswith(tok):
            return True
    return False

_SEG_RE = re.compile(r"[a-z0-9]+", re.IGNORECASE)

def split_segments(s: str) -> list[str]:
    return _SEG_RE.findall(str(s).lower())

def key_has_price_like_token(key: str) -> bool:
    for seg in split_segments(key):
        if _seg_is_banned(seg):
            return True
    return False

def text_has_price_like_token(text: str) -> bool:
    # Apply the same segmentation as keys; avoids substring traps (mask/task etc.)
    for seg in split_segments(text):
        if _seg_is_banned(seg):
            return True
    return False

def contains_price_like(obj: Any) -> bool:
    """Recursive check: keys and string values for banned tokens."""
    try:
        if isinstance(obj, dict):
            for k, v in obj.items():
                if key_has_price_like_token(str(k)):
                    return True
                if contains_price_like(v):
                    return True
        elif isinstance(obj, list):
            for it in obj:
                if contains_price_like(it):
                    return True
        elif isinstance(obj, str):
            if text_has_price_like_token(obj):
                return True
    except Exception as e:
        cg.tlog(None, "WARN", "CG_EXC", "contains_price_like exception => conservative True", e)
        # Conservative
        return True
    return False


def contains_price_like_strict(obj: Any) -> None:
    """Raise ValueError if obj contains price-like keys/values (uses contains_price_like)."""
    if contains_price_like(obj):
        raise ValueError("P0_PRICE_LIKE")

def count_numeric_tokens(obj: Any) -> int:
    """Count ints/floats in nested structures; bool is NOT counted."""
    n = 0
    if isinstance(obj, dict):
        for v in obj.values():
            n += count_numeric_tokens(v)
    elif isinstance(obj, list):
        for it in obj:
            n += count_numeric_tokens(it)
    else:
        if isinstance(obj, bool):
            return 0
        if isinstance(obj, (int, float)):
            return 1
    return n

def serialize_compact(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

def guard_max_json_len(obj: Any, max_len: int = 2048) -> None:
    if len(serialize_compact(obj)) > int(max_len):
        raise ValueError(f"P0_LIMIT_JSON_LEN_GT_{max_len}")

def guard_max_numeric_tokens(obj: Any, max_tokens: int = 50) -> None:
    n = count_numeric_tokens(obj)
    if n > int(max_tokens):
        raise ValueError(f"P0_LIMIT_NUMERIC_TOKENS_GT_{max_tokens}:{n}")
