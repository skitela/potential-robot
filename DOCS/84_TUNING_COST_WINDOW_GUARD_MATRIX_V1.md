# 84. Tuning Cost Window Guard Matrix V1

## Cel

Ta matryca nie sluzy do prognozowania zysku.

Jej cel jest prostszy i wazniejszy:

- dac agentowi strojenia mape min kosztowych i okiennych,
- zmniejszyc liczbe wejsc, ktore gasna zaraz po otwarciu,
- zabronic live tam, gdzie rodzina lub okno nie daje uczciwego czasu na rozwoj scalpingu,
- wymusic defensywe zanim instrument "dostanie w leb" od spreadu, poślizgu albo konca okna.

To jest warstwa pomocnicza dla:

- lokalnego agenta strojenia,
- agenta rodzinnego,
- koordynatora sesji i kapitalu.

Nie zmienia ona niezmienialnego kontraktu ryzyka.
Moze tylko pomagac go respektowac szybciej i madrzej.

## Zasady wspolne

### Twarde

- brak nowego live poza oknem `TRADE`
- brak nowego live w `OBSERVATION_ONLY`
- brak nowego live w `SHADOW`
- brak nowego live w `FUTURE_RESEARCH`
- brak nowego live w `CLOSE_ONLY`
- brak nowego live w ostatniej czesci glownego okna, jesli rodzina ma wysokie ryzyko szybkiego zgaszenia
- agent moze tylko:
  - podniesc wymagana pewnosc wejscia
  - obciac `risk_cap`
  - przesunac rodzine lub symbol do `PAPER_ACTIVE`
  - przesunac rodzine lub symbol do `PAPER_SHADOW`

### Miekkie

- przy rosnacej presji kosztu agent podnosi prog pewnosci, zanim ruszy `risk_cap`
- przy slabym czasie do konca okna agent najpierw blokuje nowe wejscia, a dopiero potem analizuje dalsze strojenie
- przy wysokiej presji kosztu i wysokim ryzyku szybkiego zgaszenia agent preferuje `paper`, nawet jesli lokalny sygnal wyglada dobrze

## Slownik roboczy

- `presja_kosztu`
  - `NISKA`
  - `SREDNIA`
  - `WYSOKA`
- `ryzyko_szybkiego_zgaszenia`
  - jak latwo trade moze zostac zamkniety bez dojrzalego ruchu zaraz po otwarciu
- `min_oddech`
  - minimalny uczciwy ruch po wejsciu, ktory musi pojawic sie szybko, aby scalp nie byl tylko ofiara kosztu
- `ostatnie_minuty_blokady`
  - ile minut przed koncem glownego okna nie otwierac juz nowego live

## Matryca rodzin

### FX_MAIN

- rodzina:
  - `EURUSD`
  - `GBPUSD`
  - `USDCAD`
  - `USDCHF`
- glowne okno:
  - `09:00-12:00` PL
- presja_kosztu:
  - `NISKA` do `SREDNIA`
- ryzyko_szybkiego_zgaszenia:
  - `SREDNIE`
- min_oddech:
  - `NISKI`
- ostatnie_minuty_blokady:
  - `15`
- zachowanie agenta:
  - bazowa rodzina do normalnego live paper-learning
  - najpierw podnosi pewnosc dla slabego `TREND` i slabego `BREAKOUT`
  - ryzyko tnie dopiero po powtarzalnym szumie, nie po pojedynczym slabszym sygnale
- rekomendacja:
  - `LIVE` tylko w `TRADE`
  - `PREWARM` i wszystko poza core = `PAPER_ONLY`

### FX_ASIA

- rodzina:
  - `USDJPY`
  - `AUDUSD`
  - `NZDUSD`
- glowne okno:
  - `01:00-08:00` PL zima
  - `02:00-09:00` PL lato
- presja_kosztu:
  - `SREDNIA`
- ryzyko_szybkiego_zgaszenia:
  - `SREDNIO_WYSOKIE`
- min_oddech:
  - `SREDNI`
- ostatnie_minuty_blokady:
  - `20`
- zachowanie agenta:
  - mocniej karze slaby ruch i brak czystosci po wejsciu
  - szybciej schodzi do defensywy przy szarpanym rynku
  - nowy live blisko europejskiego przekazania okna powinien byc ograniczony
- rekomendacja:
  - `LIVE` tylko w rdzeniu okna
  - koncowka azjatycka blizej Europy ma byc bardziej defensywna

### FX_CROSS

- rodzina:
  - `EURJPY`
  - `GBPJPY`
  - `EURAUD`
  - `GBPAUD`
- glowne okno:
  - rodzina aktywna we wlasnym rdzeniu poranka europejskiego
- presja_kosztu:
  - `WYSOKA`
- ryzyko_szybkiego_zgaszenia:
  - `WYSOKIE`
- min_oddech:
  - `SREDNIO_WYSOKI`
- ostatnie_minuty_blokady:
  - `25`
- zachowanie agenta:
  - to nie jest rodzina do szerokiego wpuszczania sygnalow
  - mocny podatek dla slabszych `BREAKOUT`
  - szybciej obcina `risk_cap`
  - przy near-tie prawie zawsze ma przegrac z lepszym kandydatem z tanszej rodziny, jesli oba sa tylko "poprawne"
