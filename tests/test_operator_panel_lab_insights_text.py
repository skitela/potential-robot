# -*- coding: utf-8 -*-
import tempfile
import unittest
from pathlib import Path

import TOOLS.OANDA_OPERATOR_PANEL as panel


class TestOperatorPanelLabInsightsText(unittest.TestCase):
    def test_build_lab_insights_text_fallback_includes_pln_compact(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            # Force fallback path (without reading workspace pointer txt).
            old_txt = panel.LAB_INSIGHTS_POINTER_TXT
            panel.LAB_INSIGHTS_POINTER_TXT = Path(td) / "missing.txt"
            try:
                payload = {
                    "generated_at_utc": "2026-03-04T11:00:00Z",
                    "status": "PASS",
                    "recommendation": "TEST_RECO",
                    "report_path": "C:/tmp/report.json",
                    "snapshot": {
                        "scheduler_status": "PASS",
                        "scheduler_reason": "OK",
                        "latest_ingest_quality_grade": "OK",
                        "latest_pairs_ready_for_shadow": 1,
                        "latest_pairs_total": 4,
                        "latest_explore_total_trades": 5,
                    },
                    "window_aggregate": {
                        "rows_fetched_total": 100,
                        "rows_inserted_total": 90,
                        "counterfactual_by_symbol_compact": [
                            {"symbol": "EURUSD", "counterfactual_pnl_pln_est_total": 12.5, "recommendation": "ROZWAZ_LUZOWANIE_W_SHADOW"},
                            {"symbol": "USDJPY", "counterfactual_pnl_pln_est_total": -4.0, "recommendation": "DOCISKAJ_FILTRY"},
                        ],
                    },
                }
                text = panel._build_lab_insights_text(payload)
                self.assertIn("EURUSD: +12.50 zł", text)
                self.assertIn("USDJPY: -4.00 zł", text)
                self.assertIn("TEST_RECO", text)
            finally:
                panel.LAB_INSIGHTS_POINTER_TXT = old_txt


if __name__ == "__main__":
    raise SystemExit(unittest.main())
