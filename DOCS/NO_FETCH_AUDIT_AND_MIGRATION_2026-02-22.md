# NO-FETCH Audit and Migration Plan (2026-02-22)

## Scope
- Repo: `C:\OANDA_MT5_SYSTEM`
- Goal: keep hybrid stability while moving Python decision logic to snapshot-only inputs.
- Constraint respected in this pass: no strategy parameter changes (signals, SL/TP, sizing, windows unchanged).

## 1) Hard list: legacy MT5 paths still present in Python

### A. Core runtime (`BIN/safetybot.py`)
- `ExecutionEngine.connect/ensure_connected`: `mt5.initialize`, `mt5.terminal_info` (runtime connectivity).
- `ExecutionEngine.symbol_info_cached`, `symbol_select`: symbol metadata fetch.
- `ExecutionEngine.positions_get`, `orders_get`, `account_info`, `history_deals_get`: portfolio/account polling.
- `ExecutionEngine.copy_rates`: bar fetch path from MT5 (now partial no-fetch for M5 implemented in this pass).
- `ExecutionEngine.tick`: fallback to `mt5.symbol_info_tick` when ZMQ tick cache is missing.
- `ExecutionEngine.order_send`: `mt5.order_check`, `mt5.order_send` (execution path, expected).
- `ExecutionEngine.force_flat_*`: emergency close path through MT5 API (expected fail-safe path).
- `StandardStrategy.get_trend`: requests H4/D1 through `engine.copy_rates`.
- `StandardStrategy.m5_indicators_if_due`: requests M5 through `engine.copy_rates` (now can be snapshot-backed).
- `SafetyBot._score_symbol_for_entries`: direct `mt5.symbol_info`/`mt5.symbol_select` for universe quality checks.
- Adaptive/closeout management still submits close/modify/remove through execution engine (expected, risk controls).

### B. Tooling scripts (intentionally online/live checks)
- `TOOLS/online_smoke_mt5.py`: imports and queries MT5 terminal.
- `TOOLS/audit_symbols_get_mt5.py`: imports and queries MT5 symbol universe.
- These are diagnostics, not decision loop runtime.

### C. Risk classification
- Allowed for owner role (execution/safety): order send/check, positions/orders/account reconciliation, emergency flatten.
- Migration targets (decision no-fetch): decision-side bars/trend sources and symbol qualification fetches.

## 2) Migration plan: "Python no-fetch decision" in safe phases

### Phase 0 (done in this pass)
- Added snapshot-first M5 path:
  - `ExecutionEngine.copy_rates` now prefers local M5 bars from `M5BarsStore` when timeframe is trade M5.
  - Added strict gate `hybrid_m5_no_fetch_strict` to disable fallback MT5 fetch for M5.
  - Added BAR ingestion from ZMQ into `M5BarsStore` in `_handle_market_data`.
- Added config switches:
  - `hybrid_use_zmq_m5_bars` (default `true`)
  - `hybrid_m5_no_fetch_strict` (default `false`)

### Phase 1 (next, safe)
- Remove decision dependency on MT5 for trend:
  - Option A: extend MQL5 snapshots with H4/D1 bars.
  - Option B: derive H4/D1 from accumulated M5 history in local store (deterministic resampling).
- Keep execution and emergency paths in MT5 owner layer.
- Add deterministic freshness checks: if snapshot stale => `NO-TRADE`.

### Phase 2 (strict cutover)
- Enable strict no-fetch in production config:
  - `hybrid_m5_no_fetch_strict=true`.
- Add explicit guard for trend source:
  - if trend snapshot unavailable/stale => skip entry, keep close-only/maintenance paths.
- Keep global heartbeat fail-safe behavior unchanged.

### Phase 3 (cleanup)
- Remove dead fallback branches that are no longer reachable in decision path.
- Keep only:
  - snapshot ingestion/parsing/validation in Python decision layer,
  - MT5 execution/risk owner operations in execution layer.

## 3) Contract and test requirements for cutover

### Required contracts
- Snapshot version field: already present on command channel (`__v`).
- Data snapshot schema for decision:
  - M5 bar fields: symbol, timeframe, time, open/high/low/close, volume.
  - Trend snapshot (future phase): H4/D1 equivalents or deterministic aggregation contract.
- Freshness fields and TTL checks for no-trade fail-safe.

### Required tests (minimum)
- Unit:
  - snapshot M5 source preferred over MT5 fetch.
  - strict no-fetch mode blocks fallback MT5 fetch.
  - fallback mode still works if snapshot history is short.
- Integration:
  - heartbeat fail -> scan suppression.
  - malformed snapshot -> no-trade (no open orders).
  - stale snapshot -> no-trade.

## 4) Status after this pass
- DONE:
  - M5 decision fetch can now run from local snapshots (no direct MT5 call required for that path).
  - strict no-fetch switch implemented for M5.
  - new tests for no-fetch M5 path added.
- MISSING:
  - full trend no-fetch path (H4/D1 source still MT5-backed today).
  - strict no-fetch end-state for all decision inputs.

