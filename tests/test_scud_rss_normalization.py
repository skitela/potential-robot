# -*- coding: utf-8 -*-
import datetime as dt
import types
import unittest
from unittest import mock

from BIN import scudfab02 as s


class _FakeResp:
    def __init__(self, payload: bytes):
        self._payload = payload

    def iter_content(self, chunk_size=16384):
        _ = chunk_size
        yield self._payload

    def close(self):
        return None


class TestSCUDRSSNormalization(unittest.TestCase):
    def setUp(self):
        self._orig_allow = s.ALLOW_RSS_RESEARCH
        self._orig_det = s.DETERMINISTIC_MODE
        self._orig_sources = list(s.RSS_SOURCES)

        s.ALLOW_RSS_RESEARCH = True
        s.DETERMINISTIC_MODE = False
        s.RSS_SOURCES = [
            {
                "source_id": "fed_press",
                "url": "https://www.federalreserve.gov/feeds/press_all.xml",
                "instrument_tags": ["US500", "EURUSD"],
            }
        ]

    def tearDown(self):
        s.ALLOW_RSS_RESEARCH = self._orig_allow
        s.DETERMINISTIC_MODE = self._orig_det
        s.RSS_SOURCES = self._orig_sources

    def test_fetch_rss_signals_normalized_and_fresh(self):
        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        fresh = (now - dt.timedelta(minutes=25)).isoformat().replace("+00:00", "Z")
        stale = (now - dt.timedelta(days=3)).isoformat().replace("+00:00", "Z")

        entries = [
            types.SimpleNamespace(
                title="Federal Reserve updates policy path",
                summary="Wall Street reacts",
                link="https://example.test/news/1",
                published=fresh,
            ),
            types.SimpleNamespace(
                title="Old macro note",
                summary="Historical context",
                link="https://example.test/news/2",
                published=stale,
            ),
        ]

        fake_requests = types.SimpleNamespace(
            get=lambda *args, **kwargs: _FakeResp(b"<xml/>")
        )
        fake_feedparser = types.SimpleNamespace(
            parse=lambda txt: types.SimpleNamespace(entries=entries)
        )

        with mock.patch.dict("sys.modules", {"requests": fake_requests, "feedparser": fake_feedparser}):
            out = s.fetch_rss_signals(timeout_sec=0.2)

        self.assertIn("ts_utc", out)
        self.assertIn("items", out)
        self.assertEqual(len(out["items"]), 1)
        item = out["items"][0]

        self.assertEqual(item.get("source_id"), "fed_press")
        self.assertIn("US500", item.get("instrument_tags", []))
        self.assertTrue(item.get("headline_sha256"))
        self.assertTrue(item.get("summary_sha256"))
        self.assertTrue(item.get("link_sha256"))
        self.assertIn(item.get("freshness"), {"rt_2h", "fresh_24h"})
        self.assertIn(item.get("impact_class"), {"major", "normal", "minor"})

        # P0 guards still pass for normalized output.
        s.guard_obj_no_price_like(out)
        s.guard_obj_limits(out)

    def test_keyword_only_source_drops_non_matching_news(self):
        s.RSS_SOURCES = [
            {
                "source_id": "reuters_business",
                "url": "https://feeds.reuters.com/reuters/businessNews",
                "instrument_tags": ["EURUSD", "US500"],
                "keyword_only": True,
            }
        ]

        now = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
        fresh = (now - dt.timedelta(minutes=10)).isoformat().replace("+00:00", "Z")
        entries = [
            types.SimpleNamespace(
                title="Cinema festival and culture update",
                summary="No macro keywords here",
                link="https://example.test/news/3",
                published=fresh,
            ),
        ]

        fake_requests = types.SimpleNamespace(
            get=lambda *args, **kwargs: _FakeResp(b"<xml/>")
        )
        fake_feedparser = types.SimpleNamespace(
            parse=lambda txt: types.SimpleNamespace(entries=entries)
        )

        with mock.patch.dict("sys.modules", {"requests": fake_requests, "feedparser": fake_feedparser}):
            out = s.fetch_rss_signals(timeout_sec=0.2)

        self.assertEqual(out.get("items"), [])


if __name__ == "__main__":
    unittest.main()
