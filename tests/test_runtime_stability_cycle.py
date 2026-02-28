import tempfile
from pathlib import Path

from TOOLS.runtime_stability_cycle import read_window_phase


def test_read_window_phase_extracts_latest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        log = Path(tmp) / "safetybot.log"
        log.write_text(
            "\n".join(
                [
                    "2026-02-28 08:00:00,000 | INFO | WINDOW_PHASE phase=ACTIVE window=EUROPE",
                    "2026-02-28 09:00:00,000 | INFO | WINDOW_PHASE phase=PRE_OPEN window=ASIA",
                ]
            ),
            encoding="utf-8",
        )
        phase = read_window_phase(log)
        assert phase["phase"] == "PRE_OPEN"
        assert phase["window"] == "ASIA"
