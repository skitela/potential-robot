# Chirurgiczne wsparcie runtime dla GBPUSD, USDCHF, DE30 i PLATIN

Data: 2026-03-16

## Cel
- ograniczyc brudne kandydatury, ktore tylko zapychaly papier i majtkow
- poprawic konwersje kandydat -> papierowa lekcja tam, gdzie bylo to uzasadnione genotypem
- skrocic papierowe przetrzymywanie w setupach, ktore konczyly sie glownie timeoutem i strata

## GBPUSD
- breakouty w chaosie z marna swieca zostaly dodatkowo przyciete juz na bramce papierowej
- trend i pullback dostaly lekkie pierwszenstwo tylko wtedy, gdy sygnal jest mocny i czysty
- dodano paperowy ratunek dla mocnego sygnalu trend/pullback przy blokadzie kontraktu ryzyka
- czas trzymania breakoutu na papierze zostal skrocony

## USDCHF
- breakouty oparte o slaba swiece i slaby renko zostaly mocniej blokowane
- dodano brakujace odblokowanie paperowe dla minimalnego lota
- dodano ratunek dla silnego sygnalu trendowego, gdy blokada ryzyka zabierala papierowa lekcje
- czas trzymania breakoutu na papierze zostal skrocony

## DE30
- pullback w chaosie z marna swieca lub renko zostal zablokowany
- range w trendzie i w chaosie z niska pewnoscia i slabym materialem zostal przyciety
- breakout z marna swieca dostal wyzszy prog przejscia do papieru
- czas trzymania range i breakoutu na papierze zostal skrocony

## PLATIN
- breakout z marna swieca i zbyt slaba jakoscia potwierdzenia dostal twardszy filtr
- range w chaosie z niska pewnoscia przestal przechodzic do papieru
- breakout z kiepska swieca dostal wyzszy prog wejscia do papieru
- czas trzymania breakoutu i range na papierze zostal skrocony

## Weryfikacja po wdrozeniu
- kompilacja floty: 17/17 OK
- lokalny MT5 odswiezony na profilu `MAKRO_I_MIKRO_BOT_AUTO`
- po restarcie:
  - `USDCHF` dalej potrafi otwierac papierowe pozycje trendowe
  - `DE30` po dodatkowym doszczelnieniu zaczal odrzucac slabe range w chaosie juz na etapie `SCORE_BELOW_TRIGGER`
  - `PLATIN` po doszczelnieniu przestal przepuszczac slabe range do arbitrazu i zostawia je na etapie `SCORE_BELOW_TRIGGER`

## Najwazniejszy uczciwy wniosek
- `USDCHF` pokazal realna poprawe konwersji
- `DE30` i `PLATIN` pokazaly realna poprawe czyszczenia przedpola
- `GBPUSD` ma juz lepsze sito w kodzie, ale potrzebuje kolejnego cyklu rynku, zeby zostawic nowy runtimeowy slad
