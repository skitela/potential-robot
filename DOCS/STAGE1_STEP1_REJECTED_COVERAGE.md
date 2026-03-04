# Etap 1 / Krok 1 — Odrzucone setupy + pokrycie per instrument

## Co robi runtime

- Każdy `ENTRY_SKIP` z aktywnym kontekstem symbolu zapisuje rekord odrzucenia do lokalnej bazy.
- Rekord zawiera:
  - symbol,
  - grupę,
  - tryb,
  - `reason_code`,
  - klasę powodu (np. `COST_QUALITY`, `RISK_GUARD`, `DATA_READINESS`),
  - etap (`stage`),
  - kontekst sygnału/regime (jeśli dostępny).

To jest zapis tylko audytowo-treningowy. Nie zmienia logiki execution.

## Raport pokrycia

Uruchom:

```powershell
py -3.12 -B TOOLS/rejected_coverage_report.py --root C:\OANDA_MT5_SYSTEM --lookback-hours 24
```

Wyniki:

- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.json`
- `EVIDENCE/learning_coverage/rejected_coverage_<timestamp>.txt`

Raport pokazuje:

- instrumenty bez danych (`MISSING_ALL_DATA`),
- instrumenty z odrzuceniami, ale bez próbek trade-path (`TRADE_PATH_STARVATION`),
- instrumenty z balansiem trade/no-trade (`OK_BALANCED`).

## Etap 1 / Krok 2 — bramka pokrycia (uczenie tylko na sensownym N)

Uruchom:

```powershell
py -3.12 -B TOOLS/rejected_coverage_gate.py --root C:\OANDA_MT5_SYSTEM --focus-group FX --lookback-hours 24
```

Raport:

- `EVIDENCE/learning_coverage/rejected_coverage_gate_<timestamp>.json`
- `EVIDENCE/learning_coverage/rejected_coverage_gate_<timestamp>.txt`

Werdykt:

- `PASS` — pokrycie danych wystarcza do następnej iteracji uczenia.
- `HOLD` — za mało danych (total/reject/trade) dla części instrumentów.

## Etap 1 / Krok 3 — cykl automatyczny + porządki

Uruchom:

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS/run_stage1_learning_cycle.ps1 -Root C:\OANDA_MT5_SYSTEM -FocusGroup FX -LookbackHours 24 -RetentionDays 14
```

Cykl robi:

1. raport odrzuceń,
2. bramkę pokrycia,
3. budowę datasetu uczenia (NO_TRADE + TRADE_PATH),
4. bramkę jakości datasetu (wolumen + balans + bucket coverage),
5. retencję starych raportów/datasetów.

Rejestracja zadania dziennego (user-level, bez wymuszania admin):

```powershell
powershell -ExecutionPolicy Bypass -File TOOLS/register_stage1_learning_task_user.ps1 -Root C:\OANDA_MT5_SYSTEM -LabDataRoot C:\OANDA_MT5_LAB_DATA -StartTime 22:30
```

## Etap 1 / Krok 4 — bramka jakości datasetu

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_dataset_quality.py --root C:\OANDA_MT5_SYSTEM
```

Wyniki:

- `EVIDENCE/learning_dataset_quality/stage1_dataset_quality_<timestamp>.json`
- `EVIDENCE/learning_dataset_quality/stage1_dataset_quality_<timestamp>.txt`

Werdykt:

- `PASS` — dane sa wystarczajaco rownomierne per instrument.
- `HOLD` — brak balansu NO_TRADE/TRADE_PATH albo za mala liczba bucketow.

## Dataset v2 (uzupelnienie pod nauke)

Dataset Stage-1 (`stage1_learning_*.jsonl`) zapisuje teraz dodatkowo:

- `instrument`, `side`,
- `gate_result`, `decision_stage`,
- `session_state`, `regime_state`,
- `command_type` (rozdzielone HEARTBEAT/TRADE_PATH/OTHER, gdy dostepne),
- `source_module`, `label_quality`.

To nadal warstwa audytowo-treningowa (brak ingerencji w execution path).

## Etap 1 / Krok 5 — lekkie etykietowanie kontrfaktyczne (snapshoty LAB)

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_counterfactual_from_snapshots.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA
```

Wyniki:

- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_rows_<timestamp>.jsonl`
- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_report_<timestamp>.json`

Zakres:

