# 76. First Hour Reopen Playbook INDICES

## Cel

Pierwsza godzina aktywnego okna dla `INDICES` ma sluzyc sprawdzeniu, czy nowa domena
zachowuje sie spokojnie pod wspolnym koordynatorem sesji i kapitalu oraz czy
`DE30.pro` i `US500.pro` zaczynaja zbierac czysty material do dalszego strojenia.

To nie jest godzina odwagi. To jest godzina potwierdzenia, ze indeksy weszly do
organizmu bez chaosu, bez regresji latencji i bez brudnych logow.

## Co zostawiamy nieruszone

W pierwszej godzinie aktywnego okna dla `INDICES` nie robimy:

- zmian w kodzie,
- recznego luzowania `INDEX_EU` albo `INDEX_US`,
- recznego ruszania koordynatora floty,
- recznego podnoszenia `risk_cap` albo `confidence_cap`,
- recznego zdejmowania `freeze_new_changes`,
- recznego przechodzenia z `paper` do `live` po pojedynczym dobrym sygnale,
- nowych porzadkow runtime, jesli nie ma realnej korupcji danych.

## Co obserwujemy

W pierwszej godzinie aktywnego okna obserwujemy:

- pierwsze rekordy `candidate_signals.csv`,
- pierwsze rekordy `learning_observations_v2.csv`,
- pierwsze `PAPER_OPEN` i `PAPER_CLOSE`,
- przewage `PAPER_TIMEOUT` kontra `PAPER_SL`,
- rozklad `spread_regime`, `execution_regime` i `market_regime`,
- skuteczna polityke `tuning_policy_effective.csv`,
- to, czy `INDEX_EU` i `INDEX_US` pozostaja w uczciwym trybie zamrozonego strojenia,
- czy lokalne filtry breakout i trendlike nie wpuszczaja od razu najgorszych klas.

## Jak interpretujemy pierwsza godzine

`DE30.pro` ma pokazywac przede wszystkim spokojny noon-cash rytm:

- mniej slepego breakoutu bez struktury,
- brak natychmiastowego chaosu przy przejsciu przez europejskie poludnie,
- sensowny przeplyw kandydatow nawet wtedy, gdy nie pojawi sie od razu trade.

`US500.pro` ma pokazywac przede wszystkim dyscypline przy oknie amerykanskim:

- brak nadmiernie pewnego breakoutu na samym otwarciu,
- brak agresywnego powrotu do live bez danych,
- stabilna telemetrie execution i spreadu.

Poniewaz indeksy startuja bez probki lokalnej, dobrym wynikiem jest juz:

- czysty runtime,
- logiczny przeplyw kandydatow,
- brak szumu w hierarchii,
- oraz pierwsze dane do uczenia.

## Kiedy wolno interweniowac

Interwencja w pierwszej godzinie jest uzasadniona tylko wtedy, gdy wystapi jedno z ponizszych:

- runtime nie aktualizuje sie mimo aktywnego rynku,
- journale maja uszkodzony schemat,
- skuteczna polityka strojenia ma stan oczywiscie sprzeczny z konfiguracja,
- execution pokazuje twarda serie awarii technicznych,
- koordynator domenowy zle budzi lub usypia `INDICES`.

## Co bedzie oznaka dobrego startu

Dobry start dla `INDICES` to:

- czyste logi,
- aktywny runtime domeny,
- sensowny przeplyw kandydatow,
- brak regresji latencji,
- brak agresywnego lokalnego strojenia przy `trusted_data = 0`,
- pierwsze rekordy, ktore pozwola agentowi strojenia przestac pracowac w ciszy.

## Zakres

Ten playbook dotyczy:

- `DE30.pro`
- `US500.pro`

oraz ich rodzin:

- `INDEX_EU`
- `INDEX_US`
