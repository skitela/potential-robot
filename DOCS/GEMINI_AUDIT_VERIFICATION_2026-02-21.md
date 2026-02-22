# Gemini Follow-Up: Verification vs Claims (P0/P1) — OANDA_MT5_SYSTEM

Date: 2026-02-21  
Branch: `audit/oanda_tms_live_execution_hardening`  
Base commit (HEAD): `d0328a0`  

This document verifies the latest “all P0/P1 addressed” claims against the **actual repo state**.
Key issue: multiple fixes exist **only in the working tree** (unstaged), while the **staged set still contains P0 regressions**.

## 1) Current Git State (Why “Done” is not yet true)

### 1.1 INDEX (staged) still has P0 blockers
- `CONFIG/strategy.json` (INDEX) still contains `MAIN_SESSION` with `08:00–22:00` and `group=null` and keeps `sys_budget_day=2000`.
  - Evidence: `git show :CONFIG/strategy.json` (top section).
  - This is a **strategy/time-window change** and violates the “no strategy change in this audit iteration”.
- `BIN/zeromq_bridge.py` (INDEX) binds to `tcp://*:{port}` (attack surface) and contains the previously broken multiline `print("...` string.
  - Evidence: `git show :BIN/zeromq_bridge.py` around `setup_sockets()` and `__main__` print section.
- `MQL5/Experts/HybridAgent.mq5` (INDEX) still has:
  - wrong include: `#include <Include\\zeromq_bridge.mqh>` (line ~12)
  - timer unit bug: `InpTimerMs=1000` + `EventSetTimer((uint)InpTimerMs)` (line ~26 + ~46), where `EventSetTimer()` expects seconds.
  - Evidence: `git show :MQL5/Experts/HybridAgent.mq5` lines ~12/26/46.
- `BIN/safetybot.py` (INDEX) still contains the dangerous **test auto-trade**:
  - “tick EURUSD => send BUY command” (“Wykryto tick EURUSD…”, “Test Hybrid/ZMQ”).
  - Evidence: `git show :BIN/safetybot.py` search hits for `Wykryto tick` / `Test Hybrid/ZMQ`.

Conclusion: **The staged changeset is not safe** and cannot be treated as “ready”.

### 1.2 WORKING TREE contains partial fixes (but not staged yet)
These fixes exist in the working tree only:
- `BIN/zeromq_bridge.py`: binds to localhost only.
  - Evidence: `BIN/zeromq_bridge.py:58-64` uses `tcp://127.0.0.1:{port}`.
- `MQL5/Experts/HybridAgent.mq5`: timer now in seconds and include path fixed.
  - Evidence: `MQL5/Experts/HybridAgent.mq5:12` `#include <zeromq_bridge.mqh>`
  - Evidence: `MQL5/Experts/HybridAgent.mq5:26,46,57` `InpTimerSec` + `EventSetTimer(InpTimerSec)`.
- `CONFIG/strategy.json`: restored standard windows + raised SYS budget.
  - Evidence: `CONFIG/strategy.json:8` has `sys_budget_day=5000`.
  - Evidence: `CONFIG/strategy.json:19-52` has `FX_AM 09:00-12:00` and `METAL_PM 14:00-17:00`.
- `BIN/safetybot.py`: trade_windows loader accepts dynamic keys.
  - Evidence: `BIN/safetybot.py:7632-7669` iterates `for wid in raw_tw.keys():`.
- `BIN/safetybot.py`: test auto-trade phrase `Wykryto tick...` no longer present in working tree.
  - Evidence: working tree search count for `Wykryto tick` = 0.

Conclusion: fixes are present but **not yet part of the staged release candidate**.

## 2) Claims That Are Still Not Implemented (Even in Working Tree)

### 2.1 IPC contract + ACK (P0)
Claim: “Dummy ticket hack fixed; replaced with TRADE_ACK w/ real ticket/retcode.”

Reality: working tree still returns a stub result with dummy ticket:
- Evidence: `BIN/safetybot.py:5909-5934` returns `ResultStub` with `order=999999` and `retcode=TRADE_RETCODE_DONE` after `ZMQ_SEND`.

Also, `MQL5/Experts/HybridAgent.mq5` currently does not send any ACK back to Python (no `TRADE_ACK` message type implemented).

### 2.2 Security hardening beyond localhost bind (P0)
Localhost bind is good, but still missing:
- message authentication (shared secret, or equivalent)
- request correlation (`rid`), TTL, replay protection
- strict schema + validation fail-closed on both sides

### 2.3 Vendoring + DLL audit (P0 determinism)
`DOCS/GEMINI_AUDIT_RESPONSES_2026-02-21.md` promises:
- `MQL5/Include/Vendor/` for deps + `CHECKSUMS.txt`
- `DOCS/AUDIT_DLL_MANIFEST.md`
- `TOOLS/verify_dll_integrity.py`

Reality: none of those artefacts exist in the repo yet (verify via `Test-Path` / `git ls-files`).

### 2.4 Release gates / hygiene (P0)
Gate still fails cleanliness due to:
- `Aktualizuj_EA.bat` (banned by policy)
- `.venv312/` (gate excludes `.venv`, not `.venv312`)
Evidence: `EVIDENCE/gates/cleanliness_20260221_180304.txt`.

### 2.5 Requirements locks (P0 determinism)
Claim: “pip-compile done, locks updated.”

Reality: only `.in` lists were edited; `.lock` files are unchanged (no tracked diffs to locks).

### 2.6 Test policy contradictions (P0)
The staged tests currently enforce constraints that conflict with the chosen “Hybrid” architecture:
- `tests/test_no_direct_mt5_access.py` forbids importing `MetaTrader5`, but `BIN/safetybot.py` imports it.
- `tests/test_system_integrity.py` blocks `socket.socket` (Python-level) which does not reliably block ZMQ’s native sockets → false guarantee.

## 3) Architecture Decision Needed (Owner Sign-Off)
In `DOCS/GEMINI_AUDIT_RESPONSES_2026-02-21.md`, target architecture is declared as:
- **A (Hybrid)**: Python remains connected to MT5 for “guardrails”, execution goes through EA via ZMQ.

This **conflicts** with the earlier P0 requirement “Python Decision Service only, no fetch from MT5/OANDA”.
We need explicit owner sign-off on which policy is authoritative.

## 4) What “Done” Must Mean (Acceptance Checklist)
Before calling this “stable / ready”:
1. Stage/commit the working-tree fixes that remove the staged P0 blockers:
   - revert staged `MAIN_SESSION 08-22` to standard production windows
   - stage localhost bind fix in `BIN/zeromq_bridge.py`
   - stage timer/include fixes in `MQL5/Experts/HybridAgent.mq5`
   - stage removal of test auto-trade in `BIN/safetybot.py`
2. Implement ACK contract end-to-end:
   - `rid`, `ttl_sec`, `schema_version`
   - EA sends `TRADE_ACK` with `ticket`, `retcode`, `comment`, `rid`
   - Python blocks on ACK (bounded timeout) and writes evidence
3. Decide and codify policy:
   - “no outbound internet, localhost IPC allowed” vs “no network at all”
   - Python MT5 usage scope (read-only guard vs forbidden)
4. Determinism:
   - vendor MQL5 dependencies (or mark hybrid as DEV-only)
   - update requirements locks
   - pass `TOOLS/gate_v6.py --mode offline`

## 5) References
- Original request: `DOCS/GEMINI_AUDIT_REVIEW_REQUEST_2026-02-21.md`
- Gemini responses: `DOCS/GEMINI_AUDIT_RESPONSES_2026-02-21.md`

