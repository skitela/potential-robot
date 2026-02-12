import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
import shutil
import uuid

from BIN import infobot


class TestInfobotSummaryMetrics(unittest.TestCase):
    def test_pnl_label(self) -> None:
        self.assertEqual("zysk:12.5", infobot._pnl_label(12.5))
        self.assertEqual("strata:3.25", infobot._pnl_label(-3.25))
        self.assertEqual("zero:0.0", infobot._pnl_label(0))

    def test_repair_log_stats(self) -> None:
        temp_dir = Path("EVIDENCE") / f"infobot_stats_{uuid.uuid4().hex[:8]}"
        temp_dir.mkdir(parents=True, exist_ok=True)
        try:
            log_dir = temp_dir / "LOGS" / "infobot"
            log_dir.mkdir(parents=True, exist_ok=True)
            log_path = log_dir / "infobot.log"

            now_local = datetime.now()
            old_local = now_local - timedelta(days=3)
            lines = [
                f"{old_local.strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]} | INFO | ODZYSKANO system dziala\n",
                f"{now_local.strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]} | WARNING | ALARM krytyczny\n",
                f"{now_local.strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]} | INFO | GUI_STATUS text=SYSTEM W NAPRAWIE PRZEZ CODEX\n",
                f"{now_local.strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]} | ERROR | SYSTEM DOWN - operator intervention required\n",
                f"{now_local.strftime('%Y-%m-%d %H:%M:%S,%f')[:-3]} | INFO | ODZYSKANO system dziala\n",
            ]
            log_path.write_text("".join(lines), encoding="utf-8")

            since_utc = datetime.now(timezone.utc) - timedelta(hours=24)
            stats = infobot._repair_log_stats(temp_dir, since_utc=since_utc)
            self.assertEqual(1, stats["alerts"])
            self.assertEqual(1, stats["repairing"])
            self.assertEqual(1, stats["failed"])
            self.assertEqual(1, stats["recovered"])
            self.assertGreaterEqual(stats["attempts"], 1)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
