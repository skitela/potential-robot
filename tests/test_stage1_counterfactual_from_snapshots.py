# -*- coding: utf-8 -*-
import datetime as dt
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from TOOLS.stage1_counterfactual_from_snapshots import select_no_trade_rows_stratified


def _write_stage1_dataset(path: Path) -> None:
    now = dt.datetime.now(tz=dt.timezone.utc).replace(microsecond=0)
    t0 = (now - dt.timedelta(minutes=30)).isoformat().replace("+00:00", "Z")
    t1 = (now - dt.timedelta(minutes=25)).isoformat().replace("+00:00", "Z")
    t2 = (now - dt.timedelta(minutes=20)).isoformat().replace("+00:00", "Z")
    rows = [
        {
            "ts_utc": t0,
            "symbol": "EURUSD",
            "instrument": "EURUSD",
            "sample_type": "NO_TRADE",
            "label": "SPREAD_TOO_WIDE",
            "reason_class": "COST_QUALITY",
            "window_id": "FX_AM",
            "window_phase": "ACTIVE",
            "strategy_family": "TREND_CONTINUATION",
            "side": "LONG",
            "signal": "BUY",
            "context": {"spread_points": 10.0},
        },
        {
            "ts_utc": t1,
            "symbol": "GBPUSD",
            "instrument": "GBPUSD",
            "sample_type": "NO_TRADE",
            "label": "NO_SIGNAL",
            "reason_class": "SIGNAL_LOGIC",
            "window_id": "FX_AM",
            "window_phase": "ACTIVE",
            "strategy_family": "RANGE_PULLBACK",
            "side": "SHORT",
            "signal": "SELL",
            "context": {"spread_points": 10.0},
        },
        {
            "ts_utc": t2,
            "symbol": "USDJPY",
            "instrument": "USDJPY",
            "sample_type": "NO_TRADE",
            "label": "NO_SIGNAL",
            "reason_class": "SIGNAL_LOGIC",
            "window_id": "FX_AM",
            "window_phase": "ACTIVE",
            "strategy_family": "UNKNOWN",
            "side": "UNKNOWN",
            "signal": "",
            "context": {},
        },
    ]
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")


def _create_history_db(path: Path) -> None:
    now = dt.datetime.now(tz=dt.timezone.utc).replace(microsecond=0)
    eur_base = now - dt.timedelta(minutes=29)
    gbp_base = now - dt.timedelta(minutes=24)

    conn = sqlite3.connect(str(path))
    try:
        conn.execute(
            """
            CREATE TABLE mt5_rates (
                symbol TEXT NOT NULL,
                broker_symbol TEXT NOT NULL DEFAULT '',
                timeframe TEXT NOT NULL,
                ts_utc TEXT NOT NULL,
                open REAL NOT NULL,
                high REAL NOT NULL,
                low REAL NOT NULL,
                close REAL NOT NULL,
                tick_volume INTEGER NOT NULL,
                spread INTEGER NOT NULL,
                real_volume INTEGER NOT NULL,
                source_terminal TEXT NOT NULL,
                ingest_run_id TEXT NOT NULL,
                ingested_at_utc TEXT NOT NULL,
                PRIMARY KEY (symbol, timeframe, ts_utc)
            )
            """
        )

        bars = []
        # EURUSD path: should hit TP for LONG with small tp/sl points.
        for i, (o, h, l, c) in enumerate(
            [
                (1.10000, 1.10020, 1.09990, 1.10010),
                (1.10010, 1.10040, 1.10000, 1.10030),
                (1.10030, 1.10060, 1.10020, 1.10050),
            ]
        ):
            ts = (eur_base + dt.timedelta(minutes=i)).isoformat().replace("+00:00", "Z")
            bars.append(("EURUSD", "EURUSD.PRO", "M1", ts, o, h, l, c))

        # GBPUSD path: should hit SL for SHORT with small tp/sl points.
        for i, (o, h, l, c) in enumerate(
            [
                (1.25000, 1.25030, 1.24990, 1.25020),
                (1.25020, 1.25050, 1.25010, 1.25040),
                (1.25040, 1.25070, 1.25020, 1.25060),
            ]
        ):
            ts = (gbp_base + dt.timedelta(minutes=i)).isoformat().replace("+00:00", "Z")
            bars.append(("GBPUSD", "GBPUSD.PRO", "M1", ts, o, h, l, c))

        conn.executemany(
            """
            INSERT INTO mt5_rates(
                symbol, broker_symbol, timeframe, ts_utc, open, high, low, close,
                tick_volume, spread, real_volume, source_terminal, ingest_run_id, ingested_at_utc
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 10, 0, 'TEST', 'RUN', '2026-03-04T00:00:00Z')
            """,
            bars,
        )
        conn.commit()
    finally:
        conn.close()


