# -*- coding: utf-8 -*-
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class TestLabInsightsDigestCounterfactual(unittest.TestCase):
    def test_digest_includes_counterfactual_pln_compact(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab = Path(td) / "lab"
            # Minimal source reports for digest.
            _write_json(
                lab / "reports" / "ingest" / "lab_mt5_ingest_1.json",
                {
                    "status": "PASS",
                    "generated_at_utc": "2026-03-04T10:00:00Z",
                    "summary": {
                        "rows_fetched_total": 100,
                        "rows_inserted_total": 90,
                        "rows_deduped_total": 10,
                        "quality_grade": "OK",
                    },
                    "details": [{"symbol": "EURUSD"}],
                },
            )
            _write_json(
                lab / "reports" / "daily" / "lab_daily_report_1.json",
                {
                    "status": "PASS",
                    "generated_at_utc": "2026-03-04T10:10:00Z",
                    "summary": {
                        "pairs_ready_for_shadow": 1,
                        "pairs_total": 4,
                        "explore_total_trades": 8,
                        "focus_windows": ["FX_AM"],
                    },
                    "leaderboard": [],
                },
            )
            _write_json(
                lab / "reports" / "retention" / "lab_snapshot_retention_1.json",
                {
                    "status": "PASS",
                    "generated_at_utc": "2026-03-04T10:15:00Z",
                    "summary": {"snapshot_dirs_removed": 0},
                },
            )
            _write_json(
                lab / "run" / "lab_scheduler_status.json",
                {
                    "status": "PASS",
                    "reason": "SCHEDULER_OK",
                    "generated_at_utc": "2026-03-04T10:20:00Z",
                },
            )
            _write_json(
                lab / "reports" / "stage1" / "stage1_counterfactual_summary_latest.json",
                {
                    "status": "PASS",
                    "generated_at_utc": "2026-03-04T10:25:00Z",
                    "summary": {"rows_total": 12},
                    "aggregates": {
                        "by_symbol": [
                            {
                                "symbol": "EURUSD",
                                "samples_n": 6,
                                "saved_loss_n": 1,
                                "missed_opportunity_n": 3,
                                "neutral_timeout_n": 2,
                                "counterfactual_pnl_points_total": 18.0,
                                "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW",
                            },
                            {
                                "symbol": "USDJPY",
                                "samples_n": 6,
                                "saved_loss_n": 4,
                                "missed_opportunity_n": 1,
                                "neutral_timeout_n": 1,
                                "counterfactual_pnl_points_total": -9.0,
                                "recommendation": "DOCISKAJ_FILTRY",
                            },
                        ]
                    },
                },
            )
            _write_json(
                root / "LAB" / "CONFIG" / "pln_point_estimates.json",
                {
                    "default_pln_per_point": 1.0,
                    "symbol_overrides": {
                        "EURUSD": 2.0,
                        "USDJPY": 3.0,
                    },
                },
            )

            cmd = [
                sys.executable,
                "TOOLS/lab_insights_digest.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab),
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)

            pointer = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.json"
            self.assertTrue(pointer.exists())
            payload = json.loads(pointer.read_text(encoding="utf-8"))
            wa = payload.get("window_aggregate", {})
            compact = wa.get("counterfactual_by_symbol_compact", [])
            self.assertEqual(len(compact), 2)
            eur = [x for x in compact if str(x.get("symbol")) == "EURUSD"][0]
            usd = [x for x in compact if str(x.get("symbol")) == "USDJPY"][0]
            self.assertAlmostEqual(float(eur.get("counterfactual_pnl_pln_est_total")), 36.0, places=6)
            self.assertAlmostEqual(float(usd.get("counterfactual_pnl_pln_est_total")), -27.0, places=6)

            txt = (root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.txt").read_text(encoding="utf-8")
            self.assertIn("EURUSD: +36.00 zł", txt)
            self.assertIn("USDJPY: -27.00 zł", txt)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
