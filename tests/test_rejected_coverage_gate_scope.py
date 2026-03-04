# -*- coding: utf-8 -*-
import json
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from pathlib import Path


class TestRejectedCoverageGateScope(unittest.TestCase):
    def test_active_scope_excludes_inactive_symbols(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td) / "root"
            (root / "DB").mkdir(parents=True, exist_ok=True)
            (root / "CONFIG").mkdir(parents=True, exist_ok=True)

            strategy = {
                "symbols_to_trade": ["USDJPY", "EURUSD"],
                "groups": {"USDJPY": "FX", "EURUSD": "FX"},
            }
            (root / "CONFIG" / "strategy.json").write_text(
                json.dumps(strategy, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

            db_path = root / "DB" / "decision_events.sqlite"
            conn = sqlite3.connect(str(db_path))
            conn.execute("CREATE TABLE decision_events (ts_utc TEXT, choice_A TEXT)")
            now_iso = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
            conn.execute("INSERT INTO decision_events (ts_utc, choice_A) VALUES (?, ?)", (now_iso, "USDJPY"))
            conn.commit()
            conn.close()

            out_strategy = root / "EVIDENCE" / "learning_coverage" / "gate_strategy.json"
            out_active = root / "EVIDENCE" / "learning_coverage" / "gate_active.json"

            cmd_strategy = [
                sys.executable,
                "TOOLS/rejected_coverage_gate.py",
                "--root",
                str(root),
                "--lookback-hours",
                "24",
                "--focus-group",
                "FX",
                "--symbol-scope",
                "strategy",
                "--min-total-per-symbol",
                "1",
                "--min-rejects-per-symbol",
                "0",
                "--min-trade-events-per-symbol",
                "1",
                "--out-json",
                str(out_strategy),
            ]
            proc_strategy = subprocess.run(cmd_strategy, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc_strategy.returncode, 0, msg=proc_strategy.stderr or proc_strategy.stdout)
            gate_strategy = json.loads(out_strategy.read_text(encoding="utf-8"))
            self.assertEqual(gate_strategy["verdict"]["status"], "HOLD")

            cmd_active = [
                sys.executable,
                "TOOLS/rejected_coverage_gate.py",
                "--root",
                str(root),
                "--lookback-hours",
                "24",
                "--focus-group",
                "FX",
                "--symbol-scope",
                "active",
                "--min-active-symbols",
                "1",
                "--min-total-per-symbol",
                "1",
                "--min-rejects-per-symbol",
                "0",
                "--min-trade-events-per-symbol",
                "1",
                "--out-json",
                str(out_active),
            ]
            proc_active = subprocess.run(cmd_active, cwd=str(Path(__file__).resolve().parents[1]), capture_output=True, text=True)
            self.assertEqual(proc_active.returncode, 0, msg=proc_active.stderr or proc_active.stdout)
            gate_active = json.loads(out_active.read_text(encoding="utf-8"))
            self.assertEqual(gate_active["verdict"]["status"], "PASS")
            self.assertEqual(gate_active["summary"]["scope_mode_effective"], "active")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
