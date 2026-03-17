# 90. Deckhand Forefield Cleaning v1

Data: 2026-03-16

## Cel

Deckhand lokalnego strojenia mial dotad glownie pilnowac struktury plikow:
- czy obserwacje istnieja,
- czy koszyki da sie odbudowac,
- czy kandydaci nie sa uszkodzeni technicznie.

To bylo za malo. W praktyce mogl oznaczyc dane jako `TRUSTED`, mimo ze:
- kandydaci narastali lawinowo,
- papier nie otwieral nowych pozycji,
- obserwacje praktycznie nie przyrastaly,
- agent strojenia patrzyl na przedpole zapchane `RISK_CONTRACT_BLOCK` i `PAPER_SCORE_GATE`.

## Co dodano

Deckhand liczy teraz dodatkowo:
- ile kandydatow konczy sie blokada ryzyka,
- ile kandydatow trafia na `PAPER_SCORE_GATE`,
- ile z tych kandydatow jest semantycznie brudnych:
  - niska pewnosc,
  - slaba swieca,
  - slabe lub nieznane Renko,
- ile faktycznie pojawia sie `PAPER_OPEN` w dzienniku decyzji.

## Nowe powody braku zaufania

### `PAPER_CONVERSION_BLOCKED`

Deckhand ustawia ten powod, gdy:
- nowych kandydatow jest duzo,
- nie przybywa nowych obserwacji ani nowych lekcji,
- nie ma nowych `PAPER_OPEN`,
- za to dominuja blokady ryzyka.

Interpretacja:
- agent strojenia nie powinien stroic dalej,
- bo pole jest zapchane kandydatami, ktore nie dochodza do papierowej lekcji.

### `FOREFIELD_DIRTY`

Deckhand ustawia ten powod, gdy:
- nowych kandydatow jest duzo,
- nie przybywa nowych obserwacji ani nowych lekcji,
- nie ma nowych `PAPER_OPEN`,
- dominuja kandydaci przepuszczani przez `PAPER_SCORE_GATE`,
- a znaczna ich czesc ma niski poziom pewnosci i slaba jakosc swiecy/Renko.

Interpretacja:
- agent strojenia nie powinien stroic dalej,
- bo widzi za duzo brudnego materialu i moglby sie dostrajac do szumu.

## Zakres zmian

Zmieniono:
- `MQL5\\Include\\Core\\MbTuningTypes.mqh`
- `MQL5\\Include\\Core\\MbTuningStorage.mqh`
- `MQL5\\Include\\Core\\MbTuningDeckhand.mqh`

## Uwagi operacyjne

- Zmiana nie dotyka hot-path wejsc transakcyjnych.
- Zmiana siedzi w deckhandzie i w zapisie polityki strojenia.
- Agent lokalny nadal dziala tylko wtedy, gdy deckhand wystawi `trusted=true`.
- Po wdrozeniu potrzebny jest zwykly cykl tuningu, aby nowe powody zaufania pojawily sie w `tuning_deckhand.csv`.
