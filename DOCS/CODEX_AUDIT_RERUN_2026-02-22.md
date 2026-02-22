# CODEX AUDIT RERUN 2026-02-22
Date: 2026-02-22
Repo: C:\OANDA_MT5_SYSTEM
Branch: audit/oanda_tms_live_execution_hardening

## 0) Scope and cleanup performed
Requested action: fix unnecessary changes, then rerun full audit and tests.

Actions executed before audit:
1. Restored accidental workspace edits to tracked state:
   - `BIN/safetybot.py`
   - `BIN/zeromq_bridge.py`
   - `tests/test_zeromq_bridge_e2e.py`
2. Removed transient test artifact:
   - `test_audit_trail_e2e.jsonl`
3. Verified workspace clean:
   - `git status --short` => clean

## 1) Test execution (hard evidence)

### 1.1 Full regression
Command:
`python -B -m unittest discover -s tests -p 'test_*.py' -v`

Result:
- `OK`
- `188` tests passed

### 1.2 Stress/recovery harness (offline)
Command:
`python -B TOOLS\\cross_stress_harness.py --root C:\\OANDA_MT5_SYSTEM --evidence C:\\OANDA_MT5_SYSTEM\\EVIDENCE\\audit_rerun_20260222 --duration-sec 10`

Result:
- `HARD_XCROSS_V1 status=PASS`
- summary artifact:
  - `EVIDENCE/audit_rerun_20260222/HARD_XCROSS_SUMMARY.json`
- key metrics from summary:
  - `stress_crash_count=0`
  - `stress_deadlock_suspect_count=0`
  - phases: `static=PASS`, `contracts=PASS`, `stress=PASS`, `recovery=PASS`

## 2) P0/P1/P2/P3 audit classification

### P0 (critical)
1. IPC contract integrity (hash/version/correlation/idempotency):
- Status: `PASS` (static + unit)
- Evidence:
  - hash/version/correlation validation in `BIN/zeromq_bridge.py`
  - response hash and request hash checks in `BIN/safetybot.py`
  - idempotency replay cache (`msg_id`) and hash checks in `MQL5/Experts/HybridAgent.mq5`
  - bridge e2e tests in `tests/test_zeromq_bridge_e2e.py`

2. Fail-safe on desync/timeout:
- Status: `PASS` (code-path + tests), runtime live proof = `UNKNOWN` (no live MT5 run in this audit)
- Evidence:
  - heartbeat fail-safe path and scan suppression in `BIN/safetybot.py`
  - EA-side timeout fail-safe closeout in `MQL5/Experts/HybridAgent.mq5`

3. Global pending-order ban:
- Status: `PASS` (static code path)
- Evidence:
  - no pending order creation pathways found in `BIN`/`MQL5` runtime logic
  - pending types used for counting/cancel/remove only
  - primary execution uses `TRADE_ACTION_DEAL` + market `BUY/SELL`

4. Python no-fetch discipline (snapshot-first, no direct MT5 fetch in decision path):
- Status: `PARTIAL / POLICY-FAIL if strict snapshot-only is mandatory`
- Evidence:
  - snapshot-first exists and works (`hybrid_use_zmq_m5_bars`, resampling path, strict mode flag)
  - however direct MT5 calls are still present in Python runtime (`copy_rates_from_pos`, `symbol_info_tick`, `positions_get`, `account_info`, `order_send`)
  - strict no-fetch is optional/configurable, not globally enforced by default

### P1 (operational hardening)
1. OANDA-style limits/guards:
- Status: `PASS` (unit/integration test evidence), live broker proof = `UNKNOWN`
- Evidence:
  - guard tests pass (`tests/test_oanda_limits_guard.py`, `tests/test_oanda_limits_integration.py`)

2. Latency/throughput:
- Status: `PASS` (offline harness), live latencies = `UNKNOWN`
- Evidence:
  - cross stress summary p50/p95 and zero crash/deadlock suspects

3. Recovery drills:
- Status: `PASS` (offline harness), full live MT5 restart drill = `UNKNOWN`
- Evidence:
  - harness phases include `recovery=PASS`

### P2 (quality/training)
1. Data quality / anti-overfit / drift:
- Status: `PASS` (test-level)
- Evidence:
  - training quality and drift-related tests pass (`test_training_quality`, `test_drift_guard`, `test_learner_overfit_gate`)

2. Feature governance (MQL5 feature payload use):
- Status: `PASS` (code path exists), live quality impact = `UNKNOWN`
- Evidence:
  - MQL5 BAR payload can include `sma_fast/adx/atr`
  - Python fast-path consumption implemented

3. Decision analytics readiness:
- Status: `PARTIAL`
- Evidence:
  - telemetry + evidence pipeline exists
  - no fresh live trading sample in this audit window

### P3 (evolution/readiness)
1. Refactor maturity:
- Status: `PARTIAL`
- Evidence:
  - hybrid split is in place
  - residual dual-path logic in Python still broad

2. Production readiness:
- Status: `PARTIAL`
- Evidence:
  - offline and structural gates pass
  - live MT5 compile/reload/runtime verification not executed in this rerun

## 3) Key findings (ordered)

1. **Critical policy gap if strict mode expected**:
   Python still contains direct MT5 data and execution pathways.
   If target policy is strict "Python decision service only on snapshots", this is not fully enforced.

2. **Good hardening state of IPC**:
   request/response hashing, correlation checks, retries, idempotency and fail-safe paths are materially stronger than pre-hardening state.

3. **Pending-order posture is controlled**:
   static scan indicates no new pending creation path in active runtime logic; pending handling is used for limits/cancel/remove.

4. **Stress/recovery posture improved**:
   offline cross-stress and full test suite passed with no crash/deadlock indicators.

5. **Residual repository hygiene risk**:
   `MQL5/Experts/SafetyBot/SafetyBotEA.mq5` remains a TODO skeleton and may create operator confusion if mistaken for active EA.

## 4) Recommendations after rerun

1. Decide policy explicitly:
   strict snapshot-only Python (`NO_FETCH_STRICT`) vs controlled fallback.
2. If strict required:
   gate/disable direct Python MT5 fetch calls in decision path by config + static guard test.
3. Keep current IPC contract frozen (`v1.0`) until dedicated migration plan exists.
4. Add one live canary evidence pack:
   heartbeat, trade ack hash, fail-safe trigger simulation, pending-ban runtime proof.
5. Mark inactive skeleton EA clearly or archive it to avoid deployment mistakes.

## 5) Audit conclusion
After restoring accidental file changes, system returned to stable known-good code state.
Automated validation is strong (188/188 tests + stress harness PASS).
Primary blocker to claim full strict architecture compliance is the unresolved Python direct-MT5 pathway (policy-dependent).
