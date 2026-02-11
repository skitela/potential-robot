# RUNBOOK_PRIMUM_NON_NOCERE_v1

## Scope
This runbook covers only technical orchestration, tooling, audits, smoke tests, release safety and training infrastructure.
It must not change trading strategy, entry/exit rules, or risk logic in SafetyBot/SCUD/Learner.

## Motto
Primum non nocere:
- Prefer additive changes.
- Keep OFFLINE safety by default.
- Keep full evidence for each run.
- Reject changes that weaken contracts or remove rollback paths.

## Golden Rules
1. No external AI/API integrations in dyrygent path. Agents remain OFFLINE stubs.
2. No breaking changes in shared BIN API contracts.
3. Every technical change must pass preflight and produce evidence.
4. Keep runtime lightweight (housekeeping + retention) without deleting business data.

## Standard Safe Flow
1. Run preflight gate:
   - `powershell -ExecutionPolicy Bypass -File RUN\PREFLIGHT_SAFE.ps1 -Root . -Loops 1`
2. Run dyrygent offline audit:
   - `powershell -ExecutionPolicy Bypass -File RUN\AUDIT_OFFLINE.ps1 -Root . -PrintSummary`
3. Run training offline audit:
   - `powershell -ExecutionPolicy Bypass -File RUN\AUDIT_TRAINING_OFFLINE.ps1 -Root .`
4. If preparing release, run tooling canary:
   - `powershell -ExecutionPolicy Bypass -File RUN\CANARY_TOOLING.ps1 -Root . -AutoRollbackOnFail`

## Emergency Rollback (Tooling Only)
If canary/preflight fails after a tooling update:
1. Find snapshot directory from canary evidence (`snapshot/`).
2. Run rollback:
   - `powershell -ExecutionPolicy Bypass -File RUN\ROLLBACK_TOOLING.ps1 -Root . -SnapshotDir <snapshot_path>`
3. Re-run preflight to confirm recovery.

## Evidence Checklist
Each run should include:
- `runlog.jsonl`
- command logs (`*.txt`)
- verdict (`verdict.json` or `verdict.txt`)
- API contract report
- housekeeping report
- lineage/checkpoint (training audit)

## Do Not
- Do not modify strategy logic to fix tooling/test issues.
- Do not enable LIVE/network paths in offline audits.
- Do not remove rollback scripts or snapshots.
