# 97_EURUSD_FOREX_DOCTRINE_FOR_TUNING_AGENT_V1

## Cel

Rozwinac agenta strojenia `EURUSD` tak, aby nie stroil sie tylko na liczbach, ale rozumial podstawowe zasady mikrostruktury rynku walutowego.

To znaczy:

- rozroznial cienka plynnosc od rdzenia rynku,
- rozumial okna przejsciowe i rollover,
- wiedzial, kiedy nowe eksperymenty sa uczciwe poznawczo,
- a kiedy trzeba obserwowac, ale nie zaczynac nowej polityki.

## Co zostalo dodane

Dodano osobna warstwe wiedzy:

- `MbForexDoctrineEURUSD.mqh`

Ta warstwa rozpoznaje fazy rynku:

- `ROLLOVER_RISK`
- `ASIA_THIN`
- `PRE_LONDON`
- `EUROPE_OPEN`
- `FX_MAIN_CORE`
- `POST_CORE`
- `US_OVERLAP`
- `NY_LATE`
- `OFF_CORE`

## Czego ta doktryna uczy EURUSD

### 1. Cienka plynnosc nie nadaje sie do nowych eksperymentow

W fazach:

- rollover,
- nocna cienka plynnosc,
- poza rdzeniem rynku,

agent:

- nie zaczyna nowego eksperymentu strojenia,
- mocniej karze breakout i trend,
- obcina zaufanie do wyniku takiej lekcji.

### 2. Okna przejsciowe sa wartosciowe obserwacyjnie, ale nie sa idealne do strojenia

W fazach:

- przed Europa,
- po glownym oknie,
- pozny Nowy Jork,

agent:

- moze dalej obserwowac i uczyc sie z naplywu,
- ale nie powinien rozpoczynac nowej polityki,
- bo zbyt latwo pomylic przejsciowy szum z prawdziwa przewaga.

### 3. Rdzen plynnosci EURUSD jest najlepszym polem do nauki

W fazach:

- `FX_MAIN_CORE`
- `US_OVERLAP`

agent dostaje najlepsze warunki do:

- nowych eksperymentow,
- oceny breakoutow i trendow,
- budowania uczciwej pamieci skutkow.

### 4. Rollover jest traktowany twardo

W strategii `EURUSD` doktryna moze zablokowac breakout / trend / pullback podczas rollover.

To jest celowe:

- paper ma zbierac lekcje,
- ale nie z najbardziej brudnego momentu doby.

## Gdzie to zostalo wpiete

### Strategia EURUSD

Doktryna nie jest tylko etykieta.

W `Strategy_EURUSD`:

- dodaje podatek dla breakoutu, trendu i odrzucenia zależnie od fazy rynku forex,
- przycina `confidence` i `risk`,
- blokuje najbardziej toksyczne wejscia przy rollover.

### Agent strojenia EURUSD

W `MbTuningLocalAgent`:

- przy starcie nowego eksperymentu agent sprawdza, czy faza rynku forex daje uczciwe pole do nauki,
- jesli nie, nie startuje eksperymentu,
- zapisuje rozumowanie i czeka na lepsze okno.

## Co juz zostalo potwierdzone

- Kod skompilowal sie `17/17`.
- Lokalny MT5 zostal odswiezony.
- Strategia i agent pracuja na nowym buildzie.

## Czego jeszcze uczciwie trzeba dopilnowac

Warstwa `FOREX_DOCTRINE_WAIT` uruchomi sie w pelni przy kolejnym nowym starcie eksperymentu poza rdzeniem `EURUSD`.

Czyli:

- doktryna jest juz aktywna,
- ale pierwszy zywy wpis „poczekaj na czystszy forex” pojawi sie dopiero wtedy, gdy agent bedzie chcial rozpoczac nowy eksperyment w gorszym oknie.
