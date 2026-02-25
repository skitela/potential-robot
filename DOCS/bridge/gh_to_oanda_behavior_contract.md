# GH -> OANDA Behavioral Contract (No Runtime Dependency)

## Scope
- Source behavior reference: GH commit `5192189` (R&D only).
- Target runtime: `C:\OANDA_MT5_SYSTEM` only.
- No file copy from GH, no imports, no path links, no symlinks.

## Mapping Table
| GH behavior/policy | OANDA component | Status |
|---|---|---|
| Overnight-aware `in_window` (`start > end`) | `BIN/safetybot.py::in_window`, `BIN/scheduler.py::in_window`, `MQL5/Experts/HybridAgent.mq5::IsWindowActive` | Implemented |
| Group windows (FX/METAL/INDEX + CRYPTO/EQUITY) | `BIN/safetybot.py::group_window_weight`, `BIN/scheduler.py::ActivityController.time_weight` | Implemented |
| Friday risk + Sunday reopen guard | `BIN/safetybot.py::group_market_risk_state` | Implemented |
| Risk decision per group (`entry_allowed`, `borrow_blocked`, `priority_factor`, `reason`) | `BIN/safetybot.py::group_market_risk_state` + `RequestGovernor.group_budget_state` | Implemented |
| US overlap arbitration (14:30-16:30 UTC) | `BIN/safetybot.py::us_overlap_window_active` + `effective_group_priority_factor` + borrow tuning | Implemented |
| Borrow arbitration global/per-group, blocked in risk windows | `BIN/safetybot.py::RequestGovernor._borrow_fraction_for_group` + borrow allowance methods | Implemented |
| Candidate ranking and skip on risk block | `BIN/safetybot.py::scan_once` | Implemented |
| Telemetry `GROUP_ARB` + `ENTRY_SKIP_RISK_WINDOW` | `BIN/safetybot.py::scan_once` | Implemented |
| Decision/snapshot risk metadata fields | `BIN/safetybot.py::scan_once`, `_send_trade_command` payload | Implemented |
| MQL5 runtime policy enforcement + fail-safe on read/parse errors | `MQL5/Experts/HybridAgent.mq5` (`EntryAllowedForGroup`, `BorrowBlockedForGroup`, `PriorityFactorForGroup`, runtime loader) | Implemented |

## Runtime Policy Contract
- Producer: Python (`SafetyBot._emit_policy_runtime`).
- Consumer: MQL5 (`HybridAgent.mq5`), loaded from MT5 Common Files.
- File location (relative to MT5 Common Files): `OANDA_MT5_SYSTEM/policy_runtime.json`.
- Contract schema: `DOCS/bridge/policy_runtime_schema.json`.

## Fail-safe Rules (MQL5)
- If runtime policy is required and file load/parse fails:
  - new entries are blocked (`NO-TRADE` behavior).
  - agent continues telemetry and command processing.
- If policy is loaded in `shadow` mode:
  - entry enforcement is informational only.

## Rollout Flags (Python)
- `policy_windows_v2_enabled`
- `policy_risk_windows_enabled`
- `policy_group_arbitration_enabled`
- `policy_overlap_arbitration_enabled`
- `policy_shadow_mode_enabled`

## Separation Guarantee
- OANDA runtime has zero GH runtime dependencies.
- GH commit hash is used only as documentation reference.
