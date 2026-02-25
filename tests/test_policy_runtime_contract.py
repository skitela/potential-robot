import json
import sys
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class TestPolicyRuntimeContract(unittest.TestCase):
    def test_bridge_schema_file_exists_and_has_required_groups(self) -> None:
        schema_path = ROOT / "DOCS" / "bridge" / "policy_runtime_schema.json"
        self.assertTrue(schema_path.exists(), f"Missing schema: {schema_path}")
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
        groups = (
            schema.get("properties", {})
            .get("groups", {})
            .get("required", [])
        )
        self.assertEqual(["FX", "METAL", "INDEX", "CRYPTO", "EQUITY"], groups)

    def test_python_runtime_payload_contains_all_groups_and_risk_fields(self) -> None:
        with patch.object(safetybot.SafetyBot, "__init__", lambda s, *args, **kwargs: None):
            bot = safetybot.SafetyBot()

        payload = bot._build_policy_runtime_payload(
            group_arb={"FX": {"priority_factor": 1.0}},
            group_risk={"FX": {"entry_allowed": True, "reason": "NONE"}},
        )

        self.assertEqual("1.0", str(payload.get("schema_version")))
        groups = payload.get("groups", {})
        for grp in ("FX", "METAL", "INDEX", "CRYPTO", "EQUITY"):
            self.assertIn(grp, groups, f"group missing in runtime payload: {grp}")
            node = groups.get(grp, {})
            for required_key in (
                "entry_allowed",
                "borrow_blocked",
                "priority_factor",
                "reason",
                "risk_friday",
                "risk_reopen",
            ):
                self.assertIn(required_key, node, f"{grp}.{required_key} missing")

    def test_mql5_agent_contains_policy_runtime_fail_safe_entrypoints(self) -> None:
        mql = (ROOT / "MQL5" / "Experts" / "HybridAgent.mq5").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            "IsWindowActive(",
            "IsRiskWindow(",
            "EntryAllowedForGroup(",
            "BorrowBlockedForGroup(",
            "PriorityFactorForGroup(",
            "POLICY_RUNTIME_FAILSAFE",
        )
        for token in required_tokens:
            self.assertIn(token, mql, f"Missing MQL5 policy token: {token}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
