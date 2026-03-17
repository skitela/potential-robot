# Candidate Arbitration And Portfolio Heat Migration V1

## Cel

Ten dokument zapisuje, jak przeniesc do `MAKRO_I_MIKRO_BOT` te mechanizmy starego systemu, ktore sprawialy, ze w praktyce nie handlowal on wieloma parami naraz bez potrzeby, tylko sciskal swiat do jednej najlepszej okazji albo do bardzo malej shortlisty.

Nie chodzi o kopiowanie starego monolitu `1:1`.
Chodzi o odziedziczenie jego najbardziej wartosciowych odruchow przy zachowaniu nowej architektury:

- mikro-boty na dole,
- rodziny i domeny po srodku,
- koordynator sesji i kapitalu na gorze,
- niska latencja jako warunek nienaruszalny.

## Co naprawde robil stary system

Stary system nie mial jednego magicznego przelacznika `one trade only`.
Mial zestaw kilku warstw, ktore razem bardzo mocno zawazaly liczbe otwieranych pozycji:

1. twarde limity pozycji:
- jedna pozycja na symbol,
- limit pozycji rownoleglych,
- limit otwartego ryzyka portfela;

2. shortlista kandydatow:
- tylko najlepsze kandydatury dochodzily do konca petli decyzyjnej,
- `n_limit` byl dodatkowo sciskany przez tryb dnia, canary, ECO i ostrzezenia brokera;

3. arbitraz grup:
- kandydat byl wazony nie tylko lokalna jakoscia, ale tez prawem swojej grupy do aktywnosci w danym momencie;

4. koszyki specjalne:
- byly miejsca, gdzie kilka podobnych symboli bylo traktowanych jako jeden koszyk i wybierano `TOP_1`;

5. pacing i dedupe:
- system nie odgrywal tego samego pomyslu po kilka razy i nie wystrzeliwal zbyt wielu wejsc na poczatku okna;

6. tie-break przy near-tie:
- tylko gdy dwoch kandydatow bylo prawie rownych,
- bez losowosci w hot-path,
- z zachowaniem deterministycznego rozstrzygniecia albo `skip`.

## Co przenosimy do nowego systemu 1:1

Te elementy sa na tyle dobre i zgodne z nowym organizmem, ze warto je odziedziczyc praktycznie bez zmian ideowych:

### 1. Jedna pozycja na symbol

To ma zostac bez dyskusji.
Jeden symbol nie powinien miec kilku niezaleznych pozycji tego samego typu z kilku mikro-botowych impulsow.

### 2. Portfelowe cieplo przed nowym wejsciem

Przed otwarciem nowego trade'u musi byc policzone:

- ile ryzyka jest juz otwarte,
- ile z tego siedzi w tej samej rodzinie,
- ile w innych rodzinach,
- czy po dodaniu nowej pozycji nadal miescimy sie w dopuszczalnym otwartym ryzyku dnia.

To nie moze byc tylko informacja telemetryczna.
To ma byc realny blok.

### 3. Ograniczenie shortlisty kandydatow

Nawet jesli aktywna rodzina wygeneruje kilka sensownych kandydatow, nowy system nie powinien dalej przepychac calego tlumu.
Powinien utrzymywac bardzo mala shortlista, a potem wybrac zwyciezce.

### 4. `TOP_1` dla koszyka aktywnej rodziny

To jest najcenniejsza rzecz do odziedziczenia.
W aktywnym oknie rodzina powinna wystawic kilku kandydatow, ale do `live` powinien przechodzic tylko jeden najlepszy.

### 5. Dedupe i pacing

Te dwa odruchy dalej sa potrzebne:

- nie handlowac dwa razy tego samego impulsu,
- nie zuzywac prawa do wejsc zbyt szybko na poczatku okna.

## Co upraszczamy wzgledem starego systemu

Tutaj nowy organizm ma przewage architektoniczna, wiec nie ma sensu kopiowac calej zlozonosci starego monolitu.

### 1. Globalny limit pozycji rownoleglych

W starym systemie byl potrzebny bardziej, bo wiele grup zylo pod jednym dachem naraz.
U nas okna, sen domen i koordynator dnia juz zmniejszaja tlok.

Dlatego nowy system powinien miec:

- twardy limit pozycji na symbol,
- twardy limit zwyciezcow na aktywna rodzine,
- lagodny limit globalny na cala flote,

a nie tylko jeden glupi licznik na wszystko.

### 2. Arbitraz grup i overlap arbitration

W starym systemie grupy czesciej nachodzily na siebie.
U nas duza czesc tej roboty robi juz sam harmonogram:

- rodziny spia,
- domeny maja swoje godziny,
- koordynator budzi tylko te, ktore maja prawo dzialac.

Dlatego arbitraz grupowy upraszczamy do:

- priorytetu aktywnej rodziny,
- priorytetu domeny glownej i rezerwowej,
- obciecia priorytetu przy defensive, paper i probation.

### 3. Tie-break zewnetrzny

Stary system mial zewnetrznego doradce do near-tie.
Nowy system nie powinien odziedziczyc tego `1:1` w hot-path.

Zostawiamy zasade, ale upraszczamy wykonanie:

- `clear winner` -> bierzemy zwyciezce,
- `near tie` -> lekki deterministyczny tie-break lokalny,
- `true tie` -> `paper` moze alternowac, `live` ma `skip`.

## Co jest juz w nowym systemie praktycznie zastapione

