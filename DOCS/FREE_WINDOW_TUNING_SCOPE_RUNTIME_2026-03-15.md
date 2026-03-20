# Free Window Tuning Scope Runtime - 2026-03-15

## Cel

W tej wersji stary `OANDA_MT5_SYSTEM` dostaje juz nie tylko dokumentacyjny wniosek,
ale realny kontrakt wykonawczy:

- agent strojenia patrzy tylko na instrumenty, ktore maja sens w wolnych oknach,
- unified learning bus nie promuje juz calego dawnego wszechswiata,
- `SCUD` nie buduje tie-break rankingu dla rzeczy, ktorych i tak nie chcemy potem trenowac.

## Co zostalo dodane

Dodano osobny kontrakt scope:

- `CONFIG/free_window_tuning_scope_v1.json`

Jest to lekka lista symboli:

- aktywne:
  - `DE30.pro`
  - `US500.pro`
- pomocnicze:
  - `GOLD.pro`
- obserwacyjne:
  - `USDJPY.pro`

## Gdzie scope dziala

### 1. `learner_offline.py`

Po pobraniu zamknietych zdarzen z `decision_events.sqlite`:

- rekordy sa filtrowane po symbolu,
- raport i `learner_advice.json` powstaja juz tylko z tego zawezonego zestawu,
- do raportu dopisywany jest slad ile rekordow odpadlo przez scope.

### 2. `unified_learning_pack.py`

Przy budowie wspolnego advisory:

- universe symboli jest obcinany do scope,
- `runtime_light.preferred_symbol` moze juz wskazac tylko dozwolony instrument,
- payload nosi jawny blok `training_scope`.

### 3. `scudfab02.py`

`SCUD` filtruje:

- zamkniete zdarzenia czytane z `decision_events.sqlite`,
- oraz rekordy `shadowb`, zanim zbuduje ranking symboli.

To oznacza, ze tie-break i advisory nie beda juz rozstrzygaly poza zakresem wolnych okien.

## Dlaczego to jest dobre

Wczesniej stary system uczyl sie szeroko.
To bylo dobre, gdy byl glownym organizmem.

Teraz jego rola sie zmienila:

- nie ma juz trenowac wszystkiego,
- ma trenowac tylko to, co moze sensownie wejsc obok nowej floty.

To daje:

- czystsze dane,
- mniej szumu w rankingu,
- lepszy sens dla `learner_offline`,
- bardziej uczciwy `preferred_symbol`,
- i mniejsza pokuse, by stary system doradzal cos, czego i tak nie bedziemy wykonywac.

## Czego ta wersja jeszcze nie robi

Ta wersja jest swiadomie lekka.

Nie wprowadza jeszcze:

- twardego filtrowania po wlasnych, nowych `window_id` wolnych okien,
- osobnego profilu runtime starego systemu tylko dla tych wolnych slotow,
- ani zmian po stronie glownego `strategy.json`.

To jest celowe.
Najpierw zawezamy uczenie i advisory.
Potem dopiero bedziemy budowac osobny profil starego systemu do MT5.

## Wniosek

Od tej chwili stary agent strojenia jest realnie zawężony do instrumentow,
ktore maja sens przy wolnych oknach:

- `DE30`
- `US500`
- `GOLD`
- `USDJPY`

przy czym glowny ciezar nadal siedzi na:

- `DE30`
- `US500`

To jest dobry, praktyczny most miedzy starym trenerem a nowa flota wykonawcza.
