from __future__ import annotations

import datetime as dt


def test_fx_window_weekend_guard_keeps_asia_window_off_on_saturday() -> None:
    from BIN import safetybot as sb

    orig_tw = getattr(sb.CFG, "trade_windows", None)
    orig_buf = getattr(sb.CFG, "trade_closeout_buffer_min", None)
    try:
        sb.CFG.trade_windows = {
            "FX_ASIA": {
                "group": "FX",
                "anchor_tz": "Asia/Tokyo",
                "start_hm": [9, 0],
                "end_hm": [18, 0],
            }
        }
        sb.CFG.trade_closeout_buffer_min = 15

        # Saturday 2026-03-07 01:00 UTC == Saturday morning in Tokyo, but FX should be closed.
        ctx = sb.trade_window_ctx(dt.datetime(2026, 3, 7, 1, 0, tzinfo=dt.timezone.utc))
        assert ctx["phase"] == "OFF"
        assert ctx["window_id"] is None
        assert ctx["entry_allowed"] is False
    finally:
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


def test_group_market_session_open_for_fx_respects_ny_weekend_boundary() -> None:
    from BIN import safetybot as sb

    # Saturday NY time => closed
    assert sb.group_market_session_open("FX", dt.datetime(2026, 3, 7, 1, 0, tzinfo=dt.timezone.utc)) is False
    # Sunday 16:30 NY (before reopen) => still closed; 2026-03-08 after DST switch => 20:30 UTC
    assert sb.group_market_session_open("FX", dt.datetime(2026, 3, 8, 20, 30, tzinfo=dt.timezone.utc)) is False
    # Sunday 17:30 NY (after reopen) => open; 2026-03-08 after DST switch => 21:30 UTC
    assert sb.group_market_session_open("FX", dt.datetime(2026, 3, 8, 21, 30, tzinfo=dt.timezone.utc)) is True
