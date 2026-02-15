# OANDA MT5 Memory Ledger (2026-02-15)

## Po co ten plik
- Trwała pamięć robocza projektu.
- Wznowienie prac bez ponownego analizowania od zera.

## Zasady zamrożone (nie zmieniać bez świadomej decyzji)
- Nie zmieniamy filozofii ryzyka systemu.
- Nie zmieniamy bazowych progów procentowych strat i sizingu bez osobnej akceptacji.
- Priorytet: bezpieczeństwo operacyjne + maksymalizacja stabilnego zysku.
- Środowisko docelowe: Windows 11, MT5/OANDA TMS Polska.

## Co już wdrożono
- Warstwa Black Swan:
  - `BIN/black_swan_guard.py`
  - integracja w `BIN/safetybot.py`
- Warstwa Self-Heal (szybkie samoleczenie po degradacji):
  - `BIN/self_heal_guard.py`
  - integracja w `BIN/safetybot.py`
  - automatyczne: global backoff + cooldown symboli + wymuszenie ECO
- Telemetria i metadane decyzji rozszerzone o pola self-heal.
- Fallback importowy MT5 timeframe (stabilne testy/offline import).

## Ostatnia walidacja
- Komenda:
  - `python -m unittest discover -s tests -p "test_*.py" -v`
- Wynik:
  - `Ran 92 tests ... OK`

## Backlog wdrożeń (następne kroki)
- P0 (najpierw):
  - Canary rollout + szybki rollback zmian strategii/parametrów.
  - Twarda checklista "pre-live small capital" + automatyczny gate GO/NO-GO.
  - Dziennik incydentów i automatyczna klasyfikacja przyczyn strat (execution/model/regime).
- P1:
  - Walk-forward jako domyślny tryb treningu.
  - Bramka statystyczna anty-overfit (np. SPA/Reality-Check/PBO) przed dopuszczeniem zmian.
  - Bardziej realistyczny model egzekucji (slippage, opóźnienia, zmienny spread).
- P2:
  - Detekcja driftu online i automatyczny retrain/obniżenie aktywności.
  - Rozszerzenie monitoringu jakości filli i kosztów mikrostruktury.

## Jak wznowić pracę w nowym oknie
- W pierwszej wiadomości podaj:
  - "Kontynuuj na podstawie `DOCS/OANDA_MT5_MEMORY_LEDGER_2026-02-15.md` i aktualnego `git status`."
- Następnie wskaż tylko numer kroku (`P0`, `P1`, `P2`) albo konkretny punkt backlogu.

## Źródła raportowe w repo
- Raport self-heal:
  - `EVIDENCE/SELF_HEAL_WDROZENIE_2026-02-15.md`
- Historyczny handoff:
  - `HANDOFF_20260213_MU_START.txt`
