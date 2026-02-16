import subprocess
import sys
import unittest
from unittest import mock

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from TOOLS import gate_v6


class TestGateV6KeyDetection(unittest.TestCase):
    def test_non_windows_returns_hint(self) -> None:
        with mock.patch.object(gate_v6.os, "name", "posix"):
            present, details = gate_v6.detect_key_volume_label("OANDAKEY")
        self.assertFalse(present)
        self.assertIn("NON_WINDOWS_ENV", details)

    def test_nonzero_powershell_rc_is_not_found(self) -> None:
        cp = subprocess.CompletedProcess(
            args=["powershell", "-NoProfile", "-Command", "Get-Volume"],
            returncode=1,
            stdout="",
            stderr="Access denied\n",
        )
        with mock.patch.object(gate_v6.os, "name", "nt"):
            with mock.patch("TOOLS.gate_v6.subprocess.run", return_value=cp):
                present, details = gate_v6.detect_key_volume_label("OANDAKEY_OFFLINE_SIM")
        self.assertFalse(present)
        self.assertIn("NOT_FOUND", details)
        self.assertIn("rc=1", details)

    def test_timeout_is_not_found(self) -> None:
        with mock.patch.object(gate_v6.os, "name", "nt"):
            with mock.patch(
                "TOOLS.gate_v6.subprocess.run",
                side_effect=subprocess.TimeoutExpired(cmd="powershell", timeout=10),
            ):
                present, details = gate_v6.detect_key_volume_label("OANDAKEY_OFFLINE_SIM")
        self.assertFalse(present)
        self.assertIn("reason='powershell_timeout'", details)

    def test_drive_found_but_keyfile_missing(self) -> None:
        cp = subprocess.CompletedProcess(
            args=["powershell", "-NoProfile", "-Command", "Get-Volume"],
            returncode=0,
            stdout="E\n",
            stderr="",
        )
        with mock.patch.object(gate_v6.os, "name", "nt"):
            with mock.patch("TOOLS.gate_v6.subprocess.run", return_value=cp):
                with mock.patch("TOOLS.gate_v6.Path.exists", return_value=False):
                    present, details = gate_v6.detect_key_volume_label("OANDAKEY")
        self.assertFalse(present)
        self.assertIn("FOUND label='OANDAKEY'", details)
        self.assertIn("exists=False", details)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
