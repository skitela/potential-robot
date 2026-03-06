# -*- coding: utf-8 -*-
import json
import sqlite3
import shutil
import tempfile
import unittest
from pathlib import Path

from BIN import unified_learning_pack as ul


def _write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _write_decision_events_db(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute(
        """
        CREATE TABLE decision_events (
            choice_A TEXT,
            window_id TEXT,
            window_phase TEXT,
            strategy_family TEXT,
            outcome_pnl_net REAL,
            topk_json TEXT,
            is_paper INT,
            outcome_closed_ts_utc TEXT,
            ts_utc TEXT
        );
        """
    )
    learning_topk = json.dumps(
        [
            {
                "raw": "EURUSD",
                "sym": "EURUSD",
                "proposal": {
                    "unified_learning_score_delta": 3,
                },
                "unified_rank_adjustment": {
                    "pct_bonus": 0.05,
                },
            }
        ],
        ensure_ascii=False,
    )
    core_topk = json.dumps(
        [
            {
                "raw": "EURUSD",
                "sym": "EURUSD",
                "proposal": {
                    "unified_learning_score_delta": 0,
                },
                "unified_rank_adjustment": {
                    "pct_bonus": 0.0,
                },
            }
        ],
        ensure_ascii=False,
    )
    rows = []
    for idx in range(6):
        rows.append(
            (
                "EURUSD",
                "FX_AM",
                "ACTIVE",
                "TREND_CONTINUATION",
                12.0 + idx,
                learning_topk,
                1,
                f"2026-03-06T20:0{idx}:00Z",
                f"2026-03-06T19:0{idx}:00Z",
            )
        )
    for idx in range(6):
        rows.append(
            (
                "EURUSD",
                "FX_AM",
                "ACTIVE",
                "TREND_CONTINUATION",
                -6.0 - idx,
                core_topk,
                1,
                f"2026-03-05T20:1{idx}:00Z",
                f"2026-03-05T19:1{idx}:00Z",
            )
        )
    conn.executemany(
        """
        INSERT INTO decision_events (
            choice_A, window_id, window_phase, strategy_family,
            outcome_pnl_net, topk_json, is_paper, outcome_closed_ts_utc, ts_utc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        rows,
    )
    conn.commit()
    conn.close()


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
            _write_decision_events_db(root / "DB" / "decision_events.sqlite")

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
                        "by_symbol_window_family": [
                            {
                                "symbol": "EURUSD",
                                "window": "FX_AM|ACTIVE",
                                "strategy_family": "TREND_CONTINUATION",
                                "samples_n": 30,
                                "counterfactual_pnl_points_avg": 4.5,
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
            eur = instruments.get("EURUSD") or {}
            fam = eur.get("strategy_family_advisory") or []
            self.assertEqual(len(fam), 1)
            self.assertEqual(str(fam[0].get("strategy_family") or ""), "TREND_CONTINUATION")
            source_feedback = payload.get("source_feedback") or {}
            global_feedback = source_feedback.get("global") or {}
            self.assertEqual(str(global_feedback.get("leader") or ""), "LEARNING")
            self.assertGreater(float(global_feedback.get("learning_weight") or 1.0), 1.0)
            eur_feedback = (eur.get("source_feedback") or {})
            self.assertEqual(str(eur_feedback.get("leader") or ""), "LEARNING")
            self.assertGreater(float(eur_feedback.get("learning_weight") or 1.0), 1.0)

            read_back = ul.read_unified_runtime_advice(meta)
            self.assertIsInstance(read_back, dict)
            self.assertEqual(str((read_back or {}).get("source")), "unified_learning_pack")
            self.assertEqual(str((read_back or {}).get("qa_light")), "YELLOW")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
