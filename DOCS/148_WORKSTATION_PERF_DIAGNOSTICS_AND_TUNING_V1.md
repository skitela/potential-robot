# 148 Workstation Perf Diagnostics And Tuning V1

## Cel

Podniesc przepustowosc lokalnego laboratorium bez mieszania runtime MT5/OANDA z offline ML i bez recznego strojenia przy kazdym starcie.

## Co wdrozono

- diagnostyke stacji roboczej do raportu JSON i MD
- wymuszenie planu zasilania `Wysoka wydajnosc`
- stale katalogi `perf/tmp/cache/joblib/pycache` na szybkim NVMe `C:`
- profile wydajnosci dla offline ML:
  - `ConcurrentLab`
  - `OfflineMax`
  - `Light`
- podnoszenie priorytetu dla:
  - `terminal64`
  - `metatester64`
  - `qdmcli`
  - `python`
  - wrapperow laboratorium
- sprowadzanie `Code` i `chrome` do `Normal` podczas uruchamiania laboratorium FX

## Najwazniejsze wnioski diagnostyczne

- laptop ma wystarczajace CPU i RAM do naszego toru `MT5 + QDM + offline ML`
- `C:` na NVMe jest prawidlowym miejscem dla danych i cache
- `D:` na USB/exFAT nie powinien byc uzywany do ciezkiej pracy testowej i uczacej
- glowne realne tarcie powodowaly procesy interaktywne (`Code`, `chrome`), a nie sam MT5
- GPU nie jest glownym ograniczeniem dla obecnego stosu
- pagefile jest maly i warto go pozniej rozwazyc do powiekszenia, ale nie zostal automatycznie zmieniony, bo wymaga kontrolowanego okna z restartem

## Granice bezpieczenstwa

- nie ustawiono sztywnej `CPU affinity`, bo na tym laptopie z rdzeniami hybrydowymi mogloby to pogorszyc scheduler Windows
- offline ML dalej nie zapisuje nic automatycznie do logiki botow
- agenci strojenia i wewnetrzne uczenie botow zostaja, bo obsluguja runtime i paper, a nie laboratorium offline

## Efekt

Laboratorium FX moze teraz sensownie pracowac w 3 torach:

- MT5 tester
- QDM data lane
- offline ML

bez recznego pilnowania priorytetow i katalogow roboczych przy kazdym starcie.
