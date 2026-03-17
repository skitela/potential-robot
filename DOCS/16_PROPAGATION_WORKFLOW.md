# Propagation Workflow

## Cel

Ten workflow odpowiada na docelowy model pracy:

- rozwijamy jeden bot wzorcowy,
- przenosimy tylko czesc wspolna,
- nie niszczymy lokalnych genow innych par.

## Narzedzie

Do planowania sluzy:

- `TOOLS/PLAN_STRATEGY_PROPAGATION.ps1`
- `TOOLS/GENERATE_ALL_PROPAGATION_PLANS.ps1`

Skrypt generuje plan:

- dla calego parku `common`
- dla rodziny `family`
- dla pojedynczego symbolu `symbol`
- oraz komplet planow rodzinnych `FX_MAIN / FX_ASIA / FX_CROSS`

Artefakty zbiorcze:

- `EVIDENCE/propagation_plan_matrix.json`
- `EVIDENCE/propagation_plan_matrix.txt`
- `EVIDENCE/PROPAGATION_PLANS/*`

## Co wolno propagowac

Bezpieczne do propagacji:

- helpery wspolnego flow strategii
- helpery runtime i journalingu
- helpery risk-plan
- helpery trigger gate
- wspolne narzedzia rolloutu i walidacji

## Czego nie wolno nadpisywac

Lokalne geny pary:

- `session_profile`
- okna handlu
- scoring formulas
- setup labels
- trigger thresholds
- risk model values
- `SL/TP/trail`

## Zasada operacyjna

1. Rozwijaj wzorzec lokalnie.
2. Wygeneruj `strategy_variant_registry`.
3. Wygeneruj `family_policy_registry`.
4. Uruchom `PLAN_STRATEGY_PROPAGATION.ps1`.
5. Dla calego projektu wygeneruj komplet planow rodzinnych.
6. Propaguj tylko czesc wspolna.
7. Zweryfikuj rollout preflight przed wdrozeniem.
