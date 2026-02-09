# OANDA TMS (PL) MT5 Limits Audit

## Summary
- Status: PASS (guardrails implemented; no strategy logic changes)
- Scope: price-request limits (UTC day + rolling 24h), order rate limit, positions+pending cap

## Authoritative Limits (per prompt)
- Warning level: 1000 price requests per calendar day
- Cut-off level: 5000 price requests per calendar day
- Market orders: 50 orders/sec (Appendix 4)
- Positions + pending orders: 500 total (TP/SL excluded)

## House Safety Margins (enforced)
- SOFT_WARN_REQUESTS_DAY = 1000
- HARD_STOP_REQUESTS_DAY = 4500
- HARD_STOP_ORDERS_SEC = 45
- HARD_STOP_SIMULTANEOUS = 450

## Guarded Call Sites (price requests)
- symbol_info cached path: [BIN/safetybot.py](BIN/safetybot.py#L2016-L2024)
- copy_rates_from_pos: [BIN/safetybot.py](BIN/safetybot.py#L2066-L2074)
- symbol_info_tick: [BIN/safetybot.py](BIN/safetybot.py#L2094-L2103)
- order_send precheck symbol_info: [BIN/safetybot.py](BIN/safetybot.py#L2133-L2170)
- emergency tick in force_flat_all: [BIN/safetybot.py](BIN/safetybot.py#L2468-L2492)

## Guarded Call Sites (order submit / positions)
- order rate limit + safe mode gate: [BIN/safetybot.py](BIN/safetybot.py#L2133-L2160)
- positions+pending cap check: [BIN/safetybot.py](BIN/safetybot.py#L2298-L2330)

## Central Guard Module
- OANDA limits guard: [BIN/oanda_limits_guard.py](BIN/oanda_limits_guard.py#L1-L156)

## Evidence Outputs
- State file: [EVIDENCE/oanda_limits_state.json](EVIDENCE/oanda_limits_state.json) (updated on guard activity)

## Integration Tests Added
- OANDA limits integration tests (trade modes, safe mode, warning level, evidence state):
  [tests/test_oanda_limits_integration.py](tests/test_oanda_limits_integration.py)

## Latest Test Runs (offline)
- Full suite run x3: PASS (all three runs OK)

## How to Reproduce (offline)
1) Run guard tests:
  - `python -m unittest tests.test_oanda_limits_guard`
2) Run integration tests:
  - `python -m unittest tests.test_oanda_limits_integration`
3) Run full suite (3x):
  - `1..3 | ForEach-Object { python -m unittest }`

## Notes
- Daily price request guard uses two counters and enforces the stricter outcome:
  - UTC calendar day
  - Rolling 24-hour window
- Safe mode blocks new orders; emergency operations can proceed.
