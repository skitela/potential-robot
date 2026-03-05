# OANDA_MT5_SYSTEM — Runtime Contracts

## Purpose
This document defines testable runtime contracts between MQL5, Bridge, Python, and deployment control-plane.

## Contract RC-01 — Runtime Owner
- **Rule**: Final allow/refuse for trade entry must be executed in MQL5 runtime.
- **Why**: Prevent external latency or service failures from taking ownership of execution safety.
- **Verification**:
- Integration tests prove MQL5 gate path runs even when Python advisory is degraded.
- Runtime log contains explicit refusal reasons at MQL5 side.

## Contract RC-02 — No Capital Risk Auto-Mutation
- **Rule**: Keys from `RISK_LOCKED_KEYS` are immutable by auto-deployers and approval tools.
- **Why**: Capital safety is operator-governed, not autonomous.
- **Verification**:
- Proposal/approval parser rejects payload with locked keys.
- Tests include positive and negative risk-lock scenarios.

## Contract RC-03 — Config Integrity
- **Rule**: All config bundles used for runtime must pass:
- `schema_version` compatibility,
- `config_hash` integrity check,
- atomic write semantics.
- **Why**: Avoid partial writes, stale or tampered config.
- **Verification**:
- Unit tests for hash/schema mismatch.
- Runtime loader rejects invalid bundle and keeps previous valid state.

## Contract RC-04 — Bridge Bounded Latency
- **Rule**: Bridge is measured and bounded by timeout budget buckets; timeout reasons are classified.
- **Why**: Bridge delay is the dominant risk for scalping quality.
- **Verification**:
- Runtime telemetry records `bridge_wait_ms`, `bridge_timeout_reason`, `command_type`.
- Reports separate heartbeat path vs trade path diagnostics.

## Contract RC-05 — Hot-Path Non-Blocking
- **Rule**: No heavy file I/O, no long polling sleep, no slow analytics call in entry decision hot-path.
- **Why**: Preserve low-latency response from tick to order decision.
- **Verification**:
- Code review checklist for hot-path.
- Latency split report confirms no new blocking stage.

## Contract RC-06 — Defensive Initialization
- **Rule**: Runtime methods must survive partial object initialization in tests/integration harnesses.
- **Why**: Prevent `AttributeError` failures from non-standard boot paths.
- **Verification**:
- Methods use guarded access (`getattr` + safe defaults) for optional runtime fields.
- Test suite includes partial-init scenarios.

## Contract RC-07 — Explicit Failure Handling
- **Rule**: No hidden exception swallowing in critical paths.
- **Why**: Silent failure hides regressions and corrupts diagnosis.
- **Verification**:
- Repository tests deny `except Exception: pass`.
- Non-fatal paths still record warnings/diagnostics.

## Contract RC-08 — Evidence and Replayability
- **Rule**: Runtime decisions and deployment decisions must be auditable.
- **Why**: Post-incident analysis requires complete trace.
- **Verification**:
- JSON/JSONL evidence files are produced for deployment and runtime diagnostics.
- Reports can reconstruct why a trade was blocked or allowed.

## Contract RC-09 — Deployment Hysteresis
- **Rule**: Profile switching requires cooldown and safety gating; emergency fallback must exist.
- **Why**: Avoid oscillation and unstable profile flapping.
- **Verification**:
- Cooldown state persisted.
- Emergency profile generated on contract/health failure.

## Contract RC-10 — LAB/Shadow Isolation
- **Rule**: Learning and shadow analytics must not directly execute live orders.
- **Why**: Experimental logic must not bypass production safeguards.
- **Verification**:
- Separation of runtime execution path from lab/shadow modules.
- Integration tests assert no direct live side-effects from offline pipelines.
