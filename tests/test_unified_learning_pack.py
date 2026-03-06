# -*- coding: utf-8 -*-
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from BIN import unified_learning_pack as ul


def _write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestUnifiedLearningPack(unittest.TestCase):
    def test_builds_single_advisory_bus_and_runtime_light(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            meta = root / "META"
            meta.mkdir(parents=True, exist_ok=True)

            _write_json(
                meta / "learner_advice.json",
                {
                    "schema": "oanda_mt5.learner_advice.v1",
                    "ts_utc": "2026-03-06T20:00:00Z",
                    "ttl_sec": 3600,
                    "qa_light": "YELLOW",
                    "metrics": {"n": 120, "mean_edge_fuel": 0.04, "es95": -0.02, "mdd": -0.1},
                    "ranks": [
                        {"symbol": "EURUSD", "score": 0.04, "n": 120},
                        {"symbol": "GBPUSD", "score": 0.02, "n": 90},
                    ],
                },
            )
            _write_json(
                meta / "verdict.json",
                {
                    "schema": "oanda_mt5.verdict.v1",
                    "ts_utc": "2026-03-06T20:00:00Z",
                    "ttl_sec": 172800,
                    "light": "YELLOW",
                    "metrics": {"n": 120, "mean_edge_fuel": 0.04, "es95": -0.02, "mdd": -0.1},
                },
            )
            _write_json(
                meta / "scout_advice.json",
                {
                    "schema": "oanda_mt5.scout_advice.v2",
                    "ts_utc": "2026-03-06T20:00:00Z",
                    "ttl_sec": 900,
                    "preferred_symbol": "EURUSD",
                    "light": "YELLOW",
                    "ranks": [
                        {"symbol": "EURUSD", "score": 0.05, "n": 120},
                        {"symbol": "GBPUSD", "score": 0.01, "n": 90},
                    ],
                },
            )

            _write_json(
                root / "CONFIG" / "strategy.json",
                {
                    "paper_trading": True,
                    "policy_shadow_mode_enabled": True,
                    "symbols_to_trade": ["EURUSD", "GBPUSD"],
                },
            )
            _write_json(
                root / "LAB" / "RUN" / "live_config_stage1_apply.json",
                {
                    "schema_version": "live_config_v3",
                    "instruments": {
                        "EURUSD": {
                            "active_profile": "balanced",
                            "profile_label_pl": "sredni",
                            "profile_id": "EURUSD_balanced_x",
                            "reason_for_change": "test",
                        },
                        "GBPUSD": {
                            "active_profile": "conservative",
                            "profile_label_pl": "bezpieczny",
                            "profile_id": "GBPUSD_conservative_x",
                            "reason_for_change": "test",
                        },
                    },
                },
            )

            stage1 = lab / "reports" / "stage1"
            _write_json(
                stage1 / "stage1_profile_pack_eval_latest.json",
                {
                    "schema": "oanda.mt5.stage1_profile_pack_eval.v1",
                    "evaluation_by_symbol": [
                        {
                            "symbol": "EURUSD",
                            "shadow": {
                                "shadow_trades_n": 100,
                                "shadow_net_pips_per_trade": 1.2,
                                "shadow_stability_score": 0.8,
                            },
                            "ranking": [
                                {"profile_name": "SREDNI", "final_score": 0.8},
                                {"profile_name": "BEZPIECZNY", "final_score": 0.5},
                            ],
                            "recommendation_for_tomorrow": {
                                "recommended_profile": "SREDNI",
                                "guard_reason": "OK",
                            },
                        },
                        {
                            "symbol": "GBPUSD",
                            "shadow": {
                                "shadow_trades_n": 50,
                                "shadow_net_pips_per_trade": -1.5,
                                "shadow_stability_score": 0.4,
                            },
                            "ranking": [
                                {"profile_name": "BEZPIECZNY", "final_score": -0.3},
                                {"profile_name": "SREDNI", "final_score": -0.5},
                            ],
                            "recommendation_for_tomorrow": {
                                "recommended_profile": "BEZPIECZNY",
                                "guard_reason": "OK",
                            },
                        },
                    ],
                },
            )
            _write_json(stage1 / "stage1_profile_pack_latest.json", {"schema": "oanda.mt5.stage1_profile_pack.v1"})
            _write_json(
                stage1 / "stage1_counterfactual_summary_latest.json",
                {
                    "schema": "oanda.mt5.stage1_counterfactual_summary.v1",
                    "aggregates": {
                        "by_symbol": [
                            {
                                "symbol": "EURUSD",
                                "samples_n": 80,
                                "saved_loss_n": 10,
                                "missed_opportunity_n": 12,
                                "neutral_timeout_n": 58,
                                "counterfactual_pnl_points_avg": 6.0,
                                "counterfactual_pnl_points_total": 480.0,
                                "recommendation": "TRZYMAJ",
                            },
                            {
                                "symbol": "GBPUSD",
                                "samples_n": 70,
                                "saved_loss_n": 30,
                                "missed_opportunity_n": 0,
                                "neutral_timeout_n": 40,
                                "counterfactual_pnl_points_avg": -18.0,
                                "counterfactual_pnl_points_total": -1260.0,
                                "recommendation": "DOCISKAJ_FILTRY",
                            },
                        ],
                        "by_symbol_window": [
                            {
                                "symbol": "EURUSD",
                                "window": "FX_AM|ACTIVE",
                                "samples_n": 50,
                                "counterfactual_pnl_points_avg": 5.0,
                                "recommendation": "TRZYMAJ",
                            }
                        ],
                    },
                },
            )
            _write_json(
                stage1 / "stage1_shadow_gonogo_latest.json",
                {
                    "schema": "oanda.mt5.stage1_shadow_gonogo.v1",
                    "status": "PASS",
                    "verdict": "GO",
                },
            )
            _write_json(
                stage1 / "shadow_plus_progression_latest.json",
                {
                    "schema": "oanda.mt5.shadow_plus_progress_report.v1",
                    "progress": {"stage": "LIVE_ADVISORY_READY"},
                },
            )

            out, payload = ul.build_unified_learning_pack(root=root, lab_data_root=lab)
            self.assertTrue(out.exists())
            self.assertEqual(str(payload.get("schema")), ul.SCHEMA)

            runtime_light = payload.get("runtime_light") or {}
            self.assertEqual(str(runtime_light.get("qa_light")), "YELLOW")
            self.assertEqual(str(runtime_light.get("preferred_symbol")), "EURUSD")

            instruments = payload.get("instruments") or {}
            self.assertEqual(str((instruments.get("EURUSD") or {}).get("advisory_bias")), "PROMOTE")
            self.assertEqual(str((instruments.get("GBPUSD") or {}).get("advisory_bias")), "SUPPRESS")

            read_back = ul.read_unified_runtime_advice(meta)
            self.assertIsInstance(read_back, dict)
            self.assertEqual(str((read_back or {}).get("source")), "unified_learning_pack")
            self.assertEqual(str((read_back or {}).get("qa_light")), "YELLOW")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
