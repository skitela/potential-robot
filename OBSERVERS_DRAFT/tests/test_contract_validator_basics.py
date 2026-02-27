from __future__ import annotations

import unittest

from OBSERVERS_DRAFT.common.contracts import EventRecord
from OBSERVERS_DRAFT.common.validators import DataContractValidator


class TestContractValidatorBasics(unittest.TestCase):
    def test_missing_reason_code_for_entry_block(self) -> None:
        event = EventRecord(
            event_type="ENTRY_BLOCK_COST",
            timestamp_utc="2026-02-27T00:00:00Z",
            timestamp_semantics="UTC",
            source="LOGS/audit_trail.jsonl",
            symbol_raw="USDJPY",
            symbol_canonical="USDJPY.pro",
            reason_code=None,
            payload={},
        )
        issues = DataContractValidator().validate_event(event)
        self.assertIn("MISSING_REASON_CODE_FOR_ENTRY_BLOCK", issues)

    def test_invalid_timestamp_semantics(self) -> None:
        event = EventRecord(
            event_type="ENTRY_BLOCK_COST",
            timestamp_utc="2026-02-27T00:00:00Z",
            timestamp_semantics="LOCAL_TIME",
            source="LOGS/audit_trail.jsonl",
            symbol_raw="USDJPY",
            symbol_canonical=None,
            reason_code="BLOCK_TRADE_COST",
            payload={},
        )
        issues = DataContractValidator().validate_event(event)
        self.assertIn("INVALID_TIMESTAMP_SEMANTICS", issues)
        self.assertIn("MISSING_SYMBOL_CANONICAL", issues)

