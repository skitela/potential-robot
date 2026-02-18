# Strategy/Scalp Audit - 2026-02-18

## Scope
- Compare current SafetyBot trading logic with broker/platform constraints and primary references.
- Focus on scalp discipline, request/limit safety, and cooperation with SCUD + learner_offline.

## Primary Sources Reviewed
- OANDA REST API best practices: https://developer.oanda.com/rest-live-v20/best-practices/
- OANDA API troubleshooting: https://help.oanda.com/us/en/faqs/troubleshooting-rest-v20-api.htm
- OANDA MT5 user guide (order/fill behavior and platform notes): https://help.oanda.com/us/en/faqs/mt5-user-guide.htm
- MetaTrader 5 trade return codes (incl. `10030` invalid fill): https://www.mql5.com/en/docs/constants/errorswarnings/enum_trade_return_codes
- MetaTrader 5 order properties (`ORDER_FILLING_*`): https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties
- MiFID II RTS 6 (algorithmic controls, kill-switch governance): https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=CELEX:32017R0589
- NBER microstructure/HFT evidence: https://www.nber.org/papers/w18591
- Journal evidence on short-horizon signals and cost sensitivity: https://www.sciencedirect.com/science/article/pii/S2405844020300172

## Findings Against Current Code
- Strong: order prechecks, fill-mode fallback handling for `10030`, request budgeting, cooldown/backoff, black-swan and kill-switch controls are already in place.
- Gap identified: no deterministic max holding time for open positions in normal operation. This can leave scalp positions open for many hours when no exit trigger appears.
- Impact: strategy can drift from intended "quick in/quick out" scalp behavior and tie capital on a single symbol.

## Implemented Improvements
- Added position time-stop policy to SafetyBot defaults and runtime config loading.
  - `BIN/safetybot.py:381`
  - `BIN/safetybot.py:5193`
- Added robust position timestamp/age utilities.
  - `BIN/safetybot.py:546`
  - `BIN/safetybot.py:577`
  - `BIN/safetybot.py:587`
- Added stale-position close guard with retry throttling and magic-number filtering.
  - `BIN/safetybot.py:4379`
  - `BIN/safetybot.py:4472`
- Enabled call in main scan loop so stale positions are handled automatically every cycle.
  - `BIN/safetybot.py:4772`
- Added config knobs in `CONFIG/strategy.json`.
  - `CONFIG/strategy.json:14`
- Added unit tests for new utilities.
  - `tests/test_position_time_stop_utils.py:1`

## New Strategy Parameters (current values)
- `position_time_stop_enabled=true`
- `position_time_stop_only_magic=true`
- `position_time_stop_hot_min=45`
- `position_time_stop_warm_min=120`
- `position_time_stop_eco_min=240`
- `position_time_stop_retry_sec=120`
- `position_time_stop_deviation_points=30`

## Why this aligns with sources
- Broker/platform docs emphasize robust execution constraints and rejection handling (already present; reinforced via deterministic close logic).
- RTS 6 requires resilient automated control loops; time-stop is an explicit lifecycle control for open risk.
- Microstructure evidence shows short-horizon alpha decays quickly and trading costs matter; stale holds degrade scalp intent.

## Suggested next test run (safe)
- Run 10-15 min online observation with all three agents (`SafetyBot + SCUD + learner_offline`) active.
- Track:
  - count of `TIME_STOP_CLOSE_DONE` vs `TIME_STOP_CLOSE_FAIL`
  - per-symbol hold time distribution
  - request budgets (`price/sys/order`) and OANDA rolling 24h count
  - whether additional symbols get rotations after stale close events