- bierze tylko próbki `NO_TRADE` z najnowszego datasetu Stage-1,
- używa historycznych świec M1 z curated snapshotów LAB,
- gdy strona (`LONG/SHORT`) jest nieznana, liczy oba warianty i zapisuje konserwatywny wynik (gorszy PnL),
- tworzy etykiety robocze:
  - `SAVED_LOSS`
  - `MISSED_OPPORTUNITY`
  - `NEUTRAL_TIMEOUT`

To jest warstwa treningowa offline; nie dotyka execution path.

## Etap 1 / Krok 6 — raport Saved Loss vs Missed Opportunity (per instrument/per okno)

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_counterfactual_summary.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA
```

Wyniki:

- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_summary_<timestamp>.json`
- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_summary_<timestamp>.txt`
- wskaźnik latest pod panel:
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_summary_latest.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_counterfactual_summary_latest.txt`

Raport zawiera:

- agregację `SAVED_LOSS / MISSED_OPPORTUNITY / NEUTRAL_TIMEOUT` per instrument,
- agregację per okno (`window_id|window_phase`),
- prostą rekomendację operacyjną (docisk/luzowanie/obserwacja) wyłącznie do SHADOW/LAB.

## Etap 1 / Krok 7 — 3 profile na jutro per instrument (proposal-only)

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_profile_pack.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --min-samples 30
```

Wyniki:

- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_<timestamp>.json`
- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_<timestamp>.txt`
- wskaźnik latest:
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_latest.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_latest.txt`

Raport buduje dla każdego instrumentu 3 zestawy:

- `BEZPIECZNY`
- `SREDNI`
- `ODWAZNIEJSZY`

Każdy zestaw jest oceniany heurystycznie na bazie danych kontrfaktycznych (Saved Loss / Missed Opportunity / średni PnL punktowy).

Ważne:

- to jest **proposal-only** (`auto_apply=false`),
- wymagany jest review człowieka,
- brak modyfikacji execution path.

## Etap 1 / Krok 8 — ocena 3 profili na historii + shadow (ranking per instrument)

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_profile_pack_evaluate.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --min-shadow-trades 3
```

Wyniki:

- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_eval_<timestamp>.json`
- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_eval_<timestamp>.txt`
- wskaźnik latest:
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_eval_latest.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_profile_pack_eval_latest.txt`

Ocena łączy:

- bazowy score z pakietu 3 profili (warstwa historyczna Stage-1),
- metryki shadow per instrument (`net_pips_per_trade`, stabilność, liczba trade).

Ważne:

- nadal **proposal-only** (`auto_apply=false`),
- przy zbyt małej liczbie trade w shadow profil odważniejszy jest przycinany do `SREDNI`,
- brak modyfikacji execution path.

## Etap 1 / Krok 9 — bramka człowieka + shadow deployer plan (bez dotykania runtime)

Uruchom:

```powershell
py -3.12 -B TOOLS/stage1_shadow_deployer.py --root C:\OANDA_MT5_SYSTEM --lab-data-root C:\OANDA_MT5_LAB_DATA --cooldown-minutes 60 --dry-run
```

Plik akceptacji człowieka (wymagany):

- `C:\OANDA_MT5_LAB_DATA\run\stage1_manual_approval.json`
- szablon w repo: `LAB/CONFIG/stage1_manual_approval.template.json`

Minimalny format:

```json
{
  "schema": "oanda.mt5.stage1_manual_approval.v1",
  "generated_at_utc": "2026-03-04T20:30:00Z",
  "approved": true,
  "ticket": "MANUAL-APPROVAL-001",
  "instruments": {
    "EURUSD": "AUTO",
    "GBPUSD": "BEZPIECZNY"
  }
}
```

Wyniki:

- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_shadow_deployer_<timestamp>.json`
- `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_shadow_deployer_<timestamp>.txt`
- latest:
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_shadow_deployer_latest.json`
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_shadow_deployer_latest.txt`
- stan cooldown:
  - `C:\OANDA_MT5_LAB_DATA\run\stage1_shadow_deployer_state.json`
- audit:
  - `C:\OANDA_MT5_LAB_DATA\reports\stage1\stage1_shadow_deployer_audit.jsonl`

Ważne:

- bez approval status będzie `SKIP` z powodem `HUMAN_APPROVAL_REQUIRED`,
- plan jest tylko dla SHADOW (`auto_apply=false`),
- narzędzie blokuje zakazane klucze ryzyka (`RISK_LOCKED_KEYS`),
- brak modyfikacji execution path.
