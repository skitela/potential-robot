# Gemini / Sixth - Audit Review Request (P0/P1) - OANDA_MT5_SYSTEM

Date: 2026-02-21  
Branch: `audit/oanda_tms_live_execution_hardening`  
Base commit (HEAD): `d0328a0`  
Scope: hybrid MT5(MQL5) <-> Python bridge + release/audit constraints

## 0) TL;DR (what I need from you)
You introduced a "Thin Brain, Fast Reflex" hybrid path (ZMQ + MQL5 execution agent). The direction is promising, but the current tree has several **P0 blockers**:

1. **MQL5 layer is not build-deterministic** (missing vendored deps, wrong include path, timer unit bug, unsafe DLL enablement path).
2. **IPC contract is not auditable** (no request id / TTL / ack / hash; Python fakes a successful result with dummy ticket).
3. **Policy contradictions** (tests claim "no network" + "no MetaTrader5 import", while hybrid uses ZMQ + MT5 Python API paths).
4. **Trade windows / strategy constraints are inconsistent** (dynamic iteration added, but config loader still hardcodes FX_AM/METAL_PM; config contains MAIN_SESSION with group=null and 08-22).
5. **Release gates fail** (cleanliness: `.bat` and `.venv312` artifacts).

Please respond to the questions below with: `YES/NO/UNKNOWN + fix plan + how you will test it`.

## 1) Tree State - staged vs working tree (P0 for auditability)
Right now we have a mixed state: some hybrid changes are staged, and additional hybrid + risk + IO changes are unstaged.

- Staged: ZMQ bridge + MQL5 agent + strategy.json trade_windows change + tests + requirements.in
- Unstaged: further edits in `BIN/safetybot.py`, `CONFIG/strategy.json` (sys_budget_day), `MQL5/Experts/HybridAgent.mq5` (bar stream), and IO / risk modules.

Question:
1.1. Do you intend this to ship as **one** changeset, or will you split into **atomic commits** (recommended for audit)?

## 2) MQL5 Layer - correctness, determinism, and safety (P0)

### 2.1 Build determinism & missing vendored deps
`MQL5/Include/zeromq_bridge.mqh` explicitly requires external `dingmaotu/mql-zmq` and a `libzmq.dll` + enabling "Allow DLL imports". (lines 12-28, 33)  
`MQL5/Experts/HybridAgent.mq5` requires external JSON lib (`xefino/mql5-json`). (lines 14-19)

Questions:
2.1.a. What is the **release plan** for these dependencies?
- Vendor into repo with checksums + pinned version?
- Or keep as manual install (not audit-friendly) and mark hybrid as DEV-only?
2.1.b. If DLL imports are required: where is the **hash/allowlist** and evidence that the DLL is the expected one?

### 2.2 Include path bug (will not compile as-is)
`MQL5/Experts/HybridAgent.mq5` includes `#include <Include\zeromq_bridge.mqh>` (line 12), but the repo file is at `MQL5/Include/zeromq_bridge.mqh`.

Question:
2.2. Can you confirm you compiled a working EA in MetaEditor from this repo state? If yes, what include path did you actually use?

### 2.3 Timer unit bug (ms vs seconds)
`HybridAgent.mq5` uses:
- `input ulong InpTimerMs = 1000; // ms (1000ms = 1s)` (line 26)
- `EventSetTimer((uint)InpTimerMs)` (line 46)

In MQL5, `EventSetTimer()` is in **seconds**, not milliseconds (ms requires `EventSetMillisecondTimer()`).

Question:
2.3. Which timer API do you intend here? If the intent is 1s cadence, this is currently 1000s cadence.

### 2.4 Trade execution semantics (guards, fill type, slippage, no-pending)
`HybridAgent.mq5` executes trades via `OrderSend()` with:
- `request.action = TRADE_ACTION_DEAL` (line 236)
- `request.type_filling = ORDER_FILLING_FOK` (line 245)
- `request.deviation = 10` (line 246)

Questions:
2.4.a. Why is `ORDER_FILLING_FOK` chosen (OANDA TMS often rejects unsupported filling modes; we have history of `TRADE_RETCODE_INVALID_FILL`)?
2.4.b. Where is the enforcement of:
- "no pending orders" (P0) (currently only DEAL is used, but we need explicit guard)
- close-only / no-trade fail-safe (P0)
- symbol allowlist and volume constraints (P0)
2.4.c. How will EA report **actual result** (ticket/retcode) back to Python (see 3.2)?

### 2.5 SafetyBotEA placeholder EA (incomplete / missing includes)
`MQL5/Experts/SafetyBot/SafetyBotEA.mq5` is a skeleton that:
- includes missing headers `..\..\Include\Hybrid\WebRequest.mqh` and `Contract.mqh` (lines 13-14; both paths do not exist in repo)
- uses HTTP endpoint `http://127.0.0.1:5000/decide` (line 17)
- has JSON string building that appears syntactically invalid for MQL5 string escaping (lines 107-114)

Questions:
2.5.a. Is this EA intended to be used, or should it be removed from release scope?
2.5.b. If intended: where are the missing include files and the referenced schema `SCHEMAS/snapshot_v1.json` (mentioned line 105; not present in repo)?

## 3) Python Layer - hybrid routing, contracts, and policy (P0)

### 3.1 ZMQ binding to all interfaces (attack surface)
`BIN/zeromq_bridge.py` binds sockets to `tcp://*:{port}`:
- PULL bind: line 58
- PUSH bind: line 63

Questions:
3.1.a. Why bind to `*` instead of `127.0.0.1`? This is a security issue even on "local" systems.
3.1.b. What prevents a foreign process from injecting fake market data into the PULL socket?

