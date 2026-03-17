# AUDUSD Paper Gate Dirty Range Filter V1

## Cel

Odczac najbardziej toksyczna czesc `SETUP_RANGE` dla `AUDUSD` nie przez przebudowe glownej strategii, tylko przez waski filtr w `paper gate`, czyli tam, gdzie slabie przypadki sa sztucznie dopuszczane do lekcji papierowych mimo pierwotnego `SCORE_BELOW_TRIGGER`.

## Co zrobiono

W [MicroBot_AUDUSD.mq5](C:\MAKRO_I_MIKRO_BOT\MQL5\Experts\MicroBots\MicroBot_AUDUSD.mq5):
- w branchu `IsLocalPaperModeActive() && !signal.valid && signal.reason_code == "SCORE_BELOW_TRIGGER"`
- dodano lokalny filtr `AUDUSD_RANGE_DIRTY_HYBRID_BLOCK`

Filtr blokuje dopuszczenie do `PAPER_SCORE_GATE`, gdy jednoczesnie:
- `setup_type == SETUP_RANGE`
- `market_regime == CHAOS` lub `TREND`
- candle jest `POOR/UNKNOWN`
- renko nie jest `GOOD`

To jest zmiana celowo waska:
- nie dotyka live runtime
- nie dotyka breakoutow
- nie dotyka normalnych przejsc strategii
- czyści tylko paper gate dla slabego materialu range w `AUDUSD`

## Czego nie zostawiono

Wczesniejsza proba blokady na poziomie [Strategy_AUDUSD.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Strategies\Strategy_AUDUSD.mqh) okazala sie praktycznie martwa i zostala wycofana. Zostala tylko zmiana, ktora rzeczywiscie ruszyla tor danych.

## Efekt

Porownanie bazowe:
- przed filtrem: [audusd_strategy_tester_20260317_151157_summary.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\audusd_strategy_tester_20260317_151157_summary.json)
- po filtrze: [audusd_strategy_tester_20260317_155513_summary.json](C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\audusd_strategy_tester_20260317_155513_summary.json)

Najwazniejsze zmiany:
- `paper_score_gate_rows`: `162 -> 147`
- `paper_open_rows`: `267 -> 255`
- `score_below_trigger_rows`: `31515 -> 28839`
- `learning_sample_count`: `259 -> 250`
- `realized_pnl_lifetime`: `-6.40 -> -4.67`
- `trust_reason`: `FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_HYBRID -> FOREFIELD_DIRTY_BY_LOW_CONFIDENCE_CANDLE`
- nowy jawny reason: `AUDUSD_RANGE_DIRTY_HYBRID_BLOCK` (`23284` przypadki)

## Wniosek

To jest dobra zmiana delta, bo:
- czyści toksyczny material w miejscu, w ktorym faktycznie byl przepuszczany
- poprawia jakosc diagnozy deckhanda
- poprawia lifetime pnl w testerze bez otwierania dodatkowego smiecia

To nie jest jeszcze przewaga dla `AUDUSD`, ale to jest lepsza epistemologia i czystsza baza do nastepnych ruchow.
