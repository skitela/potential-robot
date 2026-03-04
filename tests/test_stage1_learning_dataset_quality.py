# -*- coding: utf-8 -*-
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import datetime as dt
from pathlib import Path


def _create_db(path: Path) -> None:
    base = dt.datetime.now(tz=dt.timezone.utc)
    t1 = (base - dt.timedelta(minutes=20)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    t2 = (base - dt.timedelta(minutes=15)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    t3 = (base - dt.timedelta(minutes=10)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    t4 = (base - dt.timedelta(minutes=9)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    conn = sqlite3.connect(str(path))
    try:
        conn.execute(
            """
            CREATE TABLE decision_rejections(
                ts_utc TEXT,
                symbol TEXT,
                grp TEXT,
                mode TEXT,
                reason_code TEXT,
                reason_class TEXT,
                stage TEXT,
                signal TEXT,
                regime TEXT,
                window_id TEXT,
                window_phase TEXT,
                context_json TEXT
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE decision_events(
                ts_utc TEXT,
                choice_A TEXT,
                grp TEXT,
                symbol_mode TEXT,
                signal TEXT,
                signal_reason TEXT,
                regime TEXT,
                window_id TEXT,
                window_phase TEXT,
                entry_score INTEGER,
                entry_min_score INTEGER,
                spread_points REAL,
                outcome_pnl_net REAL
            )
            """
        )
        conn.execute(
            """
            INSERT INTO decision_rejections(
                ts_utc,symbol,grp,mode,reason_code,reason_class,stage,signal,regime,window_id,window_phase,context_json
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                t1,
                "EURUSD",
                "FX",
                "NORMAL",
                "SPREAD_TOO_WIDE",
                "COST_QUALITY",
                "ENTRY",
                "BUY",
                "TREND",
                "FX_AM",
                "ACTIVE",
                json.dumps({"command_type": "HEARTBEAT", "source_module": "TEST"}),
            ),
        )
        conn.execute(
            """
            INSERT INTO decision_rejections(
                ts_utc,symbol,grp,mode,reason_code,reason_class,stage,signal,regime,window_id,window_phase,context_json
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                t2,
                "GBPUSD",
                "FX",
                "NORMAL",
                "NO_SIGNAL",
                "SIGNAL_LOGIC",
                "ENTRY",
                "SELL",
                "RANGE",
                "FX_AM",
                "ACTIVE",
                json.dumps({"command_type": "OTHER", "source_module": "TEST"}),
            ),
        )
        conn.execute(
            """
            INSERT INTO decision_events(
                ts_utc,choice_A,grp,symbol_mode,signal,signal_reason,regime,window_id,window_phase,
                entry_score,entry_min_score,spread_points,outcome_pnl_net
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                t3,
                "EURUSD",
                "FX",
                "NORMAL",
                "BUY",
                "SCORE_OK",
                "TREND",
                "FX_AM",
                "ACTIVE",
                82,
                74,
                12.0,
                1.2,
            ),
        )
        conn.execute(
            """
            INSERT INTO decision_events(
                ts_utc,choice_A,grp,symbol_mode,signal,signal_reason,regime,window_id,window_phase,
                entry_score,entry_min_score,spread_points,outcome_pnl_net
            ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                t4,
                "GBPUSD",
                "FX",
                "NORMAL",
                "SELL",
                "SCORE_OK",
                "RANGE",
                "FX_AM",
                "ACTIVE",
                80,
                72,
                13.0,
                -0.5,
            ),
        )
        conn.commit()
    finally:
        conn.close()


class TestStage1DatasetQuality(unittest.TestCase):
    def test_dataset_builder_v2_and_quality_gate(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "DB").mkdir(parents=True, exist_ok=True)
            (root / "EVIDENCE" / "learning_dataset").mkdir(parents=True, exist_ok=True)
            db_path = root / "DB" / "decision_events.sqlite"
            _create_db(db_path)

            jsonl_path = root / "EVIDENCE" / "learning_dataset" / "dataset.jsonl"
            meta_path = root / "EVIDENCE" / "learning_dataset" / "dataset.meta.json"

            build_cmd = [
                sys.executable,
                "TOOLS/build_stage1_learning_dataset.py",
                "--root",
                str(root),
                "--lookback-hours",
                "24",
                "--out-jsonl",
                str(jsonl_path),
                "--out-meta",
                str(meta_path),
            ]
            r1 = subprocess.run(build_cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(r1.returncode, 0, msg=r1.stderr or r1.stdout)
            self.assertTrue(jsonl_path.exists())
            self.assertTrue(meta_path.exists())

            meta = json.loads(meta_path.read_text(encoding="utf-8"))
            self.assertEqual(meta.get("schema"), "oanda.mt5.stage1_learning_dataset.v2")
            self.assertGreaterEqual(int(meta.get("rows_total") or 0), 4)
            self.assertIn("command_type_counts", meta)

            rows = [json.loads(x) for x in jsonl_path.read_text(encoding="utf-8").splitlines() if x.strip()]
            no_trade = [x for x in rows if str(x.get("sample_type")) == "NO_TRADE"]
            self.assertGreaterEqual(len(no_trade), 2)
            self.assertTrue(any(str(x.get("command_type")) == "HEARTBEAT" for x in no_trade))

            quality_cmd = [
                sys.executable,
                "TOOLS/stage1_dataset_quality.py",
                "--root",
                str(root),
                "--dataset-jsonl",
                str(jsonl_path),
                "--min-total-per-symbol",
                "1",
                "--min-no-trade-per-symbol",
                "1",
                "--min-trade-path-per-symbol",
                "1",
                "--min-buckets-per-symbol",
                "1",
            ]
            r2 = subprocess.run(quality_cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(r2.returncode, 0, msg=r2.stderr or r2.stdout)
            self.assertIn("verdict=PASS", (r2.stdout or ""))

            quality_hold_cmd = quality_cmd[:-2] + ["--min-buckets-per-symbol", "3"]
            r3 = subprocess.run(quality_hold_cmd, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(r3.returncode, 0, msg=r3.stderr or r3.stdout)
            self.assertIn("verdict=HOLD", (r3.stdout or ""))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
