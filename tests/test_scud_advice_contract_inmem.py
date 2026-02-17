# -*- coding: utf-8 -*-
import datetime as dt
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from BIN import scudfab02 as s


class TestSCUDAdviceContractInMemory(unittest.TestCase):
    def test_write_advice_contract_v2(self):
        captured = {}

        def _capture(path, obj):
            captured["path"] = str(path)
            captured["obj"] = obj

        verdict = "GREEN"
        metrics = {"n": 100, "mean_edge_fuel": 0.1, "es95": -0.01, "mdd": -0.2}
        research = {
            "ts_utc": "2026-02-01T00:00:00Z",
            "items": [
                {
                    "source_id": "fed_press",
                    "domain": "www.federalreserve.gov",
                    "instrument_tags": ["US500"],
                    "ts_source_utc": "2026-02-01T00:00:00Z",
                    "ts_fetch_utc": "2026-02-01T00:01:00Z",
                    "headline_sha256": "a" * 64,
                    "summary_sha256": "b" * 64,
                    "link_sha256": "c" * 64,
                    "freshness": "rt_2h",
                    "impact_class": "major",
                }
            ],
        }
        ranks = [
            {"symbol": "EURUSD.PRO", "score": 0.01, "es95": -0.02, "mdd": -0.1, "n": 10},
            {"symbol": "GBPUSD.PRO", "score": 0.005, "es95": -0.03, "mdd": -0.12, "n": 9},
        ]

        with mock.patch.object(s, "atomic_write_json", side_effect=_capture):
            s.write_advice(s.runtime_root() / "META", verdict, metrics, research, ranks)

        obj = captured.get("obj") or {}
        self.assertEqual(int(obj.get("ttl_sec")), 900)
        self.assertEqual(str(obj.get("schema")), "oanda_mt5.scout_advice.v2")
        self.assertEqual(str(obj.get("preferred_symbol")), "EURUSD.PRO")
        self.assertIn("research", obj)
        self.assertTrue((obj.get("research") or {}).get("items"))

        s.guard_obj_no_price_like(obj)
        s.guard_obj_limits(obj)

    def test_read_learner_advice_retries_transient_invalid_json(self):
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        valid = {
            "schema": "oanda_mt5.learner_advice.v1",
            "ts_utc": now,
            "ttl_sec": 3600,
            "metrics": {"n": 120, "mean_edge_fuel": 0.02, "es95": -0.01, "mdd": -0.2},
            "ranks": [{"symbol": "EURUSD.PRO", "score": 0.1, "es95": -0.01, "mdd": -0.2, "n": 120}],
            "qa_light": "GREEN",
        }

        with tempfile.TemporaryDirectory() as td:
            meta_dir = Path(td)
            advice_path = meta_dir / "learner_advice.json"
            advice_path.write_text("{}", encoding="utf-8")

            state = {"n": 0}
            orig_read = Path.read_text

            def _read_text_retry_once(self, *args, **kwargs):
                if self == advice_path and state["n"] == 0:
                    state["n"] += 1
                    return "{"
                if self == advice_path:
                    return json.dumps(valid)
                return orig_read(self, *args, **kwargs)

            with mock.patch.object(Path, "read_text", new=_read_text_retry_once), \
                 mock.patch("BIN.scudfab02.time.sleep", return_value=None):
                out = s.read_learner_advice(meta_dir)

        self.assertIsInstance(out, dict)
        self.assertEqual(str((out or {}).get("source")), "offline_learner")
        self.assertEqual(int(((out or {}).get("metrics") or {}).get("n") or 0), 120)


if __name__ == "__main__":
    unittest.main()
