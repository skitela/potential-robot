import json
import shutil
import unittest
import uuid
from pathlib import Path

from BIN import repair_agent as ra


class TestRepairCodexEscalation(unittest.TestCase):
    @staticmethod
    def _mktempdir() -> Path:
        base = Path("TMP_AUDIT_IO") / "test_repair_codex_escalation"
        base.mkdir(parents=True, exist_ok=True)
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=False)
        return path

    def test_write_codex_request_contract(self) -> None:
        run_dir = self._mktempdir()
        try:
            req_path = run_dir / "codex_repair_request.json"
            alert = {"reason": "critical:missing_lock", "severity": "CRITICAL"}

            ra._write_codex_request(
                req_path,
                root=run_dir,
                event_id="ALERT-1234",
                attempt=3,
                alert=alert,
            )

            self.assertTrue(req_path.exists())
            data = json.loads(req_path.read_text(encoding="utf-8"))
            self.assertEqual(data["event_id"], "ALERT-1234")
            self.assertEqual(data["status"], "pending")
            self.assertEqual(int(data["attempt_internal"]), 3)
            self.assertEqual(data["reason"], "critical:missing_lock")
        finally:
            shutil.rmtree(run_dir, ignore_errors=True)

    def test_default_codex_command_contains_script(self) -> None:
        root = self._mktempdir()
        try:
            cmd = ra._default_codex_command(root, "ALERT-9999")
            self.assertIn("CODEX_REPAIR_AUTOMATION.ps1", cmd)
            self.assertIn("ALERT-9999", cmd)
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_iso_age_sec(self) -> None:
        self.assertIsNone(ra._iso_age_sec(""))
        self.assertIsNone(ra._iso_age_sec("not-a-ts"))
        age = ra._iso_age_sec("2026-01-01T00:00:00Z")
        self.assertIsNotNone(age)
        self.assertGreaterEqual(float(age), 0.0)

    def test_escalates_only_after_third_retry(self) -> None:
        root = self._mktempdir()
        run_dir = root / "RUN"
        log_dir = root / "LOGS"
        run_dir.mkdir(parents=True, exist_ok=True)
        log_dir.mkdir(parents=True, exist_ok=True)
        alert_path = run_dir / "infobot_alert.json"
        alert_path.write_text(
            json.dumps(
                {
                    "event_id": "ALERT-THREE-RETRY",
                    "ts_utc": "2026-02-12T00:00:00Z",
                    "severity": "CRITICAL",
                    "reason": "simulated",
                    "resolved": False,
                },
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

        saved = {
            "get_runtime_root": ra.get_runtime_root,
            "RESTART_WAIT_SEC": ra.RESTART_WAIT_SEC,
            "CHECK_SEC": ra.CHECK_SEC,
            "MAX_RETRY_PER_ALERT": ra.MAX_RETRY_PER_ALERT,
            "CODEX_ESCALATE_ENABLED": ra.CODEX_ESCALATE_ENABLED,
            "AUTO_HOTFIX": ra.AUTO_HOTFIX,
            "CODEX_TIMEOUT_SEC": ra.CODEX_TIMEOUT_SEC,
            "_run_diag": ra._run_diag,
            "_restart_all": ra._restart_all,
            "_component_ok": ra._component_ok,
            "_spawn_cmd": ra._spawn_cmd,
            "sleep": ra.time.sleep,
        }

        spawn_calls = []
        sleep_calls = {"n": 0}

        def _fake_spawn(cmd: str):
            spawn_calls.append(cmd)
            return True, "989898"

        def _fake_sleep(_sec: float):
            sleep_calls["n"] += 1
            if sleep_calls["n"] >= 8:
                raise KeyboardInterrupt("stop")

        try:
            ra.get_runtime_root = lambda enforce=True: root
            ra.RESTART_WAIT_SEC = 0
            ra.CHECK_SEC = 0
            ra.MAX_RETRY_PER_ALERT = 3
            ra.CODEX_ESCALATE_ENABLED = True
            ra.AUTO_HOTFIX = False
            ra.CODEX_TIMEOUT_SEC = 21600
            ra._run_diag = lambda _root: None
            ra._restart_all = lambda _root: None
            ra._component_ok = lambda _root: False
            ra._spawn_cmd = _fake_spawn
            ra.time.sleep = _fake_sleep

            with self.assertRaises(KeyboardInterrupt):
                ra.main()

            request = json.loads((run_dir / "codex_repair_request.json").read_text(encoding="utf-8"))
            status = json.loads((run_dir / "repair_status.json").read_text(encoding="utf-8"))

            self.assertEqual(int(request["attempt_internal"]), 3)
            self.assertEqual(status["status"], "repairing_codex")
            self.assertEqual(int(status["attempt"]), 3)
            self.assertEqual(len(spawn_calls), 1)
        finally:
            ra.get_runtime_root = saved["get_runtime_root"]
            ra.RESTART_WAIT_SEC = saved["RESTART_WAIT_SEC"]
            ra.CHECK_SEC = saved["CHECK_SEC"]
            ra.MAX_RETRY_PER_ALERT = saved["MAX_RETRY_PER_ALERT"]
            ra.CODEX_ESCALATE_ENABLED = saved["CODEX_ESCALATE_ENABLED"]
            ra.AUTO_HOTFIX = saved["AUTO_HOTFIX"]
            ra.CODEX_TIMEOUT_SEC = saved["CODEX_TIMEOUT_SEC"]
            ra._run_diag = saved["_run_diag"]
            ra._restart_all = saved["_restart_all"]
            ra._component_ok = saved["_component_ok"]
            ra._spawn_cmd = saved["_spawn_cmd"]
            ra.time.sleep = saved["sleep"]
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
