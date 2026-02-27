from __future__ import annotations

from typing import Any


def separate_signal_vs_execution_vs_regime_effects(metrics: dict[str, Any]) -> dict[str, Any]:
    block_dist = metrics.get("block_reason_distribution", {})
    quality = metrics.get("execution_quality_by_symbol", {})
    return {
        "signal_layer_notes": "No strategy inference in draft; signal-vs-regime analysis requires richer labeled events.",
        "execution_layer": {
            "symbols_with_rejects": [s for s, v in quality.items() if int(v.get("rejected", 0)) > 0],
            "reject_block_reasons": block_dist,
        },
        "regime_layer_notes": "Regime impact marked UNKNOWN in draft until direct regime tags are mapped.",
    }


def generate_rd_hypotheses(metrics: dict[str, Any], diagnosis: dict[str, Any]) -> list[dict[str, str]]:
    hypotheses: list[dict[str, str]] = []
    if diagnosis.get("execution_layer", {}).get("symbols_with_rejects"):
        hypotheses.append(
            {
                "type": "EXECUTION_QUALITY",
                "statement": "Review transport/guard path for symbols with repeated rejects.",
            }
        )
    if not metrics.get("pnl_net_by_symbol"):
        hypotheses.append(
            {
                "type": "DATA_COVERAGE",
                "statement": "Persisted TRADE_CLOSED with pnl_net is sparse; improve reporting coverage before deeper R&D claims.",
            }
        )
    return hypotheses

