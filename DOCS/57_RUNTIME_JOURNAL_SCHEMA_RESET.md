# 57. Runtime Journal Schema Reset

## Cel

Gdy journal runtime zmienia schema, samo dopisanie nowych kolumn do starego pliku nie wystarcza. Trzeba:

- odsunac stary plik do archiwum,
- pozwolic runtime stworzyc nowy naglowek,
- upewnic sie, ze lokalny serwis odtworzy journal bez czekania na przypadkowa zmiane danych.

## Narzedzie

Do tego celu dodano:

- [RESET_RUNTIME_JOURNAL_SCHEMA.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\RESET_RUNTIME_JOURNAL_SCHEMA.ps1)

Narzedzie:

- archiwizuje wskazany journal dla wybranych symboli,
- niczego nie kasuje na twardo,
- zostawia czytelny slady w `archive\schema_reset_*`.

## Zastosowanie w tej rundzie

Narzędzie zostalo uzyte dla:

- `tuning_deckhand.csv`

na symbolach:

- `EURUSD`
- `GBPUSD`
- `USDCAD`
- `USDCHF`
- `USDJPY`
- `AUDUSD`
- `NZDUSD`

Po schema reset lokalny serwis strojenia wymusza teraz odtworzenie journala, jesli plik zniknal. To daje nam:

- czysty naglowek po zmianie formatu,
- brak mieszania starej i nowej epoki,
- odtwarzalny proces porzadkowy na przyszlosc.
