# -*- coding: utf-8 -*-
import datetime as dt
import json
import sqlite3
import tempfile
import unittest
from pathlib import Path

from TOOLS.auto_deployer_kontraktorzy_pl_v3 import (
    ContractError,
    LocalSQLiteAuditHealthProvider,
    parse_approval_payload,
    parse_proposal_pack,
)


UTC = dt.timezone.utc


class TestProposalParser(unittest.TestCase):
    def test_sample_count_falls_back_to_symbol_samples_n(self) -> None:
        payload = {
            "schema": "oanda.mt5.stage1_profile_pack.v1",
            "profiles_by_symbol": [
                {
                    "symbol": "EURUSD",
                    "samples_n": 37,
                    "profiles": {
                        "sredni": {
                            "profile_name": "SREDNI",
                            "thresholds": {
                                "spread_cap_points": 22.0,
                                "signal_score_threshold": 64.0,
                                "max_latency_ms": 900.0,
                            },
                        }
                    },
                }
            ],
        }
        pack = parse_proposal_pack(payload)
        prof = pack.instruments["EURUSD"].profiles["balanced"]
        self.assertEqual(prof.sample_count, 37)


class TestApprovalParser(unittest.TestCase):
    def test_approval_parses_override_and_skips_auto(self) -> None:
        approval = {
            "schema": "oanda.mt5.stage1_manual_approval.v1",
            "approved": True,
            "instruments": {
                "EURUSD": "BEZPIECZNY",
                "GBPUSD": "AUTO",
            },
        }
        out = parse_approval_payload(approval)
        self.assertEqual(out, {"EURUSD": "conservative"})

    def test_approval_rejects_forbidden_risk_key(self) -> None:
        approval = {
            "schema": "oanda.mt5.stage1_manual_approval.v1",
            "approved": True,
            "max_open_positions": 5,
            "instruments": {"EURUSD": "SREDNI"},
        }
        with self.assertRaises(ContractError):
            parse_approval_payload(approval)


class TestRuntimeSplitMapping(unittest.TestCase):
    def test_trade_command_type_maps_to_trade_path(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            db_path = root / "decision_events.sqlite"
            audit_path = root / "audit_trail.jsonl"

            conn = sqlite3.connect(str(db_path))
            try:
                conn.execute(
                    """
                    CREATE TABLE decision_events (
                      ts_utc TEXT,
                      outcome_pnl_net REAL,
                      choice_A TEXT
                    )
                    """
                )
                conn.execute(
                    "INSERT INTO decision_events (ts_utc, outcome_pnl_net, choice_A) VALUES (?, ?, ?)",
                    ((dt.datetime.now(tz=UTC) - dt.timedelta(minutes=5)).isoformat().replace("+00:00", "Z"), 1.25, "EURUSD"),
                )
                conn.commit()
            finally:
                conn.close()

            now = dt.datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")
            rows = [
                {"timestamp_utc": now, "event_type": "COMMAND_SENT", "data": {"command_type": "TRADE", "payload": {"symbol": "EURUSD"}}},
                {"timestamp_utc": now, "event_type": "REPLY_RECEIVED", "data": {"command_type": "TRADE", "payload": {"symbol": "EURUSD"}, "wait_ms": 123.0}},
                {"timestamp_utc": now, "event_type": "COMMAND_SENT", "data": {"command_type": "HEARTBEAT"}},
                {"timestamp_utc": now, "event_type": "COMMAND_TIMEOUT", "data": {"command_type": "HEARTBEAT", "reason": "TIMEOUT"}},
            ]
            audit_path.write_text("\n".join(json.dumps(r, ensure_ascii=False) for r in rows) + "\n", encoding="utf-8")

            provider = LocalSQLiteAuditHealthProvider(db_path=db_path, audit_path=audit_path)
            split = provider.get_runtime_health_split("EURUSD", lookback_hours=1)

            self.assertEqual(split.trade_path.sample_n, 1)
            self.assertAlmostEqual(split.trade_path.timeout_rate, 0.0, places=6)
            self.assertAlmostEqual(float(split.trade_path.p95_bridge_wait_ms or 0.0), 123.0, places=6)

            self.assertEqual(split.heartbeat_path.sample_n, 1)
            self.assertAlmostEqual(split.heartbeat_path.timeout_rate, 1.0, places=6)
            self.assertEqual(split.heartbeat_path.top_timeout_reason, "TIMEOUT")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
