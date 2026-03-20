# 163 MT5 MQL5 Helpbooks And Training System Audit V1

Data: 2026-03-20

## Cel

Ten dokument zbiera najważniejsze wnioski z dwoch zrodel pomocy MetaTrader 5 / MQL5:

- lokalnej pomocy terminala MetaTrader 5
- oficjalnych materialow MetaQuotes, ktore odpowiadaja tresciom z wbudowanych ksiazek pomocy i sa czytelne do analizy

Celem nie jest przepisanie dokumentacji, tylko wyciagniecie tych rzeczy, ktore realnie pomagaja zbudowac mocniejszy system treningowo-scalpingowy dla `MAKRO_I_MIKRO_BOT`.

## Co zostalo znalezione lokalnie

Na laptopie istnieja lokalne artefakty pomocy:

- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Help\mt5terminal.chm`
- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\bases\books.dat`
- `C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\bases\books.dat`

Praktycznie:

- `mt5terminal.chm` jest glowna lokalna pomoca platformy
- `books.dat` to cache pozycji z zakladki Books
- w tym srodowisku shellowym nie dalo sie uczciwie wyjac i przejrzec tych ksiazek w sposob gwarantujacy pelna czytelnosc tresci

Dlatego jako zrodlo analityczne zostaly uzyte oficjalne strony MetaQuotes i MQL5, odpowiadajace tej samej warstwie wiedzy.

## Najwazniejsze zrodla oficjalne

- Strategy Testing:
  - https://www.metatrader5.com/en/terminal/help/algotrading/testing
- Testing Features:
  - https://www.metatrader5.com/en/terminal/help/algotrading/testing_features
- MetaTester and Remote Agents:
  - https://www.metatrader5.com/en/terminal/help/algotrading/metatester
- How the Tester Downloads Historical Data:
  - https://www.metatrader5.com/en/terminal/help/algotrading/test_preparation
- Custom Financial Instruments:
  - https://www.metatrader5.com/en/terminal/help/trading_advanced/custom_instruments
- Market Watch:
  - https://www.metatrader5.com/en/terminal/help/trading/market_watch
- Working with Python:
  - https://www.metatrader5.com/en/metaeditor/help/development/python
- Python Integration reference:
  - https://www.mql5.com/en/docs/integration/python_metatrader5
  - https://www.mql5.com/en/docs/python_metatrader5/mt5initialize_py
  - https://www.mql5.com/en/docs/python_metatrader5/mt5copyratesfrom_py
- Event handlers / tester:
  - https://www.mql5.com/en/docs/event_handlers/ontesterinit
  - https://www.mql5.com/en/docs/event_handlers/ontester
  - https://www.mql5.com/en/docs/event_handlers/ontesterpass
  - https://www.mql5.com/en/docs/optimization_frames/frameadd
- Custom symbols:
  - https://www.mql5.com/en/docs/customsymbols/customsymbolcreate
  - https://www.mql5.com/en/docs/customsymbols/customratesreplace
  - https://www.mql5.com/en/docs/customsymbols/customticksreplace
  - https://www.mql5.com/en/book/advanced/custom_symbols
- ONNX:
  - https://www.mql5.com/en/docs/onnx/onnx_intro
  - https://www.mql5.com/en/docs/onnx/onnx_prepare
  - https://www.mql5.com/en/docs/onnx/onnx_mql5
  - https://www.mql5.com/en/docs/onnx/onnx_types_autoconversion
  - https://www.mql5.com/en/docs/onnx/onnxcreate

## Wnioski kluczowe dla naszego systemu

### 1. Strategy Tester jest natywnie wielosymbolowy

To jest bardzo wazne dla `MAKRO_I_MIKRO_BOT`.

Tester MetaTrader 5:

- potrafi testowac strategie wielosymbolowe
- sam przetwarza symbole uzywane przez strategie
- pobiera brakujaca historie przez terminal
- uzywa agentow obliczeniowych do równoleglego przetwarzania optymalizacji

Wniosek dla nas:

- nie powinnismy traktowac testera tylko jako jednosymbolowego kalkulatora
- powinnismy traktowac go jako wolniejsza, ale twarda warstwe walidacyjna
- laptopowy `Python/QDM/ML` powinien typowac, a tester powinien potwierdzac

### 2. Agenci testera sa osobna warstwa obliczeniowa

Z dokumentacji MetaTrader 5 wynika:

- lokalni agenci tworza sie automatycznie
- liczba lokalnych agentow odpowiada liczbie logicznych rdzeni
- zdalni agenci i osobny `metatester64.exe` sluza do rozproszenia testow i optymalizacji
- pojedynczy test zuzywa jeden agent

Wniosek dla nas:

- nie przyspieszymy kazdego pojedynczego przebiegu w nieskonczonosc
- ale mozemy lepiej planowac kolejke, paczki i kryteria
- wartosc daje lepsza preselekcja symboli, a nie bezmyslne odpalanie wszystkiego

### 3. Jest gotowy, natywny mechanizm do zbierania wynikow optymalizacji: `OnTester*` plus ramki

To jest jeden z najwazniejszych punktow calej analizy.

