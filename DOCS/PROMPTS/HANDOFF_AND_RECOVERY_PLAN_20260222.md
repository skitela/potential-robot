# Handoff and Recovery Instructions for OANDA_MT5_SYSTEM
**To:** ChatGPT 5.3 Codex
**From:** Gemini Autonomous Agent
**Date:** 2026-02-22
**Subject:** Critical Recovery, Hardening Completion, and Full System Audit

## 1. Current System State & High-Level Objective

You are receiving this handoff to perform critical recovery and complete a system-hardening task for the `OANDA_MT5_SYSTEM`, a hybrid Forex trading bot. The system uses a Python backend for strategy and decision-making and an MQL5 Expert Advisor (EA) for trade execution. Communication is handled by a ZeroMQ bridge.

The primary objective is to finalize the transition from an unreliable "fire-and-forget" communication protocol to a robust, synchronous, and fully auditable `REQ/REP` pattern, ensuring maximum stability and operational safety.

**Constraint:** Your analysis is static. You do not have live access to the MetaTrader 5 terminal. All actions must be performed on the file system, and MQL5 changes must be deployed using the `Aktualizuj_EA.bat` script.

## 2. Analysis of Recent Changes (by Gemini Agent)

Prior to the critical incident, I performed the following architectural improvements:

### 2.1. Communication Bridge Hardening (`REQ/REP` Pattern)
I modified the ZeroMQ bridge to move from a one-way `PUSH/PULL` pattern for commands to a two-way `REQ/REP` pattern.
- **Python (`BIN/zeromq_bridge.py`):** The command socket was changed to `zmq.REQ`. The `send_command` method was enhanced to be a blocking call that sends a request and waits for a specific reply. It now includes logic for timeouts, retries, and correlation ID validation to handle desynchronization.
- **MQL5 (`MQL5/Include/zeromq_bridge.mqh`):** The command socket was changed to `zmq.REP`. A new function, `Zmq_SendReply`, was created to send acknowledgements back to the Python application.
- **MQL5 (`MQL5/Experts/HybridAgent.mq5`):** The EA was modified to use `Zmq_ReceiveRequest` and `Zmq_SendReply`, creating a closed loop for every command and ensuring Python is aware of the command's receipt and processing status.

### 2.2. Audit Trail Implementation
To provide "proof of execution," the Python bridge (`BIN/zeromq_bridge.py`) was enhanced to write a structured audit log to `LOGS/audit_trail.jsonl`. Every command sent, reply received, or failure is logged as a JSON object with a timestamp and correlation ID.

### 2.3. Heartbeat Mechanism
To ensure the `REQ/REP` channel remains synchronized and active, a heartbeat mechanism was designed.
- **MQL5 (`MQL5/Experts/HybridAgent.mq5`):** Logic was added to handle a `HEARTBEAT` action and return an immediate `HEARTBEAT_REPLY`.
- **Python (`BIN/safetybot.py`):** The main application loop was intended to be modified to send a `HEARTBEAT` command periodically.

## 3. Critical Incident Report: `safetybot.py` Corruption

**I must report a critical error on my part.** During the process of applying the changes described above, I executed a faulty `write_file` operation on `BIN/safetybot.py`. Instead of writing the complete, modified file content, I inadvertently wrote an incomplete version containing placeholder comments.

- **Current State:** The file `BIN/safetybot.py` is truncated and non-functional.
- **Cause:** Flaw in my code generation logic for the `write_file` tool.
- **Recovery Attempts:** A search for automated backups (`.bak`, etc.) was performed across the entire project directory and yielded no results. The original file is considered lost.

## 4. Key Architectural Risk Points (Neuralgic Points)

As you reconstruct and audit the system, pay close attention to these critical areas of the hybrid architecture:

1.  **`REQ/REP` State Machine:** The primary risk is a deadlock if one side sends a request and the other never replies. The timeout and socket-reconnect logic in the Python bridge is designed to mitigate this, but it requires rigorous testing.
2.  **Data Serialization Contract:** The system relies on a strict JSON contract between Python and MQL5. Any undocumented change to the structure of messages can cause parsing errors and communication failure.
3.  **Idempotency:** The `msg_id` (Python) and `correlation_id` (MQL5 reply) mechanism is crucial for preventing the duplicate execution of retried commands. This entire flow must be sound.
4.  **Error Propagation:** A trade execution failure in MQL5 must be reliably packaged into a reply and handled correctly by the Python strategy engine. The `REQ/REP` pattern is the designated channel for this.

## 5. INSTRUCTIONS FOR RECOVERY AND COMPLETION

Your primary directive is to **restore the system to a fully operational, stable, and hardened state.**

**Task 1: Reconstruct `safetybot.py`**
- From my analysis and the project's context, regenerate the full content of `BIN/safetybot.py`.
- The reconstructed file must integrate the new synchronous ZMQ flow. This involves:
    - Removing the `self.pending_zmq_requests` dictionary and the `_check_zmq_request_timeouts` method.
    - Rewriting the `_dispatch_order` and `_send_trade_command` methods to use the blocking `zmq_bridge.send_command` and process the reply immediately.
    - Removing the `TRADE_ACK` handling logic from the `_handle_market_data` method.

**Task 2: Implement and Verify Heartbeat**
- In the main `run` loop of the newly generated `safetybot.py`, add the logic to periodically (e.g., every 15 seconds) send a `HEARTBEAT` command and validate the reply.
- If a heartbeat fails, the system should log a critical error.

**Task 3: Enhance Automated Testing (CRITICAL)**
- My previous work lacked specific tests for the new bridge. You must correct this.
- Create a new test file, `tests/test_zeromq_bridge_e2e.py`.
- In this file, write `unittest` test cases that:
    - Mock the MQL5 `REP` socket to test the Python `REQ` socket's full logic.
    - Test the success path (send command, receive valid correlated reply).
    - Test the timeout-and-retry mechanism by simulating no reply from MQL5.
    - Test the desynchronization case by sending a reply with an incorrect `correlation_id`.

**Task 4: Implement MQL5 Agent Fail-Safe**
- My fail-safe logic was Python-centric. Enhance it.
- In the Python `run` loop's heartbeat logic, if multiple consecutive heartbeats fail, trigger a system-wide alert. Define "consecutive" as a configurable parameter (e.g., 3 failures). This signals a potential crash or hang of the MQL5 agent.

**Task 5: Implement Contract Versioning**
- To make future changes safer, introduce a version field to the communication protocol.
- Modify `zeromq_bridge.py` to inject a `__v: "1.0"` field into every command sent.
- Modify `HybridAgent.mq5` to check for this version and log a warning if it's missing or mismatched, but do not block the request for this initial implementation.

**Task 6: Deploy and Audit**
1.  After making any changes to MQL5 files (e.g., `HybridAgent.mq5` for contract versioning), you **must** execute the `Aktualizuj_EA.bat` script to deploy the changes to the MT5 terminal directory.
2.  Run the entire test suite, including the new tests you create, and ensure all tests pass.
3.  Perform a final static analysis of the restored `safetybot.py` and all modified components to ensure code quality, stability, and adherence to the project's conventions.
4.  Ensure all changes are saved to disk.

Your task is complete when `safetybot.py` is restored, all new logic is implemented, and the system is in a stable, tested, and verifiably hardened state.
