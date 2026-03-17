# 46 Tuning Fleet Baseline Tool

## Cel

Narzędzie buduje weekendowa, lokalna baze startowa pod agentow rodzinnych i koordynatora.

Nie wymaga jeszcze ich pelnej integracji z runtime `MT5`.
Zbiera dane z:
- rejestrow rodzin
- rejestrow wdrozen
- aktualnych plikow `runtime_state`
- lokalnych `tuning_policy`, jesli juz istnieja

I zapisuje na dysku lokalnym:
- rejestr floty strojenia
- seed polityk rodzinnych
- seed koordynatora
- raport bazowy

## Narzedzie

- [BUILD_TUNING_FLEET_BASELINE.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\BUILD_TUNING_FLEET_BASELINE.ps1)

## Efekt

Po uruchomieniu powstaja:
- `CONFIG/tuning_fleet_registry.json`
- `RUN/TUNING/family_policy_seed_<family>.json`
- `RUN/TUNING/coordinator_policy_seed.json`
- raport w `EVIDENCE`

## Dlaczego to jest potrzebne

Bo zanim agent rodzinny i koordynator wejda do runtime, dobrze jest miec:
- ich stan bazowy
- ich spojrzenie na rodziny
- ich pierwsza polityke
- ich miejsce na dysku lokalnym

To pozwala budowac nastepne kroki bez improwizacji.
