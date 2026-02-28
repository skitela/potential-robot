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
            "session_liquidity_gate_enabled",
            "session_liquidity_gate_mode",
            "session_liquidity_block_on_missing_snapshot",
            "session_liquidity_emit_caution_event",
            "session_liquidity_spread_caution_by_group",
            "session_liquidity_spread_block_by_group",
            "session_liquidity_max_tick_age_sec_by_group",
            "cost_microstructure_gate_enabled",
            "cost_microstructure_gate_mode",
            "cost_microstructure_block_on_missing_snapshot",
            "cost_microstructure_block_on_unknown_quality",
            "cost_microstructure_emit_caution_event",
            "cost_microstructure_spread_caution_by_group",
            "cost_microstructure_spread_block_by_group",
            "cost_microstructure_max_tick_age_sec_by_group",
            "cost_microstructure_gap_block_sec_by_group",
            "cost_microstructure_jump_block_points_by_group",
            "candle_adapter_enabled",
            "candle_adapter_mode",
            "candle_adapter_emit_event",
            "candle_adapter_score_weight",
            "candle_adapter_min_body_to_range",
            "candle_adapter_pin_wick_ratio_min",
            "cost_guard_auto_relax_enabled",
            "cost_guard_auto_relax_window_minutes",
            "cost_guard_auto_relax_min_total_decisions",
            "cost_guard_auto_relax_min_wave1_decisions",
            "cost_guard_auto_relax_min_unknown_blocks",
            "cost_guard_auto_relax_max_critical_incidents",
            "cost_guard_auto_relax_max_error_incidents",
            "cost_guard_auto_relax_relaxed_min_ratio",
            "cost_guard_auto_relax_block_on_unknown_quality",
            "max_daily_loss_account",
            "max_session_loss_account",
            "max_daily_loss_per_module",
            "max_consecutive_losses_per_module",
            "max_trades_per_window_per_module",
            "max_execution_anomalies_per_window",
            "max_ipc_failures_per_window",
            "max_reject_ratio_threshold",
            "jpy_basket_symbol_intents",
            "asia_wave1_symbol_intents",
            "jpy_basket_max_concurrent_positions",
            "jpy_basket_max_risk_budget",
            "trade_window_symbol_filter_enabled",
            "trade_window_symbol_intents",
        ]
        for key in required:
            self.assertIn(key, cfg)
        self.assertIn(str(cfg.get("cost_gate_policy_mode", "")).upper(), {"CANARY_ACTIVE", "DIAGNOSTIC_ONLY", "DISABLED"})
        tw = cfg.get("trade_windows", {})
        self.assertIn("FX_ASIA", tw)
        self.assertEqual("Asia/Tokyo", str(tw["FX_ASIA"].get("anchor_tz")))
        self.assertIn("FX_ASIA", cfg.get("trade_window_symbol_intents", {}))
        self.assertGreaterEqual(len(cfg.get("trade_window_symbol_intents", {}).get("FX_ASIA", [])), 1)

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
