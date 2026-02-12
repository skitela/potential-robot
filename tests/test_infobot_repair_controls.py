import unittest
from pathlib import Path
from unittest.mock import patch
import json
import shutil
import uuid

from BIN import infobot


class TestInfobotRepairControls(unittest.TestCase):
    class _Root:
        def __init__(self) -> None:
            self.destroyed = False
            self.withdrawn = False
            self.iconified = False

        def destroy(self) -> None:
            self.destroyed = True

        def withdraw(self) -> None:
            self.withdrawn = True

        def iconify(self) -> None:
            self.iconified = True

    def test_default_repair_command_missing_script(self) -> None:
        root = Path("C:/__oanda_mt5_missing_root_for_test__")
        self.assertEqual("", infobot._default_repair_command(root))

    def test_default_repair_command_with_script(self) -> None:
        root = Path(".").resolve()
        cmd = infobot._default_repair_command(root)
        self.assertIn("CODEX_REPAIR_AUTOMATION.ps1", cmd)
        self.assertIn("{event_id}", cmd)

    def test_materialize_repair_command_with_placeholder(self) -> None:
        cmd = infobot._materialize_repair_command("do_repair --id {event_id}", event_prefix="WEEKLY")
        self.assertIn("WEEKLY-", cmd)
        self.assertNotIn("{event_id}", cmd)

    def test_materialize_repair_command_without_placeholder(self) -> None:
        template = "powershell -NoProfile -File RUN\\CODEX_REPAIR_AUTOMATION.ps1"
        cmd = infobot._materialize_repair_command(template, event_prefix="MANUAL")
        self.assertEqual(template, cmd)

    def test_gui_action_stop_infobot_sets_exit(self) -> None:
        root = self._Root()
        gui = {"root": root, "closed": False, "exit": False}
        infobot._gui_action_stop_infobot(gui)
        self.assertTrue(gui["closed"])
        self.assertTrue(gui["exit"])
        self.assertTrue(root.destroyed)

    @patch("BIN.infobot.subprocess.Popen")
    def test_gui_action_stop_system_runs_stop_cmd(self, popen_mock) -> None:
        root = self._Root()
        gui = {"root": root, "closed": False, "exit": False, "stop_cmd": r"C:\OANDA_MT5_SYSTEM\stop.bat"}
        infobot._gui_action_stop_system(gui)
        popen_mock.assert_called_once()
        called_cmd = popen_mock.call_args[0][0]
        self.assertIn("stop.bat", called_cmd)
        self.assertTrue(gui["closed"])
        self.assertTrue(gui["exit"])
        self.assertTrue(root.destroyed)

    @patch("BIN.infobot.subprocess.Popen")
    def test_gui_action_repair_now_runs_repair(self, popen_mock) -> None:
        gui = {"repair_cmd": "powershell -File RUN\\CODEX_REPAIR_AUTOMATION.ps1 -EventId {event_id}"}
        infobot._gui_action_repair_now(gui)
        popen_mock.assert_called_once()
        called_cmd = popen_mock.call_args[0][0]
        self.assertIn("CODEX_REPAIR_AUTOMATION.ps1", called_cmd)
        self.assertIn("MANUAL-", called_cmd)

    @patch("BIN.infobot.subprocess.Popen")
    def test_gui_action_repair_now_empty_noop(self, popen_mock) -> None:
        infobot._gui_action_repair_now({"repair_cmd": ""})
        popen_mock.assert_not_called()

    def test_gui_status_emit_writes_file(self) -> None:
        temp_dir = Path("EVIDENCE") / "test_tmp" / f"infobot_gui_{uuid.uuid4().hex[:8]}"
        temp_dir.mkdir(parents=True, exist_ok=True)
        try:
            status_path = temp_dir / "infobot_gui_status.json"
            gui = {"status_path": str(status_path)}
            infobot._gui_status_emit(gui, "SYSTEM W NAPRAWIE", "orange")
            raw = status_path.read_text(encoding="utf-8")
            obj = json.loads(raw)
            self.assertEqual("SYSTEM W NAPRAWIE", obj.get("text"))
            self.assertEqual("orange", obj.get("color"))
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_gui_action_window_close_hides_window(self) -> None:
        root = self._Root()
        gui = {"root": root, "hidden": False, "closed": False, "exit": False}
        infobot._gui_action_window_close(gui)
        self.assertTrue(gui["hidden"])
        self.assertTrue(root.withdrawn)
        self.assertFalse(gui["closed"])
        self.assertFalse(gui["exit"])

    def test_gui_action_window_minimize_iconifies(self) -> None:
        root = self._Root()
        gui = {"root": root}
        infobot._gui_action_window_minimize(gui)
        self.assertTrue(root.iconified)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
