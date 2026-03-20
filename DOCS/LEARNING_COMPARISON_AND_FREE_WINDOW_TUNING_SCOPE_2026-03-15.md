# Porownanie starego i nowego systemu pod katem uczenia oraz zakres agenta strojenia dla wolnych okien

## Cel

Ten dokument odpowiada na jedno konkretne pytanie:

- jak porownac `OANDA_MT5_SYSTEM` i `MAKRO_I_MIKRO_BOT` pod katem uczenia,
- co w obu systemach pelni role "agenta strojenia",
- oraz jakie instrumenty stary system powinien stroic tylko dla wolnych okien czasowych, bez nachodzenia na nowa flote.

## Najkrotszy wniosek

Stary system jest silniejszy jako:

- laboratorium uczenia,
- pamiec decyzyjna,
- offline QA,
- advisory per instrument i per okno.

Nowy system jest silniejszy jako:

- runtime strojenia,
- bezpieczne lokalne dostrajanie,
- hierarchia `lokalny -> rodzina -> koordynator`,
- integracja z mikro-botami bez niszczenia latencji.

Wniosek praktyczny:

- nowy system powinien pozostac glownym organizmem scalpingu i runtime strojenia,
- stary system powinien byc zawezony do treningu i advisory tylko dla instrumentow, ktore maja sens w wolnych oknach.

## 1. Stary system - jak on sie uczy

W starym `OANDA_MT5_SYSTEM` uczenie nie bylo jednym przyciskiem "autotune".
To byl uklad kilku warstw:

- `decision_events.sqlite` jako ledger pamieci decyzji,
- `learner_offline.py` jako statystyczne sumienie i QA gate,
- `SCUD` jako advisory / tie-break przy near-tie,
- unified learning pack jako proba zebrania wszystkiego do jednego lekkiego busa wiedzy.

Najwazniejsze cechy tego modelu:

- uczenie jest glownie ex-post,
- patrzy na zamkniete zdarzenia i jakosc wynikow,
- ma byc `fail-open`,
- nie ma dotykac hot-path,
- rozroznia instrument i okno czasowe,
- nadaje sie do spokojnego treningu, rankingu i dojrzewania profili.

To jest bardzo dojrzale podejscie do:

- oceny jakosci,
- wykrywania degradacji,
- hamowania overfitu,
- zbierania wiedzy w tle.

Ale to nie jest idealny model do bezposredniego, szybkiego scalpingu w centrum runtime.

## 2. Nowy system - jak on sie uczy

`MAKRO_I_MIKRO_BOT` ma uczenie znacznie blizej wykonania.

Tutaj warstwa strojenia jest juz:

- lokalna dla mikro-bota,
- rodzinna,
- koordynowana centralnie,
- ograniczona przez guardy kosztu, okna, kapitalu i brokera.

Najwazniejsze cechy nowego modelu:

- lokalny agent czyta lokalne buckety i runtime state,
- majtek techniczny pilnuje czystosci danych,
- rodzina naklada granice wspolne,
- koordynator pilnuje kolejnosci i rollbacku,
- strojenie jest male, sekwencyjne i bezpieczne,
- nic nie przepisywuje kodu w runtime.

To jest model duzo lepszy do:

- scalpingu,
- mikro-latencji,
- realnego zycia wielu botow naraz,
- i ostroznego przejscia `paper -> live`.

## 3. Gdzie stary system jest lepszy od nowego

Stary system nadal jest wyjatkowy w kilku rzeczach:

- ma bardzo dojrzala pamiec `decision_events`,
- ma lepiej wyodrebnione sumienie statystyczne,
- ma advisory per okno i per instrument,
- duzo naturalniej nadaje sie do treningu ex-post niz do bezposredniego sprintu egzekucyjnego,
- jego wiedza jest bardziej "laboratoryjna" i przekrojowa.

Czyli:

- jesli chcemy spokojnie sprawdzac jakosc instrumentow,
- porownywac profile,
- budowac preferencje per okno,
- i uczyc sie bez presji tickowego runtime,

to stary system nadal jest bardzo cennym narzedziem.

## 4. Gdzie nowy system jest lepszy od starego

Nowy system wygrywa tam, gdzie stary zaczynal sie dusic:

- latencja,
- lokalnosc decyzji,
- modularnosc,
- zachowanie genotypu instrumentu,
- bezpieczne strojenie blisko mikro-bota.

To oznacza, ze:

- stary system nie powinien byc juz glownym silnikiem scalpu,
- ale moze byc swietnym trenerem dla wybranych, wolnych okien.

## 5. Co to znaczy dla "agenta strojenia" starego systemu

W starym systemie "agent strojenia" nie jest jednym modulem o nazwie identycznej jak w nowym systemie.
Praktycznie te role skladaja sie z:

- `learner_offline`,
- unified learning / advisory bus,
- oraz warunkowo `SCUD`, gdy sluzy do tie-break i pomocniczej oceny.

I tutaj najwazniejsza decyzja jest taka:

**stary agent strojenia nie powinien juz byc szeroki i ogolny.**

Powinien byc zawezony tylko do tych instrumentow, ktore maja potencjal realnego treningu w wolnych oknach czasowych.

Inaczej:

- bedzie uczyl sie rynku, ktorego i tak nie bedzie wykonywal,
- bedzie mieszal okna nalezace do nowej floty,
- i bedzie budowal wiedze mniej przydatna operacyjnie.

