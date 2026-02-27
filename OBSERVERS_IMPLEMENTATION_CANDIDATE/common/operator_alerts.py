from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any


def should_popup_alert(payload: dict[str, Any]) -> bool:
    severity = str(payload.get("severity", "")).upper()
    return severity == "HIGH"


def extract_alert_summary(payload: dict[str, Any]) -> str:
    parts: list[str] = []
    for key in ("type", "summary", "severity"):
        value = payload.get(key)
        if value:
            parts.append(f"{key}={value}")
    if not parts:
        return "HIGH alert detected (details in alerts JSON)."
    return " | ".join(parts)


def alert_identity(alert_path: Path, payload: dict[str, Any]) -> str:
    base = {
        "path": str(alert_path.resolve()),
        "severity": payload.get("severity"),
        "type": payload.get("type"),
        "summary": payload.get("summary"),
        "generated_at_utc": payload.get("generated_at_utc"),
    }
    digest = hashlib.sha256(json.dumps(base, sort_keys=True).encode("utf-8")).hexdigest()
    return digest
