# Migration Report: GH Behavior -> OANDA Runtime

## 1) Summary
- Type: behavioral migration (no file copy) from GH reference semantics (`5192189`) into OANDA runtime.
- Runtime dependency check: no GH imports/paths/symlinks were introduced.
- Delivery model: feature-flagged, shadow-mode capable, deterministic and rollback-friendly.

## 2) What Was Implemented

### Python (SafetyBot)
- Overnight-aware window handling.
- Group windows v2 for `FX`, `METAL`, `INDEX`, `CRYPTO`, `EQUITY`.
- Risk windows:
  - Friday NY 16:00-17:00.
  - Sunday reopen guard from NY 17:00 for `N` minutes (default 45).
- Group-level risk state:
  - `entry_allowed`, `borrow_blocked`, `priority_factor`, `reason`,
  - risk flags (`friday_risk`, `reopen_guard`).
- Overlap arbitration (14:30-16:30 UTC) and priority multipliers.
- Borrow arbitration:
  - global `group_borrow_fraction`,
  - per-group `group_borrow_fraction_by_group`,
  - borrow hard-block in risk windows.
- Candidate ranking and risk skip:
  - `prio = time_weight * score_factor * effective_group_priority_factor`,
  - hard skip in risk windows with explicit log.
- Telemetry:
  - `GROUP_ARB`,
  - `ENTRY_SKIP_RISK_WINDOW` / `ENTRY_SKIP_RISK_WINDOW_SHADOW`.
- Decision/snapshot metadata:
  - `risk_entry_allowed`, `risk_reason`, `risk_friday`, `risk_reopen`.
- Runtime policy export file for MQL5 bridge:
  - `policy_runtime.json` with flags + per-group state.

### MQL5 (HybridAgent)
- Added runtime policy loader from MT5 Common Files.
- Added policy functions:
  - `IsWindowActive(...)`,
  - `IsRiskWindow(...)`,
  - `EntryAllowedForGroup(...)`,
  - `BorrowBlockedForGroup(...)`,
  - `PriorityFactorForGroup(...)`.
- Added fail-safe:
  - on policy read/parse errors, if runtime policy is required -> no new entries.
- Added policy-aware pre-trade gating and explicit skip logging.

### Bridge contract artifacts
- `DOCS/bridge/gh_to_oanda_behavior_contract.md`
- `DOCS/bridge/policy_runtime_schema.json`

### Cross-repo hygiene guard
- Added test guard for forbidden GH references in runtime code paths.

## 3) Feature-flag rollout state
- Shadow-capable flags:
  - `policy_windows_v2_enabled`
  - `policy_risk_windows_enabled`
  - `policy_group_arbitration_enabled`
  - `policy_overlap_arbitration_enabled`
  - `policy_shadow_mode_enabled`
- Production-safe default remains configurable via `CONFIG/strategy.json`.

## 4) Validation
- Python test suite: `237 passed`.
- MQL5 deployment helper run:
  - `Aktualizuj_EA.bat` copied EA/include files.
  - DLL copy returned sharing violation (non-fatal for source migration).
  - Manual MT5 compile/reload still required at terminal side.
- Validation artifact:
  - `META/migration_validation_latest.json`
  - `LOGS/migration_validation_latest.json`

## 5) Risks / Follow-up
- MQL5 compile was not executed headlessly from this environment; perform terminal compile (`F7`) and runtime smoke.
- If MT5 Common Files path is unavailable or locked, runtime policy loader can switch to fail-safe no-trade (by design).
- Keep `policy_shadow_mode_enabled=true` for first production phase, then enable hard mode incrementally.
