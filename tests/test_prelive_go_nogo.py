import json
import shutil
import unittest
import uuid
from pathlib import Path

from TOOLS import prelive_go_nogo


class TestPreliveGoNoGo(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = Path("TMP_AUDIT_IO") / "test_prelive_go_nogo"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        (path / "META").mkdir(parents=True, exist_ok=True)
        (path / "LOGS").mkdir(parents=True, exist_ok=True)
        (path / "RUN").mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_no_go_when_qa_red(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "RED",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertFalse(bool(rep.get("go")))

    def test_go_on_clean_state(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "GREEN",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertTrue(bool(rep.get("go")))

    def test_cold_start_canary_override_allows_go(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "RED",
            "metrics": {"n": 0},
        }
        report = {
            "n_total": 0,
            "anti_overfit_reasons": ["N_TOO_LOW"],
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        (root / "LOGS" / "learner_offline_report.json").write_text(json.dumps(report), encoding="utf-8")
        (root / "RUN" / "ALLOW_COLD_START_CANARY.flag").write_text("1\n", encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertTrue(bool(rep.get("go")))
        self.assertTrue(bool(rep.get("cold_start_override")))
        self.assertEqual(str(rep.get("reason")), "GO_COLD_START_CANARY")

    def test_cold_start_override_blocked_on_incident(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "RED",
            "metrics": {"n": 0},
        }
        report = {
            "n_total": 0,
            "anti_overfit_reasons": ["N_TOO_LOW"],
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        (root / "LOGS" / "learner_offline_report.json").write_text(json.dumps(report), encoding="utf-8")
        (root / "RUN" / "ALLOW_COLD_START_CANARY.flag").write_text("1\n", encoding="utf-8")
        incident = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "severity": "ERROR",
            "kind": "retcode",
            "message": "blocked",
        }
        (root / "LOGS" / "incident_journal.jsonl").write_text(json.dumps(incident) + "\n", encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertFalse(bool(rep.get("go")))
        self.assertFalse(bool(rep.get("cold_start_override")))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
