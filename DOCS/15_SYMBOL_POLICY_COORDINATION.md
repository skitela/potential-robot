# Symbol Policy Coordination

## Cel

Ten dokument spina trzy warstwy, ktore musza pozostac zgodne:

- `CONFIG/microbots_registry.json`
- `CONFIG/strategy_variant_registry.json`
- realne profile i strategie w `MQL5/Include`

Bez tej zgodnosci latwo o cichy drift miedzy:

- planem wdrozenia,
- rodzina symbolu,
- realnym zachowaniem mikro-bota.

## Zasada zrodla prawdy

Zrodlem prawdy dla genow symbolu sa:

1. profile `MQL5/Include/Profiles`
2. lokalne strategie `MQL5/Include/Strategies`
3. `strategy_variant_registry.json` jako zrzut i mapa tych roznic

`microbots_registry.json` ma byc lekkim rejestrem wdrozeniowym i ma pozostac zgodny z tym stanem, ale nie powinien sam definiowac edge.

## Rodziny

Aktualny podzial rodzin:

- `FX_MAIN`: `EURUSD`, `GBPUSD`, `USDCAD`, `USDCHF`
- `FX_ASIA`: `USDJPY`, `NZDUSD`, `AUDUSD`
- `FX_CROSS`: `EURJPY`, `GBPJPY`, `EURAUD`, `GBPAUD`

## Wspolna koordynacja

Wspolne dla rodzin moze byc:

- kontrakt strategii
- wspolny flow runtime
- helpery indikatorow
- helpery risk-plan
- helpery trigger gate
- deployment i walidacja

Lokalne dla symbolu musza pozostac:

- `session_profile`
- okna handlu
- zestaw setupow
- scoring
- `trigger_abs`
- model ryzyka
- `SL/TP/trail`

## Walidacja

Do lapiania driftu sluzy:

- `TOOLS/VALIDATE_SYMBOL_POLICY_CONSISTENCY.ps1`
- `TOOLS/GENERATE_FAMILY_POLICY_REGISTRY.ps1`
- `TOOLS/VALIDATE_FAMILY_POLICY_BOUNDS.ps1`

Skrypt sprawdza:

- zgodnosc `session_profile` miedzy `microbots_registry` i `strategy_variant_registry`
- zgodnosc `chart_tf` z `trade_tf`
- rodziny symboli i ich bazowe podsumowania
- zgodnosc symbolu z granicami jego rodziny dla:
  - okna handlu
  - spreadu
  - progow triggera
  - dozwolonych setup labels

## Znaczenie dla latencji

Ta warstwa nie ma centralizowac decyzji tradingowej.

Jej cel to:

- utrzymac spojnosc rodzin botow,
- ograniczyc chaos przy propagacji zmian,
- nie dotykac hot-path runtime.

Czyli:

- koordynacja tak,
- centralny mozg nie.
