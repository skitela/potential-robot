# -*- coding: utf-8 -*-
import json
import unittest
import shutil
import uuid
from pathlib import Path

from BIN import scudfab02


class TestSCUDMetaContract(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = Path("TMP_AUDIT_IO") / "test_scud_contract_meta"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_scout_advice_ttl_is_900(self):
        td = self._tmpdir()
        meta = td / "META"
        meta.mkdir(parents=True, exist_ok=True)

        verdict = "GREEN"
        metrics = {"n": 100, "mean_edge_fuel": 0.1, "es95": -0.01, "mdd": -0.2}
        research = {"ts_utc": "2026-02-01T00:00:00Z", "items": ["signal_a", "signal_b"]}
        ranks = [
            {"symbol": "EURUSD.PRO", "score": 0.01, "es95": -0.02, "mdd": -0.1, "n": 10},
            {"symbol": "GBPUSD.PRO", "score": 0.005, "es95": -0.03, "mdd": -0.12, "n": 9},
        ]

        scudfab02.write_advice(meta, verdict, metrics, research, ranks)

        p = meta / "scout_advice.json"
        self.assertTrue(p.exists())
        obj = json.loads(p.read_text(encoding="utf-8"))
        self.assertEqual(int(obj.get("ttl_sec")), 900)
        self.assertEqual(str(obj.get("schema")), "oanda_mt5.scout_advice.v2")

        # P0: price-like forbidden keys/values
        scudfab02.guard_obj_no_price_like(obj)

        # P0: numeric token limits
        scudfab02.guard_obj_limits(obj)


if __name__ == "__main__":
    unittest.main()