MetaQuotes przewiduje wprost:

- `OnTesterInit()` do przygotowania optymalizacji
- `OnTester()` do zwracania custom score
- `FrameAdd()` do zapisu dodatkowych danych z passa
- `OnTesterPass()` do odbioru ramek podczas optymalizacji
- `OnTesterDeinit()` do domkniecia i zebrania opoznionych ramek

Wniosek dla nas:

- dzisiaj za duzo rzeczy czytamy z logow i summary po fakcie
- powinnismy dobudowac natywny strumien telemetryczny testera:
  - custom criterion
  - bucket score
  - trust state
  - cost state
  - session score
  - wynik symbolu
- to pozwoli wprost karmic laptopowy research i `DuckDB`

### 4. Custom Symbols sa mocniejszym narzedziem niz dotad wykorzystywalismy

MetaTrader 5 i MQL5 daja:

- `CustomSymbolCreate()`
- `CustomRatesReplace()`
- `CustomTicksReplace()`
- sesje quote/trade dla custom symbolu

To jest dla nas bardzo wazne, bo mamy `QDM` i kupiona historie.

Wniosek dla nas:

- mozemy budowac lokalne, badawcze custom symbole karmione przez `QDM`
- mozemy testowac okna i warianty bez ryzyka mieszania tego z brokerowym live
- mozemy zbudowac:
  - symbol badawczy
  - symbol brokerski live
  - wspolny alias systemowy

Wazna granica z dokumentacji:

- przy custom symbols nie wolno uzywac `MQL5 Cloud Network`
- wolno uzywac lokalnych i zdalnych agentow

To pasuje do naszego modelu, bo i tak glowny research ma zyc na laptopie i w naszych agentach.

### 5. Market Watch ma znaczenie architektoniczne

Dokumentacja platformy podkresla:

- jesli symbol jest ukryty w `Market Watch`, jego dane nie sa dostepne dla programow MQL5 i Strategy Testera

Wniosek dla nas:

- pelna flota badawcza musi miec pewnosc widocznosci potrzebnych symboli
- przy multi-symbol EAs i przy custom cross-rates nie wolno polegac na przypadkowym stanie `Market Watch`

### 6. Python integration jest przewidziana dokladnie do tego, co robimy

Oficjalna dokumentacja MQL5 wprost mowi, ze pakiet `MetaTrader5` dla Pythona sluzy do:

- szybkiego pobierania danych przez IPC z terminala
- dalszych obliczen statystycznych
- machine learning

Kluczowe szczegoly:

- `initialize()` moze wskazac konkretny terminal EXE
- terminal moze byc uruchomiony automatycznie
- czasy w `copy_rates_from()` trzeba traktowac jako UTC
- dane sa ograniczone historia dostepna w terminalu i `Max bars in chart`

Wniosek dla nas:

- nasz split `laptop research runtime` vs `paper/live runtime` jest prawidlowy
- Python jest pelnoprawna warstwa systemu, nie obejsciem
- trzeba pilnowac:
  - wyboru terminala
  - UTC
  - swiezosci danych
  - zasiegu historii

### 7. ONNX ma byc inferencja, nie treningiem

Dokumentacja MQL5 jest tu bardzo jasna:

- model mozna zaladowac przez `OnnxCreate()` lub `OnnxCreateFromBuffer()`
- trzeba ustawic shapes przez `OnnxSetInputShape()` i `OnnxSetOutputShape()`
- potem robi sie `OnnxRun()`
- MQL5 ma automatyczna konwersje typow, ale tylko w granicach wspieranych typow

Wniosek dla nas:

- obecny kierunek jest dobry:
  - trening offline w Pythonie
  - eksport do ONNX
  - inferencja w MQL5 dopiero dla dojrzalego modelu
- nie nalezy przerzucac treningu do MQL5
- wejscia modelu pod MQL5 musza byc liczbowe i stabilne

### 8. Tester ma wlasne reguly pobierania historii

To tez jest wazne praktycznie.

MetaTrader 5 wskazuje, ze:

- tester pobiera historie przez terminal
- brakujace dane sa dogrywane
- pobierane sa tez dane sprzed zakresu testu, zeby zbudowac minimum historii do obliczen
- historia agentow ma wlasne katalogi

Wniosek dla nas:

- czesc pozornego "wolnego testu" wynika z pracy przygotowawczej na historii
- trzeba oddzielac:
  - koszt samego modelu / EA
  - koszt przygotowania historii
- dlatego `QDM` i custom symbol pipeline moga dac nam realna przewage

## Co to znaczy dla naszego systemu treningowego

### Warstwa laptopowa

Laptop powinien robic:

- szybki research calej floty
- `QDM -> parquet -> DuckDB -> ML`
- priorytetyzacje symboli
- 20-minutowe sloty nadzoru symbol po symbolu
- budowe kandydatow do walidacji w testerze
- generowanie modeli ONNX i raportow

### Warstwa testera MT5

Tester powinien robic:

- twarda walidacje zmian
- optymalizacje tylko dla sensownych kandydatow
- eksport ramek z `OnTester*`
- zapis pass-results do wiedzy lokalnej

