TOOLS

Narzedzia w tym katalogu nie sa runtime.
Maja sluzyc do:

- generowania szkieletow nowych mikro-botow,
- przygotowania presetow,
- pakowania i deployu,
- walidacji struktury projektu,
- synchronizacji tokenow `kill-switch`,
- walidacji gotowosci wdrozeniowej,
- przygotowania jednego preflightu rolloutowego.

Najwazniejsze skrypty:

- `NEW_MICROBOT_SCAFFOLD.ps1` - generator nowego mikro-bota.
- `COMPILE_MICROBOT.ps1` - kompilacja jednego eksperta.
- `COMPILE_ALL_MICROBOTS.ps1` - kompilacja calej partii.
- `SYNC_OANDAKEY_TOKEN.ps1` - odswiezenie tokenu `kill-switch` dla jednej pary.
- `SYNC_ALL_OANDAKEY_TOKENS.ps1` - odswiezenie tokenow dla calej partii.
- `VALIDATE_PROJECT_LAYOUT.ps1` - walidacja wymaganej struktury projektu.
- `VALIDATE_PRESET_SAFETY.ps1` - walidacja, ze domyslne presety sa bezpieczne, a aktywne maja `live=true`.
- `VALIDATE_DEPLOYMENT_READINESS.ps1` - walidacja gotowosci rolloutowej.
- `VALIDATE_TRANSFER_PACKAGE.ps1` - walidacja, ze `PACKAGE` i `HANDOFF` tworza spojny komplet transferowy.
- `AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1` - audyt i opcjonalne czyszczenie osieroconych katalogow runtime oraz tymczasowych artefaktow projektu.
- `ROTATE_RUNTIME_LOGS.ps1` - audyt i bezpieczna rotacja przerosnietych logow runtime do `archive`, bez mieszania biezacej pracy z historycznym balastem.
- `BUILD_TUNING_FLEET_BASELINE.ps1` - budowa lokalnych seedow dla agentow rodzinnych i koordynatora strojenia na bazie rejestrow rodzin i aktualnych stanow runtime.
- `APPLY_TUNING_FLEET_BASELINE.ps1` - rozlozenie seedow rodzinnych i koordynatora do `Common Files` w formie gotowej do dalszej integracji runtime.
- `VALIDATE_TUNING_HIERARCHY.ps1` - walidacja, ze warstwa rodzinna i koordynacyjna strojenia zostala poprawnie rozlozona i jest kompletna.
- `PREPARE_MT5_ROLLOUT.ps1` - jeden przebieg: sync, build, walidacja, chart plan, package, zip.
- `GENERATE_ACTIVE_LIVE_PRESETS.ps1` - swiadome wygenerowanie presetow `live=true` poza domyslnie bezpiecznym repo.
- `EXPORT_MT5_SERVER_PROFILE.ps1` - eksport paczki serwerowej `MT5-only`.
- `EXPORT_OPERATOR_HANDOFF.ps1` - eksport dokumentow, raportow i checklist operatorskich do wdrozenia.
- `PACK_HANDOFF_ZIP.ps1` - osobny ZIP pakietu operatorskiego `HANDOFF`.
- `INSTALL_MT5_SERVER_PACKAGE.ps1` - rozklad pakietu do katalogu danych docelowego terminala `MT5`.
- `VALIDATE_MT5_SERVER_INSTALL.ps1` - walidacja, ze pakiet zostal poprawnie rozlozony po stronie serwera.
- `SIMULATE_MT5_SERVER_INSTALL.ps1` - lokalna symulacja instalacji `PACKAGE` do testowego katalogu `MT5`.
- `PACK_PROJECT_ZIP.ps1` - backup ZIP projektu.

Runtime handlu pozostaje w MQL5.
