# Prelive State Machine Audit v1

## Cel

Sprawdzic przed `live`, czy mechanizm domenowy:

- `SLEEP`
- `PREWARM`
- `LIVE`
- `LIVE_DEFENSIVE`
- `PAPER_ACTIVE`
- `PAPER_SHADOW`
- `REENTRY_PROBATION`

jest nie tylko opisany w architekturze, ale tez spójny w:

- konfiguracji
- stanie domen w `Common Files`
- runtime control
- glownym `go/no-go`

## Co audyt sprawdza

Walidator maszyny stanów sprawdza teraz:

- czy wszystkie oczekiwane stany sa zapisane w rejestrze architektury
- czy koordynator sesji odnosi sie tylko do znanych domen rezerwowych
- czy kazda domena ma:
  - stan sesyjny
  - runtime control
  - zgodny `requested_mode`
  - zgodny `risk_cap`
- czy stany nie tworza sprzecznych kombinacji, na przyklad:
  - `SLEEP` z aktywna grupa
  - `PAPER_ACTIVE` bez `PAPER_ONLY`
  - `LIVE_DEFENSIVE` bez `RUN`
  - `REENTRY_PROBATION` bez `RUN`
  - aktywna rezerwa bez kandydata
- czy w danym momencie nie ma wiecej niz jednej domeny, ktora prosi o `RUN`

## Wazna cecha audytu

Audyt odroznia teraz:

- realny blad
- od jeszcze niepodpietego runtime symbolu

To znaczy:

- brak kluczowego pliku domeny jest bledem
- ale brak stanu symbolu dla eksperta, ktory jeszcze nie zostal podlaczony do wykresu, jest tylko ostrzezeniem operacyjnym

To bylo potrzebne, zeby raport nie dawal falszywych alarmow dla metali i indeksow, ktore sa juz gotowe architektonicznie, ale jeszcze nie wszedzie zamontowane runtime na wykresach.

## Integracja z go/no-go

Audyt zostal wpiety do glownego `prelive go/no-go`.

To jest wazne, bo od teraz:

- sama poprawna skladnia skryptu nie wystarcza
- krok `session_state_machine` przejdzie tylko wtedy, gdy walidator zwroci `ok=true`

## Wynik tej rundy

Na chwile wykonania audytu:

- maszyna stanow jest spójna
- aktywna domena `RUN` byla tylko jedna
- nie stwierdzono sprzecznosci w stanach domen
- wykryto jedynie ostrzezenia o symbolach metali i indeksow, ktore nie maja jeszcze lokalnego runtime na wykresie

To jest dobry wynik przed poniedzialkiem, bo:

- architektura nie ma widocznej cichej sprzecznosci
- runtime domenowy dziala zgodnie z zalozeniami
- wiemy tez uczciwie, co jest jeszcze niepodpiete operacyjnie
