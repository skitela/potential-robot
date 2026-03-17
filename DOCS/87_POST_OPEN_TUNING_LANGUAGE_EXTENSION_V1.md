# 87. Post-Open Tuning Language Extension V1

## Cel

Po pierwszej godzinie rynku `EURUSD` mial juz dojrzalszy jezyk lokalnego strojenia niz reszta rodzin.

Ta wersja dogrywa brakujace narzedzia dla:

- `FX_ASIA`
- `FX_CROSS`
- `INDEX_EU`
- `INDEX_US`

tak aby lokalny agent strojenia po pierwszej godzinie nie tylko zbieral dane, ale umial tez bardziej precyzyjnie reagowac na:

- toksyczny `RANGE`
- chaos wewnatrz `RANGE`
- slabosc swiecy i Renko przy breakoutach i range
- zbyt agresywne indeksowe wejscia blisko startu i konca okna

## Co zostalo dodane

Lokalna polityka strojenia dostala nowe pola:

- `require_non_poor_candle_for_breakout`
- `require_non_poor_candle_for_range`
- `require_non_poor_renko_for_range`
- `range_chaos_tax`
- `range_trend_tax`
- `range_confidence_floor`
- `index_opening_impulse_tax`
- `index_noon_transition_tax`

## Gdzie to dziala

### Lokalny agent strojenia

Agent potrafi teraz rozpoznawac i zapisywac:

- kare dla `RANGE` w chaosie
- kare dla `RANGE` w trendzie lub breakoutowym tle
- minimalny prog pewnosci dla `RANGE`
- dodatkowy filtr swiecy dla breakoutu
- filtry swiecy i Renko dla `RANGE`
- lekkie podatki czasowe dla indeksow

### Strategie rodzinne

Nowe pola sa wykonawczo respektowane w:

- `AUDUSD`
- `USDJPY`
- `NZDUSD`
- `EURJPY`
- `GBPJPY`
- `EURAUD`
- `GBPAUD`
- `DE30`
- `US500`

To znaczy, ze agent nie tylko zapisuje juz bogatsza polityke, ale strategie potrafia ja wykonac.

## Dlaczego to bylo potrzebne

Przygotowane kandydatury po otwarciu rynku wskazywaly jasno, ze poza `EURUSD` brakuje jezyka dla:

- `FX_ASIA`
  - `range_confidence_floor`
  - `range_trend_tax`
  - `breakout_require_non_poor_candle`
- `FX_CROSS`
  - `range_chaos_tax`
  - `range_require_non_poor_candle`
  - `range_require_non_poor_renko`
  - `range_confidence_floor`
- `INDICES`
  - `index_opening_impulse_tax`
  - `index_noon_transition_tax`

To bylo juz opisane w kandydaturach poniedzialkowych, ale runtime lokalnego strojenia nie umial jeszcze tego wykonac.

## Wynik techniczny

- `17/17` mikro-botow kompiluje sie poprawnie
- walidacja hierarchii strojenia przechodzi z `ok=true`
- walidacja layoutu projektu przechodzi z `ok=true`
- lokalny `OANDA MT5` zostal odswiezony na pelnym profilu floty

## Wniosek

Po tej wersji `EURUSD` nie jest juz jedynym symbolem z dojrzalszym jezykiem po pierwszej godzinie rynku.

Pozostale rodziny dostaly brakujace narzedzia, dzieki czemu lokalny agent strojenia moze:

- mniej slepo obserwowac
- precyzyjniej karac toksyczne scenariusze
- i czysciej budowac kolejna fale regulacji po otwarciu rynku
