# Free Window Old System Exclusive Runtime - 2026-03-15

## Cel

Od tej wersji stary `OANDA_MT5_SYSTEM` ma juz nie tylko:

- scope uczenia,
- scope advisory,
- i gotowy profil wolnych okien,

ale dostaje tez prosty mechanizm aktywacji:

- stary system pracuje tylko w wolnych oknach,
- nowa flota mikro-botow ma wyłącznosc poza tymi oknami.

## Zasada

Stary system ma byc uruchamiany tylko na:

- `DE30` rano zimą `08:00-08:45`,
- `US500` wieczorem `20:00-21:59`,
- `GOLD` wieczorem `20:00-21:59` jako drugi, lzejszy tor.

Poza tym:

- nie ma prawa wykonywac `MT5`,
- i nie ma prawa korzystac z dawnych szerokich okien:
  - `FX_AM`
  - `FX_ASIA`
  - `INDEX_EU`
  - `INDEX_US`
  - `METAL_PM`

## Narzedzia

- aktywator:
  - `TOOLS/ACTIVATE_FREE_WINDOW_TRADE_PROFILE.ps1`
- walidator:
  - `TOOLS/VALIDATE_FREE_WINDOW_TRADE_PROFILE.ps1`

## Co robi aktywator

1. Generuje sezonowy profil z `free_window_trade_runtime_v1.json`
2. Robi backup aktualnego `CONFIG/strategy.json`
3. Nadpisuje aktywny `CONFIG/strategy.json`
4. Zapisuje raport do `EVIDENCE`

## Co sprawdza walidator

- czy aktywny profil jest oznaczony jako `free_window_training_profile_active`,
- czy stare szerokie okna zniknely,
- czy wlaczone sa:
  - `hard_no_mt5_outside_windows`
  - `trade_window_strict_group_routing`
  - `trade_window_symbol_filter_enabled`

## Wniosek

To jest ta chwila, w ktorej stary system przestaje byc organizmem "na caly dzien".
Od teraz ma byc tylko bardzo celowanym trenerem i traderem wolnych okien.
