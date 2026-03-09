from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional, Tuple


VALID_TRADE_TRIGGER_MODES = {"BRIDGE_ACTIVE", "MQL5_SHADOW_COMPARE", "MQL5_ACTIVE"}


@dataclass(frozen=True)
class RuntimeLoopSettings:
    scan_interval: int
    heartbeat_interval: int
    heartbeat_fail_threshold: int
    heartbeat_fail_safe_cooldown: int
    heartbeat_fail_log_interval: int
    scan_suppressed_log_interval: int
    trade_timeout_budget_ms: int
    trade_retries_budget: int
    heartbeat_timeout_budget_ms: int
    heartbeat_retries_budget: int
    heartbeat_queue_lock_timeout_ms: int
    run_loop_idle_sleep: float
    scan_slow_warn_ms: int
    heartbeat_worker_stale_sec: int
    trade_probe_enabled: bool
    trade_probe_interval_sec: int
    trade_probe_max_per_run: int
    trade_probe_signal: str
    trade_probe_symbol: str
    trade_probe_group: str
    trade_probe_volume: float
    trade_probe_deviation_points: int
    trade_probe_comment: str


def resolve_trade_trigger_mode(
    requested_mode: Any,
    *,
    allow_mql5_active: bool = False,
) -> Tuple[str, str]:
    mode = str(requested_mode or "BRIDGE_ACTIVE").strip().upper()
    if mode not in VALID_TRADE_TRIGGER_MODES:
        return "BRIDGE_ACTIVE", "INVALID_MODE"
    if mode == "MQL5_ACTIVE" and not allow_mql5_active:
        return "MQL5_SHADOW_COMPARE", "MQL5_ACTIVE_NOT_CUTOVER_READY"
    return mode, "OK"


def _parse_iso_utc(value: Any) -> Optional[datetime]:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def evaluate_mql5_active_readiness_gate(
    *,
    runtime_root: Path,
    enabled: bool,
    readiness_relpath: str = "EVIDENCE/cutover/mql5_cutover_readiness_latest.json",
    max_age_sec: int = 7200,
) -> Tuple[bool, str]:
    if not enabled:
        return False, "CUTOVER_GATE_DISABLED"
    rel = str(readiness_relpath or "").strip()
    if not rel:
        return False, "CUTOVER_READINESS_PATH_EMPTY"
    readiness_path = Path(rel)
    if not readiness_path.is_absolute():
        readiness_path = (Path(runtime_root) / readiness_path).resolve()
    if not readiness_path.exists():
        return False, "CUTOVER_READINESS_MISSING"
    try:
        payload = json.loads(readiness_path.read_text(encoding="utf-8"))
    except Exception:
        return False, "CUTOVER_READINESS_INVALID_JSON"

    status = str(payload.get("status") or payload.get("readiness") or "").strip().upper()
    if status != "PASS":
        if status:
            return False, f"CUTOVER_READINESS_{status}"
        return False, "CUTOVER_READINESS_UNKNOWN"

    safe_age = max(60, int(max_age_sec))
    generated_at = _parse_iso_utc(payload.get("generated_at_utc") or payload.get("ts_utc"))
    if generated_at is None:
        return False, "CUTOVER_READINESS_TS_MISSING"
    age_sec = (datetime.now(timezone.utc) - generated_at).total_seconds()
    if age_sec > float(safe_age):
        return False, "CUTOVER_READINESS_STALE"

    return True, "OK"


def build_mt5_common_file_path(
    *,
    enabled: bool,
    subdir: str,
    file_name: str,
    appdata: Optional[str] = None,
) -> Optional[Path]:
    if not enabled:
        return None
    base = str(appdata or os.environ.get("APPDATA") or "").strip()
    if not base:
        return None
    norm_subdir = str(subdir or "OANDA_MT5_SYSTEM").strip() or "OANDA_MT5_SYSTEM"
    norm_name = str(file_name or "").strip()
    if not norm_name:
        return None
    return Path(base) / "MetaQuotes" / "Terminal" / "Common" / "Files" / norm_subdir / norm_name


def should_emit_interval(*, now_ts: float, last_ts: float, interval_s: int) -> bool:
    safe_interval = max(1, int(interval_s))
    return (float(now_ts) - float(last_ts)) >= float(safe_interval)


