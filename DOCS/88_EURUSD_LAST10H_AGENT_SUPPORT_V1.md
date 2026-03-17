# EURUSD Last-10h Agent Support v1

## Cel
Przejrzec zachowanie `EURUSD` na ostatnich ~10 godzinach pracy paperowej i usunac te bariery, ktore psuly material dla lokalnego agenta strojenia.

## Co wyszlo z analizy
- Swieze kandydaty pojawialy sie masowo, ale prawie wszystkie konczyly sie na `RISK_CONTRACT_BLOCK`.
- W ostatnim badanym wycinku nie bylo praktycznie nowych `PAPER_OPEN` ani `PAPER_CLOSE`, wiec agent nie dostawal nowych, domknietych lekcji.
- Dominujacy szum w kandydaturach papierowych to:
  - `SETUP_TREND` w `CHAOS` z `POOR/POOR`
  - `SETUP_PULLBACK` w `CHAOS` z `POOR/POOR`
  - `SETUP_BREAKOUT` w `TREND` lub `CHAOS` z bardzo slaba swieca
- Journal incydentow byl zasypywany `BROKER_PRICE_RATE_LIMIT`, mimo ze w paper runtime sam tick nie powinien byc traktowany jak prawdziwe pytanie do brokera.

## Wdrozone poprawki
- W `EURUSD` podniesiono paperowy prog wejscia dla najbardziej zaszumionych ukladów `poor/poor`, zeby agent nie uczył sie na najgorszym smieciu.
- W paper runtime dodano ratunkowa podloge minimalnego lota, gdy po zastosowaniu mnoznika ryzyka lot spadal ponizej minimum brokera.
- W paper runtime wylaczono naliczanie pasywnych tickow jako `price probe`, co przestalo sztucznie odpalac `BROKER_PRICE_RATE_LIMIT`.
- Paper gate przestal wskrzeszac sygnaly, ktore twarde filtry strojenia juz uznaly za zbyt slabe (na przyklad trend na slabej swiecy).

## Pierwszy efekt po wdrozeniu
- Po kompilacji i restarcie lokalnego MT5 `EURUSD` otworzyl swieza pozycje `PAPER_OPEN`.
- W kandydaturach pojawil sie pierwszy wpis `PAPER_POSITION_OPENED`.
- Journal incydentow przestal sie dopisywac po restarcie, co potwierdza, ze lokalna poprawka uciszyla falszywy rate-limit dla paper.
- Po kolejnym dopieciu paper gate mechanizm jest juz wdrozony, ale czeka jeszcze na nastepny swiezy cykl runtime, zeby zostawic nowy sladowy dowod w logach.

## Wniosek
Najwazniejsza poprawka nie dotyczyla "magicznego nowego filtra", tylko odetkania nauki:
- mniej brudnego szumu na wejsciu,
- mniej falszywego dlawienia przez rate guard,
- wiecej realnych, domknietych przykladow dla agenta strojenia.
