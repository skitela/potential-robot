# -*- coding: utf-8 -*-
import os
import tempfile
import unittest
import datetime as dt
from pathlib import Path

from BIN import learner_offline as lr


def _make_rows(n: int) -> list[dict]:
    """
    Synthetic closed events with v3 context.
    Pattern keeps loss streaks short: -,-,+,+,+ repeated.
    """
    out: list[dict] = []
    base = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)
    for i in range(int(n)):
        t = (base + dt.timedelta(minutes=i)).isoformat().replace("+00:00", "Z")
        is_pos = (i % 5) in (2, 3, 4)
        entry_score = 80 if is_pos else 65
        pnl = 1.0 if is_pos else -1.0
        out.append(
            {
                "closed_ts_utc": t,
                "symbol": "EURUSD",
                "reqs_trade": 1,
                "pnl_net": float(pnl),
                "commission": 0.0,
                "swap": 0.0,
                "fee": 0.0,
                "grp": "FX",
                "window_id": "FX_AM",
                "window_phase": "ACTIVE",
                "entry_score": int(entry_score),
                "entry_min_score": 74,
            }
        )
    return out


class TestLearnerStage1Readiness(unittest.TestCase):
    def setUp(self) -> None:
        self._env_backup = dict(os.environ)
        os.environ["OFFLINE_DETERMINISTIC"] = "1"
        os.environ["LEARNER_STAGE1_ENABLED"] = "1"
        os.environ["LEARNER_STAGE1_N_MIN_GRP"] = "40"
        os.environ["LEARNER_STAGE1_N_MIN_SYM"] = "200"
        os.environ["LEARNER_STAGE1_SUBSET_N_MIN"] = "10"
        os.environ["LEARNER_STAGE1_GROWTH_FACTOR"] = "1.30"
        os.environ["LEARNER_STAGE1_CANARY_N_MULT"] = "1.50"

    def tearDown(self) -> None:
        os.environ.clear()
        os.environ.update(self._env_backup)

    def test_next_eval_growth(self) -> None:
        self.assertEqual(lr._stage1_next_eval_n(10, n_min=80, growth=1.30), 80)
        self.assertEqual(lr._stage1_next_eval_n(80, n_min=80, growth=1.30), 104)
        self.assertEqual(lr._stage1_next_eval_n(100, n_min=80, growth=1.30), 130)

    def test_stage1_due_gating_and_ready_shadow(self) -> None:
        rows = _make_rows(60)
        with tempfile.TemporaryDirectory() as td:
            logs = Path(td)
            sug1, ms1 = lr._stage1_update_outputs(rows=rows, window_days=180, logs_dir=logs)
            self.assertIsInstance(sug1, dict)
            self.assertIsInstance(ms1, dict)
            segs1 = sug1.get("segments") or []
            self.assertGreaterEqual(len(segs1), 1)

            # Find group segment entry.
            gseg = [s for s in segs1 if str(s.get("segment", "")).startswith("G|FX|FX_AM|ACTIVE")]
            self.assertEqual(len(gseg), 1)
            self.assertEqual(int(gseg[0].get("due") or 0), 1)
            self.assertEqual(int(gseg[0].get("ready_shadow") or 0), 1)
            self.assertEqual(int(gseg[0].get("ready_canary") or 0), 0)

            # Persist milestones, then verify gating (no re-eval until +30% n).
            lr.atomic_write_json(logs / lr.STAGE1_MILESTONES_FILE, ms1)
            sug2, _ms2 = lr._stage1_update_outputs(rows=rows, window_days=180, logs_dir=logs)
            segs2 = sug2.get("segments") or []
            gseg2 = [s for s in segs2 if str(s.get("segment", "")).startswith("G|FX|FX_AM|ACTIVE")]
            self.assertEqual(len(gseg2), 1)
            self.assertEqual(int(gseg2[0].get("due") or 0), 0)

            # When data reaches next_eval_n, it becomes due again.
            rows78 = _make_rows(78)
            sug3, _ms3 = lr._stage1_update_outputs(rows=rows78, window_days=180, logs_dir=logs)
            segs3 = sug3.get("segments") or []
            gseg3 = [s for s in segs3 if str(s.get("segment", "")).startswith("G|FX|FX_AM|ACTIVE")]
            self.assertEqual(len(gseg3), 1)
            self.assertEqual(int(gseg3[0].get("due") or 0), 1)


if __name__ == "__main__":
    raise SystemExit(unittest.main())

