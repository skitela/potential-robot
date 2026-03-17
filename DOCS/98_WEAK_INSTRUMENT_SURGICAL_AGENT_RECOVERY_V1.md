# 98. Weak Instrument Surgical Agent Recovery v1

## Cel
Domknac cztery najslabsze instrumenty poza `EURUSD` tak, aby agent strojenia:
- nie wisial bez konca w eksperymencie bez nowych lekcji,
- nie wracal do swiezo obalonej sciezki,
- dobieral alternatywna regulacje zgodna z genotypem symbolu.

## Instrumenty
- `PLATIN`
- `USDJPY`
- `GBPAUD`
- `USDCHF`

## Co znaleziono
- `PLATIN`: breakoutowy metal z bardzo mala probka, duza strata dnia i eksperymentem `REBALANCE`, ktory pozostawal w stanie oczekiwania bez nowych lekcji.
- `USDJPY`: para azjatycka z nadmiarem kupien, slabym bilansem `wygrane / przegrane` i powtarzaniem fiaska `FLOOR_RANGE_CONFIDENCE` na sciezce `SETUP_BREAKOUT / TREND`, mimo ze biezacy rynek byl bardziej zakresowy.
- `GBPAUD`: cross z duza liczba kandydatow blokowanych przez ryzyko i score gate; eksperyment `FLOOR_RANGE_CONFIDENCE` wisial bez nowych probek.
- `USDCHF`: glowna para z wysoka strata, seria porazek i powtarzajacym sie fiaskiem breakoutow w warunkach `spread_regime = CAUTION`.

## Wdrozone zmiany
Zmiany zostaly wykonane w [MbTuningLocalAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningLocalAgent.mqh).

### 1. Staly eksperyment bez nowych lekcji przestaje wisiec
Dodano nowy warunek porazki eksperymentu:
- po co najmniej `6` przegladach,
- bez nowych zamknietych lekcji,
- bez nowych papierowych otwarc,
- po odpowiednio dlugim czasie,

agent uznaje eksperyment za jalowy i robi `rollback`.

### 2. Alternatywna sciezka po fiasku jest teraz symbolowa
Dodano budowanie alternatywnej regulacji zalezne od instrumentu:

- `EURUSD`
  - po fiasku `FILTER_TREND_CANDLE / SETUP_TREND / BREAKOUT`
  - agent przechodzi do breakoutowej sciezki z filtrem swiecy.

- `USDJPY`
  - po fiasku `FLOOR_RANGE_CONFIDENCE / SETUP_BREAKOUT / TREND`
  - agent przechodzi do ostrzejszego `RANGE`:
    - wymaga lepszej swiecy i Renko dla range,
    - utrzymuje wyzszy prog pewnosci,
    - doklada podatek `range_trend`.

- `GBPAUD`
  - po fiasku `FLOOR_RANGE_CONFIDENCE / SETUP_BREAKOUT / BREAKOUT`
  - agent przechodzi do breakoutu z czystym Renko i ciasniejsza pewnoscia.

- `USDCHF`
  - po fiasku `FILTER_TREND_CANDLE / SETUP_BREAKOUT / BREAKOUT`
  - agent przechodzi do breakoutu wymagajacego dobrej swiecy i Renko
  - oraz doklada podatek konfliktu breakout/tlo.

- `PLATIN`
  - po fiasku `REBALANCE / SETUP_BREAKOUT / BREAKOUT`
  - agent przechodzi do breakoutu tylko z dobra swieca i ciasniejszym `risk_cap`.

## Oczekiwany efekt
- `PLATIN` i `GBPAUD` nie beda juz wisialy w eksperymencie bez ruchu.
- `USDJPY` przestanie wracac do zbyt podobnej sciezki breakoutowej i dostanie regulacje zgodna z genotypem range/asian.
- `USDCHF` przestanie stroic breakout zbyt latwo przy slabszym tle spreadowym.

## Walidacja
- kompilacja floty `17/17`
- walidacja hierarchii strojenia `ok=true`
- walidacja instalacji MT5 `ok=true`
- lokalny terminal zostal odswiezony
