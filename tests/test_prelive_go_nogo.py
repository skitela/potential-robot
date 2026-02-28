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

    def test_cold_start_flag_content_can_disable_override(self) -> None:
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
        (root / "RUN" / "ALLOW_COLD_START_CANARY.flag").write_text("0\n", encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertFalse(bool(rep.get("go")))
        self.assertFalse(bool(rep.get("cold_start_override")))

    def test_dependency_hygiene_skips_without_requirements_file(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "GREEN",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        rep = prelive_go_nogo.evaluate_prelive(root)
        dep = dict(rep.get("dependency_hygiene") or {})
        self.assertEqual("SKIPPED_NO_REQUIREMENTS", str(dep.get("status")))
        self.assertTrue(bool(rep.get("go")))

    def test_dependency_hygiene_contract_checks_present(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "GREEN",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        (root / "requirements.txt").write_text("requests>=0\n", encoding="utf-8")
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "mini.py").write_text("X = 1\n", encoding="utf-8")

        rep = prelive_go_nogo.evaluate_prelive(root)
        dep = dict(rep.get("dependency_hygiene") or {})
        self.assertEqual("PASS", str(dep.get("status")))

        checks = list(rep.get("checks") or [])
        ids = {str(c.get("id")) for c in checks if isinstance(c, dict)}
        self.assertIn("DEPENDENCY_REQUIREMENTS", ids)
        self.assertIn("DEPENDENCY_LOCAL_LINKS", ids)

    def test_no_go_when_dependency_links_are_unresolved(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "GREEN",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        (root / "requirements.txt").write_text("requests>=0\n", encoding="utf-8")
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "broken.py").write_text("import BIN.nonexistent_module\n", encoding="utf-8")

        rep = prelive_go_nogo.evaluate_prelive(root)
        self.assertFalse(bool(rep.get("go")))
        checks = list(rep.get("checks") or [])
        chk = {str(c.get("id")): bool(c.get("ok")) for c in checks if isinstance(c, dict)}
        self.assertFalse(chk.get("DEPENDENCY_LOCAL_LINKS", True))

    def test_dependency_requirements_ignores_local_observers_names(self) -> None:
        root = self._tmpdir()
        learner = {
            "ts_utc": "2099-01-01T00:00:00Z",
            "ttl_sec": 3600,
            "qa_light": "GREEN",
        }
        (root / "META" / "learner_advice.json").write_text(json.dumps(learner), encoding="utf-8")
        (root / "requirements.txt").write_text("requests>=0\n", encoding="utf-8")
        (root / "BIN").mkdir(parents=True, exist_ok=True)
        (root / "BIN" / "__init__.py").write_text("", encoding="utf-8")
        (root / "BIN" / "mini.py").write_text("import OBSERVERS_DRAFT\nimport common\n", encoding="utf-8")
        (root / "OBSERVERS_DRAFT").mkdir(parents=True, exist_ok=True)
        (root / "OBSERVERS_DRAFT" / "common").mkdir(parents=True, exist_ok=True)

        rep = prelive_go_nogo.evaluate_prelive(root)
        dep = dict(rep.get("dependency_hygiene") or {})
        self.assertTrue(bool(dep.get("ok_requirements")))
        self.assertEqual([], list(dep.get("missing_requirements") or []))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
