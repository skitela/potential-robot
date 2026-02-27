from __future__ import annotations

from typing import Any


def prioritize_recommendations(issue_catalog: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # Deterministic: HIGH first, then MED, then LOW. Stable sort by title.
    weight = {"HIGH": 3, "MED": 2, "LOW": 1}
    return sorted(
        issue_catalog,
        key=lambda x: (-weight.get(str(x.get("priority", "LOW")).upper(), 1), str(x.get("problem", ""))),
    )

