import shutil
import sys
import types
import unittest
import uuid
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
BIN_DIR = ROOT / "BIN"
if str(BIN_DIR) not in sys.path:
    sys.path.insert(0, str(BIN_DIR))

if "MetaTrader5" not in sys.modules:
    mt5_stub = types.ModuleType("MetaTrader5")
    mt5_stub.TIMEFRAME_M5 = 5
    mt5_stub.TIMEFRAME_H4 = 16388
    mt5_stub.TIMEFRAME_D1 = 16408
    sys.modules["MetaTrader5"] = mt5_stub

import safetybot


class TestUsbKeyEnvDpapi(unittest.TestCase):
    def _tmp_usb(self) -> Path:
        base = ROOT / "TMP_AUDIT_IO" / "test_usb_key_env_dpapi"
        usb = base / f"case_{uuid.uuid4().hex}"
        (usb / "TOKEN").mkdir(parents=True, exist_ok=True)
        self.addCleanup(lambda: shutil.rmtree(usb, ignore_errors=True))
        return usb

    def test_load_env_plaintext_password_still_supported(self) -> None:
        usb = self._tmp_usb()
        env = usb / "TOKEN" / "BotKey.env"
        env.write_text(
            "\n".join(
                [
                    "MT5_LOGIN=123",
                    "MT5_PASSWORD=plain_secret",
                    "MT5_SERVER=OANDATMS-MT5",
                    "MT5_PATH=C:\\Program Files\\OANDA TMS MT5 Terminal\\terminal64.exe",
                ]
            ),
            encoding="utf-8",
        )

        cfg = safetybot.load_env(usb)
        self.assertEqual(cfg.get("MT5_PASSWORD"), "plain_secret")

    def test_load_env_dpapi_password_is_decrypted(self) -> None:
        usb = self._tmp_usb()
        env = usb / "TOKEN" / "BotKey.env"
        env.write_text(
            "\n".join(
                [
                    "MT5_LOGIN=123",
                    "MT5_PASSWORD_MODE=DPAPI_CURRENT_USER",
                    "MT5_PASSWORD_DPAPI=01000000deadbeef",
                    "MT5_SERVER=OANDATMS-MT5",
                ]
            ),
            encoding="utf-8",
        )

        with mock.patch.object(safetybot, "_decrypt_dpapi_secure_string", return_value="decoded_secret") as dec:
            cfg = safetybot.load_env(usb)

        dec.assert_called_once_with("01000000deadbeef")
        self.assertEqual(cfg.get("MT5_PASSWORD"), "decoded_secret")

    def test_load_env_dpapi_failure_raises_runtime_error(self) -> None:
        usb = self._tmp_usb()
        env = usb / "TOKEN" / "BotKey.env"
        env.write_text("MT5_PASSWORD_DPAPI=01000000deadbeef", encoding="utf-8")

        with mock.patch.object(safetybot, "_decrypt_dpapi_secure_string", side_effect=RuntimeError("boom")):
            with self.assertRaises(RuntimeError) as ctx:
                safetybot.load_env(usb)

        self.assertIn("Nie mozna odszyfrowac", str(ctx.exception))


if __name__ == "__main__":
    raise SystemExit(unittest.main())
