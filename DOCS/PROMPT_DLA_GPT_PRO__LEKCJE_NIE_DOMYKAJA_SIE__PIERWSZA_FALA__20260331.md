# Problem do analizy: lekcje nie domykają się w pierwszej fali, mimo że laboratorium i diagnostyka zostały już częściowo naprawione

## Cel
Pracujemy nad systemem krótkiego handlu w `MT5` dla czterech najbardziej zaawansowanych instrumentów:

- `US500`
- `EURJPY`
- `AUDUSD`
- `USDCAD`

Chcemy doprowadzić system do stanu, w którym:

- obserwacja rynku przechodzi w kandydata,
- kandydat przechodzi w sprawdzenie przed wysłaniem zlecenia,
- sprawdzenie przechodzi w próbne otwarcie,
- próbne otwarcie przechodzi w próbne zamknięcie,
- a po zamknięciu powstaje pełna lekcja i wiedza odkłada się do dalszego uczenia.

Najważniejszy obecny problem brzmi:

**system żyje obserwacyjnie, ale lekcje nadal się nie domykają, a prawda po wykonaniu nie wraca do pełnego łańcucha nauki.**

## Co już naprawiliśmy

W ostatniej serii prac udało się usunąć kilka bardzo istotnych problemów infrastrukturalnych.

### 1. Laboratorium przenośne było uruchamiane w sposób, który mieszał zwykłą pracę z przebiegami testera

Objaw:

- ten sam terminal bywał używany zarówno do laboratorium uczenia, jak i do przebiegów testowych,
- przez to część zachowania wyglądała jakby roboty działały, a część jakby terminal był przejęty przez testera.

Naprawa:

- poprawiono wykrywanie i uruchamianie przenośnego laboratorium,
- dołożono osobny skrypt otwierający laboratorium z profilem robotów.

### 2. Laboratorium było przygotowywane poprawnie, ale świeżo skompilowane pliki były nadpisywane starszymi plikami wykonawczymi

Objaw:

- kompilacja kończyła się powodzeniem,
- ale po przygotowaniu laboratorium do katalogu przenośnego wracały starsze pliki wykonawcze,
- przez to nowe poprawki w kodzie nie wchodziły naprawdę do działającego środowiska.

Naprawa:

- skrypt przygotowania laboratorium został poprawiony tak, aby przy pełnej kompilacji nie nadpisywać świeżo zbudowanych plików starszymi wersjami.

### 3. Potwierdziliśmy, że świeże roboty są ładowane do laboratorium

Mamy już dowód, że po poprawkach:

- laboratorium uruchamia się z profilem robotów,
- cztery roboty ładują się poprawnie,
- świeże pliki wykonawcze trafiają do laboratorium,
- wymuszony przebieg diagnostyczny zaczął pojawiać się w logach dla całej czwórki.

Najważniejszy sygnał diagnostyczny, który zaczął się pojawiać:

- `DIAGNOSTIC FORCE TIMER_FALLBACK_SCAN`

To oznacza, że przynajmniej część toru wymuszonego skanowania naprawdę ożyła.

## Co nadal nie działa

Mimo powyższych napraw nadal nie osiągamy głównego celu.

### 1. Brak pełnego przejścia od obserwacji do lekcji

Po najnowszych poprawkach nadal widzimy:

- brak świeżych `SCAN` prowadzących do dalszego łańcucha,
- brak świeżych `EXEC_PRECHECK`,
- brak świeżych `PAPER_OPEN`,
- brak świeżych `PAPER_CLOSE`,
- brak nowych wierszy w prawdzie wykonania,
- brak nowych domkniętych lekcji.

### 2. Tylko część diagnostyki żyje, ale nie przechodzi w pełny tor wykonawczy

Na dziś mamy stan typu:

- obserwacje modelowe są świeże,
- logi decyzji są świeże,
- wymuszona diagnostyka potrafi się ujawnić,
- ale łańcuch nauki kończy się przed kandydatem albo przed pełnym sprawdzeniem.

### 3. Bardzo prawdopodobny obecny wąski gardło

Najmocniejsza hipoteza po naszej stronie jest taka:

- logika strategii dla części instrumentów zbyt często zwraca `setup_type == "NONE"`,
- albo istnieje wcześniejsza ścieżka wyjścia z logiki, zanim powstanie kandydat, sprawdzenie przed wysłaniem lub próbne otwarcie,
- przez to system wygląda jakby żył, ale nie przechodzi do pełnej nauki.

