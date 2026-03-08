from __future__ import annotations

from pathlib import Path


def test_start_with_oandakey_runs_kernel_config_preseed() -> None:
    script = Path("RUN/START_WITH_OANDAKEY.ps1").read_text(encoding="utf-8", errors="ignore")
    assert "preseed_kernel_config.py" in script
    assert "kernel_config_preseed" in script
