# 68 DOMAIN ARCHITECTURE FX METALS INDICES V1

## Cel

Po serii rozmow i prac nad `FX` przyjmujemy, ze dalszy rozwoj nie bedzie
szedl w kierunku wielu osobnych systemow. Powstaje jeden wspolny organizm
`MAKRO_I_MIKRO_BOT`, ale z trzema duzymi domenami:

- `FX`
- `METALS`
- `INDICES`

Kazda domena zachowuje swoj genotyp, okna i rodziny, ale nie dostaje
osobnego kontraktu kapitalowego ani osobnego nadrzednego sterownika dnia.

## Zasada nadrzedna

Nie budujemy:
- trzech odrebnych panstw,
- trzech odrebnych kontraktow kapitalowych,
- trzech odrebnych systemow budzenia i usypiania.

Budujemy:
- jeden wspolny organizm,
- trzy domeny handlowe,
- jeden globalny koordynator sesji i kapitalu,
- jeden wspolny kontrakt brokera,
- jeden wspolny model `paper/live/reentry`.

## Warstwy architektury

### 1. MicroBots

Na dole pozostaja mikro-boty instrumentowe.

Ich zadania:
- wykonac lokalna logike instrumentu,
- respektowac stan `SLEEP/PREWARM/LIVE/LIVE_DEFENSIVE/PAPER_ACTIVE/PAPER_SHADOW/REENTRY_PROBATION`,
- nie rozumiec calego dnia i calej floty.

Mikro-bot nie ma decydowac:
- kto zastapi inna rodzine,
- ktora domena ma sie obudzic,
- czy mozna ruszyc inny segment dnia.

### 2. Local Tuning Agent

Przy mikro-bocie pozostaje lokalny agent strojenia i jego deckhand.

Ich zadania:
- patrzec na lokalne zwyciestwa i porazki,
- dbac o lokalna wiarygodnosc danych,
- proponowac male zmiany parametrow,
- nie dotykac globalnego kontraktu kapitalowego.

### 3. Family Agent

Nad lokalnymi mikro-botami stoi agent rodzinny.

Przyklady:
- `FX_MAIN`
- `FX_ASIA`
- `FX_CROSS`
- `METALS_SPOT_PM`
- `METALS_FUTURES`
- `INDEX_EU`
- `INDEX_US`

Rodzina:
- pilnuje lokalnego genotypu,
- agreguje dane rodziny,
- moze przejsc w `paper`,
- moze dostac budzet rodzinny,
- nie zarzadza jeszcze innymi domenami.

### 4. Domain Agent

To nowa warstwa, ktora staje nad rodzinami jednej domeny.

Przyklady:
- `FX_DOMAIN_AGENT`
- `METALS_DOMAIN_AGENT`
- `INDICES_DOMAIN_AGENT`

To on odpowiada za:
- glowne i rezerwowe rodziny wewnatrz domeny,
- harmonogram domeny,
- prewarm i carryover wewnatrz domeny,
- lokalne przejscia domeny do `paper`,
- wspolprace z globalnym koordynatorem.

### 5. Global Session And Capital Coordinator

To najwyzsza warstwa wspolnego organizmu.

Tylko ona ma prawo:
- widziec cala dobe naraz,
- widziec kapital calej floty,
- budzic i usypiac domeny,
- uruchamiac domene rezerwowa,
- decydowac, czy zdegradowana domena ma zostac w `paper`,
- decydowac o warunkach reentry na poziomie domeny i calej floty.

Nie handluje w hot-path.
Pracuje spokojnie, timerowo i operacyjnie.

## Domeny

### FX

Stan:
- aktywna domena referencyjna

Rodziny:
- `FX_MAIN`
- `FX_ASIA`
- `FX_CROSS`

Uwagi:
- to tutaj powstala dojrzala warstwa strojenia,
- to stad przenosimy architekture, a nie slepe progi.

### METALS

Stan:
- domena przygotowywana architektonicznie

Rodziny:
- `METALS_SPOT_PM`
- `METALS_FUTURES`

Uwagi:
- metale dostaja osobny katalog domenowy,
- nadal pozostaja we wspolnym organizmie,
- domena bedzie budzona glownie po `FX_AM` i przed `INDEX_US`.

### INDICES

Stan:
- domena przygotowywana architektonicznie

Rodziny:
- `INDEX_EU`
- `INDEX_US`

Uwagi:
- indeksy beda naturalna domena rezerwowa i nastepca dla czesci dnia,
- nie sa jeszcze osobnym rolloutem symbolowym,
- najpierw budujemy katalog domeny i ustr oj.

## Zasady organizmu

1. Domeny nie maja osobnych kontraktow kapitalowych.
2. Domeny nie maja osobnych polityk brokera.
3. Domeny nie budza sie same nawzajem.
4. Rodzina nie moze samodzielnie przejac czasu innej domeny.
5. Tylko globalny koordynator moze aktywowac zastepstwo domenowe.
6. Przejscie do `paper` moze byc szybkie, powrot do `live` musi byc wolniejszy.
7. `paper` ma pozostac laboratorium, ale bez prawa do obchodzenia kontraktu kapitalowego.

## Skutek dla struktury projektu

W projekcie utrzymujemy:
- wspolne `MQL5`, `CONFIG`, `DOCS`, `TOOLS`, `RUN`
- oraz katalogi domenowe:
  - `METALS_MAKRO_I_MIKRO_BOT`
  - `INDICES_MAKRO_I_MIKRO_BOT`

Te katalogi nie sa osobnymi repozytoriami ani osobnymi runtime.
Sa domenowymi sekcjami wspolnego organizmu.

## Najblizszy kolejny etap

1. Dopiac model operacyjny budzenia/usypiania domen.
2. Zdefiniowac relacje:
   - domena glowna,
   - domena rezerwowa,
   - domena shadow.
3. Potem dopiero budowac rollout `METALS`.
