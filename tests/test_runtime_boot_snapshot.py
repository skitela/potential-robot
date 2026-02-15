import json
import shutil
import sys
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

import safetybot


class TestRuntimeBootSnapshot(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_runtime_boot_snapshot"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_build_payload_contains_core_sections(self):
        payload = safetybot.build_runtime_boot_snapshot_payload(
            Path("C:/OANDA_MT5_SYSTEM"),
            [("EURUSD", "EURUSD", "FX"), ("XAUUSD", "XAUUSD", "METAL")],
        )
        self.assertEqual(int(payload.get("universe_count") or 0), 2)
        self.assertIn("limits", payload)
        self.assertIn("symbol_policy", payload)
        self.assertIn("execution_burst_guard", payload)
        self.assertIn("universe", payload)
        self.assertTrue(str(payload.get("runtime_root", "")).upper().endswith("OANDA_MT5_SYSTEM"))

    def test_write_snapshot_persists_json(self):
        tmp = self._tmpdir()
        out = safetybot.write_runtime_boot_snapshot(tmp, [("EURUSD", "EURUSD", "FX")])
        self.assertIsNotNone(out)
        self.assertTrue(Path(out).exists())
        data = json.loads(Path(out).read_text(encoding="utf-8"))
        self.assertEqual(int(data.get("universe_count") or 0), 1)
        self.assertEqual(str(data.get("universe", [{}])[0].get("base") or ""), "EURUSD")


if __name__ == "__main__":
    raise SystemExit(unittest.main())

