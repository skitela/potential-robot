# EURUSD Reference And Core Link

## Cel

Ten dokument opisuje z lotu ptaka, co obecnie robi `MicroBot_EURUSD`, które elementy są jego lokalną genetyką, a które pochodzą ze wspólnego `Core`.

## EURUSD jako bot wzorcowy

`EURUSD` jest obecnie głównym wzorcem rodziny `FX_MAIN`.

Jego rola:

- sprawdzać nowe lekkie mechanizmy pod kątem latencji,
- sprawdzać ochronę kapitału przy pogarszającym się execution,
- sprawdzać, które elementy da się przenieść na cały park bez niszczenia lokalnych genów.

## Co jest lokalne dla EURUSD

Pliki lokalne:

- [MicroBot_EURUSD.mq5](/C:/MAKRO_I_MIKRO_BOT/MQL5/Experts/MicroBots/MicroBot_EURUSD.mq5)
- [Profile_EURUSD.mqh](/C:/MAKRO_I_MIKRO_BOT/MQL5/Include/Profiles/Profile_EURUSD.mqh)
- [Strategy_EURUSD.mqh](/C:/MAKRO_I_MIKRO_BOT/MQL5/Include/Strategies/Strategy_EURUSD.mqh)

Lokalne geny `EURUSD`:

- okno handlu `8-11`,
- profil `FX_MAIN`,
- lokalne progi spreadu,
- lokalny scoring `trend / pullback / breakout / rejection`,
- lokalne progi triggera,
- lokalny model ryzyka,
- lokalne mnożniki `SL/TP`,
- lokalny trailing,
- lokalny komentarz zleceń i magic number.

## Co daje Core

Pliki wspólne, z których korzysta `EURUSD`:

- `MbRuntimeTypes`
- `MbRuntimeKernel`
- `MbStorage`
- `MbRuntimeControl`
- `MbKillSwitchGuard`
- `MbRateGuard`
- `MbMarketState`
- `MbSessionGuard`
- `MbMarketGuards`
- `MbLatencyProfile`
- `MbBrokerProfilePlane`
- `MbExecutionSummaryPlane`
- `MbInformationalPolicyPlane`
- `MbExecutionPrecheck`
- `MbExecutionSend`
- `MbExecutionFeedback`
- `MbExecutionQualityGuard`
- `MbDecisionJournal`
- `MbExecutionTelemetry`
- `MbIncidentJournal`
- `MbTradeTransactionJournal`
- `MbClosedDealTracker`

## Jak EURUSD łączy się z Core

Przebieg:

1. `OnInit`
- ładuje profil i strategię,
- inicjalizuje storage,
- aktywuje kill-switch,
- ustawia cache ścieżek logów,
- uruchamia kolejki journali i telemetryki,
- uruchamia pomiar latencji.

2. `OnTimer`
- odświeża stan runtime,
- odświeża snapshot rynku,
- flushuje heartbeat i status,
- flushuje politykę informacyjną,
- flushuje broker profile i execution summary,
- flushuje kolejki journali i telemetryki,
- zapisuje runtime state.

3. `OnTick`
- działa lekko i lokalnie,
- odświeża tylko bieżący snapshot ticka,
- pilnuje open position management,
- uruchamia market guard,
- uruchamia execution quality guard,
- liczy lokalny sygnał strategii,
- liczy lokalny risk plan,
- robi execution precheck,
- opcjonalnie wysyła zlecenie,
- zapisuje lekki ślad decyzji i metryk.

4. `OnTradeTransaction`
- zapisuje lekki ślad transakcyjny,
- przetwarza zamknięte deal'e,
- aktualizuje prostą pamięć świeżych wyników.

## Co zostało dopięte ostatnio

### 1. Odchudzenie hot-path

- cache ścieżek logów w ekspercie,
- buforowanie decision events,
- buforowanie execution telemetry,
- buforowanie incident journal,
- buforowanie trade transaction journal,
- szybki `PositionSelect(symbol)` przed pełnym skanem pozycji,
- jeden znacznik `now` na cały cykl `OnTick`.

### 2. Lekka ocena jakości execution

- liczenie liczby prób wejścia,
- liczenie liczby udanych wejść,
- średnie retry,
- średni i maksymalny slippage,
- execution quality guard na bazie świeżego okna.

### 3. Lekka pamięć wyników

Zamknięte transakcje aktualizują:

- `learning_bias`
- `adaptive_risk_scale`

To jest lekka pamięć świeżych wyników, bez czytania dużej historii w gorącej ścieżce.

## Jak to przeniesiono na resztę par

Mechanizmy przeniesione na cały park:

- buforowane journale,
- cache ścieżek logów,
- latency profile,
- execution summary,
- informational policy,
- execution quality guard,
- record execution metrics,
- lekka pamięć świeżych wyników przez `MbClosedDealTracker`,
- adaptacyjna skala ryzyka w `MbStrategyCommon`.

Nie zostały przeniesione:

- lokalne setupy,
- lokalny scoring,
- lokalne okna handlu,
- lokalne parametry ryzyka,
- lokalne progi triggerów.

## Wniosek

`EURUSD` pozostaje botem wzorcowym, ale nie jest już samotnym wyjątkiem.

To, co okazało się:

- lekkie,
- bezpieczne,
- dobre dla latencji,
- neutralne wobec genetyki par,

zostało już przeniesione na pozostałe mikro-boty jako wspólna warstwa runtime.