## 6. Wlasciwy zakres instrumentow dla starego agenta strojenia

Na bazie mapy wolnych okien i dotychczasowego dopasowania instrumentow, prawidlowy zakres wyglada tak.

### Zestaw aktywny - rzeczywisty trening

- `DE30.pro`
- `US500.pro`

To sa dwa najwazniejsze instrumenty dla starego systemu, jesli ma on pracowac obok nowej floty.

Dlaczego:

- `DE30.pro` ma sens w zimowym porannym mini-oknie `08:00-08:45`,
- `US500.pro` ma najlepszy sens w wolnym wieczornym oknie `20:00-21:59`,
- oba instrumenty sa czyste okiennie,
- oba nie wchodza w centralny rytm nowej floty scalpingowej,
- oba daja staremu systemowi wartosciowy material do treningu `trade`, nie tylko do scalp mikro-wejsc.

### Zestaw wtorny - paper / lzejszy eksperyment

- `GOLD.pro`

Powod:

- wieczorne wolne okno nadal daje mu wartosc obserwacyjna,
- ale to nie powinien byc instrument glowny dla starego systemu,
- lepiej traktowac go jako drugi tor nauki niz pierwszy.

### Zestaw cien / shadow only

- `USDJPY.pro`

Powod:

- nocne fragmenty przed Azja sa za slabe na glowny live-trening starego systemu,
- ale moga dawac material obserwacyjny i porownawczy,
- to dobry kandydat do `shadow`, nie do glownych decyzji strojenia.

### Zestaw wykluczony z aktywnego strojenia starego systemu

Z aktywnego scope starego agenta strojenia powinny wypasc:

- `EURUSD.pro`
- `GBPUSD.pro`
- szeroki koszyk FX na poranek
- metale poza `GOLD.pro`
- wszystko z pasma `22:00-24:00`
- wszystko, co nie ma sensownego wolnego okna obok nowej floty

Powod jest prosty:

- te instrumenty albo naleza juz do nowego systemu,
- albo nie maja zdrowego kosztowo i okiennie miejsca,
- albo duplikuja nauke bez realnej przyszlej egzekucji.

## 7. Docelowy zakres pracy starego agenta strojenia

Najrozsadniejszy model dla starego systemu:

### Poziom A - aktywne strojenie

- `DE30.pro`
- `US500.pro`

### Poziom B - wspomagajace paper learning

- `GOLD.pro`

### Poziom C - tylko obserwacja / shadow

- `USDJPY.pro`

Ten podzial jest wazny, bo nie wszystko musi miec ten sam status:

- niektore instrumenty maja byc naprawde trenowane,
- niektore tylko wspierac porownanie,
- a niektore maja zostac wyłącznie sensorem rynku.

## 8. Jak to osadzic operacyjnie

Jesli bedziemy to wdrazac, to stary system powinien dostac:

- osobny profil treningowy,
- osobny zawezony scope instrumentow,
- filtrowanie uczenia per `instrument + okno`,
- advisory tylko dla dozwolonego zestawu wolnych okien.

Najwazniejsze zasady:

- `learner_offline` ma oceniac tylko dozwolone instrumenty i dozwolone okna,
- `SCUD` nie powinien rozstrzygac rzeczy spoza tego scope,
- unified learning output nie powinien mieszac `FX_AM` nowej floty z wieczornym `US500` starego treningu,
- nowe profile starego systemu maja byc budowane tylko dla tego zawezonego wszechswiata.

## 9. Wniosek koncowy

Jesli patrzymy uczciwie:

- stary system jest lepszy jako trener i laboratorium wiedzy,
- nowy system jest lepszy jako wykonawca i runtime strojenia.

Dlatego najlepszy uklad wspolpracy jest taki:

- nowy system odpowiada za glowny scalping i biezace bezpieczne strojenie,
- stary system odpowiada za zawezony trening i advisory tylko w wolnych oknach.

I w tym sensie agent strojenia starego systemu powinien byc juz celowany tylko w:

- `DE30.pro`
- `US500.pro`
- pomocniczo `GOLD.pro`
- obserwacyjnie `USDJPY.pro`

a nie w szeroki, dawny wszechswiat wszystkich par i sesji.

To bedzie:

- lzejsze,
- czystsze,
- bardziej spojne z nowa flota,
- i znacznie bardziej wartosciowe poznawczo.

## Zrodla wewnetrzne

- `DOCS/UNIFIED_LEARNING_PROMPT_PL.md`
- `DOCS/TECHNICAL_MEMO_GPT53_CODEX.md`
- `DOCS/FREE_WINDOWS_TRAINING_FIT_2026-03-15.md`
- `DOCS/TRAINING_WINDOW_INSTRUMENT_FIT_2026-03-15.md`
- `BIN/learner_offline.py`
- `BIN/safetybot.py`
- `C:\MAKRO_I_MIKRO_BOT\DOCS\42_LOCAL_TUNING_AGENT_V1.md`
- `C:\MAKRO_I_MIKRO_BOT\DOCS\43_TUNING_AGENT_ARCHITECTURE_V1.md`
- `C:\MAKRO_I_MIKRO_BOT\DOCS\85_TUNING_GUARD_MATRIX_RUNTIME_INTEGRATION_V1.md`
