from __future__ import annotations

from pathlib import Path

from TOOLS.kernel_shadow_parity_probe import (
    _build_probe_command,
    _classify_probe_status,
    _default_symbols_from_strategy,
)


def test_build_probe_command_uses_mismatched_hash_and_safe_payload() -> None:
    cmd = _build_probe_command("EURUSD.pro")
    assert cmd["action"] == "TRADE"
    assert cmd["request_hash"] == "PARITY_PROBE_HASH_MISMATCH"
    payload = cmd["payload"]
    assert payload["symbol"] == "EURUSD.pro"
    assert payload["volume"] == 0.0
    assert payload["comment"] == "PARITY_PROBE_NO_EXECUTION"


def test_default_symbols_from_strategy_has_non_empty_list() -> None:
    symbols = _default_symbols_from_strategy(Path(".").resolve())
    assert isinstance(symbols, list)
    assert len(symbols) > 0


def test_classify_probe_status_reports_no_active_peer_for_timeouts() -> None:
    rows = [{"symbol": "EURUSD.pro", "status": "FAILED"}]
    errors = ["Again: Resource temporarily unavailable"]
    assert _classify_probe_status(rows, errors) == "NO_ACTIVE_PEER"


def test_classify_probe_status_reports_no_active_peer_for_req_state_errors() -> None:
    rows = [{"symbol": "EURUSD.pro", "status": "FAILED"}]
    errors = ["ZMQError: Operation cannot be accomplished in current state"]
    assert _classify_probe_status(rows, errors) == "NO_ACTIVE_PEER"
