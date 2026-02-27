from __future__ import annotations

from typing import Iterable

from ..common.contracts import EventRecord
from ..common.validators import DataContractValidator


def check_data_contracts(events: Iterable[EventRecord], validator: DataContractValidator) -> dict[str, object]:
    issues: list[str] = []
    checked = 0
    for event in events:
        checked += 1
        issues.extend(validator.validate_event(event))
    return {"checked_events": checked, "issues": sorted(set(issues))}

