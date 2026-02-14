# -*- coding: utf-8 -*-
import json
import os
import shutil
import unittest
import uuid
from pathlib import Path

from TOOLS.generate_audit_report_v1_2 import _find_latest_run, _status_from_verdict


def _write_json(path: Path, payload: dict, encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding=encoding)


def _make_temp_root() -> Path:
    base = (Path(__file__).resolve().parent / "_tmp_housekeeping").resolve()
    base.mkdir(parents=True, exist_ok=True)
    root = base / f"gen_audit_v12_{uuid.uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    return root


class TestGenerateAuditReportV12(unittest.TestCase):
    def test_status_from_verdict_accepts_utf16_json(self) -> None:
        root = _make_temp_root()
        try:
            verdict = root / "verdict.json"
            _write_json(verdict, {"status": "PASS"}, encoding="utf-16")
            self.assertEqual(_status_from_verdict(verdict), "PASS")
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_find_latest_run_prefers_latest_timestamp_name(self) -> None:
        root = _make_temp_root()
        try:
            older = root / "20260214_165036"
            newer = root / "20260214_165916"

            _write_json(older / "offline" / "verdict.json", {"status": "PASS"})
            _write_json(older / "training" / "verdict.json", {"status": "PASS"})
            _write_json(newer / "offline" / "verdict.json", {"status": "PASS"})
            _write_json(newer / "training" / "verdict.json", {"status": "PASS"})

            os.utime(older, None)
            picked = _find_latest_run(root)
            self.assertEqual(picked.name, "20260214_165916")
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
