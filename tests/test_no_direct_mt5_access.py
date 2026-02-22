from __future__ import annotations

import builtins
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))


def _import_side_effect_for_missing_mt5(name, globals=None, locals=None, fromlist=(), level=0):
    real_import = _import_side_effect_for_missing_mt5._real_import  # type: ignore[attr-defined]
    if name == "MetaTrader5":
        raise ModuleNotFoundError("No module named 'MetaTrader5'")
    return real_import(name, globals, locals, fromlist, level)


_import_side_effect_for_missing_mt5._real_import = builtins.__import__  # type: ignore[attr-defined]


class TestNoDirectMT5Access(unittest.TestCase):
    def test_offline_modules_import_without_mt5(self) -> None:
        """
        Offline policy: core modules should be importable even when MetaTrader5 is unavailable.

        This test simulates a missing MetaTrader5 dependency (regardless of what's installed on
        the developer machine) and ensures that importing offline-safe modules does not attempt
        to import MetaTrader5 as a side-effect.
        """
        saved = sys.modules.pop("MetaTrader5", None)
        try:
            with mock.patch("builtins.__import__", side_effect=_import_side_effect_for_missing_mt5):
                from BIN import repair_agent  # noqa: F401
                from BIN import runtime_root  # noqa: F401
                from BIN import scudfab02  # noqa: F401
        finally:
            if saved is not None:
                sys.modules["MetaTrader5"] = saved


if __name__ == "__main__":
    raise SystemExit(unittest.main())

