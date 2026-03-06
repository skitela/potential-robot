# Nightly Testbook (PL)

Cel: każdej nocy uruchamiać ten sam zestaw testów i mieć jeden raport końcowy z informacją, co się wykonało, a co padło.

## Komendy

- `rozpocznij testy` (kolejka/plan):
  - `powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\run_nightly_testbook.ps1 -Action "start-tests" -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA`
- `przeprowadź testy` (realne wykonanie):
  - `powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\run_nightly_testbook.ps1 -Action "run-tests" -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA -RequireIdle -RequireOutsideActive`
- status ostatniego uruchomienia:
  - `powershell -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\run_nightly_testbook.ps1 -Action "status" -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA`

## Co uruchamia testbook

1. `compile_smoke` — kompilacja/import smoke (`TOOLS/smoke_compile_v6_2.py`)
2. `unit_tests_core_plus_black_swan` — testy kontraktowe + Black Swan v1/v2
3. `stage1_shadow_plus_cycle` — pełny cykl shadow+ (dry-run)
4. `runtime_latency_audit` — audyt latencji runtime
5. `black_swan_v2_runtime_report_24h` — raport 24h Black Swan v2 z logów runtime
6. `active_checklist_snapshot` — snapshot aktywności systemu i MT5

## Gdzie są raporty

- raport każdej nocy:
  - `C:\OANDA_MT5_LAB_DATA\reports\nightly_tests\<run_id>\nightly_testbook_<stamp>.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\nightly_tests\<run_id>\nightly_testbook_<stamp>.txt`
- skrót do ostatniego:
  - `C:\OANDA_MT5_LAB_DATA\reports\nightly_tests\nightly_testbook_latest.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\nightly_tests\nightly_testbook_latest.txt`
- logi kroków:
  - `C:\OANDA_MT5_LAB_DATA\reports\nightly_tests\<run_id>\logs\`
- rejestr kolejek/wykonań:
  - `C:\OANDA_MT5_LAB_DATA\run\nightly_testbook_queue.json`
  - `C:\OANDA_MT5_LAB_DATA\run\nightly_testbook_registry.jsonl`

## Interpretacja statusów

- `PASS` — wszystkie kroki przeszły.
- `PARTIAL_FAIL` — część kroków nie przeszła; raport nadal jest kompletny.
- `NO_DATA` (w raporcie Black Swan) — brak linii `BLACK_SWAN_V2` w oknie czasu.
