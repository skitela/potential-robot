# -*- coding: utf-8 -*-
import unittest

from BIN import common_contract as cc
from BIN import common_guards as cg


class TestRunContractV2(unittest.TestCase):
    def test_request_valid(self):
        req = {
            "pv": 2,
            "ts_utc": "2026-01-29T00:00:00Z",
            "rid": "TB-20260129-000000-1234-1",
            "ttl_sec": 30,
            "cands": ["EURUSD", "GBPUSD"],
            "mode": "PAPER",
            "ctx": {"mode": "PAPER", "note": "near_tie"},
        }
        v = cc.validate_run_request_v2(req)
        self.assertIsNotNone(v)

    def test_request_reject_pv(self):
        req = {
            "pv": 1,
            "ts_utc": "2026-01-29T00:00:00Z",
            "rid": "TB-20260129-000000-1234-2",
            "ttl_sec": 30,
            "cands": ["EURUSD", "GBPUSD"],
            "mode": "PAPER",
            "ctx": {},
        }
        self.assertIsNone(cc.validate_run_request_v2(req))

    def test_response_valid(self):
        resp = {
            "pv": 2,
            "ts_utc": "2026-01-29T00:00:01Z",
            "rid": "TB-20260129-000000-1234-1",
            "tb": 1,
            "pref": "EURUSD",
            "reasons": ["OK"],
        }
        v = cc.validate_run_response_v2(resp)
        self.assertIsNotNone(v)

    def test_guard_price_like_false_positive(self):
        obj = {"mask": "ok", "task": "x", "forecast": "y"}
        self.assertFalse(cg.contains_price_like(obj))

    def test_guard_price_like_true_positive(self):
        obj = {"ask_price": 1.23456}
        self.assertTrue(cg.contains_price_like(obj))


if __name__ == "__main__":
    unittest.main()