def build_runtime_loop_settings(cfg: Any) -> RuntimeLoopSettings:
    scan_interval = int(getattr(cfg, "scan_interval_sec", 60))
    heartbeat_interval = max(1, int(getattr(cfg, "zmq_heartbeat_interval_sec", 15)))
    heartbeat_fail_threshold = max(1, int(getattr(cfg, "zmq_heartbeat_fail_threshold", 3)))
    heartbeat_fail_safe_cooldown = max(
        1,
        int(getattr(cfg, "zmq_heartbeat_fail_safe_cooldown_sec", 30)),
    )
    heartbeat_fail_log_interval = max(
        1,
        int(getattr(cfg, "zmq_heartbeat_fail_log_interval_sec", 15)),
    )
    scan_suppressed_log_interval = max(
        1,
        int(getattr(cfg, "zmq_scan_suppressed_log_interval_sec", 60)),
    )

    trade_timeout_budget_ms = int(
        max(
            1,
            getattr(
                cfg,
                "bridge_trade_timeout_ms",
                getattr(cfg, "bridge_default_timeout_ms", 1200),
            ),
        )
    )
    trade_retries_budget = int(
        max(1, getattr(cfg, "bridge_trade_retries", getattr(cfg, "bridge_default_retries", 1)))
    )
    heartbeat_timeout_cfg_ms = int(
        max(
            1,
            getattr(
                cfg,
                "bridge_heartbeat_timeout_ms",
                getattr(cfg, "bridge_default_timeout_ms", 1200),
            ),
        )
    )
    heartbeat_timeout_budget_ms = int(
        max(100, min(heartbeat_timeout_cfg_ms, int(max(150, trade_timeout_budget_ms * 0.75))))
    )
    heartbeat_retries_cfg = int(
        max(1, getattr(cfg, "bridge_heartbeat_retries", getattr(cfg, "bridge_default_retries", 1)))
    )
    heartbeat_retries_budget = int(min(heartbeat_retries_cfg, trade_retries_budget))
    heartbeat_queue_lock_timeout_ms = int(
        max(1, min(100, getattr(cfg, "bridge_heartbeat_queue_lock_timeout_ms", 25)))
    )
    run_loop_idle_sleep = max(0.001, float(getattr(cfg, "run_loop_idle_sleep_sec", 0.01)))
    scan_slow_warn_ms = max(100, int(getattr(cfg, "run_loop_scan_slow_warn_ms", 1500)))
    heartbeat_worker_stale_sec = max(
        30,
        int(getattr(cfg, "zmq_heartbeat_worker_stale_sec", 120)),
    )

    trade_probe_enabled = bool(getattr(cfg, "bridge_trade_probe_enabled", False))
    trade_probe_interval_sec = max(5, int(getattr(cfg, "bridge_trade_probe_interval_sec", 15)))
    trade_probe_max_per_run = max(0, int(getattr(cfg, "bridge_trade_probe_max_per_run", 120)))
    trade_probe_signal = str(getattr(cfg, "bridge_trade_probe_signal", "BUY") or "BUY").strip().upper()
    if trade_probe_signal not in {"BUY", "SELL"}:
        trade_probe_signal = "BUY"
    trade_probe_symbol = str(
        getattr(cfg, "bridge_trade_probe_symbol", "__TRADE_PROBE_INVALID__") or "__TRADE_PROBE_INVALID__"
    ).strip()
    trade_probe_group = str(getattr(cfg, "bridge_trade_probe_group", "FX") or "FX").strip().upper()
    trade_probe_volume = float(max(0.0, float(getattr(cfg, "bridge_trade_probe_volume", 0.01) or 0.01)))
    trade_probe_deviation_points = int(
        max(1, int(getattr(cfg, "bridge_trade_probe_deviation_points", 10) or 10))
    )
    trade_probe_comment = str(
        getattr(cfg, "bridge_trade_probe_comment", "TRADE_PROBE_SAFE_NO_LIVE") or "TRADE_PROBE_SAFE_NO_LIVE"
    ).strip()

    return RuntimeLoopSettings(
        scan_interval=scan_interval,
        heartbeat_interval=heartbeat_interval,
        heartbeat_fail_threshold=heartbeat_fail_threshold,
        heartbeat_fail_safe_cooldown=heartbeat_fail_safe_cooldown,
        heartbeat_fail_log_interval=heartbeat_fail_log_interval,
        scan_suppressed_log_interval=scan_suppressed_log_interval,
        trade_timeout_budget_ms=trade_timeout_budget_ms,
        trade_retries_budget=trade_retries_budget,
        heartbeat_timeout_budget_ms=heartbeat_timeout_budget_ms,
        heartbeat_retries_budget=heartbeat_retries_budget,
        heartbeat_queue_lock_timeout_ms=heartbeat_queue_lock_timeout_ms,
        run_loop_idle_sleep=run_loop_idle_sleep,
        scan_slow_warn_ms=scan_slow_warn_ms,
        heartbeat_worker_stale_sec=heartbeat_worker_stale_sec,
        trade_probe_enabled=trade_probe_enabled,
        trade_probe_interval_sec=trade_probe_interval_sec,
        trade_probe_max_per_run=trade_probe_max_per_run,
        trade_probe_signal=trade_probe_signal,
        trade_probe_symbol=trade_probe_symbol,
        trade_probe_group=trade_probe_group,
        trade_probe_volume=trade_probe_volume,
        trade_probe_deviation_points=trade_probe_deviation_points,
        trade_probe_comment=trade_probe_comment,
    )


def build_runtime_loop_state() -> dict[str, Any]:
    return {
        "last_scan_ts": 0.0,
        "last_heartbeat_ts": 0.0,
        "last_market_data_ts": 0.0,
        "heartbeat_failures": 0,
        "heartbeat_fail_safe_active": False,
        "heartbeat_fail_safe_until": 0.0,
        "last_trade_probe_ts": 0.0,
        "trade_probe_sent": 0,
        "loop_id": 0,
    }
