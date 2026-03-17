# Family Candidate Arbitration Runtime v1

## Cel

Wdrozyc lekki arbitraz kandydatow tak, aby w aktywnym oknie rdzeniowym rodzina nie wpuszczala kilku srednich wejsc naraz, tylko wybierala jednego najlepszego reprezentanta `TOP-1`.

Najwazniejsze zalozenie:

- nie budujemy ciezkiego globalnego turnieju wszystkich domen przez cala dobe
- korzystamy z faktu, ze w biezacej architekturze rdzeniowej normalnie aktywna jest jedna rodzina handlowa naraz
- arbitraz odbywa sie wewnatrz aktywnej rodziny lub grupy
- po wyborze zwyciezcy dalej dzialaja guardy kapitalowe i wykonawcze

## Dlaczego to jest lekkie

Nowy runtime nie porownuje wszystkiego ze wszystkim. Dla kazdego kandydata:

- mikro-bot publikuje lekki snapshot kandydata dla swojej aktywnej grupy
- arbiter czyta tylko kilka swiezych snapshotow z tej grupy
- wybiera `TOP-1`
- przy remisie `live` stosuje `skip`, a w `paper` naprzemiennosc do celow poznawczych

To ogranicza narzut, bo:

- nie ma stalego globalnego rankingu calej floty
- nie ma losowosci w `live`
- nie ma potrzeby ciaglego przeliczania nieaktywnych rodzin

## Zakres grup arbitrazu

W `v1` arbiter dziala na poziomie aktywnej grupy:

- `FX_MAIN`
- `FX_ASIA`
- `FX_CROSS`
- `METALS`
- `INDEX_EU`
- `INDEX_US`

W metalach dwie rodziny wykonawcze sa celowo sklejone do jednej grupy arbitrazu `METALS`, aby w glownym oknie metalowym wybierac najlepszego kandydata sposrod:

- zlota
- srebra
- platyny
- miedzi

## Jak liczony jest priorytet

Priorytet kandydata jest lekki i deterministyczny. Bierze pod uwage:

- sile lokalnego score
- confidence
- spread regime
- execution regime
- delikatna kare za mniej korzystny profil ryzyka

To nie zastępuje strategii ani strojenia. To jest ostatnia, praktyczna selekcja miedzy kilkoma kandydatami, ktorzy i tak przeszli lokalne bramki jakosci.

## Zachowanie runtime

Kazdy mikro-bot:

- zapisuje snapshot swojego aktywnego kandydata do stanu grupowego
- czyści snapshot, gdy kandydat przestaje byc wazny, nie przechodzi rozmiaru albo odpada na prechecku
- pyta arbitra o zgode przed wejsciem

Arbiter:

- patrzy tylko na swieze snapshoty z krotkim TTL
- liczy liczbe aktywnych kandydatow
- wybiera `TOP-1`
- wykrywa `near tie`
- wykrywa `true tie`

Reguly rozstrzygania:

- `clear winner` -> zwyciezca wchodzi dalej
- `near tie` -> nadal wygrywa `TOP-1`, ale stan jest zapisany diagnostycznie
- `true tie` w `live` -> `skip`
- `true tie` w `paper` -> naprzemienne rozstrzygniecie do nauki

## Trwalosc danych

Arbiter nie rozbudowuje ciezkiej historii. Uzywa:

- nadpisywanych snapshotow kandydatow per symbol
- nadpisywanego stanu ostatniej decyzji arbitra dla grupy

To znaczy:

- stan jest lekki
- nie puchnie bez potrzeby
- nie dokladamy nowej ciezkiej bazy historycznej

## Efekt oczekiwany

Najwazniejszy efekt `v1`:

- mniej slabszych wejsc
- mniej rozproszonego ryzyka wewnatrz aktywnej rodziny
- bardziej selektywny wybor w oknie bez istotnego pogorszenia latencji

To jest swiadome odziedziczenie jednej z najlepszych praktycznych cech starego systemu, ale bez powrotu do jego ciezkiego monolitu.

## Stan wdrozenia

Etap `v1` obejmuje:

- nowy modul arbitra kandydatow w warstwie core
- integracje ze wszystkimi `17` mikro-botami
- kompilacje floty `17/17`
- przejscie walidacji layoutu i koordynatora sesji

To jest gotowa baza pod kolejny etap:

- ewentualne dopiecie portfelowego `heat gate`
- ewentualne dodatkowe reguly shortlisty lub limitu `TOP-N`
- dalsza obserwacje runtime po otwarciu rynku
