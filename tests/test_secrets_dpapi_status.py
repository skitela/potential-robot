import json
import shutil
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

from TOOLS import secrets_dpapi as sd


class TestSecretsDpapiStatus(unittest.TestCase):
    @staticmethod
    def _mkroot() -> Path:
        base = Path("TMP_AUDIT_IO") / "test_secrets_dpapi_status"
        base.mkdir(parents=True, exist_ok=True)
        root = base / f"case_{uuid.uuid4().hex}"
        root.mkdir(parents=True, exist_ok=False)
        return root

    def test_missing_secret_status(self) -> None:
        root = self._mkroot()
        try:
            st = sd.rotation_status("openai", root_override=str(root))
            self.assertEqual(st["status"], "missing")
            self.assertFalse(st["present"])
        finally:
            shutil.rmtree(root, ignore_errors=True)

    def test_rotation_due_status(self) -> None:
        root = self._mkroot()
        try:
            paths = sd.secret_paths("openai", root_override=str(root))
            paths["secret_dir"].mkdir(parents=True, exist_ok=True)
            paths["cipher_path"].write_text("ciphertext", encoding="utf-8")
            old = (datetime.now(timezone.utc) - timedelta(days=61)).isoformat().replace("+00:00", "Z")
            meta = {"provider": "openai", "created_at": old, "last_rotated_at": old}
            paths["meta_path"].write_text(json.dumps(meta), encoding="utf-8")

            st = sd.rotation_status("openai", rotation_days=60, root_override=str(root))
            self.assertEqual(st["status"], "rotation_due")
            self.assertTrue(st["present"])
            self.assertTrue(st["rotation_due"])
            self.assertGreaterEqual(int(st["age_days"]), 61)
        finally:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
