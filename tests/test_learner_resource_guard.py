# -*- coding: utf-8 -*-
import unittest
from pathlib import Path
from unittest import mock

from BIN import learner_offline as lr


class TestLearnerResourceGuard(unittest.TestCase):
    def test_decide_resource_mode_skip_on_low_memory(self):
        mode, reason = lr.decide_resource_mode(
            cpu_pct=10.0,
            mem_available_mb=1200.0,
            cpu_soft_max_pct=70.0,
            cpu_hard_max_pct=85.0,
            mem_min_mb=1500.0,
        )
        self.assertEqual(mode, "skip")
        self.assertEqual(reason, "mem_low")

    def test_decide_resource_mode_skip_on_hard_cpu(self):
        mode, reason = lr.decide_resource_mode(
            cpu_pct=91.0,
            mem_available_mb=4000.0,
            cpu_soft_max_pct=70.0,
            cpu_hard_max_pct=85.0,
            mem_min_mb=1500.0,
        )
        self.assertEqual(mode, "skip")
        self.assertEqual(reason, "cpu_hard")

    def test_decide_resource_mode_light_on_soft_cpu(self):
        mode, reason = lr.decide_resource_mode(
            cpu_pct=74.0,
            mem_available_mb=4000.0,
            cpu_soft_max_pct=70.0,
            cpu_hard_max_pct=85.0,
            mem_min_mb=1500.0,
        )
        self.assertEqual(mode, "light")
        self.assertEqual(reason, "cpu_soft")

    def test_decide_resource_mode_normal_when_cpu_unknown(self):
        mode, reason = lr.decide_resource_mode(
            cpu_pct=None,
            mem_available_mb=4000.0,
            cpu_soft_max_pct=70.0,
            cpu_hard_max_pct=85.0,
            mem_min_mb=1500.0,
        )
        self.assertEqual(mode, "normal")
        self.assertEqual(reason, "ok")

    def test_effective_scan_params_light_uses_minimum_caps(self):
        wd, rl = lr.effective_scan_params(
            base_window_days=180,
            base_row_limit=20000,
            load_mode="light",
            light_window_days=90,
            light_row_limit=5000,
        )
        self.assertEqual(wd, 90)
        self.assertEqual(rl, 5000)

    def test_effective_scan_params_light_does_not_expand(self):
        wd, rl = lr.effective_scan_params(
            base_window_days=60,
            base_row_limit=1200,
            load_mode="light",
            light_window_days=90,
            light_row_limit=5000,
        )
        self.assertEqual(wd, 60)
        self.assertEqual(rl, 1200)

    def test_run_once_skip_does_not_fetch_rows(self):
        with mock.patch.object(lr, "read_cpu_percent", return_value=95.0), \
             mock.patch.object(lr, "read_mem_available_mb", return_value=4096.0), \
             mock.patch.object(lr, "fetch_closed_events") as fetch_mock:
            rc = lr.run_once(Path("c:/OANDA_MT5_SYSTEM"))
        self.assertEqual(rc, 0)
        fetch_mock.assert_not_called()

    def test_run_once_light_uses_reduced_limit_and_marks_notes(self):
        captured_objs = []

        def _capture_write(path, obj):
            captured_objs.append((str(path), obj))

        fake_meta = {
            "schema": "oanda_mt5.learner_advice.v1",
            "ts_utc": "2026-02-11T00:00:00Z",
            "ttl_sec": 3600,
            "window_days": 90,
            "metrics": {"n": 0, "mean_edge_fuel": 0.0, "es95": 0.0, "mdd": 0.0},
            "ranks": [],
            "notes": ["source=decision_events", "method=psr_weighted", "mode=offline"],
        }
        fake_report = {"ts_utc": "2026-02-11T00:00:00Z", "window_days": 90, "syms": []}

        with mock.patch.dict(
            "os.environ",
            {
                "LEARNER_RESOURCE_GUARD": "1",
                "LEARNER_WINDOW_DAYS": "180",
                "LEARNER_ROW_LIMIT": "20000",
                "LEARNER_LIGHT_WINDOW_DAYS": "90",
                "LEARNER_LIGHT_ROW_LIMIT": "5000",
                "LEARNER_CPU_SOFT_MAX_PCT": "70",
                "LEARNER_CPU_HARD_MAX_PCT": "85",
                "LEARNER_MEM_MIN_MB": "1500",
            },
            clear=False,
        ), \
             mock.patch.object(lr, "read_cpu_percent", return_value=74.0), \
             mock.patch.object(lr, "read_mem_available_mb", return_value=4096.0), \
             mock.patch.object(lr, "fetch_closed_events", return_value=[]) as fetch_mock, \
             mock.patch.object(lr, "build_advice", return_value=(fake_meta, fake_report)), \
             mock.patch.object(lr, "atomic_write_json", side_effect=_capture_write):
            rc = lr.run_once(Path("c:/OANDA_MT5_SYSTEM"))

        self.assertEqual(rc, 0)
        _args, kwargs = fetch_mock.call_args
        self.assertEqual(int(kwargs.get("limit")), 5000)
        self.assertTrue(any("learner_advice.json" in p for (p, _o) in captured_objs))
        meta_objs = [o for (p, o) in captured_objs if p.endswith("learner_advice.json")]
        self.assertTrue(meta_objs)
        notes = list(meta_objs[0].get("notes") or [])
        self.assertIn("load_mode=light", notes)


if __name__ == "__main__":
    unittest.main()
