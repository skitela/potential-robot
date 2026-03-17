# 55. Candidate Signal Journal V1

## Cel

System ma widziec nie tylko krew z zamknietych, przegranych wejsc, ale tez kandydatow, ktorzy:

- zostali odrzuceni przez score gate,
- utkneli na rozmiarze lub margin guard,
- odpadli na precheck,
- przeszli do paper lub live.

Ten journal jest pierwszym brakujacym ogniwem pomiedzy analiza zamknietych trade'ow a analiza utraconych okazji.

## Zakres wdrozenia

Wersja `v1` zostala wpieta do siedmiu mikro-botow, ktore sa juz objete hierarchia strojenia:

- `EURUSD`
- `GBPUSD`
- `USDCAD`
- `USDCHF`
- `USDJPY`
- `AUDUSD`
- `NZDUSD`

## Co zapisuje

Journal `candidate_signals.csv` zapisuje dla kazdego realnego kandydata:

- etap (`EVALUATED`, `SIZE_BLOCK`, `PRECHECK_BLOCK`, `PAPER_OPEN`, `EXEC_SEND_OK`, `EXEC_SEND_ERROR`),
- czy kandydat zostal zaakceptowany na danym etapie,
- powod decyzji,
- setup, score, confidence, risk multiplier,
- kontekst rynku, spreadu i execution,
- sygnaly swiecowe i `Renko`,
- wolumen i spread punktowy.

## Zasady projektowe

- journal jest lekki i kolejkuje wpisy podobnie do `decision_events.csv`,
- nie siedzi w `OnTimer`, tylko w naturalnych punktach przebiegu decyzji,
- nie zastępuje `decision_events.csv`, tylko go uzupelnia,
- nie probuje jeszcze orzekać, czy odrzucony kandydat bylby finalnie wygrany; daje material do takiej analizy offline.

## Znaczenie dla strojenia

To rozszerzenie daje agentom strojenia nowy rodzaj pytania:

- nie tylko `co przegralo`,
- ale tez `co zostalo odrzucone i dlaczego`.

Bez tego lokalny kapitan byl dobry glownie w obronie. Z tym journalingiem zaczyna dostawac wzrok takze na utracona przewage.
