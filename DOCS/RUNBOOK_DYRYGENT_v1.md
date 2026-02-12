# RUNBOOK_DYRYGENT_v1

## Komendy PowerShell

1. python -m py_compile "C:\OANDA_MT5_SYSTEM\DYRYGENT_EXTERNAL.py"
2. python "C:\OANDA_MT5_SYSTEM\DYRYGENT_EXTERNAL.py" --help
3. python "C:\OANDA_MT5_SYSTEM\DYRYGENT_EXTERNAL.py" --dry-run --print-summary
4. python "C:\OANDA_MT5_SYSTEM\DYRYGENT_EXTERNAL.py" --dry-run --print-summary
   - payload_id identyczny jak w (3)
5. python -m py_compile "C:\OANDA_MT5_SYSTEM\main.py"
6. python "C:\OANDA_MT5_SYSTEM\main.py" --help
   - nie pada; komunikat wrappera
7. python -m unittest discover -s "C:\OANDA_MT5_SYSTEM\TESTS" -p "test_*.py"

## Dowody
- EVIDENCE\LLM_DRYRUN\llm_payload_manifest.json
- EVIDENCE\LLM_DRYRUN\llm_payload_redacted.txt
- EVIDENCE\LLM_DRYRUN\llm_redaction_report.json
- EVIDENCE\LLM_DRYRUN\quality_checks.json
- EVIDENCE\LLM_DRYRUN\verdict.json

## Interpretacja verdict
- PASS: spełnia 16 cech, brak wycieków
- FAIL: naruszenie polityki, wyciek, błąd krytyczny
- NEEDS_ATTENTION: wymaga ręcznego przeglądu
