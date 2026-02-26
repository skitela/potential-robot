import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class TestHardLiveCanaryContracts(unittest.TestCase):
    def test_strategy_contains_hl_contract_keys(self) -> None:
        cfg_path = ROOT / "CONFIG" / "strategy.json"
        cfg = json.loads(cfg_path.read_text(encoding="utf-8-sig"))
        required = [
            "live_canary_enabled",
            "module_live_enabled_map",
            "live_canary_allowed_groups",
            "live_canary_allowed_symbol_intents",
            "hard_live_disabled_groups",
            "hard_live_disabled_symbol_intents",
            "cost_gate_policy_mode",
            "max_daily_loss_account",
            "max_session_loss_account",
            "max_daily_loss_per_module",
            "max_consecutive_losses_per_module",
            "max_trades_per_window_per_module",
            "max_execution_anomalies_per_window",
            "max_ipc_failures_per_window",
            "max_reject_ratio_threshold",
            "jpy_basket_symbol_intents",
            "jpy_basket_max_concurrent_positions",
            "jpy_basket_max_risk_budget",
        ]
        for key in required:
            self.assertIn(key, cfg)
        self.assertIn(str(cfg.get("cost_gate_policy_mode", "")).upper(), {"CANARY_ACTIVE", "DIAGNOSTIC_ONLY", "DISABLED"})

    def test_no_live_drift_tool(self) -> None:
        script = ROOT / "TOOLS" / "no_live_drift_check.py"
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "CONFIG").mkdir(parents=True, exist_ok=True)
            (root / "EVIDENCE").mkdir(parents=True, exist_ok=True)
            cfg = {
                "live_canary_enabled": True,
                "module_live_enabled_map": {"FX": True, "METAL": False, "INDEX": False, "CRYPTO": False},
                "live_canary_allowed_groups": ["FX"],
                "live_canary_allowed_symbol_intents": ["USDJPY", "EURJPY"],
                "hard_live_disabled_groups": ["CRYPTO"],
                "hard_live_disabled_symbol_intents": ["BTCUSD", "ETHUSD", "JP225", "GOLD"],
            }
            (root / "CONFIG" / "strategy.json").write_text(json.dumps(cfg, ensure_ascii=False), encoding="utf-8")
            preflight = {
                "rows": [
                    {"canonical_symbol": "USDJPY.pro", "preflight_ok": True},
                    {"canonical_symbol": "GOLD.pro", "preflight_ok": True},
                ]
            }
            (root / "EVIDENCE" / "asia_symbol_preflight.json").write_text(
                json.dumps(preflight, ensure_ascii=False),
                encoding="utf-8",
            )
            out_rel = Path("EVIDENCE") / "no_live_drift_check.json"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(script),
                    "--root",
                    str(root),
                    "--strategy",
                    "CONFIG/strategy.json",
                    "--preflight",
                    "EVIDENCE/asia_symbol_preflight.json",
                    "--out",
                    str(out_rel),
                ],
                cwd=str(ROOT),
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(0, proc.returncode, msg=proc.stderr)
            out_path = root / out_rel
            self.assertTrue(out_path.exists())
            obj = json.loads(out_path.read_text(encoding="utf-8"))
            self.assertIn("rows", obj)
            self.assertGreaterEqual(len(obj["rows"]), 1)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
