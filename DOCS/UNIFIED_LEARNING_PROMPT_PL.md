# UNIFIED LEARNING PROMPT - OANDA_MT5_SYSTEM

## Cel

Ujednolicic uczenie systemu tak, aby:

- LAB i runtime zbieraly wiedze we wspolnym formacie,
- wynik nauki splywal do jednego pliku doradczego,
- warstwa decyzyjna dostawala jeden wazny komunikat advisory,
- nic nie dotykalo hot-path tick -> decyzja -> zlecenie,
- wszystko dzialo tylko w paper/shadow, bez live mutation.

## Zasady nienegocjowalne

- Runtime owner pozostaje po stronie MQL5.
- Python nie wydaje zlecen.
- SCUD nie staje sie drugim silnikiem tradingowym.
- Nowa warstwa ma byc advisory, lekka i fail-open.
- Brak dodatkowego network I/O i ciezkiego file I/O na goracej sciezce.
- Kazdy instrument jest oceniany osobno.
- Ten sam instrument moze miec rozne wnioski dla roznych okien.

## Rzeczywistosc systemu

System ma kilka warstw wiedzy:

1. dane live:
- ticki,
- swiece,
- decyzje,
- odrzucenia,
- wyniki zamknietych prob.

2. nauka runtime:
- learner_offline,
- SCUD,
- lekkie porady dla runtime.

3. nauka LAB:
- zbiory etapu pierwszego,
- kontrfaktyki NO_TRADE,
- profile na jutro,
- ocena gotowosci shadow.

## Problem do rozwiazania

Dzis:

- dane rosna szybko,
- ale wiedza jest rozproszona,
- LAB i runtime nie mowia jeszcze jednym jezykiem,
- tylko czesc wynikow wraca do runtime,
- czesc analiz dziala na innych wzorcach danych niz runtime.

## Docelowy kierunek

Zbudowac jeden "bus wiedzy", czyli jeden plik advisory, ktory zbiera:

- learner_offline,
- SCUD,
- profile etapu pierwszego,
- kontrfaktyki,
- go/no-go shadow,
- etap dojrzalosci shadow,
- aktywne profile per instrument.

Ten plik ma miec dwie warstwy:

1. runtime_light
- maly,
- szybki,
- nadajacy sie do odczytu przez SCUD i runtime,
- tylko najwazniejsze sygnaly:
  - qa_light,
  - preferred_symbol,
  - ranks,
  - kilka lekkich metryk.

2. details
- pelny opis dla LAB i operatora,
- per instrument,
- per okno,
- zrodla, rekomendacje, profile i kontrfaktyki.

## Jak oceniac instrument

Kazdy instrument musi miec wynik zlozony z:

- oceny runtime po zamknietych zdarzeniach,
- oceny SCUD,
- oceny LAB z kontrfaktykow,
- rekomendacji etapu pierwszego,
- aktywnego profilu zaladowanego do paper runtime.

Ocena ma byc:

- konserwatywna,
- obcieta do bezpiecznego zakresu,
- odporna na malo probek,
- interpretowana jako:
  - PROMOTE,
  - NEUTRAL,
  - SUPPRESS.

## Wazna specyfika

Analiza ma byc osobno:

- per instrument,
- per okno handlowe,
- per rodzina strategii.

Okna:

- FX_AM,
- FX_ASIA,
- INDEX_EU,
- INDEX_US,
- METAL_PM.

Ten sam symbol w roznych oknach nie moze byc traktowany jako to samo zdarzenie.

## Warstwy strategii

Nie mieszac ich bezkrytycznie.

Osobno sledzic:

- swiece japonskie,
- Renko,
- profile bazowe z shadow,
- confluence kilku warstw.

Jesli pojawi sie nowa warstwa synergii, ma ona byc wynikiem danych, a nie dogmatu.

## Oczekiwane efekty

- jeden punkt prawdy o stanie nauki,
- jeden kanal advisory do runtime,
- latwiejsze strojenie paper scalpingu,
- lepsze porownanie instrumentow,
- szybsze dojrzewanie profili na jutro,
- brak naruszenia hot-path.

## Dalsze kroki

1. Ujednolicic schemat cech runtime i LAB.
2. Zwiekszyc liczbe probek kontrfaktycznych.
3. Dodac bezpieczne metody statystyczne:
- wazenie czasowe,
- skurcz dla malych probek,
- dolne granice ufnosci.
4. Rozdzielic nauke per okno i per rodzina strategii.
5. Dopuszczac nowe wplywy do runtime tylko jako advisory w paper/shadow.
