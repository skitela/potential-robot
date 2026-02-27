from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any

from ..common.contracts import EventRecord


def calc_block_reason_distribution(events: list[EventRecord]) -> dict[str, int]:
    c = Counter()
    for e in events:
        if e.event_type.startswith("ENTRY_BLOCK_") and e.reason_code:
            c[e.reason_code] += 1
    return dict(c)


def calc_execution_quality(events: list[EventRecord]) -> dict[str, Any]:
    by_symbol: dict[str, dict[str, int]] = defaultdict(lambda: {"executed": 0, "rejected": 0})
    for e in events:
        symbol = e.symbol_canonical or e.symbol_raw or "UNKNOWN"
        if e.event_type in {"ORDER_EXECUTED", "TRADE_RETCODE_DONE"}:
            by_symbol[symbol]["executed"] += 1
        if e.event_type in {"ORDER_REJECTED", "HYBRID_DISPATCH_REJECT"}:
            by_symbol[symbol]["rejected"] += 1
    return by_symbol


def calc_pnl_net_by_symbol(events: list[EventRecord]) -> dict[str, float]:
    pnl: dict[str, float] = defaultdict(float)
    for e in events:
        symbol = e.symbol_canonical or e.symbol_raw or "UNKNOWN"
        if e.event_type == "TRADE_CLOSED":
            net = float(e.payload.get("pnl_net", 0.0) or 0.0)
            pnl[symbol] += net
    return dict(pnl)

