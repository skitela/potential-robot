# OANDATMS MT5 Snapshot - 2026-02-23

- Generated UTC: 2026-02-23T23:34:22.274473Z
- Server: OANDATMS-MT5
- Account login: 37360
- Symbols exported: EURUSD.pro, GBPUSD.pro, USDCHF.pro, USDCAD.pro, GOLD.pro, SILVER.pro

## MT5 Python field schemas

- rates: close, high, low, open, real_volume, spread, tick_volume, time
- ticks: ask, bid, flags, last, time, time_msc, volume, volume_real

## Internal DB field schemas

- m5_bars: c, h, l, o, symbol, t_utc
- decision_events: choice_A, choice_shadowB, entry_price, event_id, is_paper, mt5_deal, mt5_order, outcome_closed_ts_utc, outcome_commission, outcome_fee, outcome_pnl_net, outcome_profit, outcome_swap, price_requests_trade, price_used, server_time_anchor, signal, sl, spread_points, sys_used, topk_json, tp, ts_utc, verdict_light, volume

## Naming map (semantic, not exact names)

| MT5 rates field | Internal equivalent |
|---|---|
| time | t_utc |
| open | o |
| high | h |
| low | l |
| close | c |
| spread | spread_points (decision_events, on entry) |
| tick_volume | MISSING (recommended new field) |
| real_volume | MISSING (recommended new field) |

## Gaps for scalp-learning (recommended additions)

- exec_latency_ms
- slippage_points
- close_reason
- entry_reason_code
- regime_label
- session_window_id
- retcode_class
- tick_volume, real_volume (from bars)

## Notes

- Files were exported directly from connected MT5 terminal using Python MetaTrader5 package.
- This snapshot is server-specific (current account server).