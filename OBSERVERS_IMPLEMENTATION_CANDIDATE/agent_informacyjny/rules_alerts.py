from __future__ import annotations

from typing import Any


def _to_int_safe(value: Any) -> int:
    try:
        if value is None:
            return 0
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, (int, float)):
            return int(value)
        text = str(value).strip().upper()
        if text in {"", "UNKNOWN", "N/A", "NONE"}:
            return 0
        return int(float(text))
    except (TypeError, ValueError):
        return 0


def evaluate_alerts(report: dict[str, Any]) -> list[dict[str, Any]]:
    alerts: list[dict[str, Any]] = []
    drift = report.get("drift_checks") or {}
    if drift.get("status") in {"FAIL", "MISSING"}:
        alerts.append(
            {
                "severity": "HIGH",
                "type": "NO_LIVE_DRIFT_NOT_OK",
                "summary": "Drift check report indicates non-OK state.",
            }
        )

    anomalies = report.get("anomalies") or {}
    ret_10017 = _to_int_safe(anomalies.get("retcode_10017", 0))
    if ret_10017 > 0:
        alerts.append(
            {
                "severity": "MED",
                "type": "TRADE_DISABLED_RETURNCODE_SEEN",
                "summary": f"retcode_10017 count={ret_10017}",
            }
        )
    return alerts


def should_raise_codex_ticket(report: dict[str, Any], alerts: list[dict[str, Any]]) -> bool:
    if not alerts:
        return False
    high = [a for a in alerts if a.get("severity") == "HIGH"]
    return bool(high)
