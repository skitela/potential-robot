# Raport Wieczorny Wlasciciela Systemu

## Cel
Raport wieczorny jest prostszym widokiem biznesowym niz dashboard operatorski. Ma odpowiadac na pytanie:

- czy dzien byl dobry czy slaby,
- ktore pary zasluguja na pochwale,
- ktore pary wymagaja kontroli,
- jaka jest najwazniejsza rekomendacja na kolejny cykl.

## Artefakty
- `EVIDENCE\DAILY\raport_wieczorny_latest.txt`
- `EVIDENCE\DAILY\raport_wieczorny_latest.json`
- `EVIDENCE\DAILY\dashboard_wieczorny_latest.html`

## Generator
- `TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1`
- `RUN\GENERATE_EVENING_REPORT_NOW.ps1`
- `TOOLS\REGISTER_EVENING_REPORT_TASK.ps1`

## Zakres danych
Raport wieczorny korzysta z:
- dziennego raportu systemowego,
- wynikow 24h per para,
- latencji dobowej,
- execution pressure,
- liczby decyzji `READY`.

## Odbiorca
Raport wieczorny jest przeznaczony dla wlasciciela systemu i osob nadzorczych, ktore nie potrzebuja surowego widoku operatorskiego.
