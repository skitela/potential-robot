import builtins
import json
import shutil
import sys
import unittest
import uuid
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from TOOLS import audit_symbols_get_mt5
from TOOLS import online_smoke_mt5


def _import_side_effect_for_missing_mt5(name, globals=None, locals=None, fromlist=(), level=0):
    real_import = _import_side_effect_for_missing_mt5._real_import  # type: ignore[attr-defined]
    if name == "MetaTrader5":
        raise ModuleNotFoundError("No module named 'MetaTrader5'")
    return real_import(name, globals, locals, fromlist, level)


_import_side_effect_for_missing_mt5._real_import = builtins.__import__  # type: ignore[attr-defined]


class TestOnlineSimTools(unittest.TestCase):
    def _tmpdir(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_online_sim_tools"
        path = base / f"case_{uuid.uuid4().hex}"
        path.mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(path, ignore_errors=True))
        return path

    def test_online_smoke_offline_sim_missing_mt5(self) -> None:
        tmp = self._tmpdir()
        out = tmp / "smoke.json"
        argv = [
            "online_smoke_mt5.py",
            "--mt5-path",
            r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
            "--offline-sim",
            "--out",
            str(out),
        ]
        with mock.patch("TOOLS.online_smoke_mt5.platform.system", return_value="Windows"):
            with mock.patch("builtins.__import__", side_effect=_import_side_effect_for_missing_mt5):
                with mock.patch.object(sys, "argv", argv):
                    rc = online_smoke_mt5.main()
        self.assertEqual(rc, 0)
        payload = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(str(payload.get("result")), "DO_WERYFIKACJI_ONLINE")
        self.assertIn("Offline sim", str(payload.get("error") or ""))

    def test_online_smoke_without_offline_sim_fails_on_missing_mt5(self) -> None:
        tmp = self._tmpdir()
        out = tmp / "smoke_fail.json"
        argv = [
            "online_smoke_mt5.py",
            "--mt5-path",
            r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
            "--out",
            str(out),
        ]
        with mock.patch("TOOLS.online_smoke_mt5.platform.system", return_value="Windows"):
            with mock.patch("builtins.__import__", side_effect=_import_side_effect_for_missing_mt5):
                with mock.patch.object(sys, "argv", argv):
                    rc = online_smoke_mt5.main()
        self.assertEqual(rc, 1)
        payload = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(str(payload.get("result")), "FAIL")

    def test_symbols_audit_offline_sim_missing_mt5(self) -> None:
        tmp = self._tmpdir()
        out = tmp / "symbols.json"
        argv = [
            "audit_symbols_get_mt5.py",
            "--mt5-path",
            r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
            "--offline-sim",
            "--out",
            str(out),
        ]
        with mock.patch("TOOLS.audit_symbols_get_mt5.platform.system", return_value="Windows"):
            with mock.patch("builtins.__import__", side_effect=_import_side_effect_for_missing_mt5):
                with mock.patch.object(sys, "argv", argv):
                    rc = audit_symbols_get_mt5.main()
        self.assertEqual(rc, 0)
        payload = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(str(payload.get("result")), "DO_WERYFIKACJI_ONLINE")
        self.assertIn("Offline sim", str(payload.get("error") or ""))

    def test_symbols_audit_without_offline_sim_fails_on_missing_mt5(self) -> None:
        tmp = self._tmpdir()
        out = tmp / "symbols_fail.json"
        argv = [
            "audit_symbols_get_mt5.py",
            "--mt5-path",
            r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
            "--out",
            str(out),
        ]
        with mock.patch("TOOLS.audit_symbols_get_mt5.platform.system", return_value="Windows"):
            with mock.patch("builtins.__import__", side_effect=_import_side_effect_for_missing_mt5):
                with mock.patch.object(sys, "argv", argv):
                    rc = audit_symbols_get_mt5.main()
        self.assertEqual(rc, 1)
        payload = json.loads(out.read_text(encoding="utf-8"))
        self.assertEqual(str(payload.get("result")), "FAIL")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
