# OANDA MT5 Memory Ledger - 2026-02-15 (P0-P2 update)

## Frozen rules
- Do not change core risk philosophy.
- Do not change base percent risk and loss caps without explicit decision.
- Priority: operational safety + stable profit growth.
- Target runtime: Windows 11 + OANDA TMS MT5 Poland.

## 3-step rollout plan and status
1. P0 - Operational protection layer: COMPLETED
   - incident journal + retcode classification
   - self-heal and black-swan protection in SafetyBot
   - canary rollout guard with pause/promotion logic
   - pre-live GO/NO-GO gate script
   - cold-start canary override (manual flag, strict conditions)
2. P1 - Training quality gates: COMPLETED (core scope)
   - anti-overfit light gate in learner (`qa_light`)
   - SCUD verdict integration with learner QA signal
   - walk-forward quality metrics already active and used
3. P2 - Online adaptation: COMPLETED (first production slice)
   - drift guard integrated in SafetyBot scan cycle
   - ECO fallback on severe drift/canary/self-heal alerts
   - dynamic scan cap reduction under guard signals

## Key files changed in this cycle
- `BIN/safetybot.py`
- `BIN/learner_offline.py`
- `BIN/scudfab02.py`
- `BIN/incident_guard.py`
- `BIN/canary_rollout_guard.py`
- `BIN/drift_guard.py`
- `TOOLS/prelive_go_nogo.py`
- `TOOLS/gate_v6.py`
- tests for all new guards and gates

## Validation snapshot
- Full tests:
  - command: `python -m unittest discover -s tests -p "test_*.py" -v`
  - result: `Ran 107 tests ... OK`
- Offline audit:
  - command: `python TOOLS/gate_v6.py --mode offline`
  - run id: `20260215_122957`
  - result: PASS on all hard gates
- Pre-live gate:
  - command: `python TOOLS/prelive_go_nogo.py --root .`
  - report: `EVIDENCE/prelive_go_nogo_20260215T112932Z.json`
  - result: `GO_COLD_START_CANARY` (manual override flag enabled)

## Current launch mode
- Active mode: `GO_COLD_START_CANARY`.
- Override flag file: `RUN/ALLOW_COLD_START_CANARY.flag`.
- Guard conditions still enforced: learner freshness + zero incidents in last 24h.
- If incidents appear or freshness expires, pre-live gate can drop back to `NO_GO`.

## Resume instruction for next session
- Start with:
  - "Continue from `DOCS/OANDA_MT5_MEMORY_LEDGER_2026-02-15_P2_UPDATE.md` and current git status."
- Then provide one target:
  - `A` improve data/sample quality to move QA from RED to YELLOW/GREEN
  - `B` tune canary thresholds
  - `C` start low-capital demo/live dry-run checklist

## GH transfer package
- Porting guide for GH is ready:
  - `DOCS/OANDA_TO_GH_PORTING_PLAYBOOK_2026-02-15.md`
- Use it as primary source when implementing the same guards in GH-FX under dyrygent supervision.
