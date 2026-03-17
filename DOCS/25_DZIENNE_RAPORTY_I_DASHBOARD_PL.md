# Dzienne Raporty I Dashboard PL

## Cel

Ta warstwa daje czytelny, codzienny raport po polsku dla operatora,
tradera i właściciela systemu.

## Co powstaje

1. Raport dzienny per para
- wynik 24h
- wynik względem kapitału startowego dnia
- tryb pracy
- średnia i maksymalna latencja
- liczba decyzji i liczba sygnałów `READY`
- ostatni powód działania lub blokady

2. Raport sumaryczny
- liczba par z zyskiem
- liczba par ze stratą
- wynik sumaryczny systemu
- średnia dobowa latencja
- maksymalna dobowa latencja

3. Dashboard HTML
- po polsku
- gotowy do otwarcia bezpośrednio w przeglądarce
- rozbudowany operatorsko:
  - podsumowanie dnia
  - karty rodzin
  - liderzy `READY`
  - najnizsza latencja
  - najwyzszy `execution pressure`
  - biezace sterowanie operatorskie

## Gdzie są pliki

Raporty trafiają do:

- `EVIDENCE\DAILY\raport_dzienny_*.json`
- `EVIDENCE\DAILY\raport_dzienny_*.txt`
- `EVIDENCE\DAILY\dashboard_dzienny_*.html`

Ostatnia wersja jest też zapisywana jako:

- `EVIDENCE\DAILY\raport_dzienny_latest.json`
- `EVIDENCE\DAILY\raport_dzienny_latest.txt`
- `EVIDENCE\DAILY\dashboard_dzienny_latest.html`

## Uruchamianie ręczne

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\RUN\GENERATE_DAILY_REPORTS_NOW.ps1
```

## Harmonogram 20:30

Można zarejestrować zadanie systemowe:

```powershell
powershell -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\REGISTER_DAILY_REPORT_TASK.ps1
```

Domyślna godzina:

- `20:30`

## Sterowanie pol-interaktywne

Dashboard ma polskie akcje operatora:

- `Wlacz tryb normalny`
- `Wlacz close-only`
- `Zatrzymaj system`
- `Raport dzienny teraz`
- `Raport wieczorny teraz`

Sa one oparte na:

- `TOOLS\SET_RUNTIME_CONTROL_PL.ps1`
- `TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1`
- `RUN\WLACZ_TRYB_NORMALNY_SYSTEMU.ps1`
- `RUN\WLACZ_CLOSE_ONLY_SYSTEMU.ps1`
- `RUN\ZATRZYMAJ_SYSTEM.ps1`

Ta warstwa nie dotyka strategii i nie dociąża `OnTick`. Zapisuje tylko lokalne pliki sterowania per para.

## Po co to jest

Ta warstwa odpowiada na potrzeby operatorskie:

- szybki obraz wyniku każdej pary
- szybki obraz całego systemu
- prosty dashboard po polsku
- gotowość do codziennego użycia bez czytania surowych logów