Dołożyliśmy już dodatkowe logowanie, które ma sygnalizować przypadek:

- `DIAGNOSTIC`
- `SKIP`
- `NO_SETUP_<powód>`

ale jeszcze nie mamy pewności, czy to jest jedyny problem, czy tylko jedna z warstw problemu.

## Aktualny obraz stanu

Najważniejsze obserwacje po ostatniej serii napraw:

- dla całej czwórki pojawia się wymuszony sygnał diagnostyczny,
- warstwa laboratorium jest znacznie stabilniejsza niż wcześniej,
- nadal:
  - `fresh_paper_open_count = 0`
  - `total_execution_truth_rows = 0`
  - `tuning_freeze_count = 3`
- dobrostan nauki nadal zgłasza brak domykania lekcji pierwszej fali mimo aktywnej obserwacji.

To dla nas oznacza:

- infrastruktura nie jest już głównym problemem,
- główny problem leży teraz najpewniej w samym torze logiki decyzyjnej, selekcji ustawień, warunkach przejścia do kandydata albo w zapisie po wykonaniu.

## O co prosimy

Prosimy o bardzo konkretną analizę techniczną i wskazanie najbardziej prawdopodobnego źródła problemu.

Interesują nas szczególnie odpowiedzi na poniższe pytania.

### Pytanie 1

Dlaczego po uruchomieniu wymuszonego skanowania diagnostycznego nadal nie dochodzimy stabilnie do:

- kandydata,
- sprawdzenia przed wysłaniem,
- próbnego otwarcia,
- próbnego zamknięcia,
- lekcji?

### Pytanie 2

Czy główna blokada leży najpewniej tutaj:

- strategia zbyt często zwraca `setup_type == "NONE"`,
- blokady strojenia zatrzymują przejście z obserwacji do kandydata,
- zapis prawdy po wykonaniu nie domyka się po drodze,
- czy problem jest rozłożony na więcej niż jedną warstwę?

### Pytanie 3

Jakie minimalne, ale skuteczne zmiany w kodzie proponujesz, aby:

- nie rozwalić bezpieczeństwa systemu,
- a jednocześnie doprowadzić pierwszą falę do pierwszych stabilnie domkniętych lekcji?

### Pytanie 4

Jak najlepiej przeinstrumentować ten tor, abyśmy wprost widzieli, na którym etapie łańcuch się urywa:

- obserwacja,
- kandydat,
- sprawdzenie przed wysłaniem,
- otwarcie,
- zamknięcie,
- lekcja,
- zapis wiedzy?

### Pytanie 5

Czy zaproponowałbyś inną, prostszą i bardziej niezawodną architekturę tego przepływu dla pierwszej fali, tak aby:

- lekcje domykały się regularnie,
- wiedza odkładała się po każdym zwycięskim i przegranym przebiegu,
- a dobrostan i nadzór mogły to jednoznacznie walidować?

## Oczekiwany typ odpowiedzi

Najbardziej przydatna będzie odpowiedź w tej formie:

1. najbardziej prawdopodobna przyczyna główna,
2. przyczyny wtórne,
3. konkretne miejsca w kodzie, które należy zmienić,
4. minimalny plan naprawczy krok po kroku,
5. sposób walidacji po każdej zmianie,
6. sygnały, po których poznamy, że lekcje naprawdę zaczęły się domykać.

## Dołączone pliki

Ze względu na ograniczenie wejścia do maksymalnie 10 plików dołączamy tylko najważniejsze pliki:

1. ten prompt,
2. `MicroBot_US500.mq5`,
3. `MicroBot_EURJPY.mq5`,
4. `MicroBot_AUDUSD.mq5`,
5. `MicroBot_USDCAD.mq5`,
6. `MbFirstWaveTruthDiagnostic.mqh`,
7. `MbTuningDeckhand.mqh`,
8. `setup_mt5_microbots_profile.py`,
9. `PREPARE_NEAR_PROFIT_PORTABLE_LAB.ps1`,
10. `SET_FIRST_WAVE_TRUTH_DIAGNOSTIC_MODE.ps1`.

Dobór jest celowy:

- cztery roboty pokazują realną logikę pierwszej fali,
- dwa pliki `mqh` pokazują diagnostykę i strojenie,
- jeden skrypt pokazuje przygotowanie laboratorium, a drugi aktywację trybu diagnostycznego dla pierwszej fali,
- a ten prompt niesie pełny opis problemu i historię napraw.