### 3.2 No auditable request/response contract (no rid/ttl/ack/hash)
Current command structure is JSON with `{"action":"TRADE","payload":...}` (see `_send_trade_command` in `BIN/safetybot.py` lines 7346-7364).
There is no:
- `schema_version`
- `rid` correlation id
- `ttl_sec` / max-age
- request_hash / response_hash
- execution acknowledgment from EA back to Python

Additionally, Python currently fakes success in `_dispatch_order`:
`BIN/safetybot.py` lines 5909-5934:
- sends ZMQ command
- returns `ResultStub` with `TRADE_RETCODE_DONE` and dummy ticket `999999`

Questions:
3.2.a. Is the dummy-ticket stub a temporary DEV hack? If yes, what is the plan for:
- receiving execution ack with real ticket/retcode
- writing evidence (decision_event -> trade_ticket linkage) deterministically
3.2.b. What is the fail-closed behavior if command send fails (ZMQ down / timeout / malformed msg)?

### 3.3 "Thin brain" claim vs remaining MT5 Python API usage
You introduced ZMQ tick cache injection:
`ExecutionEngine.tick()` uses `_zmq_tick_cache` and returns a TickStub without consuming PRICE budgets:
`BIN/safetybot.py` lines 3269, 3541-3566.

However Python still imports and uses `MetaTrader5` in the same process (global import at top of `BIN/safetybot.py`) and still performs other MT5 calls in periodic `scan_once()` (hybrid run loop calls `scan_once()`).

Questions:
3.3.a. What is the target architecture:
- A) "hybrid" (Python still connected to MT5, just offloading DEAL execution), or
- B) strict separation (Python NO-FETCH / NO-MT5, EA owns all data and execution)?
3.3.b. If B): what is the migration plan to remove MT5 Python dependency while keeping existing guardrails?

### 3.4 Trade windows: dynamic ctx vs static config loader
Dynamic evaluation was added in `trade_window_ctx()`:
- iterates over `sorted(tw.keys())` (line 745-746)
- sets `group = str(w.get("group") or "").upper()` (line 769) => null group becomes empty string

But config loading still only accepts windows named exactly:
- `for wid in ("FX_AM", "METAL_PM"):` (line 7653)

Also `CONFIG/strategy.json` currently contains:
- `trade_windows.MAIN_SESSION` with `"group": null` and `08:00-22:00` (lines 19-31)

Questions:
3.4.a. Which of these is intended as source of truth?
3.4.b. If windows are now truly dynamic, why does loader still hardcode FX_AM/METAL_PM?
3.4.c. If group can be null, how is group routing enforced (FX vs METAL) without breaking P0 windows semantics?

## 4) Strategy-change constraint (P0 process)
In this audit iteration we must not silently change strategy/hours.

Observation:
- `CONFIG/strategy.json` contains 08:00-22:00 (lines 20-30), i.e. includes the 20-22 span.

Question:
4.1. Is 08-22 intended to go live now? If yes, this is a strategy/time-window change and needs explicit approval + separate change record. If not, please revert/flag as DEV-only.

## 5) Release gates / cleanliness / determinism (P0)
`TOOLS/gate_v6.py --mode offline` currently fails `cleanliness` due to banned files:
- `Aktualizuj_EA.bat` (new)
- `start.bat`, `stop.bat` (existing)
- `.venv312/.../*.bat` + `.venv312/Scripts/python*.exe` (present in repo root; gate does not exclude `.venv312`)
See: `EVIDENCE/gates/cleanliness_20260221_180304.txt`

Questions:
5.1. Are we allowed to keep `.venv312/` inside repo root, or should it be moved outside? (Gate currently treats it as release content.)
5.2. `Aktualizuj_EA.bat` references a non-existent EA filename (`Experts\\OANDA_SafetyBot_EA.mq5`, lines 25-55). Is this script obsolete? Should it be removed or converted to allowed tooling?

## 6) Dependency locks (P0)
`pyzmq` was added to:
- `requirements.live.in` line 7
- `requirements.offline.in` line 6

Questions:
6.1. Why were `requirements.*.lock` not updated? (This breaks deterministic installs.)

## 7) Tests & policy contradictions (P0)
Two new tests enforce constraints that conflict with current hybrid design:

- `tests/test_system_integrity.py` monkeypatches Python `socket.socket` to forbid any network (lines 7-19), but ZMQ uses C-level sockets (not blocked by this patch), so this test is a **false guarantee**.
- `tests/test_no_direct_mt5_access.py` forbids importing `MetaTrader5` (lines 6-55), but the project still relies on MT5 Python API in `BIN/safetybot.py`.

Questions:
7.1. What is the intended policy: "no network at all (incl. localhost)" or "no outbound internet, localhost IPC allowed"?
7.2. What is the intended policy for MT5 in Python: strictly forbidden, or allowed for live attach (current system design)?
7.3. If tests are kept: what is the scope (decision-service package only vs whole runtime)?

## 8) Evidence requested (what I need to sign off P0)
Please provide the following evidence artifacts (or an equivalent deterministic recipe):
8.1. Proof that HybridAgent compiles and runs in MT5 from this repo state (exact steps + dependency provenance + hashes).
8.2. Proof that new IPC path is fail-safe: ZMQ down => NO-TRADE (or CLOSE-ONLY) enforced by EA.
8.3. Proof that no pending orders are created (static scan + runtime guard).
8.4. Proof that trade windows are consistent between config and runtime (single source of truth).

## 9) Response format
For each section above, reply with:
- `Answer: YES/NO/UNKNOWN`
- `Fix plan: ...`
- `Tests/evidence: ...`