class TestStage1CounterfactualFromSnapshots(unittest.TestCase):
    def test_stratified_selection_keeps_symbol_window_coverage(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            ds = Path(td) / "stage1_learning_test.jsonl"
            rows = []
            now = dt.datetime.now(tz=dt.timezone.utc).replace(microsecond=0)
            for idx in range(6):
                rows.append(
                    {
                        "ts_utc": (now - dt.timedelta(minutes=idx)).isoformat().replace("+00:00", "Z"),
                        "symbol": "EURUSD",
                        "instrument": "EURUSD",
                        "sample_type": "NO_TRADE",
                        "label": "NO_SIGNAL",
                        "reason_class": "SIGNAL_LOGIC",
                        "window_id": "FX_AM",
                        "window_phase": "ACTIVE",
                    }
                )
            for idx in range(6, 12):
                rows.append(
                    {
                        "ts_utc": (now - dt.timedelta(minutes=idx)).isoformat().replace("+00:00", "Z"),
                        "symbol": "USDJPY",
                        "instrument": "USDJPY",
                        "sample_type": "NO_TRADE",
                        "label": "NO_SIGNAL",
                        "reason_class": "SIGNAL_LOGIC",
                        "window_id": "ASIA",
                        "window_phase": "ACTIVE",
                    }
                )
            ds.parent.mkdir(parents=True, exist_ok=True)
            with ds.open("w", encoding="utf-8") as f:
                for row in rows:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")

            selected, sampling = select_no_trade_rows_stratified(
                ds,
                max_rows=4,
                min_per_symbol_window=2,
            )

            self.assertEqual(len(selected), 4)
            self.assertEqual(sampling.get("mode"), "symbol_window_stratified_recent")
            by_bucket = sampling.get("selected_by_symbol_window") or {}
            self.assertEqual(int(by_bucket.get("EURUSD|FX_AM|ACTIVE") or 0), 2)
            self.assertEqual(int(by_bucket.get("USDJPY|ASIA|ACTIVE") or 0), 2)

    def test_counterfactual_labels_from_history(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            lab_root = Path(td) / "lab"
            (root / "EVIDENCE" / "learning_dataset").mkdir(parents=True, exist_ok=True)
            (lab_root / "data_curated").mkdir(parents=True, exist_ok=True)

            ds = root / "EVIDENCE" / "learning_dataset" / "stage1_learning_test.jsonl"
            _write_stage1_dataset(ds)
            hdb = lab_root / "data_curated" / "mt5_history.sqlite"
            _create_history_db(hdb)

            cmd = [
                sys.executable,
                "TOOLS/stage1_counterfactual_from_snapshots.py",
                "--root",
                str(root),
                "--lab-data-root",
                str(lab_root),
                "--dataset-jsonl",
                str(ds),
                "--history-db",
                str(hdb),
                "--horizon-minutes",
                "10",
                "--tp-points",
                "5",
                "--sl-points",
                "5",
                "--slippage-points",
                "1",
            ]
            proc = subprocess.run(cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
            self.assertIn("status=PASS", proc.stdout or "")

            report_files = sorted((lab_root / "reports" / "stage1").glob("stage1_counterfactual_report_*.json"))
            self.assertTrue(report_files, "Brak raportu counterfactual")
            rep = json.loads(report_files[-1].read_text(encoding="utf-8"))
            self.assertEqual(rep.get("status"), "PASS")
            details = rep.get("details") if isinstance(rep.get("details"), dict) else {}
            self.assertEqual(int(details.get("rows_no_trade_seen") or 0), 3)
            self.assertEqual(int(details.get("rows_evaluated") or 0), 2)
            self.assertGreaterEqual(int(details.get("rows_skipped") or 0), 1)
            self.assertIn("sampling", details)
            sampling = details.get("sampling") if isinstance(details.get("sampling"), dict) else {}
            self.assertEqual(int(sampling.get("rows_selected_total") or 0), 3)

            rows_files = sorted((lab_root / "reports" / "stage1").glob("stage1_counterfactual_rows_*.jsonl"))
            self.assertTrue(rows_files, "Brak pliku z rzędami counterfactual")
            cf_rows = [json.loads(x) for x in rows_files[-1].read_text(encoding="utf-8").splitlines() if x.strip()]
            self.assertEqual(len(cf_rows), 2)
            statuses = {str(r.get("counterfactual_status")) for r in cf_rows}
            self.assertTrue("MISSED_OPPORTUNITY" in statuses or "SAVED_LOSS" in statuses)
            families = {str(r.get("strategy_family") or "") for r in cf_rows}
            self.assertIn("TREND_CONTINUATION", families)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
