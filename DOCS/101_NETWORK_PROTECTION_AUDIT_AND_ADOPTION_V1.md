# 101 Network Protection Audit And Adoption V1

Data: 2026-03-16

## Material zrodlowy
Audyt wykonano na podstawie pliku:
- `C:\Users\skite\Desktop\MQL5_ Ochrona przed problemami sieciowymi.md`

Material opisuje trzy glowne obszary:
- monitorowanie opoznien sieciowych,
- adaptacyjny poślizg zlecenia,
- ograniczanie zalewu zapytaniami do brokera.

## Co juz mielismy w mikro-botach
Nowy system nie byl pusty w obszarze ochrony infrastrukturalnej. Mial juz:

### 1. Ochrone feedu i stanu rynku
- swiezosc ticka (`tick_age_ms`),
- blokade `CACHE_STALE`,
- blokade `TICK_STALE`,
- blokade `BROKEN_TICK`,
- limity spreadu i tryb ostroznosci przy gorszym spreadzie.

### 2. Ochrone wykonania
- wspolny wrapper wysylki z retry:
  - `MbExecutionSend.mqh`
- klasyfikacje retcode i opoznien retry:
  - `MbExecutionCommon.mqh`
- telemetryke wykonania:
  - lokalna latencja,
  - czas wysylki,
  - retry,
  - slippage,
  - retcode
- guard jakosci wykonania:
  - relacja udanych wysylek,
  - sredni retry,
  - sredni slippage

### 3. Ochrone przed floodem
- budzety odczytow cenowych i zlecen per sekunda/minuta:
  - `MbRateGuard.mqh`
- tryb `ECO` i twarde limity dla ceny i order flow

### 4. Ochrone runtime i obserwowalnosc
- heartbeat per symbol,
- runtime state,
- broker profile,
- execution summary,
- incident journal,
- status plane

### 5. Ochrone uczenia
- deckhand odrzuca material, gdy:
  - probka jest za mala,
  - bucket jest pusty,
  - przedpole jest brudne,
  - kandydaci nie konwertuja sie na sensowne lekcje paper

## Co bylo slabsze lub brakowalo
W porownaniu z materialem zrodlowym znalazly sie dwie prawdziwe luki:

### A. Brak jawnej telemetrii lacza terminal-serwer
System mierzyl bardzo dobrze skutki infrastruktury:
- retry,
- slippage,
- opoznienie lokalne,
- bledy wykonania,

ale nie pokazywal wprost:
- czy terminal jest polaczony,
- jaki jest ostatni ping do serwera.

### B. Agent strojenia nie mial osobnego powodu
Deckhand potrafil juz powiedziec:
- brak probki,
- brudne przedpole,
- zablokowana konwersja paper,

ale nie mial wprost kodu:
- `INFRASTRUCTURE_WEAK`

czyli sytuacji, w ktorej problemem nie jest rynek ani genotyp strategii, tylko sama jakosc srodowiska wykonawczego.

## Co zaadaptowano

### 1. Jawna telemetria polaczenia i pingu
Do `MbMarketSnapshot` dodano:
- `terminal_connected`
- `terminal_ping_last_us`
- `terminal_ping_last_ms`

Zrodlo:
- `TerminalInfoInteger(TERMINAL_CONNECTED)`
- `TerminalInfoInteger(TERMINAL_PING_LAST)`

Nastepnie dane te zostaly dopiete do:
- `broker_profile.json`
- `execution_summary.json`
- `informational_policy.json`

### 2. Twarda blokada przy rozlaczeniu terminala
W `MbMarketGuards.mqh`:
- brak polaczenia terminala zatrzymuje wejscie:
  - `TERMINAL_DISCONNECTED`

### 3. Ostroznosc przy wysokim pingu
W `MbMarketGuards.mqh`:
- wysoki ping wlacza ostroznosc,
- ekstremalny ping poza paper moze zablokowac wejscie:
  - `PING_TOO_HIGH`

To jest lekkie i celowo prostsze niz rozbudowany model adaptacyjny, bo juz mamy lepsze dane ex-post:
- retry,
- slippage,
- order send,
- execution pressure.

### 4. Nowy powod dla agenta strojenia
Deckhand dostal nowy stan:
- `INFRASTRUCTURE_WEAK`

Jest uruchamiany, gdy runtime pokazuje:
- zbyt wysoka `execution_pressure`,
- serie bledow wykonania,
- narastajace anomalie spreadowe,
- lub stan halt.

Agent strojenia interpretuje to teraz jawnie jako:
- nie stroic strategii na materiale zepsutym przez infrastrukture.

## Czego swiadomie nie przeniesiono 1:1

### 1. Prostego licznika zapytan jako glownego rozwiazania
Material zrodlowy proponowal prosty licznik `request_counter`.
Tego nie przeniesiono 1:1, bo mamy juz dojrzalszy model:
- osobny budzet cen,
- osobny budzet order flow,
- progi `ECO`,
- twarde odciecie floodu.

### 2. Adaptacji slippage tylko na podstawie pingu
Nie przeniesiono prostego:
- "im wiekszy ping, tym wiekszy slippage"

Powod:
- mamy juz per-symbol profile `deviation_points`,
- mamy realnie mierzone slippage ex-post,
- mamy retry i jakosc wykonania,
- surowy ping sam w sobie nie daje jeszcze dobrej decyzji o rozszerzaniu tolerancji wejscia.

To zostalo odlozone jako kandydat do dalszej, dojrzalszej wersji:
- tylko wtedy, gdy potwierdzi to telemetria slippage i retry.

## Wniosek
Material zrodlowy byl dobry jako szkic i przypomnienie doktryny.
Nasz system juz mial mocniejsze fundamenty wykonawcze niz ten szkic, ale brakowalo mu:
- jawnego obrazu lacza terminal-serwer,
- oraz wprost nazwanej blokady uczenia przy slabym stanie infrastruktury.

Te dwie rzeczy zostaly dopiete bez rozwalania hot-path i bez dokladania ciezkiej retencji.
