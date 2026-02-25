from __future__ import annotations

import datetime as dt


def test_trade_window_ctx_overnight_closeout_buffer() -> None:
    # Regression: overnight windows must not become CLOSEOUT for the entire duration.
    # Example window: Europe/Warsaw 23:00-09:00 with 15-min closeout buffer.
    from BIN import safetybot as sb

    orig_tw = getattr(sb.CFG, "trade_windows", None)
    orig_buf = getattr(sb.CFG, "trade_closeout_buffer_min", None)
    try:
        sb.CFG.trade_windows = {
            "CRYPTO_NIGHT": {
                "group": "CRYPTO",
                "anchor_tz": "Europe/Warsaw",
                "start_hm": [23, 0],
                "end_hm": [9, 0],
            }
        }
        sb.CFG.trade_closeout_buffer_min = 15

        # 2026-02-25 23:05 PL => 2026-02-25 22:05 UTC (CET = UTC+1)
        ctx = sb.trade_window_ctx(dt.datetime(2026, 2, 25, 22, 5, tzinfo=dt.timezone.utc))
        assert ctx["window_id"] == "CRYPTO_NIGHT"
        assert ctx["phase"] == "ACTIVE"
        assert ctx["entry_allowed"] is True

        # 2026-02-26 08:50 PL => 2026-02-26 07:50 UTC
        ctx2 = sb.trade_window_ctx(dt.datetime(2026, 2, 26, 7, 50, tzinfo=dt.timezone.utc))
        assert ctx2["window_id"] == "CRYPTO_NIGHT"
        assert ctx2["phase"] == "CLOSEOUT"
        assert ctx2["entry_allowed"] is False
    finally:
        # Restore globals to avoid cross-test contamination.
        if orig_tw is None:
            try:
                del sb.CFG.trade_windows
            except Exception:
                pass
        else:
            sb.CFG.trade_windows = orig_tw

        if orig_buf is None:
            try:
                del sb.CFG.trade_closeout_buffer_min
            except Exception:
                pass
        else:
            sb.CFG.trade_closeout_buffer_min = orig_buf