Pewne mechanizmy starego systemu nie musza wracac w starej postaci, bo ich rola juz zostala przejeta przez nowa architekture.

### 1. Monolityczne skanowanie calego swiata naraz

To zastapily:

- okna czasowe,
- rodziny,
- domeny,
- sen i rozgrzewka.

### 2. Duzy centralny overlap manager

To zastapil:

- globalny koordynator sesji i kapitalu,
- stany `LIVE`, `DEFENSIVE`, `PAPER`, `RESERVE`, `REENTRY`.

### 3. Zewnetrzny tie-break doradczy przy kazdej okazji

To zastapi:

- lokalna karta kandydata,
- arbitraz rodzinny,
- portfelowe cieplo,
- proste i szybkie rozstrzygniecie near-tie.

## Gdzie to wpinamy w nowym systemie

To jest kluczowe.
Nie wpinamy tego ani do pojedynczego mikro-bota, ani do najwyzszego koordynatora dnia.

Najzdrowsze miejsce jest pomiedzy nimi.

Przeplyw ma wygladac tak:

1. mikro-bot ocenia lokalny instrument;
2. jesli ma sensowny sygnal, wystawia lekki rekord kandydata;
3. kandydaci trafiaja do arbitra aktywnej rodziny lub aktywnego koszyka;
4. arbiter wybiera `TOP_1`;
5. dopiero zwyciezca trafia do guardu kapitalowego i portfelowego;
6. jesli miesci sie w limicie ryzyka i stanie dnia, dostaje zgode na `live`;
7. jesli nie, schodzi do `paper` albo `skip`.

## Jak ma wygladac karta kandydata

Kandydat nie powinien byc pelnym trade planem ani wielkim JSON-em.
Ma byc lekki.

Minimalnie powinien miec:

- symbol,
- rodzine,
- domene,
- aktywne okno,
- setup i regime,
- lokalny score lub edge,
- confidence,
- koszt/spread pressure,
- execution pressure,
- planowane ryzyko pieniezne,
- kierunek,
- znacznik czy to `paper` czy `live`,
- znacznik czy kandydat pochodzi z glownej rodziny czy z rezerwy.

To wystarczy, zeby porownac 2-5 kandydatow bez zabijania latencji.

## Jak liczymy priorytet

Na start priorytet powinien byc prosty i przejrzysty.

Nie robimy czarnej skrzynki.

Proponowany model:

`priority = local_edge * quality_factor * family_factor * capital_factor`

Gdzie:

- `local_edge` to wynik lokalnej logiki mikro-bota,
- `quality_factor` uwzglednia spread, execution i czystosc setupu,
- `family_factor` uwzglednia stan rodziny i jej prawo do aktywnosci,
- `capital_factor` uwzglednia defensive mode, probation i portfelowe cieplo.

Nie dokladamy jeszcze ciezkiego meta-rankingu.
Na poczatek ma byc prosto, jasno i szybko.

## Reguly wyboru zwyciezcy

### Clear winner

Jesli kandydat prowadzi wyraznie, przechodzi dalej.

### Near tie

Jesli dwoch kandydatow jest bardzo blisko, uruchamiamy szybki tie-break:

- lepszy koszt,
- lepszy execution,
- mniejsze ryzyko pieniezne,
- wyzszy priorytet rodziny,
- wyzszy priorytet domeny glownej.

### True tie

Jesli dalej nie ma przewagi:

- w `paper` mozemy alternowac albo zbierac oba jako telemetryczna para,
- w `live` robimy `skip`.

To jest dojrzalsze niz sztuczne `50/50`.

## Roznica miedzy paper i live

### Paper

Paper ma byc laboratorium.
Moze byc bardziej otwarty poznawczo:

- wiecej telemetryki,
- mozliwosc alternacji przy prawdziwym remisie,
- zbieranie wiedzy o utraconych kandydaturach.

### Live

Live ma byc surowy:

- jeden zwyciezca na aktywna rodzine,
- brak losowosci,
- `true tie` konczy sie `skip`,
- cieplo portfela blokuje wejscie nawet wtedy, gdy kandydat wyglada dobrze lokalnie.

## Co wdrazamy etapami

### Etap A

- jedna pozycja na symbol,
- kandydat jako lekki rekord runtime,
- `TOP_1` dla aktywnej rodziny,
- `true tie -> skip` dla `live`.

### Etap B

- pelne portfelowe cieplo z wagami:
  - mocniej dla tej samej rodziny,
  - lzej dla innych rodzin,
- ograniczenie zwyciezcow per cykl dla domeny.

### Etap C

- rezerwy i probation uwzgledniane w `family_factor`,
- telemetryka near-tie i missed-candidate outcomes,
- dalsze uczenie agenta strojenia na bazie zwyciezcow i pominietych kandydatow.

## Najwazniejszy wniosek

Do nowego systemu nie trzeba przenosic starego monolitu.
Trzeba przeniesc jego najlepszy odruch:

spojrz na kilku dobrych kandydatow,
wybierz jednego najlepszego,
sprawdz, czy portfel moze go udzwignac,
i dopiero wtedy pozwol mu wejsc.

To jest element, ktory bardzo dobrze pasuje do naszego obecnego organizmu:

- nie psuje latencji,
- wzmacnia ochrone kapitalu,
- porzadkuje konkurencje miedzy mikro-botami,
- i moze realnie poprawic zysk netto przez lepsza selekcje.
