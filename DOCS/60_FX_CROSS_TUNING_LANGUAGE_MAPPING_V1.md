# 60. FX_CROSS Tuning Language Mapping V1

## Po co ten dokument

`FX_CROSS` nie mogla dostac samej kopii jezyka strojenia z `EURUSD`, bo jej genotyp jest inny. Ten dokument opisuje, jak obecny jezyk strojenia zostal zmapowany na crossy i gdzie widac jego obecne granice.

## Co zostalo zmapowane

### Trend-like

W rodzinie `FX_CROSS` jako trend-like traktujemy:

- `SETUP_TREND`
- `SETUP_PULLBACK`

To oznacza, ze te klasy dziedzicza:

- `trend_breakout_tax`
- `trend_chaos_tax`
- `trend_caution_tax`
- `trend_no_aux_tax`
- `require_aux_support_for_trend`
- `require_non_poor_candle_for_trend`

### Mean-reversion-like

W rodzinie `FX_CROSS` jako mean-reversion-like traktujemy:

- `SETUP_REJECTION`
- `SETUP_RANGE`

To oznacza, ze te klasy dziedzicza:

- `require_support_for_rejection`
- `rejection_range_boost`

## Co juz daje wartosc

Ten most pozwolil od razu:

- podpiac crossy pod lokalnego kapitana i rodzine,
- zachowac genotyp `SETUP_PULLBACK` bez pisania osobnego silnika od zera,
- traktowac `SETUP_RANGE` jako lokalny odpowiednik mean-reversion,
- utrzymac spojnosc calej hierarchii bez rozwalania hot-path.

## Gdzie jezyk jeszcze nie domaga

Weekendowa analiza `FX_CROSS` pokazala, ze sama mapa semantyczna jeszcze nie wystarcza. Najbardziej widoczne braki to:

- `range_chaos_tax`
- `range_require_non_poor_candle`
- `range_require_non_poor_renko`
- `range_confidence_floor`

To jest wazne, bo obecnie najczytelniejsza rana rodziny siedzi w `GBPJPY` i ma postac:

- `SETUP_RANGE/CHAOS`

Obecny jezyk potrafi to opisac diagnostycznie, ale jeszcze nie umie tego wyrazic elegancko jako osobnej klasy filtrow range-specyficznych.

## Uczciwy wniosek

Obecny most jezykowy dla `FX_CROSS` jest wystarczajacy, zeby rodzine podlaczyc do hierarchii i uczciwie obserwowac. Nie jest jeszcze wystarczajacy, zeby crossy stroic z taka precyzja, z jaka stroimy `EURUSD`. To nie jest wada rollout-u. To jest po prostu kolejny etap dojrzewania jezyka strojenia.
