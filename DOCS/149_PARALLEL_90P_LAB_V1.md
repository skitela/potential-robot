# 149 Parallel 90P Lab V1

## Cel

Przesunac laboratorium z poziomu:

- jeden tester MT5
- jedna linia danych
- jeden offline ML

na poziom:

- dwa niezalezne pasy MT5
- jedna linia danych QDM
- jedna linia ML

czyli realnie 4 tory pracy naraz.

## Kluczowa zmiana

Runner testera nie zabija juz wszystkich `terminal64.exe`, tylko tylko te procesy, ktore naleza do tej samej instalacji terminala. To odblokowuje dwa rozne terminale MT5 naraz:

- `C:\Program Files\OANDA TMS MT5 Terminal`
- `C:\Program Files\MetaTrader 5`

## Docelowy podzial

### Pas 1

OANDA MT5, walidacja brokerska i najwazniejsze FX:

- `EURUSD`
- `GBPUSD`
- `AUDUSD`
- `NZDUSD`
- `EURAUD`
- `GBPAUD`

### Pas 2

Drugi terminal MT5, pas offline/custom-ready:

- `USDJPY`
- `USDCHF`
- `USDCAD`
- `EURJPY`
- `GBPJPY`

### Pas 3

`QDM`:

- sync
- eksport pod MT5
- przygotowanie materialu pod `Custom Symbols`

### Pas 4

Offline ML:

- refresh danych
- trening modeli pomocniczych
- eksport `ONNX`

## Dlaczego to jest radykalnie szybsze

- dwa testery MT5 nie czekaja juz jeden na drugi
- QDM pracuje wlasnym pasem
- ML nie blokuje testera
- drugi terminal moze stac sie docelowo pasem `Custom Symbols`

## Co jeszcze warto zrobic przy planowanym restarcie

- zwiekszyc `pagefile` na `C:` z `2048 MB` do `system-managed` albo przynajmniej `16384 MB`
- po restarcie odpalic `START_PARALLEL_90P_LAB.ps1`

## Granice bezpieczenstwa

- glownym testerem strategii dalej zostaje `MT5`
- OANDA MT5 pozostaje pasem brokersko-wiernym
- drugi terminal nie zmienia nic na VPS i nie dotyka runtime live
- ML dalej nie pisze automatycznie do botow
