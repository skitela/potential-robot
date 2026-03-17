# Kill-Switch Model

## Cel

Ten dokument opisuje docelowy model `kill-switch` w `C:\MAKRO_I_MIKRO_BOT`.

Model jest celowo zgodny z wzorcem z:

- `C:\GLOBALNY HANDEL VER1\EURUSD`

## Zasada

`kill-switch` nie czyta sekretu w hot-path.

Zamiast tego:

1. istnieje zrodlo zaufania z sekretami, np. `USB` / katalog `OANDAKEY`
2. osobny skrypt odswieza lokalny token czasowy
3. mikro-bot sprawdza tylko ten token
4. brak tokenu, token bledny albo przeterminowany oznacza `halt`

## Lancuch Operacyjny

```text
USB / OANDAKEY / BotKey.env
-> SYNC_OANDAKEY_TOKEN.ps1
-> FILE_COMMON\MAKRO_I_MIKRO_BOT\key\<SYMBOL>\oandakey_<symbol>.token
-> MbKillSwitchEvaluate()
-> halt / allow
```

## Co sprawdza runtime

Kazdy mikro-bot sprawdza:

- czy `kill_switch_required = true`
- czy istnieje plik tokenu
- czy zawartosc tokenu daje poprawny `timestamp`
- czy token nie jest starszy niz `kill_switch_max_age_sec`

Kody powodow blokady:

- `KILL_SWITCH_TOKEN_MISSING`
- `KILL_SWITCH_TOKEN_INVALID`
- `KILL_SWITCH_TOKEN_STALE`
- `KILL_SWITCH_TOKEN_BLOCKED`

## Cache runtime

Tak jak w wzorcowym `EURUSD`, runtime trzyma krotki cache wyniku:

- `last_kill_switch_check`
- `kill_switch_cached_present`
- `kill_switch_cached_halt`

Cel:

- nie czytac pliku tokenu co kazdy mikro-cykl,
- nie oslabic ochrony,
- ograniczyc narzut I/O.

## Skrypty operacyjne

Skrypty w projekcie:

- `TOOLS\SYNC_OANDAKEY_TOKEN.ps1`
- `TOOLS\SYNC_ALL_OANDAKEY_TOKENS.ps1`

Pierwszy odswieza token dla jednego symbolu.
Drugi odswieza tokeny dla calej partii z registry.

## Wazna granica odpowiedzialnosci

`kill-switch`:

- nie trzyma edge tradingowego,
- nie wybiera setupu,
- nie steruje ryzykiem pozycji,
- nie zastępuje runtime control,
- nie zastępuje `close_only`.

Jego rola jest waska:

- potwierdzic, ze bot ma aktualne pozwolenie na handel.

## Wniosek

Model `kill-switch` w `MAKRO_I_MIKRO_BOT` ma byc:

- lokalny,
- szybki,
- fail-closed,
- zgodny z wzorcem `EURUSD`,
- oparty o lekki token czasowy zamiast ciaglego czytania sekretow w runtime.
