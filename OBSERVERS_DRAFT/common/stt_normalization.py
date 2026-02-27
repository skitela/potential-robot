from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class NormalizationRule:
    source: str
    target: str


STT_NORMALIZATION_RULES: tuple[NormalizationRule, ...] = (
    NormalizationRule("honda mt5 system", "OANDA_MT5_SYSTEM"),
    NormalizationRule("oranda", "OANDA"),
    NormalizationRule("zaphotybot", "SafetyBot"),
    NormalizationRule("kodex", "Codex"),
    NormalizationRule("kodeks", "Codex"),
    NormalizationRule("kodowiec", "Codex"),
    NormalizationRule("lqm5", "MQL5"),
)


def normalize_stt_term(text: str) -> str:
    """Normalize common STT variants using explicit, deterministic rules."""
    out = text
    lowered = text.lower()
    for rule in STT_NORMALIZATION_RULES:
        if rule.source in lowered:
            out = out.replace(rule.source, rule.target)
            out = out.replace(rule.source.title(), rule.target)
            out = out.replace(rule.source.upper(), rule.target)
    return out

