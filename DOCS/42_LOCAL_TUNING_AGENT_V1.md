# 42 Local Tuning Agent V1

## Cel

Wprowadzono pierwszy praktyczny `v1` lokalnego Agenta Strojenia dla `EURUSD`, razem z podporzadkowanym mu technicznym pomocnikiem danych.

To nie jest jeszcze swobodna samoprzebudowa strategii.
To jest bezpieczny, ograniczony regulator parametrow strojenia dzialajacy:

- wewnatrz `MT5`
- poza hot-path tickowym
- na `OnTimer`
- w spokojnym cyklu serwisowym `300s` albo po zmianie probki uczenia
- na bazie lokalnych danych systemu

## Kapitan i majtek

### Kapitan
- `MbTuningLocalAgent.mqh`
- czyta bucket summary i stan runtime
- podejmuje mala, sekwencyjna zmiane parametrow strojenia
- nie rusza kodu strategii
- nie dziala bez wiarygodnych danych

### Majtek
- `MbTuningDeckhand.mqh`
- sprawdza wiarygodnosc `learning_observations_v2.csv`
- odbudowuje `learning_bucket_summary_v1.csv`, gdy probka sie zmienila albo summary zniknelo
- oznacza, czy dane sa wystarczajaco czyste do strojenia

## Dane wejsciowe

Kapitan korzysta z:
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`
- `runtime_state.csv`
- `execution_summary.json`
- `informational_policy.json`

Majtek przygotowuje mu czysty obraz i ocene zaufania:
- `TRUSTED`
- `LOW_SAMPLE`
- `BUCKETS_EMPTY`
- `DATASET_NOISY`
- `OBSERVATIONS_MISSING`

## Co wolno agentowi v1

`v1` moze zmieniac tylko dozwolone parametry sterujace:
- kara globalna dla `BREAKOUT`
- kara dla `BREAKOUT` w `CHAOS`
- kara dla `BREAKOUT` w `RANGE`
- kara dla `TREND` w `BREAKOUT`
- kara dla `TREND` w `CHAOS`
- kara dla `TREND` przy slabym spreadzie
- kara dla `TREND` bez wsparcia `AUX`
- lekki boost dla `REJECTION` w `RANGE`
- globalny limit `confidence_cap`
- globalny limit `risk_cap`
- wymog wsparcia `AUX` dla slabego `TREND`

## Czego agentowi v1 nie wolno

- przepisywac kodu zrodlowego
- zmieniac architektury `Core`
- dotykac hot-path na ticku
- stroic bez probki
- wykonywac wielu zmian naraz
- agresywnie eksperymentowac na `live`

## Gdzie zapisuje slad

- stan polityki:
  - `state/<symbol>/tuning_policy.csv`
- dziennik zmian:
  - `logs/<symbol>/tuning_actions.csv`
- dziennik pracy majtka:
  - `logs/<symbol>/tuning_deckhand.csv`

## Integracja

Pierwsza aktywna integracja zostala wykonana dla:
- `MicroBot_EURUSD`
- `Strategy_EURUSD`

To daje nam referencyjny, lokalny model strojenia, ktory mozna potem rozszerzac na kolejne mikro-boty bez naruszania ich genotypu.
