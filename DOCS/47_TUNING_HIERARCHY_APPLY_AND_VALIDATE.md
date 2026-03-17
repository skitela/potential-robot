# 47 Tuning Hierarchy Apply And Validate

## Cel

Po wygenerowaniu seedow rodzinnych i koordynatora trzeba je jeszcze:
- rozlozyc do `Common Files`
- zwalidowac, ze sa obecne i kompletne

## Aplikacja

Narzędzie:
- [APPLY_TUNING_FLEET_BASELINE.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\APPLY_TUNING_FLEET_BASELINE.ps1)

Rozklada do `Common Files`:
- polityki rodzinne
- logi rodzinne
- stan koordynatora
- log koordynatora

## Walidacja

Narzędzie:
- [VALIDATE_TUNING_HIERARCHY.ps1](C:\MAKRO_I_MIKRO_BOT\TOOLS\VALIDATE_TUNING_HIERARCHY.ps1)

Sprawdza:
- czy seed istnieje
- czy stan rodzin istnieje
- czy journale rodzin istnieja
- czy stan koordynatora istnieje
- czy log koordynatora istnieje
- czy kluczowe pola sa obecne

## Dlaczego to jest potrzebne

Bo sama architektura w projekcie to za malo.
Potrzebujemy jeszcze:
- materializacji na lokalnym dysku runtime
- prostego audytu, ze cala hierarchia strojenia naprawde zostala rozlozona