### Warstwa paper/live

Paper/live powinny robic:

- runtime z oknami rodzinnymi
- tylko przypisane instrumenty maja prawo aktywnego handlu
- pozostale sa w `paper/shadow`
- local tuning agent i mikrobot zbieraja doswiadczenie rynkowe
- ten runtime nie powinien byc jednoczesnie laboratorium 24h dla calej floty

## Najwazniejsze procedury do wdrozenia

### A. Natywna telemetria testera przez `OnTester*`

To jest najwyzszy priorytet architektoniczny.

Minimalny wzorzec:

```mq5
double OnTester()
{
   double custom_score = ComputeSessionAwareScore();
   double payload[];
   ArrayResize(payload, 4);
   payload[0] = custom_score;
   payload[1] = LastTrustPenalty();
   payload[2] = LastCostPenalty();
   payload[3] = LastWindowScore();
   FrameAdd("MICROBOT_PASS", MagicNumber(), custom_score, payload);
   return custom_score;
}
```

Korzyść:

- zamiast tylko czytac log po tescie, od razu zbieramy standaryzowane ramki dla kazdego passa

### B. Custom symbols karmione przez `QDM`

Minimalny wzorzec:

```mq5
bool ok = CustomSymbolCreate("EURUSD_QDM", "Research\\Forex", "EURUSD.pro");
if(ok)
{
   CustomRatesReplace("EURUSD_QDM", from_time, to_time, rates_m1);
   CustomTicksReplace("EURUSD_QDM", from_msc, to_msc, ticks);
}
```

Korzyść:

- oddzielamy research od brokera
- mozemy testowac alternatywne okna, czystosc danych i inne warianty sesji

### C. Python jako warstwa uczenia i selekcji

Minimalny wzorzec:

```python
import MetaTrader5 as mt5
from datetime import datetime
import pytz

tz = pytz.timezone("Etc/UTC")
utc_from = datetime(2026, 3, 1, tzinfo=tz)

mt5.initialize(path=r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe")
rates = mt5.copy_rates_from("EURUSD.pro", mt5.TIMEFRAME_M5, utc_from, 5000)
mt5.shutdown()
```

Korzyść:

- laptop szybko zbiera material do `DuckDB` i `ML`
- nie czeka biernie na wolniejszy tester

### D. ONNX tylko jako gate/scorer

Minimalny wzorzec:

```mq5
long session = OnnxCreate("paper_gate_acceptor.onnx", ONNX_COMMON_FOLDER);
OnnxSetInputShape(session, 0, input_shape);
OnnxSetOutputShape(session, 0, output_shape);
if(OnnxRun(session, 0, input_tensor, output_tensor))
{
   double score = output_tensor[0];
}
OnnxRelease(session);
```

Korzyść:

- model z laptopa moze wejsc do MQL5 jako filtr
- nie zastępuje logiki mikrobota, tylko ja wzmacnia

## Najwazniejsze decyzje architektoniczne po lekturze

1. Nie przenosic treningu ML do MQL5.
2. Rozbudowac natywna telemetrie testera przez `OnTester*` i ramki.
3. Uzyc `QDM` do budowy custom symbols dla researchu.
4. Trzymac osobne runtime:
   - `LAPTOP_RESEARCH`
   - `PAPER_LIVE`
5. W `PAPER_LIVE` handluja tylko rodziny przypisane do okna.
6. Poza oknem symbole zostaja w `paper/shadow`, a nie w pelnym live.
7. ONNX wdrazac dopiero jako liczbowy gate dla dojrzalego modelu.

## Najblizszy backlog techniczny

### Etap 1

- dodac `OnTesterInit/OnTester/OnTesterPass/OnTesterDeinit` do wspolnej warstwy mikrobotow
- zapis ramek do jednolitego formatu pass-results

### Etap 2

- zbudowac `QDM -> custom symbol` dla calej floty 17
- dopiac sesje trade/quote dla symboli badawczych

### Etap 3

- zasilic `DuckDB` nie tylko logami runtime, ale tez ramkami z testera
- powiazac to z kolejka 20-minutowego researchu

### Etap 4

- wdrozyc pierwszy prosty model ONNX jako gate `candidate -> paper`
- tylko dla czysto liczbowych cech

### Etap 5

- polaczyc wyniki testera, QDM, laptopowego ML i paper/live w jeden operator report

## Koncowy werdykt

Najwazniejsze odkrycie z tych "ksiazek" nie jest egzotyczne, tylko bardzo praktyczne:

- MetaTrader 5 i MQL5 juz maja natywne mechanizmy, ktorych my jeszcze nie wykorzystujemy do konca
- szczegolnie:
  - `OnTester*`
  - `FrameAdd`
  - `Custom Symbols`
  - `Python Integration`
  - `ONNX inference`

To oznacza, ze nie musimy budowac wszystkiego wokol testera i logow od zera. Duza czesc potrzebnego systemu jest juz przewidziana przez platforme. Nasza praca polega teraz na tym, zeby te mechanizmy dobrze zlozyc pod wlasny workflow: `QDM + laptop + MT5 tester + paper/live`.
