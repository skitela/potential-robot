from __future__ import annotations

from typing import Any, Dict

from BIN.safetybot import CFG, ExecutionQueue


class _DummyEngine:
    def __init__(self) -> None:
        self.calls = []

    def order_send(
        self,
        symbol: str,
        grp: str,
        request: Dict[str, Any],
        emergency: bool = False,
    ) -> Dict[str, Any]:
        self.calls.append(
            {
                "symbol": str(symbol),
                "grp": str(grp),
                "request": dict(request or {}),
                "emergency": bool(emergency),
            }
        )
        return {"ok": True, "emergency": bool(emergency)}


def _set_cfg_values(temp: Dict[str, Any]) -> Dict[str, Any]:
    prev: Dict[str, Any] = {}
    for key, value in temp.items():
        prev[key] = getattr(CFG, key)
        setattr(CFG, key, value)
    return prev


def _restore_cfg_values(prev: Dict[str, Any]) -> None:
    for key, value in prev.items():
        setattr(CFG, key, value)


def test_execution_queue_backpressure_drops_non_emergency(monkeypatch) -> None:
    prev = _set_cfg_values(
        {
            "execution_queue_enabled": True,
            "execution_queue_maxsize": 4,
            "execution_queue_submit_timeout_sec": 1,
            "execution_queue_backpressure_enabled": True,
            "execution_queue_backpressure_high_watermark": 0.50,
            "execution_queue_backpressure_warn_interval_sec": 1,
            "execution_queue_wait_warn_ms": 1000,
        }
    )
    try:
        engine = _DummyEngine()
        q = ExecutionQueue(engine)
        monkeypatch.setattr(q, "start", lambda: None)
        q._queue.put_nowait({"prefill": 1})
        q._queue.put_nowait({"prefill": 2})
        res = q.submit("EURUSD.pro", "FX", {"action": "DEAL"}, emergency=False, timeout_sec=1)
        snap = q.metrics_snapshot()
        assert res is None
        assert int(snap.get("backpressure_drops", 0)) == 1
        assert int(snap.get("qsize", 0)) == 2
        assert len(engine.calls) == 0
    finally:
        _restore_cfg_values(prev)


def test_execution_queue_emergency_bypasses_backpressure() -> None:
    prev = _set_cfg_values(
        {
            "execution_queue_enabled": True,
            "execution_queue_maxsize": 4,
            "execution_queue_submit_timeout_sec": 1,
            "execution_queue_backpressure_enabled": True,
            "execution_queue_backpressure_high_watermark": 0.10,
            "execution_queue_backpressure_warn_interval_sec": 1,
            "execution_queue_wait_warn_ms": 1000,
        }
    )
    try:
        engine = _DummyEngine()
        q = ExecutionQueue(engine)
        q._queue.put_nowait({"prefill": 1})
        q._queue.put_nowait({"prefill": 2})
        res = q.submit("EURUSD.pro", "FX", {"action": "DEAL"}, emergency=True, timeout_sec=1)
        snap = q.metrics_snapshot()
        assert isinstance(res, dict)
        assert bool(res.get("ok")) is True
        assert bool(res.get("emergency")) is True
        assert len(engine.calls) == 1
        assert int(snap.get("backpressure_drops", 0)) == 0
    finally:
        _restore_cfg_values(prev)

