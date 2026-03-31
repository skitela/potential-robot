# Plan Wdrożenia Pierwszej Fali Na VPS

Cel:

- domknąć pierwszą falę dla:
  - `US500`
  - `EURJPY`
  - `AUDUSD`
  - `USDCAD`
- utrzymać ten sam poziom pewności na:
  - laptopie,
  - torze testerowym,
  - torze wykonawczym po migracji,
  - VPS

## Etap 1. Preflight lokalny

- przełącz runtime na `BROKER_PARITY_FIRST_WAVE`
- zwaliduj koordynator sesji i kapitału
- odśwież audyty:
  - przejścia do serwera,
  - lustra brokera,
  - prawdy wykonania,
  - aktywności pierwszej fali,
  - domknięcia lekcji,
  - dobrostanu,
  - pełnego stosu

## Etap 2. Migracja kontrolowana

- wykonaj migrację MT5 z kontrolowanym zatrzymaniem i ponownym startem
- odczekaj okno rozruchowe
- przepuść audyt po migracji
- w razie bezpiecznej potrzeby uruchom naprawy lekkie

## Etap 3. Potwierdzenie po starcie

Sprawdź dla całej czwórki:

- świeży stan pracy
- świeże podsumowanie wykonania
- świeży dziennik decyzji
- świeże obserwacje modelu
- świeże lekcje
- świeży zapis wiedzy
- brak zaległego ogona synchronizacji VPS

## Etap 4. Stabilizacja

- odśwież dobrostan nauki
- odśwież pełny audyt
- sprawdź, czy nadzór widzi:
  - brak postępu nauki,
  - brak domknięcia lekcji,
  - brak zapisu wiedzy,
  - przerwanie przepływu po migracji

## Kryterium sukcesu

- runtime profilu pierwszej fali jest zgodny z celem
- lustro brokera jest gotowe dla całej czwórki
- po migracji audyt rozruchu przechodzi
- lekcje i wiedza domykają się lub nadzór umie wprost wskazać, gdzie łańcuch się zatrzymał
- dobrostan zgłasza problem w minutach, a nie po długim czasie
