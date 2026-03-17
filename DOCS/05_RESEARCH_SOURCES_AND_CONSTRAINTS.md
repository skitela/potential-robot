# Research Sources And Constraints

## Official Sources Confirmed During Bootstrap

### MetaTrader 5 chart attachment model

Official MetaTrader 5 Help confirms:

- Expert Advisors are attached to charts
- only one Expert Advisor can run on one chart

This supports the target deployment model:

- `1 microbot = 1 chart = 1 symbol`

Reference:

- https://www.metatrader5.com/en/terminal/help/algotrading/trade_robots_indicators

### OANDA MT5 EA usage

Official OANDA MT5 help confirms:

- EAs are imported into `MQL5/Experts`
- EAs are attached to charts
- MT4 EAs cannot be used in MT5
- Share CFD trading via EA is rejected in MT5

Reference:

- https://help.oanda.com/eu/en/faqs/mt5-user-guide-eu.htm

### MQL5 file model

Official MQL5 file reference confirms:

- local terminal files exist under terminal data folder
- common files exist in shared `Common\\Files`

This supports project-local `FILE_COMMON` path contracts for per-symbol state.

Reference:

- https://www.mql5.com/en/docs/files

### OnTradeTransaction

Official MQL5 reference confirms:

- `OnTradeTransaction()` is the native event to process trade execution results and follow-up trade state transitions
- trade transactions can arrive in a sequence that should not be assumed to be strictly ordered from the EA point of view

This supports future migration of more execution-quality logic into event-driven paths.

Reference:

- https://www.mql5.com/en/docs/event_handlers/ontradetransaction

### CTrade and OrderCheck

Official MQL5 references confirm:

- `CTrade` is the standard library trade wrapper for local buy/sell/modify flows
- `OrderCheck()` is a precheck and its result must be interpreted via returned retcode, not treated as execution itself

This supports the autonomy-first model where every microbot keeps its own local execution path, while shared code only supplies reusable helper layers.

References:

- https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade
- https://www.mql5.com/en/docs/trading/ordercheck

### MQL5 Wizard

MetaTrader 5 includes an official MQL5 Wizard for rapid Expert Advisor code generation.

This does not replace our custom scaffold generator, but it validates the idea that code-generation support is native to the ecosystem.

Reference:

- https://www.metatrader5.com/en/automated-trading/mql5wizard

## Practical Constraints

1. A microbot must be attached to the chart of its symbol.
2. A single chart must not host multiple EAs.
3. Runtime state should remain local per microbot.
4. Shared code should be compiled into each microbot, not run as a central trading controller.
5. `FILE_COMMON` should be used carefully and namespaced by project and symbol.
6. `OrderCheck()` can validate a request but does not replace local execution ownership.
7. `OnTradeTransaction()` should be treated as local execution feedback, not as a central orchestration bus.
