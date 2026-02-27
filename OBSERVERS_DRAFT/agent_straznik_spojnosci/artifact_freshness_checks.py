from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def check_artifact_freshness(paths: list[Path], stale_after_sec: int = 900) -> dict[str, Any]:
    now = datetime.now(timezone.utc).timestamp()
    findings: list[dict[str, Any]] = []
    stale_count = 0
    for path in paths:
        if not path.exists():
            findings.append({"path": str(path), "status": "MISSING", "age_sec": "UNKNOWN"})
            stale_count += 1
            continue
        age = now - path.stat().st_mtime
        status = "STALE_OR_INCOMPLETE" if age > stale_after_sec else "OK"
        if status != "OK":
            stale_count += 1
        findings.append({"path": str(path), "status": status, "age_sec": round(age, 3)})
    return {"stale_count": stale_count, "total": len(findings), "findings": findings}

