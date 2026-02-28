import tempfile
from pathlib import Path

from TOOLS.runtime_kpi_snapshot import parse_log_kpi


def test_parse_log_kpi_counts_events() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "safetybot.log"
        log_path.write_text(
            "\n".join(
                [
                    "2026-02-28 09:00:00,000 | INFO | ORDER_QUEUE_TIMEOUT seq=1",
                    "2026-02-28 09:00:01,000 | INFO | ORDER_QUEUE_FULL seq=1",
                    "2026-02-28 09:00:02,000 | WARNING | SCAN_SLOW scan_ms=2000",
                    "2026-02-28 09:00:03,000 | CRITICAL | HEARTBEAT_FAILSAFE_ACTIVE",
                ]
            ),
            encoding="utf-8",
        )
        got = parse_log_kpi(log_path, hours=72)
        assert int(got["order_queue_timeout_count"]) == 1
        assert int(got["order_queue_full_count"]) == 1
        assert int(got["scan_slow_count"]) == 1
        assert int(got["heartbeat_failsafe_active_count"]) == 1