- rekomendacja:
  - `LIVE` tylko dla najwyzszej jakosci kandydatow
  - wszystko graniczne ma spadac do `paper`

### METALS_SPOT_PM

- rodzina:
  - `GOLD`
  - `SILVER`
- glowne okno:
  - `14:00-17:00` PL
- presja_kosztu:
  - `SREDNIA` do `WYSOKIEJ`
- ryzyko_szybkiego_zgaszenia:
  - `SREDNIE`
- min_oddech:
  - `SREDNIO_WYSOKI`
- ostatnie_minuty_blokady:
  - `20`
- zachowanie agenta:
  - moze pozwolic na live tylko wtedy, gdy ruch jest juz zywy i czysty
  - pierwszy impuls po dogrzaniu ma byc traktowany ostroznie
  - po `17:00` tylko `SHADOW`, bez nowych live
- rekomendacja:
  - `PREWARM 13:45-14:00` = `PAPER_ONLY`
  - `14:00-17:00` = warunkowy `LIVE`
  - `17:00-19:00` = tylko `OBSERVATION_ONLY`

### METALS_FUTURES

- rodzina:
  - `PLATIN`
  - `COPPERUS`
- glowne okno:
  - `14:00-17:00` PL
- presja_kosztu:
  - `WYSOKA`
- ryzyko_szybkiego_zgaszenia:
  - `WYSOKIE`
- min_oddech:
  - `WYSOKI`
- ostatnie_minuty_blokady:
  - `25`
- zachowanie agenta:
  - duzo szybciej ucina ryzyko niz w `FX_MAIN`
  - wymaga wyzszej pewnosci i bardziej zywego rynku
  - nie powinien wpuszczac "prawie dobrych" scalpow tylko dlatego, ze jest okno metali
- rekomendacja:
  - `LIVE` tylko po przejsciu ostrzejszych bramek
  - kazdy slaby kandydat ma spadac do `paper`

### INDEX_EU

- rodzina:
  - `DE30`
- glowne okno:
  - `12:00-14:00` PL
- presja_kosztu:
  - `SREDNIA`
- ryzyko_szybkiego_zgaszenia:
  - `SREDNIO_WYSOKIE`
- min_oddech:
  - `SREDNI`
- ostatnie_minuty_blokady:
  - `15`
- zachowanie agenta:
  - rodzina jeszcze mloda runtime, wiec agent ma byc bardziej badaczem niz bohaterem
  - alternatywne szczyty pozostaja `FUTURE_RESEARCH`
  - bazowy tryb to ostrozny `paper-first`
- rekomendacja:
  - `LIVE` dopiero po dojrzeniu runtime
  - na teraz okno jest glownie do spokojnej obserwacji i strojenia

### INDEX_US

- rodzina:
  - `US500`
- glowne okno:
  - `17:00-20:00` PL
- presja_kosztu:
  - `SREDNIA` do `WYSOKIEJ`
- ryzyko_szybkiego_zgaszenia:
  - `WYSOKIE`
- min_oddech:
  - `SREDNIO_WYSOKI`
- ostatnie_minuty_blokady:
  - `20`
- zachowanie agenta:
  - rodzina moze byc atrakcyjna ruchowo, ale agent ma unikac szarpania zaraz po zmianach impulsu
  - preferowany jest czysty zwyciezca rodziny, nie kilka poprawnych kandydatow
  - silny nacisk na defensywe przy slabych warunkach wykonania
- rekomendacja:
  - `LIVE` tylko dla wyraznego zwyciezcy rodziny i czystego cost/execution
  - slaby near-tie ma konczyc sie `skip`, nie wymuszonym trade

## Proste reguly dla agenta strojenia

### Gdy presja_kosztu = NISKA

- podniesienie pewnosci:
  - `+0.00 do +0.03`
- wstepne ciecie `risk_cap`:
  - `1.00 do 0.90`

### Gdy presja_kosztu = SREDNIA

- podniesienie pewnosci:
  - `+0.03 do +0.08`
- wstepne ciecie `risk_cap`:
  - `0.90 do 0.80`

### Gdy presja_kosztu = WYSOKA

- podniesienie pewnosci:
  - `+0.08 do +0.15`
- wstepne ciecie `risk_cap`:
  - `0.80 do 0.65`
- preferowany skutek:
  - `paper`
  - albo `skip`

## Gdzie to podpinac

Ta matryca powinna byc czytana:

- przez lokalnego agenta strojenia jako warstwa domyslnej ostroznosci
- przez agenta rodzinnego jako mapa preferencji okna i kosztu
- przez koordynatora sesji jako uzasadnienie:
  - `RUN`
  - `CLOSE_ONLY`
  - `PAPER_ACTIVE`
  - `PAPER_SHADOW`

Nie powinna siedziec w hot-path ticka jako ciezki kalkulator.
Powinna byc lekka i interpretacyjna.

## Najwazniejszy sens

To nie jest narzedzie do "wyciagania wiekszego zysku z niczego".

To jest narzedzie, ktore ma sprawic, ze agent strojenia:

- rzadziej otworzy scalp bez miejsca na oddech
- rzadziej wejdzie tuz przed smiercia okna
- rzadziej przegra z kosztem, zanim rynek zdazy sie ruszyc
- i czesciej wybierze `paper` zamiast durnego heroizmu
