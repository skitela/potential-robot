# 70. Manual Core Capital Contract V1

## Cel

Ten etap oddziela dwie rzeczy:

- runtime umie chronić kapital rdzeniowy,
- operator umie ten kapital rdzeniowy ustawic swiadomie i recznie.

To jest bardzo wazne, bo pierwszy odczyt equity z terminala nie zawsze musi byc idealnym odpowiednikiem realnego kapitalu bazowego, od ktorego chcemy liczyc ochronę `live`.

## Architektura

Wprowadzono jeden wspolny kontrakt globalny dla calego organizmu:

- projektowy plik zrodla:
  - `CONFIG\\core_capital_contract_v1.json`
- runtime state w `Common Files`:
  - `state\\_global\\core_capital_contract.csv`

Mikro-boty nie ustalaja juz same prawdy o rdzeniu kapitalu.

One:

- odczytuja wspolny kontrakt,
- cache-uja go lekko w runtime,
- i tylko respektuja jego wartosci.

## Zasada dzialania

Jesli kontrakt globalny jest:

- obecny
- i `enabled = 1`

to:

- `paper` bierze `paper_core_capital`
- `live` bierze `live_core_capital`

Jesli kontraktu nie ma albo jest wylaczony:

- runtime wraca do bezpiecznego fallbacku,
- czyli pierwszego zobaczonego `equity`.

## Dlaczego to jest dobre

To daje trzy korzysci:

- prawdziwy kapital bazowy moze byc ustawiony swiadomie,
- wszystkie domeny i mikro-boty widza te sama konstytucje kapitalowa,
- agenci nadal nie maja prawa zmieniac rdzenia kapitalu.

## Pliki

### Runtime

- `MQL5\\Include\\Core\\MbCoreCapitalContract.mqh`

### Config

- `CONFIG\\core_capital_contract_v1.json`

### Narzedzia

- `TOOLS\\APPLY_CORE_CAPITAL_CONTRACT.ps1`
- `TOOLS\\VALIDATE_CORE_CAPITAL_CONTRACT.ps1`

## Wartości bootstrap

Na potrzeby obecnego etapu przyjeto bootstrap:

- `paper_core_capital = 1000`
- `live_core_capital = 1000`

To nie jest dogmat.

To jest swiadomy punkt startowy zgodny z obecnym scenariuszem roboczym i ma zostac pozniej zaktualizowany, jesli realny kapital bazowy bedzie inny.

## Najwazniejszy wniosek

Od teraz rdzen kapitalu nie jest juz tylko domyslem runtime.

Moze byc ustawiony wprost, recznie i wspolnie dla calej floty, bez oddawania tej decyzji agentom czy chwilowemu equity terminala.
