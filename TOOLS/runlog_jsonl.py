#!/usr/bin/env python3
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def generate_run_id(prefix: str = "run") -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    token = uuid.uuid4().hex[:8]
    return f"{prefix}_{stamp}_{token}"


def append_event(path: Path, event: str, run_id: str, **fields: Any) -> Dict[str, Any]:
    record: Dict[str, Any] = {
        "ts_utc": utc_now_iso(),
        "event": str(event),
        "run_id": str(run_id),
    }
    record.update(fields)

    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("a", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
    return record
