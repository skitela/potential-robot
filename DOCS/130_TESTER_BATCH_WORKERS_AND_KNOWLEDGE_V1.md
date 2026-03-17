# Tester Batch Workers And Knowledge V1

## Cel
- przyspieszyć badanie kolejnych instrumentów bez brudzenia aktywnego `paper/shadow`
- uporządkować evidence per run
- wyciągać z testera więcej wiedzy niż samo `final_balance`

## Wdrożone elementy
- `RUN_MICROBOT_STRATEGY_TESTER.ps1`
  - per-run copy logów bez kolizji nazw
  - `worker_name`
  - evidence per worker
  - poprawiony licznik `paper_conversion_ratio`
  - automatyczny eksport wiedzy po biegu
- `EXPORT_STRATEGY_TESTER_KNOWLEDGE.ps1`
  - top reasony kandydatów
  - `paper_open` per `setup/regime`
  - statystyki zamknięć `timeout / SL / TP`
  - najsłabsze wzorce obserwacji
  - snapshot deckhanda
- `RUN_STRATEGY_TESTER_BATCH.ps1`
  - batch dla wielu symboli
  - zapis batch report
  - gotowość do późniejszego worker modelu
- `VALIDATE_STRATEGY_TESTER_REPEATABILITY.ps1`
  - kontrola stabilności baseline między kolejnymi runami

## Przygotowane kolejne pary
- `GBPUSD`
- `USDCAD`
- `USDCHF`

## Wniosek systemowy
- tester stał się już sensownym laboratorium wieloinstrumentowym
- nadal nie oddajemy automatowi zmian w kodzie
- ale automat daje teraz dużo lepszy materiał do decyzji człowieka
