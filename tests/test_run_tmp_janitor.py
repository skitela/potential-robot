import os
import shutil
import time
import unittest
import uuid
from pathlib import Path

from TOOLS.run_tmp_janitor import run_janitor


class TestRunTmpJanitor(unittest.TestCase):
    def test_plan_respects_prefix_retention_and_age(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "EVIDENCE" / "test_tmp" / f"janitor_{uuid.uuid4().hex[:8]}").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        run_dir = tmp_root / "RUN"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            now = time.time()
            files = []
            for idx in range(6):
                p = run_dir / f"infobot_gui_status.json.tmp.111.{idx}"
                p.write_text("{}", encoding="utf-8")
                # idx 0 newest, idx 5 oldest
                age = idx * 120
                os.utime(p, (now - age, now - age))
                files.append(p)

            report = run_janitor(
                tmp_root,
                run_rel="RUN",
                min_age_sec=180,
                keep_per_prefix=2,
                max_delete=100,
                apply=False,
            )
            self.assertEqual(report["status"], "PASS")
            planned = {a["path"] for a in report["actions"] if a["result"] == "PLAN"}

            # kept by prefix retention (2 newest)
            self.assertNotIn(str(files[0].resolve()), planned)
            self.assertNotIn(str(files[1].resolve()), planned)
            # stale enough + beyond retention -> planned
            self.assertIn(str(files[2].resolve()), planned)
            self.assertIn(str(files[3].resolve()), planned)
            self.assertIn(str(files[4].resolve()), planned)
            self.assertIn(str(files[5].resolve()), planned)
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)

    def test_apply_deletes_only_stale_candidates(self) -> None:
        workspace = Path(__file__).resolve().parents[1]
        tmp_root = (workspace / "EVIDENCE" / "test_tmp" / f"janitor_{uuid.uuid4().hex[:8]}").resolve()
        shutil.rmtree(tmp_root, ignore_errors=True)
        tmp_root.mkdir(parents=True, exist_ok=True)
        run_dir = tmp_root / "RUN"
        run_dir.mkdir(parents=True, exist_ok=True)
        try:
            now = time.time()
            keep = run_dir / "infobot_heartbeat.json.tmp.222.keep"
            old_1 = run_dir / "infobot_heartbeat.json.tmp.222.old1"
            old_2 = run_dir / "infobot_heartbeat.json.tmp.222.old2"
            keep.write_text("{}", encoding="utf-8")
            old_1.write_text("{}", encoding="utf-8")
            old_2.write_text("{}", encoding="utf-8")
            os.utime(keep, (now - 30, now - 30))
            os.utime(old_1, (now - 600, now - 600))
            os.utime(old_2, (now - 900, now - 900))

            report = run_janitor(
                tmp_root,
                run_rel="RUN",
                min_age_sec=120,
                keep_per_prefix=1,
                max_delete=100,
                apply=True,
            )
            self.assertEqual(report["status"], "PASS")
            self.assertTrue(keep.exists())
            self.assertFalse(old_1.exists())
            self.assertFalse(old_2.exists())
            self.assertGreaterEqual(int(report["summary"]["deleted"]), 2)
            self.assertEqual(int(report["summary"]["failed"]), 0)
        finally:
            shutil.rmtree(tmp_root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
