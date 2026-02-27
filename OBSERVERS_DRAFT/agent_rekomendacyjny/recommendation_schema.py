from __future__ import annotations

from dataclasses import dataclass


@dataclass(slots=True)
class RecommendationItem:
    problem: str
    evidence: str
    impact: str
    risk: str
    scope: str
    requires_codex: bool
    verify_after_change: str

