import shutil
import unittest
import uuid
import os
import time
from pathlib import Path

from TOOLS.runtime_housekeeping import run_housekeeping


class TestRuntimeHousekeeping(unittest.TestCase):
    def test_apply_removes_safe_artifacts(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "EVIDENCE" / "test_tmp" / f"hk_{uuid.uuid4().hex[:8]}").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        try:
            (tmp_root / "__pycache__").mkdir(parents=True, exist_ok=True)
            (tmp_root / "__pycache__" / "a.pyc").write_bytes(b"x")
            (tmp_root / "RUN").mkdir(parents=True, exist_ok=True)
            (tmp_root / "RUN" / "infobot.lock").write_text("1", encoding="utf-8")
            (tmp_root / "LOGS").mkdir(parents=True, exist_ok=True)
            (tmp_root / "LOGS" / "sample.log").write_text("abc", encoding="utf-8")

            report = run_housekeeping(
                tmp_root,
                apply=True,
                keep_runs=5,
                keep_audit_v12_runs=3,
                keep_gates=10,
                max_single_log_mb=1,
            )
            self.assertEqual(report["status"], "PASS")
            self.assertGreaterEqual(int(report["summary"]["actions_total"]), 1)
            self.assertIn("actions_failed", report["summary"])
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)

    def test_retention_plan_targets_oldest_entries_for_known_evidence_groups(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "EVIDENCE" / "test_tmp" / f"hk_{uuid.uuid4().hex[:8]}").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        try:
            audit_root = tmp_root / "EVIDENCE" / "audit_v12_live"
            audit_root.mkdir(parents=True, exist_ok=True)
            old_run = audit_root / "20260101_000000"
            new_run = audit_root / "20260102_000000"
            template_file = audit_root / "template_validate.json"
            old_run.mkdir(parents=True, exist_ok=True)
            new_run.mkdir(parents=True, exist_ok=True)
            (old_run / "x.txt").write_text("old", encoding="utf-8")
            (new_run / "x.txt").write_text("new", encoding="utf-8")
            template_file.write_text("{}", encoding="utf-8")
            now_ts = time.time()
            os.utime(old_run, (now_ts - 120, now_ts - 120))
            os.utime(new_run, (now_ts - 10, now_ts - 10))
            os.utime(template_file, (now_ts - 240, now_ts - 240))

            smoke_root = tmp_root / "EVIDENCE" / "online_smoke"
            smoke_root.mkdir(parents=True, exist_ok=True)
            old_smoke = smoke_root / "old.json"
            new_smoke = smoke_root / "new.json"
            old_smoke.write_text("{}", encoding="utf-8")
            new_smoke.write_text("{}", encoding="utf-8")
            os.utime(old_smoke, (now_ts - 120, now_ts - 120))
            os.utime(new_smoke, (now_ts - 10, now_ts - 10))

            housekeeping_root = tmp_root / "EVIDENCE" / "housekeeping"
            housekeeping_root.mkdir(parents=True, exist_ok=True)
            old_housekeeping = housekeeping_root / "old_housekeeping.json"
            new_housekeeping = housekeeping_root / "new_housekeeping.json"
            old_housekeeping.write_text("{}", encoding="utf-8")
            new_housekeeping.write_text("{}", encoding="utf-8")
            os.utime(old_housekeeping, (now_ts - 120, now_ts - 120))
            os.utime(new_housekeeping, (now_ts - 10, now_ts - 10))

            gates_root = tmp_root / "EVIDENCE" / "gates"
            gates_root.mkdir(parents=True, exist_ok=True)
            old_gate = gates_root / "old_gate.txt"
            new_gate = gates_root / "new_gate.txt"
            old_gate.write_text("old", encoding="utf-8")
            new_gate.write_text("new", encoding="utf-8")
            os.utime(old_gate, (now_ts - 120, now_ts - 120))
            os.utime(new_gate, (now_ts - 10, now_ts - 10))

            hard_root = tmp_root / "EVIDENCE" / "hard_xcross"
            hard_root.mkdir(parents=True, exist_ok=True)
            old_hard = hard_root / "20260101_010101"
            new_hard = hard_root / "20260102_010101"
            old_hard.mkdir(parents=True, exist_ok=True)
            new_hard.mkdir(parents=True, exist_ok=True)
            (old_hard / "x.txt").write_text("old", encoding="utf-8")
            (new_hard / "x.txt").write_text("new", encoding="utf-8")
            os.utime(old_hard, (now_ts - 120, now_ts - 120))
            os.utime(new_hard, (now_ts - 10, now_ts - 10))

            preflight_root = tmp_root / "EVIDENCE" / "preflight_safe"
            preflight_root.mkdir(parents=True, exist_ok=True)
            old_preflight = preflight_root / "20260101_020202"
            new_preflight = preflight_root / "20260102_020202"
            old_preflight.mkdir(parents=True, exist_ok=True)
            new_preflight.mkdir(parents=True, exist_ok=True)
            (old_preflight / "x.txt").write_text("old", encoding="utf-8")
            (new_preflight / "x.txt").write_text("new", encoding="utf-8")
            os.utime(old_preflight, (now_ts - 120, now_ts - 120))
            os.utime(new_preflight, (now_ts - 10, now_ts - 10))

            report = run_housekeeping(
                tmp_root,
                apply=False,
                keep_runs=1,
                keep_audit_v12_runs=1,
                keep_gates=1,
                max_single_log_mb=1,
            )
            self.assertEqual(report["status"], "PASS")
            planned = {
                action["path"]
                for action in report["actions"]
                if action["kind"] == "evidence_retention" and action["result"] == "PLAN"
            }
            self.assertIn(str(old_run.resolve()), planned)
            self.assertIn(str(old_smoke.resolve()), planned)
            self.assertIn(str(old_hard.resolve()), planned)
            self.assertIn(str(old_preflight.resolve()), planned)
            self.assertIn(str(old_gate.resolve()), planned)
            self.assertIn(str(old_housekeeping.resolve()), planned)
            self.assertNotIn(str(new_run.resolve()), planned)
            self.assertNotIn(str(new_smoke.resolve()), planned)
            self.assertNotIn(str(new_hard.resolve()), planned)
            self.assertNotIn(str(new_preflight.resolve()), planned)
            self.assertNotIn(str(new_gate.resolve()), planned)
            self.assertNotIn(str(new_housekeeping.resolve()), planned)
            self.assertNotIn(str(template_file.resolve()), planned)
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)

    def test_plan_includes_temp_glob_dirs_and_run_tmp_files(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "EVIDENCE" / "test_tmp" / f"hk_{uuid.uuid4().hex[:8]}").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        try:
            probe_dir = tmp_root / "EVIDENCE" / "perm_probe_test123"
            probe_dir.mkdir(parents=True, exist_ok=True)
            (probe_dir / "x.txt").write_text("x", encoding="utf-8")

            run_dir = tmp_root / "RUN"
            run_dir.mkdir(parents=True, exist_ok=True)
            tmp_file = run_dir / "system_control_last.json.tmp"
            tmp_file.write_text("{}", encoding="utf-8")

            report = run_housekeeping(
                tmp_root,
                apply=False,
                keep_runs=1,
                keep_audit_v12_runs=1,
                keep_gates=1,
                max_single_log_mb=1,
            )
            planned_by_kind = {}
            for action in report["actions"]:
                if action["result"] != "PLAN":
                    continue
                planned_by_kind.setdefault(action["kind"], set()).add(action["path"])

            self.assertIn(str(probe_dir.resolve()), planned_by_kind.get("temp_root_glob", set()))
            self.assertIn(str(tmp_file.resolve()), planned_by_kind.get("run_temp_file", set()))
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
