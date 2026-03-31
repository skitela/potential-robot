# Raport: instrumenty realnie uczące się

Stan oceniony na podstawie bezpośrednich śladów nauki w zwykłym lokalnym torze
`Common Files`, nie na podstawie samych obserwacji modelu.

## Kryterium

Instrument uznajemy za **realnie uczący się**, jeśli spełnia łącznie:

1. ma świeży zapis lekcji w `learning_observations_v2.csv`,
2. ma świeży zapis wiedzy w `broker_net_ledger_runtime.csv`,
3. dla pierwszej fali ma też świeży ślad wykonania w `execution_truth`,
4. świeżość liczymy praktycznie w krótkim oknie operacyjnym, około 30 minut.

Sama aktywność w `decision_events.csv` albo same obserwacje modelu nie wystarczają.

## Wynik

### Uczy się teraz naprawdę

- `US500`

Powód:
- świeży zapis lekcji,
- świeży zapis wiedzy,
- świeży ślad wykonania,
- świeży pełny łańcuch domknięcia w zwykłym lokalnym torze.

### Uczył się dziś naprawdę, ale nie jest już świeży w bieżącym oknie

- `EURJPY`

Powód:
- ma dzisiejszy pełny łańcuch,
- ma zapis lekcji i wiedzy,
- ale jego ostatnie domknięcie wypadło już poza krótkie okno operacyjne.

### Nie uczą się teraz naprawdę

- `AUDUSD`
- `USDCAD`
- `DE30`
- `GOLD`
- `SILVER`
- `EURUSD`
- `GBPUSD`
- `USDJPY`
- `USDCHF`
- `EURAUD`
- `COPPER-US`

Powód wspólny:
- brak świeżego zapisu wiedzy,
- albo brak świeżej lekcji,
- albo oba naraz.

## Najkrótszy wniosek

Jeżeli pytanie brzmi **„które instrumenty naprawdę uczą się teraz”**, odpowiedź jest jedna:

- `US500`

Jeżeli pytanie brzmi **„które instrumenty dziś już realnie domknęły naukę w zwykłym lokalnym torze”**, odpowiedź brzmi:

- `US500`
- `EURJPY`
