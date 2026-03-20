# Free Window Trade Runtime Profile - 2026-03-15

## Cel

Stary system ma juz nie tylko zawężony scope uczenia.
Ma tez dostac gotowy rytm runtime dla wolnych okien.

To oznacza dwie rzeczy naraz:

- dawne szerokie okna typu `FX_AM`, `FX_ASIA`, `INDEX_EU`, `INDEX_US`, `METAL_PM` nie maja juz byc docelowym rytmem starego systemu,
- zamiast nich stary system ma dostac male, celowane okna tylko tam, gdzie nowa flota mikro-botow nie pracuje.

## Co zostalo przygotowane

Dodano osobny kontrakt runtime:

- `CONFIG/free_window_trade_runtime_v1.json`

oraz generator sezonowego pliku strategii:

- `BIN/apply_free_window_trade_profile.py`

Generator nie nadpisuje od razu glownego `strategy.json`.
Buduje gotowy plik:

- `strategy.free_window_training.winter.json`
- albo `strategy.free_window_training.summer.json`

## Profil zimowy

Zima dostaje:

- `TRAIN_DE30_AM_WINTER`
  - `08:00-08:45` PL
  - tylko `DE30`
- `TRAIN_US500_PM`
  - `20:00-21:59` PL
  - tylko `US500`
- `TRAIN_GOLD_PM`
  - `20:00-21:59` PL
  - tylko `GOLD`

## Profil letni

Lato dostaje:

- `TRAIN_US500_PM`
  - `20:00-21:59` PL
  - tylko `US500`
- `TRAIN_GOLD_PM`
  - `20:00-21:59` PL
  - tylko `GOLD`

`DE30` rano wypada latem, bo nachodzi na `FX_ASIA` nowej floty.

## Co zostaje wygaszone

W runtime starego systemu do profilu wolnych okien nie przenosimy juz:

- dawnego szerokiego poranka FX,
- szerokiego `METAL_PM`,
- dziennego `INDEX_EU`,
- glownego `INDEX_US`,
- ani nocnego `FX_ASIA` jako aktywnego trade.

Te pasma staja sie:

- dziedzictwem historycznych danych,
- ale nie docelowym rytmem nowego treningu starego systemu.

## Jak tego uzyc

Wygenerowanie profilu zimowego:

```powershell
python BIN\apply_free_window_trade_profile.py --season winter
```

Wygenerowanie profilu letniego:

```powershell
python BIN\apply_free_window_trade_profile.py --season summer
```

## Wniosek

Teraz mamy juz dwa poziomy porzadku:

- scope uczenia i advisory,
- oraz osobny, gotowy scope runtime.

To jest wlasnie to "wyfasić tamte okna i wlaczyc dane instrumenty w danych oknach",
ale zrobione bez brutalnego niszczenia glownego `strategy.json`.
