# -*- coding: utf-8 -*-
"""
MT5 SAFETY BOT — OANDA TMS (PL) via MT5
Wersja: v1.11-DECISION-EVENTS-SNAPSHOT-VERDICT (FX + METALS + INDICES)

Data: 2026-01-25

Najważniejsze zmiany vs v1.6/v1.7:
1) Budżet requestów zgodny z kontraktem audytu (P0) oraz OANDA Appendix 3 dot. "requests for price":
   - WARNING: 1000 price-requests / day
   - Bot hard-cap: 400 price-requests / day (kontrakt audytu)
   - Rezerwa awaryjna na domknięcia/kill-switch z wydzielonej puli
2) Rozdzielenie requestów:
   - PRICE: tick + pobór świec (copy_rates_*) => liczone do limitu 400/d (P0)
   - SYS: pozostałe (positions_get, account_info, history_deals_get, symbol_select, symbol_info) => osobny, konserwatywny limiter
   Uzasadnienie: Appendix 3 dotyczy "requests for price"; SYS nadal jest limitowany, żeby nie przeciążyć systemu.
3) Scheduler budżetowy:
   - Nie skanuje wszystkich instrumentów co minutę (to by wysadziło limit 900/d).
   - Co iterację wybiera 1–N symboli wg priorytetu (profil godzin + Score_hour = PnL_net/PRICE_requests).
   - Tick pobierany dopiero, gdy M5 wskazuje potencjalny sygnał (lub dla pozycji do domknięcia).
4) Profile per grupa i per instrument (DAX vs US500) z poprawnym DST (NY i PL).

Wymagania:
    pip install MetaTrader5 pandas numpy ta
"""

try:
    import MetaTrader5 as mt5
except Exception as e:  # pragma: no cover
    mt5 = None  # type: ignore
    _MT5_IMPORT_ERROR = e  # type: ignore

import pandas as pd
import numpy as np
import ta
import time
import datetime as dt
import os
import sys
import sqlite3
import threading
import queue as pyqueue
import shutil
import subprocess
import platform
import getpass
import re
import base64
import ctypes
import math

def sqlite_exec_retry(conn: sqlite3.Connection, query: str, params=None, *, tries: int = 6, base_sleep: float = 0.15):
    """
    Retry/backoff for SQLITE_BUSY / locked. Never spin-loop CPU.
    """
    if params is None:
        params = ()
    for i in range(tries):
        try:
            return conn.execute(query, params)
        except sqlite3.OperationalError as e:
            msg = str(e).lower()
            if ("locked" in msg) or ("busy" in msg):
                time.sleep(base_sleep * (2 ** i))
                continue
            raise
    # final try (let it raise if still failing)
    return conn.execute(query, params)

def sqlite_execmany_retry(conn: sqlite3.Connection, query: str, seq_params, *, tries: int = 6, base_sleep: float = 0.15):
    for i in range(tries):
        try:
            return conn.executemany(query, seq_params)
        except sqlite3.OperationalError as e:
            msg = str(e).lower()
            if ("locked" in msg) or ("busy" in msg):
                time.sleep(base_sleep * (2 ** i))
                continue
            raise
    return conn.executemany(query, seq_params)
import json
import uuid
import logging
import traceback
from types import SimpleNamespace
from pathlib import Path
from typing import Dict, Optional, List, Tuple, Any, Callable, Set
try:
    from . import common_guards as cg
    from . import common_contract as cc
    from .session_liquidity_gate import (
        SessionLiquidityGateConfig,
        SessionLiquidityGateInput,
        evaluate_session_liquidity_gate,
    )
    from .cost_microstructure_gate import (
        CostMicrostructureGateConfig,
        CostMicrostructureGateInput,
        evaluate_cost_microstructure_gate,
    )
    from .japanese_candle_adapter import (
        JapaneseCandleAdapterConfig,
        JapaneseCandleInput,
        evaluate_japanese_candle_adapter,
    )
    from .renko_sensor import (
        RenkoSensorConfig,
        RenkoTick,
        build_renko_bricks,
    )
    from .black_swan_guard import BlackSwanGuard, BlackSwanPolicy, BlackSwanSignal
    from .capital_protection_black_swan_guard_v2 import (
        CapitalProtectionBlackSwanGuardV2,
        GuardAction as BlackSwanGuardActionV2,
        GuardConfig as BlackSwanGuardConfigV2,
        GuardDecision as BlackSwanGuardDecisionV2,
        MarketSnapshot as BlackSwanMarketSnapshotV2,
    )
    from .self_heal_guard import SelfHealGuard, SelfHealPolicy
    from .canary_rollout_guard import CanaryRolloutGuard, CanaryPolicy
    from .drift_guard import DriftGuard, DriftPolicy
    from .incident_guard import IncidentJournal, classify_retcode
    from .oanda_limits_guard import OandaLimitsGuard
    from .cost_guard_runtime import (
        CostGuardMetrics,
        CostGuardThresholds,
        derive_off_threshold,
        evaluate_cost_guard_state,
        update_transition_window,
    )
    from .config_manager import ConfigManager
    from .risk_manager import RiskManager
    from .deployment_plane import (
        build_kernel_runtime_payload,
        build_kernel_symbol_rows,
        build_policy_runtime_payload,
    )
    from .kernel_config_plane import (
        KERNEL_CONFIG_POLICY_VERSION,
    )
    from .runtime_supervisor import (
        build_runtime_loop_state,
        build_runtime_loop_settings,
        build_mt5_common_file_path,
        resolve_trade_trigger_mode,
        should_emit_interval,
    )
    from .zeromq_bridge import ZMQBridge, build_request_hash, build_response_hash
except Exception:  # pragma: no cover
    import common_guards as cg
    import common_contract as cc
    from session_liquidity_gate import (
        SessionLiquidityGateConfig,
        SessionLiquidityGateInput,
        evaluate_session_liquidity_gate,
    )
    from cost_microstructure_gate import (
        CostMicrostructureGateConfig,
        CostMicrostructureGateInput,
        evaluate_cost_microstructure_gate,
    )
    from japanese_candle_adapter import (
        JapaneseCandleAdapterConfig,
        JapaneseCandleInput,
        evaluate_japanese_candle_adapter,
    )
    from renko_sensor import (
        RenkoSensorConfig,
        RenkoTick,
        build_renko_bricks,
    )
    from black_swan_guard import BlackSwanGuard, BlackSwanPolicy, BlackSwanSignal
    from capital_protection_black_swan_guard_v2 import (
        CapitalProtectionBlackSwanGuardV2,
        GuardAction as BlackSwanGuardActionV2,
        GuardConfig as BlackSwanGuardConfigV2,
        GuardDecision as BlackSwanGuardDecisionV2,
        MarketSnapshot as BlackSwanMarketSnapshotV2,
    )
    from self_heal_guard import SelfHealGuard, SelfHealPolicy
    from canary_rollout_guard import CanaryRolloutGuard, CanaryPolicy
    from drift_guard import DriftGuard, DriftPolicy
    from incident_guard import IncidentJournal, classify_retcode
    from oanda_limits_guard import OandaLimitsGuard
    from cost_guard_runtime import (
        CostGuardMetrics,
        CostGuardThresholds,
        derive_off_threshold,
        evaluate_cost_guard_state,
        update_transition_window,
    )
    from config_manager import ConfigManager
    from risk_manager import RiskManager
    from deployment_plane import (
        build_kernel_runtime_payload,
        build_kernel_symbol_rows,
        build_policy_runtime_payload,
    )
    from kernel_config_plane import (
        KERNEL_CONFIG_POLICY_VERSION,
    )
    from runtime_supervisor import (
        build_runtime_loop_state,
        build_runtime_loop_settings,
        build_mt5_common_file_path,
        resolve_trade_trigger_mode,
        should_emit_interval,
    )
    from zeromq_bridge import ZMQBridge, build_request_hash, build_response_hash
try:
    from .runtime_root import (
        REQUIRED_OANDA_MT5_EXE,
        ensure_dirs,
        get_run_mode,
        get_runtime_root,
        project_paths,
        require_live_oanda_terminal,
    )
except Exception:  # pragma: no cover
    from runtime_root import (
        REQUIRED_OANDA_MT5_EXE,
        ensure_dirs,
        get_run_mode,
        get_runtime_root,
        project_paths,
        require_live_oanda_terminal,
    )
from zoneinfo import ZoneInfo

TZ_NY = ZoneInfo("America/New_York")
TZ_PL = ZoneInfo("Europe/Warsaw")
UTC = dt.timezone.utc

# =============================================================================
# HARD LIMITS (Rulebook v1.2b) — must be defined (P0 runtime sanity)
# =============================================================================
LOCK_ACQUIRE_MAX_SECONDS = 5
MIGRATE_WALLCLOCK_MAX_SECONDS = 120
MIGRATE_STEP_MAX_SECONDS = 30
SQLITE_BUSY_TIMEOUT_MS = 3000
DISK_FREE_MIN_MB = 500
BACKUP_RETAIN_MAX_COUNT = 30
BACKUP_RETAIN_MAX_TOTAL_GB = 10

# =============================================================================
# CFG
# =============================================================================

class CFG:
    BOT_VERSION = "v1.11-DECISION-EVENTS-SNAPSHOT-VERDICT"
    verdict_ttl_sec = 172800  # 48h TTL for META/verdict.json

    # USB kill-switch: obecność TOKEN/BotKey.env na pendrive
    usb_drive_label = "OANDAKEY"


    # REQUIRED parameters referenced by code (must be explicitly set; do not guess defaults).
    # If any is None, bramki muszą dać FAIL, a część wykonawcza nie może wystartować.
    fixed_sl_points = None        # int
    fixed_tp_points = None        # int
    atr_period = None             # int
    cooldown_stops_s = None       # int
    paper_trading = None          # bool

    # pętla globalna (scheduler wybiera co zrobić w tej iteracji)
    scan_interval_sec: int = 60
    # REQ/REP heartbeat to validate MQL5 agent liveness
    zmq_heartbeat_interval_sec: int = 15
    zmq_heartbeat_fail_threshold: int = 3
    zmq_heartbeat_fail_safe_cooldown_sec: int = 30
    zmq_heartbeat_fail_log_interval_sec: int = 15
    zmq_scan_suppressed_log_interval_sec: int = 60
    # Bridge latency budget (safe defaults, configurable in CONFIG/strategy.json).
    bridge_default_timeout_ms: int = 1200
    bridge_default_retries: int = 1
    bridge_audit_async_enabled: bool = True
    bridge_audit_queue_maxsize: int = 8192
    bridge_audit_queue_put_timeout_ms: int = 2
    bridge_audit_batch_size: int = 64
    bridge_audit_flush_interval_ms: int = 200
    bridge_heartbeat_timeout_ms: int = 900
    bridge_heartbeat_retries: int = 1
    # Fast-fail heartbeat lock policy: do not block runtime loop when command channel is busy.
    bridge_heartbeat_queue_lock_timeout_ms: int = 25
    # Avoid expensive REQ socket reconnect on heartbeat timeout (trade path keeps default behavior).
    bridge_heartbeat_reconnect_on_timeout: bool = False
    # Treat heartbeat timeouts as non-fatal while market-data stream is still alive.
    bridge_heartbeat_timeout_nonfatal: bool = True
    # Heartbeat yields briefly after recent/ongoing trade command.
    bridge_heartbeat_trade_priority_window_ms: int = 300
    bridge_trade_timeout_ms: int = 1200
    bridge_trade_retries: int = 1
    # Controlled TRADE-path probe for latency audits (safe mode: invalid symbol -> no order send).
    bridge_trade_probe_enabled: bool = False
    bridge_trade_probe_interval_sec: int = 15
    bridge_trade_probe_max_per_run: int = 120
    bridge_trade_probe_signal: str = "BUY"
    bridge_trade_probe_symbol: str = "__TRADE_PROBE_INVALID__"
    bridge_trade_probe_group: str = "FX"
    bridge_trade_probe_volume: float = 0.01
    bridge_trade_probe_deviation_points: int = 10
    bridge_trade_probe_comment: str = "TRADE_PROBE_SAFE_NO_LIVE"
    run_loop_idle_sleep_sec: float = 0.01
    run_loop_scan_slow_warn_ms: int = 1500
    run_loop_scan_stats_window: int = 120
    # częstotliwość sprawdzania obecności klucza USB podczas uśpienia pętli
    usb_watch_check_interval_sec: int = 3
    # Hybrid data path:
    # - prefer M5 bars from MQL5 snapshots (ZMQ BAR) instead of Python -> mt5.copy_rates
    # - strict mode blocks fallback fetches when snapshot history is missing
    hybrid_use_zmq_m5_bars: bool = True
    # Prefer indicator features delivered by MQL5 (BAR message with sma_fast/adx/atr).
    hybrid_use_zmq_m5_features: bool = True
    # Reuse M5 store to synthesize H4/D1 bars for trend (no direct mt5.copy_rates when possible).
    hybrid_use_mtf_resample_from_m5_store: bool = True
    hybrid_m5_no_fetch_strict: bool = True
    # Hard switch: decision path must operate on MQL5 snapshots only.
    hybrid_no_mt5_data_fetch_hard: bool = True
    # Maximum accepted age of incoming market snapshots in decision path.
    hybrid_snapshot_max_age_sec: int = 180
    # BAR snapshots are M5-based and naturally older than tick stream; keep a wider age budget.
    hybrid_snapshot_bar_max_age_sec: int = 900
    # If False, stale BAR stream alone does not hard-block new entries while tick stream is fresh.
    hybrid_snapshot_block_on_bar_only: bool = True
    # Startup grace for snapshot stream warmup (prevents false startup blocks).
    hybrid_snapshot_startup_grace_sec: int = 120
    # Log cadence for snapshot-health warnings.
    hybrid_snapshot_health_log_interval_sec: int = 60
    # Log cadence for strict-snapshot missing messages (per symbol base).
    hybrid_snapshot_missing_log_interval_sec: int = 300
    # Snapshot freshness windows for symbol/account metadata channels.
    hybrid_symbol_snapshot_max_age_sec: int = 300
    hybrid_symbol_static_snapshot_max_age_sec: int = 86400
    hybrid_account_snapshot_max_age_sec: int = 30
    hybrid_account_static_snapshot_max_age_sec: int = 300
    # Legacy pull cadence values still referenced in strategy hot/warm/eco path.
    # Keep explicit defaults aligned with CONFIG/scheduler.json.
    m5_pull_sec_hot: int = 60
    m5_pull_sec_warm: int = 120
    m5_pull_sec_eco: int = 300
    # Guardrail for stale/future next-bar deadlines caused by clock/epoch drift.
    m5_wait_new_bar_max_sec: int = 900
    # If ECO limits collapse to zero while flat, keep at least minimal market probing alive.
    eco_probe_symbols_when_flat: int = 1

    # --- V1.10: Time anchoring + open-position always-on guard ---
    open_positions_guard_sec: int = 60

    # Okresowa synchronizacja zegara z czasem serwera (koszt: 1 PRICE na sync)
    time_anchor_sync_sec: int = 900   # 15 min
    time_anchor_min_price_remaining: int = 40  # nie syncuj, jeśli budżet niski
    # Reject stale updates that would rewind anchor time too far backwards.
    time_anchor_max_backward_sec: int = 120

    # Spend-down — jeśli pod koniec dnia NY zostało dużo niewykorzystanego PRICE budżetu,
    # bot może chwilowo zwiększyć aktywność (bez podnoszenia cap).
    spenddown_enabled: bool = True
    spenddown_start_hour_ny: int = 19
    spenddown_min_remaining_price: int = 120
    spenddown_boost_mode: str = "WARM"
    spenddown_extra_symbols: int = 1

    # --- OANDA Appendix 3/4 (T&C; current amended) ---
    # Appendix 3: Limits on the number of requests for price submitted.
    oanda_price_warning_per_day: int = 1000   # WARNING level per calendar day
    oanda_price_cutoff_per_day: int = 5000    # CUT-OFF level per calendar day
    # Appendix 4: Limits on Orders / Positions.
    # Hard broker limit=50/s; house limit is intentionally lower for LIVE stability.
    oanda_market_orders_per_sec: int = 20     # applies to market Orders only
    oanda_positions_pending_limit: int = 450  # house stop before 500 (positions + pending orders, excl. TP/SL)
    oanda_warn_degrade_enabled: bool = True
    oanda_warn_symbols_cap: int = 1

    # --- House safety margins (do not loosen) ---

    # Calendar-day enforcement policy: PL (Europe/Warsaw) as primary "calendar day" boundary.
    # Scheduling and daily loss limits use PL day. NY/UTC keys are still tracked for diagnostics and as a hard guard.
    calendar_day_policy: str = "PL_WARSAW"

    # --- Budżety dzienne (P0; twarde) ---
    # Kontrakt audytu wymaga jawnych wartości budżetów, raportowanych w logu BUDGET.
    # UWAGA: to są limity wewnętrzne (konserwatywne), niezależne od limitów Appendix 3/4.
    price_budget_day: int = 400   # total PRICE requests/day (tick + copy_rates_*)
    order_budget_day: int = 400   # total mt5.order_send calls/day (open/modify/close + retries)
    sys_budget_day: int = 400     # total SYS requests/day (symbol_info, positions_get, account_info, ...)

    # Soft/Emergency podział budżetów (utrzymuje możliwość awaryjnych domknięć).
    price_soft_fraction: float = 0.96
    # Wymuszenie 45/45/10: 10% rezerwy awaryjnej (domknięcia/kill-switch), 90% na trading.
    price_emergency_reserve_fraction: float = 0.10

    # ORDER: 90% na handel, 10% na awaryjne domknięcia.
    order_emergency_reserve_fraction: float = 0.10

    sys_soft_fraction: float = 0.90
    # SYS: preferowany podział procentowy, z dolnym zabezpieczeniem stałym.
    sys_emergency_reserve_fraction: float = 0.10
    sys_emergency_reserve: int = 40  # minimalna stała rezerwa awaryjna SYS

    # Progi ECO (P0): ECO gdy licznik przekroczy próg.
    # Dopuszczamy osobne progi per kategoria, żeby nie dusić scalpingu przez SYS.
    eco_threshold_pct: float = 0.80
    eco_threshold_price_pct: float = 0.80
    eco_threshold_order_pct: float = 0.80
    eco_threshold_sys_pct: float = 0.80

    # --- Backward-compat aliases (do not use in new code) ---
    price_day_cap_fraction: float = 0.40  # 400/1000 (kept for legacy references)
    sys_day_cap: int = 400                # legacy name for sys_budget_day
    order_eco_threshold_pct: float = 0.80 # legacy name for eco_threshold_pct

    # --- Stops precheck buffer (points) ---
    stops_buffer_pts: int = 10

    # --- Cooldowns (seconds) ---
    cooldown_trade_mode_s: int = 300
    cooldown_stops_too_close_s: int = 120
    cooldown_budget_s: int = 600
    cooldown_market_closed_s: int = 900
    cooldown_no_quotes_s: int = 120
    cooldown_limit_s: int = 900
    cooldown_no_money_s: int = 600

    # --- Retry (P0 deterministic) ---
    retry_sleep_s: float = 0.20
    max_retry_requote: int = 1
    max_retry_price_changed: int = 1
    max_retry_locked: int = 1
    max_retry_invalid_price: int = 1

    # --- GLOBAL_BACKOFF (P0 closed list) ---
    global_backoff_too_many_requests_s: int = 120
    global_backoff_timeout_s: int = 60
    global_backoff_connection_s: int = 60
    global_backoff_error_s: int = 60
    global_backoff_trade_disabled_s: int = 300
    global_backoff_locked_s: int = 30
    global_backoff_no_money_s: int = 600
    execution_burst_guard_enabled: bool = True
    execution_burst_lookback_sec: int = 120
    execution_burst_error_threshold: int = 4
    execution_burst_backoff_s: int = 180
    execution_burst_symbol_cooldown_s: int = 180

    # --- Grupy i profile ---

    # --- Trade windows (P0): 2 okna, brak handlu poza nimi ---
    # Wymaganie operacyjne (czas PL / Europe/Warsaw):
    # - 09:00–12:00: FX (trening + scalping)
    # - 14:00–17:00: METAL (XAU/XAG)
    # Poza oknami:
    # - brak nowych wejść (entry_allowed=0)
    # - brak PRICE polling (tick/copy_rates), poza awaryjnymi domknięciami (emergency)
    trade_windows = {
        "FX_AM": {"group": "FX", "anchor_tz": "Europe/Warsaw", "start_hm": (9, 0), "end_hm": (12, 0)},
        "METAL_PM": {"group": "METAL", "anchor_tz": "Europe/Warsaw", "start_hm": (14, 0), "end_hm": (17, 0)},
    }
    trade_window_strict_group_routing: bool = True
    trade_closeout_buffer_min: int = 15
    # Trade-window extensions (v1): improve continuity without changing the base windows.
    # - PREFETCH: near the next window start, compute (and optionally warm) a shortlist for the next group.
    #   It is observation-only (no trades).
    # - CARRYOVER: grace period after window switch; can be observation-only or (optionally) allow limited entries
    #   from the previous group.
    # - FX ROTATION: optional deterministic bucketing of FX symbols when the group is over scan capacity.
    trade_window_prefetch_enabled: bool = False
    trade_window_prefetch_lead_min: int = 15
    trade_window_prefetch_max_symbols: int = 4
    trade_window_prefetch_warm_store_indicators: bool = False
    trade_window_carryover_enabled: bool = False
    trade_window_carryover_minutes: int = 3
    trade_window_carryover_max_symbols: int = 2
    trade_window_carryover_trade_enabled: bool = False
    trade_window_carryover_groups: Tuple[str, ...] = ()
    trade_window_fx_rotation_enabled: bool = False
    trade_window_fx_rotation_bucket_size: int = 4
    trade_window_fx_rotation_period_sec: int = 180
    trade_window_fx_rotation_only_when_over_capacity: bool = True
    # Optional per-window symbol routing (execution policy only; no strategy changes).
    # Keys are window ids from trade_windows, values are symbol intents to resolve at runtime.
    trade_window_symbol_filter_enabled: bool = False
    trade_window_symbol_intents: Dict[str, Tuple[str, ...]] = {}
    hard_no_mt5_outside_windows: bool = True
    # Outside windows we still do minimal SYS reconciliation (positions/orders) for safety.
    trade_off_sys_poll_sec: int = 900
    fx_only_mode: bool = True
    symbols_to_trade = ["EURUSD", "GBPUSD", "USDJPY", "USDCHF", "USDCAD", "AUDUSD", "NZDUSD", "EURGBP"]
    symbol_group_map = {
        "EURUSD": "FX",
        "GBPUSD": "FX",
        "USDJPY": "FX",
        "EURJPY": "FX",
        "AUDJPY": "FX",
        "NZDJPY": "FX",
        "USDCHF": "FX",
        "USDCAD": "FX",
        "AUDUSD": "FX",
        "NZDUSD": "FX",
        "EURGBP": "FX",
        "XAUUSD": "METAL",
        "XAGUSD": "METAL",
        "GOLD": "METAL",
        "SILVER": "METAL",
        "PLATIN": "METAL",
        "PALLAD": "METAL",
        "COPPER-US": "METAL",
        "DAX40": "INDEX",
        "DE40": "INDEX",
        "DE30": "INDEX",
        "GER40": "INDEX",
        "GER30": "INDEX",
        "EU50": "INDEX",
        "US500": "INDEX",
        "SPX500": "INDEX",
        "US100": "INDEX",
        "NAS100": "INDEX",
        "US30": "INDEX",
        "WS30": "INDEX",
        "BTCUSD": "CRYPTO",
        "ETHUSD": "CRYPTO",
        "LTCUSD": "CRYPTO",
        "XRPUSD": "CRYPTO",
    }
    index_profile_map = {
        "DAX40": "EU",
        "DE40": "EU",
        "DE30": "EU",
        "GER40": "EU",
        "GER30": "EU",
        "EU50": "EU",
        "US500": "US",
        "SPX500": "US",
        "US100": "US",
        "NAS100": "US",
        "US30": "US",
        "WS30": "US",
    }
    # Broker-specific base aliases (OANDA TMS MT5 may expose DE30/GOLD names).
    symbol_alias_map: Dict[str, Tuple[str, ...]] = {
        "EURUSD": ("EURUSD",),
        "GBPUSD": ("GBPUSD",),
        "USDJPY": ("USDJPY",),
        "EURJPY": ("EURJPY",),
        "AUDJPY": ("AUDJPY",),
        "NZDJPY": ("NZDJPY",),
        "USDCHF": ("USDCHF",),
        "USDCAD": ("USDCAD",),
        "AUDUSD": ("AUDUSD",),
        "NZDUSD": ("NZDUSD",),
        "EURGBP": ("EURGBP",),
        "XAUUSD": ("XAUUSD", "GOLD"),
        "XAGUSD": ("XAGUSD", "SILVER"),
        "PLATIN": ("PLATIN",),
        "PALLAD": ("PALLAD",),
        "COPPER-US": ("COPPER-US",),
        "DAX40": ("DAX40", "DE40", "DE30", "GER40", "GER30"),
        "EU50": ("EU50",),
        "US500": ("US500", "SPX500"),
        "US100": ("US100", "NAS100"),
        "US30": ("US30", "WS30"),
        "BTCUSD": ("BTCUSD",),
        "ETHUSD": ("ETHUSD",),
        "LTCUSD": ("LTCUSD",),
        "XRPUSD": ("XRPUSD",),
    }
    symbol_suffixes: Tuple[str, ...] = ("", ".pro", ".stp", ".pl")
    # OANDA MT5 policy guard: block accidental algo on equity/ETF/ETN symbols (non-close only).
    symbol_policy_enabled: bool = True
    symbol_policy_fail_on_other_group: bool = True
    symbol_policy_allowed_groups: Tuple[str, ...] = ("FX", "METAL", "INDEX", "CRYPTO", "EQUITY")
    symbol_policy_forbidden_symbol_markers: Tuple[str, ...] = (".ETF", "_CFD.ETF", ".ETN", "_CFD.ETN")
    symbol_policy_forbidden_path_markers: Tuple[str, ...] = ("STOCK", "AKCJE", "EQUITY", "ETF", "ETN")

    # Group-policy v2 (behavioral migration from R&D semantics).
    # Feature flags: stage rollout via shadow mode.
    policy_windows_v2_enabled: bool = True
    policy_risk_windows_enabled: bool = True
    policy_group_arbitration_enabled: bool = True
    policy_overlap_arbitration_enabled: bool = True
    policy_shadow_mode_enabled: bool = True
    policy_runtime_emit_enabled: bool = True
    policy_runtime_emit_interval_sec: int = 15
    policy_runtime_file_name: str = "policy_runtime.json"
    policy_runtime_emit_common_file: bool = True
    policy_runtime_common_subdir: str = "OANDA_MT5_SYSTEM"
    budget_log_interval_sec: int = 60
    oanda_price_breakdown_log_interval_sec: int = 60
    kernel_config_emit_enabled: bool = True
    kernel_config_emit_interval_sec: int = 15
    kernel_config_file_name: str = "kernel_config_v1.json"
    kernel_config_emit_common_file: bool = True
    kernel_config_common_subdir: str = "OANDA_MT5_SYSTEM"
    trade_trigger_mode: str = "BRIDGE_ACTIVE"
    trade_trigger_mode_allow_mql5_active: bool = False
    # Stage-1 live profile adapter (control-plane only, no hot-path blocking).
    stage1_live_config_enabled: bool = True
    stage1_live_config_file: str = "LAB/RUN/live_config_stage1_apply.json"
    stage1_live_reload_interval_sec: int = 15
    stage1_live_status_file: str = "RUN/stage1_live_loader_status.json"
    stage1_live_audit_file: str = "RUN/stage1_live_loader_audit.jsonl"
    stage1_live_audit_enabled: bool = True

    # dzienny podział budżetu PRICE między grupy (z możliwością pożyczania)
    group_price_shares = {"FX": 0.45, "METAL": 0.25, "INDEX": 0.30, "CRYPTO": 0.00, "EQUITY": 0.00}
    per_group: Dict[str, Dict[str, Any]] = {}
    per_symbol: Dict[str, Dict[str, Any]] = {}
    # ile z niewykorzystanych budżetów innych grup można "pożyczyć"
    group_borrow_fraction: float = 0.15
    group_borrow_fraction_by_group = {"FX": 0.15, "METAL": 0.15, "INDEX": 0.20, "CRYPTO": 0.25, "EQUITY": 0.20}
    group_priority_boost = {"FX": 1.00, "METAL": 1.05, "INDEX": 1.10, "CRYPTO": 0.95, "EQUITY": 0.90}
    group_overlap_priority_factor = {"FX": 0.90, "METAL": 1.00, "INDEX": 1.20, "CRYPTO": 0.85, "EQUITY": 1.05}
    group_borrow_unlock_power: float = 1.0  # 1.0=linear unlock by session progress
    group_priority_min_factor: float = 0.40
    group_priority_max_factor: float = 1.80
    group_priority_pressure_weight: float = 0.45

    friday_risk_enabled: bool = True
    friday_risk_ny_start_hm: Tuple[int, int] = (16, 0)
    friday_risk_ny_end_hm: Tuple[int, int] = (17, 0)
    friday_risk_groups: Tuple[str, ...] = ("FX", "METAL", "INDEX", "EQUITY")
    friday_risk_close_only_groups: Tuple[str, ...] = ("FX", "METAL")
    friday_risk_close_only: bool = True
    friday_risk_borrow_block: bool = True
    friday_risk_priority_factor: float = 0.60
    reopen_guard_enabled: bool = True
    reopen_guard_ny_start_hm: Tuple[int, int] = (17, 0)
    reopen_guard_groups: Tuple[str, ...] = ("FX", "METAL", "INDEX", "EQUITY")
    reopen_guard_minutes: int = 45
    reopen_guard_close_only_groups: Tuple[str, ...] = ("FX", "METAL")
    reopen_guard_close_only: bool = True
    reopen_guard_borrow_block: bool = True
    reopen_guard_priority_factor: float = 0.70

    # --- Strategia ---
    timeframe_trade = getattr(mt5, "TIMEFRAME_M5", 5)
    timeframe_trend_h4 = getattr(mt5, "TIMEFRAME_H4", 16388)
    timeframe_trend_d1 = getattr(mt5, "TIMEFRAME_D1", 16408)

    magic_number: int = 888123

    # --- Risk policy (defaults; no "on-feel") ---
    # Per-trade caps (as fraction of equity). Position sizing is based on SL distance and tick value.
    risk_per_trade_max_pct: float = 0.015
    risk_scalp_pct: float = 0.003
    risk_scalp_min_pct: float = 0.002
    risk_scalp_max_pct: float = 0.004
    risk_swing_pct: float = 0.01
    risk_swing_min_pct: float = 0.008
    risk_swing_max_pct: float = 0.015
    max_open_risk_pct: float = 0.018
    max_positions_parallel: int = 5
    max_positions_per_symbol: int = 1
    daily_loss_soft_pct: float = 0.02
    daily_loss_hard_pct: float = 0.03
    self_heal_max_net_loss_abs: float = 0.0

    # Execution-quality gates (spread vs p80 from recent history).
    # Scalp (HOT) requires tighter spreads; WARM tolerates wider spreads.
    spread_gate_hot_factor: float = 1.25
    spread_gate_warm_factor: float = 1.75
    spread_gate_eco_factor: float = 2.00

    # FX_AM scoring gate (poranna sesja Forex): deterministic quality score before order submit.
    fx_signal_score_enabled: bool = True
    fx_signal_score_threshold: int = 74
    fx_signal_score_hot_relaxed_enabled: bool = True
    fx_signal_score_hot_relaxed_threshold: int = 68
    fx_spread_cap_points_default: float = 24.0
    fx_atr_points_min: float = 70.0
    fx_atr_points_max: float = 220.0
    fx_impulse_atr_fraction_min: float = 0.05
    fx_body_range_ratio_min: float = 0.55
    fx_body_vs_atr_clip_max: float = 2.2

    # FX_AM pacing gate for ORDER budget usage inside 09:00-12:00 PL window.
    fx_budget_pacing_enabled: bool = True
    fx_budget_pacing_phase1_progress: float = 0.25   # 09:45 in 3h window
    fx_budget_pacing_phase2_progress: float = 0.6667 # 11:00 in 3h window
    fx_budget_pacing_phase1_ratio: float = 0.25
    fx_budget_pacing_phase2_ratio: float = 0.70
    fx_budget_pacing_slack: float = 0.05

    # METAL_PM scoring gate (popołudniowa sesja metali): deterministic quality score.
    metal_signal_score_enabled: bool = True
    metal_signal_score_threshold: int = 76
    metal_signal_score_hot_relaxed_enabled: bool = True
    metal_signal_score_hot_relaxed_threshold: int = 70
    metal_spread_cap_points_default: float = 120.0
    metal_atr_points_min: float = 120.0
    metal_atr_points_max: float = 900.0
    metal_impulse_atr_fraction_min: float = 0.07
    metal_body_range_ratio_min: float = 0.45
    metal_body_vs_atr_clip_max: float = 2.8
    metal_wick_rejection_ratio_min: float = 1.20
    metal_retest_distance_atr_max: float = 0.35

    # METAL_PM pacing gate for ORDER budget usage inside 14:00-17:00 PL window.
    metal_budget_pacing_enabled: bool = True
    metal_budget_pacing_phase1_progress: float = 0.25
    metal_budget_pacing_phase2_progress: float = 0.6667
    metal_budget_pacing_phase1_ratio: float = 0.25
    metal_budget_pacing_phase2_ratio: float = 0.70
    metal_budget_pacing_slack: float = 0.05

    # CRYPTO scoring guard (BTC/ETH): stricter than base FX/METAL gates.
    crypto_signal_score_enabled: bool = True
    crypto_signal_score_threshold: int = 78
    crypto_signal_score_hot_relaxed_enabled: bool = True
    crypto_signal_score_hot_relaxed_threshold: int = 74

    # CRYPTO capital protection: lighter sizing + tighter margin/exposure controls.
    crypto_major_risk_mult: float = 0.55
    crypto_major_min_margin_free_pct: float = 0.45
    crypto_major_max_open_positions: int = 1
    crypto_no_money_backoff_s: int = 900
    crypto_no_money_cooldown_s: int = 900

    # Self-heal guard (fast pause after local degradation; does not alter risk % policy).
    self_heal_enabled: bool = True
    self_heal_lookback_sec: int = 10800
    self_heal_min_deals_in_window: int = 3
    self_heal_loss_streak_trigger: int = 3
    self_heal_backoff_s: int = 900
    self_heal_symbol_cooldown_s: int = 600
    self_heal_recent_deals_limit: int = 64

    # Canary rollout (P0): conservative live-small-cap progression.
    canary_rollout_enabled: bool = True
    canary_lookback_sec: int = 86400
    canary_promote_min_deals: int = 15
    canary_promote_min_net_pnl: float = 0.0
    canary_pause_loss_streak: int = 3
    canary_pause_net_loss_abs: float = 0.0
    canary_max_error_incidents: int = 3
    canary_max_symbols_per_iter: int = 1
    canary_backoff_s: int = 900

    # Hard Live Canary contract (execution/risk gates; no strategy/edge changes).
    live_canary_enabled: bool = False
    module_live_enabled_map: Dict[str, bool] = {
        "FX": True,
        "METAL": False,
        "INDEX": False,
        "CRYPTO": False,
        "EQUITY": False,
    }
    live_canary_allowed_groups: Tuple[str, ...] = ("FX",)
    live_canary_allowed_symbol_intents: Tuple[str, ...] = ("USDJPY", "EURJPY", "AUDJPY", "NZDJPY")
    hard_live_disabled_groups: Tuple[str, ...] = ("CRYPTO", "METAL", "INDEX", "EQUITY")
    hard_live_disabled_symbol_intents: Tuple[str, ...] = ("BTCUSD", "ETHUSD", "JP225", "GOLD")
    hard_live_contract_file_name: str = "live_canary_contract.json"
    no_live_drift_file_name: str = "no_live_drift_check.json"
    # Cost gate policy for live canary.
    cost_gate_policy_mode: str = "DIAGNOSTIC_ONLY"  # CANARY_ACTIVE / DIAGNOSTIC_ONLY / DISABLED
    cost_gate_min_target_to_cost_ratio: float = 1.10
    cost_gate_block_on_unknown_quality: bool = True
    # Session + Liquidity gate (operational veto/permit; no strategy mutation).
    session_liquidity_gate_enabled: bool = True
    session_liquidity_gate_mode: str = "SHADOW_ONLY"  # SHADOW_ONLY / GATE_ENFORCE / DISABLED
    session_liquidity_block_on_missing_snapshot: bool = True
    session_liquidity_emit_caution_event: bool = True
    session_liquidity_spread_caution_by_group: Dict[str, float] = {
        "FX": 24.0,
        "METAL": 120.0,
        "INDEX": 90.0,
        "CRYPTO": 400.0,
        "EQUITY": 50.0,
    }
    session_liquidity_spread_block_by_group: Dict[str, float] = {
        "FX": 32.0,
        "METAL": 180.0,
        "INDEX": 130.0,
        "CRYPTO": 650.0,
        "EQUITY": 80.0,
    }
    session_liquidity_max_tick_age_sec_by_group: Dict[str, float] = {
        "FX": 8.0,
        "METAL": 10.0,
        "INDEX": 12.0,
        "CRYPTO": 15.0,
        "EQUITY": 15.0,
    }
    # Cost + Microstructure gate (operational veto/permit; no strategy mutation).
    cost_microstructure_gate_enabled: bool = True
    cost_microstructure_gate_mode: str = "SHADOW_ONLY"  # SHADOW_ONLY / GATE_ENFORCE / DISABLED
    cost_microstructure_block_on_missing_snapshot: bool = True
    cost_microstructure_block_on_unknown_quality: bool = True
    cost_microstructure_emit_caution_event: bool = True
    cost_microstructure_spread_caution_by_group: Dict[str, float] = {
        "FX": 22.0,
        "METAL": 110.0,
        "INDEX": 85.0,
        "CRYPTO": 380.0,
        "EQUITY": 45.0,
    }
    cost_microstructure_spread_block_by_group: Dict[str, float] = {
        "FX": 30.0,
        "METAL": 170.0,
        "INDEX": 125.0,
        "CRYPTO": 620.0,
        "EQUITY": 75.0,
    }
    cost_microstructure_max_tick_age_sec_by_group: Dict[str, float] = {
        "FX": 6.0,
        "METAL": 8.0,
        "INDEX": 10.0,
        "CRYPTO": 12.0,
        "EQUITY": 12.0,
    }
    cost_microstructure_gap_block_sec_by_group: Dict[str, float] = {
        "FX": 20.0,
        "METAL": 25.0,
        "INDEX": 30.0,
        "CRYPTO": 35.0,
        "EQUITY": 35.0,
    }
    cost_microstructure_jump_block_points_by_group: Dict[str, float] = {
        "FX": 80.0,
        "METAL": 350.0,
        "INDEX": 200.0,
        "CRYPTO": 1400.0,
        "EQUITY": 120.0,
    }
    # Japanese Candle adapter (advisory; does not execute orders).
    candle_adapter_enabled: bool = True
    candle_adapter_mode: str = "SHADOW_ONLY"  # SHADOW_ONLY / ADVISORY_SCORE / DISABLED
    candle_adapter_emit_event: bool = True
    candle_adapter_score_weight: float = 6.0
    candle_adapter_min_body_to_range: float = 0.35
    candle_adapter_pin_wick_ratio_min: float = 1.6
    # Renko adapter (advisory; no direct execution). Default SHADOW_ONLY to avoid strategy drift.
    renko_adapter_enabled: bool = True
    renko_adapter_mode: str = "SHADOW_ONLY"  # SHADOW_ONLY / ADVISORY_SCORE / DISABLED
    renko_adapter_emit_event: bool = True
    renko_adapter_score_weight: float = 4.0
    renko_adapter_price_source: str = "MID"  # MID / BID / ASK
    renko_adapter_tick_limit: int = 1200
    renko_adapter_cache_ttl_sec: float = 5.0
    renko_adapter_min_bricks_ready: int = 3
    renko_adapter_brick_size_points_default: float = 8.0
    renko_adapter_brick_size_points_by_group: Dict[str, float] = {
        "FX": 8.0,
        "METAL": 80.0,
        "INDEX": 40.0,
        "CRYPTO": 120.0,
        "EQUITY": 20.0,
    }
    # Renko data path (P0 data contract): persist tick snapshots for deterministic Renko build.
    # This does not alter entry/exit logic; it only stores data for Renko sensor analysis.
    renko_tick_store_enabled: bool = True
    renko_tick_store_min_interval_ms: int = 200
    renko_tick_store_min_price_delta_points: float = 0.0
    renko_tick_store_max_rows_per_symbol: int = 120000
    renko_tick_store_prune_every: int = 500
    # Auto-relax for execution guards (no strategy change): only if runtime evidence is sufficient.
    cost_guard_auto_relax_enabled: bool = False
    cost_guard_auto_relax_window_minutes: int = 360
    cost_guard_auto_relax_min_total_decisions: int = 220
    cost_guard_auto_relax_min_wave1_decisions: int = 24
    cost_guard_auto_relax_min_unknown_blocks: int = 20
    cost_guard_auto_relax_max_critical_incidents: int = 0
    cost_guard_auto_relax_max_error_incidents: int = 4
    cost_guard_auto_relax_relaxed_min_ratio: float = 1.08
    cost_guard_auto_relax_block_on_unknown_quality: bool = False
    cost_guard_auto_relax_hysteresis_enabled: bool = True
    cost_guard_auto_relax_hysteresis_total_ratio: float = 0.85
    cost_guard_auto_relax_hysteresis_wave1_ratio: float = 0.85
    cost_guard_auto_relax_hysteresis_unknown_ratio: float = 0.85
    cost_guard_auto_relax_flap_window_minutes: int = 30
    cost_guard_auto_relax_flap_alert_threshold: int = 4
    cost_guard_auto_relax_status_file_name: str = "cost_guard_auto_relax_status.json"
    # Hard live limits / throttles.
    max_daily_loss_account: float = 0.02
    max_session_loss_account: float = 0.01
    max_daily_loss_per_module: float = 0.008
    max_consecutive_losses_per_module: int = 3
    max_trades_per_window_per_module: int = 8
    max_execution_anomalies_per_window: int = 4
    max_ipc_failures_per_window: int = 4
    max_reject_ratio_threshold: float = 0.50
    max_reject_ratio_min_samples: int = 10
    # JPY basket exposure guard (Wave-1).
    jpy_basket_symbol_intents: Tuple[str, ...] = ("USDJPY", "EURJPY", "AUDJPY", "NZDJPY")
    jpy_basket_max_concurrent_positions: int = 1
    jpy_basket_max_risk_budget: float = 0.006
    jpy_basket_selection_mode: str = "TOP_1"
    jpy_basket_ranking_basis_for_top_k: str = "cost_execution_aware"
    # Asia Wave-1 symbol intents for deterministic preflight evidence.
    asia_wave1_symbol_intents: Tuple[str, ...] = ("USDJPY", "EURJPY", "AUDJPY", "NZDJPY")

    # Drift guard (P2): online regime degradation detector.
    drift_guard_enabled: bool = True
    drift_min_samples: int = 30
    drift_baseline_window: int = 30
    drift_recent_window: int = 15
    drift_mean_drop_fraction: float = 0.40
    drift_zscore_threshold: float = 1.8
    drift_backoff_s: int = 900
    black_swan_threshold: float = 3.0
    black_swan_precaution_fraction: float = 0.8
    # Warm-up guard: do not trigger black-swan kill-switch with no volatility samples.
    black_swan_min_vol_samples: int = 1
    kill_switch_on_black_swan_stress: bool = True
    kill_switch_black_swan_multiplier: float = 1.0
    # Black Swan v2 advisory guard (no direct execution ownership).
    black_swan_v2_enabled: bool = True
    black_swan_v2_hard_max_spread_points: float = 40.0
    black_swan_v2_hard_max_slippage_points: float = 25.0
    black_swan_v2_hard_max_bridge_wait_ms: float = 300.0
    black_swan_v2_hard_max_heartbeat_age_ms: float = 2500.0
    black_swan_v2_hard_max_tick_gap_ms: float = 2000.0
    black_swan_v2_crash_bridge_streak_required: int = 3
    black_swan_v2_liquidity_floor_score: float = 0.15
    black_swan_v2_liquidity_floor_streak_required: int = 3
    black_swan_v2_min_tick_rate_fraction: float = 0.30
    black_swan_v2_required_stable_ticks_for_recovery: int = 8
    black_swan_v2_halt_cooldown_sec: int = 300
    black_swan_v2_close_only_cooldown_sec: int = 180
    black_swan_v2_defensive_cooldown_sec: int = 90
    black_swan_v2_caution_cooldown_sec: int = 30
    manual_kill_switch_file: str = "RUN/kill_switch.flag"

    # Learner QA gate (P1): anti-overfit traffic-light from learner_offline.
    learner_qa_gate_enabled: bool = True
    learner_qa_red_to_eco: bool = True
    learner_qa_yellow_symbol_cap: int = 1
    unified_learning_runtime_enabled: bool = True
    unified_learning_runtime_paper_only: bool = True
    unified_learning_runtime_min_samples: int = 20
    unified_learning_runtime_max_abs_score_delta: int = 6
    unified_learning_rank_enabled: bool = True
    unified_learning_rank_paper_only: bool = True
    unified_learning_rank_min_samples: int = 20
    unified_learning_rank_max_bonus_pct: float = 0.08

    # Legacy/backward compatibility names (deprecated; do not use for sizing)
    max_risk_cap_acct: float = 0.0
    max_risk_cap_pln: float = max_risk_cap_acct

    sma_fast: int = 20
    sma_trend: int = 200
    adx_period: int = 14
    adx_threshold: int = 22
    adx_range_max: int = 18
    regime_switch_enabled: bool = True
    mean_reversion_enabled: bool = True
    structure_filter_enabled: bool = True
    sma_structure_fast: int = 55
    sma_structure_slow: int = 200
    # When strict no-fetch mode has short MTF history after restart,
    # allow a conservative fallback trend estimate instead of hard NEUTRAL.
    trend_short_fallback_enabled: bool = True
    trend_short_fallback_min_h4_rows: int = 3
    trend_short_fallback_min_d1_rows: int = 1

    # Adaptive exits: ATR-based SL/TP derived from current regime.
    atr_exit_enabled: bool = True
    atr_exit_use_override: bool = True
    atr_sl_mult_hot: float = 1.2
    atr_sl_mult_warm: float = 1.5
    atr_sl_mult_eco: float = 1.8
    atr_tp_mult_hot: float = 1.8
    atr_tp_mult_warm: float = 2.2
    atr_tp_mult_eco: float = 2.6
    atr_sl_min_points: int = 80
    atr_tp_min_points: int = 120

    # Open-position management: trailing + partial take-profit.
    trailing_stop_enabled: bool = True
    trailing_activation_r: float = 0.8
    trailing_atr_mult: float = 1.0
    trailing_update_retry_sec: int = 60
    partial_tp_enabled: bool = True
    partial_tp_r: float = 1.0
    partial_tp_fraction: float = 0.5
    partial_tp_retry_sec: int = 120
    sltp_modify_min_interval_sec: int = 12
    sltp_modify_max_per_sec: int = 6

    # Execution idempotency / pre-flight checks.
    signal_dedupe_enabled: bool = True
    signal_dedupe_ttl_sec: int = 900
    use_order_check: bool = True
    execution_queue_enabled: bool = True
    execution_queue_maxsize: int = 256
    execution_queue_submit_timeout_sec: int = 20
    execution_queue_backpressure_enabled: bool = True
    execution_queue_backpressure_high_watermark: float = 0.85
    execution_queue_backpressure_warn_interval_sec: int = 30
    execution_queue_wait_warn_ms: int = 1000
    pending_reconcile_poll_sec: int = 60
    pending_reconcile_force_poll_sec: int = 20

    # Position lifecycle guard (scalp discipline): prevent stale multi-hour holds.
    position_time_stop_enabled: bool = True
    position_time_stop_only_magic: bool = True
    position_time_stop_hot_min: int = 45
    position_time_stop_warm_min: int = 120
    position_time_stop_eco_min: int = 240
    position_time_stop_retry_sec: int = 120
    position_time_stop_deviation_points: int = 30

    # --- Rollover (NY 17:00) ---
    rollover_block_minutes_before: int = 30
    rollover_block_minutes_after: int = 15
    force_close_before_rollover_min: int = 5

    # --- Throttle zleceń ---
    # Allows frequent scalps while keeping deterministic caps.
    min_seconds_between_orders: float = 1.0
    max_orders_per_minute: int = 6
    max_orders_per_hour: int = 120

    # --- Paper/live ---
    paper_live_hours_required: int = 72
    allow_live_trading_override: bool = False

    # --- DB/Log ---
    db_filename: str = "decision_events.sqlite"

    # --- Cache/TTL ---
    trend_cache_ttl_sec = 3600
    symbol_info_cache_ttl_sec = 6 * 3600
    deals_poll_interval_sec = 600   # 10 min, bo to SYS request
    runtime_metrics_interval_sec = 600  # periodic metrics snapshot (10 min)

    # --- Scheduler ---

    # --- Pobór M5 (PRICE) ---

    # --- Pobór tick (PRICE) ---
    # tick pobieramy dopiero gdy:
    # - mamy sygnał i chcemy wykonać transakcję
    # - musimy zamknąć pozycję (force-close/kill)
    # (nie pobieramy ticka rutynowo co minutę dla każdego symbolu)

    # --- Pozyskanie pozycji (SYS) ---

    # --- Retry / kill ---
    close_retries: int = 5
    close_retry_delay_sec: float = 1.0
    kill_close_deviation_points: int = 50

# =============================================================================
# TIME HELPERS
# =============================================================================

# =============================================================================
# CFG COMPLETENESS (V6 OFFLINE GATE SUPPORT)
# =============================================================================

def required_cfg_missing_fields() -> list[str]:
    """
    Fields referenced by code that MUST be explicitly configured.
    Do not guess defaults here; missing/invalid fields must block execution.
    """
    required_specs = {
        "fixed_sl_points": int,
        "fixed_tp_points": int,
        "atr_period": int,
        "cooldown_stops_s": int,
        "paper_trading": bool,
    }
    missing: list[str] = []
    for k, t in required_specs.items():
        if not hasattr(CFG, k):
            missing.append(k)
            continue
        v = getattr(CFG, k)
        if v is None or not isinstance(v, t):
            missing.append(k)
    return missing

# =============================================================================
# TIME ANCHOR (V1.10)
# =============================================================================

_TIME_ANCHOR = None  # ustawiane w SafetyBot po połączeniu z MT5

# MT5 Python API returns `tick.time` / rate["time"] as an epoch-like integer, but on some brokers
# it behaves like "server-local epoch" (UTC epoch + tz offset). We must correct it to real UTC
# before feeding TimeAnchor, otherwise day-boundary and trade-windows can shift by ~1h (P0).
_MT5_SERVER_EPOCH_OFFSET_HAVE = False
_MT5_SERVER_EPOCH_OFFSET_SEC = 0
_MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS = 0.0


def _mt5_epoch_offset_snap(raw_offset_s: float, snap_s: int) -> int:
    snap = max(1, int(snap_s))
    return int(round(float(raw_offset_s) / float(snap)) * snap)


def _maybe_update_mt5_server_epoch_offset(epoch_s: int, source: str, max_age_s: int) -> None:
    """Best-effort detection of MT5 server-epoch offset vs true UTC epoch.

    We only attempt this using timestamps that are expected to be close to "now" (tick/M1/M5),
    otherwise bar age would dominate the estimate.
    """
    global _MT5_SERVER_EPOCH_OFFSET_HAVE, _MT5_SERVER_EPOCH_OFFSET_SEC, _MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS
    try:
        now_ts = float(time.time())
        raw = float(int(epoch_s)) - now_ts

        # If the provided epoch is expected to be close to now, then `raw` should be roughly:
        #   raw ~= server_tz_offset_seconds (+/- small network delay, +/- small bar age)
        # We treat small skews as "already UTC epoch".
        max_age = max(0, int(max_age_s))
        max_skew = int(getattr(CFG, "mt5_server_epoch_max_skew_sec", 120))
        if abs(raw) <= float(max_skew + max_age):
            snapped = 0
        else:
            snap_s = int(getattr(CFG, "mt5_server_epoch_offset_snap_sec", 60))
            snapped = _mt5_epoch_offset_snap(raw, snap_s=snap_s)

        # Sanity clamp: if absurd, ignore.
        max_abs = int(getattr(CFG, "mt5_server_epoch_max_offset_abs_sec", 14 * 3600))
        if abs(int(snapped)) > max_abs:
            return

        if (not _MT5_SERVER_EPOCH_OFFSET_HAVE) or (int(snapped) != int(_MT5_SERVER_EPOCH_OFFSET_SEC)):
            _MT5_SERVER_EPOCH_OFFSET_HAVE = True
            _MT5_SERVER_EPOCH_OFFSET_SEC = int(snapped)
            # Rate-limit logs in case of flapping clocks.
            now = float(time.time())
            if (now - float(_MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS)) >= 60.0:
                _MT5_SERVER_EPOCH_OFFSET_LAST_LOG_TS = now
                logging.warning(
                    "MT5_SERVER_EPOCH_OFFSET source=%s raw=%.2f snapped=%s max_age_s=%s",
                    str(source),
                    float(raw),
                    int(snapped),
                    int(max_age),
                )
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)


def mt5_epoch_to_utc_dt(epoch_s: int) -> dt.datetime:
    """Convert MT5 epoch-like seconds to real UTC datetime using detected server offset (best-effort)."""
    try:
        off = int(_MT5_SERVER_EPOCH_OFFSET_SEC) if bool(_MT5_SERVER_EPOCH_OFFSET_HAVE) else 0
        return dt.datetime.fromtimestamp(int(epoch_s) - off, tz=UTC)
    except Exception:
        return dt.datetime.fromtimestamp(int(epoch_s), tz=UTC)


class TimeAnchor:
    """Zegar oparty o czas serwera (tick/bar) + monotonic() jako nośnik między synchronizacjami.
    Chroni rollover/NY-day przed dryftem czasu systemowego i problemami DST.
    """
    def __init__(self):
        self._have = False
        self._server_utc: Optional[dt.datetime] = None
        self._mono: float = 0.0
        self._last_sync_mono: float = 0.0

    def update(self, server_utc: dt.datetime) -> None:
        if server_utc is None:
            return
        if server_utc.tzinfo is None:
            server_utc = server_utc.replace(tzinfo=UTC)
        else:
            server_utc = server_utc.astimezone(UTC)

        now_mono = time.monotonic()
        if self._have and self._server_utc is not None:
            est_now = self._server_utc + dt.timedelta(seconds=float(now_mono - self._mono))
            max_back_s = max(0, int(getattr(CFG, "time_anchor_max_backward_sec", 120)))
            if max_back_s > 0:
                min_allowed = est_now - dt.timedelta(seconds=float(max_back_s))
                if server_utc < min_allowed:
                    logging.warning(
                        f"TIME_ANCHOR_STALE_UPDATE_SKIP new={server_utc.isoformat()} "
                        f"est={est_now.isoformat()} max_back_s={max_back_s}"
                    )
                    return

        self._server_utc = server_utc
        self._mono = now_mono
        self._last_sync_mono = self._mono
        self._have = True

    def now_utc(self) -> dt.datetime:
        if not self._have or self._server_utc is None:
            return dt.datetime.now(UTC)
        delta = time.monotonic() - self._mono
        return self._server_utc + dt.timedelta(seconds=float(delta))

    def server_now_utc(self) -> dt.datetime:
        """Compatibility alias used by decision-event metadata paths."""
        return self.now_utc()

    def sync_due(self) -> bool:
        if not self._have:
            return True
        return (time.monotonic() - self._last_sync_mono) >= float(CFG.time_anchor_sync_sec)

def now_utc() -> dt.datetime:
    if _TIME_ANCHOR is not None:
        try:
            return _TIME_ANCHOR.now_utc()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
    return dt.datetime.now(UTC)

def now_ny() -> dt.datetime:
    return now_utc().astimezone(TZ_NY)

def now_pl() -> dt.datetime:
    return now_utc().astimezone(TZ_PL)

def ny_day_hour_key(ts_utc: Optional[dt.datetime] = None) -> Tuple[str, int]:
    if ts_utc is None:
        ts_utc = now_utc()
    ny = ts_utc.astimezone(TZ_NY)
    return ny.strftime("%Y-%m-%d"), int(ny.hour)

def utc_day_key(ts_utc: Optional[dt.datetime] = None) -> str:
    """Calendar day key in UTC."""
    if ts_utc is None:
        ts_utc = now_utc()
    u = ts_utc.astimezone(UTC)
    return u.strftime("%Y-%m-%d")

def pl_day_key(ts_utc: Optional[dt.datetime] = None) -> str:
    """Calendar day key in Europe/Warsaw."""
    if ts_utc is None:
        ts_utc = now_utc()
    p = ts_utc.astimezone(TZ_PL)
    return p.strftime("%Y-%m-%d")

# =============================================================================
# TRADE WINDOWS (P0): 2 okna czasowe + bufor domknięcia
# =============================================================================

def _in_window(local_now: dt.datetime, start_hm: Tuple[int, int], end_hm: Tuple[int, int]) -> bool:
    s_h, s_m = int(start_hm[0]), int(start_hm[1])
    e_h, e_m = int(end_hm[0]), int(end_hm[1])
    start = local_now.replace(hour=s_h, minute=s_m, second=0, microsecond=0)
    end = local_now.replace(hour=e_h, minute=e_m, second=0, microsecond=0)
    if (s_h, s_m) == (e_h, e_m):
        return True
    if end >= start:
        return bool(start <= local_now <= end)
    # Overnight window support (e.g. 22:00-02:00).
    end = end + dt.timedelta(days=1)
    ref = local_now
    if ref < start:
        ref = ref + dt.timedelta(days=1)
    return bool(start <= ref <= end)


def group_market_session_open(grp: str, now_dt: Optional[dt.datetime] = None) -> bool:
    """
    Lightweight market-calendar guard for trade-window activation.

    We keep this intentionally conservative:
    - CRYPTO remains always-on
    - FX/METAL are considered closed from Friday 17:00 NY until Sunday 17:00 NY
    - INDEX/EQUITY are considered closed on Saturday/Sunday

    This guard exists to prevent runtime from treating clock-based windows as ACTIVE
    when the underlying market is actually closed and only stale snapshots are left.
    """
    ref = (now_dt or now_utc()).astimezone(UTC)
    ny = ref.astimezone(TZ_NY)
    grp_u = _group_key(grp)

    if grp_u == "CRYPTO":
        return True

    wd = int(ny.weekday())
    hm = (int(ny.hour), int(ny.minute))

    try:
        reopen_cfg = getattr(CFG, "reopen_guard_ny_start_hm", (17, 0))
        reopen_hm = (int(reopen_cfg[0]), int(reopen_cfg[1]))
    except Exception:
        reopen_hm = (17, 0)

    if grp_u in {"FX", "METAL"}:
        if wd == 5:
            return False
        if wd == 6 and hm < reopen_hm:
            return False
        if wd == 4 and hm >= reopen_hm:
            return False
        return True

    if grp_u in {"INDEX", "EQUITY"}:
        return wd not in (5, 6)

    return True


def trade_window_ctx(now_dt: Optional[dt.datetime] = None) -> Dict[str, object]:
    """Return current trade-window context.

    phase:
      - ACTIVE: allowed to open new entries for the active group
      - CLOSEOUT: within buffer to window end; only closing/cancel allowed (no entries)
      - OFF: outside windows; no PRICE polling, only minimal SYS safety reconciliation
    """
    if now_dt is None:
        now_dt = now_utc()

    # Default: OFF
    ctx: Dict[str, object] = {
        "phase": "OFF",
        "window_id": None,
        "group": None,
        "anchor_tz": None,
        "pl_now": now_dt.astimezone(TZ_PL),
        "anchor_now": None,
        "entry_allowed": False,
        "mt5_allowed": False,
        "closeout_only": False,
    }

    try:
        tw = getattr(CFG, "trade_windows", {}) or {}
        buf_min = int(getattr(CFG, "trade_closeout_buffer_min", 15))
    except Exception:
        tw = {}
        buf_min = 15

    # Deterministic order: iterate over configured windows
    for wid in sorted(tw.keys()):
        w = tw.get(wid)
        if not isinstance(w, dict) or not w:
            continue
        try:
            tz = ZoneInfo(str(w.get("anchor_tz") or "Europe/Warsaw"))
        except Exception:
            tz = TZ_PL
        local_now = now_dt.astimezone(tz)
        try:
            start_hm = tuple(w.get("start_hm") or (0, 0))
            end_hm = tuple(w.get("end_hm") or (0, 0))
        except Exception:
            continue
        if _in_window(local_now, start_hm, end_hm):
            grp = str(w.get("group") or "").upper()
            if grp and (not group_market_session_open(grp, now_dt)):
                continue
            # Closeout buffer:
            # For overnight windows (e.g. 23:00-09:00) the "end" moment is on the next day.
            # We must compute end_dt robustly, otherwise the whole overnight window becomes CLOSEOUT.
            s_h, s_m = int(start_hm[0]), int(start_hm[1])
            e_h, e_m = int(end_hm[0]), int(end_hm[1])
            if (s_h, s_m) == (e_h, e_m):
                # Always-on: there is no meaningful "end", so entries remain allowed.
                in_closeout = False
            else:
                overnight = bool((e_h, e_m) < (s_h, s_m))
                start_dt = local_now.replace(hour=s_h, minute=s_m, second=0, microsecond=0)
                if overnight and (local_now.hour, local_now.minute) < (e_h, e_m):
                    # After-midnight part: start happened "yesterday".
                    start_dt = start_dt - dt.timedelta(days=1)
                end_dt = start_dt.replace(hour=e_h, minute=e_m, second=0, microsecond=0)
                if overnight:
                    end_dt = end_dt + dt.timedelta(days=1)
                closeout_start = end_dt - dt.timedelta(minutes=int(buf_min))
                in_closeout = bool(local_now >= closeout_start)
            ctx.update({
                "phase": "CLOSEOUT" if in_closeout else "ACTIVE",
                "window_id": wid,
                "group": grp,
                "anchor_tz": str(w.get("anchor_tz") or "Europe/Warsaw"),
                "anchor_now": local_now,
                "entry_allowed": (not in_closeout),
                "mt5_allowed": True,
                "closeout_only": bool(in_closeout),
            })
            return ctx

    return ctx


def trade_window_next_ctx(
    now_dt: Optional[dt.datetime] = None,
    *,
    trade_windows: Optional[Dict[str, Dict[str, object]]] = None,
) -> Optional[Dict[str, object]]:
    """Return the next scheduled trade-window start (UTC), based on repeating daily windows.

    Notes:
    - Deterministic: ties are broken by window_id (lexicographic).
    - "Always-on" windows (start==end) are ignored for "next start" calculation.
    - Overnight windows are supported (end < start in local anchor time).
    """
    if now_dt is None:
        now_dt = now_utc()
    if trade_windows is None:
        try:
            trade_windows = getattr(CFG, "trade_windows", {}) or {}
        except Exception:
            trade_windows = {}

    best: Optional[Tuple[dt.datetime, str, Dict[str, object]]] = None  # (start_utc, window_id, ctx)
    for wid in sorted(trade_windows.keys()):
        w = trade_windows.get(wid)
        if not isinstance(w, dict) or not w:
            continue
        try:
            tz = ZoneInfo(str(w.get("anchor_tz") or "Europe/Warsaw"))
        except Exception:
            tz = TZ_PL
        local_now = now_dt.astimezone(tz)
        try:
            start_hm = tuple(w.get("start_hm") or (0, 0))
            end_hm = tuple(w.get("end_hm") or (0, 0))
        except Exception:
            continue
        s_h, s_m = int(start_hm[0]), int(start_hm[1])
        e_h, e_m = int(end_hm[0]), int(end_hm[1])
        if (s_h, s_m) == (e_h, e_m):
            # Always-on windows have no meaningful "next start".
            continue
        start_today = local_now.replace(hour=s_h, minute=s_m, second=0, microsecond=0)
        overnight = bool((e_h, e_m) < (s_h, s_m))

        active = _in_window(local_now, (s_h, s_m), (e_h, e_m))
        if active and overnight and local_now < start_today:
            # Window started "yesterday"; next occurrence starts today.
            next_start_local = start_today
        elif active:
            next_start_local = start_today + dt.timedelta(days=1)
        else:
            if local_now < start_today:
                next_start_local = start_today
            else:
                next_start_local = start_today + dt.timedelta(days=1)

        start_utc = next_start_local.astimezone(UTC)
        if best is None or start_utc < best[0] or (start_utc == best[0] and wid < best[1]):
            minutes_to = max(0.0, (start_utc - now_dt).total_seconds() / 60.0)
            ctx = {
                "window_id": wid,
                "group": str(w.get("group") or "").upper(),
                "anchor_tz": str(w.get("anchor_tz") or "Europe/Warsaw"),
                "anchor_start": next_start_local,
                "start_utc": start_utc,
                "minutes_to_start": float(minutes_to),
            }
            best = (start_utc, wid, ctx)

    return best[2] if best is not None else None


def fx_rotation_bucket(
    symbols: List[str],
    *,
    now_ts: Optional[float] = None,
    bucket_size: int = 4,
    period_sec: int = 180,
) -> Tuple[int, List[str], int]:
    """Deterministically bucket symbols for rotation.

    Returns: (bucket_index, bucket_symbols, bucket_count)
    """
    if now_ts is None:
        now_ts = time.time()
    syms = sorted([str(s or "").strip() for s in symbols if str(s or "").strip()])
    if not syms:
        return 0, [], 0
    bsz = max(1, int(bucket_size))
    period = max(1, int(period_sec))
    buckets: List[List[str]] = [syms[i : i + bsz] for i in range(0, len(syms), bsz)]
    bcount = int(len(buckets))
    idx = int(int(now_ts) // int(period)) % bcount
    return int(idx), list(buckets[idx]), bcount

def pl_day_start_utc_ts(ts_utc: Optional[dt.datetime] = None) -> int:
    """Start of PL day (00:00 Europe/Warsaw) expressed as UTC epoch seconds."""
    if ts_utc is None:
        ts_utc = now_utc()
    p = ts_utc.astimezone(TZ_PL)
    start_pl = p.replace(hour=0, minute=0, second=0, microsecond=0)
    start_utc = start_pl.astimezone(UTC)
    return int(start_utc.timestamp())


def _parse_hhmm(value: Any, default_hour: int = 17, default_minute: int = 0) -> Tuple[int, int]:
    text = str(value or "").strip()
    if not text:
        return int(default_hour), int(default_minute)
    parts = text.split(":", 1)
    if len(parts) != 2:
        return int(default_hour), int(default_minute)
    try:
        hour = int(parts[0])
        minute = int(parts[1])
    except Exception:
        return int(default_hour), int(default_minute)
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        return int(default_hour), int(default_minute)
    return int(hour), int(minute)


def third_friday_date(year: int, month: int) -> dt.date:
    if month < 1 or month > 12:
        raise ValueError(f"invalid month: {month}")
    first = dt.date(int(year), int(month), 1)
    # Monday=0 ... Friday=4
    days_to_first_friday = (4 - int(first.weekday())) % 7
    return first + dt.timedelta(days=int(days_to_first_friday + 14))


def quarterly_rollover_date(year: int, month: int, offset_days: int = -2) -> dt.date:
    third_friday = third_friday_date(int(year), int(month))
    return third_friday + dt.timedelta(days=int(offset_days))


def quarterly_rollover_dates(
    year: int,
    months: Optional[List[int]] = None,
    offset_days: int = -2,
) -> Dict[int, dt.date]:
    if not months:
        months = [3, 6, 9, 12]
    out: Dict[int, dt.date] = {}
    for raw in months:
        try:
            mm = int(raw)
        except Exception:
            continue
        if mm < 1 or mm > 12:
            continue
        out[mm] = quarterly_rollover_date(int(year), int(mm), offset_days=int(offset_days))
    return out


def position_open_ts_utc(pos: Any) -> Optional[int]:
    """Best-effort extraction of MT5 position open timestamp (UTC epoch seconds)."""
    now_ts = int(time.time())
    candidates: List[int] = []
    # Use open-time fields first. update-time fields can move on modify/trailing,
    # which would artificially "rejuvenate" position age and block time-stop exits.
    open_fields = (
        ("time", 1),
        ("time_msc", 1000),
    )
    update_fields = (
        ("time_update", 1),
        ("time_update_msc", 1000),
    )

    fields = open_fields + update_fields
    for field, div in fields:
        raw = getattr(pos, field, None)
        if raw is None:
            continue
        try:
            ts = int(float(raw))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            continue
        if div > 1:
            ts //= int(div)
        if ts > 0:
            candidates.append(int(ts))
    if not candidates:
        return None
    valid = [t for t in candidates if (t >= 946684800 and t <= now_ts + 300)]
    if not valid:
        return None

    # Prefer timestamps coming from open fields.
    open_candidates: List[int] = []
    for field, div in open_fields:
        raw = getattr(pos, field, None)
        if raw is None:
            continue
        try:
            ts = int(float(raw))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            continue
        if div > 1:
            ts //= int(div)
        if ts >= 946684800 and ts <= now_ts + 300:
            open_candidates.append(int(ts))

    if open_candidates:
        return int(min(open_candidates))

    # Last-resort fallback for brokers/feeds without open-time fields.
    return int(min(valid))


def position_age_sec(pos: Any, now_ts: Optional[int] = None) -> Optional[int]:
    """Return position age in seconds, or None if timestamp is unavailable."""
    if now_ts is None:
        now_ts = int(time.time())
    ts_open = position_open_ts_utc(pos)
    if ts_open is None:
        return None
    return int(max(0, int(now_ts) - int(ts_open)))


def _group_key(group: Optional[str]) -> str:
    g = str(group or "").strip().upper()
    if g in {"METALS", "XAU"}:
        return "METAL"
    if g in {"INDICES"}:
        return "INDEX"
    if g in {"CRYPTOS", "CRYPTOCURRENCY", "CRYPTOCURRENCIES"}:
        return "CRYPTO"
    if g in {"EQUITIES", "STOCKS"}:
        return "EQUITY"
    return g


def _symbol_key(symbol: Optional[str]) -> str:
    s = str(symbol or "").strip()
    if not s:
        return ""
    try:
        return str(symbol_base(s)).upper()
    except Exception:
        return str(s).split(".", 1)[0].upper()


_STAGE1_ALLOWED_THRESHOLD_KEYS = {
    "spread_cap_points",
    "max_spread_points",
    "signal_score_threshold",
    "max_latency_ms",
    "min_tradeability_score",
    "min_setup_quality_score",
    "min_liquidity_score",
}

_STAGE1_THRESHOLD_INPUT_ALIASES: Dict[str, str] = {
    "spread_cap_points": "spread_cap_points",
    "max_spread_points": "spread_cap_points",
    "signal_score_threshold": "signal_score_threshold",
    "max_latency_ms": "max_latency_ms",
    "min_tradeability_score": "min_tradeability_score",
    "min_setup_quality_score": "min_setup_quality_score",
    "min_liquidity_score": "min_liquidity_score",
}

_STAGE1_OVERRIDE_KEY_ALIASES: Dict[str, str] = {
    "spread_cap_points": "spread_cap_points",
    "max_spread_points": "spread_cap_points",
    "fx_spread_cap_points": "spread_cap_points",
    "metal_spread_cap_points": "spread_cap_points",
    "signal_score_threshold": "signal_score_threshold",
    "fx_signal_score_threshold": "signal_score_threshold",
    "metal_signal_score_threshold": "signal_score_threshold",
    "max_latency_ms": "max_latency_ms",
    "bridge_trade_timeout_ms": "max_latency_ms",
    "min_tradeability_score": "min_tradeability_score",
    "min_setup_quality_score": "min_setup_quality_score",
    "min_liquidity_score": "min_liquidity_score",
}

_STAGE1_LIVE_LOCK = threading.Lock()
_STAGE1_LIVE_OVERRIDES: Dict[str, Dict[str, float]] = {}
_STAGE1_LIVE_META: Dict[str, Any] = {}


def _normalize_stage1_signal_threshold(raw: Any) -> float:
    val = float(raw)
    if 0.0 <= val <= 1.0:
        val = float(val * 100.0)
    return float(max(0.0, min(100.0, val)))


def _clamp_stage1_threshold(key: str, value: float) -> float:
    if key == "spread_cap_points":
        return float(max(0.1, min(400.0, value)))
    if key == "signal_score_threshold":
        return float(max(0.0, min(100.0, value)))
    if key == "max_latency_ms":
        return float(max(10.0, min(5000.0, value)))
    if key in {"min_tradeability_score", "min_setup_quality_score", "min_liquidity_score"}:
        return float(max(0.0, min(1.0, value)))
    return float(value)


def _parse_stage1_live_config_payload(payload: Dict[str, Any]) -> Tuple[Dict[str, Dict[str, float]], Dict[str, Any]]:
    schema = str(payload.get("schema_version") or "").strip()
    if schema != "live_config_v3":
        raise ValueError(f"STAGE1_SCHEMA_MISMATCH:{schema or 'EMPTY'}")
    instruments = payload.get("instruments")
    if not isinstance(instruments, dict):
        raise ValueError("STAGE1_INSTRUMENTS_MISSING")

    overrides: Dict[str, Dict[str, float]] = {}
    skipped_symbols: List[str] = []
    for raw_symbol, block in instruments.items():
        if not isinstance(block, dict):
            continue
        sym = _symbol_key(str(raw_symbol))
        if not sym:
            continue
        thresholds = block.get("thresholds")
        if not isinstance(thresholds, dict):
            skipped_symbols.append(sym)
            continue
        out: Dict[str, float] = {}
        for raw_key, raw_val in thresholds.items():
            k = str(raw_key or "").strip()
            if k not in _STAGE1_ALLOWED_THRESHOLD_KEYS:
                continue
            k_eff = _STAGE1_THRESHOLD_INPUT_ALIASES.get(k, k)
            try:
                num = float(raw_val)
            except Exception:
                continue
            if k_eff == "signal_score_threshold":
                num = _normalize_stage1_signal_threshold(num)
            out[k_eff] = _clamp_stage1_threshold(k_eff, num)
        if not out:
            skipped_symbols.append(sym)
            continue
        overrides[sym] = out

    meta = {
        "schema_version": schema,
        "deployment_id": str(payload.get("deployment_id") or ""),
        "generated_at": str(payload.get("generated_at") or ""),
        "source_proposal_id": str(payload.get("source_proposal_id") or ""),
        "source_proposal_hash": str(payload.get("source_proposal_hash") or ""),
        "config_hash": str(payload.get("config_hash") or ""),
        "instrument_count": int(len(instruments)),
        "loaded_symbols": int(len(overrides)),
        "skipped_symbols": skipped_symbols,
    }
    return overrides, meta


def _set_stage1_live_overrides(overrides: Dict[str, Dict[str, float]], meta: Dict[str, Any]) -> None:
    clean: Dict[str, Dict[str, float]] = {}
    for raw_symbol, row in (overrides or {}).items():
        sym = _symbol_key(raw_symbol)
        if not sym or not isinstance(row, dict):
            continue
        r: Dict[str, float] = {}
        for k, v in row.items():
            if k in _STAGE1_ALLOWED_THRESHOLD_KEYS:
                try:
                    r[k] = float(v)
                except Exception:
                    continue
        if r:
            clean[sym] = r
    with _STAGE1_LIVE_LOCK:
        _STAGE1_LIVE_OVERRIDES.clear()
        _STAGE1_LIVE_OVERRIDES.update(clean)
        _STAGE1_LIVE_META.clear()
        _STAGE1_LIVE_META.update(dict(meta or {}))
        _STAGE1_LIVE_META["applied_at_utc"] = now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _get_stage1_override_value(symbol: Optional[str], key: str) -> Optional[float]:
    sym = _symbol_key(symbol)
    if not sym:
        return None
    alias = _STAGE1_OVERRIDE_KEY_ALIASES.get(str(key or "").strip())
    if not alias:
        return None
    with _STAGE1_LIVE_LOCK:
        row = _STAGE1_LIVE_OVERRIDES.get(sym)
        if not isinstance(row, dict):
            return None
        value = row.get(alias)
    if value is None:
        return None
    try:
        return float(value)
    except Exception:
        return None


def _is_crypto_major_symbol(symbol: Optional[str]) -> bool:
    s = _symbol_key(symbol)
    return bool(s in {"BTCUSD", "ETHUSD"})


def _cfg_group_value(group: Optional[str], key: str, default: Any, symbol: Optional[str] = None) -> Any:
    try:
        override = _get_stage1_override_value(symbol, key)
        if override is not None:
            return override
        s = _symbol_key(symbol)
        if s:
            per_symbol = getattr(CFG, "per_symbol", {}) or {}
            if isinstance(per_symbol, dict):
                sym_node = per_symbol.get(s, {})
                if isinstance(sym_node, dict) and key in sym_node:
                    return sym_node.get(key, default)
        per_group = getattr(CFG, "per_group", {}) or {}
        if not isinstance(per_group, dict):
            return default
        g = _group_key(group)
        node = per_group.get(g, {})
        if not isinstance(node, dict):
            return default
        return node.get(key, default)
    except Exception:
        return default


def _cfg_group_int(group: Optional[str], key: str, default: int, symbol: Optional[str] = None) -> int:
    raw = _cfg_group_value(group, key, default, symbol=symbol)
    try:
        return int(raw)
    except Exception:
        return int(default)


def _cfg_group_float(group: Optional[str], key: str, default: float, symbol: Optional[str] = None) -> float:
    raw = _cfg_group_value(group, key, default, symbol=symbol)
    try:
        return float(raw)
    except Exception:
        return float(default)


def _cfg_group_bool(group: Optional[str], key: str, default: bool, symbol: Optional[str] = None) -> bool:
    raw = _cfg_group_value(group, key, default, symbol=symbol)
    if isinstance(raw, bool):
        return bool(raw)
    txt = str(raw).strip().lower()
    if txt in {"1", "true", "yes", "y", "on"}:
        return True
    if txt in {"0", "false", "no", "n", "off"}:
        return False
    return bool(default)


def _group_in_targets(grp: str, targets: Any) -> bool:
    g = _group_key(grp)
    vals: List[str] = []
    if isinstance(targets, (list, tuple, set)):
        for item in targets:
            k = _group_key(str(item or ""))
            if k:
                vals.append(k)
    if not vals:
        return False
    return bool(("ALL" in vals) or (g in vals))


def _cfg_group_set(key: str, fallback: Tuple[str, ...]) -> set[str]:
    raw = getattr(CFG, key, fallback)
    vals: set[str] = set()
    if isinstance(raw, (list, tuple, set)):
        for x in raw:
            g = _group_key(str(x or ""))
            if g:
                vals.add(g)
    return vals


def _cfg_group_map_float(key: str, grp: str, default: float) -> float:
    try:
        raw = getattr(CFG, key, {}) or {}
        if isinstance(raw, dict):
            val = raw.get(_group_key(grp), default)
            return float(val)
    except Exception:
        return float(default)
    return float(default)


def us_overlap_window_active(now_dt: Optional[dt.datetime] = None) -> bool:
    ref = (now_dt or now_utc()).astimezone(UTC)
    return in_window(ref, (14, 30), (16, 30))


def group_market_risk_state(grp: str, now_dt: Optional[dt.datetime] = None) -> Dict[str, Any]:
    """
    Unified market risk state by group.
    Friday risk and Sunday reopen guard can independently:
    - block new entries (close-only by group),
    - block budget borrowing,
    - dampen group priority factor.
    """
    ref = (now_dt or now_utc()).astimezone(UTC)
    ny = ref.astimezone(TZ_NY)
    grp_u = _group_key(grp)

    risk_windows_on = bool(getattr(CFG, "policy_risk_windows_enabled", True))
    if not risk_windows_on:
        return {
            "group": str(grp_u),
            "friday_risk": False,
            "reopen_guard": False,
            "entry_allowed": True,
            "borrow_blocked": False,
            "priority_factor": 1.0,
            "reason": "RISK_WINDOWS_DISABLED",
        }

    friday_targets = _cfg_group_set("friday_risk_groups", ("FX", "METAL", "INDEX", "EQUITY"))
    friday_close_only_groups = _cfg_group_set("friday_risk_close_only_groups", ("FX", "METAL"))
    reopen_targets = _cfg_group_set("reopen_guard_groups", ("FX", "METAL", "INDEX", "EQUITY"))
    reopen_close_only_groups = _cfg_group_set("reopen_guard_close_only_groups", ("FX", "METAL"))

    friday_risk = False
    reopen_guard = False
    close_only = False
    borrow_blocked = False
    priority_factor = 1.0
    reasons: List[str] = []

    friday_enabled = bool(
        _cfg_group_bool(grp_u, "friday_risk_enabled", bool(getattr(CFG, "friday_risk_enabled", True)))
    )
    friday_borrow_block = bool(
        _cfg_group_bool(grp_u, "friday_risk_borrow_block", bool(getattr(CFG, "friday_risk_borrow_block", True)))
    )
    friday_prio = float(
        max(
            0.05,
            min(
                1.80,
                _cfg_group_float(
                    grp_u,
                    "friday_risk_priority_factor",
                    float(getattr(CFG, "friday_risk_priority_factor", 0.60)),
                ),
            ),
        )
    )
    fr_start = getattr(CFG, "friday_risk_ny_start_hm", (16, 0))
    fr_end = getattr(CFG, "friday_risk_ny_end_hm", (17, 0))
    try:
        friday_start = (int(fr_start[0]), int(fr_start[1]))
        friday_end = (int(fr_end[0]), int(fr_end[1]))
    except Exception:
        friday_start, friday_end = (16, 0), (17, 0)
    if friday_enabled and grp_u in friday_targets and int(ny.weekday()) == 4:
        try:
            friday_risk = bool(in_window(ny, friday_start, friday_end))
        except Exception:
            friday_risk = False
    if friday_risk:
        reasons.append("FRIDAY_SPREAD_RISK")
        if grp_u in friday_close_only_groups:
            close_only = True
        if friday_borrow_block:
            borrow_blocked = True
        priority_factor = min(priority_factor, friday_prio)

    reopen_enabled = bool(
        _cfg_group_bool(grp_u, "reopen_guard_enabled", bool(getattr(CFG, "reopen_guard_enabled", True)))
    )
    reopen_borrow_block = bool(
        _cfg_group_bool(grp_u, "reopen_guard_borrow_block", bool(getattr(CFG, "reopen_guard_borrow_block", True)))
    )
    reopen_prio = float(
        max(
            0.05,
            min(
                1.80,
                _cfg_group_float(
                    grp_u,
                    "reopen_guard_priority_factor",
                    float(getattr(CFG, "reopen_guard_priority_factor", 0.70)),
                ),
            ),
        )
    )
    reopen_minutes = int(
        max(1, _cfg_group_int(grp_u, "reopen_guard_minutes", int(getattr(CFG, "reopen_guard_minutes", 45))))
    )

    re_start = getattr(CFG, "reopen_guard_ny_start_hm", (17, 0))
    try:
        reopen_hm = (int(re_start[0]), int(re_start[1]))
    except Exception:
        reopen_hm = (17, 0)
    if reopen_enabled and grp_u in reopen_targets and int(ny.weekday()) == 6:
        try:
            start = ny.replace(hour=int(reopen_hm[0]), minute=int(reopen_hm[1]), second=0, microsecond=0)
            end = start + dt.timedelta(minutes=int(reopen_minutes))
            reopen_guard = bool(start <= ny <= end)
        except Exception:
            reopen_guard = False
    if reopen_guard:
        reasons.append("REOPEN_GAP_GUARD")
        if grp_u in reopen_close_only_groups:
            close_only = True
        if reopen_borrow_block:
            borrow_blocked = True
        priority_factor = min(priority_factor, reopen_prio)

    return {
        "group": str(grp_u),
        "friday_risk": bool(friday_risk),
        "reopen_guard": bool(reopen_guard),
        "entry_allowed": bool(not close_only),
        "borrow_blocked": bool(borrow_blocked),
        "priority_factor": float(max(0.05, min(1.80, priority_factor))),
        "reason": ",".join(reasons) if reasons else "NONE",
    }


def group_window_weight(grp: str, symbol: str, now_dt: Optional[dt.datetime] = None) -> float:
    ref = (now_dt or now_utc()).astimezone(UTC)
    ny = ref.astimezone(TZ_NY)
    pl = ref.astimezone(TZ_PL)
    utc_local = ref.astimezone(UTC)
    grp_u = _group_key(grp)

    if grp_u == "FX":
        if in_window(ny, (8, 0), (12, 0)):
            return 1.00
        if in_window(ny, (3, 0), (8, 0)) or in_window(ny, (12, 0), (16, 0)):
            return 0.60
        return 0.25

    if grp_u == "METAL":
        if in_window(ny, (7, 0), (13, 0)):
            return 1.00
        if in_window(ny, (3, 0), (7, 0)) or in_window(ny, (13, 0), (16, 30)):
            return 0.60
        return 0.25

    if grp_u == "INDEX":
        prof = index_profile(symbol)
        if prof == "EU":
            if in_window(pl, (9, 0), (12, 0)):
                return 0.90
            if in_window(pl, (12, 0), (15, 0)):
                return 0.60
            if in_window(pl, (15, 0), (17, 35)):
                return 1.00
            return 0.25
        if prof == "US":
            if in_window(ny, (9, 30), (11, 0)) or in_window(ny, (15, 0), (16, 0)):
                return 1.00
            if in_window(ny, (11, 0), (15, 0)):
                return 0.60
            return 0.25
        return 0.35

    if grp_u == "CRYPTO":
        if in_window(utc_local, (21, 0), (7, 0)):
            return 1.00
        if in_window(utc_local, (7, 0), (14, 30)):
            return 0.70
        if in_window(utc_local, (14, 30), (21, 0)):
            return 0.45
        return 0.55

    if grp_u == "EQUITY":
        if in_window(ny, (9, 30), (11, 0)) or in_window(ny, (15, 0), (16, 0)):
            return 1.00
        if in_window(ny, (11, 0), (15, 0)):
            return 0.65
        if in_window(ny, (4, 0), (9, 30)) or in_window(ny, (16, 0), (20, 0)):
            return 0.35
        return 0.15

    return 0.20


def effective_group_priority_factor(grp: str, now_dt: Optional[dt.datetime] = None) -> float:
    ref = (now_dt or now_utc()).astimezone(UTC)
    grp_u = _group_key(grp)
    base = _cfg_group_map_float("group_priority_boost", grp_u, 1.0)
    overlap_mul = 1.0
    if bool(getattr(CFG, "policy_overlap_arbitration_enabled", True)) and us_overlap_window_active(ref):
        overlap_mul = _cfg_group_map_float("group_overlap_priority_factor", grp_u, 1.0)
    risk = group_market_risk_state(grp_u, ref)
    factor = float(base) * float(overlap_mul) * float(risk.get("priority_factor", 1.0))
    lo = float(getattr(CFG, "group_priority_min_factor", 0.40) or 0.40)
    hi = float(getattr(CFG, "group_priority_max_factor", 1.80) or 1.80)
    lo = max(0.05, min(lo, hi))
    hi = max(lo, hi)
    return max(lo, min(hi, factor))


def risk_window_skip_decision(
    *,
    symbol: str,
    group: str,
    risk_state: Dict[str, Any],
    is_open_symbol: bool,
    use_risk_windows_hard: bool,
    policy_risk_windows_enabled: bool,
) -> Tuple[bool, str]:
    """Return (skip_entry, log_tag) for risk-window admission policy."""
    if bool(is_open_symbol):
        return False, ""
    if bool(risk_state.get("entry_allowed", True)):
        return False, ""
    if bool(use_risk_windows_hard):
        return True, "ENTRY_SKIP_RISK_WINDOW"
    if bool(policy_risk_windows_enabled):
        return False, "ENTRY_SKIP_RISK_WINDOW_SHADOW"
    return False, ""


def position_time_stop_minutes_for_mode(mode: str, grp: Optional[str] = None, symbol: Optional[str] = None) -> int:
    m = str(mode).upper()
    if m == "HOT":
        base = int(max(0, int(getattr(CFG, "position_time_stop_hot_min", 0))))
        return int(max(0, _cfg_group_int(grp, "position_time_stop_hot_min", base, symbol=symbol)))
    if m == "WARM":
        base = int(max(0, int(getattr(CFG, "position_time_stop_warm_min", 0))))
        return int(max(0, _cfg_group_int(grp, "position_time_stop_warm_min", base, symbol=symbol)))
    base = int(max(0, int(getattr(CFG, "position_time_stop_eco_min", 0))))
    return int(max(0, _cfg_group_int(grp, "position_time_stop_eco_min", base, symbol=symbol)))


def resolve_adx_regime(adx_value: float, trend_min: float, range_max: float) -> str:
    """Return TREND / RANGE / TRANSITION for deterministic entry routing."""
    try:
        adx = float(adx_value)
        trend_thr = float(trend_min)
        range_thr = float(range_max)
    except Exception:
        return "TRANSITION"
    if not np.isfinite(adx):
        return "TRANSITION"
    if range_thr > trend_thr:
        range_thr = trend_thr
    if adx >= trend_thr:
        return "TREND"
    if adx <= range_thr:
        return "RANGE"
    return "TRANSITION"


def adaptive_exit_points(
    mode: str,
    point: float,
    atr_value: Optional[float],
    grp: Optional[str] = None,
    symbol: Optional[str] = None,
) -> Tuple[int, int]:
    """Compute SL/TP in points using fixed or ATR-based exits."""
    sl_pts = int(
        max(1, _cfg_group_int(grp, "fixed_sl_points", int(getattr(CFG, "fixed_sl_points", 1) or 1), symbol=symbol))
    )
    tp_pts = int(
        max(1, _cfg_group_int(grp, "fixed_tp_points", int(getattr(CFG, "fixed_tp_points", 1) or 1), symbol=symbol))
    )
    if (not bool(getattr(CFG, "atr_exit_enabled", True))) or point <= 0.0 or atr_value is None:
        return sl_pts, tp_pts
    try:
        atr = float(atr_value)
    except Exception:
        return sl_pts, tp_pts
    if (not np.isfinite(atr)) or atr <= 0.0:
        return sl_pts, tp_pts

    m = str(mode).upper()
    if m == "HOT":
        sl_mult = _cfg_group_float(grp, "atr_sl_mult_hot", float(getattr(CFG, "atr_sl_mult_hot", 1.2)), symbol=symbol)
        tp_mult = _cfg_group_float(grp, "atr_tp_mult_hot", float(getattr(CFG, "atr_tp_mult_hot", 1.8)), symbol=symbol)
    elif m == "WARM":
        sl_mult = _cfg_group_float(grp, "atr_sl_mult_warm", float(getattr(CFG, "atr_sl_mult_warm", 1.5)), symbol=symbol)
        tp_mult = _cfg_group_float(grp, "atr_tp_mult_warm", float(getattr(CFG, "atr_tp_mult_warm", 2.2)), symbol=symbol)
    else:
        sl_mult = _cfg_group_float(grp, "atr_sl_mult_eco", float(getattr(CFG, "atr_sl_mult_eco", 1.8)), symbol=symbol)
        tp_mult = _cfg_group_float(grp, "atr_tp_mult_eco", float(getattr(CFG, "atr_tp_mult_eco", 2.6)), symbol=symbol)

    atr_pts = float(atr) / float(point)
    if (not np.isfinite(atr_pts)) or atr_pts <= 0.0:
        return sl_pts, tp_pts

    calc_sl = int(max(1, round(atr_pts * sl_mult)))
    calc_tp = int(max(1, round(atr_pts * tp_mult)))
    min_sl = int(
        max(1, _cfg_group_int(grp, "atr_sl_min_points", int(getattr(CFG, "atr_sl_min_points", 1) or 1), symbol=symbol))
    )
    min_tp = int(
        max(1, _cfg_group_int(grp, "atr_tp_min_points", int(getattr(CFG, "atr_tp_min_points", 1) or 1), symbol=symbol))
    )

    if bool(getattr(CFG, "atr_exit_use_override", True)):
        sl_pts = max(min_sl, calc_sl)
        tp_pts = max(min_tp, calc_tp)
    else:
        sl_pts = max(sl_pts, min_sl, calc_sl)
        tp_pts = max(tp_pts, min_tp, calc_tp)
    return int(sl_pts), int(tp_pts)


def select_entry_signal(
    *,
    trend_h4: str,
    structure_h4: str,
    regime: str,
    close_price: float,
    open_price: float,
    sma_fast_value: float,
    structure_filter_enabled: bool,
    mean_reversion_enabled: bool,
    mode: str = "HOT",
) -> Tuple[Optional[str], str]:
    """Return (signal, reason_code) for trend/range routing."""
    trend = str(trend_h4).upper()
    structure = str(structure_h4).upper()
    if structure_filter_enabled and structure in {"BUY", "SELL"} and structure != trend:
        return None, "STRUCTURE_MISMATCH"

    reg = str(regime).upper()
    if reg == "TREND":
        strict_buy = bool(trend == "BUY" and close_price > sma_fast_value and close_price > open_price)
        strict_sell = bool(trend == "SELL" and close_price < sma_fast_value and close_price < open_price)
        if strict_buy:
            return "BUY", "TREND_BREAK_CONTINUATION"
        if strict_sell:
            return "SELL", "TREND_BREAK_CONTINUATION"
        # WARM/ECO: keep trend direction, but allow one of the two short-term confirmations.
        # This reduces missed entries without disabling trend discipline entirely.
        m = str(mode).upper()
        if m in {"WARM", "ECO"}:
            if trend == "BUY" and (close_price > sma_fast_value or close_price > open_price):
                return "BUY", "TREND_RELAXED_CONTINUATION"
            if trend == "SELL" and (close_price < sma_fast_value or close_price < open_price):
                return "SELL", "TREND_RELAXED_CONTINUATION"
        return None, "NO_TREND_SIGNAL"

    if reg == "RANGE" and mean_reversion_enabled:
        # Range module: fade short-term stretch but keep H4 bias.
        if trend == "BUY" and close_price < sma_fast_value and close_price < open_price:
            return "BUY", "RANGE_PULLBACK_BUY"
        if trend == "SELL" and close_price > sma_fast_value and close_price > open_price:
            return "SELL", "RANGE_PULLBACK_SELL"
        return None, "NO_RANGE_SIGNAL"

    if reg == "RANGE":
        return None, "RANGE_DISABLED"
    # ECO fallback for transitional ADX regime:
    # keep directionality from H4 trend, require at least one short-term continuation cue.
    # This increases entry opportunity without removing trend anchoring.
    if reg == "TRANSITION":
        m = str(mode).upper()
        if m == "ECO":
            if trend == "BUY" and close_price > sma_fast_value:
                return "BUY", "ADX_TRANSITION_ECO_CONTINUATION"
            if trend == "SELL" and close_price < sma_fast_value:
                return "SELL", "ADX_TRANSITION_ECO_CONTINUATION"
    return None, "ADX_TRANSITION"


def fx_spread_cap_points(symbol: str, grp: Optional[str] = "FX") -> float:
    """Per-symbol hard spread cap in points for FX scoring gate."""
    default_cap = float(max(1.0, float(getattr(CFG, "fx_spread_cap_points_default", 24.0) or 24.0)))
    cap = _cfg_group_float(grp, "fx_spread_cap_points", default_cap, symbol=symbol)
    try:
        return float(max(1.0, float(cap)))
    except Exception:
        return default_cap


def fx_score_threshold_for_mode(mode: str, symbol: Optional[str] = None) -> int:
    base_default = int(max(0, int(getattr(CFG, "fx_signal_score_threshold", 74) or 74)))
    base_thr = int(max(0, _cfg_group_int("FX", "fx_signal_score_threshold", base_default, symbol=symbol)))
    if bool(getattr(CFG, "fx_signal_score_hot_relaxed_enabled", True)) and str(mode).upper() == "HOT":
        hot_default = int(max(0, int(getattr(CFG, "fx_signal_score_hot_relaxed_threshold", 68) or 68)))
        hot_thr = int(max(0, _cfg_group_int("FX", "fx_signal_score_hot_relaxed_threshold", hot_default, symbol=symbol)))
        return int(min(base_thr, hot_thr))
    return int(base_thr)


def window_progress_ratio(
    local_dt: dt.datetime,
    start_hm: Tuple[int, int],
    end_hm: Tuple[int, int],
) -> float:
    """Return elapsed ratio [0..1] inside a same-day time window."""
    s = local_dt.replace(hour=int(start_hm[0]), minute=int(start_hm[1]), second=0, microsecond=0)
    e = local_dt.replace(hour=int(end_hm[0]), minute=int(end_hm[1]), second=0, microsecond=0)
    total_s = max(1.0, float((e - s).total_seconds()))
    elapsed_s = float((local_dt - s).total_seconds())
    if elapsed_s <= 0.0:
        return 0.0
    if elapsed_s >= total_s:
        return 1.0
    return float(elapsed_s / total_s)


def _session_pacing_limit_ratio(
    progress: float,
    phase1_progress: float,
    phase2_progress: float,
    phase1_ratio: float,
    phase2_ratio: float,
) -> float:
    p = float(max(0.0, min(1.0, float(progress))))
    p1 = float(max(0.0, min(1.0, float(phase1_progress))))
    p2 = float(max(p1, min(1.0, float(phase2_progress))))
    r1 = float(max(0.0, min(1.0, float(phase1_ratio))))
    r2 = float(max(r1, min(1.0, float(phase2_ratio))))
    if p <= p1:
        return r1
    if p <= p2:
        return r2
    return 1.0


def fx_pacing_limit_ratio(progress: float) -> float:
    """Piecewise ORDER-budget pacing target for FX_AM session."""
    return float(
        _session_pacing_limit_ratio(
            progress=progress,
            phase1_progress=float(getattr(CFG, "fx_budget_pacing_phase1_progress", 0.25) or 0.25),
            phase2_progress=float(getattr(CFG, "fx_budget_pacing_phase2_progress", 0.6667) or 0.6667),
            phase1_ratio=float(getattr(CFG, "fx_budget_pacing_phase1_ratio", 0.25) or 0.25),
            phase2_ratio=float(getattr(CFG, "fx_budget_pacing_phase2_ratio", 0.70) or 0.70),
        )
    )


def fx_budget_pacing_allows_entry(
    gov: "RequestGovernor",
    db: "Persistence",
    now_dt: Optional[dt.datetime] = None,
) -> Tuple[bool, Dict[str, float]]:
    """
    Gate entries when ORDER budget for FX is consumed too quickly early in FX_AM.
    """
    if not bool(getattr(CFG, "fx_budget_pacing_enabled", True)):
        return True, {"enabled": 0.0}
    if gov is None or db is None:
        return True, {"enabled": 1.0, "reason": "MISSING_STATE"}  # type: ignore[dict-item]

    now_u = now_dt if isinstance(now_dt, dt.datetime) else now_utc()
    now_pl_dt = now_u.astimezone(TZ_PL)
    win = (getattr(CFG, "trade_windows", {}) or {}).get("FX_AM", {})
    if not isinstance(win, dict):
        win = {}
    start_hm = win.get("start_hm", (9, 0))
    end_hm = win.get("end_hm", (12, 0))
    try:
        sh = (int(start_hm[0]), int(start_hm[1]))
        eh = (int(end_hm[0]), int(end_hm[1]))
    except Exception:
        sh, eh = (9, 0), (12, 0)

    progress = window_progress_ratio(now_pl_dt, sh, eh)
    try:
        borrow = int(gov.order_group_borrow_allowance("FX", now_dt=now_u))
    except TypeError:
        borrow = int(gov.order_group_borrow_allowance("FX"))
    cap = int(max(0, int(gov.order_group_cap("FX")) + int(borrow)))
    used = int(max(0, int(db.get_order_group_actions_day("FX", now_dt=now_u, emergency=False))))
    if cap <= 0:
        return False, {
            "enabled": 1.0,
            "progress": float(progress),
            "limit_ratio": 0.0,
            "slack": float(getattr(CFG, "fx_budget_pacing_slack", 0.05)),
            "used_ratio": 1.0,
            "used": float(used),
            "cap": float(cap),
            "reason": "FX_ORDER_CAP_ZERO",  # type: ignore[dict-item]
        }
    used_ratio = float(used) / float(cap)
    limit_ratio = float(fx_pacing_limit_ratio(progress))
    slack = float(max(0.0, float(getattr(CFG, "fx_budget_pacing_slack", 0.05) or 0.05)))
    ok = bool(used_ratio <= (limit_ratio + slack))
    return ok, {
        "enabled": 1.0,
        "progress": float(progress),
        "limit_ratio": float(limit_ratio),
        "slack": float(slack),
        "used_ratio": float(used_ratio),
        "used": float(used),
        "cap": float(cap),
    }


def score_fx_entry_signal(
    *,
    symbol: str,
    grp: str,
    mode: str,
    signal: str,
    signal_reason: str,
    trend_h4: str,
    structure_h4: str,
    regime: str,
    close_price: float,
    open_price: float,
    high_price: Optional[float],
    low_price: Optional[float],
    sma_fast_value: float,
    adx_value: float,
    atr_value: Optional[float],
    point: float,
    spread_points: float,
    spread_p80: float,
    execution_error_recent: int = 0,
) -> Tuple[int, Dict[str, float]]:
    """
    Deterministic FX signal scoring (0..100) for poranna sesja.
    """
    parts: Dict[str, float] = {}
    score = 0.0

    trend = str(trend_h4).upper()
    struct = str(structure_h4).upper()
    reg = str(regime).upper()
    sig = str(signal).upper()
    sig_reason = str(signal_reason).upper()
    mode_u = str(mode).upper()

    # A) Regime + direction (max 25)
    a = 0.0
    if trend in {"BUY", "SELL"}:
        a += 8.0
    if struct in {"BUY", "SELL"} and struct == trend:
        a += 7.0
    adx_thr = float(max(0.0, _cfg_group_float(grp, "adx_threshold", float(getattr(CFG, "adx_threshold", 13)), symbol=symbol)))
    adx_rng = float(max(0.0, _cfg_group_float(grp, "adx_range_max", float(getattr(CFG, "adx_range_max", 10)), symbol=symbol)))
    if reg == "TREND" and np.isfinite(adx_value) and float(adx_value) >= float(adx_thr):
        a += 10.0
    elif reg == "RANGE" and np.isfinite(adx_value) and float(adx_value) <= float(adx_rng):
        a += 8.0
    parts["A_regime_direction"] = float(min(25.0, a))
    score += parts["A_regime_direction"]

    # B) Trigger quality (max 25)
    b = 0.0
    if sig in {"BUY", "SELL"} and sig_reason not in {"", "NO_TREND_SIGNAL", "NO_RANGE_SIGNAL"}:
        b += 12.0
    body = abs(float(close_price) - float(open_price))
    rng = None
    try:
        if high_price is not None and low_price is not None:
            rng_val = abs(float(high_price) - float(low_price))
            if np.isfinite(rng_val) and rng_val > 0.0:
                rng = float(rng_val)
    except Exception:
        rng = None
    body_ratio_min = float(max(0.0, min(1.0, float(getattr(CFG, "fx_body_range_ratio_min", 0.55) or 0.55))))
    if rng is not None and rng > 0.0 and (float(body) / float(rng)) >= body_ratio_min:
        b += 6.0
    elif atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0:
        if (float(body) / float(atr_value)) >= 0.20:
            b += 6.0
    if atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0:
        impulse_min = float(max(0.0, float(getattr(CFG, "fx_impulse_atr_fraction_min", 0.05) or 0.05)))
        if float(body) >= impulse_min * float(atr_value):
            b += 7.0
    parts["B_trigger"] = float(min(25.0, b))
    score += parts["B_trigger"]

    # C) Cost & liquidity (max 20)
    c = 0.0
    spread_gate_hot = _cfg_group_float(grp, "spread_gate_hot_factor", float(getattr(CFG, "spread_gate_hot_factor", 1.25)), symbol=symbol)
    spread_gate_warm = _cfg_group_float(grp, "spread_gate_warm_factor", float(getattr(CFG, "spread_gate_warm_factor", 1.75)), symbol=symbol)
    spread_gate_eco = _cfg_group_float(grp, "spread_gate_eco_factor", float(getattr(CFG, "spread_gate_eco_factor", 2.00)), symbol=symbol)
    if mode_u == "HOT":
        gate = float(spread_gate_hot)
    elif mode_u == "WARM":
        gate = float(spread_gate_warm)
    else:
        gate = float(spread_gate_eco)
    sp = float(spread_points if np.isfinite(spread_points) else 0.0)
    p80 = float(spread_p80 if np.isfinite(spread_p80) else 0.0)
    if p80 > 0.0 and sp > 0.0 and sp <= (gate * p80):
        c += 12.0
    cap = float(fx_spread_cap_points(symbol, grp=grp))
    if sp > 0.0 and sp <= cap:
        c += 8.0
    parts["C_cost"] = float(min(20.0, c))
    score += parts["C_cost"]

    # D) Volatility quality (max 15)
    d = 0.0
    atr_pts = None
    if atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0 and float(point) > 0.0:
        atr_pts = float(atr_value) / float(point)
        atr_min_pts = float(max(1.0, float(getattr(CFG, "fx_atr_points_min", 70.0) or 70.0)))
        atr_max_pts = float(max(atr_min_pts, float(getattr(CFG, "fx_atr_points_max", 220.0) or 220.0)))
        if atr_min_pts <= float(atr_pts) <= atr_max_pts:
            d += 8.0
        clip = float(max(1.0, float(getattr(CFG, "fx_body_vs_atr_clip_max", 2.2) or 2.2)))
        if float(body) <= clip * float(atr_value):
            d += 7.0
    parts["D_volatility"] = float(min(15.0, d))
    score += parts["D_volatility"]

    # E) Execution/risk readiness (max 15)
    e = 6.0  # pre-gates (cooldown/backoff/soft budget) were already passed
    if int(max(0, int(execution_error_recent))) == 0:
        e += 5.0
    if sig in {"BUY", "SELL"} and trend == sig:
        e += 4.0
    parts["E_exec_risk"] = float(min(15.0, e))
    score += parts["E_exec_risk"]

    score_clamped = int(max(0, min(100, int(round(score)))))
    parts["score_total"] = float(score_clamped)
    parts["spread_points"] = float(sp)
    parts["spread_p80"] = float(p80)
    parts["spread_cap_points"] = float(cap)
    parts["atr_points"] = float(atr_pts) if atr_pts is not None and np.isfinite(atr_pts) else -1.0
    parts["adx_threshold"] = float(adx_thr)
    parts["adx_range_max"] = float(adx_rng)
    return score_clamped, parts


def infer_runtime_strategy_family(
    *,
    mode: str,
    signal: str,
    signal_reason: str,
    candle_ctx: Optional[Dict[str, Any]] = None,
    renko_ctx: Optional[Dict[str, Any]] = None,
) -> str:
    sig_reason = str(signal_reason or "").upper()
    if "RENKO" in sig_reason and ("CANDLE" in sig_reason or "JAPANESE" in sig_reason):
        return "CANDLE_RENKO_CONFLUENCE"
    if "RENKO" in sig_reason:
        return "RENKO_ONLY"
    if "CANDLE" in sig_reason or "JAPANESE" in sig_reason:
        return "CANDLE_ONLY"

    candle_ctx = candle_ctx if isinstance(candle_ctx, dict) else {}
    renko_ctx = renko_ctx if isinstance(renko_ctx, dict) else {}
    candle_mode = str(candle_ctx.get("mode") or "").upper()
    candle_bias = str(candle_ctx.get("candle_bias") or "").upper()
    candle_reason = str(candle_ctx.get("reason_code") or "").upper()
    renko_mode = str(renko_ctx.get("mode") or "").upper()
    renko_bias = str(renko_ctx.get("renko_bias") or "").upper()
    renko_reason = str(renko_ctx.get("reason_code") or "").upper()
    candle_score = max(
        float(candle_ctx.get("candle_score_long", 0.0) or 0.0),
        float(candle_ctx.get("candle_score_short", 0.0) or 0.0),
    )
    renko_score = max(
        float(renko_ctx.get("renko_score_long", 0.0) or 0.0),
        float(renko_ctx.get("renko_score_short", 0.0) or 0.0),
    )

    candle_active = bool(
        candle_mode == "ADVISORY_SCORE"
        and (candle_bias not in {"", "NONE"} or candle_reason not in {"", "NONE"} or candle_score > 0.0)
    )
    renko_active = bool(
        renko_mode == "ADVISORY_SCORE"
        and (renko_bias not in {"", "NONE"} or renko_reason not in {"", "NONE"} or renko_score > 0.0)
    )
    if candle_active and renko_active:
        return "CANDLE_RENKO_CONFLUENCE"
    if renko_active:
        return "RENKO_ONLY"
    if candle_active:
        return "CANDLE_ONLY"

    tokens = " ".join([str(mode or ""), str(signal or ""), sig_reason]).upper()
    if "RANGE" in tokens or "PULLBACK" in tokens:
        return "RANGE_PULLBACK"
    if "TREND" in tokens or "ADX" in tokens or "CONTINUATION" in tokens or "BREAK" in tokens:
        return "TREND_CONTINUATION"
    if str(mode or "").upper() in {"HOT", "WARM", "ECO"}:
        return "CORE_RUNTIME"
    return "UNKNOWN"


def metal_spread_cap_points(symbol: str, grp: Optional[str] = "METAL") -> float:
    """Per-symbol hard spread cap in points for METAL scoring gate."""
    default_cap = float(max(1.0, float(getattr(CFG, "metal_spread_cap_points_default", 120.0) or 120.0)))
    cap = _cfg_group_float(grp, "metal_spread_cap_points", default_cap, symbol=symbol)
    try:
        return float(max(1.0, float(cap)))
    except Exception:
        return default_cap


def metal_score_threshold_for_mode(mode: str, symbol: Optional[str] = None) -> int:
    base_default = int(max(0, int(getattr(CFG, "metal_signal_score_threshold", 76) or 76)))
    base_thr = int(max(0, _cfg_group_int("METAL", "metal_signal_score_threshold", base_default, symbol=symbol)))
    if bool(getattr(CFG, "metal_signal_score_hot_relaxed_enabled", True)) and str(mode).upper() == "HOT":
        hot_default = int(max(0, int(getattr(CFG, "metal_signal_score_hot_relaxed_threshold", 70) or 70)))
        hot_thr = int(max(0, _cfg_group_int("METAL", "metal_signal_score_hot_relaxed_threshold", hot_default, symbol=symbol)))
        return int(min(base_thr, hot_thr))
    return int(base_thr)


def crypto_score_threshold_for_mode(mode: str, symbol: Optional[str] = None) -> int:
    base_default = int(max(0, int(getattr(CFG, "crypto_signal_score_threshold", 78) or 78)))
    base_thr = int(max(0, _cfg_group_int("CRYPTO", "signal_score_threshold", base_default, symbol=symbol)))
    if bool(getattr(CFG, "crypto_signal_score_hot_relaxed_enabled", True)) and str(mode).upper() == "HOT":
        hot_default = int(max(0, int(getattr(CFG, "crypto_signal_score_hot_relaxed_threshold", 74) or 74)))
        hot_thr = int(max(0, _cfg_group_int("CRYPTO", "signal_score_hot_relaxed_threshold", hot_default, symbol=symbol)))
        return int(min(base_thr, hot_thr))
    return int(base_thr)


def metal_pacing_limit_ratio(progress: float) -> float:
    """Piecewise ORDER-budget pacing target for METAL_PM session."""
    return float(
        _session_pacing_limit_ratio(
            progress=progress,
            phase1_progress=float(getattr(CFG, "metal_budget_pacing_phase1_progress", 0.25) or 0.25),
            phase2_progress=float(getattr(CFG, "metal_budget_pacing_phase2_progress", 0.6667) or 0.6667),
            phase1_ratio=float(getattr(CFG, "metal_budget_pacing_phase1_ratio", 0.25) or 0.25),
            phase2_ratio=float(getattr(CFG, "metal_budget_pacing_phase2_ratio", 0.70) or 0.70),
        )
    )


def metal_budget_pacing_allows_entry(
    gov: "RequestGovernor",
    db: "Persistence",
    now_dt: Optional[dt.datetime] = None,
) -> Tuple[bool, Dict[str, float]]:
    """
    Gate entries when ORDER budget for METAL is consumed too quickly early in METAL_PM.
    """
    if not bool(getattr(CFG, "metal_budget_pacing_enabled", True)):
        return True, {"enabled": 0.0}
    if gov is None or db is None:
        return True, {"enabled": 1.0, "reason": "MISSING_STATE"}  # type: ignore[dict-item]

    now_u = now_dt if isinstance(now_dt, dt.datetime) else now_utc()
    now_pl_dt = now_u.astimezone(TZ_PL)
    win = (getattr(CFG, "trade_windows", {}) or {}).get("METAL_PM", {})
    if not isinstance(win, dict):
        win = {}
    start_hm = win.get("start_hm", (14, 0))
    end_hm = win.get("end_hm", (17, 0))
    try:
        sh = (int(start_hm[0]), int(start_hm[1]))
        eh = (int(end_hm[0]), int(end_hm[1]))
    except Exception:
        sh, eh = (14, 0), (17, 0)

    progress = window_progress_ratio(now_pl_dt, sh, eh)
    try:
        borrow = int(gov.order_group_borrow_allowance("METAL", now_dt=now_u))
    except TypeError:
        borrow = int(gov.order_group_borrow_allowance("METAL"))
    cap = int(max(0, int(gov.order_group_cap("METAL")) + int(borrow)))
    used = int(max(0, int(db.get_order_group_actions_day("METAL", now_dt=now_u, emergency=False))))
    if cap <= 0:
        return False, {
            "enabled": 1.0,
            "progress": float(progress),
            "limit_ratio": 0.0,
            "slack": float(getattr(CFG, "metal_budget_pacing_slack", 0.05)),
            "used_ratio": 1.0,
            "used": float(used),
            "cap": float(cap),
            "reason": "METAL_ORDER_CAP_ZERO",  # type: ignore[dict-item]
        }
    used_ratio = float(used) / float(cap)
    limit_ratio = float(metal_pacing_limit_ratio(progress))
    slack = float(max(0.0, float(getattr(CFG, "metal_budget_pacing_slack", 0.05) or 0.05)))
    ok = bool(used_ratio <= (limit_ratio + slack))
    return ok, {
        "enabled": 1.0,
        "progress": float(progress),
        "limit_ratio": float(limit_ratio),
        "slack": float(slack),
        "used_ratio": float(used_ratio),
        "used": float(used),
        "cap": float(cap),
    }


def score_metal_entry_signal(
    *,
    symbol: str,
    grp: str,
    mode: str,
    signal: str,
    signal_reason: str,
    trend_h4: str,
    structure_h4: str,
    regime: str,
    close_price: float,
    open_price: float,
    high_price: Optional[float],
    low_price: Optional[float],
    sma_fast_value: float,
    adx_value: float,
    atr_value: Optional[float],
    point: float,
    spread_points: float,
    spread_p80: float,
    execution_error_recent: int = 0,
) -> Tuple[int, Dict[str, float]]:
    """
    Deterministic METAL signal scoring (0..100) for popołudniowa sesja metali.
    """
    parts: Dict[str, float] = {}
    score = 0.0

    trend = str(trend_h4).upper()
    struct = str(structure_h4).upper()
    reg = str(regime).upper()
    sig = str(signal).upper()
    sig_reason = str(signal_reason).upper()
    mode_u = str(mode).upper()

    # A) Regime + direction (max 25)
    a = 0.0
    if trend in {"BUY", "SELL"}:
        a += 8.0
    if struct in {"BUY", "SELL"} and struct == trend:
        a += 7.0
    adx_thr = float(max(0.0, _cfg_group_float(grp, "adx_threshold", float(getattr(CFG, "adx_threshold", 17)), symbol=symbol)))
    adx_rng = float(max(0.0, _cfg_group_float(grp, "adx_range_max", float(getattr(CFG, "adx_range_max", 11)), symbol=symbol)))
    if reg == "TREND" and np.isfinite(adx_value) and float(adx_value) >= float(adx_thr):
        a += 10.0
    elif reg == "RANGE" and np.isfinite(adx_value) and float(adx_value) <= float(adx_rng):
        a += 8.0
    parts["A_regime_direction"] = float(min(25.0, a))
    score += parts["A_regime_direction"]

    # B) Trigger quality with wick/retest checks (max 25)
    b = 0.0
    if sig in {"BUY", "SELL"} and sig_reason not in {"", "NO_TREND_SIGNAL", "NO_RANGE_SIGNAL"}:
        b += 10.0

    body = abs(float(close_price) - float(open_price))
    rng = None
    upper_wick = 0.0
    lower_wick = 0.0
    try:
        if high_price is not None and low_price is not None:
            h = float(high_price)
            l = float(low_price)
            o = float(open_price)
            c = float(close_price)
            rng_val = abs(h - l)
            if np.isfinite(rng_val) and rng_val > 0.0:
                rng = float(rng_val)
            upper_wick = max(0.0, h - max(o, c))
            lower_wick = max(0.0, min(o, c) - l)
    except Exception:
        rng = None
        upper_wick = 0.0
        lower_wick = 0.0

    body_ratio_min = float(max(0.0, min(1.0, float(getattr(CFG, "metal_body_range_ratio_min", 0.45) or 0.45))))
    if rng is not None and rng > 0.0 and (float(body) / float(rng)) >= body_ratio_min:
        b += 6.0
    elif atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0:
        if (float(body) / float(atr_value)) >= 0.15:
            b += 6.0

    wick_need = float(max(0.0, float(getattr(CFG, "metal_wick_rejection_ratio_min", 1.20) or 1.20)))
    if body > 0.0:
        wick_ratio = (lower_wick / body) if sig == "BUY" else (upper_wick / body)
        if float(wick_ratio) >= wick_need:
            b += 5.0
    else:
        wick_ratio = 0.0

    if atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0:
        retest_max = float(max(0.0, float(getattr(CFG, "metal_retest_distance_atr_max", 0.35) or 0.35)))
        dist_sma = abs(float(close_price) - float(sma_fast_value))
        if dist_sma <= (retest_max * float(atr_value)):
            b += 4.0
    parts["B_trigger"] = float(min(25.0, b))
    score += parts["B_trigger"]

    # C) Cost & liquidity (max 20)
    c = 0.0
    spread_gate_hot = _cfg_group_float(grp, "spread_gate_hot_factor", float(getattr(CFG, "spread_gate_hot_factor", 1.4)), symbol=symbol)
    spread_gate_warm = _cfg_group_float(grp, "spread_gate_warm_factor", float(getattr(CFG, "spread_gate_warm_factor", 2.0)), symbol=symbol)
    spread_gate_eco = _cfg_group_float(grp, "spread_gate_eco_factor", float(getattr(CFG, "spread_gate_eco_factor", 2.5)), symbol=symbol)
    if mode_u == "HOT":
        gate = float(spread_gate_hot)
    elif mode_u == "WARM":
        gate = float(spread_gate_warm)
    else:
        gate = float(spread_gate_eco)
    sp = float(spread_points if np.isfinite(spread_points) else 0.0)
    p80 = float(spread_p80 if np.isfinite(spread_p80) else 0.0)
    if p80 > 0.0 and sp > 0.0 and sp <= (gate * p80):
        c += 12.0
    cap = float(metal_spread_cap_points(symbol, grp=grp))
    if sp > 0.0 and sp <= cap:
        c += 8.0
    parts["C_cost"] = float(min(20.0, c))
    score += parts["C_cost"]

    # D) Volatility quality (max 15)
    d = 0.0
    atr_pts = None
    if atr_value is not None and np.isfinite(float(atr_value)) and float(atr_value) > 0.0 and float(point) > 0.0:
        atr_pts = float(atr_value) / float(point)
        atr_min_pts = float(max(1.0, float(getattr(CFG, "metal_atr_points_min", 120.0) or 120.0)))
        atr_max_pts = float(max(atr_min_pts, float(getattr(CFG, "metal_atr_points_max", 900.0) or 900.0)))
        if atr_min_pts <= float(atr_pts) <= atr_max_pts:
            d += 8.0
        impulse_min = float(max(0.0, float(getattr(CFG, "metal_impulse_atr_fraction_min", 0.07) or 0.07)))
        clip = float(max(1.0, float(getattr(CFG, "metal_body_vs_atr_clip_max", 2.8) or 2.8)))
        if float(body) >= impulse_min * float(atr_value) and float(body) <= clip * float(atr_value):
            d += 7.0
    parts["D_volatility"] = float(min(15.0, d))
    score += parts["D_volatility"]

    # E) Execution/risk readiness (max 15)
    e = 6.0
    if int(max(0, int(execution_error_recent))) == 0:
        e += 5.0
    if sig in {"BUY", "SELL"} and trend == sig:
        e += 4.0
    parts["E_exec_risk"] = float(min(15.0, e))
    score += parts["E_exec_risk"]

    score_clamped = int(max(0, min(100, int(round(score)))))
    parts["score_total"] = float(score_clamped)
    parts["spread_points"] = float(sp)
    parts["spread_p80"] = float(p80)
    parts["spread_cap_points"] = float(cap)
    parts["atr_points"] = float(atr_pts) if atr_pts is not None and np.isfinite(atr_pts) else -1.0
    parts["wick_ratio"] = float(wick_ratio)
    parts["adx_threshold"] = float(adx_thr)
    parts["adx_range_max"] = float(adx_rng)
    return score_clamped, parts


def partial_close_volume(volume: float, fraction: float, vol_min: float, vol_step: float) -> float:
    """Deterministic partial close volume rounded down to broker step."""
    try:
        v = float(volume)
        frac = float(fraction)
    except Exception:
        return 0.0
    if (not np.isfinite(v)) or (not np.isfinite(frac)) or v <= 0.0 or frac <= 0.0 or frac >= 1.0:
        return 0.0
    if vol_step <= 0.0:
        return 0.0
    raw = v * frac
    steps = int(math.floor(raw / float(vol_step)))
    out = float(round(steps * float(vol_step), 8))
    if out <= 0.0:
        return 0.0
    min_vol = float(max(0.0, vol_min))
    # Do not close if either leg would violate minimum size.
    if min_vol > 0.0:
        if out < min_vol:
            return 0.0
        if (v - out) < min_vol:
            return 0.0
    return out

def in_window(local_dt: dt.datetime, start_hm: Tuple[int, int], end_hm: Tuple[int, int]) -> bool:
    s = local_dt.replace(hour=start_hm[0], minute=start_hm[1], second=0, microsecond=0)
    e = local_dt.replace(hour=end_hm[0], minute=end_hm[1], second=0, microsecond=0)
    if (start_hm[0], start_hm[1]) == (end_hm[0], end_hm[1]):
        return True
    if s <= e:
        return bool(s <= local_dt <= e)
    # Overnight window support (e.g. 21:00-07:00).
    return bool(local_dt >= s or local_dt <= e)

# =============================================================================
# USB
# =============================================================================

def get_usb_path(label: Optional[str] = None) -> Optional[Path]:
    """Return the root path of the USB key (by filesystem label), or None.

    Timeout-protected to avoid hangs on PowerShell/WMIC calls.
    """
    label = (label or "OANDAKEY").strip()
    drive_letter: Optional[str] = None
    # VPS/serwer fallback: lokalny katalog z TOKEN/BotKey.env.
    # Priorytet nadal ma fizyczny wolumin o etykiecie OANDAKEY.
    fallback_candidates: List[Path] = []
    for env_key in ("OANDAKEY_ROOT", "OANDAKEY_FALLBACK_ROOT"):
        raw = (os.environ.get(env_key) or "").strip()
        if raw:
            try:
                fallback_candidates.append(Path(raw))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
    # Standardowy fallback dla runtime na VPS.
    fallback_candidates.append(Path("C:/OANDA_MT5_SYSTEM/KEY"))

    timeout_s = 8

    # Fallback 0: PowerShell .NET DriveInfo (works in locked-down environments).
    try:
        ps_di = (
            "$d = [System.IO.DriveInfo]::GetDrives() | "
            "Where-Object { $_.IsReady -and $_.VolumeLabel -eq '%s' } | "
            "Select-Object -First 1; "
            "if ($d -and $d.Name) { Write-Output $d.Name }"
        ) % label.replace("'", "''")
        out = subprocess.check_output(
            ["powershell", "-NoProfile", "-Command", ps_di],
            stderr=subprocess.STDOUT,
            text=True,
            errors="ignore",
            timeout=timeout_s,
        ).strip()
        if out:
            # Expected like "D:\"
            cand = out.strip()
            if len(cand) >= 1 and cand[0].isalpha():
                drive_letter = cand[0].upper()
    except subprocess.TimeoutExpired:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed")
        drive_letter = None
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        drive_letter = None

    # Prefer PowerShell Get-Volume (Windows 10/11)
    if not drive_letter:
        try:
            ps = (
                "$v = Get-Volume | Where-Object { $_.FileSystemLabel -eq '%s' } | Select-Object -First 1;"
                "if ($v -and $v.DriveLetter) { Write-Output $v.DriveLetter }"
            ) % label.replace("'", "''")
            out = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command", ps],
                stderr=subprocess.STDOUT,
                text=True,
                errors="ignore",
                timeout=timeout_s,
            ).strip()
            if out:
                drive_letter = out.strip()
        except subprocess.TimeoutExpired:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed")
            drive_letter = None
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            drive_letter = None

    # Fallback: WMIC (still label-based)
    if not drive_letter:
        try:
            out = subprocess.check_output(
                ["wmic", "logicaldisk", "get", "DeviceID,VolumeName"],
                stderr=subprocess.STDOUT,
                text=True,
                errors="ignore",
                timeout=timeout_s,
            )
            for line in out.splitlines():
                line = line.strip()
                if not line or "DeviceID" in line:
                    continue
                parts = [p for p in line.split() if p]
                if len(parts) >= 2:
                    dev = parts[0]
                    vol = " ".join(parts[1:])
                    if vol.strip().upper() == label.upper():
                        drive_letter = dev.replace(":", "")
                        break
        except subprocess.TimeoutExpired:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed")
            drive_letter = None
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            drive_letter = None

    if not drive_letter:
        for root in fallback_candidates:
            try:
                env_path = root / "TOKEN" / "BotKey.env"
                if env_path.exists():
                    return root
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None

    usb_root = Path(f"{drive_letter}:/")
    env_path = usb_root / "TOKEN" / "BotKey.env"
    if env_path.exists():
        return usb_root
    return None
def usb_present() -> bool:
    return get_usb_path() is not None

def _pid_is_running(pid: int) -> bool:
    try:
        pid = int(pid)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return False
    if pid <= 0:
        return False

    # Windows: tasklist is the simplest without extra deps; POSIX: os.kill(pid, 0).
    if os.name == 'nt':
        try:
            import subprocess
            cp = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}"],
                capture_output=True,
                text=True,
                check=False,
                timeout=3,
            )
            return str(pid) in (cp.stdout or "")
        except Exception as e:
            # Conservative: if we cannot probe the PID, treat as running.
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return True

    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError as e:
        # Conservative: unknown permission state => treat as running (avoid stale-lock false positives).
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return True
    except Exception as e:
        # Conservative: any other OS error => treat as running.
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return True

def pid_exists(pid: int) -> bool:
    """Backward-compatible alias used by lock cleanup."""
    return _pid_is_running(pid)

def acquire_lockfile(lock_path: Path) -> None:
    """Exclusive lockfile with stale-PID cleanup. Hard timeout: LOCK_ACQUIRE_MAX_SECONDS."""
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    while (time.time() - t0) <= float(LOCK_ACQUIRE_MAX_SECONDS):
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            payload = json.dumps({"pid": os.getpid(), "ts_utc": now_utc().isoformat().replace('+00:00','Z')}, separators=(",", ":"))
            os.write(fd, payload.encode("utf-8", errors="ignore"))
            os.close(fd)
            return
        except FileExistsError:
            # possible stale lock
            try:
                raw = lock_path.read_text(encoding="utf-8", errors="ignore").strip()
                pid = 0
                if raw.startswith("{"):
                    try:
                        pid = int(json.loads(raw).get("pid") or 0)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        pid = 0
                else:
                    pid = int(raw) if raw.isdigit() else 0
                # Empty/invalid lock payload should never block startup.
                if pid <= 0:
                    try:
                        payload = json.dumps({"pid": os.getpid(), "ts_utc": now_utc().isoformat().replace('+00:00','Z')}, separators=(",", ":"))
                        lock_path.write_text(payload, encoding="utf-8")
                        return
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        # Fallback: remove stale file and retry.
                        try:
                            lock_path.unlink(missing_ok=True)
                            time.sleep(0.05)
                            continue
                        except Exception as e:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                            time.sleep(0.1)
                            continue
                if pid and (not pid_exists(pid)):
                    try:
                        payload = json.dumps({"pid": os.getpid(), "ts_utc": now_utc().isoformat().replace('+00:00','Z')}, separators=(",", ":"))
                        lock_path.write_text(payload, encoding="utf-8")
                        return
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        try:
                            lock_path.unlink(missing_ok=True)
                            time.sleep(0.05)
                            continue
                        except Exception as e2:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e2)
                            time.sleep(0.1)
                            continue
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            time.sleep(0.1)
            continue
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            time.sleep(0.1)
            continue
    raise RuntimeError(f"ALREADY_RUNNING: lock exists at {lock_path}")

def release_lockfile(lock_path: Path) -> None:
    try:
        lock_path.unlink(missing_ok=True)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        try:
            lock_path.write_text("", encoding="utf-8")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

def setup_logging(runtime_root: Path) -> None:
    r"""
    Logging is always local (C:\\OANDA_MT5_SYSTEM\\LOGS). USB is never used for logs.
    Unified log name: LOGS\\safetybot.log
    """
    log_dir = runtime_root / "LOGS"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "safetybot.log"

    handlers = []
    try:
        from logging.handlers import RotatingFileHandler
        handlers.append(RotatingFileHandler(str(log_file), maxBytes=10_000_000, backupCount=10, encoding="utf-8"))
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        handlers.append(logging.FileHandler(str(log_file), encoding="utf-8"))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=handlers,
        force=True,
    )

def _decrypt_dpapi_b64(cipher_b64: str) -> str:
    """Decrypt base64-encoded DPAPI blob (CurrentUser scope)."""
    if os.name != "nt":
        raise RuntimeError("DPAPI decrypt is supported only on Windows.")

    raw = base64.b64decode((cipher_b64 or "").strip(), validate=True)
    if not raw:
        raise RuntimeError("MT5_PASSWORD_DPAPI_B64 is empty.")

    from ctypes import wintypes

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_byte)),
        ]

    crypt32 = ctypes.windll.crypt32
    kernel32 = ctypes.windll.kernel32
    crypt32.CryptUnprotectData.argtypes = [
        ctypes.POINTER(DATA_BLOB),
        ctypes.POINTER(wintypes.LPWSTR),
        ctypes.POINTER(DATA_BLOB),
        ctypes.c_void_p,
        ctypes.c_void_p,
        wintypes.DWORD,
        ctypes.POINTER(DATA_BLOB),
    ]
    crypt32.CryptUnprotectData.restype = wintypes.BOOL
    kernel32.LocalFree.argtypes = [ctypes.c_void_p]
    kernel32.LocalFree.restype = ctypes.c_void_p

    in_buf = ctypes.create_string_buffer(raw, len(raw))
    in_blob = DATA_BLOB(len(raw), ctypes.cast(in_buf, ctypes.POINTER(ctypes.c_byte)))
    out_blob = DATA_BLOB()

    ok = crypt32.CryptUnprotectData(
        ctypes.byref(in_blob),
        None,
        None,
        None,
        None,
        0,
        ctypes.byref(out_blob),
    )
    if not ok:
        raise ctypes.WinError()

    try:
        dec_bytes = ctypes.string_at(out_blob.pbData, out_blob.cbData)
        return dec_bytes.decode("utf-8")
    finally:
        if out_blob.pbData:
            kernel32.LocalFree(out_blob.pbData)

def _decrypt_dpapi_secure_string(cipher_text: str) -> str:
    """Decrypt PowerShell ConvertFrom-SecureString DPAPI payload."""
    if os.name != "nt":
        raise RuntimeError("DPAPI decrypt is supported only on Windows.")
    raw = (cipher_text or "").strip()
    if not raw:
        raise RuntimeError("MT5_PASSWORD_DPAPI is empty.")

    ps = (
        "$ErrorActionPreference='Stop'\n"
        "$c = [Console]::In.ReadToEnd().Trim()\n"
        "$s = ConvertTo-SecureString -String $c\n"
        "$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)\n"
        "try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }\n"
        "finally { if ($b -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }\n"
    )
    out = subprocess.check_output(
        ["powershell", "-NoProfile", "-Command", ps],
        input=raw,
        stderr=subprocess.STDOUT,
        text=True,
        errors="ignore",
        timeout=10,
    )
    plain = (out or "").strip()
    if not plain:
        raise RuntimeError("DPAPI secure string decryption returned empty value.")
    return plain

def load_env(usb_root: Path) -> Dict[str, str]:
    env_path = usb_root / "TOKEN" / "BotKey.env"
    if not env_path.exists():
        raise FileNotFoundError(f"Brak pliku konfiguracji: {env_path}")
    cfg = {}
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip().lstrip("\ufeff")] = v.strip()
    if "MT5_PASSWORD" not in cfg:
        if "MT5_PASSWORD_DPAPI_B64" in cfg:
            try:
                cfg["MT5_PASSWORD"] = _decrypt_dpapi_b64(cfg["MT5_PASSWORD_DPAPI_B64"])
            except Exception as e:
                raise RuntimeError("Nie mozna odszyfrowac MT5_PASSWORD_DPAPI_B64 dla tego uzytkownika Windows.") from e
        elif "MT5_PASSWORD_DPAPI" in cfg:
            try:
                cfg["MT5_PASSWORD"] = _decrypt_dpapi_secure_string(cfg["MT5_PASSWORD_DPAPI"])
            except Exception as e:
                raise RuntimeError("Nie mozna odszyfrowac MT5_PASSWORD_DPAPI dla tego uzytkownika Windows.") from e
    return cfg

# =============================================================================
# DB
# =============================================================================

class Persistence:
    def __init__(self, db_path: Optional[Path] = None):
        """Local state DB (budgets, req counters, deals log)."""
        if db_path is None:
            db_path = Path(CFG.db_filename)
        else:
            db_path = Path(db_path)
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = str(db_path)
        self._db_dir = db_path.parent
        self._db_delete_capable = self._probe_delete_capability(self._db_dir)
        self.conn = self._connect()
        try:
            self._init_db()
        except sqlite3.OperationalError as e:
            msg = str(e).lower()
            if ("disk i/o" in msg) or ("database disk image is malformed" in msg):
                logging.warning(f"DB_INIT_RECOVERY_TRIGGER path={self.db_path} err={type(e).__name__}:{e}")
                try:
                    self.conn.close()
                except Exception as exc:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", exc)
                self._recover_corrupt_sqlite_files()
                self.conn = self._connect()
                self._init_db()
            else:
                raise

    def _probe_delete_capability(self, directory: Path) -> bool:
        probe = Path(directory) / ".sqlite_delete_probe.tmp"
        try:
            with open(probe, "w", encoding="utf-8") as f:
                f.write("1")
            os.remove(probe)
            return True
        except Exception:
            return False

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path, timeout=5, check_same_thread=False)
        # Some environments allow write but deny delete in DB dir.
        # WAL/DELETE journaling then fails with "disk I/O error".
        try:
            if self._db_delete_capable:
                conn.execute("PRAGMA journal_mode=WAL;")
                conn.execute("PRAGMA synchronous=NORMAL;")
            else:
                conn.execute("PRAGMA journal_mode=OFF;")
                conn.execute("PRAGMA synchronous=OFF;")
                logging.warning(f"DB_JOURNAL_FALLBACK mode=OFF dir={self._db_dir}")
            conn.execute("PRAGMA temp_store=MEMORY;")
            conn.execute("PRAGMA busy_timeout=5000;")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return conn

    def _recover_corrupt_sqlite_files(self) -> None:
        base = Path(self.db_path)
        stamp = now_utc().strftime("%Y%m%d_%H%M%S")
        for suffix in ("", "-wal", "-shm"):
            src = Path(str(base) + suffix)
            if not src.exists():
                continue
            dst = src.parent / f"{src.name}.corrupt_{stamp}"
            try:
                os.replace(str(src), str(dst))
                logging.warning(f"DB_RECOVERY_MOVE src={src} dst={dst}")
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _init_db(self):
        c = self.conn.cursor()
        # Budżety dzienne (NY) rozdzielone na PRICE i SYS
        c.execute("""CREATE TABLE IF NOT EXISTS budget_day (
            ny_date TEXT PRIMARY KEY,
            price_count INTEGER DEFAULT 0,
            price_emergency INTEGER DEFAULT 0,
            sys_count INTEGER DEFAULT 0,
            sys_emergency INTEGER DEFAULT 0
        )""")
        # Log requestów per godzina NY (dla Score_hour)
        c.execute("""CREATE TABLE IF NOT EXISTS req_hourly (
            ny_date TEXT,
            ny_hour INTEGER,
            category TEXT,      -- PRICE / SYS
            grp TEXT,
            symbol TEXT,
            kind TEXT,
            count INTEGER DEFAULT 0,
            PRIMARY KEY (ny_date, ny_hour, category, grp, symbol, kind)
        )""")
        # Spread history (opcjonalnie)
        c.execute("""CREATE TABLE IF NOT EXISTS spread_history (
            symbol TEXT,
            timestamp INTEGER,
            spread_points REAL
        )""")
        # Deals log
        c.execute("""CREATE TABLE IF NOT EXISTS deals_log (
            deal_ticket INTEGER PRIMARY KEY,
            time INTEGER,
            ny_date TEXT,
            ny_hour INTEGER,
            grp TEXT,
            symbol TEXT,
            profit REAL,
            commission REAL,
            swap REAL
        )""")
        # System state
        c.execute("""CREATE TABLE IF NOT EXISTS system_state (
            key TEXT PRIMARY KEY,
            value TEXT
        )""")
        c.execute("""INSERT OR IGNORE INTO system_state (key, value) VALUES ('paper_start_ts', '0')""")
        c.execute("""INSERT OR IGNORE INTO system_state (key, value) VALUES ('last_deals_poll_ts', '0')""")
        c.execute("""INSERT OR IGNORE INTO system_state (key, value) VALUES ('last_positions_poll_ts', '0')""")
        self.conn.commit()

    def get_or_set_paper_start(self) -> float:
        c = self.conn.cursor()
        c.execute("SELECT value FROM system_state WHERE key='paper_start_ts'")
        row = c.fetchone()
        if row and float(row[0]) > 0:
            return float(row[0])
        ts = time.time()
        c.execute("UPDATE system_state SET value=? WHERE key='paper_start_ts'", (str(ts),))
        self.conn.commit()
        return ts

    def get_last_ts(self, key: str) -> int:
        c = self.conn.cursor()
        c.execute("SELECT value FROM system_state WHERE key=?", (key,))
        row = c.fetchone()
        return int(float(row[0])) if row else 0

    def set_last_ts(self, key: str, ts: int):
        c = self.conn.cursor()
        c.execute("UPDATE system_state SET value=? WHERE key=?", (str(int(ts)), key))
        self.conn.commit()

    # --- P0 state helpers (uses existing system_state table; no _init_db logic changes) ---
    def _state_get(self, key: str, default: str = "0") -> str:
        c = self.conn.cursor()
        c.execute("SELECT value FROM system_state WHERE key=?", (str(key),))
        row = c.fetchone()
        return str(row[0]) if row and row[0] is not None else str(default)

    def _state_set(self, key: str, value: str) -> None:
        c = self.conn.cursor()
        c.execute("INSERT OR REPLACE INTO system_state (key, value) VALUES (?, ?)", (str(key), str(value)))
        self.conn.commit()

    def state_get(self, key: str, default: str = "0") -> str:
        return self._state_get(key, default)

    def state_set(self, key: str, value: str) -> None:
        self._state_set(key, value)

    def _state_inc_int(self, key: str, delta: int) -> int:
        """Atomic-ish increment for integer counters stored in system_state."""
        cur_s = self._state_get(key, "0")
        try:
            cur = int(float(cur_s))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            cur = 0
        nxt = int(cur) + int(delta)
        self._state_set(key, str(int(nxt)))
        return int(nxt)

    def _day_counter_key(self, category: str, day_type: str, day: str, emergency: bool) -> str:
        cat = str(category).upper().strip()
        dtp = str(day_type).lower().strip()
        if cat not in ("PRICE", "SYS"):
            cat = "SYS"
        if dtp not in ("ny", "utc", "pl"):
            dtp = "utc"
        base = f"budget_{cat.lower()}_{'em_' if emergency else ''}{dtp}:{day}"
        return base

    def get_day_counter(self, category: str, day_type: str, day: str, emergency: bool) -> int:
        key = self._day_counter_key(category, day_type, day, emergency)
        try:
            return int(float(self._state_get(key, "0")))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0

    def inc_day_counter(self, category: str, day_type: str, day: str, n: int, emergency: bool) -> int:
        key = self._day_counter_key(category, day_type, day, emergency)
        return self._state_inc_int(key, int(n))

    def _order_actions_key(self, day_type: str, day: str) -> str:
        dtp = str(day_type).lower().strip()
        if dtp not in ("ny", "utc", "pl"):
            dtp = "utc"
        return f"order_actions_{dtp}:{day}"

    def _order_group_actions_key(self, day_type: str, day: str, grp: str, emergency: bool = False) -> str:
        dtp = str(day_type).lower().strip()
        if dtp not in ("ny", "utc", "pl"):
            dtp = "utc"
        g = str(grp or "OTHER").strip().upper() or "OTHER"
        pref = "order_actions_em_" if bool(emergency) else "order_actions_"
        return f"{pref}{dtp}:{day}:{g}"

    def get_order_actions_state(self, now_dt: Optional[dt.datetime] = None) -> Dict[str, int]:
        """Return ORDER action counters for NY/UTC/PL and strict-guard used=max(ny, utc, pl)."""
        if now_dt is None:
            now_dt = now_utc()
        day_ny, _ = ny_day_hour_key(now_dt)
        utc_day = utc_day_key(now_dt)
        pl_day = pl_day_key(now_dt)

        def _get(dtp: str, day: str) -> int:
            v = self._state_get(self._order_actions_key(dtp, day), "0")
            try:
                return int(float(v))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                return 0

        ny = _get("ny", day_ny)
        utc = _get("utc", utc_day)
        pl = _get("pl", pl_day)
        used = max(int(ny), int(utc), int(pl))
        return {
            "day_ny": day_ny,
            "utc_day": utc_day,
            "pl_day": pl_day,
            "ny": int(ny),
            "utc": int(utc),
            "pl": int(pl),
            "used": int(used),
        }

    def get_order_actions_day(self, now_dt: Optional[dt.datetime] = None) -> int:
        """Strict-guard ORDER actions/day used for budget enforcement (max across NY/UTC/PL)."""
        st = self.get_order_actions_state(now_dt=now_dt)
        return int(st.get("used") or 0)

    def inc_order_action(self, n: int = 1, now_dt: Optional[dt.datetime] = None) -> int:
        """Increment ORDER actions for NY/UTC/PL day-keys (strict-guard)."""
        if now_dt is None:
            now_dt = now_utc()
        st = self.get_order_actions_state(now_dt=now_dt)
        day_ny = str(st["day_ny"])
        utc_day = str(st["utc_day"])
        pl_day = str(st["pl_day"])

        # Increment all three counters to avoid boundary ambiguity
        self._state_inc_int(self._order_actions_key("ny", day_ny), int(n))
        self._state_inc_int(self._order_actions_key("utc", utc_day), int(n))
        self._state_inc_int(self._order_actions_key("pl", pl_day), int(n))

        st2 = self.get_order_actions_state(now_dt=now_dt)
        return int(st2.get("used") or 0)

    def get_order_group_actions_state(
        self,
        grp: str,
        now_dt: Optional[dt.datetime] = None,
        emergency: bool = False,
    ) -> Dict[str, int]:
        """ORDER actions/day for a specific group with strict day-key guard."""
        if now_dt is None:
            now_dt = now_utc()
        day_ny, _ = ny_day_hour_key(now_dt)
        utc_day = utc_day_key(now_dt)
        pl_day = pl_day_key(now_dt)

        def _get(dtp: str, day: str) -> int:
            v = self._state_get(self._order_group_actions_key(dtp, day, grp=grp, emergency=bool(emergency)), "0")
            try:
                return int(float(v))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                return 0

        ny = _get("ny", day_ny)
        utc = _get("utc", utc_day)
        pl = _get("pl", pl_day)
        used = max(int(ny), int(utc), int(pl))
        return {
            "day_ny": day_ny,
            "utc_day": utc_day,
            "pl_day": pl_day,
            "ny": int(ny),
            "utc": int(utc),
            "pl": int(pl),
            "used": int(used),
        }

    def get_order_group_actions_day(
        self,
        grp: str,
        now_dt: Optional[dt.datetime] = None,
        emergency: bool = False,
    ) -> int:
        st = self.get_order_group_actions_state(grp=grp, now_dt=now_dt, emergency=bool(emergency))
        return int(st.get("used") or 0)

    def inc_order_group_action(
        self,
        grp: str,
        n: int = 1,
        now_dt: Optional[dt.datetime] = None,
        emergency: bool = False,
    ) -> int:
        if now_dt is None:
            now_dt = now_utc()
        st = self.get_order_group_actions_state(grp=grp, now_dt=now_dt, emergency=bool(emergency))
        day_ny = str(st["day_ny"])
        utc_day = str(st["utc_day"])
        pl_day = str(st["pl_day"])
        self._state_inc_int(self._order_group_actions_key("ny", day_ny, grp=grp, emergency=bool(emergency)), int(n))
        self._state_inc_int(self._order_group_actions_key("utc", utc_day, grp=grp, emergency=bool(emergency)), int(n))
        self._state_inc_int(self._order_group_actions_key("pl", pl_day, grp=grp, emergency=bool(emergency)), int(n))
        st2 = self.get_order_group_actions_state(grp=grp, now_dt=now_dt, emergency=bool(emergency))
        return int(st2.get("used") or 0)


    def get_global_backoff_until_ts(self) -> int:
        try:
            return int(float(self._state_get("global_backoff_until_ts", "0")))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0

    def set_global_backoff(self, until_ts: int, reason: str) -> None:
        self._state_set("global_backoff_until_ts", str(int(until_ts)))
        self._state_set("global_backoff_reason", str(reason or ""))

    def get_global_backoff_reason(self) -> str:
        return str(self._state_get("global_backoff_reason", ""))

    def get_cooldown_until_ts(self, symbol: str) -> int:
        key = f"cooldown_until_ts:{str(symbol)}"
        try:
            return int(float(self._state_get(key, "0")))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0

    def get_cooldown_reason(self, symbol: str) -> str:
        return str(self._state_get(f"cooldown_reason:{str(symbol)}", ""))

    def set_cooldown(self, symbol: str, seconds: int, reason: str) -> int:
        now_ts = int(time.time())
        until_ts = now_ts + int(max(1, seconds))
        self._state_set(f"cooldown_until_ts:{str(symbol)}", str(int(until_ts)))
        self._state_set(f"cooldown_reason:{str(symbol)}", str(reason or ""))
        return int(until_ts)

    def is_cooldown_active(self, symbol: str, now_ts: Optional[int] = None) -> bool:
        if now_ts is None:
            now_ts = int(time.time())
        return int(self.get_cooldown_until_ts(symbol)) > int(now_ts)

    def _ensure_day_row(self, ny_date: str):
        c = self.conn.cursor()
        c.execute("INSERT OR IGNORE INTO budget_day (ny_date, price_count, price_emergency, sys_count, sys_emergency) VALUES (?, 0, 0, 0, 0)", (ny_date,))
        self.conn.commit()

    def get_day_counts(self) -> Dict[str, int]:
        ny_date, _ = ny_day_hour_key()
        self._ensure_day_row(ny_date)
        c = self.conn.cursor()
        c.execute("SELECT price_count, price_emergency, sys_count, sys_emergency FROM budget_day WHERE ny_date=?", (ny_date,))
        row = c.fetchone()
        return {
            "price": int(row[0]),
            "price_em": int(row[1]),
            "sys": int(row[2]),
            "sys_em": int(row[3]),
        }

    def inc_request(self, category: str, grp: str, symbol: str, kind: str, n: int, emergency: bool):
        # We keep NY-day accounting for analytics/profiles, but enforce "calendar day" limits
        # via additional UTC/PL counters (strict-min policy).
        ny_date, ny_hour = ny_day_hour_key()
        self._ensure_day_row(ny_date)
        c = self.conn.cursor()
        if category == "PRICE":
            if emergency:
                c.execute("UPDATE budget_day SET price_emergency = price_emergency + ? WHERE ny_date=?", (n, ny_date))
            else:
                c.execute("UPDATE budget_day SET price_count = price_count + ? WHERE ny_date=?", (n, ny_date))
        else:
            if emergency:
                c.execute("UPDATE budget_day SET sys_emergency = sys_emergency + ? WHERE ny_date=?", (n, ny_date))
            else:
                c.execute("UPDATE budget_day SET sys_count = sys_count + ? WHERE ny_date=?", (n, ny_date))

        c.execute("""INSERT OR IGNORE INTO req_hourly (ny_date, ny_hour, category, grp, symbol, kind, count)
                     VALUES (?, ?, ?, ?, ?, ?, 0)""", (ny_date, ny_hour, category, grp, symbol, kind))
        c.execute("""UPDATE req_hourly SET count = count + ?
                     WHERE ny_date=? AND ny_hour=? AND category=? AND grp=? AND symbol=? AND kind=?""",
                  (n, ny_date, ny_hour, category, grp, symbol, kind))
        self.conn.commit()

        # Calendar-day counters for strict enforcement (UTC + PL)
        try:
            u_day = utc_day_key()
            p_day = pl_day_key()
            self.inc_day_counter(category, "utc", u_day, int(n), bool(emergency))
            self.inc_day_counter(category, "pl", p_day, int(n), bool(emergency))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def group_req_used_today(self, category: str, grp: str) -> int:
        ny_date, _ = ny_day_hour_key()
        c = self.conn.cursor()
        c.execute("""SELECT COALESCE(SUM(count), 0) FROM req_hourly
                     WHERE ny_date=? AND category=? AND grp=?""", (ny_date, str(category).upper(), grp))
        row = c.fetchone()
        return int(row[0] if row else 0)

    def group_price_used_today(self, grp: str) -> int:
        return int(self.group_req_used_today("PRICE", grp))

    def group_sys_used_today(self, grp: str) -> int:
        return int(self.group_req_used_today("SYS", grp))

    def log_spread(self, symbol: str, spread_points: float):
        ts = int(time.time())
        c = self.conn.cursor()
        c.execute("INSERT INTO spread_history (symbol, timestamp, spread_points) VALUES (?, ?, ?)",
                  (symbol, ts, float(spread_points)))
        if ts % 97 == 0:
            cutoff = ts - 7 * 24 * 3600
            c.execute("DELETE FROM spread_history WHERE timestamp < ?", (cutoff,))
        self.conn.commit()

    def get_p80_spread(self, symbol: str) -> float:
        c = self.conn.cursor()
        c.execute("SELECT spread_points FROM spread_history WHERE symbol=? ORDER BY timestamp DESC LIMIT 800", (symbol,))
        rows = c.fetchall()
        if not rows:
            return 0.0
        vals = [float(r[0]) for r in rows]
        return float(np.percentile(vals, 80))

    def upsert_deal(self, ticket: int, when_ts: int, grp: str, symbol: str,
                    profit: float, commission: float, swap: float):
        ny_date, ny_hour = ny_day_hour_key(dt.datetime.fromtimestamp(when_ts, tz=UTC))
        c = self.conn.cursor()
        c.execute("""INSERT OR REPLACE INTO deals_log
                     (deal_ticket, time, ny_date, ny_hour, grp, symbol, profit, commission, swap)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                  (int(ticket), int(when_ts), ny_date, int(ny_hour), grp, symbol,
                   float(profit), float(commission), float(swap)))
        self.conn.commit()

    def pnl_net_since_ts(self, start_ts: int) -> float:
        """Net PnL (profit+commission+swap) since start_ts (epoch seconds)."""
        c = self.conn.cursor()
        c.execute("""SELECT COALESCE(SUM(profit + commission + swap), 0.0)
                     FROM deals_log WHERE time >= ?""", (int(start_ts),))
        r = c.fetchone()
        try:
            return float(r[0] or 0.0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0.0

    def recent_deals_for_self_heal(self, limit: int = 64) -> List[Tuple[int, str, float]]:
        """Newest deals as (time, symbol, pnl_net), descending by time."""
        c = self.conn.cursor()
        lim = int(max(1, limit))
        c.execute(
            """SELECT time, symbol, (profit + commission + swap) AS pnl_net
               FROM deals_log
               ORDER BY time DESC
               LIMIT ?""",
            (lim,),
        )
        rows = c.fetchall()
        out: List[Tuple[int, str, float]] = []
        for r in rows:
            try:
                t_i = int(r[0])
                sym = str(r[1] or "")
                pnl = float(r[2] or 0.0)
                out.append((t_i, sym, pnl))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                continue
        return out

    def pnl_net_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> float:
        cutoff = (dt.datetime.now(TZ_NY) - dt.timedelta(days=lookback_days)).strftime("%Y-%m-%d")
        c = self.conn.cursor()
        c.execute("""SELECT COALESCE(SUM(profit + swap + commission), 0.0) FROM deals_log
                     WHERE ny_date>=? AND ny_hour=? AND grp=? AND symbol=?""",
                  (cutoff, int(ny_hour), grp, symbol))
        row = c.fetchone()
        return float(row[0] if row else 0.0)

    def price_req_for_hour(self, grp: str, symbol: str, ny_hour: int, lookback_days: int = 14) -> int:
        cutoff = (dt.datetime.now(TZ_NY) - dt.timedelta(days=lookback_days)).strftime("%Y-%m-%d")
        c = self.conn.cursor()
        c.execute("""SELECT COALESCE(SUM(count), 0) FROM req_hourly
                     WHERE ny_date>=? AND ny_hour=? AND category='PRICE' AND grp=? AND symbol=?""",
                  (cutoff, int(ny_hour), grp, symbol))
        row = c.fetchone()
        return int(row[0] if row else 0)

# =============================================================================
# GOVERNOR
# =============================================================================

def symbol_base(raw_symbol: str) -> str:
    return raw_symbol.split(".")[0]

def canonical_symbol(symbol: str) -> str:
    """Canonical symbol format for telemetry joins: BASE[.suffix-lower]."""
    raw = str(symbol or "").strip()
    if not raw:
        return ""
    if "." in raw:
        base, suffix = raw.split(".", 1)
        base_u = str(base).strip().upper()
        suf_l = str(suffix).strip().lower()
        return f"{base_u}.{suf_l}" if suf_l else base_u
    return raw.upper()

def symbol_alias_candidates(raw_symbol: str) -> List[str]:
    raw = str(raw_symbol or "").strip().upper()
    if not raw:
        return []
    out: List[str] = []
    seen = set()
    alias_cfg = getattr(CFG, "symbol_alias_map", {}) or {}
    for cand in alias_cfg.get(raw, (raw,)):
        key = str(cand or "").strip().upper()
        if key and key not in seen:
            seen.add(key)
            out.append(key)
    if raw not in seen:
        out.insert(0, raw)
    return out

def guess_group(symbol: str) -> str:
    return CFG.symbol_group_map.get(symbol_base(symbol), "OTHER")

def index_profile(symbol: str) -> str:
    return CFG.index_profile_map.get(symbol_base(symbol), "GEN")

def symbol_policy_block_reason(
    symbol: str,
    grp: str,
    *,
    info: Optional[object] = None,
    is_close: bool = False,
) -> Optional[str]:
    """Fail-closed policy for symbol classes on OANDA MT5."""
    if not bool(getattr(CFG, "symbol_policy_enabled", True)):
        return None
    if bool(is_close):
        return None

    grp_u = str(grp or "").strip().upper()
    allowed_groups = {
        str(x).strip().upper()
        for x in (getattr(CFG, "symbol_policy_allowed_groups", ("FX", "METAL", "INDEX", "CRYPTO", "EQUITY")) or ())
        if str(x).strip()
    }
    if bool(getattr(CFG, "symbol_policy_fail_on_other_group", True)) and grp_u not in allowed_groups:
        return f"group_blocked:{grp_u or 'UNKNOWN'}"

    sym_u = str(symbol or "").upper()
    for tok in (getattr(CFG, "symbol_policy_forbidden_symbol_markers", ()) or ()):
        t = str(tok or "").strip().upper()
        if t and t in sym_u:
            return f"forbidden_symbol_marker:{t}"

    info_path = ""
    try:
        info_path = str(getattr(info, "path", "") or "").upper()
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        info_path = ""
    if info_path:
        for tok in (getattr(CFG, "symbol_policy_forbidden_path_markers", ()) or ()):
            t = str(tok or "").strip().upper()
            if t and t in info_path:
                return f"forbidden_path_marker:{t}"
    return None

# =============================================================================
# SCOUT (read-only) — lokalnie (<HARD_ROOT>\META\scout_advice.json)
# =============================================================================

SCOUT_META_DIR = "META"
SCOUT_FILE_NAME = "scout_advice.json"
VERDICT_FILE_NAME = "verdict.json"
MARKET_SNAPSHOT_FILE_NAME = "market_snapshot.json"
DECISION_EVENTS_DB_NAME = "decision_events.sqlite"
M5_BARS_DB_NAME = "m5_bars.sqlite"
TICK_SNAPSHOTS_DB_NAME = "tick_snapshots.sqlite"

# --- DB migration constants (P0) ---
LEGACY_DB_NAMES = [
    "mt5_v1_10_1.sqlite",
    "mt5_state.sqlite",
    "safetybot_state.sqlite",
]

# SQLite PRAGMA user_version target for decision_events.sqlite
CURRENT_SCHEMA_VERSION = 4


SCOUT_MAX_BYTES = 256_000  # ochrona IO
SCOUT_MAX_AGE_SEC = 900
MAX_JSONL_LINE_LEN = 2048  # hard limit for a single JSONL line (used by SCUD JSONL; kept here for contract completeness)

_FORBIDDEN_PRICE_KEYS = (
    "bid","ask","open","high","low","close","ohlc","tick","ticks","candle","candles",
    "rate","rates","price","prices","quote","quotes","spread"
)

# -------------------------
# Limits: numeric token guard (Rulebook P0)
MAX_NUMERIC_TOKENS = 50
MAX_NUMERIC_LIST_LEN = 50

def _count_numeric_tokens(obj) -> int:
    if isinstance(obj, bool) or obj is None:
        return 0
    if isinstance(obj, (int, float)):
        return 1
    if isinstance(obj, dict):
        return sum(_count_numeric_tokens(v) for v in obj.values())
    if isinstance(obj, list):
        return sum(_count_numeric_tokens(v) for v in obj)
    return 0

def _has_numeric_list_over_limit(obj, limit: int = MAX_NUMERIC_LIST_LEN) -> bool:
    if isinstance(obj, list):
        if len(obj) > limit and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            return True
        return any(_has_numeric_list_over_limit(v, limit) for v in obj)
    if isinstance(obj, dict):
        return any(_has_numeric_list_over_limit(v, limit) for v in obj.values())
    return False

def guard_obj_limits(obj) -> None:
    """Raise ValueError if P0 numeric limits are exceeded."""
    if _has_numeric_list_over_limit(obj, MAX_NUMERIC_LIST_LEN):
        raise ValueError("P0_LIMIT_NUMERIC_LIST_GT_50")
    n = _count_numeric_tokens(obj)
    if n > MAX_NUMERIC_TOKENS:
        raise ValueError(f"P0_LIMIT_NUMERIC_TOKENS_GT_50:{n}")
# -------------------------
# -------------------------
# SCUD tie-break (RUN channel) — contract RUN pv=2 (strict, price-free)
# Request (pv=2 exact keys): pv, ts_utc, rid, ttl_sec, cands, mode, ctx
# Response (pv=2 exact keys): pv, ts_utc, rid, tb (0/1/2), pref, reasons
# SafetyBot applies response ONLY when tb == 1.
# -------------------------
TIEBREAK_REQ_NAME = "tiebreak_request.json"
TIEBREAK_RES_NAME = "tiebreak_response.json"

def validate_payload_limits(obj: dict, max_len: int = MAX_JSONL_LINE_LEN) -> bool:
    """Hard P0 gate for outbound JSON payloads (RUN/META)."""
    try:
        if _contains_forbidden_price_keys(obj):
            return False
        guard_obj_limits(obj)
        s = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if len(s) > int(max_len):
            return False
        return True
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return False

TIEBREAK_REQ_TTL_SEC = 30
TIEBREAK_RES_MAX_AGE_SEC = 30
TIEBREAK_WAIT_SEC = 0.35
TIEBREAK_POLL_SEC = 0.05
JSON_READ_RETRIES = 5
JSON_READ_RETRY_SLEEP_S = 0.04
ATOMIC_WRITE_RETRIES = 6
ATOMIC_WRITE_RETRY_SLEEP_S = 0.05

def _now_utc_iso() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def write_tiebreak_request(run_dir: Path, a: str, b: str, is_live: bool, ctx: Optional[Dict[str, Any]] = None) -> str:
    """Best-effort: write RUN/tiebreak_request.json (atomic). Never raises.
    Contract: RUN pv=2 strict. Returns rid or "".
    """
    try:
        run_dir.mkdir(parents=True, exist_ok=True)
        a0 = str(a).strip().upper()
        b0 = str(b).strip().upper()
        if not a0 or not b0 or a0 == b0:
            return ""
        rid = f"TB-{dt.datetime.now(tz=UTC).strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{int(time.time()*1000)%100000}"
        mode = ("LIVE" if is_live else "PAPER")
        note = ""
        if isinstance(ctx, dict):
            if isinstance(ctx.get("note"), str):
                note = ctx.get("note") or ""
            elif isinstance(ctx.get("reason"), str):
                note = ctx.get("reason") or ""
        note = str(note).strip()
        if len(note) > 128:
            note = note[:128]
        payload = {
            "pv": 2,
            "ts_utc": _now_utc_iso(),
            "rid": rid,
            "ttl_sec": int(TIEBREAK_REQ_TTL_SEC),
            "cands": [a0, b0],
            "mode": mode,
            "ctx": {"mode": mode, "note": note},
        }

        # strict schema check (pv==2, exact keys, types/ranges)
        if not cc.validate_run_request_v2(payload):
            payload["ctx"]["note"] = "ctx_trimmed"
            if not cc.validate_run_request_v2(payload):
                return ""

        # hard gates: price-like keys/values, numeric limits, serialized length
        if not validate_payload_limits(payload):
            payload["ctx"]["note"] = "payload_trimmed"
            if not validate_payload_limits(payload):
                return ""

        atomic_write_json(Path(run_dir) / TIEBREAK_REQ_NAME, payload)
        return rid
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return ""

def load_tiebreak_response(run_dir: Path, rec_id: str, pair: set) -> Optional[str]:
    """Read RUN/tiebreak_response.json if it matches rid and is fresh. Apply only when tb==1.
    Contract: RUN pv=2 strict.
    """
    try:
        path = Path(run_dir) / TIEBREAK_RES_NAME
        if not path.exists():
            return None
        if path.stat().st_size <= 0 or path.stat().st_size > 50_000:
            return None
        age = time.time() - path.stat().st_mtime
        if age < 0 or age > float(TIEBREAK_RES_MAX_AGE_SEC):
            return None
        data = _safe_read_json(path)
        if not data:
            return None
        if _contains_forbidden_price_keys(data):
            logging.warning("TIEBREAK RESP IGNORED | price-like keys/values detected")
            return None

        v = cc.validate_run_response_v2(data, rid_expected=str(rec_id).strip())
        if not v:
            return None
        if int(v.get("tb") or 0) != 1:
            return None
        pref = str(v.get("pref") or "").strip().upper()
        if pref and pref in pair:
            return pref
        return None
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None

def _parse_iso_utc(s: str) -> Optional[dt.datetime]:
    try:
        s = s.strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        d = dt.datetime.fromisoformat(s)
        if d.tzinfo is None:
            d = d.replace(tzinfo=UTC)
        return d.astimezone(UTC)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None

def atomic_write_json(path: Path, payload: Dict[str, Any]) -> None:
    """Atomic JSON write with retry/backoff and direct-write fallback for transient WinError 5 locks."""
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    tries = max(1, int(ATOMIC_WRITE_RETRIES))
    sleep_s = max(0.0, float(ATOMIC_WRITE_RETRY_SLEEP_S))
    last_exc: Optional[Exception] = None
    for i in range(tries):
        tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}.{i}")
        try:
            with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
                f.flush()
                try:
                    os.fsync(f.fileno())
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            os.replace(tmp, path)
            return
        except Exception as e:
            last_exc = e
        finally:
            try:
                if tmp.exists():
                    tmp.unlink(missing_ok=True)
            except Exception as exc:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", exc)

        # Fallback: direct overwrite (still with fsync).
        try:
            with open(path, "w", encoding="utf-8", newline="\n") as f2:
                f2.write(data)
                f2.flush()
                try:
                    os.fsync(f2.fileno())
                except Exception as e2:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e2)
            return
        except Exception as e:
            last_exc = e
            if i + 1 < tries:
                time.sleep(sleep_s)

    if last_exc is not None:
        raise last_exc
    raise IOError(f"atomic_write_json_failed:{path}")

def build_runtime_boot_snapshot_payload(runtime_root: Path, universe: List[Tuple[str, str, str]]) -> Dict[str, Any]:
    allowed_groups = [
        str(x).strip().upper()
        for x in (getattr(CFG, "symbol_policy_allowed_groups", ("FX", "METAL", "INDEX", "CRYPTO", "EQUITY")) or ())
        if str(x).strip()
    ]
    uni = []
    for raw, canon, grp in (universe or []):
        uni.append(
            {
                "raw": str(raw),
                "canon": str(canon),
                "group": str(grp),
                "base": symbol_base(str(canon)),
            }
        )
    return {
        "ts_utc": dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "runtime_root": str(Path(runtime_root)),
        "bot_version": str(getattr(CFG, "BOT_VERSION", "")),
        "limits": {
            "house_price_warn_per_day": int(getattr(CFG, "oanda_price_warning_per_day", 0)),
            "house_price_hard_stop_per_day": int(getattr(CFG, "oanda_price_cutoff_per_day", 0)),
            "house_orders_per_sec": int(getattr(CFG, "oanda_market_orders_per_sec", 0)),
            "house_positions_pending_limit": int(getattr(CFG, "oanda_positions_pending_limit", 0)),
            "price_budget_day": int(getattr(CFG, "price_budget_day", 0)),
            "order_budget_day": int(getattr(CFG, "order_budget_day", 0)),
            "sys_budget_day": int(getattr(CFG, "sys_budget_day", 0)),
        },
        "symbol_policy": {
            "enabled": bool(getattr(CFG, "symbol_policy_enabled", True)),
            "fail_on_other_group": bool(getattr(CFG, "symbol_policy_fail_on_other_group", True)),
            "allowed_groups": allowed_groups,
            "forbidden_symbol_markers": [str(x) for x in (getattr(CFG, "symbol_policy_forbidden_symbol_markers", ()) or ())],
            "forbidden_path_markers": [str(x) for x in (getattr(CFG, "symbol_policy_forbidden_path_markers", ()) or ())],
        },
        "policy_windows_v2": {
            "policy_windows_v2_enabled": bool(getattr(CFG, "policy_windows_v2_enabled", True)),
            "policy_risk_windows_enabled": bool(getattr(CFG, "policy_risk_windows_enabled", True)),
            "policy_group_arbitration_enabled": bool(getattr(CFG, "policy_group_arbitration_enabled", True)),
            "policy_overlap_arbitration_enabled": bool(getattr(CFG, "policy_overlap_arbitration_enabled", True)),
            "policy_shadow_mode_enabled": bool(getattr(CFG, "policy_shadow_mode_enabled", True)),
            "policy_runtime_file_name": str(getattr(CFG, "policy_runtime_file_name", "policy_runtime.json")),
        },
        "execution_burst_guard": {
            "enabled": bool(getattr(CFG, "execution_burst_guard_enabled", True)),
            "lookback_sec": int(getattr(CFG, "execution_burst_lookback_sec", 0)),
            "error_threshold": int(getattr(CFG, "execution_burst_error_threshold", 0)),
            "backoff_sec": int(getattr(CFG, "execution_burst_backoff_s", 0)),
            "symbol_cooldown_sec": int(getattr(CFG, "execution_burst_symbol_cooldown_s", 0)),
        },
        "universe_count": int(len(uni)),
        "universe": uni,
    }

def write_runtime_boot_snapshot(runtime_root: Path, universe: List[Tuple[str, str, str]]) -> Optional[Path]:
    try:
        payload = build_runtime_boot_snapshot_payload(runtime_root, universe)
        out_path = Path(runtime_root) / "EVIDENCE" / "runtime_boot_snapshot.json"
        atomic_write_json(out_path, payload)
        return out_path
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None

def _contains_forbidden_price_keys(obj: Any) -> bool:
    """Recursive P0 guard: price-like tokens in keys OR string values.
    Uses boundary/token match (no substring false-positives like mask->ask).
    """
    return cg.contains_price_like(obj)

def _safe_read_json(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    try:
        sz = path.stat().st_size
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None
    if sz <= 0 or sz > SCOUT_MAX_BYTES:
        return None
    tries = max(1, int(JSON_READ_RETRIES))
    for i in range(tries):
        try:
            raw = path.read_text(encoding="utf-8", errors="replace")
            obj = json.loads(raw)
            if not isinstance(obj, dict):
                return None
            return obj
        except json.JSONDecodeError:
            if i + 1 >= tries:
                return None
            time.sleep(float(JSON_READ_RETRY_SLEEP_S))
        except PermissionError:
            if i + 1 >= tries:
                return None
            time.sleep(float(JSON_READ_RETRY_SLEEP_S))
        except OSError:
            if i + 1 >= tries:
                return None
            time.sleep(float(JSON_READ_RETRY_SLEEP_S))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return None
    return None

def load_verdict(meta_dir: Path) -> Optional[Dict[str, Any]]:
    """Read META/verdict.json (Scout v1.1) with TTL guard (48h default)."""
    try:
        path = Path(meta_dir) / VERDICT_FILE_NAME
        data = _safe_read_json(path)
        if not data:
            return None
        if _contains_forbidden_price_keys(data):
            logging.warning("VERDICT IGNORED | forbidden price-like keys detected")
            return None
        ts = _parse_iso_utc(str(data.get("ts_utc", "") or ""))
        if ts is None:
            return None
        ttl = int(data.get("ttl_sec") or CFG.verdict_ttl_sec)
        wall_now_utc = dt.datetime.now(tz=UTC)
        age = (wall_now_utc - ts).total_seconds()
        if age < -5.0 or age > ttl:
            return None
        age = max(0.0, float(age))
        light = str(data.get("light") or "").upper()
        if light not in ("GREEN","YELLOW","RED","INSUFFICIENT_DATA"):
            return None
        return {"ts_utc": ts, "age_sec": float(age), "ttl_sec": ttl, "light": light, "raw": data}
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None

def load_scout_advice(meta_dir: Path) -> Optional[Dict[str, Any]]:
    """
    Scout v1.1 loader. Odrzuca jeśli:
    - brak pliku / błąd JSON
    - ts_utc starszy niż 10 minut (hard limit, niezależnie od ttl_sec w pliku)
    - payload zawiera pola wyglądające na kwotowania/ceny/rates (forbidden keys)
    """
    try:
        path = Path(meta_dir) / SCOUT_FILE_NAME
        data = _safe_read_json(path)
        if not data:
            return None
        if _contains_forbidden_price_keys(data):
            logging.warning("SCOUT IGNORED | forbidden price-like keys detected")
            return None

        ts = _parse_iso_utc(str(data.get("ts_utc", "") or ""))
        if ts is None:
            return None
        ttl = min(int(data.get("ttl_sec") or SCOUT_MAX_AGE_SEC), SCOUT_MAX_AGE_SEC)
        wall_now_utc = dt.datetime.now(tz=UTC)
        age = (wall_now_utc - ts).total_seconds()
        if age < -5.0:
            return None
        age = max(0.0, float(age))
        if age > ttl:
            logging.info(f"SCOUT STALE | age_sec={int(age)} > ttl_sec={ttl}")
            return None

        pref = str(data.get("preferred_symbol") or data.get("preferred") or "").strip().upper()
        ranks = data.get("ranks") or []
        topk_seen = data.get("topk_seen") or []
        notes = data.get("notes") or []
        if not pref and not ranks:
            return None

        return {
            "ts_utc": ts,
            "age_sec": float(age),
            "ttl_sec": ttl,
            "preferred_symbol": pref,
            "ranks": ranks if isinstance(ranks, list) else [],
            "topk_seen": topk_seen if isinstance(topk_seen, list) else [],
            "notes": notes if isinstance(notes, list) else [],
            "raw": data,
        }
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        logging.warning("SCOUT IGNORED | loader exception")
        return None


def load_unified_learning_advice(meta_dir: Path) -> Optional[Dict[str, Any]]:
    try:
        path = Path(meta_dir) / "unified_learning_advice.json"
        data = _safe_read_json(path)
        if not data:
            return None
        ts = _parse_iso_utc(str(data.get("generated_at_utc") or data.get("ts_utc") or ""))
        ttl = int(data.get("ttl_sec") or 0)
        instruments = data.get("instruments")
        if ts is None or ttl <= 0 or not isinstance(instruments, dict):
            return None
        wall_now_utc = dt.datetime.now(tz=UTC)
        age = (wall_now_utc - ts).total_seconds()
        if age < -5.0:
            return None
        age = max(0.0, float(age))
        if age > float(ttl):
            return None
        return {
            "ts_utc": ts,
            "age_sec": float(age),
            "ttl_sec": int(ttl),
            "runtime_light": data.get("runtime_light") if isinstance(data.get("runtime_light"), dict) else {},
            "instruments": instruments,
            "raw": data,
        }
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return None


def resolve_unified_learning_family_adjustment(
    *,
    unified: Optional[Dict[str, Any]],
    symbol: str,
    window_id: str,
    window_phase: str,
    strategy_family: str,
    min_samples: int,
    max_abs_delta: int,
) -> Dict[str, Any]:
    out = {
        "score_delta": 0,
        "advisory_bias": "NEUTRAL",
        "window": "",
        "strategy_family": str(strategy_family or "").upper(),
        "reasons": [],
        "matched_window_samples": 0,
        "matched_family_samples": 0,
    }
    if not isinstance(unified, dict):
        return out
    instruments = unified.get("instruments")
    if not isinstance(instruments, dict):
        return out
    sym = symbol_base(symbol)
    item = instruments.get(sym)
    if not isinstance(item, dict):
        return out

    bias = str(item.get("advisory_bias") or "NEUTRAL").strip().upper()
    out["advisory_bias"] = bias
    target_window = f"{str(window_id or '').upper()}|{str(window_phase or '').upper()}".strip("|")
    out["window"] = target_window
    target_family = str(strategy_family or "").strip().upper()
    min_samples = max(1, int(min_samples))
    max_abs_delta = max(0, int(max_abs_delta))
    score = 0.0
    reasons: List[str] = []

    def _feedback_payload_weight(payload_obj: Any) -> Tuple[float, str]:
        if not isinstance(payload_obj, dict):
            return 1.0, "INSUFFICIENT_DATA"
        leader = str(payload_obj.get("leader") or "INSUFFICIENT_DATA").strip().upper() or "INSUFFICIENT_DATA"
        try:
            weight_raw = float(payload_obj.get("learning_weight"))
        except Exception:
            weight_raw = 1.0
        weight = float(max(0.75, min(1.25, weight_raw)))
        return weight, leader

    if bias == "PROMOTE":
        score += 0.30
        reasons.append("symbol_promote")
    elif bias == "SUPPRESS":
        score -= 0.40
        reasons.append("symbol_suppress")

    def _apply_row(row_obj: Dict[str, Any], *, weight: float, label: str) -> None:
        nonlocal score
        rec = str(row_obj.get("recommendation") or "").strip().upper()
        try:
            avg = float(row_obj.get("counterfactual_pnl_points_avg") or 0.0)
        except Exception:
            avg = 0.0
        local = 0.0
        if rec == "DOCISKAJ_FILTRY":
            local -= 1.0
        elif rec == "ROZWAZ_LUZOWANIE_W_SHADOW":
            local += 0.85
        elif rec == "TRZYMAJ":
            if avg > 4.0:
                local += 0.20
            elif avg < -4.0:
                local -= 0.20
        if avg > 10.0:
            local += 0.10
        elif avg < -10.0:
            local -= 0.10
        score += float(local) * float(weight)
        reasons.append(f"{label}:{rec or 'NONE'}")

    matched_window = None
    for row_obj in (item.get("window_advisory") or []):
        if not isinstance(row_obj, dict):
            continue
        if str(row_obj.get("window") or "").strip().upper() != target_window:
            continue
        samples_n = int(row_obj.get("samples_n") or 0)
        if samples_n < min_samples:
            continue
        matched_window = row_obj
        out["matched_window_samples"] = samples_n
        break

    matched_family = None
    for row_obj in (item.get("strategy_family_advisory") or []):
        if not isinstance(row_obj, dict):
            continue
        if str(row_obj.get("window") or "").strip().upper() != target_window:
            continue
        if str(row_obj.get("strategy_family") or "").strip().upper() != target_family:
            continue
        samples_n = int(row_obj.get("samples_n") or 0)
        if samples_n < min_samples:
            continue
        matched_family = row_obj
        out["matched_family_samples"] = samples_n
        break

    if isinstance(matched_window, dict):
        _apply_row(matched_window, weight=0.35, label="window")
    if isinstance(matched_family, dict):
        _apply_row(matched_family, weight=0.75, label="family")

    global_feedback = None
    try:
        global_feedback = (((unified.get("raw") or {}).get("global") or {}).get("source_feedback"))
    except Exception:
        global_feedback = None
    symbol_feedback = item.get("source_feedback") if isinstance(item.get("source_feedback"), dict) else None
    window_feedback = matched_window.get("source_feedback") if isinstance(matched_window, dict) and isinstance(matched_window.get("source_feedback"), dict) else None
    family_feedback = matched_family.get("source_feedback") if isinstance(matched_family, dict) and isinstance(matched_family.get("source_feedback"), dict) else None

    feedback_weights: List[float] = []
    feedback_leaders: List[str] = []
    for feedback_obj in (global_feedback, symbol_feedback, window_feedback, family_feedback):
        weight_val, leader_val = _feedback_payload_weight(feedback_obj)
        if weight_val > 0.0:
            feedback_weights.append(weight_val)
        if leader_val and leader_val != "INSUFFICIENT_DATA":
            feedback_leaders.append(leader_val)
    effective_weight = float(sum(feedback_weights) / len(feedback_weights)) if feedback_weights else 1.0
    feedback_leader = feedback_leaders[0] if feedback_leaders else "INSUFFICIENT_DATA"
    score *= effective_weight
    if abs(effective_weight - 1.0) >= 0.03:
        reasons.append(f"feedback_weight:{effective_weight:.3f}")

    score = max(-1.0, min(1.0, float(score)))
    out["score_delta"] = int(max(-max_abs_delta, min(max_abs_delta, int(round(score * float(max_abs_delta))))))
    out["reasons"] = reasons
    out["feedback_weight"] = round(effective_weight, 6)
    out["feedback_leader"] = feedback_leader
    return out


def resolve_unified_learning_rank_adjustment(
    *,
    unified: Optional[Dict[str, Any]],
    symbol: str,
    window_id: str,
    window_phase: str,
    min_samples: int,
    max_bonus_pct: float,
) -> Dict[str, Any]:
    out = {
        "pct_bonus": 0.0,
        "prio_multiplier": 1.0,
        "advisory_bias": "NEUTRAL",
        "window": "",
        "reasons": [],
        "matched_window_samples": 0,
        "feedback_weight": 1.0,
        "feedback_leader": "INSUFFICIENT_DATA",
    }
    if not isinstance(unified, dict):
        return out
    instruments = unified.get("instruments")
    if not isinstance(instruments, dict):
        return out
    sym = symbol_base(symbol)
    item = instruments.get(sym)
    if not isinstance(item, dict):
        return out

    target_window = f"{str(window_id or '').upper()}|{str(window_phase or '').upper()}".strip("|")
    out["window"] = target_window
    bias = str(item.get("advisory_bias") or "NEUTRAL").strip().upper()
    out["advisory_bias"] = bias
    try:
        consensus = float(item.get("consensus_score"))
    except Exception:
        consensus = 0.0
    min_samples = max(1, int(min_samples))
    max_bonus_pct = float(max(0.0, min(float(max_bonus_pct), 0.20)))

    matched_window = None
    for row_obj in (item.get("window_advisory") or []):
        if not isinstance(row_obj, dict):
            continue
        if str(row_obj.get("window") or "").strip().upper() != target_window:
            continue
        samples_n = int(row_obj.get("samples_n") or 0)
        if samples_n < min_samples:
            continue
        matched_window = row_obj
        out["matched_window_samples"] = samples_n
        break

    score = 0.0
    reasons: List[str] = []
    if bias == "PROMOTE":
        score += 0.32
        reasons.append("symbol_promote")
    elif bias == "SUPPRESS":
        score -= 0.40
        reasons.append("symbol_suppress")

    score += float(max(-0.25, min(0.25, consensus * 0.55)))
    if abs(consensus) >= 0.05:
        reasons.append(f"consensus:{consensus:.3f}")

    if isinstance(matched_window, dict):
        rec = str(matched_window.get("recommendation") or "").strip().upper()
        try:
            avg = float(matched_window.get("avg_points"))
        except Exception:
            try:
                avg = float(matched_window.get("counterfactual_pnl_points_avg"))
            except Exception:
                avg = 0.0
        if rec == "DOCISKAJ_FILTRY":
            score -= 0.30
        elif rec == "ROZWAZ_LUZOWANIE_W_SHADOW":
            score += 0.26
        elif rec == "TRZYMAJ":
            score += float(max(-0.08, min(0.08, avg / 50.0)))
        if avg > 10.0:
            score += 0.04
        elif avg < -10.0:
            score -= 0.04
        reasons.append(f"window:{rec or 'NONE'}")

    def _feedback_payload_weight(payload_obj: Any) -> Tuple[float, str]:
        if not isinstance(payload_obj, dict):
            return 1.0, "INSUFFICIENT_DATA"
        leader = str(payload_obj.get("leader") or "INSUFFICIENT_DATA").strip().upper() or "INSUFFICIENT_DATA"
        try:
            weight_raw = float(payload_obj.get("learning_weight"))
        except Exception:
            weight_raw = 1.0
        weight = float(max(0.75, min(1.25, weight_raw)))
        return weight, leader

    global_feedback = None
    try:
        global_feedback = (((unified.get("raw") or {}).get("global") or {}).get("source_feedback"))
    except Exception:
        global_feedback = None
    symbol_feedback = item.get("source_feedback") if isinstance(item.get("source_feedback"), dict) else None
    window_feedback = matched_window.get("source_feedback") if isinstance(matched_window, dict) and isinstance(matched_window.get("source_feedback"), dict) else None

    feedback_weights: List[float] = []
    feedback_leaders: List[str] = []
    for feedback_obj in (global_feedback, symbol_feedback, window_feedback):
        weight_val, leader_val = _feedback_payload_weight(feedback_obj)
        if weight_val > 0.0:
            feedback_weights.append(weight_val)
        if leader_val and leader_val != "INSUFFICIENT_DATA":
            feedback_leaders.append(leader_val)
    effective_weight = float(sum(feedback_weights) / len(feedback_weights)) if feedback_weights else 1.0
    feedback_leader = feedback_leaders[0] if feedback_leaders else "INSUFFICIENT_DATA"
    score *= effective_weight
    if abs(effective_weight - 1.0) >= 0.03:
        reasons.append(f"feedback_weight:{effective_weight:.3f}")

    score = max(-1.0, min(1.0, float(score)))
    pct_bonus = float(max(-max_bonus_pct, min(max_bonus_pct, score * max_bonus_pct)))
    out["pct_bonus"] = round(pct_bonus, 6)
    out["prio_multiplier"] = round(1.0 + pct_bonus, 6)
    out["reasons"] = reasons
    out["feedback_weight"] = round(effective_weight, 6)
    out["feedback_leader"] = feedback_leader
    return out

def apply_scout_tiebreak(candidates: List[Tuple[float, str, str, str]],
                         scout: Optional[Dict[str, Any]],
                         verdict: Optional[Dict[str, Any]],
                         top_k: int,
                         is_live: bool,
                         run_dir: Optional[Path] = None) -> List[Tuple[float, str, str, str]]:
    """
    Tie-breaker (mode B) jest dopuszczony WYŁĄCZNIE gdy:
    - verdict.light == GREEN,
    - działa także w LIVE,
    - w Top-K istnieje "remis praktyczny" pomiędzy TOP-1 i TOP-2 (bez progów stałych; heurystyka na bazie rozkładu prio),
    - SCOUT wskazuje preferencję A/B (preferred_symbol) albo posiada rankingi pozwalające rozstrzygnąć parę.
    Nie zmienia logiki wejść/wyjść — tylko kolejność shortlisty (maksymalnie w obrębie TOP-2).
    """
    if not candidates or top_k <= 0:
        return candidates
    if not verdict or str(verdict.get("light") or "") != "GREEN":
        return candidates
    if not scout:
        return candidates

    if not has_near_tie_in_topk(candidates, top_k):
        return candidates

    view = candidates[:top_k]
    rest = candidates[top_k:]
    if len(view) < 2:
        return candidates

    a_raw = str(view[0][1]).strip().upper()
    b_raw = str(view[1][1]).strip().upper()
    pair = {a_raw, b_raw}

    # 0) RUN channel (on-demand): request + short wait for response (never blocks)
    chosen = ""
    if run_dir is not None:
        try:
            rec_id = write_tiebreak_request(Path(run_dir), a_raw, b_raw, is_live=is_live, ctx={'reason':'near_tie'})
            if rec_id:
                req_ts = time.time()
                deadline = time.time() + float(TIEBREAK_WAIT_SEC)
                while time.time() < deadline:
                    pref_run = load_tiebreak_response(Path(run_dir), rec_id=rec_id, pair=pair)
                    if pref_run:
                        chosen = pref_run
                        latency_ms = int((time.time() - req_ts) * 1000)
                        logging.info(
                            f"TIEBREAK_RESP | rid={rec_id} latency_ms={latency_ms} pair={a_raw}/{b_raw}"
                        )
                        break
                    time.sleep(float(TIEBREAK_POLL_SEC))
                if not chosen:
                    waited_ms = int((time.time() - req_ts) * 1000)
                    logging.info(
                        f"TIEBREAK_TIMEOUT | rid={rec_id} waited_ms={waited_ms} pair={a_raw}/{b_raw}"
                    )
                if chosen:
                    logging.info(f"SCOUT TIEBREAK | source=RUN | mode={'LIVE' if is_live else 'PAPER'} | choose={chosen} | pair={a_raw}/{b_raw}")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            chosen = ""

    # 1) Direct preferred (if within the tied pair)
    pref = str(scout.get("preferred_symbol") or scout.get("preferred") or "").strip().upper()
    chosen = chosen or (pref if pref in pair else "")

    # 2) Otherwise try ranks to resolve A/B (wyniki + ryzyko, bez cen/kwotowań)
    if not chosen:
        ranks = scout.get("ranks") or []
        # compare lexicographically: higher score/edge, higher es95, lower mdd, higher n
        metric_map: Dict[str, Tuple[float, float, float, int]] = {}
        if isinstance(ranks, list):
            for r in ranks:
                if not isinstance(r, dict):
                    continue
                sym = str(r.get("symbol") or r.get("raw") or "").strip().upper()
                if not sym:
                    continue
                # score-like (np. mean_edge_fuel), es95, mdd, n
                score = r.get("score")
                if not isinstance(score, (int, float)):
                    for k in ("scud_score", "edge_mean", "mean_edge_fuel"):
                        v = r.get(k)
                        if isinstance(v, (int, float)):
                            score = v
                            break
                esv = r.get("es95")
                mdd = r.get("mdd")
                n = r.get("n")
                if not isinstance(score, (int, float)):
                    continue
                esv_f = float(esv) if isinstance(esv, (int, float)) else 0.0
                mdd_f = float(mdd) if isinstance(mdd, (int, float)) else 0.0
                n_i = int(n) if isinstance(n, (int, float)) else 0
                metric_map[sym] = (float(score), esv_f, -mdd_f, n_i)

        ta = metric_map.get(a_raw)
        tb = metric_map.get(b_raw)
        if ta is not None and tb is not None:
            chosen = a_raw if ta >= tb else b_raw
        elif ta is not None:
            chosen = a_raw
        elif tb is not None:
            chosen = b_raw
    if not chosen or chosen == a_raw:
        return candidates

    logging.info(f"SCOUT TIEBREAK | mode={'LIVE' if is_live else 'PAPER'} | choose={chosen} | pair={a_raw}/{b_raw}")
    # bump chosen (which must be B) to the top of Top-K with minimal influence
    bumped = list(view)
    # find chosen index within view (only swap within top2)
    idx = None
    for i, (_, raw, _sym, _grp) in enumerate(bumped[:2]):
        if str(raw).strip().upper() == chosen:
            idx = i
            break
    if idx is None:
        return candidates

    prio, raw, sym, grp = bumped[idx]
    max_prio = max(x[0] for x in bumped)
    bumped[idx] = (max_prio + 0.001, raw, sym, grp)
    bumped.sort(key=lambda x: x[0], reverse=True)
    return bumped + rest

def has_near_tie_in_topk(candidates: List[Tuple[float, str, str, str]], top_k: int) -> bool:
    """Near-tie detector used to decide whether SCUD tie-break path is worth consulting."""
    if not candidates or int(top_k) <= 1:
        return False
    view = candidates[:int(top_k)]
    if len(view) < 2:
        return False
    prios = sorted((float(x[0]) for x in view), reverse=True)
    gaps = [prios[i] - prios[i + 1] for i in range(len(prios) - 1)]
    if not gaps:
        return True
    gap12 = prios[0] - prios[1]
    sorted_gaps = sorted(float(x) for x in gaps)
    n = len(sorted_gaps)
    mid = n // 2
    med_gap = sorted_gaps[mid] if (n % 2 == 1) else 0.5 * (sorted_gaps[mid - 1] + sorted_gaps[mid])
    return bool(gap12 <= med_gap)
def is_price_kind(kind: str) -> bool:
    return kind == "tick" or kind.startswith("rates_")


def pip_size_from_point(point: float, digits: int) -> float:
    p = float(point or 0.0)
    d = int(digits or 0)
    if p <= 0.0:
        return 0.0
    if d in (3, 5):
        return p * 10.0
    return p


def pips_to_price(pips: float, point: float, digits: int) -> float:
    ps = pip_size_from_point(point, digits)
    if ps <= 0.0:
        return 0.0
    return float(pips) * ps


def price_to_pips(delta_price: float, point: float, digits: int) -> float:
    ps = pip_size_from_point(point, digits)
    if ps <= 0.0:
        return 0.0
    return float(delta_price) / ps


def round_price_to_digits(price: float, digits: int) -> float:
    return float(round(float(price), int(max(0, digits))))

# =============================================================================
# P0 helpers: trade_mode / retcode mapping / budgets
# =============================================================================

def _trade_mode_name(mode_num: int) -> str:
    """Best-effort mapping for MetaTrader5 symbol trade modes."""
    try:
        m = int(mode_num)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return "UNKNOWN"
    # Prefer MetaTrader5 constants if present
    try:
        consts = {
            int(getattr(mt5, "SYMBOL_TRADE_MODE_DISABLED")): "DISABLED",
            int(getattr(mt5, "SYMBOL_TRADE_MODE_LONGONLY")): "LONGONLY",
            int(getattr(mt5, "SYMBOL_TRADE_MODE_SHORTONLY")): "SHORTONLY",
            int(getattr(mt5, "SYMBOL_TRADE_MODE_CLOSEONLY")): "CLOSEONLY",
            int(getattr(mt5, "SYMBOL_TRADE_MODE_FULL")): "FULL",
        }
        if m in consts:
            return consts[m]
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
    # Fallback (common MT5 enum values; conservative)
    fallback = {0: "DISABLED", 1: "LONGONLY", 2: "SHORTONLY", 3: "CLOSEONLY", 4: "FULL"}
    return fallback.get(m, "UNKNOWN")

_RETCODE_FALLBACK = {
    10004: "TRADE_RETCODE_REQUOTE",
    10006: "TRADE_RETCODE_REJECT",
    10007: "TRADE_RETCODE_CANCEL",
    10008: "TRADE_RETCODE_PLACED",
    10009: "TRADE_RETCODE_DONE",
    10010: "TRADE_RETCODE_DONE_PARTIAL",
    10011: "TRADE_RETCODE_ERROR",
    10012: "TRADE_RETCODE_TIMEOUT",
    10013: "TRADE_RETCODE_INVALID",
    10014: "TRADE_RETCODE_INVALID_VOLUME",
    10015: "TRADE_RETCODE_INVALID_PRICE",
    10016: "TRADE_RETCODE_INVALID_STOPS",
    10017: "TRADE_RETCODE_TRADE_DISABLED",
    10018: "TRADE_RETCODE_MARKET_CLOSED",
    10019: "TRADE_RETCODE_NO_MONEY",
    10020: "TRADE_RETCODE_PRICE_CHANGED",
    10021: "TRADE_RETCODE_PRICE_OFF",
    10022: "TRADE_RETCODE_INVALID_EXPIRATION",
    10023: "TRADE_RETCODE_ORDER_CHANGED",
    10024: "TRADE_RETCODE_TOO_MANY_REQUESTS",
    10025: "TRADE_RETCODE_NO_CHANGES",
    10026: "TRADE_RETCODE_SERVER_DISABLES_AT",
    10027: "TRADE_RETCODE_CLIENT_DISABLES_AT",
    10028: "TRADE_RETCODE_LOCKED",
    10029: "TRADE_RETCODE_FROZEN",
    10030: "TRADE_RETCODE_INVALID_FILL",
    10031: "TRADE_RETCODE_CONNECTION",
    10032: "TRADE_RETCODE_ONLY_REAL",
    10033: "TRADE_RETCODE_LIMIT_ORDERS",
    10034: "TRADE_RETCODE_LIMIT_VOLUME",
    10035: "TRADE_RETCODE_INVALID_ORDER",
    10036: "TRADE_RETCODE_POSITION_CLOSED",
    10038: "TRADE_RETCODE_INVALID_CLOSE_VOLUME",
    10039: "TRADE_RETCODE_CLOSE_ORDER_EXIST",
    10040: "TRADE_RETCODE_LIMIT_POSITIONS",
    10041: "TRADE_RETCODE_REJECT_CANCEL",
    10042: "TRADE_RETCODE_LONG_ONLY",
    10043: "TRADE_RETCODE_SHORT_ONLY",
    10044: "TRADE_RETCODE_CLOSE_ONLY",
    10045: "TRADE_RETCODE_FIFO_CLOSE",
    10046: "TRADE_RETCODE_HEDGE_PROHIBITED",
}

def _retcode_name(retcode_num: int) -> str:
    try:
        n = int(retcode_num)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return "TRADE_RETCODE_UNKNOWN"
    # Prefer constants from mt5 if they match (best-effort)
    try:
        for k, v in mt5.__dict__.items():
            if isinstance(v, int) and v == n and str(k).startswith("TRADE_RETCODE_"):
                return str(k)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
    return _RETCODE_FALLBACK.get(n, "TRADE_RETCODE_UNKNOWN")

def _seconds_until_next_ny_midnight(now_utc_dt: dt.datetime) -> int:
    """Deterministic: seconds until next NY day (00:00) based on ZoneInfo."""
    try:
        ny = now_utc_dt.astimezone(TZ_NY)
        next_midnight = (ny.replace(hour=0, minute=0, second=0, microsecond=0) + dt.timedelta(days=1))
        delta = next_midnight - ny
        return max(1, int(delta.total_seconds()))
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return int(CFG.cooldown_budget_s)

def _seconds_until_next_utc_midnight(now_utc_dt: dt.datetime) -> int:
    """Deterministic: seconds until next UTC day (00:00) based on timezone-aware datetime."""
    try:
        utc = now_utc_dt.astimezone(UTC)
        next_midnight = (utc.replace(hour=0, minute=0, second=0, microsecond=0) + dt.timedelta(days=1))
        delta = next_midnight - utc
        return max(1, int(delta.total_seconds()))
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return int(CFG.cooldown_budget_s)

def _seconds_until_next_pl_midnight(now_utc_dt: dt.datetime) -> int:
    """Deterministic: seconds until next PL day (00:00 Europe/Warsaw) based on ZoneInfo."""
    try:
        pl = now_utc_dt.astimezone(TZ_PL)
        next_midnight = (pl.replace(hour=0, minute=0, second=0, microsecond=0) + dt.timedelta(days=1))
        delta = next_midnight - pl
        return max(1, int(delta.total_seconds()))
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return int(CFG.cooldown_budget_s)

class DecisionEventStore:
    """SQLite store for decision events (readable by Scout; write-only by SafetyBot)."""
    def __init__(self, db_dir: Path):
        self.db_dir = db_dir
        self.db_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.db_dir / DECISION_EVENTS_DB_NAME
        self.conn = sqlite3.connect(str(self.db_path), timeout=5, isolation_level=None, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL;")
        self.conn.execute("PRAGMA synchronous=NORMAL;")
        self.conn.execute("PRAGMA foreign_keys=ON;")
        self._init_schema()

    def _init_schema(self) -> None:
        self.conn.execute(
            """CREATE TABLE IF NOT EXISTS decision_events (
                event_id TEXT PRIMARY KEY,
                ts_utc TEXT NOT NULL,
                server_time_anchor TEXT,
                topk_json TEXT NOT NULL,
                choice_A TEXT NOT NULL,
                choice_shadowB TEXT,
                verdict_light TEXT,
                signal TEXT,
                sl REAL,
                tp REAL,
                entry_price REAL,
                volume REAL,
                spread_points REAL,
                price_used INT,
                price_requests_trade INT,
                sys_used INT,
                is_paper INT,
                mt5_order INT,
                mt5_deal INT,
                outcome_pnl_net REAL,
                outcome_profit REAL,
                outcome_commission REAL,
                outcome_swap REAL,
                outcome_fee REAL,
                outcome_closed_ts_utc TEXT,
                -- v3 (scalp-learning context; additive)
                grp TEXT,
                window_id TEXT,
                window_phase TEXT,
                window_group TEXT,
                global_mode TEXT,
                symbol_mode TEXT,
                prio REAL,
                time_weight REAL,
                score_factor REAL,
                group_factor REAL,
                signal_reason TEXT,
                strategy_family TEXT,
                regime TEXT,
                adx REAL,
                atr_points REAL,
                spread_p80 REAL,
                spread_cap_points REAL,
                entry_score INT,
                entry_min_score INT,
                risk_entry_allowed INT,
                risk_reason TEXT,
                risk_friday INT,
                risk_reopen INT,
                eco_active INT,
                black_swan_flag INT,
                black_swan_precaution INT,
                self_heal_active INT,
                canary_active INT,
                drift_active INT,
                snapshot_block_new_entries INT,
                fx_bucket_idx INT,
                fx_bucket_count INT,
                carryover_active INT,
                mt5_retcode INT,
                mt5_retcode_name TEXT,
                bot_version TEXT,
                policy_shadow_mode INT,
                policy_windows_v2_enabled INT,
                policy_risk_windows_enabled INT,
                policy_group_arbitration_enabled INT,
                policy_overlap_arbitration_enabled INT
            );"""
        )
        try:
            event_cols_now = {str(r[1]) for r in self.conn.execute("PRAGMA table_info(decision_events)").fetchall()}
            if "strategy_family" not in event_cols_now:
                self.conn.execute("ALTER TABLE decision_events ADD COLUMN strategy_family TEXT;")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_ts ON decision_events(ts_utc);")
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_choice ON decision_events(choice_A);")
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_closed ON decision_events(outcome_closed_ts_utc);")
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_grp_closed ON decision_events(grp, outcome_closed_ts_utc);")
        self.conn.execute(
            """CREATE TABLE IF NOT EXISTS decision_rejections (
                reject_id TEXT PRIMARY KEY,
                ts_utc TEXT NOT NULL,
                symbol TEXT,
                grp TEXT,
                mode TEXT,
                reason_code TEXT NOT NULL,
                reason_class TEXT,
                stage TEXT,
                signal TEXT,
                strategy_family TEXT,
                regime TEXT,
                window_id TEXT,
                window_phase TEXT,
                context_json TEXT
            );"""
        )
        # Additive migration for early table versions.
        try:
            cols_now = {str(r[1]) for r in self.conn.execute("PRAGMA table_info(decision_rejections)").fetchall()}
            if "window_id" not in cols_now:
                self.conn.execute("ALTER TABLE decision_rejections ADD COLUMN window_id TEXT;")
            if "window_phase" not in cols_now:
                self.conn.execute("ALTER TABLE decision_rejections ADD COLUMN window_phase TEXT;")
            if "strategy_family" not in cols_now:
                self.conn.execute("ALTER TABLE decision_rejections ADD COLUMN strategy_family TEXT;")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_rejections_ts ON decision_rejections(ts_utc);")
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_rejections_symbol_ts ON decision_rejections(symbol, ts_utc);")
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_rejections_reason_ts ON decision_rejections(reason_code, ts_utc);")

    def insert_event(self, row: Dict[str, Any]) -> None:
        cols = [
            "event_id","ts_utc","server_time_anchor","topk_json","choice_A","choice_shadowB","verdict_light",
            "signal","sl","tp","entry_price","volume","spread_points",
            "price_used","price_requests_trade","sys_used","is_paper","mt5_order","mt5_deal",
            "outcome_pnl_net","outcome_profit","outcome_commission","outcome_swap","outcome_fee","outcome_closed_ts_utc",
            # v3 (scalp-learning context)
            "grp","window_id","window_phase","window_group","global_mode","symbol_mode",
            "prio","time_weight","score_factor","group_factor",
            "signal_reason","strategy_family","regime","adx","atr_points","spread_p80","spread_cap_points",
            "entry_score","entry_min_score",
            "risk_entry_allowed","risk_reason","risk_friday","risk_reopen",
            "eco_active","black_swan_flag","black_swan_precaution","self_heal_active","canary_active","drift_active",
            "snapshot_block_new_entries","fx_bucket_idx","fx_bucket_count","carryover_active",
            "mt5_retcode","mt5_retcode_name","bot_version",
            "policy_shadow_mode","policy_windows_v2_enabled","policy_risk_windows_enabled",
            "policy_group_arbitration_enabled","policy_overlap_arbitration_enabled",
        ]
        vals = [row.get(c) for c in cols]
        q = "INSERT OR REPLACE INTO decision_events (" + ",".join(cols) + ") VALUES (" + ",".join(["?"]*len(cols)) + ")"
        sqlite_exec_retry(self.conn, q, vals)

    def apply_deal(self, event_id: str, profit: float, commission: float, swap: float, fee: float, closed_ts_utc: str) -> None:
        # accumulate (in case of multiple deals); keep last closed_ts_utc
        cur = sqlite_exec_retry(self.conn,
            "SELECT outcome_profit,outcome_commission,outcome_swap,outcome_fee FROM decision_events WHERE event_id=?",
            (event_id,),
        ).fetchone()
        if not cur:
            return
        op, oc, osw, ofee = cur
        op = float(op or 0.0) + float(profit or 0.0)
        oc = float(oc or 0.0) + float(commission or 0.0)
        osw = float(osw or 0.0) + float(swap or 0.0)
        ofee = float(ofee or 0.0) + float(fee or 0.0)
        pnl = op + oc + osw + ofee
        sqlite_exec_retry(self.conn,
            """UPDATE decision_events
               SET outcome_profit=?, outcome_commission=?, outcome_swap=?, outcome_fee=?, outcome_pnl_net=?, outcome_closed_ts_utc=?
               WHERE event_id=?""",
            (op, oc, osw, ofee, pnl, closed_ts_utc, event_id),
        )

    def insert_rejection(self, row: Dict[str, Any]) -> None:
        cols = [
            "reject_id",
            "ts_utc",
            "symbol",
            "grp",
            "mode",
            "reason_code",
            "reason_class",
            "stage",
            "signal",
            "strategy_family",
            "regime",
            "window_id",
            "window_phase",
            "context_json",
        ]
        vals = [row.get(c) for c in cols]
        q = "INSERT OR REPLACE INTO decision_rejections (" + ",".join(cols) + ") VALUES (" + ",".join(["?"] * len(cols)) + ")"
        sqlite_exec_retry(self.conn, q, vals)

class M5BarsStore:
    """Lightweight SQLite store for M5 bars (used by Scout evaluator)."""
    def __init__(self, db_dir: Path):
        self.db_dir = db_dir
        self.db_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.db_dir / M5_BARS_DB_NAME
        self._lock = threading.Lock()
        self.conn = sqlite3.connect(str(self.db_path), timeout=5, isolation_level=None, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL;")
        self.conn.execute("PRAGMA synchronous=NORMAL;")
        self.conn.execute("PRAGMA foreign_keys=ON;")
        self.conn.execute(
            """CREATE TABLE IF NOT EXISTS m5_bars (
                symbol TEXT NOT NULL,
                t_utc TEXT NOT NULL,
                o REAL, h REAL, l REAL, c REAL,
                PRIMARY KEY(symbol, t_utc)
            );"""
        )
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_m5_bars_sym_t ON m5_bars(symbol, t_utc);")

    def upsert_df(self, base_symbol: str, df: "pd.DataFrame") -> None:
        if df is None or len(df) == 0:
            return
        # store only last 60 bars to limit IO
        tail = df.tail(60)
        rows = []
        for _, r in tail.iterrows():
            # df["time"] is TZ_PL; convert to UTC iso
            try:
                t_utc = r["time"].tz_convert(UTC).to_pydatetime()
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                continue
            rows.append((base_symbol, t_utc.replace(tzinfo=UTC).isoformat().replace("+00:00","Z"),
                         float(r["open"]), float(r["high"]), float(r["low"]), float(r["close"])))
        with self._lock:
            self.conn.executemany("INSERT OR REPLACE INTO m5_bars(symbol,t_utc,o,h,l,c) VALUES (?,?,?,?,?,?)", rows)

    def upsert_bar_snapshot(self, base_symbol: str, bar: Dict[str, Any]) -> bool:
        """Persist one BAR snapshot received from MQL5 over ZMQ."""
        try:
            ts = int(bar.get("time") or 0)
            if ts <= 0:
                return False
            # Some MT5 servers expose epoch-like values shifted by server timezone.
            # Reuse common offset detector/converter before persisting BAR history.
            _maybe_update_mt5_server_epoch_offset(
                int(ts),
                source="zmq_bar",
                max_age_s=max(300, int(getattr(CFG, "hybrid_snapshot_bar_max_age_sec", 900))),
            )
            t_utc = mt5_epoch_to_utc_dt(int(ts)).replace(microsecond=0)
            row = (
                str(base_symbol),
                t_utc.isoformat().replace("+00:00", "Z"),
                float(bar.get("open")),
                float(bar.get("high")),
                float(bar.get("low")),
                float(bar.get("close")),
            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return False
        with self._lock:
            sqlite_exec_retry(
                self.conn,
                "INSERT OR REPLACE INTO m5_bars(symbol,t_utc,o,h,l,c) VALUES (?,?,?,?,?,?)",
                row,
            )
        return True

    def read_recent_df(self, base_symbol: str, limit: int) -> Optional["pd.DataFrame"]:
        """Read recent bars as dataframe compatible with indicator pipeline."""
        lim = max(1, int(limit))
        with self._lock:
            rows = sqlite_exec_retry(
                self.conn,
                "SELECT t_utc,o,h,l,c FROM m5_bars WHERE symbol=? ORDER BY t_utc DESC LIMIT ?",
                (str(base_symbol), int(lim)),
            ).fetchall()
        if not rows:
            return None
        rows = list(reversed(rows))
        out = pd.DataFrame(rows, columns=["t_utc", "open", "high", "low", "close"])
        ts = pd.to_datetime(out["t_utc"], utc=True, errors="coerce")
        out["time"] = ts.dt.tz_convert(TZ_PL)
        out = out.dropna(subset=["time"]).copy()
        if out.empty:
            return None
        for c in ("open", "high", "low", "close"):
            out[c] = pd.to_numeric(out[c], errors="coerce")
        out = out.dropna(subset=["open", "high", "low", "close"]).copy()
        if out.empty:
            return None
        return out[["time", "open", "high", "low", "close"]].reset_index(drop=True)

    def read_resampled_df(self, base_symbol: str, timeframe_min: int, limit: int) -> Optional["pd.DataFrame"]:
        """
        Build synthetic higher timeframe bars from stored M5 stream.
        Used as no-fetch fallback for trend inputs (H4/D1).
        """
        tf = max(1, int(timeframe_min))
        lim = max(1, int(limit))
        m5_per_bar = max(1, int(round(tf / 5.0)))
        pull_n = max(lim * m5_per_bar + (m5_per_bar * 8), 512)
        with self._lock:
            rows = sqlite_exec_retry(
                self.conn,
                "SELECT t_utc,o,h,l,c FROM m5_bars WHERE symbol=? ORDER BY t_utc DESC LIMIT ?",
                (str(base_symbol), int(pull_n)),
            ).fetchall()
        if not rows:
            return None
        rows = list(reversed(rows))
        out = pd.DataFrame(rows, columns=["t_utc", "open", "high", "low", "close"])
        out["time_utc"] = pd.to_datetime(out["t_utc"], utc=True, errors="coerce")
        out = out.dropna(subset=["time_utc"]).copy()
        if out.empty:
            return None
        for c in ("open", "high", "low", "close"):
            out[c] = pd.to_numeric(out[c], errors="coerce")
        out = out.dropna(subset=["open", "high", "low", "close"]).copy()
        if out.empty:
            return None

        out = out.set_index("time_utc")
        rs = out.resample(f"{tf}min", label="right", closed="right").agg(
            {"open": "first", "high": "max", "low": "min", "close": "last"}
        )
        rs = rs.dropna(subset=["open", "high", "low", "close"]).copy()
        if rs.empty:
            return None
        rs = rs.tail(lim)
        rs = rs.reset_index()
        rs["time"] = rs["time_utc"].dt.tz_convert(TZ_PL)
        return rs[["time", "open", "high", "low", "close"]].reset_index(drop=True)


def inspect_m5_store_readiness(
    store: Any,
    base_symbol: str,
    need_rows: int,
    now_ts: float,
    *,
    timeframe_min: int,
) -> Dict[str, Any]:
    """
    Lightweight readiness check for local M5 store.

    Used to distinguish:
    - real short history / missing bars
    - stale but otherwise complete local store
    """
    state: Dict[str, Any] = {
        "rows": 0,
        "fresh_ok": False,
        "stale": False,
        "age_s": None,
        "max_age_sec": None,
        "last_bar_utc": None,
        "df": None,
    }
    if store is None:
        return state
    try:
        df = store.read_recent_df(str(base_symbol), max(1, int(need_rows)))
    except Exception:
        return state
    if df is None or len(df) == 0:
        return state

    rows = int(len(df))
    state["rows"] = rows
    state["df"] = df
    try:
        ts = pd.Timestamp(df["time"].iloc[-1])
        if ts.tzinfo is None:
            ts = ts.tz_localize(TZ_PL)
        ts_utc = ts.tz_convert(UTC)
        age_s = max(0.0, float(now_ts) - float(ts_utc.timestamp()))
        trade_tf = int(getattr(CFG, "timeframe_trade", 5))
        max_age_base = max(5, int(getattr(CFG, "hybrid_snapshot_max_age_sec", 180)))
        max_age_bar = max(max_age_base, int(getattr(CFG, "hybrid_snapshot_bar_max_age_sec", 900)))
        if int(timeframe_min) > int(trade_tf):
            max_age = max(max_age_bar, int(timeframe_min) * 60 + max(120, int(trade_tf) * 60))
        else:
            max_age = max_age_bar
        state.update(
            {
                "age_s": float(age_s),
                "max_age_sec": int(max_age),
                "last_bar_utc": ts_utc.replace(microsecond=0).isoformat(),
                "fresh_ok": bool(age_s <= float(max_age)),
                "stale": bool(age_s > float(max_age)),
            }
        )
    except Exception:
        return state
    return state


class TickSnapshotsStore:
    """SQLite tick snapshot store for Renko/offline analytics (no direct trading decisions)."""

    def __init__(self, db_dir: Path):
        self.db_dir = db_dir
        self.db_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.db_dir / TICK_SNAPSHOTS_DB_NAME
        self._lock = threading.Lock()
        self._last_ts_msc: Dict[str, int] = {}
        self._last_bid_ask: Dict[str, Tuple[float, float]] = {}
        self._insert_counter: Dict[str, int] = {}
        self.conn = sqlite3.connect(str(self.db_path), timeout=5, isolation_level=None, check_same_thread=False)
        self.conn.execute("PRAGMA journal_mode=WAL;")
        self.conn.execute("PRAGMA synchronous=NORMAL;")
        self.conn.execute("PRAGMA foreign_keys=ON;")
        self.conn.execute(
            """
            CREATE TABLE IF NOT EXISTS tick_snapshots (
                symbol TEXT NOT NULL,
                ts_utc TEXT NOT NULL,
                ts_msc INTEGER NOT NULL,
                bid REAL NOT NULL,
                ask REAL NOT NULL,
                mid REAL NOT NULL,
                spread_points REAL,
                point REAL,
                digits INTEGER,
                recv_ts_utc TEXT,
                PRIMARY KEY(symbol, ts_msc)
            );
            """
        )
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS ix_tick_snapshots_symbol_ts_msc ON tick_snapshots(symbol, ts_msc);"
        )

    def _prune_symbol(self, symbol: str, keep_rows: int) -> None:
        keep = max(1000, int(keep_rows))
        cur = sqlite_exec_retry(
            self.conn,
            """
            SELECT ts_msc
            FROM tick_snapshots
            WHERE symbol=?
            ORDER BY ts_msc DESC
            LIMIT 1 OFFSET ?
            """,
            (str(symbol), int(keep - 1)),
        ).fetchone()
        if not cur:
            return
        cutoff = int(cur[0] or 0)
        if cutoff <= 0:
            return
        sqlite_exec_retry(
            self.conn,
            "DELETE FROM tick_snapshots WHERE symbol=? AND ts_msc < ?",
            (str(symbol), int(cutoff)),
        )

    def upsert_tick_snapshot(self, base_symbol: str, tick: Dict[str, Any], recv_ts: float) -> bool:
        if not bool(getattr(CFG, "renko_tick_store_enabled", True)):
            return False
        try:
            symbol = str(base_symbol or "").strip().upper()
            if not symbol:
                return False

            ts_msc = int(tick.get("timestamp_ms") or 0)
            if ts_msc <= 0:
                return False
            ts_sec = int(ts_msc // 1000)
            _maybe_update_mt5_server_epoch_offset(
                int(ts_sec),
                source="zmq_tick",
                max_age_s=max(10, int(getattr(CFG, "hybrid_snapshot_max_age_sec", 180))),
            )
            ts_utc = mt5_epoch_to_utc_dt(int(ts_sec)).replace(microsecond=0).isoformat().replace("+00:00", "Z")
            recv_ts_utc = dt.datetime.fromtimestamp(float(max(0.0, recv_ts)), tz=UTC).replace(
                microsecond=0
            ).isoformat().replace("+00:00", "Z")

            bid = float(tick.get("bid", 0.0) or 0.0)
            ask = float(tick.get("ask", 0.0) or 0.0)
            if bid <= 0.0 or ask <= 0.0:
                return False
            mid = (bid + ask) * 0.5
            point = float(tick.get("point", 0.0) or 0.0)
            spread_pts = float(tick.get("spread_points", 0.0) or 0.0)
            if spread_pts <= 0.0 and point > 0.0:
                spread_pts = max(0.0, (ask - bid) / point)
            digits = int(tick.get("digits", 0) or 0)

            min_interval_ms = max(0, int(getattr(CFG, "renko_tick_store_min_interval_ms", 200)))
            min_delta_pts = float(max(0.0, float(getattr(CFG, "renko_tick_store_min_price_delta_points", 0.0))))
            prev_ts_msc = int(self._last_ts_msc.get(symbol, 0) or 0)
            if prev_ts_msc > 0 and (ts_msc - prev_ts_msc) < min_interval_ms:
                return False

            prev_bid, prev_ask = self._last_bid_ask.get(symbol, (0.0, 0.0))
            if min_delta_pts > 0.0 and point > 0.0 and prev_bid > 0.0 and prev_ask > 0.0:
                delta_pts = max(abs(bid - prev_bid), abs(ask - prev_ask)) / point
                if delta_pts < min_delta_pts:
                    return False

            row = (
                symbol,
                ts_utc,
                int(ts_msc),
                float(bid),
                float(ask),
                float(mid),
                float(spread_pts),
                float(point),
                int(digits),
                recv_ts_utc,
            )
            with self._lock:
                sqlite_exec_retry(
                    self.conn,
                    """
                    INSERT OR REPLACE INTO tick_snapshots(
                        symbol, ts_utc, ts_msc, bid, ask, mid, spread_points, point, digits, recv_ts_utc
                    ) VALUES (?,?,?,?,?,?,?,?,?,?)
                    """,
                    row,
                )
                self._last_ts_msc[symbol] = int(ts_msc)
                self._last_bid_ask[symbol] = (float(bid), float(ask))
                n = int(self._insert_counter.get(symbol, 0) or 0) + 1
                self._insert_counter[symbol] = n
                prune_every = max(10, int(getattr(CFG, "renko_tick_store_prune_every", 500)))
                if (n % prune_every) == 0:
                    keep_rows = max(1000, int(getattr(CFG, "renko_tick_store_max_rows_per_symbol", 120000)))
                    self._prune_symbol(symbol, keep_rows)
            return True
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return False

    def read_recent_ticks(self, base_symbol: str, limit: int = 4000) -> List[Dict[str, Any]]:
        symbol = str(base_symbol or "").strip().upper()
        if not symbol:
            return []
        lim = max(1, int(limit))
        with self._lock:
            rows = sqlite_exec_retry(
                self.conn,
                """
                SELECT ts_utc, ts_msc, bid, ask, mid, spread_points, point, digits, recv_ts_utc
                FROM tick_snapshots
                WHERE symbol=?
                ORDER BY ts_msc DESC
                LIMIT ?
                """,
                (symbol, int(lim)),
            ).fetchall()
        out: List[Dict[str, Any]] = []
        for row in reversed(rows):
            out.append(
                {
                    "symbol": symbol,
                    "ts_utc": row[0],
                    "ts_msc": int(row[1]),
                    "bid": float(row[2]),
                    "ask": float(row[3]),
                    "mid": float(row[4]),
                    "spread_points": (None if row[5] is None else float(row[5])),
                    "point": (None if row[6] is None else float(row[6])),
                    "digits": (None if row[7] is None else int(row[7])),
                    "recv_ts_utc": row[8],
                }
            )
        return out


class RequestGovernor:
    """
    Ogranicza:
    - PRICE: tick + rates -> cap 400/d (NY day) z rezerwą awaryjną
    - SYS: pozostałe -> osobny cap
    Dodatkowo: cap dzienny per grupa (FX/METAL/INDEX) na PRICE z możliwością pożyczania.
    """
    def __init__(self, db: Persistence):
        self.db = db
        self.price_day_cap = int(CFG.price_budget_day)
        self.price_emergency = int(self.price_day_cap * CFG.price_emergency_reserve_fraction)
        self.price_trade_budget = max(0, self.price_day_cap - self.price_emergency)
        self.price_soft = int(self.price_trade_budget * CFG.price_soft_fraction)

        self.order_day_cap = int(CFG.order_budget_day)
        self.order_emergency = int(max(0, self.order_day_cap * float(getattr(CFG, "order_emergency_reserve_fraction", 0.10))))
        self.order_emergency = int(min(self.order_day_cap, self.order_emergency))
        self.order_trade_budget = max(0, self.order_day_cap - self.order_emergency)

        self.sys_day_cap = int(getattr(CFG, 'sys_budget_day', CFG.sys_day_cap))
        sys_em_abs = int(max(0, int(getattr(CFG, "sys_emergency_reserve", 0))))
        sys_em_frac = float(max(0.0, float(getattr(CFG, "sys_emergency_reserve_fraction", 0.0))))
        sys_em_from_frac = int(max(0, self.sys_day_cap * sys_em_frac))
        self.sys_emergency = int(min(max(sys_em_abs, sys_em_from_frac), max(0, self.sys_day_cap)))
        self.sys_trade_budget = max(0, self.sys_day_cap - self.sys_emergency)
        self.sys_soft = int(self.sys_trade_budget * CFG.sys_soft_fraction)
    def _group_price_cap(self, grp: str) -> int:
        """Dzienny cap PRICE dla grupy, liczony z price_trade_budget wg CFG.group_price_shares (znormalizowane)."""
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return int(self.price_trade_budget)
        total = 0.0
        for v in shares.values():
            try:
                total += max(0.0, float(v))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                total += 0.0
        if total <= 0.0:
            return int(self.price_trade_budget)
        try:
            w = max(0.0, float(shares.get(grp, 0.0))) / total
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            w = 0.0
        cap = int(self.price_trade_budget * w)
        return max(0, cap)

    def _group_window_unlock_ratio(self, grp: str, now_dt: Optional[dt.datetime] = None) -> float:
        """
        Session-aware unlock ratio [0..1] for a group.
        - before group window starts: 0.0
        - in window: proportional unlock
        - after window end: 1.0
        If group has no configured windows, fallback to PL-day progress.
        """
        now_u = now_dt if isinstance(now_dt, dt.datetime) else now_utc()
        tw = getattr(CFG, "trade_windows", {}) or {}
        gk = _group_key(grp)

        windows: List[Tuple[ZoneInfo, Tuple[int, int], Tuple[int, int]]] = []
        if isinstance(tw, dict):
            for _wid, w in tw.items():
                if not isinstance(w, dict):
                    continue
                if _group_key(str(w.get("group") or "")) != gk:
                    continue
                try:
                    tz = ZoneInfo(str(w.get("anchor_tz") or "Europe/Warsaw"))
                except Exception:
                    tz = TZ_PL
                start_raw = w.get("start_hm", (0, 0))
                end_raw = w.get("end_hm", (23, 59))
                try:
                    sh = (int(start_raw[0]), int(start_raw[1]))
                    eh = (int(end_raw[0]), int(end_raw[1]))
                except Exception:
                    sh, eh = (0, 0), (23, 59)
                windows.append((tz, sh, eh))

        if not windows:
            now_pl = now_u.astimezone(TZ_PL)
            day_start = now_pl.replace(hour=0, minute=0, second=0, microsecond=0)
            elapsed = float((now_pl - day_start).total_seconds())
            ratio = max(0.0, min(1.0, elapsed / 86400.0))
        else:
            total_s = 0.0
            elapsed_s = 0.0
            for tz, sh, eh in windows:
                local_now = now_u.astimezone(tz)
                start = local_now.replace(hour=int(sh[0]), minute=int(sh[1]), second=0, microsecond=0)
                end = local_now.replace(hour=int(eh[0]), minute=int(eh[1]), second=0, microsecond=0)
                if (int(sh[0]), int(sh[1])) == (int(eh[0]), int(eh[1])):
                    return 1.0
                ref = local_now
                if end <= start:
                    end = end + dt.timedelta(days=1)
                    if ref < start:
                        ref = ref + dt.timedelta(days=1)
                dur = float((end - start).total_seconds())
                if dur <= 0.0:
                    continue
                total_s += dur
                elapsed = float((ref - start).total_seconds())
                if elapsed <= 0.0:
                    continue
                elapsed_s += min(dur, elapsed)
            ratio = 1.0 if total_s <= 0.0 else max(0.0, min(1.0, elapsed_s / total_s))

        try:
            unlock_power = float(getattr(CFG, "group_borrow_unlock_power", 1.0) or 1.0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            unlock_power = 1.0
        unlock_power = max(0.05, min(4.0, unlock_power))
        return float(max(0.0, min(1.0, float(ratio) ** float(unlock_power))))

    def _borrow_fraction_for_group(self, grp: str, now_dt: Optional[dt.datetime] = None) -> float:
        if not bool(getattr(CFG, "policy_group_arbitration_enabled", True)):
            return 0.0
        if bool(getattr(CFG, "policy_shadow_mode_enabled", True)):
            return 0.0
        base_frac = float(getattr(CFG, "group_borrow_fraction", 0.0) or 0.0)
        grp_u = _group_key(grp)
        frac = _cfg_group_map_float("group_borrow_fraction_by_group", grp_u, base_frac)
        if bool(getattr(CFG, "policy_overlap_arbitration_enabled", True)) and us_overlap_window_active(now_dt):
            if grp_u == "INDEX":
                frac += 0.10
            elif grp_u in {"FX", "CRYPTO"}:
                frac *= 0.80
        return float(max(0.0, min(1.0, frac)))

    def _group_borrow_allowance(self, grp: str, now_dt: Optional[dt.datetime] = None) -> int:
        """Ile grupa może \"pożyczyć\" z niewykorzystanych capów innych grup (CFG.group_borrow_fraction)."""
        if not bool(getattr(CFG, "policy_group_arbitration_enabled", True)):
            return 0
        rs = group_market_risk_state(grp, now_dt=now_dt)
        if bool(rs.get("borrow_blocked")):
            return 0
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return 0
        frac = self._borrow_fraction_for_group(grp, now_dt=now_dt)
        if frac <= 0.0:
            return 0
        unused_other = 0.0
        for g in shares.keys():
            if _group_key(g) == _group_key(grp):
                continue
            cap_g = int(self._group_price_cap(g))
            used_g = int(self.db.group_price_used_today(g))
            unlocked = int(float(cap_g) * self._group_window_unlock_ratio(g, now_dt=now_dt))
            transferable = max(0, min(cap_g, unlocked) - used_g)
            unused_other += float(transferable)
        return int(unused_other * float(frac))

    def order_group_cap(self, grp: str) -> int:
        """Dzienny cap ORDER dla grupy, liczony z puli order_trade_budget wg udziałów grup."""
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return int(self.order_trade_budget)
        total = 0.0
        for v in shares.values():
            try:
                total += max(0.0, float(v))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                total += 0.0
        if total <= 0.0:
            return int(self.order_trade_budget)
        try:
            w = max(0.0, float(shares.get(grp, 0.0))) / total
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            w = 0.0
        return max(0, int(self.order_trade_budget * w))

    def order_group_borrow_allowance(self, grp: str, now_dt: Optional[dt.datetime] = None) -> int:
        """Ile grupa ORDER może pożyczyć z niewykorzystanej puli innych grup."""
        if not bool(getattr(CFG, "policy_group_arbitration_enabled", True)):
            return 0
        rs = group_market_risk_state(grp, now_dt=now_dt)
        if bool(rs.get("borrow_blocked")):
            return 0
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return 0
        frac = self._borrow_fraction_for_group(grp, now_dt=now_dt)
        if frac <= 0.0:
            return 0
        unused_other = 0.0
        for g in shares.keys():
            if _group_key(g) == _group_key(grp):
                continue
            cap_g = int(self.order_group_cap(g))
            used_g = int(self.db.get_order_group_actions_day(g))
            unlocked = int(float(cap_g) * self._group_window_unlock_ratio(g, now_dt=now_dt))
            transferable = max(0, min(cap_g, unlocked) - used_g)
            unused_other += float(transferable)
        return int(unused_other * float(frac))

    def sys_group_cap(self, grp: str) -> int:
        """Dzienny cap SYS dla grupy, liczony z puli sys_trade_budget wg udziałów grup."""
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return int(self.sys_trade_budget)
        total = 0.0
        for v in shares.values():
            try:
                total += max(0.0, float(v))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                total += 0.0
        if total <= 0.0:
            return int(self.sys_trade_budget)
        try:
            w = max(0.0, float(shares.get(grp, 0.0))) / total
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            w = 0.0
        return max(0, int(self.sys_trade_budget * w))

    def sys_group_borrow_allowance(self, grp: str, now_dt: Optional[dt.datetime] = None) -> int:
        """Ile grupa SYS może pożyczyć z niewykorzystanej puli innych grup."""
        if not bool(getattr(CFG, "policy_group_arbitration_enabled", True)):
            return 0
        rs = group_market_risk_state(grp, now_dt=now_dt)
        if bool(rs.get("borrow_blocked")):
            return 0
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return 0
        frac = self._borrow_fraction_for_group(grp, now_dt=now_dt)
        if frac <= 0.0:
            return 0
        unused_other = 0.0
        for g in shares.keys():
            if _group_key(g) == _group_key(grp):
                continue
            cap_g = int(self.sys_group_cap(g))
            used_g = int(self.db.group_sys_used_today(g))
            unlocked = int(float(cap_g) * self._group_window_unlock_ratio(g, now_dt=now_dt))
            transferable = max(0, min(cap_g, unlocked) - used_g)
            unused_other += float(transferable)
        return int(unused_other * float(frac))

    def group_budget_state(self, grp: str, now_dt: Optional[dt.datetime] = None) -> Dict[str, Any]:
        """
        Compact per-group budget snapshot used by arbitration and telemetry.
        Values are safe-clamped and include borrow allowances at current session progress.
        """
        g = _group_key(grp)
        now_u = now_dt if isinstance(now_dt, dt.datetime) else now_utc()
        unlock = float(self._group_window_unlock_ratio(g, now_dt=now_u))
        rs = group_market_risk_state(g, now_dt=now_u)

        price_cap = int(max(0, self._group_price_cap(g)))
        order_cap = int(max(0, self.order_group_cap(g)))
        sys_cap = int(max(0, self.sys_group_cap(g)))

        price_borrow = int(max(0, self._group_borrow_allowance(g, now_dt=now_u)))
        order_borrow = int(max(0, self.order_group_borrow_allowance(g, now_dt=now_u)))
        sys_borrow = int(max(0, self.sys_group_borrow_allowance(g, now_dt=now_u)))

        try:
            price_used = int(max(0, self.db.group_price_used_today(g)))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            price_used = 0
        try:
            order_used = int(max(0, self.db.get_order_group_actions_day(g, now_dt=now_u, emergency=False)))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            order_used = 0
        try:
            sys_used = int(max(0, self.db.group_sys_used_today(g)))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            sys_used = 0

        def _ratio(used: int, cap: int, borrow: int) -> float:
            denom = max(1, int(cap) + int(borrow))
            return float(max(0.0, min(2.0, float(used) / float(denom))))

        price_usage = _ratio(price_used, price_cap, price_borrow)
        order_usage = _ratio(order_used, order_cap, order_borrow)
        sys_usage = _ratio(sys_used, sys_cap, sys_borrow)

        return {
            "group": str(g),
            "unlock_ratio": float(unlock),
            "risk_entry_allowed": float(1.0 if bool(rs.get("entry_allowed")) else 0.0),
            "risk_borrow_blocked": float(1.0 if bool(rs.get("borrow_blocked")) else 0.0),
            "risk_priority_factor": float(rs.get("priority_factor", 1.0)),
            "risk_friday": float(1.0 if bool(rs.get("friday_risk")) else 0.0),
            "risk_reopen": float(1.0 if bool(rs.get("reopen_guard")) else 0.0),
            "risk_reason": str(rs.get("reason", "NONE")),
            "price_used": float(price_used),
            "price_cap": float(price_cap),
            "price_borrow": float(price_borrow),
            "price_usage_ratio": float(price_usage),
            "price_remaining": float(max(0, (price_cap + price_borrow) - price_used)),
            "order_used": float(order_used),
            "order_cap": float(order_cap),
            "order_borrow": float(order_borrow),
            "order_usage_ratio": float(order_usage),
            "order_remaining": float(max(0, (order_cap + order_borrow) - order_used)),
            "sys_used": float(sys_used),
            "sys_cap": float(sys_cap),
            "sys_borrow": float(sys_borrow),
            "sys_usage_ratio": float(sys_usage),
            "sys_remaining": float(max(0, (sys_cap + sys_borrow) - sys_used)),
        }

    def group_priority_factor(self, grp: str, now_dt: Optional[dt.datetime] = None) -> float:
        """
        Dynamic group arbitration factor:
        - penalizes groups already near their effective budgets
        - allows per-group priority_boost tuning via CFG.per_group.<GROUP>.priority_boost
        """
        g = _group_key(grp)
        if bool(getattr(CFG, "policy_group_arbitration_enabled", True)) and (
            not bool(getattr(CFG, "policy_shadow_mode_enabled", True))
        ):
            return float(effective_group_priority_factor(g, now_dt=now_dt))

        st = self.group_budget_state(g, now_dt=now_dt)
        pressure = float(
            max(
                float(st.get("price_usage_ratio", 0.0)),
                float(st.get("order_usage_ratio", 0.0)),
                float(st.get("sys_usage_ratio", 0.0)),
            )
        )
        unlock = float(st.get("unlock_ratio", 0.0))

        try:
            boost = float(_cfg_group_float(g, "priority_boost", 1.0))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            boost = 1.0

        try:
            w = float(getattr(CFG, "group_priority_pressure_weight", 0.45) or 0.45)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            w = 0.45
        w = max(0.0, min(1.0, w))

        # Small uplift for unlocked low-pressure windows to reduce idle budget.
        uplift = 0.12 * max(0.0, 1.0 - pressure) * max(0.0, min(1.0, unlock))
        raw = float(boost) * (1.0 - (w * pressure) + uplift)
        rs = group_market_risk_state(g, now_dt=now_dt)
        raw *= float(rs.get("priority_factor", 1.0))

        try:
            f_min = float(getattr(CFG, "group_priority_min_factor", 0.65) or 0.65)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            f_min = 0.65
        try:
            f_max = float(getattr(CFG, "group_priority_max_factor", 1.30) or 1.30)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            f_max = 1.30
        lo = max(0.30, min(float(f_min), float(f_max)))
        hi = max(lo, min(2.00, float(f_max)))
        return float(max(lo, min(hi, raw)))


    def day_state(self) -> Dict[str, int]:
        # Day keys (analytics + enforcement)
        c_ny = self.db.get_day_counts()
        now_dt = now_utc()
        day_ny, _ = ny_day_hour_key(now_dt)
        utc_day = utc_day_key(now_dt)
        pl_day = pl_day_key(now_dt)

        # PRICE counts (trade vs emergency) per day type
        ny_price = int(c_ny["price"])
        ny_price_em = int(c_ny["price_em"])
        utc_price = int(self.db.get_day_counter("PRICE", "utc", utc_day, emergency=False))
        utc_price_em = int(self.db.get_day_counter("PRICE", "utc", utc_day, emergency=True))
        pl_price = int(self.db.get_day_counter("PRICE", "pl", pl_day, emergency=False))
        pl_price_em = int(self.db.get_day_counter("PRICE", "pl", pl_day, emergency=True))

        # SYS counts
        ny_sys = int(c_ny["sys"])
        ny_sys_em = int(c_ny["sys_em"])
        utc_sys = int(self.db.get_day_counter("SYS", "utc", utc_day, emergency=False))
        utc_sys_em = int(self.db.get_day_counter("SYS", "utc", utc_day, emergency=True))
        pl_sys = int(self.db.get_day_counter("SYS", "pl", pl_day, emergency=False))
        pl_sys_em = int(self.db.get_day_counter("SYS", "pl", pl_day, emergency=True))

        policy = str(getattr(CFG, "calendar_day_policy", "") or "").upper()
        # Primary: PL (Warsaw) by default (matches user's day boundary). We still keep a hard guard across NY/UTC/PL.
        if policy in {"PL_WARSAW", "PL"}:
            pri_price, pri_price_em = pl_price, pl_price_em
            pri_sys, pri_sys_em = pl_sys, pl_sys_em
            pri_day_key = pl_day
        elif policy == "UTC":
            pri_price, pri_price_em = utc_price, utc_price_em
            pri_sys, pri_sys_em = utc_sys, utc_sys_em
            pri_day_key = utc_day
        else:
            # Fallback: strict-min behavior
            pri_price, pri_price_em = max(ny_price, utc_price, pl_price), max(ny_price_em, utc_price_em, pl_price_em)
            pri_sys, pri_sys_em = max(ny_sys, utc_sys, pl_sys), max(ny_sys_em, utc_sys_em, pl_sys_em)
            pri_day_key = pl_day

        # Hard guard across plausible "calendar day" interpretations
        price_guard_used = max(ny_price, utc_price, pl_price)
        price_guard_em_used = max(ny_price_em, utc_price_em, pl_price_em)
        sys_guard_used = max(ny_sys, utc_sys, pl_sys)
        sys_guard_em_used = max(ny_sys_em, utc_sys_em, pl_sys_em)

        # Used values reported as primary; remaining is guarded to avoid exceed under other keys.
        price_used = int(pri_price)
        price_em_used = int(pri_price_em)
        sys_used = int(pri_sys)
        sys_em_used = int(pri_sys_em)

        price_remaining_primary = max(0, int(self.price_trade_budget) - int(pri_price))
        price_remaining_guard = max(0, int(self.price_trade_budget) - int(price_guard_used))
        price_remaining = int(min(price_remaining_primary, price_remaining_guard))

        price_em_remaining_primary = max(0, int(self.price_emergency) - int(pri_price_em))
        price_em_remaining_guard = max(0, int(self.price_emergency) - int(price_guard_em_used))
        price_em_remaining = int(min(price_em_remaining_primary, price_em_remaining_guard))

        sys_remaining_primary = max(0, int(self.sys_trade_budget) - int(pri_sys))
        sys_remaining_guard = max(0, int(self.sys_trade_budget) - int(sys_guard_used))
        sys_remaining = int(min(sys_remaining_primary, sys_remaining_guard))

        sys_em_remaining_primary = max(0, int(self.sys_emergency) - int(pri_sys_em))
        sys_em_remaining_guard = max(0, int(self.sys_emergency) - int(sys_guard_em_used))
        sys_em_remaining = int(min(sys_em_remaining_primary, sys_em_remaining_guard))

        # Totals for logs/eco heuristics (primary + guard)
        price_requests_day = int(pri_price + pri_price_em)
        sys_requests_day = int(pri_sys + pri_sys_em)
        price_requests_day_guard = int(price_guard_used + price_guard_em_used)
        sys_requests_day_guard = int(sys_guard_used + sys_guard_em_used)

        order_st = self.db.get_order_actions_state(now_dt=now_dt)
        order_actions_day = int(order_st.get('used') or 0)
        return {
            "day_ny": day_ny,
            "utc_day": utc_day,
            "pl_day": pl_day,

            # Effective day key used for ORDER actions and daily scheduling
            "day_primary": str(pri_day_key),

            # PRICE (tick + rates)
            "price_used": int(price_used),
            "price_em_used": int(price_em_used),
            "price_requests_day": int(price_requests_day),
            "price_requests_day_guard": int(price_requests_day_guard),
            "price_budget": int(self.price_day_cap),
            "price_remaining": int(price_remaining),
            "price_em_remaining": int(price_em_remaining),

            # SYS
            "sys_used": int(sys_used),
            "sys_em_used": int(sys_em_used),
            "sys_requests_day": int(sys_requests_day),
            "sys_requests_day_guard": int(sys_requests_day_guard),
            "sys_budget": int(self.sys_day_cap),
            "sys_remaining": int(sys_remaining),
            "sys_em_remaining": int(sys_em_remaining),

            # ORDER actions/day
            "order_actions_day": int(order_actions_day),
            "order_budget": int(CFG.order_budget_day),
            "order_trade_budget": int(self.order_trade_budget),
            "order_em_budget": int(self.order_emergency),

            "order_actions_ny": int(order_st.get("ny") or 0),
            "order_actions_utc": int(order_st.get("utc") or 0),
            "order_actions_pl": int(order_st.get("pl") or 0),

            # Debug-only breakdowns
            "price_used_ny": int(ny_price),
            "price_used_utc": int(utc_price),
            "price_used_pl": int(pl_price),
            "price_em_used_ny": int(ny_price_em),
            "price_em_used_utc": int(utc_price_em),
            "price_em_used_pl": int(pl_price_em),

            "sys_used_ny": int(ny_sys),
            "sys_used_utc": int(utc_sys),
            "sys_used_pl": int(pl_sys),
            "sys_em_used_ny": int(ny_sys_em),
            "sys_em_used_utc": int(utc_sys_em),
            "sys_em_used_pl": int(pl_sys_em),
        }

    def price_soft_mode(self) -> bool:
        """
        Soft mode for PRICE budget.
        True means: stop opening new entries and keep budget for safety/maintenance.
        """
        try:
            st = self.day_state()
            # Soft threshold translated to "remaining budget" guard.
            # Example: soft=96% of trade budget => trigger when <=4% remains.
            soft_remaining = max(0, int(self.price_trade_budget) - int(self.price_soft))
            return int(st.get("price_remaining", 0)) <= int(soft_remaining)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            # Fail-safe: if we cannot determine budget state, prefer soft mode.
            return True

    def sys_soft_mode(self) -> bool:
        """Soft mode for SYS budget (limit non-critical system requests)."""
        try:
            st = self.day_state()
            soft_remaining = max(0, int(self.sys_trade_budget) - int(self.sys_soft))
            return int(st.get("sys_remaining", 0)) <= int(soft_remaining)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return True

    def can_consume(self, grp: str, symbol: str, kind: str, cost: int = 1, emergency: bool = False) -> bool:
        cat = "PRICE" if is_price_kind(kind) else "SYS"
        st = self.day_state()
        now_ref = now_utc()

        if cat == "PRICE":
            if emergency:
                if st["price_em_remaining"] < cost:
                    return False
            else:
                if st["price_remaining"] < cost:
                    return False
                # cap per grupa (z pożyczką)
                if grp in CFG.group_price_shares:
                    used_g = self.db.group_price_used_today(grp)
                    cap_g = self._group_price_cap(grp)
                    if used_g + cost > cap_g + self._group_borrow_allowance(grp, now_dt=now_ref):
                        return False
        else:
            if emergency:
                if st["sys_em_remaining"] < cost:
                    return False
            else:
                if st["sys_remaining"] < cost:
                    return False
                if grp in CFG.group_price_shares:
                    used_g = self.db.group_sys_used_today(grp)
                    cap_g = self.sys_group_cap(grp)
                    if used_g + cost > cap_g + self.sys_group_borrow_allowance(grp, now_dt=now_ref):
                        return False
        return True

    def consume(self, grp: str, symbol: str, kind: str, cost: int = 1, emergency: bool = False) -> bool:
        if not self.can_consume(grp, symbol, kind, cost=cost, emergency=emergency):
            return False
        cat = "PRICE" if is_price_kind(kind) else "SYS"
        self.db.inc_request(cat, grp, symbol, kind, int(cost), bool(emergency))
        return True

# =============================================================================
# THROTTLE ORDERS
# =============================================================================

class OrderThrottle:
    def __init__(self):
        self.last_order_time = 0.0
        self.orders_last_min: List[float] = []
        self.orders_last_hour: List[float] = []

    def can_trade(self) -> bool:
        if mt5 is None:
            return False
        now = time.time()
        if now - self.last_order_time < CFG.min_seconds_between_orders:
            return False
        self.orders_last_min = [t for t in self.orders_last_min if now - t < 60]
        self.orders_last_hour = [t for t in self.orders_last_hour if now - t < 3600]
        if len(self.orders_last_min) >= CFG.max_orders_per_minute:
            return False
        if len(self.orders_last_hour) >= CFG.max_orders_per_hour:
            return False
        return True

    def register_trade(self):
        now = time.time()
        self.last_order_time = now
        self.orders_last_min.append(now)
        self.orders_last_hour.append(now)


class ExecutionQueue:
    """Single-writer dispatcher for order submissions.

    WHY: serializes non-emergency order flow through one worker thread, so
    different strategy paths cannot race on parallel `order_send` calls.
    """

    def __init__(self, engine: "ExecutionEngine"):
        self.engine = engine
        self.enabled = bool(getattr(CFG, "execution_queue_enabled", True))
        self.maxsize = max(1, int(getattr(CFG, "execution_queue_maxsize", 256)))
        self.submit_timeout_sec = max(1, int(getattr(CFG, "execution_queue_submit_timeout_sec", 20)))
        self.backpressure_enabled = bool(getattr(CFG, "execution_queue_backpressure_enabled", True))
        self.backpressure_high_watermark = float(
            getattr(CFG, "execution_queue_backpressure_high_watermark", 0.85)
        )
        self.backpressure_high_watermark = min(0.99, max(0.10, self.backpressure_high_watermark))
        self.backpressure_warn_interval_sec = max(
            1,
            int(getattr(CFG, "execution_queue_backpressure_warn_interval_sec", 30)),
        )
        self.wait_warn_ms = max(100, int(getattr(CFG, "execution_queue_wait_warn_ms", 1000)))
        self._queue: "pyqueue.Queue[Optional[Dict[str, Any]]]" = pyqueue.Queue(maxsize=self.maxsize)
        self._stop_evt = threading.Event()
        self._worker: Optional[threading.Thread] = None
        self._worker_ident: int = 0
        self._seq = 0
        self._seq_lock = threading.Lock()
        self._last_backpressure_log_ts: float = 0.0
        self._metric_backpressure_drops: int = 0
        self._metric_queue_full: int = 0
        self._metric_queue_timeout: int = 0
        self._metric_wait_warn: int = 0

    def _next_seq(self) -> int:
        with self._seq_lock:
            self._seq += 1
            return int(self._seq)

    def start(self) -> None:
        if not self.enabled:
            return
        if self._worker is not None and self._worker.is_alive():
            return
        self._stop_evt.clear()
        self._worker = threading.Thread(
            target=self._run,
            name="SafetyBot-OrderWriter",
            daemon=True,
        )
        self._worker.start()
        logging.info("ORDER_QUEUE_START enabled=1 maxsize=%s", int(self.maxsize))

    def _fill_ratio(self) -> float:
        try:
            return float(self._queue.qsize()) / float(max(1, int(self.maxsize)))
        except Exception:
            return 0.0

    def metrics_snapshot(self) -> Dict[str, Any]:
        return {
            "enabled": bool(self.enabled),
            "maxsize": int(self.maxsize),
            "qsize": int(self._queue.qsize()),
            "fill_ratio": float(round(self._fill_ratio(), 4)),
            "backpressure_drops": int(self._metric_backpressure_drops),
            "queue_full": int(self._metric_queue_full),
            "queue_timeout": int(self._metric_queue_timeout),
            "wait_warn": int(self._metric_wait_warn),
        }

    def stop(self, timeout_sec: float = 5.0) -> None:
        if not self.enabled:
            return
        self._stop_evt.set()
        try:
            self._queue.put_nowait(None)
        except Exception as exc:
            logging.debug("ORDER_QUEUE_STOP_WAKEUP_FAIL %s", exc)
        worker = self._worker
        if worker is not None and worker.is_alive():
            worker.join(timeout=max(0.1, float(timeout_sec)))
        alive = int(bool(worker is not None and worker.is_alive()))
        logging.info("ORDER_QUEUE_STOP alive=%s", int(alive))

    def _run(self) -> None:
        self._worker_ident = int(threading.get_ident())
        while not self._stop_evt.is_set():
            try:
                item = self._queue.get(timeout=0.5)
            except pyqueue.Empty:
                continue
            if item is None:
                self._queue.task_done()
                break
            done_evt = item["done_evt"]
            box = item["box"]
            symbol = str(item["symbol"])
            grp = str(item["grp"])
            request = dict(item["request"] or {})
            emergency = bool(item["emergency"])
            seq = int(item["seq"])
            t0 = float(time.perf_counter())
            try:
                box["res"] = self.engine.order_send(symbol, grp, request, emergency=emergency)
            except Exception as e:
                box["exc"] = repr(e)
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            finally:
                run_ms = int((time.perf_counter() - t0) * 1000.0)
                if run_ms >= 500:
                    logging.warning(
                        "ORDER_QUEUE_SLOW seq=%s symbol=%s grp=%s run_ms=%s emergency=%s",
                        int(seq),
                        symbol,
                        grp,
                        int(run_ms),
                        int(emergency),
                    )
                done_evt.set()
                self._queue.task_done()

    def submit(self, symbol: str, grp: str, request: dict, emergency: bool = False, timeout_sec: Optional[int] = None):
        if not self.enabled:
            return self.engine.order_send(symbol, grp, request, emergency=bool(emergency))
        # Emergency closes bypass queue to reduce flatten latency.
        if emergency:
            return self.engine.order_send(symbol, grp, request, emergency=True)
        worker_alive = bool(self._worker is not None and self._worker.is_alive())
        if not worker_alive:
            self.start()
        if int(threading.get_ident()) == int(self._worker_ident or 0):
            # avoid deadlock if called re-entrantly from worker
            return self.engine.order_send(symbol, grp, request, emergency=bool(emergency))

        if self.backpressure_enabled:
            qsize = int(self._queue.qsize())
            fill_ratio = float(qsize) / float(max(1, int(self.maxsize)))
            if fill_ratio >= float(self.backpressure_high_watermark):
                self._metric_backpressure_drops = int(self._metric_backpressure_drops) + 1
                now_ts = float(time.time())
                if (now_ts - float(self._last_backpressure_log_ts)) >= float(self.backpressure_warn_interval_sec):
                    self._last_backpressure_log_ts = now_ts
                    logging.warning(
                        "ORDER_QUEUE_BACKPRESSURE_DROP symbol=%s grp=%s qsize=%s maxsize=%s fill_ratio=%.3f threshold=%.3f",
                        str(symbol),
                        str(grp),
                        int(qsize),
                        int(self.maxsize),
                        float(fill_ratio),
                        float(self.backpressure_high_watermark),
                    )
                return None

        done_evt = threading.Event()
        box: Dict[str, Any] = {}
        seq = self._next_seq()
        item = {
            "seq": int(seq),
            "symbol": str(symbol),
            "grp": str(grp),
            "request": dict(request or {}),
            "emergency": bool(emergency),
            "done_evt": done_evt,
            "box": box,
        }
        t_enqueue = float(time.perf_counter())
        try:
            self._queue.put(item, timeout=1.0)
        except pyqueue.Full:
            self._metric_queue_full = int(self._metric_queue_full) + 1
            logging.warning(
                "ORDER_QUEUE_FULL seq=%s symbol=%s grp=%s qsize=%s",
                int(seq),
                str(symbol),
                str(grp),
                int(self._queue.qsize()),
            )
            return None

        wait_timeout = int(timeout_sec) if timeout_sec is not None else int(self.submit_timeout_sec)
        wait_timeout = max(1, int(wait_timeout))
        if not done_evt.wait(timeout=float(wait_timeout)):
            self._metric_queue_timeout = int(self._metric_queue_timeout) + 1
            logging.warning(
                "ORDER_QUEUE_TIMEOUT seq=%s symbol=%s grp=%s timeout_s=%s qsize=%s",
                int(seq),
                str(symbol),
                str(grp),
                int(wait_timeout),
                int(self._queue.qsize()),
            )
            return None
        queue_wait_ms = int((time.perf_counter() - t_enqueue) * 1000.0)
        if queue_wait_ms >= int(self.wait_warn_ms):
            self._metric_wait_warn = int(self._metric_wait_warn) + 1
            logging.warning(
                "ORDER_QUEUE_WAIT_HIGH seq=%s symbol=%s grp=%s wait_ms=%s",
                int(seq),
                str(symbol),
                str(grp),
                int(queue_wait_ms),
            )
        if "exc" in box:
            logging.error(
                "ORDER_QUEUE_WORKER_EXC seq=%s symbol=%s grp=%s err=%s",
                int(seq),
                str(symbol),
                str(grp),
                str(box.get("exc")),
            )
            return None
        return box.get("res")

# =============================================================================
# MT5 CLIENT
# =============================================================================

class ExecutionEngine:
    def __init__(self, config: Dict[str, str], gov: RequestGovernor, limits: Optional[OandaLimitsGuard] = None):
        self.login = int(config["MT5_LOGIN"])
        self.password = config["MT5_PASSWORD"]
        self.server = config["MT5_SERVER"]
        self.path = config.get("MT5_PATH", str(REQUIRED_OANDA_MT5_EXE))
        self.gov = gov
        self.limits = limits
        self.connected = False
        self._sym_info_cache: Dict[str, Tuple[float, object]] = {}
        self._zmq_tick_cache: Dict[str, Dict[str, Any]] = {}
        self._zmq_symbol_info_cache: Dict[str, Dict[str, Any]] = {}
        self._symbol_info_static_cache: Dict[str, Dict[str, Any]] = {}
        self._zmq_account_cache: Dict[str, Any] = {}
        self._account_info_static_cache: Dict[str, Any] = {}
        self._snapshot_missing_symbol_log_ts: Dict[str, float] = {}
        self._snapshot_missing_account_log_ts: float = 0.0
        # Rate-limit helper for Appendix 4 (market orders/sec)
        self._deal_ts: List[float] = []
        self._sltp_ts: List[float] = []
        self._sltp_pos_ts: Dict[int, float] = {}
        self._exec_error_ts: List[float] = []
        self.incident_journal: Optional[IncidentJournal] = None
        self._retcodes_day_key: str = str(pl_day_key(now_utc()))
        self._retcodes_day: Dict[int, int] = {}
        # Last known MT5 snapshots used as defensive fallback when MT5 API
        # transiently returns None (common during terminal reconnect/busy windows).
        self._positions_cache: Tuple = tuple()
        self._orders_cache: Tuple = tuple()

    def _roll_retcodes_day(self) -> None:
        day_key = str(pl_day_key(now_utc()))
        if day_key != str(self._retcodes_day_key):
            self._retcodes_day_key = day_key
            self._retcodes_day = {}

    def _note_retcode_day(self, retcode_num: int) -> None:
        self._roll_retcodes_day()
        rc = int(retcode_num)
        self._retcodes_day[rc] = int(self._retcodes_day.get(rc, 0)) + 1

    def metrics_snapshot(self) -> Dict[str, Any]:
        self._roll_retcodes_day()
        success_codes = {
            int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
            int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
            int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008)),
        }
        rejects = 0
        reject_map: Dict[int, int] = {}
        for rc, cnt in self._retcodes_day.items():
            c = int(cnt)
            if int(rc) in success_codes:
                continue
            rejects += c
            reject_map[int(rc)] = c
        top_rejects = sorted(reject_map.items(), key=lambda x: x[1], reverse=True)[:5]
        return {
            "day_key": str(self._retcodes_day_key),
            "rejects_day": int(rejects),
            "retcodes_day": dict(self._retcodes_day),
            "top_rejects": [(int(rc), int(cnt)) for rc, cnt in top_rejects],
        }

    def _check_execution_burst_guard(
        self,
        *,
        symbol: str,
        retcode_num: int,
        retcode_name: str,
        emergency: bool,
    ) -> bool:
        """Fast fail-safe: after burst of severe retcodes, activate global backoff."""
        if emergency or (not bool(getattr(CFG, "execution_burst_guard_enabled", True))):
            return False
        cls, sev = classify_retcode(int(retcode_num), str(retcode_name))
        if str(sev).upper() not in {"ERROR", "CRITICAL"}:
            return False
        if str(cls).lower() == "ok":
            return False

        now_ts = float(time.time())
        lookback = max(1.0, float(getattr(CFG, "execution_burst_lookback_sec", 120)))
        threshold = max(1, int(getattr(CFG, "execution_burst_error_threshold", 4)))
        self._exec_error_ts = [t for t in self._exec_error_ts if (now_ts - float(t)) <= lookback]
        self._exec_error_ts.append(now_ts)
        if len(self._exec_error_ts) < threshold:
            return False

        backoff_s = max(1, int(getattr(CFG, "execution_burst_backoff_s", 180)))
        until = int(now_ts) + int(backoff_s)
        self.gov.db.set_global_backoff(until_ts=until, reason=f"execution_burst:{retcode_num}:{retcode_name}")
        cd_s = max(1, int(getattr(CFG, "execution_burst_symbol_cooldown_s", backoff_s)))
        cd = self.gov.db.set_cooldown(symbol, int(cd_s), "execution_burst")
        logging.warning(
            f"EXECUTION_BURST_GUARD symbol={symbol} errors={len(self._exec_error_ts)} "
            f"threshold={threshold} lookback_s={int(lookback)} backoff_s={backoff_s} "
            f"cooldown_until_ts={cd} retcode_num={int(retcode_num)} retcode_name={str(retcode_name)}"
        )
        try:
            if self.incident_journal is not None:
                self.incident_journal.note_guard(
                    guard="execution_burst_guard",
                    reason=f"retcode={int(retcode_num)}:{str(retcode_name)}",
                    severity="ERROR",
                    category="execution",
                    symbol=str(symbol),
                    extra={"errors": int(len(self._exec_error_ts)), "threshold": int(threshold), "lookback_sec": int(lookback)},
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        # Reset local burst window after arm to avoid repeated immediate triggers.
        self._exec_error_ts = []
        return True

    def connect(self) -> bool:
        if mt5 is None:
            err = globals().get("_MT5_IMPORT_ERROR", None)
            logging.error(f"MT5 import failed: {err}")
            self.connected = False
            return False

        # V6.2: enforce OANDA MT5 terminal path (LIVE hard requirement)
        if str(self.path).strip() != str(REQUIRED_OANDA_MT5_EXE):
            logging.error(f"LIVE_MT5_PATH_FAIL: MT5_PATH={self.path} (required {REQUIRED_OANDA_MT5_EXE})")
            self.connected = False
            return False
        if not Path(str(REQUIRED_OANDA_MT5_EXE)).is_file():
            logging.error(f"LIVE_MT5_FAIL: missing required terminal: {REQUIRED_OANDA_MT5_EXE}")
            self.connected = False
            return False
        try:
            ok = bool(mt5.initialize(path=self.path, login=self.login, password=self.password, server=self.server))
        except Exception as e:
            cg.tlog(None, "ERROR", "MT5_INIT_EXC", "mt5.initialize raised", e)
            ok = False
        if not ok:
            logging.error(f"MT5 Init failed: {mt5.last_error() if mt5 is not None else None}")
            self.connected = False
            return False
        self.connected = True
        return True

    def ensure_connected(self):
        if not self.connected:
            self.connect()
        if mt5 is None:
            # connect() already logged the root cause
            self.connected = False
            return
        try:
            if not mt5.terminal_info():
                logging.warning("MT5 lost connection, reconnecting...")
                self.connect()
        except Exception as e:
            cg.tlog(None, "WARN", "MT5_TERMINFO_EXC", "mt5.terminal_info raised", e)
            self.connected = False
            self.connect()

    def _snapshot_only_mode(self) -> bool:
        return bool(getattr(CFG, "hybrid_m5_no_fetch_strict", False)) and bool(
            getattr(CFG, "hybrid_no_mt5_data_fetch_hard", False)
        )

    def _symbol_info_from_snapshot(self, symbol: str) -> Optional[object]:
        cache = self._zmq_symbol_info_cache if isinstance(self._zmq_symbol_info_cache, dict) else {}
        static_cache = self._symbol_info_static_cache if isinstance(self._symbol_info_static_cache, dict) else {}
        base = symbol_base(symbol)
        rec = (
            cache.get(base)
            or cache.get(str(symbol).upper())
            or static_cache.get(base)
            or static_cache.get(str(symbol).upper())
        )
        if not isinstance(rec, dict):
            return None
        try:
            age_s = max(0.0, time.time() - float(rec.get("recv_ts") or 0.0))
            max_age = max(5, int(getattr(CFG, "hybrid_symbol_snapshot_max_age_sec", 300)))
            static_max_age = max(max_age, int(getattr(CFG, "hybrid_symbol_static_snapshot_max_age_sec", 86400)))
            if bool(rec.get("seed_static", False)):
                if age_s > float(static_max_age):
                    return None
            else:
                if age_s > float(max_age):
                    return None
            return SimpleNamespace(
                symbol=str(symbol).upper(),
                point=float(rec.get("point", 0.0) or 0.0),
                digits=int(rec.get("digits", 0) or 0),
                spread=float(rec.get("spread", 0.0) or 0.0),
                trade_tick_size=float(rec.get("trade_tick_size", 0.0) or 0.0),
                trade_tick_value=float(rec.get("trade_tick_value", 0.0) or 0.0),
                volume_min=float(rec.get("volume_min", 0.0) or 0.0),
                volume_max=float(rec.get("volume_max", 0.0) or 0.0),
                volume_step=float(rec.get("volume_step", 0.0) or 0.0),
                trade_stops_level=int(rec.get("trade_stops_level", 0) or 0),
                trade_freeze_level=int(rec.get("trade_freeze_level", 0) or 0),
            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return None

    def _account_info_from_snapshot(self) -> Optional[object]:
        rec = self._zmq_account_cache if isinstance(self._zmq_account_cache, dict) else {}
        static_rec = self._account_info_static_cache if isinstance(self._account_info_static_cache, dict) else {}
        if not rec:
            rec = static_rec
        if not rec:
            return None
        try:
            age_s = max(0.0, time.time() - float(rec.get("recv_ts") or 0.0))
            max_age = max(5, int(getattr(CFG, "hybrid_account_snapshot_max_age_sec", 30)))
            static_max_age = max(max_age, int(getattr(CFG, "hybrid_account_static_snapshot_max_age_sec", 300)))
            if bool(rec.get("seed_static", False)):
                if age_s > float(static_max_age):
                    return None
            else:
                if age_s > float(max_age):
                    return None
            return SimpleNamespace(
                balance=float(rec.get("balance", 0.0) or 0.0),
                equity=float(rec.get("equity", 0.0) or 0.0),
                margin_free=float(rec.get("margin_free", 0.0) or 0.0),
                margin_level=float(rec.get("margin_level", 0.0) or 0.0),
            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return None

    def symbol_info_cached(self, symbol: str, grp: str, db: Persistence) -> Optional[object]:
        if self._snapshot_only_mode():
            info = self._symbol_info_from_snapshot(symbol)
            if info is None:
                now_ts = float(time.time())
                log_every_sec = max(30, int(getattr(CFG, "hybrid_snapshot_missing_log_interval_sec", 300)))
                base_key = symbol_base(str(symbol)).upper()
                last_ts = float(self._snapshot_missing_symbol_log_ts.get(base_key, 0.0) or 0.0)
                if (now_ts - last_ts) >= float(log_every_sec):
                    self._snapshot_missing_symbol_log_ts[base_key] = now_ts
                    logging.debug("SYMBOL_INFO_STRICT_SNAPSHOT_MISSING symbol=%s", symbol)
            return info

        now = time.time()
        cached = self._sym_info_cache.get(symbol)
        if cached and (now - cached[0] < CFG.symbol_info_cache_ttl_sec):
            return cached[1]
        if not self.gov.consume(grp, symbol, "symbol_info", 1, emergency=False):
            return None
        info = mt5.symbol_info(symbol)
        if info is not None:
            self._sym_info_cache[symbol] = (now, info)
        return info

    def symbol_select(self, symbol: str, grp: str) -> bool:
        if mt5 is None:
            return False
        if not self.gov.consume(grp, symbol, "symbol_select", 1, emergency=False):
            return False
        return bool(mt5.symbol_select(symbol, True))

    def positions_get(self, emergency: bool = False) -> Optional[Tuple]:
        if mt5 is None:
            return None
        # Primary budget lane.
        consumed = bool(self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=bool(emergency)))
        if not consumed and (not bool(emergency)):
            # Fail-safe retry on emergency SYS pool for critical visibility into open risk.
            consumed = bool(self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=True))
            if consumed:
                logging.info("POSITIONS_GET_BUDGET_FALLBACK lane=emergency")
        if not consumed:
            if self._positions_cache:
                logging.warning(
                    "POSITIONS_GET_CACHE_FALLBACK lane=budget cache_count=%s emergency=%s",
                    int(len(self._positions_cache)),
                    int(bool(emergency)),
                )
                return tuple(self._positions_cache)
            return None

        pos = mt5.positions_get()
        if pos is not None:
            self._positions_cache = tuple(pos)
            return pos

        err1 = None
        try:
            err1 = mt5.last_error()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # One emergency retry when primary call returns None.
        if not bool(emergency):
            em_ok = bool(self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=True))
            if em_ok:
                pos2 = mt5.positions_get()
                if pos2 is not None:
                    self._positions_cache = tuple(pos2)
                    logging.info(
                        "POSITIONS_GET_RECOVERED lane=emergency count=%s err1=%s",
                        int(len(pos2)),
                        err1,
                    )
                    return pos2
                err2 = None
                try:
                    err2 = mt5.last_error()
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                logging.warning("POSITIONS_GET_NONE err1=%s err2=%s", err1, err2)
            else:
                logging.warning("POSITIONS_GET_NONE err1=%s emergency_budget=0", err1)
        else:
            logging.warning("POSITIONS_GET_NONE emergency=1 err=%s", err1)

        if self._positions_cache:
            logging.warning(
                "POSITIONS_GET_CACHE_FALLBACK lane=mt5_none cache_count=%s",
                int(len(self._positions_cache)),
            )
            return tuple(self._positions_cache)
        return None

    def orders_get(self, emergency: bool = False) -> Optional[Tuple]:
        """Pending orders (does not include SL/TP as separate objects in typical MT5 setups)."""
        if mt5 is None:
            return None
        consumed = bool(self.gov.consume("SYS", "__ORDERS__", "orders_get", 1, emergency=bool(emergency)))
        if not consumed and (not bool(emergency)):
            consumed = bool(self.gov.consume("SYS", "__ORDERS__", "orders_get", 1, emergency=True))
            if consumed:
                logging.info("ORDERS_GET_BUDGET_FALLBACK lane=emergency")
        if not consumed:
            if self._orders_cache:
                logging.warning(
                    "ORDERS_GET_CACHE_FALLBACK lane=budget cache_count=%s emergency=%s",
                    int(len(self._orders_cache)),
                    int(bool(emergency)),
                )
                return tuple(self._orders_cache)
            return None
        ords = mt5.orders_get()
        if ords is not None:
            self._orders_cache = tuple(ords)
            return ords
        err = None
        try:
            err = mt5.last_error()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        logging.warning("ORDERS_GET_NONE err=%s", err)
        if self._orders_cache:
            logging.warning(
                "ORDERS_GET_CACHE_FALLBACK lane=mt5_none cache_count=%s",
                int(len(self._orders_cache)),
            )
            return tuple(self._orders_cache)
        return None

    def account_info(self):
        if self._snapshot_only_mode():
            acc = self._account_info_from_snapshot()
            if acc is None:
                now_ts = float(time.time())
                log_every_sec = max(30, int(getattr(CFG, "hybrid_snapshot_missing_log_interval_sec", 300)))
                if (now_ts - float(self._snapshot_missing_account_log_ts or 0.0)) >= float(log_every_sec):
                    self._snapshot_missing_account_log_ts = now_ts
                    logging.info("ACCOUNT_INFO_STRICT_SNAPSHOT_MISSING")
            return acc
        if mt5 is None:
            return None
        if not self.gov.consume("SYS", "__ACCOUNT__", "account_info", 1, emergency=False):
            return None
        return mt5.account_info()

    def history_deals_get(self, from_dt: dt.datetime, to_dt: dt.datetime):
        if not self.gov.consume("SYS", "__DEALS__", "history_deals_get", 1, emergency=False):
            return None
        return mt5.history_deals_get(from_dt, to_dt)

    def copy_rates(self, symbol: str, grp: str, timeframe, n: int):
        # Hybrid path: for M5 decision bars prefer local snapshots from MQL5 (ZMQ BAR),
        # so Python does not need to fetch bars directly from MT5.
        try:
            tf_i = int(timeframe)
        except Exception:
            tf_i = int(getattr(CFG, "timeframe_trade", 5))
        want_n = max(1, int(n))
        trade_tf = int(getattr(CFG, "timeframe_trade", 5))

        def _tf_minutes(tf: int) -> Optional[int]:
            # MQL5 timeframe enum fallback mapping used in this codebase.
            if tf in (1,):
                return 1
            if tf in (5,):
                return 5
            if tf in (15,):
                return 15
            if tf in (30,):
                return 30
            if tf in (60,):
                return 60
            if tf in (240, 16388):
                return 240
            if tf in (1440, 16408):
                return 1440
            return None

        use_store = bool(getattr(CFG, "hybrid_use_zmq_m5_bars", True)) and getattr(self, "bars_store", None) is not None
        need_tf_min = _tf_minutes(tf_i)
        can_resample = bool(getattr(CFG, "hybrid_use_mtf_resample_from_m5_store", True))
        if use_store and need_tf_min is not None:
            df_store = None
            try:
                if int(need_tf_min) == int(trade_tf):
                    df_store = self.bars_store.read_recent_df(symbol_base(symbol), want_n)
                elif can_resample and int(need_tf_min) > int(trade_tf):
                    df_store = self.bars_store.read_resampled_df(symbol_base(symbol), need_tf_min, want_n)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                df_store = None

            strict_no_fetch = bool(getattr(CFG, "hybrid_m5_no_fetch_strict", False)) or bool(
                getattr(CFG, "hybrid_no_mt5_data_fetch_hard", False)
            )
            if df_store is not None and len(df_store) > 0:
                fresh_ok = True
                try:
                    ts = pd.Timestamp(df_store["time"].iloc[-1])
                    if ts.tzinfo is None:
                        ts = ts.tz_localize(TZ_PL)
                    age_s = max(0.0, time.time() - float(ts.tz_convert(UTC).timestamp()))
                    max_age_base = max(5, int(getattr(CFG, "hybrid_snapshot_max_age_sec", 180)))
                    max_age_bar = max(max_age_base, int(getattr(CFG, "hybrid_snapshot_bar_max_age_sec", 900)))
                    if need_tf_min is not None and int(need_tf_min) > int(trade_tf):
                        max_age = max(max_age_bar, int(need_tf_min) * 60 + max(120, int(trade_tf) * 60))
                    else:
                        max_age = max_age_bar
                    if age_s > float(max_age):
                        fresh_ok = False
                        logging.warning(
                            "COPY_RATES_STORE_STALE symbol=%s tf=%s age_s=%.1f max_age=%s",
                            symbol,
                            tf_i,
                            float(age_s),
                            int(max_age),
                        )
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    fresh_ok = False

                if fresh_ok:
                    rows = int(len(df_store))
                    if rows >= int(want_n):
                        logging.debug(
                            "COPY_RATES_SOURCE source=ZMQ_STORE symbol=%s tf=%s rows=%s",
                            symbol,
                            tf_i,
                            rows,
                        )
                        return df_store.tail(want_n).reset_index(drop=True)
                    if strict_no_fetch:
                        logging.info(
                            "COPY_RATES_STRICT_NOFETCH_PARTIAL symbol=%s tf=%s need_rows=%s have_rows=%s",
                            symbol,
                            tf_i,
                            int(want_n),
                            rows,
                        )
                        return df_store.tail(rows).reset_index(drop=True)
            if strict_no_fetch:
                logging.info(
                    "COPY_RATES_STRICT_NOFETCH_SKIP symbol=%s tf=%s need_rows=%s have_rows=%s",
                    symbol,
                    tf_i,
                    int(want_n),
                    int(0 if df_store is None else len(df_store)),
                )
                return None

        kind = f"rates_{timeframe}"
        if self.limits is not None:
            if not self.limits.allow_price_request(emergency=False, kind=kind):
                logging.info(f"SKIP_PRICE_LIMIT kind=copy_rates symbol={symbol}")
                return None
        if not self.gov.consume(grp, symbol, kind, 1, emergency=False):
            return None
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, n)
        if self.limits is not None:
            # Count OANDA PRICE only after real MT5 request attempt.
            self.limits.note_price_request(now_ts=time.time(), emergency=False, kind=kind)
        if rates is None or len(rates) == 0:
            err1 = None
            try:
                err1 = mt5.last_error()
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            # Recovery path: symbol can transiently drop from MarketWatch sync.
            selected = False
            try:
                selected = bool(self.symbol_select(symbol, grp))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                selected = False

            rates2 = None
            err2 = None
            if selected and self.gov.consume(grp, symbol, kind, 1, emergency=False):
                rates2 = mt5.copy_rates_from_pos(symbol, timeframe, 0, n)
                if self.limits is not None:
                    self.limits.note_price_request(now_ts=time.time(), emergency=False, kind=kind)
                try:
                    err2 = mt5.last_error()
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            if rates2 is None or len(rates2) == 0:
                logging.info(
                    "COPY_RATES_EMPTY symbol=%s tf=%s n=%s err1=%s selected=%s err2=%s",
                    symbol,
                    timeframe,
                    n,
                    err1,
                    int(bool(selected)),
                    err2,
                )
                return None
            rates = rates2
            logging.info(
                "COPY_RATES_RECOVERED symbol=%s tf=%s n=%s rows=%s err1=%s",
                symbol,
                timeframe,
                n,
                int(len(rates)),
                err1,
            )
        df = pd.DataFrame(rates)
        # Detect MT5 server-epoch offset from "fresh" bars (M1/M5), then correct time column to true UTC.
        try:
            tf_int = int(timeframe) if timeframe is not None else -1
        except Exception:
            tf_int = -1
        if tf_int in (1, 5) and "time" in df.columns and len(df) > 0:
            try:
                _maybe_update_mt5_server_epoch_offset(int(df["time"].iloc[-1]), source=str(kind), max_age_s=600)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        off = int(_MT5_SERVER_EPOCH_OFFSET_SEC) if bool(_MT5_SERVER_EPOCH_OFFSET_HAVE) else 0
        t_series = pd.to_datetime((df["time"].astype(int) - int(off)), unit="s", utc=True)
        # V1.10: time anchor update (server bar time)
        if _TIME_ANCHOR is not None:
            try:
                _TIME_ANCHOR.update(t_series.iloc[-1].to_pydatetime())
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        df["time"] = t_series.dt.tz_convert(TZ_PL)
        # Offline evaluator support: persist recent M5 bars (no extra MT5 requests)
        try:
            if getattr(self, "bars_store", None) is not None:
                self.bars_store.upsert_df(symbol_base(symbol), df)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return df

    def tick(self, symbol: str, grp: str, emergency: bool = False):
        # 1. Sprawdź cache ZMQ (Hybrid Mode)
        zmq_data = self._zmq_tick_cache.get(symbol) or self._zmq_tick_cache.get(symbol_base(symbol))
        if zmq_data:
            # Tworzymy stub udający strukturę MqlTick
            class TickStub:
                def __init__(self, d):
                    self.bid = float(d.get("bid", 0.0))
                    self.ask = float(d.get("ask", 0.0))
                    self.time = int(d.get("timestamp_ms", 0) // 1000)
                    self.volume = int(d.get("volume", 0))
            
            t = TickStub(zmq_data)
            logging.debug(f"TICK_FROM_ZMQ_CACHE symbol={symbol}")
            # Przy danych z ZMQ nie konsumujemy budżetu PRICE (oszczędność!)
            return t

        if self._snapshot_only_mode() and (not bool(emergency)):
            logging.info("TICK_STRICT_NOFETCH_SKIP symbol=%s emergency=%s", symbol, int(bool(emergency)))
            return None

        # 2. Fallback do standardowego pobierania przez MT5 API
        if self.limits is not None:
            if not self.limits.allow_price_request(emergency=bool(emergency), kind="tick"):
                logging.info(f"SKIP_PRICE_LIMIT kind=tick symbol={symbol} emergency={int(bool(emergency))}")
                return None
        if not self.gov.consume(grp, symbol, "tick", 1, emergency=bool(emergency)):
            return None
        t = mt5.symbol_info_tick(symbol)
        if self.limits is not None:
            # Count OANDA PRICE only after real MT5 request attempt.
            self.limits.note_price_request(now_ts=time.time(), emergency=bool(emergency), kind="tick")
        # V1.10: time anchor update (server tick time)
        if t is not None and _TIME_ANCHOR is not None:
            try:
                _maybe_update_mt5_server_epoch_offset(int(t.time), source="tick", max_age_s=10)
                _TIME_ANCHOR.update(mt5_epoch_to_utc_dt(int(t.time)))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return t

    def _rate_limit_market_orders(self, request: dict) -> None:
        """Appendix 4: market orders rate limit (orders/sec).

        Uses a 1-second sliding window and sleeps just enough to comply.
        This is defensive; the strategy already operates at much lower rates.
        """
        try:
            action = request.get("action")
            if action != getattr(mt5, "TRADE_ACTION_DEAL", None):
                return
            # House stop (conservative), configured against broker hard-limit.
            limit = max(1, int(getattr(CFG, "oanda_market_orders_per_sec", 20)))
            now = time.time()
            self._deal_ts = [t for t in self._deal_ts if (now - float(t)) < 1.0]
            if len(self._deal_ts) >= limit:
                oldest = min(self._deal_ts) if self._deal_ts else now
                wait_s = max(0.0, 1.0 - (now - float(oldest)))
                if wait_s > 0.0:
                    time.sleep(min(1.0, wait_s + 0.01))
            self._deal_ts.append(time.time())
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _allow_sltp_modify(self, request: dict, emergency: bool = False) -> bool:
        if emergency:
            return True
        try:
            action = request.get("action")
            if action != getattr(mt5, "TRADE_ACTION_SLTP", None):
                return True
            now = float(time.time())
            max_per_sec = max(1, int(getattr(CFG, "sltp_modify_max_per_sec", 6)))
            min_interval = max(1, int(getattr(CFG, "sltp_modify_min_interval_sec", 12)))
            self._sltp_ts = [t for t in self._sltp_ts if (now - float(t)) < 1.0]
            if len(self._sltp_ts) >= max_per_sec:
                return False
            pos_ticket = int(request.get("position") or 0)
            if pos_ticket > 0:
                last = float(self._sltp_pos_ts.get(pos_ticket, 0.0) or 0.0)
                if (now - last) < float(min_interval):
                    return False
                self._sltp_pos_ts[pos_ticket] = now
            self._sltp_ts.append(now)
            return True
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return False

    def order_send(self, symbol: str, grp: str, request: dict, emergency: bool = False):
        """P0 order_send wrapper.

        - Counts ORDER actions/day separately from PRICE/SYS budgets.
        - Precheck: fresh mt5.symbol_info(symbol) as SYS (separate from PRICE) right before sending.
        - Enforces trade_mode + stops_level/freeze_level distance (points).
        - Deterministic retries + closed GLOBAL_BACKOFF list.
        - Always logs retcode_num + retcode_name for every mt5.order_send call.
        """
        now_dt = now_utc()
        day_ny, _ = ny_day_hour_key(now_dt)
        utc_day = utc_day_key(now_dt)
        pl_day = pl_day_key(now_dt)
        # ORDER actions are tracked for NY/UTC/PL; strict-guard used=max(ny,utc,pl)
        now_ts = float(time.time())

        # GLOBAL_BACKOFF gate (allow emergency closes to attempt, but still log state)
        backoff_until = int(self.gov.db.get_global_backoff_until_ts())
        if (not emergency) and backoff_until and now_ts < float(backoff_until):
            reason = self.gov.db.get_global_backoff_reason()
            logging.info(f"SKIP_GLOBAL_BACKOFF symbol={symbol} until_ts={backoff_until} reason={reason}")
            return None

        if self.limits is not None:
            if not self.limits.allow_order_submit(now_ts=now_ts, emergency=bool(emergency)):
                logging.info(f"SKIP_ORDER_RATE_LIMIT symbol={symbol} emergency={int(bool(emergency))}")
                return None
        if not self._allow_sltp_modify(request=request, emergency=bool(emergency)):
            logging.info(
                "SKIP_SLTP_THROTTLE symbol=%s position=%s emergency=%s",
                symbol,
                int(request.get("position") or 0),
                int(bool(emergency)),
            )
            return None

        # SYS: fresh symbol_info right before order_send (not counted as PRICE request)
        if not self.gov.consume(grp, symbol, "symbol_info", 1, emergency=bool(emergency)):
            logging.info(f"SKIP_SYS_BUDGET symbol={symbol} kind=symbol_info emergency={int(bool(emergency))}")
            return None
        info = mt5.symbol_info(symbol)
        if info is None:
            logging.info(f"SKIP_SYMBOL_INFO_NONE symbol={symbol} emergency={int(bool(emergency))}")
            return None

        # Account/terminal permission precheck before any order attempt.
        # This prevents repeated broker-side 10017 bursts when trading is disabled.
        account_trade_allowed = True
        account_trade_expert = True
        terminal_trade_allowed = True
        account_balance = None
        account_login = ""
        try:
            if not self.gov.consume("SYS", "__ACCOUNT__", "account_info", 1, emergency=bool(emergency)):
                logging.info(f"SKIP_SYS_BUDGET symbol={symbol} kind=account_info emergency={int(bool(emergency))}")
                return None
            acc_info = mt5.account_info()
            if acc_info is None:
                cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "account_info_none")
                logging.warning(f"SKIP_ACCOUNT_INFO_NONE symbol={symbol} cooldown_until_ts={cd}")
                return None
            account_trade_allowed = bool(getattr(acc_info, "trade_allowed", True))
            account_trade_expert = bool(getattr(acc_info, "trade_expert", True))
            account_balance = float(getattr(acc_info, "balance", 0.0) or 0.0)
            account_login = str(getattr(acc_info, "login", "") or "")
            try:
                tinfo = mt5.terminal_info()
                if tinfo is not None:
                    terminal_trade_allowed = bool(getattr(tinfo, "trade_allowed", True))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                terminal_trade_allowed = True
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            account_trade_allowed = True
            account_trade_expert = True
            terminal_trade_allowed = True

        if (not emergency) and ((not account_trade_allowed) or (not account_trade_expert) or (not terminal_trade_allowed)):
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_flags_disabled")
            backoff_s = int(max(1, CFG.global_backoff_trade_disabled_s))
            until = int(time.time()) + backoff_s
            reason = (
                f"trade_flags:acc_allowed={int(account_trade_allowed)}:"
                f"acc_expert={int(account_trade_expert)}:term_allowed={int(terminal_trade_allowed)}"
            )
            self.gov.db.set_global_backoff(until_ts=until, reason=reason)
            logging.warning(
                f"SKIP_TRADE_FLAGS symbol={symbol} login={account_login} "
                f"acc_trade_allowed={int(account_trade_allowed)} acc_trade_expert={int(account_trade_expert)} "
                f"term_trade_allowed={int(terminal_trade_allowed)} account_balance={account_balance} "
                f"cooldown_until_ts={cd} backoff_until_ts={until}"
            )
            return None

        # Trade mode precheck (closing ops allowed)
        tm_num = int(getattr(info, "trade_mode", -1))
        tm_name = _trade_mode_name(tm_num)

        action = request.get("action")
        is_close = False
        try:
            if "position" in request and int(request.get("position") or 0) > 0:
                is_close = True
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            is_close = False
        try:
            if action == getattr(mt5, "TRADE_ACTION_CLOSE_BY", -999):
                is_close = True
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        side = "NA"
        try:
            typ = request.get("type")
            if typ == getattr(mt5, "ORDER_TYPE_BUY", -999):
                side = "BUY"
            elif typ == getattr(mt5, "ORDER_TYPE_SELL", -999):
                side = "SELL"
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        if tm_name == "DISABLED":
            # Disabled => always SKIP (P0)
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_mode_disabled")
            logging.info(f"SKIP_TRADE_MODE symbol={symbol} trade_mode={tm_name} cooldown_until_ts={cd}")
            return None
        if tm_name == "CLOSEONLY" and (not is_close):
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_mode_close_only")
            logging.info(f"SKIP_TRADE_MODE symbol={symbol} trade_mode={tm_name} cooldown_until_ts={cd}")
            return None
        if tm_name == "LONGONLY" and (not is_close) and side == "SELL":
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_mode_long_only")
            logging.info(f"SKIP_TRADE_MODE symbol={symbol} trade_mode={tm_name} side={side} cooldown_until_ts={cd}")
            return None
        if tm_name == "SHORTONLY" and (not is_close) and side == "BUY":
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_mode_short_only")
            logging.info(f"SKIP_TRADE_MODE symbol={symbol} trade_mode={tm_name} side={side} cooldown_until_ts={cd}")
            return None

        # No guessing: if trade_mode is unknown (new/unsupported numeric), skip entries.
        if tm_name == "UNKNOWN" and (not is_close):
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_trade_mode_s), "trade_mode_unknown")
            logging.info(f"SKIP_TRADE_MODE symbol={symbol} trade_mode={tm_name} cooldown_until_ts={cd}")
            return None

        block_reason = symbol_policy_block_reason(symbol, grp, info=info, is_close=bool(is_close))
        if block_reason:
            cd = self.gov.db.set_cooldown(symbol, int(CFG.cooldown_limit_s), "symbol_policy_blocked")
            logging.warning(
                f"SKIP_SYMBOL_POLICY symbol={symbol} group={grp} reason={block_reason} "
                f"cooldown_until_ts={cd} emergency={int(bool(emergency))}"
            )
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="symbol_policy",
                        reason=str(block_reason),
                        severity="ERROR",
                        category="broker_policy",
                        symbol=str(symbol),
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return None

        # Stops distance precheck (points) — only if SL/TP present
        # No guessing: if we cannot read stop/freeze/point, do not open new positions.
        try:
            stops_level_raw = getattr(info, "trade_stops_level", None)
            freeze_level_raw = getattr(info, "trade_freeze_level", None)
            point_raw = getattr(info, "point", None)
            digits_raw = getattr(info, "digits", None)
            if stops_level_raw is None or freeze_level_raw is None or point_raw is None:
                raise ValueError("missing stops/freeze/point")
            stops_level = int(stops_level_raw)
            freeze_level = int(freeze_level_raw)
            point = float(point_raw)
            digits = int(digits_raw if digits_raw is not None else 5)
            if stops_level < 0 or freeze_level < 0 or (point <= 0.0):
                raise ValueError("invalid stops/freeze/point")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            if not is_close:
                cooldown_s = int(CFG.cooldown_stops_s)
                cd = self.gov.db.set_cooldown(symbol, cooldown_s, "stops_level_unknown")
                logging.info(f"SKIP_PRECHECK_STOPS symbol={symbol} reason=unknown_limits cooldown_until_ts={cd}")
                return None
            # For closes: allow best-effort even if metadata is missing.
            stops_level, freeze_level = 0, 0
            try:
                point = float(getattr(info, "point", 0.0) or 0.0)
                digits = int(getattr(info, "digits", 5) or 5)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                point = 0.0
                digits = 5
            if point <= 0.0:
                point = 1e-5
        buffer_pts = int(CFG.stops_buffer_pts)
        min_required_pts = int(max(stops_level, freeze_level) + buffer_pts)

        # compute sl_pts/tp_pts from request price (no extra PRICE request here)
        try:
            price = float(request.get("price"))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            price = None
        def _pts(v):
            if v is None:
                return 0.0
            try:
                vv = float(v)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                return 0.0
            if vv <= 0.0 or price is None:
                return 0.0
            return abs(float(price) - vv) / float(point)

        sl_v = request.get("sl")
        tp_v = request.get("tp")
        sl_pts = float(_pts(sl_v))
        tp_pts = float(_pts(tp_v))

        if (sl_pts > 0.0 and sl_pts < float(min_required_pts)) or (tp_pts > 0.0 and tp_pts < float(min_required_pts)):
            cooldown_s = int(CFG.cooldown_stops_too_close_s)
            self.gov.db.set_cooldown(symbol, cooldown_s, "stops_too_close")
            min_required_price = float(min_required_pts) * float(point)
            min_required_pips = price_to_pips(min_required_price, point, digits)
            sl_pips = price_to_pips(float(abs(float(price or 0.0) - float(sl_v or 0.0))) if sl_v is not None else 0.0, point, digits)
            tp_pips = price_to_pips(float(abs(float(price or 0.0) - float(tp_v or 0.0))) if tp_v is not None else 0.0, point, digits)
            # Required one-liner (P0)
            logging.info(
                f"SKIP_PRECHECK_STOPS symbol={symbol} side={side} sl_pts={sl_pts:.2f} tp_pts={tp_pts:.2f} "
                f"min_required_pts={min_required_pts} stops_level={stops_level} freeze_level={freeze_level} "
                f"buffer_pts={buffer_pts} sl_pips={sl_pips:.3f} tp_pips={tp_pips:.3f} "
                f"min_required_pips={min_required_pips:.3f} cooldown_s={cooldown_s}"
            )
            return None

        # Appendix 4: max positions + pending orders simultaneously (excl. TP/SL) => precheck.
        if (not emergency) and int(CFG.oanda_positions_pending_limit) > 0 and (not is_close):
            try:
                pos = self.positions_get(emergency=False) or ()
                ords = self.orders_get(emergency=False) or ()
                pending_types = {
                    getattr(mt5, "ORDER_TYPE_BUY_LIMIT", None),
                    getattr(mt5, "ORDER_TYPE_SELL_LIMIT", None),
                    getattr(mt5, "ORDER_TYPE_BUY_STOP", None),
                    getattr(mt5, "ORDER_TYPE_SELL_STOP", None),
                    getattr(mt5, "ORDER_TYPE_BUY_STOP_LIMIT", None),
                    getattr(mt5, "ORDER_TYPE_SELL_STOP_LIMIT", None),
                }
                pending_types = {t for t in pending_types if t is not None}
                pending = 0
                for o in ords:
                    try:
                        t = getattr(o, "type", None)
                        if t in pending_types:
                            pending += 1
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                total = int(len(pos)) + int(pending)
                if self.limits is not None:
                    if not self.limits.allow_positions_pending(total, emergency=False):
                        cooldown_s = int(CFG.cooldown_limit_s)
                        cd = self.gov.db.set_cooldown(symbol, cooldown_s, "limit_positions_pending")
                        logging.info(
                            f"SKIP_PRECHECK_POS_LIMIT symbol={symbol} positions={len(pos)} pending={pending} "
                            f"total={total} limit={int(CFG.oanda_positions_pending_limit)} cooldown_until_ts={cd}"
                        )
                        return None
                if total >= int(CFG.oanda_positions_pending_limit):
                    cooldown_s = int(CFG.cooldown_limit_s)
                    cd = self.gov.db.set_cooldown(symbol, cooldown_s, "limit_positions_pending")
                    logging.info(
                        f"SKIP_PRECHECK_POS_LIMIT symbol={symbol} positions={len(pos)} pending={pending} "
                        f"total={total} limit={int(CFG.oanda_positions_pending_limit)} cooldown_until_ts={cd}"
                    )
                    return None
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # ORDER budget check (non-emergency; strict-guard across NY/UTC/PL)
        if not emergency:
            order_trade_cap = int(getattr(self.gov, "order_trade_budget", int(CFG.order_budget_day)))
            order_st = self.gov.db.get_order_actions_state(now_dt=now_dt)
            used = int(order_st.get("used") or 0)
            if used >= int(order_trade_cap):
                exhausted = []
                if int(order_st.get("ny") or 0) >= int(order_trade_cap):
                    exhausted.append(_seconds_until_next_ny_midnight(now_dt))
                if int(order_st.get("utc") or 0) >= int(order_trade_cap):
                    exhausted.append(_seconds_until_next_utc_midnight(now_dt))
                if int(order_st.get("pl") or 0) >= int(order_trade_cap):
                    exhausted.append(_seconds_until_next_pl_midnight(now_dt))
                cooldown_s = int(min(exhausted) if exhausted else _seconds_until_next_ny_midnight(now_dt))
                self.gov.db.set_cooldown(symbol, cooldown_s, "order_budget_exhausted")
                logging.info(
                    f"SKIP_ORDER_BUDGET symbol={symbol} order_actions_day={used} order_trade_budget={int(order_trade_cap)} "
                    f"order_ny={int(order_st.get('ny') or 0)} order_utc={int(order_st.get('utc') or 0)} order_pl={int(order_st.get('pl') or 0)} "
                    f"cooldown_s={cooldown_s}"
                )
                return None
            try:
                if str(grp).upper() in getattr(CFG, "group_price_shares", {}):
                    used_g = int(self.gov.db.get_order_group_actions_day(str(grp).upper(), now_dt=now_dt, emergency=False))
                    cap_g = int(self.gov.order_group_cap(str(grp).upper()))
                    borrow_g = int(self.gov.order_group_borrow_allowance(str(grp).upper(), now_dt=now_dt))
                    if used_g >= (cap_g + borrow_g):
                        cooldown_s = int(_seconds_until_next_pl_midnight(now_dt))
                        self.gov.db.set_cooldown(symbol, cooldown_s, "order_group_budget_exhausted")
                        logging.info(
                            "SKIP_ORDER_GROUP_BUDGET symbol=%s grp=%s used=%s cap=%s borrow=%s cooldown_s=%s",
                            symbol,
                            str(grp).upper(),
                            int(used_g),
                            int(cap_g),
                            int(borrow_g),
                            int(cooldown_s),
                        )
                        return None
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

# Deterministic retries + closed GLOBAL_BACKOFF list
        retry_left = {
            10004: int(CFG.max_retry_requote),
            10020: int(CFG.max_retry_price_changed),
            10028: int(CFG.max_retry_locked),
            10015: int(CFG.max_retry_invalid_price),
        }
        global_backoff_cfg = {
            10024: int(CFG.global_backoff_too_many_requests_s),
            10012: int(CFG.global_backoff_timeout_s),
            10031: int(CFG.global_backoff_connection_s),
            10011: int(CFG.global_backoff_error_s),
            10017: int(CFG.global_backoff_trade_disabled_s),
            10026: int(CFG.global_backoff_trade_disabled_s),
            10027: int(CFG.global_backoff_trade_disabled_s),
            10028: int(CFG.global_backoff_locked_s),  # only after max_retry_locked exhausted
            10019: int(CFG.global_backoff_no_money_s),
        }
        symbol_cooldown_cfg = {
            10016: (int(CFG.cooldown_stops_too_close_s), "invalid_stops"),
            10018: (int(CFG.cooldown_market_closed_s), "market_closed"),
            10019: (int(CFG.cooldown_no_money_s), "no_money"),
            10021: (int(CFG.cooldown_no_quotes_s), "no_quotes"),
            10022: (int(CFG.cooldown_limit_s), "invalid_expiration"),
            10030: (int(CFG.cooldown_trade_mode_s), "invalid_fill_mode"),
            10033: (int(CFG.cooldown_limit_s), "limit_orders"),
            10034: (int(CFG.cooldown_limit_s), "limit_volume"),
            10040: (int(CFG.cooldown_limit_s), "limit_positions"),
            10042: (int(CFG.cooldown_trade_mode_s), "long_only"),
            10043: (int(CFG.cooldown_trade_mode_s), "short_only"),
            10044: (int(CFG.cooldown_trade_mode_s), "close_only"),
            10045: (int(CFG.cooldown_trade_mode_s), "fifo_close"),
            10046: (int(CFG.cooldown_trade_mode_s), "hedge_prohibited"),
        }

        # Invalid fill (10030) is commonly broker/symbol-policy specific.
        # Build deterministic filling-mode fallback list for this symbol.
        request = dict(request or {})
        fill_candidates: List[int] = []
        requested_fill = request.get("type_filling")

        def _append_fill_candidate(v: Any) -> None:
            if v is None:
                return
            try:
                iv = int(v)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                return
            if iv not in fill_candidates:
                fill_candidates.append(iv)

        try:
            symbol_fill_mask = int(getattr(info, "filling_mode", 0) or 0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            symbol_fill_mask = 0

        order_fill_fok = getattr(mt5, "ORDER_FILLING_FOK", None)
        order_fill_ioc = getattr(mt5, "ORDER_FILLING_IOC", None)
        order_fill_return = getattr(mt5, "ORDER_FILLING_RETURN", None)

        sym_fill_fok = int(getattr(mt5, "SYMBOL_FILLING_FOK", 1))
        sym_fill_ioc = int(getattr(mt5, "SYMBOL_FILLING_IOC", 2))
        sym_fill_return = int(getattr(mt5, "SYMBOL_FILLING_RETURN", 4))

        if symbol_fill_mask > 0:
            if (symbol_fill_mask & sym_fill_fok) != 0:
                _append_fill_candidate(order_fill_fok)
            if (symbol_fill_mask & sym_fill_ioc) != 0:
                _append_fill_candidate(order_fill_ioc)
            if (symbol_fill_mask & sym_fill_return) != 0:
                _append_fill_candidate(order_fill_return)

        # Keep requested fill as candidate, but prefer broker-supported modes first when known.
        _append_fill_candidate(requested_fill)

        # Safe fallback set when symbol flags are missing/inconclusive.
        _append_fill_candidate(order_fill_ioc)
        _append_fill_candidate(order_fill_fok)
        _append_fill_candidate(order_fill_return)

        fill_idx = 0
        if fill_candidates:
            request["type_filling"] = int(fill_candidates[0])

        attempt = 0
        last_res = None
        while True:
            # Budget check per attempt (non-emergency; strict-guard across NY/UTC/PL)
            if not emergency:
                order_trade_cap = int(getattr(self.gov, "order_trade_budget", int(CFG.order_budget_day)))
                order_st = self.gov.db.get_order_actions_state(now_dt=now_dt)
                used = int(order_st.get("used") or 0)
                if (used + 1) > int(order_trade_cap):
                    exhausted = []
                    if int(order_st.get("ny") or 0) >= int(order_trade_cap):
                        exhausted.append(_seconds_until_next_ny_midnight(now_dt))
                    if int(order_st.get("utc") or 0) >= int(order_trade_cap):
                        exhausted.append(_seconds_until_next_utc_midnight(now_dt))
                    if int(order_st.get("pl") or 0) >= int(order_trade_cap):
                        exhausted.append(_seconds_until_next_pl_midnight(now_dt))
                    cooldown_s = int(min(exhausted) if exhausted else _seconds_until_next_ny_midnight(now_dt))
                    self.gov.db.set_cooldown(symbol, cooldown_s, "order_budget_exhausted")
                    logging.info(
                        f"SKIP_ORDER_BUDGET symbol={symbol} order_actions_day={used} order_trade_budget={int(order_trade_cap)} "
                        f"order_ny={int(order_st.get('ny') or 0)} order_utc={int(order_st.get('utc') or 0)} order_pl={int(order_st.get('pl') or 0)} "
                        f"cooldown_s={cooldown_s}"
                    )
                    return None
                try:
                    grp_u = str(grp).upper()
                    if grp_u in getattr(CFG, "group_price_shares", {}):
                        used_g = int(self.gov.db.get_order_group_actions_day(grp_u, now_dt=now_dt, emergency=False))
                        cap_g = int(self.gov.order_group_cap(grp_u))
                        borrow_g = int(self.gov.order_group_borrow_allowance(grp_u, now_dt=now_dt))
                        if (used_g + 1) > (cap_g + borrow_g):
                            cooldown_s = int(_seconds_until_next_pl_midnight(now_dt))
                            self.gov.db.set_cooldown(symbol, cooldown_s, "order_group_budget_exhausted")
                            logging.info(
                                "SKIP_ORDER_GROUP_BUDGET symbol=%s grp=%s used=%s cap=%s borrow=%s cooldown_s=%s",
                                symbol,
                                grp_u,
                                int(used_g),
                                int(cap_g),
                                int(borrow_g),
                                int(cooldown_s),
                            )
                            return None
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            # Optional broker-side preflight on the exact request payload.
            # WHY: catches invalid stops/fill/permissions before consuming ORDER action budget.
            if (not emergency) and bool(getattr(CFG, "use_order_check", True)) and hasattr(mt5, "order_check"):
                if not self.gov.consume(grp, symbol, "order_check", 1, emergency=False):
                    logging.info(f"SKIP_SYS_BUDGET symbol={symbol} kind=order_check emergency=0")
                    return None
                t_check0 = time.perf_counter()
                chk = mt5.order_check(request)
                check_ms = int((time.perf_counter() - t_check0) * 1000.0)
                chk_num = -1
                try:
                    if chk is not None and hasattr(chk, "retcode"):
                        chk_num = int(getattr(chk, "retcode"))
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    chk_num = -1
                chk_name = "ORDER_CHECK_OK" if chk_num == 0 else _retcode_name(chk_num)
                logging.info(
                    "ORDER_CHECK symbol=%s attempt=%s retcode_num=%s retcode_name=%s latency_ms=%s",
                    symbol,
                    int(attempt + 1),
                    int(chk_num),
                    chk_name,
                    int(check_ms),
                )
                if chk_num not in (0, int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)), int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)), int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008))):
                    try:
                        if chk_num in symbol_cooldown_cfg:
                            sec, rsn = symbol_cooldown_cfg[int(chk_num)]
                            cd = self.gov.db.set_cooldown(symbol, int(sec), f"order_check:{rsn}")
                            logging.info(
                                "ORDER_CHECK_COOLDOWN symbol=%s retcode_num=%s retcode_name=%s cooldown_until_ts=%s reason=%s",
                                symbol,
                                int(chk_num),
                                chk_name,
                                int(cd),
                                str(rsn),
                            )
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    if chk_num in global_backoff_cfg:
                        backoff_s = int(global_backoff_cfg.get(chk_num, 0))
                        if backoff_s > 0:
                            until = int(time.time()) + backoff_s
                            self.gov.db.set_global_backoff(until_ts=until, reason=f"order_check:{chk_num}:{chk_name}")
                            logging.warning(
                                "GLOBAL_BACKOFF source=order_check retcode_num=%s retcode_name=%s backoff_s=%s until_ts=%s",
                                int(chk_num),
                                chk_name,
                                int(backoff_s),
                                int(until),
                            )
                    return None

            # Count every mt5.order_send call as ORDER action/day (P0)
            self.gov.db.inc_order_action(1, now_dt=now_dt)
            self.gov.db.inc_order_group_action(str(grp).upper(), 1, now_dt=now_dt, emergency=bool(emergency))

            attempt += 1
            # Appendix 4: market orders/sec guard
            self._rate_limit_market_orders(request)
            t_send0 = time.perf_counter()
            res = mt5.order_send(request)
            send_ms = int((time.perf_counter() - t_send0) * 1000.0)
            last_res = res
            ret_num = -1
            try:
                if res is not None and hasattr(res, "retcode"):
                    ret_num = int(getattr(res, "retcode"))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                ret_num = -1
            ret_name = _retcode_name(ret_num)

            # Required per-call log (P0)
            logging.info(
                "ORDER_SEND symbol=%s attempt=%s retcode_num=%s retcode_name=%s latency_ms=%s",
                symbol,
                int(attempt),
                int(ret_num),
                str(ret_name),
                int(send_ms),
            )
            self._note_retcode_day(int(ret_num))
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_retcode(
                        symbol=str(symbol),
                        retcode_num=int(ret_num),
                        retcode_name=str(ret_name),
                        emergency=bool(emergency),
                        attempt=int(attempt),
                        source="order_send",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            # Fallback filling-mode rotation on broker-side invalid fill.
            if ret_num == 10030 and (fill_idx + 1) < len(fill_candidates):
                prev_fill = request.get("type_filling")
                fill_idx += 1
                request["type_filling"] = int(fill_candidates[fill_idx])
                logging.warning(
                    f"ORDER_RETRY_FILLING_SWITCH symbol={symbol} "
                    f"from={prev_fill} to={request['type_filling']} retcode_num={ret_num}"
                )
                continue

            # Success codes
            try:
                if ret_num in (int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
                               int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
                               int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008))):
                    return res
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            if self._check_execution_burst_guard(
                symbol=symbol,
                retcode_num=int(ret_num),
                retcode_name=str(ret_name),
                emergency=bool(emergency),
            ):
                return res

            # Broker/server disabled trading (10017): enforce symbol cooldown + global backoff immediately.
            if ret_num == 10017:
                backoff_s = int(max(1, CFG.global_backoff_trade_disabled_s))
                until = int(time.time()) + backoff_s
                self.gov.db.set_global_backoff(until_ts=until, reason=f"{ret_num}:{ret_name}")
                cd = self.gov.db.set_cooldown(symbol, int(max(1, CFG.cooldown_trade_mode_s)), "trade_disabled")
                logging.warning(
                    f"TRADE_DISABLED_GUARD symbol={symbol} retcode_num={ret_num} retcode_name={ret_name} "
                    f"acc_trade_allowed={int(account_trade_allowed)} acc_trade_expert={int(account_trade_expert)} "
                    f"term_trade_allowed={int(terminal_trade_allowed)} account_balance={account_balance} "
                    f"cooldown_until_ts={cd} backoff_until_ts={until}"
                )
                return res

            # Insufficient margin guard for BTC/ETH: avoid repeated no-money churn.
            if ret_num == 10019 and _is_crypto_major_symbol(symbol):
                no_money_backoff_s = int(
                    max(
                        1,
                        _cfg_group_int(
                            grp,
                            "no_money_backoff_s",
                            int(getattr(CFG, "crypto_no_money_backoff_s", 900)),
                            symbol=symbol,
                        ),
                    )
                )
                no_money_cd_s = int(
                    max(
                        1,
                        _cfg_group_int(
                            grp,
                            "no_money_cooldown_s",
                            int(getattr(CFG, "crypto_no_money_cooldown_s", 900)),
                            symbol=symbol,
                        ),
                    )
                )
                until = int(time.time()) + int(no_money_backoff_s)
                self.gov.db.set_global_backoff(until_ts=until, reason=f"no_money_crypto:{ret_num}:{ret_name}")
                cd = self.gov.db.set_cooldown(symbol, int(no_money_cd_s), "no_money_crypto")
                logging.warning(
                    "NO_MONEY_GUARD symbol=%s grp=%s retcode_num=%s retcode_name=%s cooldown_until_ts=%s backoff_until_ts=%s",
                    symbol,
                    str(grp).upper(),
                    int(ret_num),
                    str(ret_name),
                    int(cd),
                    int(until),
                )
                return res

            # Retryable codes (deterministic)
            if ret_num in retry_left and int(retry_left[ret_num]) > 0:
                retry_left[ret_num] = int(retry_left[ret_num]) - 1
                time.sleep(float(CFG.retry_sleep_s))
                continue

            
            # Per-symbol cooldown on server-side constraints (P0)
            try:
                if ret_num in symbol_cooldown_cfg:
                    sec, rsn = symbol_cooldown_cfg[int(ret_num)]
                    cd = self.gov.db.set_cooldown(symbol, int(sec), str(rsn))
                    logging.info(f"SKIP_RETCODE_COOLDOWN symbol={symbol} retcode_num={ret_num} retcode_name={ret_name} cooldown_until_ts={cd} reason={rsn}")
                    return res
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            # GLOBAL_BACKOFF (P0 closed list)
            if ret_num in global_backoff_cfg:
                backoff_s = int(global_backoff_cfg.get(ret_num, 0))
                if backoff_s > 0:
                    until = int(time.time()) + backoff_s
                    self.gov.db.set_global_backoff(until_ts=until, reason=f"{ret_num}:{ret_name}")
                    logging.warning(f"GLOBAL_BACKOFF retcode_num={ret_num} retcode_name={ret_name} backoff_s={backoff_s} until_ts={until}")
                return res

            # Other failures: no global backoff (P0)
            logging.warning(f"ORDER_FAIL symbol={symbol} retcode_num={ret_num} retcode_name={ret_name}")
            return res

    def force_flat_all(self, db: Persistence, retries: int, delay: float, deviation: int) -> bool:
        logging.critical("EXECUTING FORCE FLAT (KILL SWITCH)")
        for _ in range(int(retries)):
            # emergency SYS positions_get
            if not self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=True):
                return False
            positions = mt5.positions_get()
            if not positions:
                return True

            ok_all = True
            for pos in positions:
                sym = pos.symbol
                grp = guess_group(sym)
                info = self.symbol_info_cached(sym, grp, db)
                if info is None:
                    ok_all = False
                    continue
                # emergency PRICE tick
                t = self.tick(sym, grp, emergency=True)
                if t is None:
                    ok_all = False
                    continue

                if t is not None and _TIME_ANCHOR is not None:

                    try:

                        _maybe_update_mt5_server_epoch_offset(int(t.time), source="tick_emergency", max_age_s=10)
                        _TIME_ANCHOR.update(mt5_epoch_to_utc_dt(int(t.time)))

                    except Exception as e:

                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                if not t:
                    ok_all = False
                    continue
                close_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                price = t.bid if pos.type == mt5.ORDER_TYPE_BUY else t.ask
                req = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": sym,
                    "volume": pos.volume,
                    "type": close_type,
                    "position": pos.ticket,
                    "price": float(price),
                    "deviation": int(deviation),
                    "magic": CFG.magic_number,
                    "comment": "KILL_SWITCH",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                # emergency ORDER order_send (still counted; bypass budget via emergency=True)
                res = self.order_send(sym, grp, req, emergency=True)
                if not res or res.retcode != mt5.TRADE_RETCODE_DONE:
                    ok_all = False

            if ok_all:
                return True
            time.sleep(delay)
        return False

    def force_flat_symbol(self, symbol: str, db: Persistence, retries: int, delay: float, deviation: int) -> bool:
        target = str(symbol or "").strip()
        if not target:
            return False
        logging.warning(f"EXECUTING FORCE FLAT SYMBOL symbol={target}")
        for _ in range(int(retries)):
            # emergency SYS positions_get
            if not self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=True):
                return False
            all_pos = mt5.positions_get()
            if not all_pos:
                return True
            positions = [p for p in all_pos if str(getattr(p, "symbol", "")) == target]
            if not positions:
                return True

            ok_all = True
            for pos in positions:
                sym = str(getattr(pos, "symbol", target))
                grp = guess_group(sym)
                info = self.symbol_info_cached(sym, grp, db)
                if info is None:
                    ok_all = False
                    continue
                t = self.tick(sym, grp, emergency=True)
                if t is None:
                    ok_all = False
                    continue
                if t is not None and _TIME_ANCHOR is not None:
                    try:
                        _maybe_update_mt5_server_epoch_offset(int(t.time), source="tick_emergency", max_age_s=10)
                        _TIME_ANCHOR.update(mt5_epoch_to_utc_dt(int(t.time)))
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                close_type = mt5.ORDER_TYPE_SELL if pos.type == mt5.ORDER_TYPE_BUY else mt5.ORDER_TYPE_BUY
                price = t.bid if pos.type == mt5.ORDER_TYPE_BUY else t.ask
                if float(price or 0.0) <= 0.0:
                    ok_all = False
                    continue
                req = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": sym,
                    "volume": float(getattr(pos, "volume", 0.0) or 0.0),
                    "type": close_type,
                    "position": int(getattr(pos, "ticket", 0) or 0),
                    "price": float(price),
                    "deviation": int(deviation),
                    "magic": CFG.magic_number,
                    "comment": "TIME_STOP_FORCE_FLAT",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }
                if req["position"] <= 0 or req["volume"] <= 0.0:
                    ok_all = False
                    continue
                res = self.order_send(sym, grp, req, emergency=True)
                done_code = int(getattr(mt5, "TRADE_RETCODE_DONE", 10009))
                if not res or int(getattr(res, "retcode", -1)) != done_code:
                    ok_all = False

            if ok_all:
                return True
            time.sleep(delay)
        return False


class MT5Client(ExecutionEngine):
    """Backward-compatible alias after extracting MT5 execution logic."""

    def order_send(self, symbol: str, grp: str, request: dict, emergency: bool = False):
        return super().order_send(symbol, grp, request, emergency=emergency)

# =============================================================================
# ACTIVITY CONTROLLER (profile + score + warunki)
# =============================================================================

try:
    from .scheduler import ActivityController
except Exception:  # pragma: no cover
    from scheduler import ActivityController


# =============================================================================
# STRATEGY (H4 trend priority, tick on demand)
# =============================================================================

class StrategyCache:
    def __init__(self):
        self.trend_cache: Dict[str, Tuple[float, str, str, str]] = {}
        self.last_m5_calc_ts: Dict[str, float] = {}
        self.last_m5_bar_time: Dict[str, pd.Timestamp] = {}
        self.next_m5_fetch_ts: Dict[str, float] = {}
        self.last_soft_skip_log_ts: Dict[str, float] = {}
        self.skip_log_throttle_ts: Dict[str, float] = {}

class StandardStrategy:
    def __init__(
        self,
        engine: ExecutionEngine,
        gov: RequestGovernor,
        throttle: OrderThrottle,
        db: Persistence,
        config: ConfigManager,
        risk_manager: RiskManager,
        order_queue: Optional[ExecutionQueue] = None,
        dispatch_order_hook: Optional[Callable[[str, str, dict, bool], Any]] = None,
    ):
        self.engine = engine
        self.gov = gov
        self.throttle = throttle
        self.db = db
        self.config = config
        self.risk_manager = risk_manager
        self.order_queue = order_queue
        self.dispatch_order_hook = dispatch_order_hook
        self.cache = StrategyCache()
        self.last_indicators: Dict[str, Dict[str, Any]] = {}
        self.zmq_feature_cache: Optional[Dict[str, Dict[str, Any]]] = None
        self._scan_meta: Dict[str, Any] = {}
        self.decision_store: Optional[DecisionEventStore] = None
        self._last_eval_price_before: Optional[int] = None
        self._last_eval_sys_before: Optional[int] = None
        self._last_event_id: Optional[str] = None
        self._signal_seen_local: Dict[str, float] = {}
        self._metrics_day_key: str = str(pl_day_key(now_utc()))
        self._metrics_day: Dict[str, int] = {
            "entry_signals": 0,
            "entry_ok": 0,
            "entry_fail": 0,
        }
        self._metrics_total: Dict[str, int] = {
            "entry_signals": 0,
            "entry_ok": 0,
            "entry_fail": 0,
        }
        self._skip_day: Dict[str, int] = {}
        self._skip_total: Dict[str, int] = {}
        self._spread_entry_sum_day: float = 0.0
        self._spread_entry_count_day: int = 0
        self._renko_eval_cache: Dict[str, Dict[str, Any]] = {}
        self._skip_capture_ctx: Dict[str, Any] = {}
        self.execution_telemetry_hook: Optional[Callable[[Dict[str, Any]], None]] = None
        # Guard defaults; populated by SafetyBot preflight when available.
        self._asia_shadow_symbol_gate: Dict[str, bool] = {}
        self._asia_shadow_symbol_targets: Set[str] = set()

    def _append_execution_telemetry(self, payload: Dict[str, Any]) -> None:
        """
        Strategy-level telemetry sink.
        Uses SafetyBot hook when available; otherwise no-op to avoid blocking trade path.
        """
        hook = getattr(self, "execution_telemetry_hook", None)
        if not callable(hook):
            return
        try:
            hook(dict(payload or {}))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _metrics_roll_day(self) -> None:
        day_key = str(pl_day_key(now_utc()))
        if day_key == str(self._metrics_day_key):
            return
        self._metrics_day_key = day_key
        self._metrics_day = {"entry_signals": 0, "entry_ok": 0, "entry_fail": 0}
        self._skip_day = {}
        self._spread_entry_sum_day = 0.0
        self._spread_entry_count_day = 0

    def set_skip_capture_context(self, symbol: str, grp: str, mode: str, stage: str = "SCAN") -> None:
        self._skip_capture_ctx = {
            "symbol": str(symbol or ""),
            "grp": str(grp or ""),
            "mode": str(mode or ""),
            "stage": str(stage or "SCAN"),
        }

    def update_skip_capture_context(self, **kwargs: Any) -> None:
        if not isinstance(self._skip_capture_ctx, dict):
            self._skip_capture_ctx = {}
        for k, v in kwargs.items():
            if v is None:
                continue
            self._skip_capture_ctx[str(k)] = v

    def clear_skip_capture_context(self) -> None:
        self._skip_capture_ctx = {}

    @staticmethod
    def _classify_skip_reason(reason: str) -> str:
        r = str(reason or "UNKNOWN").upper()
        if "SPREAD" in r or "COST" in r or "SCORE" in r:
            return "COST_QUALITY"
        if "RISK" in r or "LOSS" in r or "HEAT" in r or "EXPOSURE" in r:
            return "RISK_GUARD"
        if "TREND" in r or "NO_SIGNAL" in r or "SIGNAL_" in r:
            return "SIGNAL_LOGIC"
        if "DATA" in r or "TICK" in r or "POINT" in r or "M5_" in r:
            return "DATA_READINESS"
        if "ROLL" in r or "WINDOW" in r or "PREFLIGHT" in r or "COOLDOWN" in r:
            return "SESSION_POLICY"
        if "RUNTIME" in r or "BACKOFF" in r or "UNAVAILABLE" in r:
            return "RUNTIME_GUARD"
        return "OTHER"

    def _persist_skip_rejection(self, reason: str) -> None:
        if getattr(self, "decision_store", None) is None:
            return
        ctx = dict(self._skip_capture_ctx or {})
        symbol = str(ctx.get("symbol") or "")
        grp = str(ctx.get("grp") or "")
        mode = str(ctx.get("mode") or "")
        stage = str(ctx.get("stage") or "SCAN")
        if not symbol:
            # Avoid mislabeling global/runtime skips when symbol context is unknown.
            return
        reason_code = str(reason or "UNKNOWN").upper()
        strategy_family = str(
            ctx.get("strategy_family")
            or infer_runtime_strategy_family(
                mode=mode,
                signal=str(ctx.get("signal") or ""),
                signal_reason=str(ctx.get("signal_reason") or ""),
            )
        ).upper()
        tw = trade_window_ctx(now_utc())
        window_id = str((tw or {}).get("window_id") or "OFF")
        window_phase = str((tw or {}).get("phase") or "OFF")
        row = {
            "reject_id": str(uuid.uuid4()),
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "symbol": str(symbol_base(symbol)),
            "grp": grp.upper() if grp else None,
            "mode": mode.upper() if mode else None,
            "reason_code": reason_code,
            "reason_class": self._classify_skip_reason(reason_code),
            "stage": stage.upper() if stage else None,
            "signal": (str(ctx.get("signal")).upper() if ctx.get("signal") else None),
            "strategy_family": strategy_family,
            "regime": (str(ctx.get("regime")).upper() if ctx.get("regime") else None),
            "window_id": window_id,
            "window_phase": window_phase,
            "context_json": json.dumps(
                {
                    "signal_reason": ctx.get("signal_reason"),
                    "strategy_family": strategy_family,
                    "trend_h4": ctx.get("trend_h4"),
                    "structure_h4": ctx.get("structure_h4"),
                },
                ensure_ascii=False,
            ),
        }
        try:
            self.decision_store.insert_rejection(row)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _metric_inc_skip(self, reason: str) -> None:
        self._metrics_roll_day()
        key = str(reason or "UNKNOWN")
        self._skip_day[key] = int(self._skip_day.get(key, 0)) + 1
        self._skip_total[key] = int(self._skip_total.get(key, 0)) + 1
        self._persist_skip_rejection(key)

    def _metric_note_entry_signal(self) -> None:
        self._metrics_roll_day()
        self._metrics_day["entry_signals"] = int(self._metrics_day.get("entry_signals", 0)) + 1
        self._metrics_total["entry_signals"] = int(self._metrics_total.get("entry_signals", 0)) + 1

    def _metric_note_order_result(self, ok: bool, spread_points: Optional[float] = None) -> None:
        self._metrics_roll_day()
        key = "entry_ok" if bool(ok) else "entry_fail"
        self._metrics_day[key] = int(self._metrics_day.get(key, 0)) + 1
        self._metrics_total[key] = int(self._metrics_total.get(key, 0)) + 1
        try:
            sp = float(spread_points) if spread_points is not None else float("nan")
            if np.isfinite(sp) and sp > 0.0:
                self._spread_entry_sum_day += float(sp)
                self._spread_entry_count_day += 1
        except Exception:
            return

    def _skip_log_allowed(self, symbol: str, reason: str, interval_sec: int) -> bool:
        if int(interval_sec) <= 0:
            return True
        now_ts = float(time.time())
        key = f"{str(symbol)}|{str(reason or 'UNKNOWN').upper()}"
        last_ts = float(self.cache.skip_log_throttle_ts.get(key, 0.0) or 0.0)
        if (now_ts - last_ts) < float(interval_sec):
            return False
        self.cache.skip_log_throttle_ts[key] = now_ts
        return True

    def metrics_snapshot(self) -> Dict[str, Any]:
        self._metrics_roll_day()
        avg_spread = 0.0
        if int(self._spread_entry_count_day) > 0:
            avg_spread = float(self._spread_entry_sum_day) / float(self._spread_entry_count_day)
        return {
            "day_key": str(self._metrics_day_key),
            "entry_signals_day": int(self._metrics_day.get("entry_signals", 0)),
            "entries_day": int(self._metrics_day.get("entry_ok", 0)),
            "entry_fails_day": int(self._metrics_day.get("entry_fail", 0)),
            "avg_spread_entry_points_day": float(avg_spread),
            "skip_day": dict(self._skip_day),
            "entry_signals_total": int(self._metrics_total.get("entry_signals", 0)),
            "entries_total": int(self._metrics_total.get("entry_ok", 0)),
            "entry_fails_total": int(self._metrics_total.get("entry_fail", 0)),
            "skip_total": dict(self._skip_total),
        }

    def _signal_id(self, symbol: str, signal: str, signal_reason: str, regime: str) -> str:
        bar_ts = self.cache.last_m5_bar_time.get(symbol)
        if isinstance(bar_ts, pd.Timestamp):
            bar_key = bar_ts.tz_convert(UTC).strftime("%Y%m%dT%H%M%SZ")
        else:
            bar_key = str(int(time.time() // 60))
        return (
            f"{symbol_base(symbol)}|tf={int(getattr(CFG, 'timeframe_trade', 5))}|"
            f"bar={bar_key}|signal={str(signal)}|reason={str(signal_reason)}|regime={str(regime)}"
        )

    def _signal_dedup_block(self, signal_id: str) -> bool:
        if not bool(getattr(CFG, "signal_dedupe_enabled", True)):
            return False
        now_ts = float(time.time())
        ttl_s = max(30, int(getattr(CFG, "signal_dedupe_ttl_sec", 900)))
        last_local = float(self._signal_seen_local.get(signal_id, 0.0) or 0.0)
        if (now_ts - last_local) < ttl_s:
            return True
        key = f"signal_seen_ts:{signal_id}"
        try:
            last_db = float(self.db.state_get(key, "0") or 0.0)
        except Exception:
            last_db = 0.0
        if (now_ts - last_db) < ttl_s:
            self._signal_seen_local[signal_id] = now_ts
            return True
        self._signal_seen_local[signal_id] = now_ts
        try:
            self.db.state_set(key, str(now_ts))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return False

    def _evaluate_candle_context(
        self,
        *,
        symbol: str,
        grp: str,
        signal: str,
        trend_h4: str,
        regime: str,
        ind: Dict[str, Any],
    ) -> Dict[str, Any]:
        mode = str(getattr(CFG, "candle_adapter_mode", "SHADOW_ONLY") or "SHADOW_ONLY").strip().upper()
        if mode not in {"SHADOW_ONLY", "ADVISORY_SCORE", "DISABLED"}:
            mode = "SHADOW_ONLY"
        cfg = JapaneseCandleAdapterConfig(
            enabled=bool(getattr(CFG, "candle_adapter_enabled", True)),
            mode=mode,
            min_body_to_range=float(max(0.0, getattr(CFG, "candle_adapter_min_body_to_range", 0.35))),
            pin_wick_ratio_min=float(max(0.1, getattr(CFG, "candle_adapter_pin_wick_ratio_min", 1.6))),
        )
        required = ("prev_open", "prev_high", "prev_low", "prev_close")
        if any(ind.get(k) is None for k in required):
            return {
                "ready": False,
                "candle_bias": "NONE",
                "candle_score_long": 0.0,
                "candle_score_short": 0.0,
                "candle_quality_grade": "UNKNOWN",
                "candle_patterns": [],
                "no_trade_hint": False,
                "reason_code": "CANDLE_PREV_BAR_MISSING",
                "mode": mode,
                "symbol_raw": str(symbol),
                "symbol_canonical": canonical_symbol(symbol),
                "group": _group_key(grp),
            }
        inp = JapaneseCandleInput(
            signal=str(signal),
            trend_h4=str(trend_h4),
            regime=str(regime),
            open_price=float(ind.get("open")),
            high_price=float(ind.get("high")),
            low_price=float(ind.get("low")),
            close_price=float(ind.get("close")),
            prev_open=float(ind.get("prev_open")),
            prev_high=float(ind.get("prev_high")),
            prev_low=float(ind.get("prev_low")),
            prev_close=float(ind.get("prev_close")),
        )
        out = dict(evaluate_japanese_candle_adapter(cfg, inp))
        out.update(
            {
                "symbol_raw": str(symbol),
                "symbol_canonical": canonical_symbol(symbol),
                "group": _group_key(grp),
            }
        )
        return out

    def _apply_candle_advisory_score(
        self,
        *,
        signal: str,
        base_score: int,
        candle_ctx: Dict[str, Any],
    ) -> int:
        mode = str(candle_ctx.get("mode") or "SHADOW_ONLY").upper()
        if mode != "ADVISORY_SCORE":
            return int(base_score)
        long_s = float(candle_ctx.get("candle_score_long", 0.0) or 0.0)
        short_s = float(candle_ctx.get("candle_score_short", 0.0) or 0.0)
        weight = float(max(0.0, getattr(CFG, "candle_adapter_score_weight", 6.0)))
        delta = (long_s - short_s) if str(signal).upper() == "BUY" else (short_s - long_s)
        adjusted = int(round(float(base_score) + float(delta) * float(weight)))
        return int(max(0, min(100, adjusted)))

    def _evaluate_renko_context(
        self,
        *,
        symbol: str,
        grp: str,
        signal: str,
        point: float,
    ) -> Dict[str, Any]:
        mode = str(getattr(CFG, "renko_adapter_mode", "SHADOW_ONLY") or "SHADOW_ONLY").strip().upper()
        if mode not in {"SHADOW_ONLY", "ADVISORY_SCORE", "DISABLED"}:
            mode = "SHADOW_ONLY"
        base = symbol_base(symbol)
        symbol_canon = canonical_symbol(symbol)
        grp_u = _group_key(grp)
        if (not bool(getattr(CFG, "renko_adapter_enabled", True))) or mode == "DISABLED":
            return {
                "ready": False,
                "mode": mode,
                "renko_bias": "NONE",
                "renko_score_long": 0.0,
                "renko_score_short": 0.0,
                "renko_quality_grade": "UNKNOWN",
                "renko_no_trade_hint": False,
                "reason_code": "RENKO_ADAPTER_DISABLED",
                "symbol_raw": str(symbol),
                "symbol_canonical": str(symbol_canon),
                "group": str(grp_u),
            }
        if float(point or 0.0) <= 0.0:
            return {
                "ready": False,
                "mode": mode,
                "renko_bias": "NONE",
                "renko_score_long": 0.0,
                "renko_score_short": 0.0,
                "renko_quality_grade": "UNKNOWN",
                "renko_no_trade_hint": False,
                "reason_code": "RENKO_POINT_INVALID",
                "symbol_raw": str(symbol),
                "symbol_canonical": str(symbol_canon),
                "group": str(grp_u),
            }

        ttl = float(max(0.5, getattr(CFG, "renko_adapter_cache_ttl_sec", 5.0)))
        now_ts = float(time.time())
        cache = dict(self._renko_eval_cache.get(base) or {})
        if float(cache.get("cache_expire_ts", 0.0) or 0.0) >= now_ts:
            return dict(cache.get("payload") or {})

        tick_store = getattr(self.engine, "tick_store", None)
        if tick_store is None:
            out = {
                "ready": False,
                "mode": mode,
                "renko_bias": "NONE",
                "renko_score_long": 0.0,
                "renko_score_short": 0.0,
                "renko_quality_grade": "UNKNOWN",
                "renko_no_trade_hint": False,
                "reason_code": "RENKO_TICK_STORE_UNAVAILABLE",
                "symbol_raw": str(symbol),
                "symbol_canonical": str(symbol_canon),
                "group": str(grp_u),
            }
            self._renko_eval_cache[base] = {"cache_expire_ts": now_ts + ttl, "payload": dict(out)}
            return out

        tick_limit = int(max(100, getattr(CFG, "renko_adapter_tick_limit", 1200)))
        t0 = float(time.perf_counter())
        rows = tick_store.read_recent_ticks(base, limit=tick_limit) if hasattr(tick_store, "read_recent_ticks") else []
        if not rows:
            out = {
                "ready": False,
                "mode": mode,
                "renko_bias": "NONE",
                "renko_score_long": 0.0,
                "renko_score_short": 0.0,
                "renko_quality_grade": "UNKNOWN",
                "renko_no_trade_hint": False,
                "reason_code": "RENKO_NO_TICKS",
                "symbol_raw": str(symbol),
                "symbol_canonical": str(symbol_canon),
                "group": str(grp_u),
                "renko_eval_ms": int(round((time.perf_counter() - t0) * 1000.0)),
            }
            self._renko_eval_cache[base] = {"cache_expire_ts": now_ts + ttl, "payload": dict(out)}
            return out

        ticks: List[RenkoTick] = []
        for row in rows:
            try:
                ticks.append(
                    RenkoTick(
                        ts_msc=int(row.get("ts_msc") or 0),
                        bid=float(row.get("bid") or 0.0),
                        ask=float(row.get("ask") or 0.0),
                    )
                )
            except Exception:
                continue
        if not ticks:
            out = {
                "ready": False,
                "mode": mode,
                "renko_bias": "NONE",
                "renko_score_long": 0.0,
                "renko_score_short": 0.0,
                "renko_quality_grade": "UNKNOWN",
                "renko_no_trade_hint": False,
                "reason_code": "RENKO_TICK_PARSE_FAIL",
                "symbol_raw": str(symbol),
                "symbol_canonical": str(symbol_canon),
                "group": str(grp_u),
                "renko_eval_ms": int(round((time.perf_counter() - t0) * 1000.0)),
            }
            self._renko_eval_cache[base] = {"cache_expire_ts": now_ts + ttl, "payload": dict(out)}
            return out

        brick_pts = float(
            max(
                1.0,
                _cfg_group_map_float(
                    "renko_adapter_brick_size_points_by_group",
                    grp_u,
                    float(getattr(CFG, "renko_adapter_brick_size_points_default", 8.0)),
                ),
            )
        )
        src = str(getattr(CFG, "renko_adapter_price_source", "MID") or "MID").strip().upper()
        renko_out = build_renko_bricks(
            RenkoSensorConfig(
                brick_size_points=float(brick_pts),
                point=float(point),
                price_source=src,
            ),
            ticks,
        )
        bricks_count = int(renko_out.get("bricks_count", 0) or 0)
        min_ready = int(max(1, getattr(CFG, "renko_adapter_min_bricks_ready", 3)))
        ready = bool(renko_out.get("ready", False)) and (bricks_count >= min_ready)
        last_dir = str(renko_out.get("last_brick_dir") or "NONE").upper()
        run_len = int(max(0, renko_out.get("run_length", 0) or 0))
        reversal_flag = bool(renko_out.get("reversal_flag", False))
        qflags = renko_out.get("quality_flags") if isinstance(renko_out.get("quality_flags"), dict) else {}
        ask_lt_bid_count = int(qflags.get("ask_lt_bid_count", 0) or 0)
        non_mono_count = int(qflags.get("non_monotonic_ts_count", 0) or 0)
        quality = "POOR"
        if ready:
            quality = "GOOD"
        elif bool(renko_out.get("ready", False)):
            quality = "FAIR"
        if ask_lt_bid_count > 0 or non_mono_count > 0:
            quality = "POOR"

        long_s = 0.0
        short_s = 0.0
        no_trade_hint = False
        if ready:
            run_bonus = min(0.35, max(0.0, float(run_len - 1) * 0.07))
            base_score = min(0.95, 0.55 + run_bonus)
            if last_dir == "UP":
                long_s = base_score
                short_s = 0.20
            elif last_dir == "DOWN":
                short_s = base_score
                long_s = 0.20
            else:
                long_s = 0.30
                short_s = 0.30
            if reversal_flag:
                long_s *= 0.85
                short_s *= 0.85
                if run_len <= 1:
                    no_trade_hint = True
        bias = "NONE"
        if long_s > short_s:
            bias = "UP"
        elif short_s > long_s:
            bias = "DOWN"
        if quality == "POOR":
            no_trade_hint = True

        reason = str(renko_out.get("reason_code") or "RENKO_UNKNOWN")
        if ready:
            reason = "RENKO_OK"
        elif bool(renko_out.get("ready", False)) and bricks_count < min_ready:
            reason = "RENKO_BRICKS_TOO_FEW"

        out = {
            "ready": bool(ready),
            "mode": mode,
            "renko_bias": bias,
            "renko_score_long": float(max(0.0, min(1.0, long_s))),
            "renko_score_short": float(max(0.0, min(1.0, short_s))),
            "renko_quality_grade": str(quality),
            "renko_no_trade_hint": bool(no_trade_hint),
            "reason_code": str(reason),
            "last_brick_dir": str(last_dir),
            "run_length": int(run_len),
            "reversal_flag": bool(reversal_flag),
            "bricks_count": int(bricks_count),
            "brick_size_points": float(brick_pts),
            "price_source": str(src),
            "ask_lt_bid_count": int(ask_lt_bid_count),
            "non_monotonic_ts_count": int(non_mono_count),
            "symbol_raw": str(symbol),
            "symbol_canonical": str(symbol_canon),
            "group": str(grp_u),
            "renko_eval_ms": int(round((time.perf_counter() - t0) * 1000.0)),
        }
        self._renko_eval_cache[base] = {"cache_expire_ts": now_ts + ttl, "payload": dict(out)}
        return out

    def _apply_renko_advisory_score(
        self,
        *,
        signal: str,
        base_score: int,
        renko_ctx: Dict[str, Any],
    ) -> int:
        mode = str(renko_ctx.get("mode") or "SHADOW_ONLY").upper()
        if mode != "ADVISORY_SCORE":
            return int(base_score)
        long_s = float(renko_ctx.get("renko_score_long", 0.0) or 0.0)
        short_s = float(renko_ctx.get("renko_score_short", 0.0) or 0.0)
        weight = float(max(0.0, getattr(CFG, "renko_adapter_score_weight", 4.0)))
        delta = (long_s - short_s) if str(signal).upper() == "BUY" else (short_s - long_s)
        adjusted = int(round(float(base_score) + float(delta) * float(weight)))
        return int(max(0, min(100, adjusted)))

    def _apply_unified_learning_advisory_score(
        self,
        *,
        symbol: str,
        base_score: int,
        strategy_family: str,
        is_paper: bool,
    ) -> Tuple[int, Dict[str, Any]]:
        if not bool(getattr(CFG, "unified_learning_runtime_enabled", True)):
            return int(base_score), {}
        if bool(getattr(CFG, "unified_learning_runtime_paper_only", True)) and (not bool(is_paper)):
            return int(base_score), {}
        scan_meta = self._scan_meta if isinstance(getattr(self, "_scan_meta", None), dict) else {}
        unified = scan_meta.get("unified_learning") if isinstance(scan_meta, dict) else None
        tw_meta = scan_meta.get("trade_window") if isinstance(scan_meta, dict) else None
        adj = resolve_unified_learning_family_adjustment(
            unified=unified if isinstance(unified, dict) else None,
            symbol=symbol,
            window_id=str((tw_meta or {}).get("window_id") or ""),
            window_phase=str((tw_meta or {}).get("phase") or ""),
            strategy_family=str(strategy_family or ""),
            min_samples=int(getattr(CFG, "unified_learning_runtime_min_samples", 20)),
            max_abs_delta=int(getattr(CFG, "unified_learning_runtime_max_abs_score_delta", 6)),
        )
        delta = int(adj.get("score_delta") or 0)
        if delta == 0:
            return int(base_score), adj
        adjusted = int(max(0, min(100, int(base_score) + int(delta))))
        logging.info(
            "UNIFIED_LEARNING_SCORE symbol=%s window=%s family=%s base=%s delta=%s adjusted=%s bias=%s feedback_weight=%.3f leader=%s reasons=%s",
            str(symbol_base(symbol)),
            str(adj.get("window") or "UNKNOWN"),
            str(strategy_family or "UNKNOWN"),
            int(base_score),
            int(delta),
            int(adjusted),
            str(adj.get("advisory_bias") or "NEUTRAL"),
            float(adj.get("feedback_weight") or 1.0),
            str(adj.get("feedback_leader") or "UNKNOWN"),
            ",".join([str(x) for x in (adj.get("reasons") or [])]) or "NONE",
        )
        return adjusted, adj

    def _dispatch_order(self, symbol: str, grp: str, request: dict, emergency: bool = False):
        # Prefer a single dispatch path when provided by the bot (hybrid REQ/REP).
        if callable(self.dispatch_order_hook):
            try:
                return self.dispatch_order_hook(symbol, grp, request, bool(emergency))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                return None
        if self.order_queue is not None:
            return self.order_queue.submit(symbol, grp, request, emergency=bool(emergency))
        return self.engine.order_send(symbol, grp, request, emergency=bool(emergency))

    def _rollover_cfg(self) -> Dict[str, Any]:
        raw = getattr(self.config, "rollover", {}) or {}
        if isinstance(raw, dict):
            return dict(raw)
        return {}

    def _rollover_cfg_bool(self, key: str, default: bool) -> bool:
        cfg = self._rollover_cfg()
        raw = cfg.get(key, default)
        if isinstance(raw, bool):
            return raw
        text = str(raw).strip().lower()
        if text in {"1", "true", "yes", "y", "on"}:
            return True
        if text in {"0", "false", "no", "n", "off"}:
            return False
        return bool(default)

    def _rollover_cfg_int(self, key: str, default: int) -> int:
        cfg = self._rollover_cfg()
        raw = cfg.get(key, default)
        try:
            return int(raw)
        except Exception:
            return int(default)

    def _index_rollover_symbol_set(self) -> set[str]:
        cfg = self._rollover_cfg()
        raw = cfg.get("index_symbols")
        out: set[str] = set()
        if isinstance(raw, list):
            for item in raw:
                for cand in symbol_alias_candidates(str(item or "")):
                    out.add(cand)
        if out:
            return out
        fallback = set()
        for sym, grp in (getattr(CFG, "symbol_group_map", {}) or {}).items():
            if str(grp or "").upper() == "INDEX":
                for cand in symbol_alias_candidates(str(sym or "")):
                    fallback.add(cand)
        return fallback

    def _is_index_rollover_symbol(self, symbol: Optional[str]) -> bool:
        if not symbol:
            return True
        cands = set(symbol_alias_candidates(symbol_base(symbol)))
        allowed = self._index_rollover_symbol_set()
        return not cands.isdisjoint(allowed)

    def _quarterly_months(self) -> List[int]:
        cfg = self._rollover_cfg()
        raw = cfg.get("quarter_months", [3, 6, 9, 12])
        if not isinstance(raw, list):
            return [3, 6, 9, 12]
        out: List[int] = []
        for item in raw:
            try:
                mm = int(item)
            except Exception:
                continue
            if 1 <= mm <= 12 and mm not in out:
                out.append(mm)
        return out or [3, 6, 9, 12]

    def _quarterly_rollover_anchor_ny(self, now_ny_dt: dt.datetime) -> Optional[dt.datetime]:
        if not self._rollover_cfg_bool("auto_index_quarterly", True):
            return None
        months = self._quarterly_months()
        offset_days = self._rollover_cfg_int("quarter_roll_offset_days", -2)
        schedule = quarterly_rollover_dates(int(now_ny_dt.year), months=months, offset_days=offset_days)
        expected = schedule.get(int(now_ny_dt.month))
        if expected is None:
            return None
        if now_ny_dt.date() != expected:
            return None
        hh = self._rollover_cfg_int("index_anchor_ny_hour", 17)
        mm = self._rollover_cfg_int("index_anchor_ny_minute", 0)
        hh = max(0, min(23, int(hh)))
        mm = max(0, min(59, int(mm)))
        return now_ny_dt.replace(hour=hh, minute=mm, second=0, microsecond=0)

    def _manual_rollover_anchors_ny(self, symbol: Optional[str]) -> List[Tuple[dt.datetime, Dict[str, Any]]]:
        cfg = self._rollover_cfg()
        raw = cfg.get("events")
        if not isinstance(raw, list):
            return []
        symbol_cands = set(symbol_alias_candidates(symbol_base(symbol or ""))) if symbol else set()
        out: List[Tuple[dt.datetime, Dict[str, Any]]] = []
        for item in raw:
            if not isinstance(item, dict):
                continue
            symbols = item.get("symbols")
            if isinstance(symbols, list) and symbols:
                allowed: set[str] = set()
                for s in symbols:
                    allowed.update(symbol_alias_candidates(str(s or "")))
                if symbol and symbol_cands.isdisjoint(allowed):
                    continue
            date_raw = str(item.get("date", "") or "").strip()
            if not date_raw:
                continue
            try:
                d = dt.date.fromisoformat(date_raw)
            except Exception:
                continue
            hh, mm = _parse_hhmm(item.get("time", "17:00"), default_hour=17, default_minute=0)
            tz_name = str(item.get("tz", "America/New_York") or "America/New_York")
            try:
                tz_obj = ZoneInfo(tz_name)
            except Exception:
                tz_obj = TZ_NY
            anchor_local = dt.datetime(d.year, d.month, d.day, hh, mm, 0, 0, tzinfo=tz_obj)
            out.append((anchor_local.astimezone(TZ_NY), dict(item)))
        return out

    def _daily_rollover_anchor_ny(self, now_ny_dt: dt.datetime) -> dt.datetime:
        return now_ny_dt.replace(hour=17, minute=0, second=0, microsecond=0)

    def _is_in_window(
        self,
        now_ny_dt: dt.datetime,
        anchor_ny_dt: dt.datetime,
        *,
        block_before_min: int,
        block_after_min: int,
    ) -> bool:
        start = anchor_ny_dt - dt.timedelta(minutes=max(0, int(block_before_min)))
        end = anchor_ny_dt + dt.timedelta(minutes=max(0, int(block_after_min)))
        return bool(start <= now_ny_dt <= end)

    def rollover_safe(self, symbol: Optional[str] = None) -> bool:
        now_ny_dt = now_ny()

        # Daily NY 17:00 safeguard (legacy behavior kept on purpose).
        if self._is_in_window(
            now_ny_dt,
            self._daily_rollover_anchor_ny(now_ny_dt),
            block_before_min=int(CFG.rollover_block_minutes_before),
            block_after_min=int(CFG.rollover_block_minutes_after),
        ):
            return False

        if not self._rollover_cfg_bool("enabled", True):
            return True

        if self._is_index_rollover_symbol(symbol):
            q_anchor = self._quarterly_rollover_anchor_ny(now_ny_dt)
            if q_anchor is not None and self._is_in_window(
                now_ny_dt,
                q_anchor,
                block_before_min=self._rollover_cfg_int("quarter_block_minutes_before", int(CFG.rollover_block_minutes_before)),
                block_after_min=self._rollover_cfg_int("quarter_block_minutes_after", int(CFG.rollover_block_minutes_after)),
            ):
                return False

        for anchor_ny_dt, event in self._manual_rollover_anchors_ny(symbol):
            before_min = int(event.get("block_before_min", CFG.rollover_block_minutes_before))
            after_min = int(event.get("block_after_min", CFG.rollover_block_minutes_after))
            if self._is_in_window(now_ny_dt, anchor_ny_dt, block_before_min=before_min, block_after_min=after_min):
                return False

        return True

    def force_close_window(self, symbol: Optional[str] = None) -> bool:
        now_ny_dt = now_ny()

        if self._is_in_window(
            now_ny_dt,
            self._daily_rollover_anchor_ny(now_ny_dt),
            block_before_min=int(CFG.force_close_before_rollover_min),
            block_after_min=0,
        ):
            return True

        if not self._rollover_cfg_bool("enabled", True):
            return False

        if self._is_index_rollover_symbol(symbol):
            q_anchor = self._quarterly_rollover_anchor_ny(now_ny_dt)
            if q_anchor is not None and self._is_in_window(
                now_ny_dt,
                q_anchor,
                block_before_min=self._rollover_cfg_int("quarter_force_close_before_min", int(CFG.force_close_before_rollover_min)),
                block_after_min=0,
            ):
                return True

        for anchor_ny_dt, event in self._manual_rollover_anchors_ny(symbol):
            force_before = int(event.get("force_close_before_min", CFG.force_close_before_rollover_min))
            if self._is_in_window(now_ny_dt, anchor_ny_dt, block_before_min=force_before, block_after_min=0):
                return True

        return False

    def get_trend(self, symbol: str, grp: str) -> Tuple[str, str, str]:
        now_ts = time.time()
        cached = self.cache.trend_cache.get(symbol)
        if cached and (now_ts - cached[0] < CFG.trend_cache_ttl_sec):
            return cached[1], cached[2], cached[3]

        sma_trend_win = max(2, _cfg_group_int(grp, "sma_trend", int(getattr(CFG, "sma_trend", 200)), symbol=symbol))
        sma_struct_fast_win = max(
            2,
            _cfg_group_int(grp, "sma_structure_fast", int(getattr(CFG, "sma_structure_fast", 55)), symbol=symbol),
        )
        sma_struct_slow_win = max(
            sma_struct_fast_win + 1,
            _cfg_group_int(grp, "sma_structure_slow", int(getattr(CFG, "sma_structure_slow", 200)), symbol=symbol),
        )

        slow_need = max(int(sma_trend_win), int(sma_struct_slow_win))
        req_h4 = max(80, slow_need + 20)
        req_d1 = max(80, int(sma_trend_win) + 20)
        df_h4 = self.engine.copy_rates(symbol, grp, CFG.timeframe_trend_h4, req_h4)
        df_d1 = self.engine.copy_rates(symbol, grp, CFG.timeframe_trend_d1, req_d1)
        if df_h4 is None or df_d1 is None:
            return "NEUTRAL", "NEUTRAL", "NEUTRAL"

        rows_h4 = int(len(df_h4))
        rows_d1 = int(len(df_d1))
        min_h4_rows = max(40, int(sma_struct_fast_win) + 5)
        min_d1_rows = 40
        if rows_h4 < min_h4_rows or rows_d1 < min_d1_rows:
            fallback_enabled = bool(
                _cfg_group_bool(
                    grp,
                    "trend_short_fallback_enabled",
                    bool(getattr(CFG, "trend_short_fallback_enabled", True)),
                    symbol=symbol,
                )
            )
            fallback_min_h4 = max(
                2,
                _cfg_group_int(
                    grp,
                    "trend_short_fallback_min_h4_rows",
                    int(getattr(CFG, "trend_short_fallback_min_h4_rows", 3)),
                    symbol=symbol,
                ),
            )
            fallback_min_d1 = max(
                1,
                _cfg_group_int(
                    grp,
                    "trend_short_fallback_min_d1_rows",
                    int(getattr(CFG, "trend_short_fallback_min_d1_rows", 1)),
                    symbol=symbol,
                ),
            )
            if fallback_enabled and rows_h4 >= fallback_min_h4 and rows_d1 >= fallback_min_d1:
                close_h4_last = float(df_h4["close"].iloc[-1])
                close_h4_prev = float(df_h4["close"].iloc[-2]) if rows_h4 >= 2 else close_h4_last
                trend_h4 = "BUY" if close_h4_last >= close_h4_prev else "SELL"

                if rows_d1 >= 2:
                    close_d1_last = float(df_d1["close"].iloc[-1])
                    close_d1_prev = float(df_d1["close"].iloc[-2])
                    trend_d1 = "BUY" if close_d1_last >= close_d1_prev else "SELL"
                else:
                    trend_d1 = trend_h4

                struct_span = max(2, min(rows_h4, 5))
                struct_ref = float(df_h4["close"].tail(struct_span).mean())
                structure_h4 = "BUY" if close_h4_last >= struct_ref else "SELL"

                logging.warning(
                    "TREND_DATA_SHORT_FALLBACK symbol=%s grp=%s rows_h4=%s rows_d1=%s min_h4=%s min_d1=%s trend_h4=%s trend_d1=%s structure_h4=%s",
                    symbol,
                    grp,
                    rows_h4,
                    rows_d1,
                    min_h4_rows,
                    min_d1_rows,
                    trend_h4,
                    trend_d1,
                    structure_h4,
                )
                self.cache.trend_cache[symbol] = (now_ts, trend_h4, trend_d1, structure_h4)
                return trend_h4, trend_d1, structure_h4
            logging.info(
                "TREND_DATA_SHORT symbol=%s grp=%s rows_h4=%s rows_d1=%s min_h4=%s min_d1=%s",
                symbol,
                grp,
                rows_h4,
                rows_d1,
                min_h4_rows,
                min_d1_rows,
            )
            return "NEUTRAL", "NEUTRAL", "NEUTRAL"

        trend_win_h4 = min(int(sma_trend_win), max(20, rows_h4 - 5))
        trend_win_d1 = min(int(sma_trend_win), max(20, rows_d1 - 5))
        struct_fast_eff = min(int(sma_struct_fast_win), max(10, rows_h4 - 10))
        struct_slow_eff = min(int(sma_struct_slow_win), max(struct_fast_eff + 1, rows_h4 - 5))
        if trend_win_h4 < 20 or trend_win_d1 < 20 or struct_slow_eff <= struct_fast_eff:
            return "NEUTRAL", "NEUTRAL", "NEUTRAL"

        if (
            trend_win_h4 != int(sma_trend_win)
            or trend_win_d1 != int(sma_trend_win)
            or struct_fast_eff != int(sma_struct_fast_win)
            or struct_slow_eff != int(sma_struct_slow_win)
        ):
            logging.info(
                "TREND_WARMUP_ADAPT symbol=%s grp=%s trend_cfg=%s trend_h4=%s trend_d1=%s struct_fast_cfg=%s struct_fast=%s struct_slow_cfg=%s struct_slow=%s rows_h4=%s rows_d1=%s",
                symbol,
                grp,
                int(sma_trend_win),
                int(trend_win_h4),
                int(trend_win_d1),
                int(sma_struct_fast_win),
                int(struct_fast_eff),
                int(sma_struct_slow_win),
                int(struct_slow_eff),
                rows_h4,
                rows_d1,
            )

        df_h4["sma_trend"] = ta.trend.sma_indicator(df_h4["close"], window=trend_win_h4)
        df_d1["sma_trend"] = ta.trend.sma_indicator(df_d1["close"], window=trend_win_d1)
        df_h4["sma_struct_fast"] = ta.trend.sma_indicator(df_h4["close"], window=struct_fast_eff)
        df_h4["sma_struct_slow"] = ta.trend.sma_indicator(df_h4["close"], window=struct_slow_eff)

        trend_h4 = "BUY" if float(df_h4["close"].iloc[-1]) > float(df_h4["sma_trend"].iloc[-1]) else "SELL"
        trend_d1 = "BUY" if float(df_d1["close"].iloc[-1]) > float(df_d1["sma_trend"].iloc[-1]) else "SELL"
        struct_fast = float(df_h4["sma_struct_fast"].iloc[-1])
        struct_slow = float(df_h4["sma_struct_slow"].iloc[-1])
        if struct_fast > struct_slow:
            structure_h4 = "BUY"
        elif struct_fast < struct_slow:
            structure_h4 = "SELL"
        else:
            structure_h4 = "NEUTRAL"
        self.cache.trend_cache[symbol] = (now_ts, trend_h4, trend_d1, structure_h4)
        return trend_h4, trend_d1, structure_h4

    def m5_indicators_if_due(self, symbol: str, grp: str, mode: str) -> Optional[Dict]:
        now_ts = time.time()
        tf_min = max(1, int(getattr(CFG, "timeframe_trade", 5)))
        default_wait_max = max(600, int(tf_min) * 2 * 60)
        wait_new_bar_max = max(
            int(tf_min) * 60,
            _cfg_group_int(
                grp,
                "m5_wait_new_bar_max_sec",
                int(getattr(CFG, "m5_wait_new_bar_max_sec", default_wait_max)),
                symbol=symbol,
            ),
        )
        try:
            sch = getattr(self.config, "scheduler", {}) or {}
            if mode == "ECO":
                pull = int(sch.get("m5_pull_sec_eco", CFG.m5_pull_sec_eco))
            elif mode == "WARM":
                pull = int(sch.get("m5_pull_sec_warm", CFG.m5_pull_sec_warm))
            else:
                pull = int(sch.get("m5_pull_sec_hot", CFG.m5_pull_sec_hot))
            pull = max(1, _cfg_group_int(grp, f"m5_pull_sec_{str(mode).lower()}", int(pull), symbol=symbol))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            pull = CFG.m5_pull_sec_eco if mode == "ECO" else (CFG.m5_pull_sec_warm if mode == "WARM" else CFG.m5_pull_sec_hot)
        last = self.cache.last_m5_calc_ts.get(symbol, 0.0)
        if now_ts - last < pull:
            wait_s = int(max(0, float(pull) - (now_ts - last)))
            self._metric_inc_skip("M5_PULL_WAIT")
            logging.info(f"ENTRY_SKIP_PRE symbol={symbol} grp={grp} mode={mode} reason=M5_PULL_WAIT wait_s={wait_s}")
            return None

        next_fetch_ts = float(self.cache.next_m5_fetch_ts.get(symbol, 0.0) or 0.0)
        if next_fetch_ts > now_ts:
            wait_raw_s = float(next_fetch_ts - now_ts)
            if wait_raw_s > float(wait_new_bar_max):
                # Defensive reset: do not freeze scans for ~hour due to future-shifted bar clocks.
                logging.warning(
                    "M5_WAIT_NEW_BAR_GUARD_RESET symbol=%s grp=%s mode=%s wait_raw_s=%s max_wait_s=%s tf_min=%s next_fetch_ts=%s now_ts=%s",
                    symbol,
                    grp,
                    mode,
                    int(wait_raw_s),
                    int(wait_new_bar_max),
                    int(tf_min),
                    int(next_fetch_ts),
                    int(now_ts),
                )
                self.cache.next_m5_fetch_ts[symbol] = float(now_ts)
            else:
                wait_s = int(max(0, wait_raw_s))
                self._metric_inc_skip("M5_WAIT_NEW_BAR")
                logging.info(
                    f"ENTRY_SKIP_PRE symbol={symbol} grp={grp} mode={mode} reason=M5_WAIT_NEW_BAR wait_s={wait_s}"
                )
                return None

        if bool(getattr(CFG, "hybrid_use_zmq_m5_features", True)):
            fcache = self.zmq_feature_cache if isinstance(self.zmq_feature_cache, dict) else None
            fres = None
            if fcache is not None:
                fres = fcache.get(symbol_base(symbol)) or fcache.get(str(symbol).upper())
            if isinstance(fres, dict):
                try:
                    ts_msg = float(fres.get("recv_ts") or 0.0)
                    max_age = max(5, int(getattr(CFG, "hybrid_snapshot_max_age_sec", 180)))
                    age_s = max(0.0, now_ts - ts_msg)
                    if age_s <= float(max_age):
                        last_bar = pd.Timestamp(fres.get("bar_time_pl"))
                        prev_bar = self.cache.last_m5_bar_time.get(symbol)
                        if prev_bar is not None and last_bar == prev_bar:
                            self._metric_inc_skip("M5_SAME_BAR")
                            logging.info(f"ENTRY_SKIP_PRE symbol={symbol} grp={grp} mode={mode} reason=M5_SAME_BAR")
                            return None
                        self.cache.last_m5_calc_ts[symbol] = now_ts
                        self.cache.last_m5_bar_time[symbol] = last_bar
                        self.cache.next_m5_fetch_ts[symbol] = float(now_ts) + float(max(1, int(getattr(CFG, "timeframe_trade", 5))) * 60)
                        ind = {
                            "close": float(fres.get("close")),
                            "open": float(fres.get("open")),
                            "high": (float(fres.get("high")) if fres.get("high") is not None else None),
                            "low": (float(fres.get("low")) if fres.get("low") is not None else None),
                            "sma": float(fres.get("sma_fast")),
                            "adx": float(fres.get("adx")),
                            "atr": float(fres.get("atr")),
                        }
                        self.last_indicators[symbol_base(symbol)] = dict(ind)
                        logging.info(
                            "ENTRY_READY source=ZMQ_FEATURE symbol=%s grp=%s mode=%s adx=%.2f close=%.6f sma=%.6f open=%.6f",
                            symbol,
                            grp,
                            mode,
                            float(ind["adx"]),
                            float(ind["close"]),
                            float(ind["sma"]),
                            float(ind["open"]),
                        )
                        return ind
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        strict_no_fetch = bool(getattr(CFG, "hybrid_m5_no_fetch_strict", False)) or bool(
            getattr(CFG, "hybrid_no_mt5_data_fetch_hard", False)
        )
        store_state = inspect_m5_store_readiness(
            getattr(self.engine, "bars_store", None),
            symbol_base(symbol),
            120,
            now_ts,
            timeframe_min=tf_min,
        )
        if strict_no_fetch and bool(store_state.get("stale")) and int(store_state.get("rows") or 0) > 0:
            self.cache.last_m5_calc_ts[symbol] = now_ts
            self._metric_inc_skip("M5_STORE_STALE")
            logging.info(
                "ENTRY_SKIP_PRE symbol=%s grp=%s mode=%s reason=M5_STORE_STALE rows=%s age_s=%s max_age=%s last_bar_utc=%s",
                symbol,
                grp,
                mode,
                int(store_state.get("rows") or 0),
                int(float(store_state.get("age_s") or 0.0)),
                int(store_state.get("max_age_sec") or 0),
                store_state.get("last_bar_utc"),
            )
            return None

        df = self.engine.copy_rates(symbol, grp, CFG.timeframe_trade, 120)
        if df is None or len(df) < 60:
            self.cache.last_m5_calc_ts[symbol] = now_ts
            rows = 0 if df is None else int(len(df))
            reason = "M5_DATA_SHORT"
            if strict_no_fetch and int(store_state.get("rows") or 0) > 0 and bool(store_state.get("stale")):
                reason = "M5_STORE_STALE"
            self._metric_inc_skip(reason)
            if reason == "M5_STORE_STALE":
                logging.info(
                    "ENTRY_SKIP_PRE symbol=%s grp=%s mode=%s reason=M5_STORE_STALE rows=%s age_s=%s max_age=%s last_bar_utc=%s",
                    symbol,
                    grp,
                    mode,
                    rows,
                    int(float(store_state.get('age_s') or 0.0)),
                    int(store_state.get('max_age_sec') or 0),
                    store_state.get('last_bar_utc'),
                )
            else:
                logging.info(f"ENTRY_SKIP_PRE symbol={symbol} grp={grp} mode={mode} reason=M5_DATA_SHORT rows={rows}")
            return None

        self.cache.last_m5_calc_ts[symbol] = now_ts
        last_bar = df["time"].iloc[-1]
        try:
            ts_bar = pd.Timestamp(last_bar)
            if ts_bar.tzinfo is None:
                ts_bar = ts_bar.tz_localize(TZ_PL)
            ts_utc = ts_bar.tz_convert(UTC)
            next_fetch = float(ts_utc.timestamp()) + float(tf_min * 60)
            wait_raw_s = float(next_fetch - now_ts)
            if wait_raw_s > float(wait_new_bar_max):
                logging.warning(
                    "M5_NEXT_FETCH_CLAMP symbol=%s grp=%s mode=%s wait_raw_s=%s max_wait_s=%s tf_min=%s bar_ts_utc=%s",
                    symbol,
                    grp,
                    mode,
                    int(wait_raw_s),
                    int(wait_new_bar_max),
                    int(tf_min),
                    ts_utc.replace(microsecond=0).isoformat(),
                )
                next_fetch = float(now_ts) + float(tf_min * 60)
            self.cache.next_m5_fetch_ts[symbol] = float(next_fetch)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        prev_bar = self.cache.last_m5_bar_time.get(symbol)
        if prev_bar is not None and last_bar == prev_bar :
            self._metric_inc_skip("M5_SAME_BAR")
            logging.info(f"ENTRY_SKIP_PRE symbol={symbol} grp={grp} mode={mode} reason=M5_SAME_BAR")
            return None
        self.cache.last_m5_bar_time[symbol] = last_bar

        sma_fast_win = max(2, _cfg_group_int(grp, "sma_fast", int(getattr(CFG, "sma_fast", 20)), symbol=symbol))
        adx_period = max(2, _cfg_group_int(grp, "adx_period", int(getattr(CFG, "adx_period", 14)), symbol=symbol))
        atr_period = max(2, _cfg_group_int(grp, "atr_period", int(getattr(CFG, "atr_period", 14)), symbol=symbol))

        df["sma_fast"] = ta.trend.sma_indicator(df["close"], window=sma_fast_win)
        adx = ta.trend.ADXIndicator(df["high"], df["low"], df["close"], window=adx_period)
        df["adx"] = adx.adx()

        atr = None
        try:
            tr1 = (df["high"] - df["low"]).abs()
            tr2 = (df["high"] - df["close"].shift(1)).abs()
            tr3 = (df["low"] - df["close"].shift(1)).abs()
            tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
            atr = float(tr.rolling(window=atr_period, min_periods=atr_period).mean().iloc[-1])
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            atr = None

        ind = {
            "close": float(df["close"].iloc[-1]),
            "open": float(df["open"].iloc[-1]),
            "high": float(df["high"].iloc[-1]),
            "low": float(df["low"].iloc[-1]),
            "prev_close": (float(df["close"].iloc[-2]) if len(df) >= 2 else None),
            "prev_open": (float(df["open"].iloc[-2]) if len(df) >= 2 else None),
            "prev_high": (float(df["high"].iloc[-2]) if len(df) >= 2 else None),
            "prev_low": (float(df["low"].iloc[-2]) if len(df) >= 2 else None),
            "sma": float(df["sma_fast"].iloc[-1]),
            "adx": float(df["adx"].iloc[-1]),
            "atr": float(atr) if atr is not None else None,
        }
        try:
            self.last_indicators[symbol_base(symbol)] = dict(ind)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        logging.info(
            f"ENTRY_READY symbol={symbol} grp={grp} mode={mode} "
            f"adx={float(ind['adx']):.2f} close={float(ind['close']):.6f} "
            f"sma={float(ind['sma']):.6f} open={float(ind['open']):.6f}"
        )
        return ind

    def try_trade(
        self,
        symbol: str,
        grp: str,
        mode: str,
        info,
        signal: str,
        is_paper: bool,
        ind: Optional[Dict[str, Any]] = None,
    ):
        self.update_skip_capture_context(stage="TRADE_PATH", signal=str(signal or ""))
        # tick na żądanie: spread + cena wykonania
        tick = self.engine.tick(symbol, grp, emergency=False)
        if not tick:
            # Signals are rare relative to scan loop; allow one emergency tick fetch as fallback
            # when snapshot tick stream is temporarily missing.
            tick = self.engine.tick(symbol, grp, emergency=True)
            if tick:
                logging.warning("ENTRY_TICK_FALLBACK symbol=%s grp=%s mode=%s source=MT5_EMERGENCY", symbol, grp, mode)
        if not tick:
            self._metric_inc_skip("TICK_UNAVAILABLE")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=TICK_UNAVAILABLE", symbol, grp, mode)
            return

        spread_pts = (tick.ask - tick.bid) / float(info.point)
        self.db.log_spread(symbol, spread_pts)
        p80 = self.db.get_p80_spread(symbol)
        spread_gate_hot = _cfg_group_float(
            grp, "spread_gate_hot_factor", float(getattr(CFG, "spread_gate_hot_factor", 1.25)), symbol=symbol
        )
        spread_gate_warm = _cfg_group_float(
            grp, "spread_gate_warm_factor", float(getattr(CFG, "spread_gate_warm_factor", 1.75)), symbol=symbol
        )
        spread_gate_eco = _cfg_group_float(
            grp, "spread_gate_eco_factor", float(getattr(CFG, "spread_gate_eco_factor", 2.00)), symbol=symbol
        )
        # Execution green gate: scalp (HOT) is only allowed on tight spreads; if spread widens,
        # we either downgrade HOT->WARM (if still acceptable) or skip.
        if p80 > 0:
            m_upper = str(mode).upper()
            if m_upper == "HOT" and spread_pts > float(spread_gate_hot) * p80:
                if spread_pts <= float(spread_gate_warm) * p80:
                    mode = "WARM"
                else:
                    self._metric_inc_skip("SPREAD_TOO_WIDE_HOT")
                    logging.info(
                        "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=SPREAD_TOO_WIDE spread_pts=%.2f p80=%.2f gate_hot=%.2f",
                        symbol,
                        grp,
                        m_upper,
                        float(spread_pts),
                        float(p80),
                        float(spread_gate_hot),
                    )
                    return
            elif m_upper == "WARM" and spread_pts > float(spread_gate_warm) * p80:
                self._metric_inc_skip("SPREAD_TOO_WIDE_WARM")
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=SPREAD_TOO_WIDE spread_pts=%.2f p80=%.2f gate_warm=%.2f",
                    symbol,
                    grp,
                    m_upper,
                    float(spread_pts),
                    float(p80),
                    float(spread_gate_warm),
                )
                return
            elif m_upper == "ECO" and spread_pts > float(spread_gate_eco) * p80:
                self._metric_inc_skip("SPREAD_TOO_WIDE_ECO")
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=SPREAD_TOO_WIDE spread_pts=%.2f p80=%.2f gate_eco=%.2f",
                    symbol,
                    grp,
                    m_upper,
                    float(spread_pts),
                    float(p80),
                    float(spread_gate_eco),
                )
                return

        price = float(tick.ask if signal == "BUY" else tick.bid)

        # account/risk context (no guessing)
        acc = self.engine.account_info()
        if acc is None:
            self._metric_inc_skip("ACCOUNT_INFO_UNAVAILABLE")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=ACCOUNT_INFO_UNAVAILABLE", symbol, grp, mode)
            return
        bal_now = float(getattr(acc, "balance", 0.0) or 0.0)
        eq_now = float(getattr(acc, "equity", bal_now) or bal_now)
        margin_free = float(getattr(acc, "margin_free", 0.0) or 0.0)
        if _is_crypto_major_symbol(symbol):
            min_margin_free_pct = float(
                max(
                    0.0,
                    min(
                        0.95,
                        _cfg_group_float(
                            grp,
                            "min_margin_free_pct",
                            float(getattr(CFG, "crypto_major_min_margin_free_pct", 0.45)),
                            symbol=symbol,
                        ),
                    ),
                )
            )
            margin_free_pct = 0.0 if eq_now <= 0.0 else float(margin_free) / float(eq_now)
            if margin_free_pct < float(min_margin_free_pct):
                self._metric_inc_skip("CRYPTO_MARGIN_GUARD")
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=CRYPTO_MARGIN_GUARD margin_free_pct=%.4f min=%.4f",
                    symbol,
                    grp,
                    mode,
                    float(margin_free_pct),
                    float(min_margin_free_pct),
                )
                return

        point = float(getattr(info, "point", 0.0) or 0.0)
        if point <= 0:
            self._metric_inc_skip("POINT_INVALID")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=POINT_INVALID", symbol, grp, mode)
            return
        atr_value = None
        if isinstance(ind, dict):
            try:
                atr_value = float(ind.get("atr", 0.0))
            except Exception:
                atr_value = None
        sl_points, tp_points = adaptive_exit_points(mode, point, atr_value, grp=grp, symbol=symbol)
        sl = price - sl_points * point if signal == "BUY" else price + sl_points * point
        tp = price + tp_points * point if signal == "BUY" else price - tp_points * point

        # Daily loss limit (PL day). Baseline estimated from balance minus realized net PnL since PL midnight.
        try:
            start_ts = pl_day_start_utc_ts()
            pnl_today = float(self.db.pnl_net_since_ts(int(start_ts)))
            bal_start = float(bal_now - pnl_today)
            if bal_start <= 0:
                bal_start = float(bal_now)
            dd_pct = 0.0
            if bal_start > 0:
                dd_pct = max(0.0, (bal_start - eq_now) / bal_start)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return

        if not self.risk_manager.daily_loss_guard(symbol, mode, dd_pct):
            self._metric_inc_skip("DAILY_LOSS_GUARD")
            if self._skip_log_allowed(symbol, "DAILY_LOSS_GUARD", 30):
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=DAILY_LOSS_GUARD dd_pct=%.5f",
                    symbol,
                    grp,
                    mode,
                    float(dd_pct),
                )
            return

        soft_loss = (dd_pct >= float(self.config.risk['daily_loss_soft_pct']))
        risk_pct = self.risk_manager.get_risk_pct(mode, soft_loss)
        if _is_crypto_major_symbol(symbol):
            risk_mult = float(
                max(
                    0.05,
                    min(
                        1.0,
                        _cfg_group_float(
                            grp,
                            "risk_multiplier",
                            float(getattr(CFG, "crypto_major_risk_mult", 0.55)),
                            symbol=symbol,
                        ),
                    ),
                )
            )
            risk_pct = float(risk_pct) * float(risk_mult)
            logging.info(
                "CRYPTO_RISK_MULT symbol=%s grp=%s mode=%s risk_mult=%.3f risk_pct=%.6f",
                symbol,
                grp,
                mode,
                float(risk_mult),
                float(risk_pct),
            )

        risk_money = eq_now * risk_pct
        if risk_money <= 0:
            self._metric_inc_skip("RISK_MONEY_ZERO")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=RISK_MONEY_ZERO", symbol, grp, mode)
            return

        # Portfolio heat + volume sizing from SL distance
        tick_size = float(getattr(info, "trade_tick_size", 0.0) or 0.0)
        tick_value = float(getattr(info, "trade_tick_value", 0.0) or 0.0)
        vol_min = float(getattr(info, "volume_min", 0.0) or 0.0)
        vol_max = float(getattr(info, "volume_max", 0.0) or 0.0)
        vol_step = float(getattr(info, "volume_step", 0.0) or 0.0)

        volume = self.risk_manager.get_sizing(
            eq_now, risk_pct, price, sl,
            tick_size, tick_value,
            vol_min, vol_max, vol_step,
            symbol,
            margin_free=margin_free
        )

        if volume is None:
            self._metric_inc_skip("VOLUME_UNAVAILABLE")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=VOLUME_UNAVAILABLE", symbol, grp, mode)
            return
        try:
            vol_cap = float(_cfg_group_float(grp, "volume_cap_lots", 0.0, symbol=symbol))
        except Exception:
            vol_cap = 0.0
        if vol_cap > 0.0:
            volume = min(float(volume), float(vol_cap))
            if vol_step > 0.0:
                volume = math.floor(float(volume) / float(vol_step)) * float(vol_step)
            volume = float(round(max(vol_min, min(vol_max, volume)), 8))
            if volume < vol_min:
                logging.info(
                    f"SKIP_VOL_CAP symbol={symbol} grp={grp} vol_cap={vol_cap:.6f} vol_min={vol_min:.6f}"
                )
                return
        
        positions = self.engine.positions_get(emergency=False)
        if positions is None:
            self._metric_inc_skip("POSITIONS_UNAVAILABLE")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=POSITIONS_UNAVAILABLE", symbol, grp, mode)
            return
        
        our_positions = [p for p in positions if int(getattr(p, "magic", 0) or 0) == int(CFG.magic_number)]
        if _is_crypto_major_symbol(symbol):
            max_major = int(
                max(
                    1,
                    _cfg_group_int(
                        grp,
                        "max_open_positions",
                        int(getattr(CFG, "crypto_major_max_open_positions", 1)),
                        symbol=symbol,
                    ),
                )
            )
            open_major = int(
                sum(
                    1
                    for p in our_positions
                    if _is_crypto_major_symbol(getattr(p, "symbol", ""))
                )
            )
            if open_major >= max_major:
                self._metric_inc_skip("CRYPTO_EXPOSURE_GUARD")
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=CRYPTO_EXPOSURE_GUARD open_major=%s max_major=%s",
                    symbol,
                    grp,
                    mode,
                    int(open_major),
                    int(max_major),
                )
                return

        if not self.risk_manager.check_portfolio_heat(our_positions, eq_now, symbol, risk_money, self.engine, self.db, grp):
            self._metric_inc_skip("PORTFOLIO_HEAT")
            logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=PORTFOLIO_HEAT", symbol, grp, mode)
            return

        cmd = mt5.ORDER_TYPE_BUY if signal == "BUY" else mt5.ORDER_TYPE_SELL

        # Decision event (do Scout) — zapis tylko, gdy realnie spełnione warunki wejścia
        event_id = None
        if getattr(self, "decision_store", None) is not None:
            event_id = uuid.uuid4().hex[:12]
            self._last_event_id = event_id

        # licznik kosztów (EDGE FUEL) — obejmuje całą ocenę symbolu + tick/account_info + order_send
        try:
            st = self.gov.day_state()
            price_used_now = int(st.get("price_used") or 0)
            sys_used_now = int(st.get("sys_used") or 0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            price_used_now = 0
            sys_used_now = 0

        price_before = int(self._last_eval_price_before or max(0, price_used_now - 1))
        price_requests_trade = max(1, price_used_now - price_before)

        base_choice = symbol_base(symbol)
        shadowB = None
        verdict_light = None
        server_time_anchor = None
        scan_meta: Dict[str, Any] = {}
        proposals_src: Dict[str, Any] = {}
        try:
            scan_meta = self._scan_meta if isinstance(getattr(self, "_scan_meta", None), dict) else {}
            shadowB = scan_meta.get("choice_shadowB")
            verdict_light = scan_meta.get("verdict_light")
            server_time_anchor = scan_meta.get("server_time_anchor")
            raw_props = scan_meta.get("proposals") if isinstance(scan_meta, dict) else None
            proposals_src = raw_props if isinstance(raw_props, dict) else {}
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        grp_u = _group_key(grp)
        # --- scalp-learning context (v3 DB columns; best-effort, no new MT5 fetches) ---
        tw_window_id = ""
        tw_phase = ""
        tw_group = ""
        global_mode = ""
        fx_bucket_idx = 0
        fx_bucket_count = 0
        carryover_active = 0
        policy_shadow_mode = 1
        p_windows_v2 = 0
        p_risk_windows = 0
        p_group_arb = 0
        p_overlap_arb = 0
        try:
            tw_meta = scan_meta.get("trade_window") if isinstance(scan_meta, dict) else None
            if isinstance(tw_meta, dict):
                tw_window_id = str(tw_meta.get("window_id") or "")
                tw_phase = str(tw_meta.get("phase") or "")
                tw_group = str(tw_meta.get("group") or "")
            global_mode = str(scan_meta.get("global_mode") or "")
            fx_meta = scan_meta.get("fx_rotation") if isinstance(scan_meta, dict) else None
            if isinstance(fx_meta, dict):
                fx_bucket_idx = int(fx_meta.get("bucket_idx") or 0)
                fx_bucket_count = int(fx_meta.get("bucket_count") or 0)
            co_meta = scan_meta.get("carryover") if isinstance(scan_meta, dict) else None
            if isinstance(co_meta, dict):
                carryover_active = 1 if bool(co_meta.get("active")) else 0
            policy_shadow_mode = 1 if bool(scan_meta.get("policy_shadow_mode", True)) else 0
            flags = scan_meta.get("policy_flags") if isinstance(scan_meta, dict) else None
            if isinstance(flags, dict):
                p_windows_v2 = 1 if bool(flags.get("windows_v2_enabled", False)) else 0
                p_risk_windows = 1 if bool(flags.get("risk_windows_enabled", False)) else 0
                p_group_arb = 1 if bool(flags.get("group_arbitration_enabled", False)) else 0
                p_overlap_arb = 1 if bool(flags.get("overlap_arbitration_enabled", False)) else 0
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        risk_entry_allowed = 1
        risk_reason = "NONE"
        risk_friday = 0
        risk_reopen = 0
        group_factor = 1.0
        try:
            gab = scan_meta.get("group_arb") if isinstance(scan_meta, dict) else None
            if isinstance(gab, dict):
                gmeta = gab.get(str(grp_u)) or {}
                if isinstance(gmeta, dict):
                    risk_entry_allowed = 1 if bool(gmeta.get("risk_entry_allowed", True)) else 0
                    risk_reason = str(gmeta.get("risk_reason", "NONE"))
                    risk_friday = 1 if bool(gmeta.get("risk_friday", False)) else 0
                    risk_reopen = 1 if bool(gmeta.get("risk_reopen", False)) else 0
                    group_factor = float(gmeta.get("priority_factor", 1.0))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # Ranking decomposition (the exact same semantic used in scan_once).
        now_rank = now_utc()
        use_windows_v2_hard = bool(p_windows_v2) and (not bool(policy_shadow_mode))
        try:
            time_weight = float(group_window_weight(grp_u, symbol, now_dt=now_rank)) if use_windows_v2_hard else float(self.ctrl.time_weight(grp_u, symbol))
        except Exception:
            time_weight = 1.0
        try:
            score_factor = float(self.ctrl.score_factor(grp_u, symbol))
        except Exception:
            score_factor = 1.0
        prio = float(time_weight) * float(score_factor) * float(group_factor)

        # Proposal for chosen symbol (stored by evaluate_symbol)
        prop_choice = proposals_src.get(base_choice) if isinstance(proposals_src, dict) else None
        signal_reason = str(prop_choice.get("signal_reason")) if isinstance(prop_choice, dict) and prop_choice.get("signal_reason") is not None else None
        strategy_family = str(prop_choice.get("strategy_family")) if isinstance(prop_choice, dict) and prop_choice.get("strategy_family") is not None else None
        regime = str(prop_choice.get("regime")) if isinstance(prop_choice, dict) and prop_choice.get("regime") is not None else None
        entry_score = int(prop_choice.get("entry_score")) if isinstance(prop_choice, dict) and prop_choice.get("entry_score") is not None else None
        entry_min_score = int(prop_choice.get("entry_min_score")) if isinstance(prop_choice, dict) and prop_choice.get("entry_min_score") is not None else None
        spread_cap_points = None
        try:
            if isinstance(prop_choice, dict) and prop_choice.get("spread_cap_points") is not None:
                spread_cap_points = float(prop_choice.get("spread_cap_points"))
        except Exception:
            spread_cap_points = None
        if spread_cap_points is None:
            try:
                if grp_u == "FX":
                    spread_cap_points = float(fx_spread_cap_points(symbol, grp=grp_u))
                elif grp_u == "METAL":
                    spread_cap_points = float(metal_spread_cap_points(symbol, grp=grp_u))
            except Exception:
                spread_cap_points = None

        # Global guard states (from scan_meta)
        black_swan_flag = 1 if bool(scan_meta.get("black_swan_flag", False)) else 0
        black_swan_precaution = 1 if bool(scan_meta.get("black_swan_precaution", False)) else 0
        self_heal_active = 1 if bool(scan_meta.get("self_heal_active", False)) else 0
        canary_active = 1 if bool(scan_meta.get("canary_active", False)) else 0
        drift_active = 1 if bool(scan_meta.get("drift_active", False)) else 0
        snapshot_block_new_entries = 1 if bool(scan_meta.get("snapshot_block_new_entries", False)) else 0

        eco_active = 1 if (str(global_mode).upper() == "ECO" or str(mode).upper() == "ECO") else 0

        topk_payload = []
        try:
            topk_list = scan_meta.get("topk_final") or scan_meta.get("topk_base") or []
            proposals = proposals_src if isinstance(proposals_src, dict) else {}
            for it in topk_list:
                raw = it.get("raw")
                ind = self.last_indicators.get(str(raw))
                prop = proposals.get(str(raw))
                prop2 = None
                if isinstance(prop, dict):
                    prop2 = dict(prop)
                    prop2["volume"] = float(volume)
                    if str(raw) == base_choice:
                        prop2["entry_price"] = float(price)
                        prop2["sl"] = float(sl)
                        prop2["tp"] = float(tp)
                        prop2["sl_points"] = int(sl_points)
                        prop2["tp_points"] = int(tp_points)
                topk_payload.append({
                    "raw": raw,
                    "sym": it.get("sym"),
                    "grp": it.get("grp"),
                    "prio": it.get("prio"),
                    "risk_entry_allowed": it.get("risk_entry_allowed"),
                    "risk_reason": it.get("risk_reason"),
                    "risk_friday": it.get("risk_friday"),
                    "risk_reopen": it.get("risk_reopen"),
                    "ind": ind,
                    "proposal": prop2,
                })
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        if event_id and getattr(self, "decision_store", None) is not None:
            row = {
                "event_id": event_id,
                "ts_utc": now_utc().isoformat().replace("+00:00", "Z"),
                "server_time_anchor": server_time_anchor,
                "topk_json": json.dumps(topk_payload, ensure_ascii=False),
                "choice_A": base_choice,
                "choice_shadowB": shadowB,
                "verdict_light": verdict_light,
                "signal": signal,
                "sl": float(sl),
                "tp": float(tp),
                "entry_price": float(price),
                "volume": float(volume),
                "spread_points": float(spread_pts),
                "price_used": int(price_used_now),
                "price_requests_trade": int(price_requests_trade),
                "sys_used": int(sys_used_now),
                "is_paper": int(1 if is_paper else 0),
                "mt5_order": None,
                "mt5_deal": None,
                "mt5_retcode": None,
                "mt5_retcode_name": None,
                "outcome_pnl_net": None,
                "outcome_profit": None,
                "outcome_commission": None,
                "outcome_swap": None,
                "outcome_fee": None,
                "outcome_closed_ts_utc": None,
                # v3 scalp-learning context (additive)
                "grp": str(grp_u),
                "window_id": (tw_window_id or None),
                "window_phase": (tw_phase or None),
                "window_group": (tw_group or None),
                "global_mode": (str(global_mode).upper() if global_mode else None),
                "symbol_mode": str(mode).upper(),
                "prio": float(prio),
                "time_weight": float(time_weight),
                "score_factor": float(score_factor),
                "group_factor": float(group_factor),
                "signal_reason": signal_reason,
                "strategy_family": strategy_family,
                "regime": regime,
                "adx": (float(ind.get("adx")) if isinstance(ind, dict) and ind.get("adx") is not None else None),
                "atr_points": (
                    (float(atr_value) / float(point))
                    if (atr_value is not None and float(point) > 0.0)
                    else None
                ),
                "spread_p80": (float(p80) if p80 is not None else None),
                "spread_cap_points": (float(spread_cap_points) if spread_cap_points is not None else None),
                "entry_score": entry_score,
                "entry_min_score": entry_min_score,
                "risk_entry_allowed": int(risk_entry_allowed),
                "risk_reason": str(risk_reason),
                "risk_friday": int(risk_friday),
                "risk_reopen": int(risk_reopen),
                "eco_active": int(eco_active),
                "black_swan_flag": int(black_swan_flag),
                "black_swan_precaution": int(black_swan_precaution),
                "self_heal_active": int(self_heal_active),
                "canary_active": int(canary_active),
                "drift_active": int(drift_active),
                "snapshot_block_new_entries": int(snapshot_block_new_entries),
                "fx_bucket_idx": int(fx_bucket_idx),
                "fx_bucket_count": int(fx_bucket_count),
                "carryover_active": int(carryover_active),
                "bot_version": str(CFG.BOT_VERSION),
                "policy_shadow_mode": int(policy_shadow_mode),
                "policy_windows_v2_enabled": int(p_windows_v2),
                "policy_risk_windows_enabled": int(p_risk_windows),
                "policy_group_arbitration_enabled": int(p_group_arb),
                "policy_overlap_arbitration_enabled": int(p_overlap_arb),
            }
            try:
                self.decision_store.insert_event(row)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        comment = f"SBOT-EVT-{event_id}" if event_id else f"MT5_SAFETY_BOT_{CFG.BOT_VERSION}"
        order_dev = int(max(1, _cfg_group_int(grp, "order_deviation_points", 20, symbol=symbol)))
        spread_component_price = (float(spread_pts) * float(point)) if float(point) > 0.0 else None
        expected_slippage_points = float(max(0.0, min(float(order_dev), float(max(0.0, float(spread_pts) * 0.25)))))
        expected_slippage_price = (
            float(expected_slippage_points) * float(point) if float(point) > 0.0 else None
        )
        estimated_entry_cost_components = {
            "spread_points": float(spread_pts),
            "spread_cost_price": spread_component_price,
            "expected_slippage_points": float(expected_slippage_points),
            "expected_slippage_cost_price": expected_slippage_price,
            "commission_estimate": None,
            "fee_estimate": None,
            "cost_units": "price_and_points",
            "cost_currency_basis": "SYMBOL_QUOTE_OR_UNKNOWN",
            "cost_estimation_quality": "PARTIAL",
            "calibration_status": "HYPOTHESIS_DEFAULT",
        }
        estimated_round_trip_cost = {
            "value_price": (
                float(2.0 * ((spread_component_price or 0.0) + (expected_slippage_price or 0.0)))
                if spread_component_price is not None
                else None
            ),
            "unit": "price",
            "cost_estimation_quality": ("PARTIAL" if spread_component_price is not None else "UNKNOWN"),
            "calibration_status": "HYPOTHESIS_DEFAULT",
        }
        target_move_price = float(abs(float(tp) - float(price)))
        cost_feasible_shadow = None
        if estimated_round_trip_cost.get("value_price") is not None:
            try:
                cost_feasible_shadow = bool(float(target_move_price) > float(estimated_round_trip_cost.get("value_price") or 0.0))
            except Exception:
                cost_feasible_shadow = None

        req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": cmd,
            "price": float(price),
            "sl": float(sl),
            "tp": float(tp),
            "deviation": order_dev,
            "magic": CFG.magic_number,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
            "spread_at_decision_points": float(spread_pts),
            "spread_at_decision_unit": "points",
            "spread_at_decision_provenance": "python.strategy.tick_snapshot",
            "estimated_entry_cost_components": estimated_entry_cost_components,
            "estimated_round_trip_cost": estimated_round_trip_cost,
            "cost_feasibility_shadow": cost_feasible_shadow,
            "target_move_price": float(target_move_price),
            "cost_gate_policy_mode": str(getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY")),
            "net_cost_feasible": (None if cost_feasible_shadow is None else bool(cost_feasible_shadow)),
            "cost_gate_reason_code": "NONE",
        }

        if is_paper:
            logging.info(f"PAPER TRADE: {signal} {symbol} @ {price} | SL {sl} TP {tp}")
            return

        res = self._dispatch_order(symbol, grp, req, emergency=False)
        et_symbol_canon = canonical_symbol(symbol)
        et_msg_id = str(getattr(res, "message_id", "") or "")
        et_request_price = float(getattr(res, "request_price", float(price)) or 0.0) if res is not None else float(price)
        et_fill_price = float(getattr(res, "executed_price", 0.0) or 0.0) if res is not None else 0.0
        et_slippage_abs = getattr(res, "slippage_abs_price", None) if res is not None else None
        et_slippage_points = getattr(res, "slippage_points", None) if res is not None else None
        et_slippage_ticks = getattr(res, "slippage_ticks", None) if res is not None else None
        et_retcode = int(getattr(res, "retcode", 0) or 0) if res is not None else 0
        et_record = {
            "event_type": "EXECUTION_RESULT",
            "correlation_id": et_msg_id,
            "request_id": str(getattr(res, "request_id", et_msg_id) if res is not None else et_msg_id),
            "command_id": str(getattr(res, "command_id", et_msg_id) if res is not None else et_msg_id),
            "message_id": et_msg_id,
            "symbol_raw": str(symbol),
            "symbol_canonical": et_symbol_canon,
            "group": str(grp_u),
            "request_price": float(et_request_price),
            "fill_price": float(et_fill_price) if et_fill_price > 0.0 else None,
            "spread_at_decision": float(spread_pts),
            "spread_unit": "points",
            "spread_provenance": "python.strategy.tick_snapshot",
            "slippage_abs_price": (float(et_slippage_abs) if et_slippage_abs is not None else None),
            "slippage_points": (float(et_slippage_points) if et_slippage_points is not None else None),
            "slippage_ticks": (float(et_slippage_ticks) if et_slippage_ticks is not None else None),
            "deviation_requested_points": int(order_dev),
            "deviation_effective_points": int(getattr(res, "deviation_effective_points", 0) or 0) if res is not None else None,
            "deviation_expected_points": int(order_dev),
            "deviation_unit": "points",
            "retcode": int(et_retcode),
            "retcode_name": (_retcode_name(int(et_retcode)) if et_retcode else "UNKNOWN"),
            "cost_estimation_quality": str(
                getattr(res, "cost_estimation_quality", estimated_entry_cost_components.get("cost_estimation_quality", "UNKNOWN"))
                if res is not None
                else estimated_entry_cost_components.get("cost_estimation_quality", "UNKNOWN")
            ),
            "estimated_entry_cost_components": estimated_entry_cost_components,
            "estimated_round_trip_cost": estimated_round_trip_cost,
            "cost_feasibility_shadow": cost_feasible_shadow,
            "cost_feasibility_mode": str(
                getattr(res, "cost_gate_policy_mode", getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY"))
                if res is not None
                else getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY")
            ).lower(),
            "net_cost_feasible": (
                getattr(res, "net_cost_feasible", (None if cost_feasible_shadow is None else bool(cost_feasible_shadow)))
                if res is not None
                else (None if cost_feasible_shadow is None else bool(cost_feasible_shadow))
            ),
            "cost_gate_reason_code": str(getattr(res, "cost_gate_reason_code", "NONE") if res is not None else "NONE"),
            "target_move_price": float(target_move_price),
            "cost_feasibility_payload_echo": (getattr(res, "cost_feasibility_shadow", None) if res is not None else None),
            "realized_cost_components": (
                dict(getattr(res, "realized_cost_components", {}) or {}) if res is not None else {}
            ),
            "timezone_basis": "UTC",
            "exact_window": "runtime_event",
            "source_list": ["python.safetybot", "python.zmq_bridge", "mql5.hybrid_agent"],
            "symbol_filter": str(et_symbol_canon),
            "method": "dispatch_result",
            "sample_size_n": 1,
            "low_stat_power": True,
        }
        if res is not None:
            try:
                dev_eff_pts = int(getattr(res, "deviation_effective_points", 0) or 0)
                if dev_eff_pts > int(order_dev) * 4:
                    self._emit_unit_diagnostic(
                        parameter_name="deviation_effective_points",
                        current_unit="points",
                        expected_unit="points",
                        risk_level="MED",
                        details={
                            "symbol": str(symbol),
                            "deviation_expected_points": int(order_dev),
                            "deviation_effective_points": int(dev_eff_pts),
                            "retcode": int(et_retcode),
                        },
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        self._append_execution_telemetry(et_record)
        if not res or res.retcode != mt5.TRADE_RETCODE_DONE:
            self._metric_note_order_result(False, spread_points=float(spread_pts))
            logging.error(f"Order failed: {getattr(res, 'retcode', None)} {getattr(res, 'comment', '')}")
            if event_id and getattr(self, "decision_store", None) is not None:
                try:
                    st2 = self.gov.day_state()
                    rc = int(getattr(res, "retcode", 0) or 0) if res is not None else None
                    self.decision_store.insert_event({
                        "event_id": event_id,
                        "ts_utc": now_utc().isoformat().replace("+00:00", "Z"),
                        "server_time_anchor": server_time_anchor,
                        "topk_json": json.dumps(topk_payload, ensure_ascii=False),
                        "choice_A": base_choice,
                        "choice_shadowB": shadowB,
                        "verdict_light": verdict_light,
                        "signal": signal,
                        "sl": float(sl),
                        "tp": float(tp),
                        "entry_price": float(price),
                        "volume": float(volume),
                        "spread_points": float(spread_pts),
                        "price_used": int(st2.get("price_used") or price_used_now),
                        "price_requests_trade": int(max(1, int(st2.get("price_used") or price_used_now) - price_before)),
                        "sys_used": int(st2.get("sys_used") or sys_used_now),
                        "is_paper": 0,
                        "mt5_order": int(getattr(res, "order", 0) or 0) if res is not None else 0,
                        "mt5_deal": int(getattr(res, "deal", 0) or 0) if res is not None else 0,
                        "mt5_retcode": rc,
                        "mt5_retcode_name": (_retcode_name(int(rc)) if rc is not None else None),
                        "outcome_pnl_net": None,
                        "outcome_profit": None,
                        "outcome_commission": None,
                        "outcome_swap": None,
                        "outcome_fee": None,
                        "outcome_closed_ts_utc": None,
                        # v3 context (same as pre-dispatch row)
                        "grp": str(grp_u),
                        "window_id": (tw_window_id or None),
                        "window_phase": (tw_phase or None),
                        "window_group": (tw_group or None),
                        "global_mode": (str(global_mode).upper() if global_mode else None),
                        "symbol_mode": str(mode).upper(),
                        "prio": float(prio),
                        "time_weight": float(time_weight),
                        "score_factor": float(score_factor),
                        "group_factor": float(group_factor),
                        "signal_reason": signal_reason,
                        "strategy_family": strategy_family,
                        "regime": regime,
                        "adx": (float(ind.get("adx")) if isinstance(ind, dict) and ind.get("adx") is not None else None),
                        "atr_points": (
                            (float(atr_value) / float(point))
                            if (atr_value is not None and float(point) > 0.0)
                            else None
                        ),
                        "spread_p80": (float(p80) if p80 is not None else None),
                        "spread_cap_points": (float(spread_cap_points) if spread_cap_points is not None else None),
                        "entry_score": entry_score,
                        "entry_min_score": entry_min_score,
                        "risk_entry_allowed": int(risk_entry_allowed),
                        "risk_reason": str(risk_reason),
                        "risk_friday": int(risk_friday),
                        "risk_reopen": int(risk_reopen),
                        "eco_active": int(eco_active),
                        "black_swan_flag": int(black_swan_flag),
                        "black_swan_precaution": int(black_swan_precaution),
                        "self_heal_active": int(self_heal_active),
                        "canary_active": int(canary_active),
                        "drift_active": int(drift_active),
                        "snapshot_block_new_entries": int(snapshot_block_new_entries),
                        "fx_bucket_idx": int(fx_bucket_idx),
                        "fx_bucket_count": int(fx_bucket_count),
                        "carryover_active": int(carryover_active),
                        "bot_version": str(CFG.BOT_VERSION),
                        "policy_shadow_mode": int(policy_shadow_mode),
                        "policy_windows_v2_enabled": int(p_windows_v2),
                        "policy_risk_windows_enabled": int(p_risk_windows),
                        "policy_group_arbitration_enabled": int(p_group_arb),
                        "policy_overlap_arbitration_enabled": int(p_overlap_arb),
                    })
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return

        # update decision event with MT5 ids
        if event_id and getattr(self, "decision_store", None) is not None:
            try:
                st2 = self.gov.day_state()
                self.decision_store.insert_event({
                    "event_id": event_id,
                    "ts_utc": now_utc().isoformat().replace("+00:00", "Z"),
                    "server_time_anchor": server_time_anchor,
                    "topk_json": json.dumps(topk_payload, ensure_ascii=False),
                    "choice_A": base_choice,
                    "choice_shadowB": shadowB,
                    "verdict_light": verdict_light,
                    "signal": signal,
                    "sl": float(sl),
                    "tp": float(tp),
                    "entry_price": float(price),
                    "volume": float(volume),
                    "spread_points": float(spread_pts),
                    "price_used": int(st2.get("price_used") or price_used_now),
                    "price_requests_trade": int(max(1, int(st2.get("price_used") or price_used_now) - price_before)),
                    "sys_used": int(st2.get("sys_used") or sys_used_now),
                    "is_paper": 0,
                    "mt5_order": int(getattr(res, "order", 0) or 0),
                    "mt5_deal": int(getattr(res, "deal", 0) or 0),
                    "mt5_retcode": int(getattr(res, "retcode", 0) or 0),
                    "mt5_retcode_name": _retcode_name(int(getattr(res, "retcode", 0) or 0)),
                    "outcome_pnl_net": None,
                    "outcome_profit": None,
                    "outcome_commission": None,
                    "outcome_swap": None,
                    "outcome_fee": None,
                    "outcome_closed_ts_utc": None,
                    # v3 context (same as pre-dispatch row)
                    "grp": str(grp_u),
                    "window_id": (tw_window_id or None),
                    "window_phase": (tw_phase or None),
                    "window_group": (tw_group or None),
                    "global_mode": (str(global_mode).upper() if global_mode else None),
                    "symbol_mode": str(mode).upper(),
                    "prio": float(prio),
                    "time_weight": float(time_weight),
                    "score_factor": float(score_factor),
                    "group_factor": float(group_factor),
                    "signal_reason": signal_reason,
                    "strategy_family": strategy_family,
                    "regime": regime,
                    "adx": (float(ind.get("adx")) if isinstance(ind, dict) and ind.get("adx") is not None else None),
                    "atr_points": (
                        (float(atr_value) / float(point))
                        if (atr_value is not None and float(point) > 0.0)
                        else None
                    ),
                    "spread_p80": (float(p80) if p80 is not None else None),
                    "spread_cap_points": (float(spread_cap_points) if spread_cap_points is not None else None),
                    "entry_score": entry_score,
                    "entry_min_score": entry_min_score,
                    "risk_entry_allowed": int(risk_entry_allowed),
                    "risk_reason": str(risk_reason),
                    "risk_friday": int(risk_friday),
                    "risk_reopen": int(risk_reopen),
                    "eco_active": int(eco_active),
                    "black_swan_flag": int(black_swan_flag),
                    "black_swan_precaution": int(black_swan_precaution),
                    "self_heal_active": int(self_heal_active),
                    "canary_active": int(canary_active),
                    "drift_active": int(drift_active),
                    "snapshot_block_new_entries": int(snapshot_block_new_entries),
                    "fx_bucket_idx": int(fx_bucket_idx),
                    "fx_bucket_count": int(fx_bucket_count),
                    "carryover_active": int(carryover_active),
                    "bot_version": str(CFG.BOT_VERSION),
                    "policy_shadow_mode": int(policy_shadow_mode),
                    "policy_windows_v2_enabled": int(p_windows_v2),
                    "policy_risk_windows_enabled": int(p_risk_windows),
                    "policy_group_arbitration_enabled": int(p_group_arb),
                    "policy_overlap_arbitration_enabled": int(p_overlap_arb),
                })
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        self.throttle.register_trade()
        self._metric_note_order_result(True, spread_points=float(spread_pts))
        logging.info(f"Order executed: {getattr(res, 'order', None)}")
    def evaluate_symbol(self, symbol: str, grp: str, mode: str, info, is_paper: bool) -> None:
        # P0: global backoff + per-symbol cooldown (avoid wasting PRICE budget on repeated skips)
        try:
            now_ts = int(time.time())
            gb_until = int(self.db.get_global_backoff_until_ts())
            if gb_until and now_ts < gb_until:
                reason = self.db.get_global_backoff_reason()
                self._metric_inc_skip("GLOBAL_BACKOFF")
                if self._skip_log_allowed(symbol, "GLOBAL_BACKOFF", 30):
                    logging.info(
                        "SKIP_GLOBAL_BACKOFF symbol=%s until_ts=%s reason=%s",
                        symbol,
                        int(gb_until),
                        str(reason),
                    )
                return
            if self.db.is_cooldown_active(symbol, now_ts=now_ts):
                cd_until = self.db.get_cooldown_until_ts(symbol)
                cd_reason = self.db.get_cooldown_reason(symbol)
                self._metric_inc_skip("COOLDOWN_ACTIVE")
                if self._skip_log_allowed(symbol, "COOLDOWN", 30):
                    logging.info(
                        "SKIP_COOLDOWN symbol=%s until_ts=%s reason=%s",
                        symbol,
                        int(cd_until),
                        str(cd_reason),
                    )
                return
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        if bool(getattr(CFG, "policy_shadow_mode_enabled", True)):
            sym_norm = canonical_symbol(symbol)
            if (
                sym_norm in self._asia_shadow_symbol_targets
                and (not bool(self._asia_shadow_symbol_gate.get(sym_norm, False)))
            ):
                self._metric_inc_skip("ASIA_PREFLIGHT_BLOCK")
                logging.warning(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=ASIA_PREFLIGHT_BLOCK preflight_ok=0",
                    symbol,
                    grp,
                    mode,
                )
                self._append_execution_telemetry(
                    {
                        "event_type": "ASIA_PREFLIGHT_BLOCK",
                        "symbol_raw": str(symbol),
                        "symbol_canonical": sym_norm,
                        "group": str(grp),
                        "method": "preflight_gate",
                        "sample_size_n": 1,
                        "low_stat_power": True,
                        "source_list": ["EVIDENCE/asia_symbol_preflight.json"],
                    }
                )
                return

        # soft-mode price: no new entries
        if self.gov.price_soft_mode():
            # Emit once per minute per symbol to avoid "silent stall" perception.
            try:
                last_soft = float(self.cache.last_soft_skip_log_ts.get(symbol, 0.0))
                if (now_ts - last_soft) >= 60:
                    st_soft = self.gov.day_state()
                    logging.info(
                        "ENTRY_SKIP_PRE symbol=%s grp=%s mode=%s reason=PRICE_SOFT_MODE price_used=%s price_soft=%s price_trade_budget=%s",
                        symbol,
                        grp,
                        mode,
                        int(st_soft.get("price_used", 0)),
                        int(getattr(self.gov, "price_soft", 0)),
                        int(getattr(self.gov, "price_trade_budget", 0)),
                    )
                    self.cache.last_soft_skip_log_ts[symbol] = float(now_ts)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            self._metric_inc_skip("PRICE_SOFT_MODE")
            return
        if not self.throttle.can_trade():
            self._metric_inc_skip("THROTTLE_BLOCK")
            return
        if not self.rollover_safe(symbol=symbol):
            self._metric_inc_skip("ROLLOVER_BLOCK")
            return

        try:
            st0 = self.gov.day_state()
            self._last_eval_price_before = int(st0.get('price_used') or 0)
            self._last_eval_sys_before = int(st0.get('sys_used') or 0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            self._last_eval_price_before = None
            self._last_eval_sys_before = None

        ind = self.m5_indicators_if_due(symbol, grp, mode)
        if not ind:
            return
        adx_value = float(ind["adx"])
        trend_h4, _trend_d1, structure_h4 = self.get_trend(symbol, grp)
        self.update_skip_capture_context(trend_h4=str(trend_h4), structure_h4=str(structure_h4), stage="TREND_CHECK")
        if trend_h4 == "NEUTRAL":
            self._metric_inc_skip("TREND_NEUTRAL")
            if self._skip_log_allowed(symbol, "TREND_NEUTRAL", 60):
                logging.info("ENTRY_SKIP symbol=%s grp=%s mode=%s reason=TREND_NEUTRAL", symbol, grp, mode)
            return

        regime = "TREND"
        if bool(getattr(CFG, "regime_switch_enabled", True)):
            adx_threshold = _cfg_group_float(
                grp, "adx_threshold", float(getattr(CFG, "adx_threshold", 22)), symbol=symbol
            )
            adx_range_max = _cfg_group_float(
                grp, "adx_range_max", float(getattr(CFG, "adx_range_max", 18)), symbol=symbol
            )
            regime = resolve_adx_regime(
                adx_value,
                adx_threshold,
                adx_range_max,
            )

        signal, signal_reason = select_entry_signal(
            trend_h4=trend_h4,
            structure_h4=structure_h4,
            regime=regime,
            close_price=float(ind["close"]),
            open_price=float(ind["open"]),
            sma_fast_value=float(ind["sma"]),
            structure_filter_enabled=bool(getattr(CFG, "structure_filter_enabled", True)),
            mean_reversion_enabled=bool(getattr(CFG, "mean_reversion_enabled", True)),
            mode=mode,
        )
        self.update_skip_capture_context(
            stage="SIGNAL_SELECT",
            signal=str(signal or ""),
            signal_reason=str(signal_reason or ""),
            regime=str(regime or ""),
        )

        if signal:
            grp_u = str(grp).upper()
            exec_err_recent = 0
            try:
                lookback = max(1.0, float(getattr(CFG, "execution_burst_lookback_sec", 120) or 120))
                ts_now = float(time.time())
                src = list(getattr(self.engine, "_exec_error_ts", []) or [])
                exec_err_recent = int(sum(1 for t in src if (ts_now - float(t)) <= lookback))
            except Exception:
                exec_err_recent = 0
            entry_score = None
            entry_min_score = None
            entry_spread_cap_points = None
            unified_learning_adj: Dict[str, Any] = {}
            candle_ctx = self._evaluate_candle_context(
                symbol=symbol,
                grp=grp,
                signal=signal,
                trend_h4=trend_h4,
                regime=regime,
                ind=ind,
            )
            renko_ctx = self._evaluate_renko_context(
                symbol=symbol,
                grp=grp,
                signal=signal,
                point=float(getattr(info, "point", 0.0) or 0.0),
            )
            try:
                self._scan_meta.setdefault("candle_context", {})[symbol_base(symbol)] = dict(candle_ctx)
                self._scan_meta.setdefault("renko_context", {})[symbol_base(symbol)] = dict(renko_ctx)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            strategy_family = infer_runtime_strategy_family(
                mode=mode,
                signal=signal,
                signal_reason=signal_reason,
                candle_ctx=candle_ctx,
                renko_ctx=renko_ctx,
            )
            self.update_skip_capture_context(strategy_family=strategy_family)
            if bool(getattr(CFG, "candle_adapter_emit_event", True)):
                c_patterns = ",".join([str(x) for x in (candle_ctx.get("candle_patterns") or [])]) or "NONE"
                logging.info(
                    "CANDLE_ADAPTER symbol=%s grp=%s mode=%s ready=%s bias=%s quality=%s reason=%s long=%.3f short=%.3f patterns=%s",
                    symbol,
                    grp_u,
                    str(candle_ctx.get("mode") or "SHADOW_ONLY"),
                    int(bool(candle_ctx.get("ready", False))),
                    str(candle_ctx.get("candle_bias") or "NONE"),
                    str(candle_ctx.get("candle_quality_grade") or "UNKNOWN"),
                    str(candle_ctx.get("reason_code") or "NONE"),
                    float(candle_ctx.get("candle_score_long", 0.0) or 0.0),
                    float(candle_ctx.get("candle_score_short", 0.0) or 0.0),
                    c_patterns,
                )
            if bool(getattr(CFG, "renko_adapter_emit_event", True)):
                logging.info(
                    "RENKO_ADAPTER symbol=%s grp=%s mode=%s ready=%s bias=%s quality=%s reason=%s "
                    "long=%.3f short=%.3f run=%s rev=%s bricks=%s brick_pts=%.2f eval_ms=%s",
                    symbol,
                    grp_u,
                    str(renko_ctx.get("mode") or "SHADOW_ONLY"),
                    int(bool(renko_ctx.get("ready", False))),
                    str(renko_ctx.get("renko_bias") or "NONE"),
                    str(renko_ctx.get("renko_quality_grade") or "UNKNOWN"),
                    str(renko_ctx.get("reason_code") or "NONE"),
                    float(renko_ctx.get("renko_score_long", 0.0) or 0.0),
                    float(renko_ctx.get("renko_score_short", 0.0) or 0.0),
                    int(renko_ctx.get("run_length", 0) or 0),
                    int(bool(renko_ctx.get("reversal_flag", False))),
                    int(renko_ctx.get("bricks_count", 0) or 0),
                    float(renko_ctx.get("brick_size_points", 0.0) or 0.0),
                    int(renko_ctx.get("renko_eval_ms", 0) or 0),
                )

            if grp_u == "FX":
                pace_ok, pace_meta = fx_budget_pacing_allows_entry(self.gov, self.db, now_dt=now_utc())
                if not pace_ok:
                    self._metric_inc_skip("FX_BUDGET_PACING")
                    logging.info(
                        "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=FX_BUDGET_PACING used=%s cap=%s "
                        "used_ratio=%.3f limit_ratio=%.3f progress=%.3f slack=%.3f",
                        symbol,
                        grp,
                        mode,
                        int(pace_meta.get("used", 0.0)),
                        int(pace_meta.get("cap", 0.0)),
                        float(pace_meta.get("used_ratio", 0.0)),
                        float(pace_meta.get("limit_ratio", 0.0)),
                        float(pace_meta.get("progress", 0.0)),
                        float(pace_meta.get("slack", 0.0)),
                    )
                    return

                if bool(getattr(CFG, "fx_signal_score_enabled", True)):
                    spread_hint = float(getattr(info, "spread", 0.0) or 0.0)
                    spread_p80 = float(self.db.get_p80_spread(symbol) or 0.0)
                    fx_score, fx_parts = score_fx_entry_signal(
                        symbol=symbol,
                        grp=grp,
                        mode=mode,
                        signal=signal,
                        signal_reason=signal_reason,
                        trend_h4=trend_h4,
                        structure_h4=structure_h4,
                        regime=regime,
                        close_price=float(ind["close"]),
                        open_price=float(ind["open"]),
                        high_price=float(ind.get("high")) if ind.get("high") is not None else None,
                        low_price=float(ind.get("low")) if ind.get("low") is not None else None,
                        sma_fast_value=float(ind["sma"]),
                        adx_value=adx_value,
                        atr_value=float(ind.get("atr")) if ind.get("atr") is not None else None,
                        point=float(getattr(info, "point", 0.0) or 0.0),
                        spread_points=spread_hint,
                        spread_p80=spread_p80,
                        execution_error_recent=exec_err_recent,
                    )
                    min_score = int(fx_score_threshold_for_mode(mode, symbol=symbol))
                    entry_score = self._apply_candle_advisory_score(
                        signal=signal,
                        base_score=int(fx_score),
                        candle_ctx=candle_ctx,
                    )
                    entry_score = self._apply_renko_advisory_score(
                        signal=signal,
                        base_score=int(entry_score),
                        renko_ctx=renko_ctx,
                    )
                    entry_score, unified_learning_adj = self._apply_unified_learning_advisory_score(
                        symbol=symbol,
                        base_score=int(entry_score),
                        strategy_family=str(strategy_family),
                        is_paper=bool(is_paper),
                    )
                    entry_min_score = int(min_score)
                    try:
                        entry_spread_cap_points = float(fx_parts.get("spread_cap_points", 0.0) or 0.0)
                    except Exception:
                        entry_spread_cap_points = None
                    logging.info(
                        "ENTRY_SCORE symbol=%s grp=%s mode=%s score=%s min_score=%s "
                        "A=%.1f B=%.1f C=%.1f D=%.1f E=%.1f spread=%.2f p80=%.2f cap=%.2f atr_pts=%.2f",
                        symbol,
                        grp,
                        mode,
                        int(entry_score),
                        int(min_score),
                        float(fx_parts.get("A_regime_direction", 0.0)),
                        float(fx_parts.get("B_trigger", 0.0)),
                        float(fx_parts.get("C_cost", 0.0)),
                        float(fx_parts.get("D_volatility", 0.0)),
                        float(fx_parts.get("E_exec_risk", 0.0)),
                        float(fx_parts.get("spread_points", 0.0)),
                        float(fx_parts.get("spread_p80", 0.0)),
                        float(fx_parts.get("spread_cap_points", 0.0)),
                        float(fx_parts.get("atr_points", -1.0)),
                    )
                    if int(entry_score) < int(min_score):
                        self._metric_inc_skip("FX_SCORE_BELOW_THRESHOLD")
                        logging.info(
                            "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=FX_SCORE_BELOW_THRESHOLD score=%s min_score=%s",
                            symbol,
                            grp,
                            mode,
                            int(entry_score),
                            int(min_score),
                        )
                        return

            elif grp_u == "METAL":
                pace_ok, pace_meta = metal_budget_pacing_allows_entry(self.gov, self.db, now_dt=now_utc())
                if not pace_ok:
                    self._metric_inc_skip("METAL_BUDGET_PACING")
                    logging.info(
                        "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=METAL_BUDGET_PACING used=%s cap=%s "
                        "used_ratio=%.3f limit_ratio=%.3f progress=%.3f slack=%.3f",
                        symbol,
                        grp,
                        mode,
                        int(pace_meta.get("used", 0.0)),
                        int(pace_meta.get("cap", 0.0)),
                        float(pace_meta.get("used_ratio", 0.0)),
                        float(pace_meta.get("limit_ratio", 0.0)),
                        float(pace_meta.get("progress", 0.0)),
                        float(pace_meta.get("slack", 0.0)),
                    )
                    return

                if bool(getattr(CFG, "metal_signal_score_enabled", True)):
                    spread_hint = float(getattr(info, "spread", 0.0) or 0.0)
                    spread_p80 = float(self.db.get_p80_spread(symbol) or 0.0)
                    metal_score, metal_parts = score_metal_entry_signal(
                        symbol=symbol,
                        grp=grp,
                        mode=mode,
                        signal=signal,
                        signal_reason=signal_reason,
                        trend_h4=trend_h4,
                        structure_h4=structure_h4,
                        regime=regime,
                        close_price=float(ind["close"]),
                        open_price=float(ind["open"]),
                        high_price=float(ind.get("high")) if ind.get("high") is not None else None,
                        low_price=float(ind.get("low")) if ind.get("low") is not None else None,
                        sma_fast_value=float(ind["sma"]),
                        adx_value=adx_value,
                        atr_value=float(ind.get("atr")) if ind.get("atr") is not None else None,
                        point=float(getattr(info, "point", 0.0) or 0.0),
                        spread_points=spread_hint,
                        spread_p80=spread_p80,
                        execution_error_recent=exec_err_recent,
                    )
                    min_score = int(metal_score_threshold_for_mode(mode, symbol=symbol))
                    entry_score = self._apply_candle_advisory_score(
                        signal=signal,
                        base_score=int(metal_score),
                        candle_ctx=candle_ctx,
                    )
                    entry_score = self._apply_renko_advisory_score(
                        signal=signal,
                        base_score=int(entry_score),
                        renko_ctx=renko_ctx,
                    )
                    entry_score, unified_learning_adj = self._apply_unified_learning_advisory_score(
                        symbol=symbol,
                        base_score=int(entry_score),
                        strategy_family=str(strategy_family),
                        is_paper=bool(is_paper),
                    )
                    entry_min_score = int(min_score)
                    try:
                        entry_spread_cap_points = float(metal_parts.get("spread_cap_points", 0.0) or 0.0)
                    except Exception:
                        entry_spread_cap_points = None
                    logging.info(
                        "ENTRY_SCORE symbol=%s grp=%s mode=%s score=%s min_score=%s "
                        "A=%.1f B=%.1f C=%.1f D=%.1f E=%.1f spread=%.2f p80=%.2f cap=%.2f atr_pts=%.2f wick=%.2f",
                        symbol,
                        grp,
                        mode,
                        int(entry_score),
                        int(min_score),
                        float(metal_parts.get("A_regime_direction", 0.0)),
                        float(metal_parts.get("B_trigger", 0.0)),
                        float(metal_parts.get("C_cost", 0.0)),
                        float(metal_parts.get("D_volatility", 0.0)),
                        float(metal_parts.get("E_exec_risk", 0.0)),
                        float(metal_parts.get("spread_points", 0.0)),
                        float(metal_parts.get("spread_p80", 0.0)),
                        float(metal_parts.get("spread_cap_points", 0.0)),
                        float(metal_parts.get("atr_points", -1.0)),
                        float(metal_parts.get("wick_ratio", 0.0)),
                    )
                    if int(entry_score) < int(min_score):
                        self._metric_inc_skip("METAL_SCORE_BELOW_THRESHOLD")
                        logging.info(
                            "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=METAL_SCORE_BELOW_THRESHOLD score=%s min_score=%s",
                            symbol,
                            grp,
                            mode,
                            int(entry_score),
                            int(min_score),
                        )
                        return

            elif grp_u == "CRYPTO":
                if bool(getattr(CFG, "crypto_signal_score_enabled", True)):
                    spread_hint = float(getattr(info, "spread", 0.0) or 0.0)
                    spread_p80 = float(self.db.get_p80_spread(symbol) or 0.0)
                    crypto_score, crypto_parts = score_metal_entry_signal(
                        symbol=symbol,
                        grp=grp,
                        mode=mode,
                        signal=signal,
                        signal_reason=signal_reason,
                        trend_h4=trend_h4,
                        structure_h4=structure_h4,
                        regime=regime,
                        close_price=float(ind["close"]),
                        open_price=float(ind["open"]),
                        high_price=float(ind.get("high")) if ind.get("high") is not None else None,
                        low_price=float(ind.get("low")) if ind.get("low") is not None else None,
                        sma_fast_value=float(ind["sma"]),
                        adx_value=adx_value,
                        atr_value=float(ind.get("atr")) if ind.get("atr") is not None else None,
                        point=float(getattr(info, "point", 0.0) or 0.0),
                        spread_points=spread_hint,
                        spread_p80=spread_p80,
                        execution_error_recent=exec_err_recent,
                    )
                    min_score = int(crypto_score_threshold_for_mode(mode, symbol=symbol))
                    entry_score = self._apply_candle_advisory_score(
                        signal=signal,
                        base_score=int(crypto_score),
                        candle_ctx=candle_ctx,
                    )
                    entry_score = self._apply_renko_advisory_score(
                        signal=signal,
                        base_score=int(entry_score),
                        renko_ctx=renko_ctx,
                    )
                    entry_score, unified_learning_adj = self._apply_unified_learning_advisory_score(
                        symbol=symbol,
                        base_score=int(entry_score),
                        strategy_family=str(strategy_family),
                        is_paper=bool(is_paper),
                    )
                    entry_min_score = int(min_score)
                    try:
                        entry_spread_cap_points = float(crypto_parts.get("spread_cap_points", 0.0) or 0.0)
                    except Exception:
                        entry_spread_cap_points = None
                    logging.info(
                        "ENTRY_SCORE symbol=%s grp=%s mode=%s score=%s min_score=%s "
                        "A=%.1f B=%.1f C=%.1f D=%.1f E=%.1f spread=%.2f p80=%.2f cap=%.2f atr_pts=%.2f wick=%.2f",
                        symbol,
                        grp,
                        mode,
                        int(entry_score),
                        int(min_score),
                        float(crypto_parts.get("A_regime_direction", 0.0)),
                        float(crypto_parts.get("B_trigger", 0.0)),
                        float(crypto_parts.get("C_cost", 0.0)),
                        float(crypto_parts.get("D_volatility", 0.0)),
                        float(crypto_parts.get("E_exec_risk", 0.0)),
                        float(crypto_parts.get("spread_points", 0.0)),
                        float(crypto_parts.get("spread_p80", 0.0)),
                        float(crypto_parts.get("spread_cap_points", 0.0)),
                        float(crypto_parts.get("atr_points", -1.0)),
                        float(crypto_parts.get("wick_ratio", 0.0)),
                    )
                    if int(entry_score) < int(min_score):
                        self._metric_inc_skip("CRYPTO_SCORE_BELOW_THRESHOLD")
                        logging.info(
                            "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=CRYPTO_SCORE_BELOW_THRESHOLD score=%s min_score=%s",
                            symbol,
                            grp,
                            mode,
                            int(entry_score),
                            int(min_score),
                        )
                        return

            signal_id = self._signal_id(symbol, signal, signal_reason, regime)
            if self._signal_dedup_block(signal_id):
                self._metric_inc_skip("SIGNAL_DUPLICATE")
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=SIGNAL_DUPLICATE signal_id=%s",
                    symbol,
                    grp,
                    mode,
                    signal_id,
                )
                return
            logging.info(
                f"ENTRY_SIGNAL symbol={symbol} grp={grp} mode={mode} trend_h4={trend_h4} "
                f"structure_h4={structure_h4} regime={regime} reason={signal_reason} "
                f"signal={signal} close={float(ind['close']):.6f} sma={float(ind['sma']):.6f} "
                f"open={float(ind['open']):.6f} adx={adx_value:.2f}"
            )
            self._metric_note_entry_signal()
            try:
                base = symbol_base(symbol)
                mid = float(ind.get('close'))
                point = float(getattr(info, 'point', 0.0) or 0.0)
                if point == 0.0:
                    point = 1e-5
                sl_points, tp_points = adaptive_exit_points(
                    mode, point, float(ind.get("atr", 0.0) or 0.0), grp=grp, symbol=symbol
                )
                if signal == 'BUY':
                    sl = mid - sl_points * point
                    tp = mid + tp_points * point
                else:
                    sl = mid + sl_points * point
                    tp = mid - tp_points * point
                self._scan_meta.setdefault('proposals', {})[base] = {
                    'base_symbol': base,
                    'direction': signal,
                    'entry_price': mid,
                    'sl': float(sl),
                    'tp': float(tp),
                    'sl_points': int(sl_points),
                    'tp_points': int(tp_points),
                    'point': point,
                    'tick_size': float(getattr(info, 'trade_tick_size', 0.0) or 0.0),
                    'tick_value': float(getattr(info, 'trade_tick_value', 0.0) or 0.0),
                    'spread_points': float(getattr(info, 'spread', 0.0) or 0.0),
                    'spread_cap_points': float(entry_spread_cap_points) if entry_spread_cap_points is not None else None,
                    'regime': str(regime),
                    'signal_reason': str(signal_reason),
                    'strategy_family': str(strategy_family),
                    'unified_learning_score_delta': int((unified_learning_adj or {}).get("score_delta") or 0),
                    'unified_learning_advisory_bias': str((unified_learning_adj or {}).get("advisory_bias") or "NEUTRAL"),
                    'unified_learning_feedback_weight': float((unified_learning_adj or {}).get("feedback_weight") or 1.0),
                    'unified_learning_feedback_leader': str((unified_learning_adj or {}).get("feedback_leader") or "INSUFFICIENT_DATA"),
                    'unified_learning_reasons': list((unified_learning_adj or {}).get("reasons") or []),
                    'entry_score': int(entry_score) if entry_score is not None else None,
                    'entry_min_score': int(entry_min_score) if entry_min_score is not None else None,
                    'candle_adapter_mode': str(candle_ctx.get("mode") or "SHADOW_ONLY"),
                    'candle_bias': str(candle_ctx.get("candle_bias") or "NONE"),
                    'candle_quality_grade': str(candle_ctx.get("candle_quality_grade") or "UNKNOWN"),
                    'candle_reason_code': str(candle_ctx.get("reason_code") or "NONE"),
                    'candle_score_long': float(candle_ctx.get("candle_score_long", 0.0) or 0.0),
                    'candle_score_short': float(candle_ctx.get("candle_score_short", 0.0) or 0.0),
                    'renko_adapter_mode': str(renko_ctx.get("mode") or "SHADOW_ONLY"),
                    'renko_bias': str(renko_ctx.get("renko_bias") or "NONE"),
                    'renko_quality_grade': str(renko_ctx.get("renko_quality_grade") or "UNKNOWN"),
                    'renko_reason_code': str(renko_ctx.get("reason_code") or "NONE"),
                    'renko_score_long': float(renko_ctx.get("renko_score_long", 0.0) or 0.0),
                    'renko_score_short': float(renko_ctx.get("renko_score_short", 0.0) or 0.0),
                }
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            self.try_trade(symbol, grp, mode, info, signal, is_paper, ind=ind)
        else:
            self._metric_inc_skip("NO_SIGNAL")
            if self._skip_log_allowed(symbol, "NO_SIGNAL", 90):
                logging.info(
                    "ENTRY_SKIP symbol=%s grp=%s mode=%s reason=NO_SIGNAL trend_h4=%s "
                    "structure_h4=%s regime=%s signal_reason=%s close=%.6f sma=%.6f open=%.6f adx=%.2f",
                    symbol,
                    grp,
                    mode,
                    str(trend_h4),
                    str(structure_h4),
                    str(regime),
                    str(signal_reason),
                    float(ind["close"]),
                    float(ind["sma"]),
                    float(ind["open"]),
                    float(adx_value),
                )

# =============================================================================
# BOT
# =============================================================================

def _disk_free_mb(path: Path) -> int:
    try:
        u = shutil.disk_usage(str(path))
        return int(u.free // (1024 * 1024))
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return 0

def _copy_with_timeout(src: Path, dst: Path, max_seconds: int) -> bool:
    """Copy file in chunks with wallclock timeout. Returns True if completed."""
    t0 = time.time()
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    try:
        buf = 8 * 1024 * 1024
        with open(src, "rb") as fsrc, open(tmp, "wb") as fdst:
            while True:
                if (time.time() - t0) > float(max_seconds):
                    return False
                chunk = fsrc.read(buf)
                if not chunk:
                    break
                fdst.write(chunk)
        try:
            os.replace(tmp, dst)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            shutil.move(str(tmp), str(dst))
        return True
    finally:
        try:
            if tmp.exists():
                tmp.unlink(missing_ok=True)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

def _enforce_backup_retention(backups_root: Path, keep_dir: Optional[Path] = None) -> None:
    """Enforce retention: last BACKUP_RETAIN_MAX_COUNT and total size <= BACKUP_RETAIN_MAX_TOTAL_GB."""
    try:
        backups_root.mkdir(parents=True, exist_ok=True)
        dirs = [p for p in backups_root.iterdir() if p.is_dir()]
        dirs.sort(key=lambda p: p.name)  # YYYYMMDD_HHMMSS lexicographic
        # Count-based
        while len(dirs) > int(BACKUP_RETAIN_MAX_COUNT):
            victim = dirs.pop(0)
            if keep_dir is not None and victim.resolve() == keep_dir.resolve():
                # never delete current backup dir
                dirs.append(victim)
                break
            shutil.rmtree(victim, ignore_errors=True)
        # Size-based
        def dir_size_bytes(d: Path) -> int:
            s = 0
            for fp in d.rglob("*"):
                try:
                    if fp.is_file():
                        s += fp.stat().st_size
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return s
        limit_bytes = int(BACKUP_RETAIN_MAX_TOTAL_GB) * (1024**3)
        # recompute dirs after possible deletions
        dirs = [p for p in backups_root.iterdir() if p.is_dir()]
        dirs.sort(key=lambda p: p.name)
        total = sum(dir_size_bytes(d) for d in dirs)
        while total > limit_bytes and dirs:
            victim = dirs.pop(0)
            if keep_dir is not None and victim.resolve() == keep_dir.resolve():
                break
            sz = dir_size_bytes(victim)
            shutil.rmtree(victim, ignore_errors=True)
            total = max(0, total - sz)
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

def _sqlite_table_exists(cur: sqlite3.Cursor, table: str) -> bool:
    try:
        row = cur.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
            (str(table),),
        ).fetchone()
        return bool(row and row[0] == 1)
    except Exception:
        return False


def _sqlite_table_cols(cur: sqlite3.Cursor, table: str) -> Set[str]:
    try:
        cols = cur.execute(f"PRAGMA table_info({table});").fetchall()
        return {str(r[1]) for r in cols if r and r[1]}
    except Exception:
        return set()


def _migrate_decision_events_schema_v3(cur: sqlite3.Cursor, log: logging.Logger) -> None:
    """Schema v3: enrich decision_events with scalp-learning fields (additive, safe).

    Must be idempotent. Safe to run even if table does not exist yet.
    """
    if not _sqlite_table_exists(cur, "decision_events"):
        log.info("MIGRATE V3 | decision_events_missing=1 action=SKIP_STRUCTURAL")
        return

    cols = _sqlite_table_cols(cur, "decision_events")
    # Additive columns only (no strategy behavior impact).
    want: List[Tuple[str, str]] = [
        ("grp", "TEXT"),
        ("window_id", "TEXT"),
        ("window_phase", "TEXT"),
        ("window_group", "TEXT"),
        ("global_mode", "TEXT"),
        ("symbol_mode", "TEXT"),
        ("prio", "REAL"),
        ("time_weight", "REAL"),
        ("score_factor", "REAL"),
        ("group_factor", "REAL"),
        ("signal_reason", "TEXT"),
        ("strategy_family", "TEXT"),
        ("regime", "TEXT"),
        ("adx", "REAL"),
        ("atr_points", "REAL"),
        ("spread_p80", "REAL"),
        ("spread_cap_points", "REAL"),
        ("entry_score", "INT"),
        ("entry_min_score", "INT"),
        ("risk_entry_allowed", "INT"),
        ("risk_reason", "TEXT"),
        ("risk_friday", "INT"),
        ("risk_reopen", "INT"),
        ("eco_active", "INT"),
        ("black_swan_flag", "INT"),
        ("black_swan_precaution", "INT"),
        ("self_heal_active", "INT"),
        ("canary_active", "INT"),
        ("drift_active", "INT"),
        ("snapshot_block_new_entries", "INT"),
        ("fx_bucket_idx", "INT"),
        ("fx_bucket_count", "INT"),
        ("carryover_active", "INT"),
        ("mt5_retcode", "INT"),
        ("mt5_retcode_name", "TEXT"),
        ("bot_version", "TEXT"),
        ("policy_shadow_mode", "INT"),
        ("policy_windows_v2_enabled", "INT"),
        ("policy_risk_windows_enabled", "INT"),
        ("policy_group_arbitration_enabled", "INT"),
        ("policy_overlap_arbitration_enabled", "INT"),
    ]
    added = 0
    for name, typ in want:
        if name in cols:
            continue
        cur.execute(f"ALTER TABLE decision_events ADD COLUMN {name} {typ};")
        added += 1
        cols.add(name)
    log.info("MIGRATE V3 | decision_events_add_columns=%s", int(added))

    # Helpful indexes for analytics/learner (idempotent).
    cur.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_choice ON decision_events(choice_A);")
    cur.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_closed ON decision_events(outcome_closed_ts_utc);")
    if "grp" in cols:
        cur.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_grp_closed ON decision_events(grp, outcome_closed_ts_utc);")


def ensure_db_ready(db_dir: Path, backups_dir: Path, release_id: str, log: logging.Logger) -> None:
    """Auto DB migration/compatibility per Rulebook v1.2. Stops on unsafe state."""
    t0 = time.time()
    db_dir.mkdir(parents=True, exist_ok=True)
    backups_dir.mkdir(parents=True, exist_ok=True)

    decision_path = db_dir / DECISION_EVENTS_DB_NAME
    legacy_found = "NONE"
    if not decision_path.exists():
        for name in LEGACY_DB_NAMES:
            p = db_dir / name
            if p.exists():
                legacy_found = name
                break

    log.info(f"ENV | host={platform.node()} | user={getpass.getuser()} | root={db_dir.parent} | release_id={release_id}")
    log.info(f"MIGRATE START | release_id={release_id} | db_path={decision_path} | current_schema={CURRENT_SCHEMA_VERSION}")
    log.info(f"MIGRATE DETECT | decision_db_exists={1 if decision_path.exists() else 0} | legacy_found={legacy_found}")

    if (time.time() - t0) > float(MIGRATE_WALLCLOCK_MAX_SECONDS):
        raise SystemExit(3)

    # If legacy exists and decision missing: backup + rename
    backup_dir = None
    if (not decision_path.exists()) and legacy_found != "NONE":
        src = db_dir / legacy_found
        # disk free guard
        free_mb = _disk_free_mb(backups_dir)
        if free_mb < int(DISK_FREE_MIN_MB):
            log.error(f"MIGRATE BACKUP | src={src} | dst=NONE | status=FAIL | reason=disk_free_mb<{DISK_FREE_MIN_MB}")
            raise SystemExit(3)

        backup_dir = backups_dir / dt.datetime.now(tz=UTC).strftime("%Y%m%d_%H%M%S")
        backup_dir.mkdir(parents=True, exist_ok=True)
        dst = backup_dir / f"{legacy_found}.bak"
        ok = _copy_with_timeout(src, dst, max_seconds=int(MIGRATE_STEP_MAX_SECONDS))
        if not ok:
            try:
                if dst.exists():
                    dst.unlink(missing_ok=True)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            log.error(f"MIGRATE BACKUP | src={src} | dst={dst} | status=FAIL | reason=TIMEOUT")
            raise SystemExit(3)
        log.info(f"MIGRATE BACKUP | src={src} | dst={dst} | status=OK")

        # atomic rename within DB dir
        try:
            os.replace(str(src), str(decision_path))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            log.error(f"MIGRATE RENAME | from={src} | to={decision_path} | status=FAIL | err={type(e).__name__}")
            raise SystemExit(3)
        log.info(f"MIGRATE RENAME | from={src} | to={decision_path} | status=OK")

    # Enforce retention after backup+rename
    if backup_dir is not None:
        _enforce_backup_retention(backups_dir, keep_dir=backup_dir)

    # Schema migrations (stepwise)
    try:
        conn = sqlite3.connect(str(decision_path), timeout=3, isolation_level=None, check_same_thread=False)
        conn.execute(f"PRAGMA busy_timeout={int(SQLITE_BUSY_TIMEOUT_MS)};")
        cur = conn.cursor()
        cur.execute("PRAGMA user_version;")
        row = cur.fetchone()
        before = int(row[0] if row and row[0] is not None else 0)
        log.info(f"MIGRATE SCHEMA | before={before} | target={CURRENT_SCHEMA_VERSION}")
        v = before
        while v < int(CURRENT_SCHEMA_VERSION):
            if (time.time() - t0) > float(MIGRATE_WALLCLOCK_MAX_SECONDS):
                raise TimeoutError("MIGRATE_WALLCLOCK_TIMEOUT")
            step_start = time.time()
            cur.execute("BEGIN;")
            try:
                # Migration step v -> v+1 (currently: only bump user_version; structural changes must be added here later)
                nxt = v + 1
                if v == 2 and nxt == 3:
                    _migrate_decision_events_schema_v3(cur, log)
                cur.execute(f"PRAGMA user_version={nxt};")
                cur.execute("COMMIT;")
                log.info(f"MIGRATE STEP | from={v} | to={nxt} | id=v{v}_to_v{nxt} | status=OK")
                v = nxt
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                try:
                    cur.execute("ROLLBACK;")
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                log.error(f"MIGRATE STEP | from={v} | to={v+1} | id=v{v}_to_v{v+1} | status=FAIL | err={type(e).__name__}")
                raise SystemExit(3)
            if (time.time() - step_start) > float(MIGRATE_STEP_MAX_SECONDS):
                log.error("MIGRATE STEP | status=FAIL | reason=TIMEOUT")
                raise SystemExit(3)
        # final
        cur.execute("PRAGMA user_version;")
        after = int(cur.fetchone()[0] or 0)
        log.info(f"MIGRATE END | after={after} | status=OK")
        conn.close()
    except SystemExit:
        raise
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        log.error(f"MIGRATE END | after=? | status=FAIL | err={type(e).__name__}")
        raise SystemExit(3)

    if backup_dir is not None:
        # retention again after OK (now allowed to delete older)
        _enforce_backup_retention(backups_dir, keep_dir=None)

    if (time.time() - t0) > float(MIGRATE_WALLCLOCK_MAX_SECONDS):
        log.error("MIGRATE END | status=FAIL | reason=TIMEOUT")
        raise SystemExit(3)

class SafetyBot:
    def __init__(
        self,
        config,
        db,
        gov,
        risk_manager,
        limits,
        black_swan_guard,
        self_heal_guard,
        canary_guard,
        drift_guard,
        incident_journal,
        zmq_bridge,
        black_swan_guard_v2=None,
    ):
        self.cfg = CFG
        self.config = config
        self.db = db
        self.gov = gov
        self.risk_manager = risk_manager
        self.limits = limits
        self.black_swan_guard = black_swan_guard
        self.black_swan_guard_v2 = black_swan_guard_v2
        self.self_heal_guard = self_heal_guard
        self.canary_guard = canary_guard
        self.drift_guard = drift_guard
        self.incident_journal = incident_journal
        self.zmq_bridge = zmq_bridge
        self._black_swan_v2_last_decision: Optional[BlackSwanGuardDecisionV2] = None
        self._black_swan_block_new_entries: bool = False
        self._black_swan_v2_reason: str = "NONE"
        self._black_swan_v2_state: str = "NORMAL"
        self._black_swan_v2_action: str = "ALLOW"
        self._last_heartbeat_ok_ts: float = 0.0
        self._last_trade_slippage_points: float = 0.0

        # --- runtime root (V6.2 hard-root) ---
        self.run_mode = get_run_mode()
        self.runtime_root = get_runtime_root(enforce=True)
        _paths = project_paths(self.runtime_root)
        self.bin_dir = _paths["bin"]
        self.meta_dir = _paths["meta"]
        self.db_dir = _paths["db"]
        self.config_dir = _paths["config"]
        self.logs_dir = _paths["logs"]
        self.run_dir = _paths["run"]
        self.backups_dir = _paths["backups"]
        self.lock_dir = _paths["lock"]
        self.evidence_dir = _paths["evidence"]
        self.execution_telemetry_path = self.logs_dir / "execution_telemetry_v2.jsonl"
        self.asia_preflight_path = self.evidence_dir / "asia_symbol_preflight.json"
        self.live_canary_contract_path = self.evidence_dir / str(
            getattr(CFG, "hard_live_contract_file_name", "live_canary_contract.json")
        )
        self.no_live_drift_path = self.evidence_dir / str(
            getattr(CFG, "no_live_drift_file_name", "no_live_drift_check.json")
        )
        self.cost_guard_auto_relax_path = self.evidence_dir / str(
            getattr(CFG, "cost_guard_auto_relax_status_file_name", "cost_guard_auto_relax_status.json")
        )
        self._asia_shadow_symbol_gate: Dict[str, bool] = {}
        self._asia_shadow_symbol_targets: Set[str] = set()
        self._live_canary_allowed_symbols: Set[str] = set()
        self._hard_live_disabled_symbols: Set[str] = set()
        self._cost_guard_auto_relax_state: Dict[str, Any] = {
            "active": False,
            "effective_block_on_unknown_quality": bool(getattr(CFG, "cost_gate_block_on_unknown_quality", True)),
            "effective_min_ratio": float(max(0.0, getattr(CFG, "cost_gate_min_target_to_cost_ratio", 1.10))),
            "reason": "NOT_EVALUATED",
            "metrics": {},
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        }
        self._cost_guard_flap_transition_ts: List[float] = []
        self._live_module_states: Dict[str, str] = {}
        self._live_module_state_reasons: Dict[str, List[str]] = {}
        self._live_window_trade_counts: Dict[str, int] = {}
        self._live_window_keys: Dict[str, str] = {}
        self._live_guard_snapshot: Dict[str, Any] = {}
        self.manual_kill_switch_path = self.runtime_root / str(getattr(CFG, "manual_kill_switch_file", "RUN/kill_switch.flag"))
        self._last_manual_kill_log_ts = 0.0
        self._startup_ts: float = float(time.time())
        self._last_snapshot_health_log_ts: float = 0.0
        self.stage1_live_config_enabled = bool(getattr(CFG, "stage1_live_config_enabled", True))
        self.stage1_live_config_path = self.runtime_root / str(
            getattr(CFG, "stage1_live_config_file", "LAB/RUN/live_config_stage1_apply.json")
        )
        self.stage1_live_reload_interval_sec = max(
            2, int(getattr(CFG, "stage1_live_reload_interval_sec", 15))
        )
        self.stage1_live_status_path = self.runtime_root / str(
            getattr(CFG, "stage1_live_status_file", "RUN/stage1_live_loader_status.json")
        )
        self.stage1_live_audit_path = self.runtime_root / str(
            getattr(CFG, "stage1_live_audit_file", "RUN/stage1_live_loader_audit.jsonl")
        )
        self.stage1_live_audit_enabled = bool(getattr(CFG, "stage1_live_audit_enabled", True))
        self._stage1_live_last_check_ts: float = 0.0
        self._stage1_live_last_seen_mtime_ns: int = -1
        self._stage1_live_last_mtime_ns: int = -1
        self._stage1_live_last_failed_mtime_ns: int = -1
        self._stage1_live_last_error: str = ""
        self._stage1_live_last_loaded_symbols: int = 0
        self._stage1_live_last_ok_utc: str = ""
        self._stage1_live_last_status: str = "INIT"
        self._stage1_live_last_status_reason: str = "NOT_CHECKED"
        self._metrics_day_key = str(pl_day_key(now_utc()))
        self._metrics_eco_scans_day = 0
        self._metrics_warn_scans_day = 0
        self._metrics_10m_last_emit_ts = 0.0
        self._metrics_10m_anchor: Dict[str, Any] = {}
        self._runtime_loop_id: int = 0
        self._last_group_budget_log_ts = 0.0
        self._loop_scan_durations_ms: List[int] = []
        self._loop_scan_runs: int = 0
        self._loop_scan_errors: int = 0
        self._loop_heartbeat_fail_total: int = 0
        self._loop_heartbeat_recoveries: int = 0
        self._loop_section_durations_ms: Dict[str, List[int]] = {
            "tick_ingest": [],
            "bridge_send": [],
            "bridge_wait": [],
            "bridge_parse": [],
            "session_gate": [],
            "cost_gate": [],
            "decision_core": [],
            "execution_call": [],
            "io_log": [],
        }
        self._last_scan_suppressed_log_ts: float = 0.0
        self._last_heartbeat_fail_log_ts: float = 0.0
        self._last_loop_health_emit_ts: float = 0.0
        self._last_policy_runtime_emit_ts: float = 0.0
        self._last_kernel_config_emit_ts: float = 0.0
        self._runtime_cached_group_arb: Dict[str, Dict[str, Any]] = {}
        self._runtime_cached_group_risk: Dict[str, Dict[str, Any]] = {}
        self._runtime_cached_group_ts_utc: str = ""
        self._last_budget_log_ts: float = 0.0
        self._last_oanda_price_breakdown_log_ts: float = 0.0
        ensure_dirs(_paths)

        # LIVE: terminal OANDA MT5 hard requirement (fail-fast before connect)
        if self.run_mode == "LIVE":
            try:
                require_live_oanda_terminal()
            except Exception as e:
                logging.error(str(e))
                raise SystemExit(11)

        # --- lock (multi-run guard) ---
        self.lock_path = self.run_dir / 'safetybot.lock'
        acquire_lockfile(self.lock_path)
        import atexit
        atexit.register(lambda: release_lockfile(self.lock_path))
        # --- logging (local only; required for OFFLINE traceability) ---
        setup_logging(self.runtime_root)
        logging.getLogger("SafetyBot").info("Start (offline-first guards enabled).")
        # Control-plane adapter: load stage1 live config once at startup.
        self._reload_stage1_live_config(force=True)

        # --- KEY drive (identified by volume label; not by drive letter) ---
        self.key_drive = get_usb_path(self.cfg.usb_drive_label)
        if self.key_drive is None:
            msg = f"CRITICAL: BRAK KLUCZA (TOKEN/BotKey.env) na woluminie o etykiecie '{self.cfg.usb_drive_label}'. Tryb bezpieczny: SafetyBot nie startuje."
            print(msg)
            logging.getLogger("SafetyBot").warning(msg)
            raise SystemExit(2)
        try:
            self.mt5_config = load_env(self.key_drive)

            missing = required_cfg_missing_fields()
            if missing:
                msg = "CRITICAL: Brak wymaganych pol konfiguracji: " + ", ".join(missing) + ". Uzupelnij CFG i uruchom bramki. SafetyBot nie startuje."
                print(msg)
                logging.getLogger("SafetyBot").error(msg)
                raise SystemExit(3)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            print("CRITICAL: Nie mozna wczytac TOKEN/BotKey.env. SafetyBot nie startuje.")
            raise SystemExit(2)
        meta = _safe_read_json(self.runtime_root / 'RELEASE_META.json')
        release_id = (str(meta.get('release_id')) if isinstance(meta, dict) and meta.get('release_id') else 'UNKNOWN')
        logging.info(f"Runtime root: {self.runtime_root}")
        ensure_db_ready(self.db_dir, self.backups_dir, release_id=release_id, log=logging.getLogger())
        self.limits.write_state()

        # --- time anchor ---
        global _TIME_ANCHOR
        _TIME_ANCHOR = TimeAnchor()
        self.time_anchor = _TIME_ANCHOR

        # --- MT5 client ---
        self.execution_engine = ExecutionEngine(self.mt5_config, self.gov, self.limits)
        self.execution_engine.incident_journal = self.incident_journal
        self.execution_queue = ExecutionQueue(self.execution_engine)
        self.execution_queue.start()
        self.throttle = OrderThrottle()

        # --- stores for Scout ---
        self.decision_store = DecisionEventStore(self.db_dir)
        self.bars_store = M5BarsStore(self.db_dir)
        self.tick_store = TickSnapshotsStore(self.db_dir)
        self.execution_engine.bars_store = self.bars_store
        self.execution_engine.tick_store = self.tick_store
        self._zmq_m5_feature_cache: Dict[str, Dict[str, Any]] = {}
        self._zmq_symbol_info_cache: Dict[str, Dict[str, Any]] = {}
        self._zmq_account_cache: Dict[str, Any] = {}
        self._zmq_last_tick_ts: Dict[str, float] = {}
        self._zmq_last_bar_ts: Dict[str, float] = {}
        self._micro_tick_state: Dict[str, Dict[str, Any]] = {}
        self.execution_engine._zmq_symbol_info_cache = self._zmq_symbol_info_cache
        self.execution_engine._zmq_account_cache = self._zmq_account_cache

        # --- strategy / controller ---
        self.ctrl = ActivityController(self.db, self.config)
        self.strategy = StandardStrategy(
            self.execution_engine,
            self.gov,
            self.throttle,
            self.db,
            self.config,
            self.risk_manager,
            order_queue=self.execution_queue,
            dispatch_order_hook=self._dispatch_order,
        )
        self.strategy.decision_store = self.decision_store
        self.strategy.zmq_feature_cache = self._zmq_m5_feature_cache
        self.strategy.execution_telemetry_hook = self._append_execution_telemetry
        self.resolved_symbols = {}
        # Cache of last known open positions; used by guard polling cadence.
        self._positions_cache: Dict[str, List] = {}
        # Cache of last known pending orders for dedicated reconcile loop.
        self._pending_cache: Dict[str, List] = {}
        # Last close-attempt timestamp per ticket for position time-stop retries.
        self._position_close_attempt_ts: Dict[int, int] = {}
        # Adaptive exit state.
        self._partial_tp_done_tickets: Dict[int, bool] = {}
        self._partial_close_attempt_ts: Dict[int, int] = {}
        self._trail_update_attempt_ts: Dict[int, int] = {}
        # Trade windows: last logged state (to avoid log spam).
        self._last_tw_phase: Optional[str] = None
        self._last_tw_window_id: Optional[str] = None
        self._last_tw_group: Optional[str] = None

        # --- connect + universe ---
        if not self.execution_engine.connect():
            logging.critical('Nie udało się połączyć z MT5. SafetyBot kończy pracę.')
            raise SystemExit(1)
        self.universe = self._build_universe()
        if not self.universe:
            logging.critical('Universe puste. SafetyBot kończy pracę.')
            raise SystemExit(1)
        self._seed_symbol_info_static_cache()
        self._seed_account_snapshot_cache()
        self._refresh_asia_preflight_evidence()

        # SafetyBot reads Scout outputs ONLY from local runtime (not from USB).
        snap_path = write_runtime_boot_snapshot(self.runtime_root, self.universe)
        if snap_path is not None:
            logging.info(f"RUNTIME_BOOT_SNAPSHOT path={snap_path}")
        self.usb_root = str(self.runtime_root)

        # prime server time anchor (1 tick request)
        self._prime_time_anchor()

        # paper trading mode
        self.is_paper = bool(CFG.paper_trading)
        if bool(getattr(self, "is_paper", True)):
            self.paper_start_ts = self.db.get_or_set_paper_start()
        else:
            self.paper_start_ts = 0.0
        self._refresh_live_canary_contract()
        _tw_init = trade_window_ctx(now_utc())
        self._refresh_no_live_drift_check(tw_ctx=_tw_init)
        self._refresh_cost_guard_auto_relax_state(tw_ctx=_tw_init)

    def _seed_symbol_info_static_cache(self) -> None:
        if mt5 is None:
            return
        seeded = 0
        now_ts = float(time.time())
        cache = self.execution_engine._symbol_info_static_cache
        for (_raw, canon, _grp) in (self.universe or []):
            if not canon:
                continue
            try:
                info = mt5.symbol_info(canon)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                info = None
            if info is None:
                continue
            base = symbol_base(canon)
            rec = {
                "recv_ts": float(now_ts),
                "seed_static": True,
                "point": float(getattr(info, "point", 0.0) or 0.0),
                "digits": int(getattr(info, "digits", 0) or 0),
                "spread": float(getattr(info, "spread", 0.0) or 0.0),
                "trade_tick_size": float(getattr(info, "trade_tick_size", 0.0) or 0.0),
                "trade_tick_value": float(getattr(info, "trade_tick_value", 0.0) or 0.0),
                "volume_min": float(getattr(info, "volume_min", 0.0) or 0.0),
                "volume_max": float(getattr(info, "volume_max", 0.0) or 0.0),
                "volume_step": float(getattr(info, "volume_step", 0.0) or 0.0),
                "trade_stops_level": int(getattr(info, "trade_stops_level", 0) or 0),
                "trade_freeze_level": int(getattr(info, "trade_freeze_level", 0) or 0),
            }
            cache[str(base)] = dict(rec)
            cache[str(canon).upper()] = dict(rec)
            seeded += 1
        if seeded > 0:
            logging.info("SYMBOL_INFO_STATIC_CACHE_SEEDED count=%s", int(seeded))

    def _seed_account_snapshot_cache(self) -> None:
        if mt5 is None:
            return
        try:
            info = mt5.account_info()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            info = None
        if info is None:
            return
        rec = {
            "recv_ts": float(time.time()),
            "seed_static": True,
            "balance": float(getattr(info, "balance", 0.0) or 0.0),
            "equity": float(getattr(info, "equity", 0.0) or 0.0),
            "margin_free": float(getattr(info, "margin_free", 0.0) or 0.0),
            "margin_level": float(getattr(info, "margin_level", 0.0) or 0.0),
        }
        self.execution_engine._account_info_static_cache.clear()
        self.execution_engine._account_info_static_cache.update(rec)
        logging.info("ACCOUNT_INFO_STATIC_CACHE_SEEDED")

    def _append_jsonl_record(self, path: Path, payload: Dict[str, Any]) -> None:
        io_t0 = time.perf_counter()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            line = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            with open(path, "a", encoding="utf-8", newline="\n") as f:
                f.write(line + "\n")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        finally:
            try:
                io_ms = int((time.perf_counter() - io_t0) * 1000.0)
                self._record_section_duration("io_log", io_ms)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _emit_unit_diagnostic(
        self,
        parameter_name: str,
        current_unit: str,
        expected_unit: str,
        risk_level: str,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        evt = {
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "event_type": "UNIT_MISMATCH_RISK" if str(current_unit).strip() else "AMBIGUOUS_UNIT",
            "parameter_name": str(parameter_name or ""),
            "current_unit": str(current_unit or "AMBIGUOUS_UNIT"),
            "expected_unit": str(expected_unit or "AMBIGUOUS_UNIT"),
            "risk_level": str(risk_level or "LOW").upper(),
            "source_provenance": "python.safetybot",
            "details": dict(details or {}),
        }
        logging.warning(
            "UNIT_DIAGNOSTIC event=%s parameter=%s current_unit=%s expected_unit=%s risk=%s details=%s",
            evt["event_type"],
            evt["parameter_name"],
            evt["current_unit"],
            evt["expected_unit"],
            evt["risk_level"],
            evt["details"],
        )
        telemetry_path = getattr(self, "execution_telemetry_path", None)
        if telemetry_path:
            self._append_jsonl_record(telemetry_path, evt)

    def _append_execution_telemetry(self, payload: Dict[str, Any]) -> None:
        rec = dict(payload or {})
        rec.setdefault("ts_utc", now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"))
        rec.setdefault("timestamp_semantics", "UTC")
        rec.setdefault("source_provenance", "python.safetybot")
        rec.setdefault("method", "event")
        rec.setdefault("sample_size_n", 1)
        rec.setdefault("low_stat_power", True)
        telemetry_path = getattr(self, "execution_telemetry_path", None)
        if telemetry_path:
            self._append_jsonl_record(telemetry_path, rec)

    def _stage1_live_meta_snapshot(self) -> Tuple[int, Dict[str, Any]]:
        with _STAGE1_LIVE_LOCK:
            loaded = int(len(_STAGE1_LIVE_OVERRIDES))
            meta = dict(_STAGE1_LIVE_META)
        return loaded, meta

    def _emit_stage1_live_loader_event(
        self,
        *,
        level: str,
        status: str,
        reason: str,
        details: Optional[Dict[str, Any]] = None,
    ) -> None:
        lvl = str(level or "INFO").strip().upper()
        st = str(status or "UNKNOWN").strip().upper() or "UNKNOWN"
        rs = str(reason or "NONE").strip().upper() or "NONE"
        loaded_symbols, meta = self._stage1_live_meta_snapshot()
        evt = {
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "event_type": "STAGE1_LIVE_LOADER",
            "status": st,
            "reason": rs,
            "enabled": bool(self.stage1_live_config_enabled),
            "config_path": str(self.stage1_live_config_path),
            "loaded_symbols": int(loaded_symbols),
            "last_loaded_symbols": int(self._stage1_live_last_loaded_symbols),
            "last_ok_utc": str(self._stage1_live_last_ok_utc or ""),
            "last_error": str(self._stage1_live_last_error or ""),
            "meta": meta,
            "details": dict(details or {}),
        }
        msg = (
            "STAGE1_LOADER status=%s reason=%s loaded_symbols=%s config=%s details=%s"
            % (st, rs, int(loaded_symbols), str(self.stage1_live_config_path), evt["details"])
        )
        if lvl == "ERROR":
            logging.error(msg)
        elif lvl == "WARNING":
            logging.warning(msg)
        else:
            logging.info(msg)
        if bool(self.stage1_live_audit_enabled):
            self._append_jsonl_record(self.stage1_live_audit_path, evt)

    def _write_stage1_live_loader_status(self, status: str, reason: str) -> None:
        loaded_symbols, meta = self._stage1_live_meta_snapshot()
        payload = {
            "schema_version": "stage1_live_loader_status_v1",
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "status": str(status or "UNKNOWN").strip().upper() or "UNKNOWN",
            "reason": str(reason or "NONE").strip().upper() or "NONE",
            "enabled": bool(self.stage1_live_config_enabled),
            "config_path": str(self.stage1_live_config_path),
            "reload_interval_sec": int(self.stage1_live_reload_interval_sec),
            "last_check_ts_epoch": float(self._stage1_live_last_check_ts or 0.0),
            "last_seen_mtime_ns": int(self._stage1_live_last_seen_mtime_ns),
            "last_loaded_mtime_ns": int(self._stage1_live_last_mtime_ns),
            "last_failed_mtime_ns": int(self._stage1_live_last_failed_mtime_ns),
            "last_ok_utc": str(self._stage1_live_last_ok_utc or ""),
            "last_error": str(self._stage1_live_last_error or ""),
            "last_loaded_symbols": int(self._stage1_live_last_loaded_symbols),
            "active_override_symbols": int(loaded_symbols),
            "meta": meta,
        }
        try:
            atomic_write_json(self.stage1_live_status_path, payload)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _reload_stage1_live_config(self, *, force: bool = False) -> None:
        now_ts = float(time.time())
        if not bool(self.stage1_live_config_enabled):
            if self._stage1_live_last_status != "DISABLED":
                self._stage1_live_last_status = "DISABLED"
                self._stage1_live_last_status_reason = "CONFIG_DISABLED"
                self._emit_stage1_live_loader_event(
                    level="INFO",
                    status="DISABLED",
                    reason="CONFIG_DISABLED",
                )
                self._write_stage1_live_loader_status("DISABLED", "CONFIG_DISABLED")
            return
        if (not force) and ((now_ts - float(self._stage1_live_last_check_ts or 0.0)) < float(self.stage1_live_reload_interval_sec)):
            return
        self._stage1_live_last_check_ts = now_ts

        try:
            st = self.stage1_live_config_path.stat()
            mtime_ns = int(st.st_mtime_ns)
        except FileNotFoundError:
            if self._stage1_live_last_status != "MISSING":
                self._stage1_live_last_status = "MISSING"
                self._stage1_live_last_status_reason = "CONFIG_FILE_MISSING"
                self._emit_stage1_live_loader_event(
                    level="WARNING",
                    status="MISSING",
                    reason="CONFIG_FILE_MISSING",
                    details={"fallback_mode": "KEEP_LAST_GOOD"},
                )
                self._write_stage1_live_loader_status("MISSING", "CONFIG_FILE_MISSING")
            return
        except Exception as e:
            reason = f"STAT_ERROR:{type(e).__name__}"
            self._stage1_live_last_error = reason
            if self._stage1_live_last_status_reason != reason:
                self._stage1_live_last_status = "ERROR"
                self._stage1_live_last_status_reason = reason
                self._emit_stage1_live_loader_event(
                    level="ERROR",
                    status="ERROR",
                    reason=reason,
                    details={"fallback_mode": "KEEP_LAST_GOOD"},
                )
                self._write_stage1_live_loader_status("ERROR", reason)
            return

        self._stage1_live_last_seen_mtime_ns = int(mtime_ns)
        if (not force) and int(mtime_ns) == int(self._stage1_live_last_mtime_ns):
            return
        if (not force) and int(mtime_ns) == int(self._stage1_live_last_failed_mtime_ns):
            return

        parse_t0 = time.perf_counter()
        try:
            raw = self.stage1_live_config_path.read_text(encoding="utf-8", errors="strict")
            payload = json.loads(raw)
            if not isinstance(payload, dict):
                raise ValueError("STAGE1_JSON_NOT_OBJECT")
            overrides, meta = _parse_stage1_live_config_payload(payload)
            _set_stage1_live_overrides(overrides, meta)
            self._stage1_live_last_mtime_ns = int(mtime_ns)
            self._stage1_live_last_failed_mtime_ns = -1
            self._stage1_live_last_loaded_symbols = int(len(overrides))
            self._stage1_live_last_error = ""
            self._stage1_live_last_ok_utc = now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")
            self._stage1_live_last_status = "OK"
            self._stage1_live_last_status_reason = "CONFIG_APPLIED"
            self._emit_stage1_live_loader_event(
                level="INFO",
                status="OK",
                reason="CONFIG_APPLIED",
                details={
                    "mtime_ns": int(mtime_ns),
                    "parse_ms": int((time.perf_counter() - parse_t0) * 1000.0),
                    "loaded_symbols": int(len(overrides)),
                    "deployment_id": str(meta.get("deployment_id") or ""),
                    "config_hash": str(meta.get("config_hash") or ""),
                },
            )
            self._write_stage1_live_loader_status("OK", "CONFIG_APPLIED")
        except Exception as e:
            self._stage1_live_last_failed_mtime_ns = int(mtime_ns)
            self._stage1_live_last_error = f"{type(e).__name__}:{e}"
            reason = f"PARSE_ERROR:{type(e).__name__}"
            self._stage1_live_last_status = "ERROR"
            self._stage1_live_last_status_reason = reason
            self._emit_stage1_live_loader_event(
                level="ERROR",
                status="ERROR",
                reason=reason,
                details={
                    "mtime_ns": int(mtime_ns),
                    "error": str(e),
                    "fallback_mode": "KEEP_LAST_GOOD",
                },
            )
            self._write_stage1_live_loader_status("ERROR", reason)

    def _refresh_asia_preflight_evidence(self) -> None:
        """Build deterministic symbol-preflight artifact for Asia shadow rollout decisions."""
        intents_cfg = getattr(CFG, "asia_wave1_symbol_intents", ("USDJPY", "EURJPY", "AUDJPY", "NZDJPY", "JP225", "GOLD"))
        intents: List[str] = []
        seen_intents: Set[str] = set()
        for raw_intent in (intents_cfg or ()):
            key = str(raw_intent or "").strip().upper()
            if key and key not in seen_intents:
                seen_intents.add(key)
                intents.append(key)
        rows: List[Dict[str, Any]] = []
        gate: Dict[str, bool] = {}
        targets: Set[str] = set()
        for intent in intents:
            canon = self.resolve_canon_symbol(intent)
            canon_norm = canonical_symbol(canon or "")
            if canon_norm:
                targets.add(canon_norm)
            exists = bool(canon)
            selected = False
            visible = False
            tradable = "UNKNOWN"
            select_attempted = False
            select_result = "UNKNOWN"
            fail_reason = ""
            info = None
            if exists and mt5 is not None:
                try:
                    info = mt5.symbol_info(canon)
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    info = None
                if info is None:
                    try:
                        select_attempted = True
                        select_result = "OK" if bool(mt5.symbol_select(canon, True)) else "FAIL"
                        info = mt5.symbol_info(canon)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        select_result = "EXCEPTION"
                        info = None
            if info is not None:
                try:
                    selected = bool(getattr(info, "select", False))
                except Exception:
                    selected = False
                try:
                    visible = bool(getattr(info, "visible", False))
                except Exception:
                    visible = False
                try:
                    tradable = _trade_mode_name(int(getattr(info, "trade_mode", -1)))
                except Exception:
                    tradable = "UNKNOWN"
            else:
                if not exists:
                    fail_reason = "SYMBOL_NOT_RESOLVED"
                elif select_attempted and select_result != "OK":
                    fail_reason = "SYMBOL_SELECT_FAIL"
                else:
                    fail_reason = "SYMBOL_INFO_UNAVAILABLE"
            preflight_ok = bool(exists and selected and visible and tradable in ("FULL", "LONGONLY", "SHORTONLY"))
            if canon_norm:
                gate[canon_norm] = preflight_ok
            rows.append(
                {
                    "alias_intent": intent,
                    "raw_symbol": intent,
                    "canonical_symbol": canon or "",
                    "canonical_symbol_norm": canon_norm or "",
                    "exists": bool(exists),
                    "selected": bool(selected),
                    "visible": bool(visible),
                    "tradable": str(tradable),
                    "session_info_available": "UNKNOWN",
                    "symbol_select_attempted": bool(select_attempted),
                    "symbol_select_result": str(select_result),
                    "preflight_ok": bool(preflight_ok),
                    "fail_reason": fail_reason or "",
                    "source": ("RUNTIME_MT5" if mt5 is not None else "UNKNOWN"),
                    "confidence": ("HIGH" if info is not None else ("MED" if exists else "LOW")),
                }
            )
        report = {
            "schema_version": "2R.A1",
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "timezone_basis": "UTC",
            "window_basis": "N/A",
            "source_list": ["python.runtime.mt5_symbol_info" if mt5 is not None else "UNKNOWN"],
            "method": "startup_preflight",
            "sample_size_n": int(len(rows)),
            "low_stat_power": bool(len(rows) < 5),
            "rows": rows,
        }
        self._asia_shadow_symbol_gate = gate
        self._asia_shadow_symbol_targets = targets
        try:
            if hasattr(self, "strategy") and self.strategy is not None:
                self.strategy._asia_shadow_symbol_gate = dict(gate)
                self.strategy._asia_shadow_symbol_targets = set(targets)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        try:
            atomic_write_json(self.asia_preflight_path, report)
            logging.info("ASIA_PREFLIGHT_EVIDENCE path=%s symbols=%s", self.asia_preflight_path, int(len(rows)))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _resolve_intents_to_canonical(self, intents: Tuple[str, ...]) -> Set[str]:
        out: Set[str] = set()
        for raw in (intents or ()):
            intent = str(raw or "").strip().upper()
            if not intent:
                continue
            canon = self.resolve_canon_symbol(intent)
            if canon:
                out.add(canonical_symbol(canon))
            else:
                out.add(canonical_symbol(intent))
        return out

    def _refresh_live_canary_contract(self) -> None:
        groups = {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}
        module_map_raw = dict(getattr(CFG, "module_live_enabled_map", {}) or {})
        module_map: Dict[str, bool] = {}
        for g in sorted(groups):
            module_map[g] = bool(module_map_raw.get(g, False))

        allowed_groups = {
            _group_key(str(g))
            for g in (getattr(CFG, "live_canary_allowed_groups", ()) or ())
            if str(g).strip()
        }
        hard_groups = {
            _group_key(str(g))
            for g in (getattr(CFG, "hard_live_disabled_groups", ()) or ())
            if str(g).strip()
        }
        self._live_canary_allowed_symbols = self._resolve_intents_to_canonical(
            tuple(getattr(CFG, "live_canary_allowed_symbol_intents", ()) or ())
        )
        self._hard_live_disabled_symbols = self._resolve_intents_to_canonical(
            tuple(getattr(CFG, "hard_live_disabled_symbol_intents", ()) or ())
        )

        rows: List[Dict[str, Any]] = []
        universe_rows = list(getattr(self, "universe", []) or [])
        for raw, sym, grp in universe_rows:
            grp_u = _group_key(grp)
            sym_canon = canonical_symbol(sym)
            module_live_enabled = bool(module_map.get(grp_u, False))
            symbol_live_enabled = True
            reason = "NONE"
            if not bool(getattr(CFG, "live_canary_enabled", False)):
                symbol_live_enabled = False
                reason = "LIVE_CANARY_DISABLED"
            elif grp_u in hard_groups:
                symbol_live_enabled = False
                reason = "HARD_LIVE_DISABLED_GROUP"
            elif sym_canon in self._hard_live_disabled_symbols:
                symbol_live_enabled = False
                reason = "HARD_LIVE_DISABLED_SYMBOL"
            elif grp_u not in allowed_groups:
                symbol_live_enabled = False
                reason = "GROUP_NOT_IN_WAVE1"
            elif not module_live_enabled:
                symbol_live_enabled = False
                reason = "MODULE_LIVE_DISABLED"
            elif self._live_canary_allowed_symbols and sym_canon not in self._live_canary_allowed_symbols:
                symbol_live_enabled = False
                reason = "SYMBOL_NOT_IN_WAVE1"
            elif (
                sym_canon in self._asia_shadow_symbol_targets
                and (not bool(self._asia_shadow_symbol_gate.get(sym_canon, False)))
            ):
                symbol_live_enabled = False
                reason = "ASIA_PREFLIGHT_BLOCK"
            rows.append(
                {
                    "symbol_raw": str(sym),
                    "symbol_canonical": sym_canon,
                    "group": grp_u,
                    "module_live_enabled": bool(module_live_enabled),
                    "symbol_live_enabled": bool(symbol_live_enabled),
                    "hard_live_disabled_reason": str(reason),
                }
            )

        payload = {
            "schema_version": "HL.A1",
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "live_canary_enabled": bool(getattr(CFG, "live_canary_enabled", False)),
            "module_live_enabled_map": module_map,
            "live_canary_allowed_groups": sorted(allowed_groups),
            "live_canary_allowed_symbols": sorted(self._live_canary_allowed_symbols),
            "hard_live_disabled_groups": sorted(hard_groups),
            "hard_live_disabled_symbols": sorted(self._hard_live_disabled_symbols),
            "jpy_basket_symbol_set": sorted(
                self._resolve_intents_to_canonical(tuple(getattr(CFG, "jpy_basket_symbol_intents", ()) or ()))
            ),
            "jpy_basket_selection_mode": str(getattr(CFG, "jpy_basket_selection_mode", "TOP_1")),
            "jpy_basket_ranking_basis_for_top_k": str(getattr(CFG, "jpy_basket_ranking_basis_for_top_k", "")),
            "rows": rows,
            "calibration_status": {
                "module_live_enabled_map": "HYPOTHESIS_DEFAULT",
                "live_canary_allowed_symbols": "CALIBRATED",
                "hard_live_disabled_symbols": "HYPOTHESIS_DEFAULT",
            },
        }
        self._live_guard_snapshot = payload
        try:
            atomic_write_json(self.live_canary_contract_path, payload)
            logging.info(
                "LIVE_CANARY_CONTRACT path=%s enabled=%s rows=%s",
                str(self.live_canary_contract_path),
                int(bool(payload.get("live_canary_enabled"))),
                int(len(rows)),
            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _live_entry_contract(self, symbol: str, group: str) -> Dict[str, Any]:
        grp_u = _group_key(group)
        sym_canon = canonical_symbol(symbol)
        module_map = dict(getattr(CFG, "module_live_enabled_map", {}) or {})
        live_module_states = dict(getattr(self, "_live_module_states", {}) or {})
        live_module_state_reasons = dict(getattr(self, "_live_module_state_reasons", {}) or {})
        hard_live_disabled_symbols = set(getattr(self, "_hard_live_disabled_symbols", set()) or set())
        live_canary_allowed_symbols = set(getattr(self, "_live_canary_allowed_symbols", set()) or set())
        allowed_groups = {
            _group_key(str(g))
            for g in (getattr(CFG, "live_canary_allowed_groups", ()) or ())
            if str(g).strip()
        }
        hard_groups = {
            _group_key(str(g))
            for g in (getattr(CFG, "hard_live_disabled_groups", ()) or ())
            if str(g).strip()
        }
        state = str(live_module_states.get(grp_u, "NORMAL")).upper()
        reasons = list(live_module_state_reasons.get(grp_u, []) or [])
        if bool(getattr(self, "is_paper", True)):
            return {
                "entry_allowed": True,
                "reason_code": "PAPER_MODE",
                "module_live_enabled": True,
                "symbol_live_enabled": True,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if not bool(getattr(CFG, "live_canary_enabled", False)):
            return {
                "entry_allowed": False,
                "reason_code": "LIVE_CANARY_DISABLED",
                "module_live_enabled": False,
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if grp_u in hard_groups:
            return {
                "entry_allowed": False,
                "reason_code": "HARD_LIVE_DISABLED_GROUP",
                "module_live_enabled": False,
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if sym_canon in hard_live_disabled_symbols:
            return {
                "entry_allowed": False,
                "reason_code": "HARD_LIVE_DISABLED_SYMBOL",
                "module_live_enabled": bool(module_map.get(grp_u, False)),
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        module_live_enabled = bool(module_map.get(grp_u, False))
        if (allowed_groups and grp_u not in allowed_groups) or (not module_live_enabled):
            return {
                "entry_allowed": False,
                "reason_code": ("GROUP_NOT_IN_WAVE1" if allowed_groups and grp_u not in allowed_groups else "MODULE_LIVE_DISABLED"),
                "module_live_enabled": bool(module_live_enabled),
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if live_canary_allowed_symbols and sym_canon not in live_canary_allowed_symbols:
            return {
                "entry_allowed": False,
                "reason_code": "SYMBOL_NOT_IN_WAVE1",
                "module_live_enabled": bool(module_live_enabled),
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if (
            sym_canon in self._asia_shadow_symbol_targets
            and (not bool(self._asia_shadow_symbol_gate.get(sym_canon, False)))
        ):
            return {
                "entry_allowed": False,
                "reason_code": "ASIA_PREFLIGHT_BLOCK",
                "module_live_enabled": bool(module_live_enabled),
                "symbol_live_enabled": False,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        if state in {"OFF", "RESTRICTED"}:
            return {
                "entry_allowed": False,
                "reason_code": f"MODULE_STATE_{state}",
                "module_live_enabled": bool(module_live_enabled),
                "symbol_live_enabled": True,
                "module_state": state,
                "module_state_reasons": reasons,
                "symbol_canonical": sym_canon,
            }
        return {
            "entry_allowed": True,
            "reason_code": "NONE",
            "module_live_enabled": bool(module_live_enabled),
            "symbol_live_enabled": True,
            "module_state": state,
            "module_state_reasons": reasons,
            "symbol_canonical": sym_canon,
        }

    def _session_liquidity_gate_eval(
        self,
        symbol: str,
        group: str,
        request: Dict[str, Any],
        *,
        tw_ctx: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        grp_u = _group_key(group)
        mode = str(getattr(CFG, "session_liquidity_gate_mode", "SHADOW_ONLY") or "SHADOW_ONLY").strip().upper()
        if mode not in {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}:
            mode = "SHADOW_ONLY"
        cfg = SessionLiquidityGateConfig(
            enabled=bool(getattr(CFG, "session_liquidity_gate_enabled", True)),
            mode=mode,
            block_on_missing_snapshot=bool(getattr(CFG, "session_liquidity_block_on_missing_snapshot", True)),
        )
        tw = dict(tw_ctx or trade_window_ctx(now_utc()) or {})
        tw_phase = str(tw.get("phase") or "UNKNOWN").upper()
        tw_window_id = str(tw.get("window_id") or "NONE")
        tw_group = _group_key(str(tw.get("group") or ""))

        base = symbol_base(symbol)
        snapshot = {}
        try:
            snapshot = dict(self._zmq_symbol_info_cache.get(base) or {})
        except Exception:
            snapshot = {}

        spread_points: Optional[float] = None
        for candidate in (
            request.get("spread_points"),
            request.get("spread_at_decision"),
            snapshot.get("spread"),
        ):
            try:
                v = float(candidate)
                if v >= 0.0:
                    spread_points = float(v)
                    break
            except Exception:
                continue

        tick_age_sec: Optional[float] = None
        try:
            t_tick = float(self._zmq_last_tick_ts.get(base, 0.0) or 0.0)
            if t_tick <= 0.0:
                t_tick = float(snapshot.get("recv_ts", 0.0) or 0.0)
            if t_tick > 0.0:
                tick_age_sec = max(0.0, float(time.time()) - float(t_tick))
        except Exception:
            tick_age_sec = None

        caution_default = float(
            _cfg_group_map_float("session_liquidity_spread_caution_by_group", grp_u, 24.0)
        )
        block_default = float(
            _cfg_group_map_float("session_liquidity_spread_block_by_group", grp_u, caution_default * 1.25)
        )
        tick_age_default = float(
            _cfg_group_map_float("session_liquidity_max_tick_age_sec_by_group", grp_u, 8.0)
        )
        spread_caution_points = float(
            max(
                0.0,
                _cfg_group_float(
                    grp_u,
                    "session_liquidity_spread_caution_points",
                    caution_default,
                    symbol=symbol,
                ),
            )
        )
        spread_block_points = float(
            max(
                spread_caution_points,
                _cfg_group_float(
                    grp_u,
                    "session_liquidity_spread_block_points",
                    block_default,
                    symbol=symbol,
                ),
            )
        )
        max_tick_age_sec = float(
            max(
                0.1,
                _cfg_group_float(
                    grp_u,
                    "session_liquidity_max_tick_age_sec",
                    tick_age_default,
                    symbol=symbol,
                ),
            )
        )

        inp = SessionLiquidityGateInput(
            group=grp_u,
            symbol=str(symbol),
            trade_window_phase=str(tw_phase),
            trade_window_id=str(tw_window_id),
            trade_window_group=str(tw_group),
            strict_group_routing=bool(getattr(CFG, "trade_window_strict_group_routing", True)),
            spread_points=spread_points,
            tick_age_sec=tick_age_sec,
            max_tick_age_sec=max_tick_age_sec,
            spread_caution_points=spread_caution_points,
            spread_block_points=spread_block_points,
        )
        decision = dict(evaluate_session_liquidity_gate(cfg, inp))
        decision.update(
            {
                "symbol_raw": str(symbol),
                "symbol_canonical": canonical_symbol(symbol),
                "group": str(grp_u),
                "trade_window_phase": str(tw_phase),
                "trade_window_id": str(tw_window_id),
                "trade_window_group": str(tw_group),
                "spread_points": spread_points,
                "tick_age_sec": tick_age_sec,
                "max_tick_age_sec": float(max_tick_age_sec),
                "spread_caution_points": float(spread_caution_points),
                "spread_block_points": float(spread_block_points),
            }
        )
        return decision

    def _cost_microstructure_gate_eval(self, symbol: str, group: str, request: Dict[str, Any]) -> Dict[str, Any]:
        grp_u = _group_key(group)
        mode = str(getattr(CFG, "cost_microstructure_gate_mode", "SHADOW_ONLY") or "SHADOW_ONLY").strip().upper()
        if mode not in {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}:
            mode = "SHADOW_ONLY"
        cfg = CostMicrostructureGateConfig(
            enabled=bool(getattr(CFG, "cost_microstructure_gate_enabled", True)),
            mode=mode,
            block_on_missing_snapshot=bool(getattr(CFG, "cost_microstructure_block_on_missing_snapshot", True)),
            block_on_unknown_quality=bool(getattr(CFG, "cost_microstructure_block_on_unknown_quality", True)),
            min_target_to_cost_ratio=float(max(0.0, getattr(CFG, "cost_gate_min_target_to_cost_ratio", 1.10))),
        )

        base = symbol_base(symbol)
        snapshot = {}
        try:
            snapshot = dict(self._zmq_symbol_info_cache.get(base) or {})
        except Exception:
            snapshot = {}
        micro_state = {}
        try:
            micro_state = dict(self._micro_tick_state.get(base) or {})
        except Exception:
            micro_state = {}

        spread_points: Optional[float] = None
        for candidate in (
            request.get("spread_points"),
            request.get("spread_at_decision"),
            snapshot.get("spread"),
        ):
            try:
                v = float(candidate)
                if v >= 0.0:
                    spread_points = float(v)
                    break
            except Exception:
                continue

        tick_age_sec: Optional[float] = None
        try:
            t_tick = float(self._zmq_last_tick_ts.get(base, 0.0) or 0.0)
            if t_tick <= 0.0:
                t_tick = float(snapshot.get("recv_ts", 0.0) or 0.0)
            if t_tick > 0.0:
                tick_age_sec = max(0.0, float(time.time()) - float(t_tick))
        except Exception:
            tick_age_sec = None

        spread_caution = float(
            max(
                0.0,
                _cfg_group_float(
                    grp_u,
                    "cost_microstructure_spread_caution_points",
                    _cfg_group_map_float("cost_microstructure_spread_caution_by_group", grp_u, 22.0),
                    symbol=symbol,
                ),
            )
        )
        spread_block = float(
            max(
                spread_caution,
                _cfg_group_float(
                    grp_u,
                    "cost_microstructure_spread_block_points",
                    _cfg_group_map_float("cost_microstructure_spread_block_by_group", grp_u, spread_caution * 1.25),
                    symbol=symbol,
                ),
            )
        )
        max_tick_age_sec = float(
            max(
                0.1,
                _cfg_group_float(
                    grp_u,
                    "cost_microstructure_max_tick_age_sec",
                    _cfg_group_map_float("cost_microstructure_max_tick_age_sec_by_group", grp_u, 6.0),
                    symbol=symbol,
                ),
            )
        )
        gap_block_sec = float(
            max(
                0.1,
                _cfg_group_float(
                    grp_u,
                    "cost_microstructure_gap_block_sec",
                    _cfg_group_map_float("cost_microstructure_gap_block_sec_by_group", grp_u, 20.0),
                    symbol=symbol,
                ),
            )
        )
        jump_block_points = float(
            max(
                0.0,
                _cfg_group_float(
                    grp_u,
                    "cost_microstructure_jump_block_points",
                    _cfg_group_map_float("cost_microstructure_jump_block_points_by_group", grp_u, 80.0),
                    symbol=symbol,
                ),
            )
        )

        est_rt = request.get("estimated_round_trip_cost") if isinstance(request.get("estimated_round_trip_cost"), dict) else {}
        est_comp = request.get("estimated_entry_cost_components") if isinstance(request.get("estimated_entry_cost_components"), dict) else {}
        quality = str(
            est_comp.get("cost_estimation_quality")
            or est_rt.get("cost_estimation_quality")
            or "UNKNOWN"
        ).upper()

        inp = CostMicrostructureGateInput(
            group=grp_u,
            symbol=str(symbol),
            spread_points=spread_points,
            spread_caution_points=spread_caution,
            spread_block_points=spread_block,
            tick_age_sec=tick_age_sec,
            max_tick_age_sec=max_tick_age_sec,
            tick_gap_sec=(
                None
                if micro_state.get("tick_gap_sec") is None
                else float(max(0.0, float(micro_state.get("tick_gap_sec") or 0.0)))
            ),
            gap_block_sec=gap_block_sec,
            price_jump_points=(
                None
                if micro_state.get("price_jump_points") is None
                else float(max(0.0, float(micro_state.get("price_jump_points") or 0.0)))
            ),
            jump_block_points=jump_block_points,
            ask_lt_bid=bool(micro_state.get("ask_lt_bid", False)),
            cost_estimation_quality=quality,
            cost_feasibility_shadow=request.get("cost_feasibility_shadow"),
            target_move_price=request.get("target_move_price"),
            estimated_round_trip_cost_price=(
                est_rt.get("value_price")
                if isinstance(est_rt, dict)
                else None
            ),
        )
        decision = dict(evaluate_cost_microstructure_gate(cfg, inp))
        decision.update(
            {
                "symbol_raw": str(symbol),
                "symbol_canonical": canonical_symbol(symbol),
                "group": str(grp_u),
                "spread_points": spread_points,
                "tick_age_sec": tick_age_sec,
                "max_tick_age_sec": float(max_tick_age_sec),
                "tick_gap_sec": inp.tick_gap_sec,
                "gap_block_sec": float(gap_block_sec),
                "price_jump_points": inp.price_jump_points,
                "jump_block_points": float(jump_block_points),
                "ask_lt_bid": bool(inp.ask_lt_bid),
                "tick_rate_1s": micro_state.get("tick_rate_1s"),
                "spread_roll_mean_points": micro_state.get("spread_roll_mean_points"),
                "spread_roll_p95_points": micro_state.get("spread_roll_p95_points"),
                "stale_tick_flag": bool(micro_state.get("stale_tick_flag", False)),
                "burst_flag": bool(micro_state.get("burst_flag", False)),
                "quality_flags": str(micro_state.get("quality_flags") or "UNKNOWN"),
                "spread_caution_points": float(spread_caution),
                "spread_block_points": float(spread_block),
                "cost_estimation_quality": str(quality),
            }
        )
        return decision

    def _window_start_utc(self, tw_ctx: Dict[str, Any], now_dt: dt.datetime) -> int:
        phase = str(tw_ctx.get("phase") or "OFF").upper()
        wid = str(tw_ctx.get("window_id") or "")
        if phase not in {"ACTIVE", "CLOSEOUT"} or not wid:
            return int(pl_day_start_utc_ts(now_dt))
        tw = getattr(CFG, "trade_windows", {}) or {}
        w = tw.get(wid) if isinstance(tw, dict) else None
        if not isinstance(w, dict):
            return int(pl_day_start_utc_ts(now_dt))
        try:
            tz = ZoneInfo(str(w.get("anchor_tz") or "Europe/Warsaw"))
        except Exception:
            tz = TZ_PL
        local_now = now_dt.astimezone(tz)
        start_hm = tuple(w.get("start_hm") or (0, 0))
        end_hm = tuple(w.get("end_hm") or (0, 0))
        s_h, s_m = int(start_hm[0]), int(start_hm[1])
        e_h, e_m = int(end_hm[0]), int(end_hm[1])
        start_local = local_now.replace(hour=s_h, minute=s_m, second=0, microsecond=0)
        if (e_h, e_m) < (s_h, s_m) and (local_now.hour, local_now.minute) < (s_h, s_m):
            start_local = start_local - dt.timedelta(days=1)
        return int(start_local.astimezone(UTC).timestamp())

    def _pnl_net_since_ts_group(self, start_ts: int, group: str) -> float:
        grp = _group_key(group)
        try:
            cur = self.db.conn.cursor()
            cur.execute(
                """SELECT COALESCE(SUM(profit + commission + swap), 0.0)
                   FROM deals_log WHERE time >= ? AND grp = ?""",
                (int(start_ts), str(grp)),
            )
            row = cur.fetchone()
            return float(row[0] or 0.0) if row else 0.0
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0.0

    def _loss_streak_group(self, group: str, limit: int = 64) -> int:
        grp = _group_key(group)
        try:
            cur = self.db.conn.cursor()
            cur.execute(
                """SELECT (profit + commission + swap) AS pnl_net
                   FROM deals_log WHERE grp = ?
                   ORDER BY time DESC LIMIT ?""",
                (str(grp), int(max(1, limit))),
            )
            rows = cur.fetchall()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            rows = []
        streak = 0
        for row in rows:
            try:
                pnl = float(row[0] or 0.0)
            except Exception:
                pnl = 0.0
            if pnl < 0.0:
                streak += 1
            else:
                break
        return int(streak)

    def _count_ipc_failures_since(self, start_ts_utc: int, tail_lines: int = 4000) -> int:
        path = self.logs_dir / "audit_trail.jsonl"
        if not path.exists():
            return 0
        failure_events = {
            "COMMAND_TIMEOUT",
            "COMMAND_SEND_TIMEOUT",
            "COMMAND_FAILED",
            "REPLY_INVALID_JSON",
            "REPLY_REQUEST_HASH_MISMATCH",
            "REPLY_RESPONSE_HASH_MISMATCH",
        }
        count = 0
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            return 0
        for ln in lines[-int(max(1, tail_lines)) :]:
            try:
                obj = json.loads(str(ln or "{}"))
                ts_raw = str(obj.get("timestamp_utc") or "")
                ts = 0
                if ts_raw:
                    ts = int(dt.datetime.fromisoformat(ts_raw.replace("Z", "+00:00")).timestamp())
                if ts and ts < int(start_ts_utc):
                    continue
                evt = str(obj.get("event_type_norm") or obj.get("event_type") or "").strip().upper()
                if evt in failure_events:
                    count += 1
            except Exception:
                continue
        return int(count)

    def _count_execution_telemetry_events_since(
        self,
        start_ts_utc: int,
        *,
        event_type: str,
        reason_code: str = "",
        symbol_set: Optional[Set[str]] = None,
        tail_lines: int = 6000,
    ) -> int:
        path = self.execution_telemetry_path
        if not path.exists():
            return 0
        evt = str(event_type or "").strip().upper()
        reason = str(reason_code or "").strip().upper()
        symbols_norm = {canonical_symbol(s) for s in (symbol_set or set()) if str(s).strip()}
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except Exception:
            return 0
        count = 0
        for ln in lines[-int(max(1, tail_lines)) :]:
            try:
                obj = json.loads(str(ln or "{}"))
            except Exception:
                continue
            ts = _parse_iso_utc(str(obj.get("ts_utc") or ""))
            if ts is None or int(ts.timestamp()) < int(start_ts_utc):
                continue
            if str(obj.get("event_type") or "").strip().upper() != evt:
                continue
            if reason and str(obj.get("reason_code") or "").strip().upper() != reason:
                continue
            if symbols_norm:
                sym = canonical_symbol(str(obj.get("symbol_canonical") or obj.get("symbol_raw") or ""))
                if sym not in symbols_norm:
                    continue
            count += 1
        return int(count)

    def _count_decision_events_since(
        self,
        start_ts_utc: int,
        *,
        intents: Optional[Set[str]] = None,
    ) -> int:
        start_iso = dt.datetime.fromtimestamp(int(start_ts_utc), tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
        sql = "SELECT COUNT(*) FROM decision_events WHERE ts_utc >= ?"
        params: List[Any] = [str(start_iso)]
        intents_u = {str(x).strip().upper() for x in (intents or set()) if str(x).strip()}
        if intents_u:
            placeholders = ",".join(["?"] * len(intents_u))
            sql += f" AND UPPER(COALESCE(choice_A,'')) IN ({placeholders})"
            params.extend(sorted(intents_u))
        try:
            cur = self.db.conn.cursor()
            cur.execute(sql, tuple(params))
            row = cur.fetchone()
            return int(row[0] or 0) if row else 0
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return 0

    def _refresh_cost_guard_auto_relax_state(self, tw_ctx: Optional[Dict[str, Any]] = None) -> None:
        now_dt = now_utc()
        window_min = int(max(30, getattr(CFG, "cost_guard_auto_relax_window_minutes", 360)))
        start_ts = int((now_dt - dt.timedelta(minutes=window_min)).timestamp())
        enabled = bool(getattr(CFG, "cost_guard_auto_relax_enabled", False))
        base_block_unknown = bool(getattr(CFG, "cost_gate_block_on_unknown_quality", True))
        base_min_ratio = float(max(0.0, getattr(CFG, "cost_gate_min_target_to_cost_ratio", 1.10)))
        relaxed_block_unknown = bool(getattr(CFG, "cost_guard_auto_relax_block_on_unknown_quality", False))
        relaxed_min_ratio = float(max(0.0, getattr(CFG, "cost_guard_auto_relax_relaxed_min_ratio", base_min_ratio)))

        allowed_symbols = set(self._live_canary_allowed_symbols or set())
        if not allowed_symbols:
            allowed_symbols = self._resolve_intents_to_canonical(
                tuple(getattr(CFG, "live_canary_allowed_symbol_intents", ()) or ())
            )
        allowed_intents = {
            str(x).strip().upper()
            for x in (getattr(CFG, "live_canary_allowed_symbol_intents", ()) or ())
            if str(x).strip()
        }

        decision_total = self._count_decision_events_since(start_ts)
        decision_wave1 = self._count_decision_events_since(start_ts, intents=allowed_intents)
        unknown_blocks = self._count_execution_telemetry_events_since(
            start_ts,
            event_type="ENTRY_BLOCK_COST",
            reason_code="BLOCK_TRADE_COST_UNKNOWN",
            symbol_set=allowed_symbols,
        )
        incident_counts = (
            self.incident_journal.recent_counts(lookback_sec=max(60, window_min * 60))
            if self.incident_journal
            else {}
        )
        critical = int((incident_counts or {}).get("critical", 0) or 0)
        err_worse = int((incident_counts or {}).get("error_or_worse", 0) or 0)

        min_total = int(max(1, getattr(CFG, "cost_guard_auto_relax_min_total_decisions", 220)))
        min_wave1 = int(max(1, getattr(CFG, "cost_guard_auto_relax_min_wave1_decisions", 24)))
        min_unknown = int(max(1, getattr(CFG, "cost_guard_auto_relax_min_unknown_blocks", 20)))
        max_critical = int(max(0, getattr(CFG, "cost_guard_auto_relax_max_critical_incidents", 0)))
        max_errors = int(max(0, getattr(CFG, "cost_guard_auto_relax_max_error_incidents", 4)))

        hysteresis_enabled = bool(getattr(CFG, "cost_guard_auto_relax_hysteresis_enabled", True))
        min_total_off = derive_off_threshold(
            min_total,
            float(getattr(CFG, "cost_guard_auto_relax_hysteresis_total_ratio", 0.85)),
        )
        min_wave1_off = derive_off_threshold(
            min_wave1,
            float(getattr(CFG, "cost_guard_auto_relax_hysteresis_wave1_ratio", 0.85)),
        )
        min_unknown_off = derive_off_threshold(
            min_unknown,
            float(getattr(CFG, "cost_guard_auto_relax_hysteresis_unknown_ratio", 0.85)),
        )

        prev = dict(self._cost_guard_auto_relax_state or {})
        prev_active = bool(prev.get("active", False))

        eval_result = evaluate_cost_guard_state(
            prev_active=prev_active,
            enabled=enabled,
            metrics=CostGuardMetrics(
                decision_total=int(decision_total),
                decision_wave1=int(decision_wave1),
                unknown_blocks=int(unknown_blocks),
                critical_incidents=int(critical),
                error_or_worse_incidents=int(err_worse),
            ),
            thresholds=CostGuardThresholds(
                min_total_on=int(min_total),
                min_wave1_on=int(min_wave1),
                min_unknown_on=int(min_unknown),
                max_critical=int(max_critical),
                max_errors=int(max_errors),
                min_total_off=int(min_total_off),
                min_wave1_off=int(min_wave1_off),
                min_unknown_off=int(min_unknown_off),
            ),
            hysteresis_enabled=hysteresis_enabled,
        )
        active = bool(eval_result.get("active", False))
        reason = str(eval_result.get("reason") or "UNKNOWN")
        hysteresis_hold = bool(eval_result.get("hysteresis_hold", False))

        effective_block_unknown = base_block_unknown
        effective_min_ratio = base_min_ratio
        if active:
            effective_block_unknown = bool(relaxed_block_unknown)
            effective_min_ratio = float(min(base_min_ratio, relaxed_min_ratio))

        state_changed = bool(prev_active != bool(active))
        flap_window_min = int(max(5, getattr(CFG, "cost_guard_auto_relax_flap_window_minutes", 30)))
        flap_alert_threshold = int(max(2, getattr(CFG, "cost_guard_auto_relax_flap_alert_threshold", 4)))
        self._cost_guard_flap_transition_ts, flap_transition_count = update_transition_window(
            history_ts=self._cost_guard_flap_transition_ts,
            now_ts=now_dt.timestamp(),
            window_sec=int(max(60, flap_window_min * 60)),
            changed=state_changed,
        )
        flap_alert = bool(state_changed and flap_transition_count >= flap_alert_threshold)

        payload = {
            "schema_version": "COST_GUARD_RELAX.V1",
            "ts_utc": now_dt.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "window_minutes": int(window_min),
            "trade_window_phase": str((tw_ctx or {}).get("phase") or "UNKNOWN"),
            "trade_window_id": str((tw_ctx or {}).get("window_id") or "UNKNOWN"),
            "enabled": bool(enabled),
            "active": bool(active),
            "reason": str(reason),
            "hysteresis_hold": bool(hysteresis_hold),
            "thresholds": {
                "min_total_decisions": int(min_total),
                "min_wave1_decisions": int(min_wave1),
                "min_unknown_blocks": int(min_unknown),
                "min_total_decisions_off": int(min_total_off),
                "min_wave1_decisions_off": int(min_wave1_off),
                "min_unknown_blocks_off": int(min_unknown_off),
                "max_critical_incidents": int(max_critical),
                "max_error_incidents": int(max_errors),
                "base_min_ratio": float(base_min_ratio),
                "relaxed_min_ratio": float(relaxed_min_ratio),
                "base_block_on_unknown": bool(base_block_unknown),
                "relaxed_block_on_unknown": bool(relaxed_block_unknown),
                "hysteresis_enabled": bool(hysteresis_enabled),
                "flap_window_minutes": int(flap_window_min),
                "flap_alert_threshold": int(flap_alert_threshold),
            },
            "metrics": {
                "decision_total_window": int(decision_total),
                "decision_wave1_window": int(decision_wave1),
                "unknown_blocks_wave1_window": int(unknown_blocks),
                "incident_critical_window": int(critical),
                "incident_error_or_worse_window": int(err_worse),
                "flap_transitions_window": int(flap_transition_count),
            },
            "effective": {
                "cost_gate_block_on_unknown_quality": bool(effective_block_unknown),
                "cost_gate_min_target_to_cost_ratio": float(effective_min_ratio),
            },
        }
        self._cost_guard_auto_relax_state = payload
        try:
            atomic_write_json(self.cost_guard_auto_relax_path, payload)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        prev_reason = str(prev.get("reason") or "")
        prev_block = bool(prev.get("effective_block_on_unknown_quality", prev.get("effective", {}).get("cost_gate_block_on_unknown_quality", base_block_unknown))) if isinstance(prev, dict) else base_block_unknown
        prev_ratio = float(prev.get("effective_min_ratio", prev.get("effective", {}).get("cost_gate_min_target_to_cost_ratio", base_min_ratio))) if isinstance(prev, dict) else base_min_ratio
        if (prev_active != bool(active)) or (prev_reason != str(reason)) or (prev_block != bool(effective_block_unknown)) or (abs(prev_ratio - float(effective_min_ratio)) > 1e-9):
            logging.warning(
                "COST_GUARD_AUTO_RELAX active=%s reason=%s decisions=%s wave1=%s unknown_blocks=%s incidents_error=%s incidents_critical=%s block_unknown=%s min_ratio=%.3f",
                int(bool(active)),
                str(reason),
                int(decision_total),
                int(decision_wave1),
                int(unknown_blocks),
                int(err_worse),
                int(critical),
                int(bool(effective_block_unknown)),
                float(effective_min_ratio),
            )
            self._append_execution_telemetry(
                {
                    "event_type": "COST_GUARD_AUTO_RELAX",
                    "active": bool(active),
                    "reason_code": str(reason),
                    "window_minutes": int(window_min),
                    "decision_total_window": int(decision_total),
                    "decision_wave1_window": int(decision_wave1),
                    "unknown_blocks_wave1_window": int(unknown_blocks),
                    "incident_error_or_worse_window": int(err_worse),
                    "incident_critical_window": int(critical),
                    "effective_block_on_unknown_quality": bool(effective_block_unknown),
                    "effective_min_ratio": float(effective_min_ratio),
                    "hysteresis_hold": bool(hysteresis_hold),
                    "flap_transitions_window": int(flap_transition_count),
                    "flap_window_minutes": int(flap_window_min),
                    "method": "cost_guard_auto_relax",
                    "sample_size_n": int(max(1, decision_wave1)),
                    "low_stat_power": bool(int(decision_wave1) < int(min_wave1)),
                }
            )
        if flap_alert:
            logging.error(
                "COST_GUARD_AUTO_RELAX_FLAP_ALERT transitions=%s threshold=%s window_min=%s active=%s reason=%s",
                int(flap_transition_count),
                int(flap_alert_threshold),
                int(flap_window_min),
                int(bool(active)),
                str(reason),
            )
            self._append_execution_telemetry(
                {
                    "event_type": "COST_GUARD_AUTO_RELAX_FLAP_ALERT",
                    "active": bool(active),
                    "reason_code": str(reason),
                    "transitions_window": int(flap_transition_count),
                    "threshold": int(flap_alert_threshold),
                    "window_minutes": int(flap_window_min),
                    "method": "cost_guard_auto_relax",
                    "sample_size_n": int(max(1, flap_transition_count)),
                    "low_stat_power": False,
                }
            )

    def _cost_gate_effective_params(self) -> Dict[str, Any]:
        state = dict(self._cost_guard_auto_relax_state or {})
        effective = state.get("effective", {}) if isinstance(state.get("effective"), dict) else {}
        block_unknown = bool(
            effective.get(
                "cost_gate_block_on_unknown_quality",
                state.get(
                    "effective_block_on_unknown_quality",
                    getattr(CFG, "cost_gate_block_on_unknown_quality", True),
                ),
            )
        )
        min_ratio = float(
            effective.get(
                "cost_gate_min_target_to_cost_ratio",
                state.get(
                    "effective_min_ratio",
                    getattr(CFG, "cost_gate_min_target_to_cost_ratio", 1.10),
                ),
            )
        )
        return {
            "active": bool(state.get("active", False)),
            "reason": str(state.get("reason") or "UNKNOWN"),
            "block_unknown_quality": bool(block_unknown),
            "min_target_to_cost_ratio": float(max(0.0, min_ratio)),
        }

    def _refresh_live_module_states(self, tw_ctx: Dict[str, Any], st: Dict[str, Any]) -> None:
        groups = sorted({
            _group_key(str(g))
            for g in (getattr(CFG, "module_live_enabled_map", {}) or {}).keys()
            if str(g).strip()
        } or {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"})

        now_dt = now_utc()
        start_ts_pl = int(pl_day_start_utc_ts(now_dt))
        start_ts_window = int(self._window_start_utc(tw_ctx, now_dt))
        phase = str(tw_ctx.get("phase") or "OFF").upper()
        window_id = str(tw_ctx.get("window_id") or "OFF")
        window_key = f"{str(pl_day_key(now_dt))}:{phase}:{window_id}"

        if not self.is_paper:
            for g in groups:
                if str(self._live_window_keys.get(g, "")) != window_key:
                    self._live_window_keys[g] = str(window_key)
                    self._live_window_trade_counts[g] = 0

        acc = self.execution_engine.account_info()
        bal_now = float(getattr(acc, "balance", 0.0) or 0.0) if acc is not None else 0.0
        eq_now = float(getattr(acc, "equity", bal_now) or bal_now) if acc is not None else bal_now
        pnl_today = float(self.db.pnl_net_since_ts(int(start_ts_pl)))
        bal_start = float(bal_now - pnl_today)
        if bal_start <= 0.0:
            bal_start = float(max(1.0, bal_now))
        dd_pct = max(0.0, (float(bal_start) - float(eq_now)) / float(bal_start)) if bal_start > 0.0 else 0.0
        session_pnl = float(self.db.pnl_net_since_ts(int(start_ts_window)))

        exec_metrics = self.execution_engine.metrics_snapshot()
        retcodes = dict(exec_metrics.get("retcodes_day") or {})
        total_exec_samples = int(sum(int(v) for v in retcodes.values())) if retcodes else 0
        rejects = int(exec_metrics.get("rejects_day", 0) or 0)
        reject_ratio = (float(rejects) / float(total_exec_samples)) if total_exec_samples > 0 else 0.0

        lookback_sec = max(60, int(time.time()) - int(start_ts_window))
        incident_counts = self.incident_journal.recent_counts(lookback_sec=lookback_sec) if self.incident_journal else {}
        exec_anomalies = int((incident_counts or {}).get("error_or_worse", 0) or 0)
        ipc_failures = int(self._count_ipc_failures_since(int(start_ts_window)))

        out_states: Dict[str, str] = {}
        out_reasons: Dict[str, List[str]] = {}
        module_map = dict(getattr(CFG, "module_live_enabled_map", {}) or {})
        max_daily_loss_account = float(max(0.0, getattr(CFG, "max_daily_loss_account", 0.0)))
        max_session_loss_account = float(max(0.0, getattr(CFG, "max_session_loss_account", 0.0)))
        max_daily_loss_module = float(max(0.0, getattr(CFG, "max_daily_loss_per_module", 0.0)))
        max_consecutive = int(max(1, getattr(CFG, "max_consecutive_losses_per_module", 3)))
        max_trades_window = int(max(1, getattr(CFG, "max_trades_per_window_per_module", 8)))
        max_exec_anom = int(max(1, getattr(CFG, "max_execution_anomalies_per_window", 4)))
        max_ipc = int(max(1, getattr(CFG, "max_ipc_failures_per_window", 4)))
        max_reject_ratio = float(max(0.0, getattr(CFG, "max_reject_ratio_threshold", 1.0)))
        max_reject_samples = int(max(1, getattr(CFG, "max_reject_ratio_min_samples", 10)))

        for grp in groups:
            reasons: List[str] = []
            state = "NORMAL"
            module_live = bool(module_map.get(grp, False))
            if not module_live:
                state = "OFF"
                reasons.append("MODULE_LIVE_DISABLED")
            if max_daily_loss_account > 0.0 and dd_pct >= max_daily_loss_account:
                state = "OFF"
                reasons.append("ACCOUNT_DAILY_LOSS")
            if max_session_loss_account > 0.0 and session_pnl <= (-1.0 * max_session_loss_account * bal_start):
                state = "OFF"
                reasons.append("SESSION_LOSS")

            module_pnl = float(self._pnl_net_since_ts_group(int(start_ts_pl), grp))
            if max_daily_loss_module > 0.0 and module_pnl <= (-1.0 * max_daily_loss_module * bal_start):
                state = "OFF"
                reasons.append("MODULE_DAILY_LOSS")

            if int(self._loss_streak_group(grp)) >= max_consecutive:
                state = "OFF"
                reasons.append("MODULE_LOSS_STREAK")

            if state != "OFF":
                tr_count = int(self._live_window_trade_counts.get(grp, 0))
                if tr_count >= max_trades_window:
                    state = "RESTRICTED"
                    reasons.append("MODULE_TRADES_WINDOW_CAP")
                if exec_anomalies >= max_exec_anom:
                    state = "RESTRICTED"
                    reasons.append("EXECUTION_ANOMALIES_CAP")
                if ipc_failures >= max_ipc:
                    state = "RESTRICTED"
                    reasons.append("IPC_FAILURES_CAP")
                if total_exec_samples >= max_reject_samples and reject_ratio >= max_reject_ratio:
                    state = "RESTRICTED"
                    reasons.append("REJECT_RATIO_CAP")
                elif total_exec_samples >= max_reject_samples and reject_ratio >= (0.8 * max_reject_ratio):
                    state = "REDUCE"
                    reasons.append("REJECT_RATIO_HIGH")

            if not reasons:
                reasons.append("NONE")
            out_states[grp] = str(state)
            out_reasons[grp] = list(reasons)

            prev_state = str(self._live_module_states.get(grp, "UNKNOWN"))
            prev_reasons = list(self._live_module_state_reasons.get(grp, []))
            if prev_state != state or prev_reasons != reasons:
                logging.warning(
                    "MODULE_STATE_CHANGE grp=%s prev=%s new=%s reasons=%s window_key=%s",
                    grp,
                    prev_state,
                    state,
                    ",".join(reasons),
                    window_key,
                )

        self._live_module_states = out_states
        self._live_module_state_reasons = out_reasons
        self._live_guard_snapshot = {
            "schema_version": "HL.A1.runtime",
            "ts_utc": now_dt.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "window_key": window_key,
            "window_phase": phase,
            "window_id": window_id,
            "dd_pct": float(dd_pct),
            "session_pnl": float(session_pnl),
            "bal_start": float(bal_start),
            "eq_now": float(eq_now),
            "reject_ratio": float(reject_ratio),
            "reject_samples": int(total_exec_samples),
            "execution_anomalies": int(exec_anomalies),
            "ipc_failures": int(ipc_failures),
            "module_states": dict(out_states),
            "module_state_reasons": dict(out_reasons),
            "module_trade_counts": dict(self._live_window_trade_counts),
        }

    def _refresh_no_live_drift_check(self, tw_ctx: Dict[str, Any]) -> None:
        rows: List[Dict[str, Any]] = []
        for raw, sym, grp in (self.universe or []):
            c = self._live_entry_contract(sym, grp)
            rows.append(
                {
                    "symbol_raw": str(sym),
                    "symbol_canonical": str(c.get("symbol_canonical") or canonical_symbol(sym)),
                    "group": _group_key(grp),
                    "entry_allowed": bool(c.get("entry_allowed", False)),
                    "reason_code": str(c.get("reason_code") or "UNKNOWN"),
                    "module_state": str(c.get("module_state") or "UNKNOWN"),
                    "module_state_reasons": list(c.get("module_state_reasons") or []),
                    "module_live_enabled": bool(c.get("module_live_enabled", False)),
                    "symbol_live_enabled": bool(c.get("symbol_live_enabled", False)),
                }
            )
        payload = {
            "schema_version": "HL.A1",
            "ts_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
            "live_canary_enabled": bool(getattr(CFG, "live_canary_enabled", False)),
            "policy_shadow_mode_enabled": bool(getattr(CFG, "policy_shadow_mode_enabled", True)),
            "trade_window_phase": str(tw_ctx.get("phase") or "UNKNOWN"),
            "trade_window_id": str(tw_ctx.get("window_id") or "UNKNOWN"),
            "rows": rows,
        }
        try:
            atomic_write_json(self.no_live_drift_path, payload)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _blocked_result_stub(self, *, retcode: int, comment: str, symbol: str, request: Dict[str, Any]) -> Any:
        ctx = {
            "message_id": "",
            "command_id": "",
            "request_id": "",
            "symbol_raw": str(symbol),
            "symbol_canonical": canonical_symbol(symbol),
            "request_price": float(request.get("price", 0.0) or 0.0),
            "deviation_requested_points": int(request.get("deviation") or request.get("deviation_points") or 0),
            "timestamp_utc": now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "timestamp_semantics": "UTC",
        }
        return SimpleNamespace(
            retcode=int(retcode),
            comment=str(comment),
            order=0,
            deal=0,
            request_context=ctx,
            message_id="",
            command_id="",
            request_id="",
            symbol_raw=str(symbol),
            symbol_canonical=canonical_symbol(symbol),
            request_price=float(ctx["request_price"]),
            executed_price=0.0,
            deviation_requested_points=int(ctx["deviation_requested_points"]),
            deviation_effective_points=0,
            point_size=0.0,
            tick_size=0.0,
            slippage_abs_price=None,
            slippage_points=None,
            slippage_ticks=None,
            spread_at_decision=None,
            spread_unit="UNKNOWN",
            spread_provenance="python.live_gate",
            estimated_entry_cost_components=dict(request.get("estimated_entry_cost_components") or {}),
            estimated_round_trip_cost=dict(request.get("estimated_round_trip_cost") or {}),
            cost_feasibility_shadow=request.get("cost_feasibility_shadow"),
            net_cost_feasible=request.get("net_cost_feasible"),
            cost_gate_policy_mode=str(request.get("cost_gate_policy_mode") or "DIAGNOSTIC_ONLY"),
            cost_gate_reason_code=str(request.get("cost_gate_reason_code") or "NONE"),
            realized_cost_components={},
            cost_estimation_quality="UNKNOWN",
            source_provenance="python.live_gate",
            timestamp_utc=ctx["timestamp_utc"],
            timestamp_semantics="UTC",
        )

    def resolve_canon_symbol(self, raw_sym: str) -> Optional[str]:
        if not isinstance(getattr(self, "resolved_symbols", None), dict):
            self.resolved_symbols = {}
        if not isinstance(getattr(self, "group_map_resolved", None), dict):
            self.group_map_resolved = {}
        if not hasattr(self, "db"):
            self.db = None
        if raw_sym in self.resolved_symbols:
            return self.resolved_symbols[raw_sym]
        engine = getattr(self, "execution_engine", None)
        if engine is None:
            # Backward-compatible fallback for tests/stubs using old attribute name.
            engine = getattr(self, "mt", None)
        if engine is None or not hasattr(engine, "symbol_info_cached"):
            return None
        suffixes = tuple(getattr(CFG, "symbol_suffixes", ("", ".pro", ".stp", ".pl")) or ("",))
        raw_norm = str(raw_sym or "").strip().upper()
        grp_default = CFG.symbol_group_map.get(raw_norm, "OTHER")

        def _score_symbol_for_entries(info_obj: object) -> Tuple[int, str]:
            """Prefer symbols that can accept new entries (FULL > directional > UNKNOWN)."""
            tm_name = "UNKNOWN"
            try:
                tm_name = _trade_mode_name(int(getattr(info_obj, "trade_mode", -1)))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                tm_name = "UNKNOWN"
            if tm_name == "FULL":
                return 3, tm_name
            if tm_name in ("LONGONLY", "SHORTONLY"):
                return 2, tm_name
            if tm_name == "UNKNOWN":
                return 1, tm_name
            if tm_name == "CLOSEONLY":
                return 0, tm_name
            return -1, tm_name

        best_score = -2
        best_cand: Optional[str] = None
        best_info: Optional[object] = None
        best_tm = "UNKNOWN"
        saw_disabled = False

        for base in symbol_alias_candidates(raw_norm):
            grp = CFG.symbol_group_map.get(base, grp_default)
            for suf in suffixes:
                cand = f"{base}{suf}"
                # Startup discovery path: do not consume SYS budget.
                info = None
                if mt5 is not None:
                    try:
                        info = mt5.symbol_info(cand)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        info = None
                    if info is None:
                        try:
                            mt5.symbol_select(cand, True)
                            info = mt5.symbol_info(cand)
                        except Exception as e:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                            info = None
                # Fallback to budget-aware path if direct probe is unavailable.
                if info is None:
                    info = engine.symbol_info_cached(cand, grp, self.db)
                if info is not None:
                    score, tm_name = _score_symbol_for_entries(info)
                    if score < 0:
                        saw_disabled = True
                        continue
                    if score > best_score:
                        best_score = score
                        best_cand = cand
                        best_info = info
                        best_tm = tm_name
                    if best_score >= 3:
                        break
            if best_score >= 3:
                break

        if best_cand is None:
            if saw_disabled:
                logging.warning(f"RESOLVE_SYMBOL_DISABLED_ONLY raw={raw_norm}")
            return None

        try:
            if hasattr(engine, "_sym_info_cache") and best_info is not None:
                engine._sym_info_cache[best_cand] = (time.time(), best_info)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        self.resolved_symbols[raw_sym] = best_cand
        logging.info(f"RESOLVE_SYMBOL raw={raw_norm} canon={best_cand} trade_mode={best_tm}")
        return best_cand

    def _build_universe(self) -> List[Tuple[str, str, str]]:
        """Buduje listę instrumentów (raw, canon, grp) i dodaje je do MarketWatch tylko raz.
        Cel: nie przepalać SYS budżetu na symbol_select w każdej iteracji.
        """
        out: List[Tuple[str, str, str]] = []
        for raw in CFG.symbols_to_trade:
            raw_norm = str(raw or "").strip().upper()
            grp_hint = str(CFG.symbol_group_map.get(raw_norm, "UNKNOWN") or "UNKNOWN").upper()
            if bool(getattr(CFG, "fx_only_mode", True)) and grp_hint not in {"UNKNOWN", "FX"}:
                logging.info(f"UNIVERSE_SKIP_FX_ONLY_PRE raw={raw} group_hint={grp_hint}")
                continue
            sym = self.resolve_canon_symbol(raw)
            if not sym:
                logging.warning(f"Nie znaleziono symbolu w MT5: {raw}")
                continue
            grp = guess_group(sym)
            if bool(getattr(CFG, "fx_only_mode", True)) and str(grp).upper() != "FX":
                logging.info(f"UNIVERSE_SKIP_FX_ONLY raw={raw} symbol={sym} group={grp}")
                continue
            info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
            block_reason = symbol_policy_block_reason(sym, grp, info=info, is_close=False)
            if block_reason:
                logging.warning(f"UNIVERSE_SKIP_SYMBOL_POLICY raw={raw} symbol={sym} group={grp} reason={block_reason}")
                continue
            # symbol_select jest SYS — robimy to jednorazowo
            self.execution_engine.symbol_select(sym, grp)
            out.append((raw, sym, grp))
        return out

    # -------------------------------------------------------------------------
    # V1.10: Time anchor helpers
    # -------------------------------------------------------------------------
    def _prime_time_anchor(self) -> None:
        """Jednorazowa inicjalizacja zegara serwera (1 PRICE request)."""
        if not self.universe:
            return
        # preferuj FX jako "referencyjny" (zwykle najpłynniejszy)
        ref_sym, ref_grp = None, None
        for _, sym, grp in self.universe:
            if grp == "FX":
                ref_sym, ref_grp = sym, grp
                break
        if ref_sym is None:
            _, ref_sym, ref_grp = self.universe[0]
        t = self.execution_engine.tick(ref_sym, ref_grp)
        if t is not None:
            logging.info(f"TIME ANCHOR primed via tick: {ref_sym}")

    def _time_anchor_sync_if_due(self, st: dict) -> None:
        """Okresowa synchronizacja czasu serwera.
        Koszt: 1 PRICE request / sync. Wykonuj tylko, jeśli budżet pozwala.
        """
        if _TIME_ANCHOR is None:
            return
        try:
            if not self.time_anchor.sync_due():
                return
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return
        try:
            if int(st.get("price_remaining", 0)) < int(CFG.time_anchor_min_price_remaining):
                return
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return

        # sync — preferuj FX
        ref_sym, ref_grp = None, None
        for _, sym, grp in self.universe:
            if grp == "FX":
                ref_sym, ref_grp = sym, grp
                break
        if ref_sym is None:
            _, ref_sym, ref_grp = self.universe[0]

        _ = self.execution_engine.tick(ref_sym, ref_grp)  # tick() aktualizuje kotwicę

    def _manual_kill_switch_active(self) -> bool:
        try:
            active = bool(self.manual_kill_switch_path.exists())
        except Exception:
            active = False
        if active:
            now_ts = float(time.time())
            if (now_ts - float(self._last_manual_kill_log_ts or 0.0)) >= 60.0:
                logging.warning(
                    "MANUAL_KILL_SWITCH active=1 path=%s (new entries paused)",
                    str(self.manual_kill_switch_path),
                )
                self._last_manual_kill_log_ts = now_ts
        return active

    def _metrics_roll_day(self) -> None:
        day_key = str(pl_day_key(now_utc()))
        if day_key == str(self._metrics_day_key):
            return
        self._metrics_day_key = day_key
        self._metrics_eco_scans_day = 0
        self._metrics_warn_scans_day = 0
        self._metrics_10m_anchor = {}
        self._metrics_10m_last_emit_ts = 0.0

    @staticmethod
    def _percentile_int(values: List[int], pct: float) -> int:
        if not values:
            return 0
        p = min(1.0, max(0.0, float(pct)))
        s = sorted(int(v) for v in values)
        idx = int(round((len(s) - 1) * p))
        idx = min(len(s) - 1, max(0, idx))
        return int(s[idx])

    def _record_scan_duration(self, scan_ms: int) -> None:
        win = max(16, int(getattr(CFG, "run_loop_scan_stats_window", 120)))
        self._loop_scan_durations_ms.append(int(max(0, scan_ms)))
        if len(self._loop_scan_durations_ms) > win:
            self._loop_scan_durations_ms = self._loop_scan_durations_ms[-win:]

    def _record_section_duration(self, section: str, duration_ms: int) -> None:
        key = str(section or "").strip().lower()
        if not key:
            return
        if not isinstance(getattr(self, "_loop_section_durations_ms", None), dict):
            self._loop_section_durations_ms = {}
        win = max(
            16,
            int(
                getattr(
                    CFG,
                    "run_loop_section_stats_window",
                    getattr(CFG, "run_loop_scan_stats_window", 120),
                )
            ),
        )
        arr = self._loop_section_durations_ms.setdefault(key, [])
        arr.append(int(max(0, duration_ms)))
        if len(arr) > win:
            self._loop_section_durations_ms[key] = arr[-win:]

    def _record_bridge_diag(self, diag: Dict[str, Any], *, action: str) -> None:
        if not isinstance(diag, dict) or not diag:
            return
        send_ms = int(max(0, int(diag.get("bridge_send_ms", 0) or 0)))
        wait_ms = int(max(0, int(diag.get("bridge_wait_ms", 0) or 0)))
        parse_ms = int(max(0, int(diag.get("bridge_parse_ms", 0) or 0)))
        total_ms = int(max(0, int(diag.get("bridge_total_ms", 0) or 0)))
        reason = str(diag.get("bridge_timeout_reason") or "NONE").strip().upper() or "NONE"
        subreason = str(diag.get("bridge_timeout_subreason") or "NONE").strip().upper() or "NONE"
        status = str(diag.get("status") or "UNKNOWN").strip().upper() or "UNKNOWN"
        command_type = str(diag.get("command_type") or str(action or "").upper() or "OTHER").strip().upper() or "OTHER"
        budget_bucket = str(diag.get("timeout_budget_bucket") or "UNKNOWN").strip().upper() or "UNKNOWN"
        loop_id = str(diag.get("loop_id") or "none")
        cmd_id = str(diag.get("command_id") or "")
        attempts = int(max(0, int(diag.get("attempts", 0) or 0)))
        timeout_budget_ms = int(max(1, int(diag.get("timeout_budget_ms", 1) or 1)))
        queue_wait_ms = int(max(0, int(diag.get("command_queue_wait_ms", 0) or 0)))
        audit_lock_wait_ms = int(max(0, int(diag.get("audit_log_lock_wait_max_ms", 0) or 0)))
        self._record_section_duration("bridge_send", send_ms)
        self._record_section_duration("bridge_wait", wait_ms)
        self._record_section_duration("bridge_parse", parse_ms)
        logging.info(
            "BRIDGE_DIAG action=%s command_type=%s loop_id=%s command_id=%s status=%s reason=%s subreason=%s attempts=%s "
            "send_ms=%s wait_ms=%s parse_ms=%s total_ms=%s timeout_budget_ms=%s timeout_budget_bucket=%s queue_wait_ms=%s audit_lock_wait_max_ms=%s",
            str(action or "").upper(),
            command_type,
            loop_id,
            cmd_id,
            status,
            reason,
            subreason,
            attempts,
            send_ms,
            wait_ms,
            parse_ms,
            total_ms,
            timeout_budget_ms,
            budget_bucket,
            queue_wait_ms,
            audit_lock_wait_ms,
        )

    def _section_metrics_snapshot(self) -> Dict[str, Dict[str, int]]:
        out: Dict[str, Dict[str, int]] = {}
        for section in (
            "tick_ingest",
            "bridge_send",
            "bridge_wait",
            "bridge_parse",
            "session_gate",
            "cost_gate",
            "decision_core",
            "execution_call",
            "io_log",
        ):
            arr = list(self._loop_section_durations_ms.get(section, []))
            out[section] = {
                "n": int(len(arr)),
                "p50_ms": int(self._percentile_int(arr, 0.50)),
                "p95_ms": int(self._percentile_int(arr, 0.95)),
                "p99_ms": int(self._percentile_int(arr, 0.99)),
                "max_ms": int(max(arr)) if arr else 0,
            }
        return out

    def _loop_metrics_snapshot(self) -> Dict[str, Any]:
        arr = list(self._loop_scan_durations_ms)
        return {
            "scan_runs_total": int(self._loop_scan_runs),
            "scan_errors_total": int(self._loop_scan_errors),
            "scan_last_ms": int(arr[-1]) if arr else 0,
            "scan_p50_ms": int(self._percentile_int(arr, 0.50)),
            "scan_p95_ms": int(self._percentile_int(arr, 0.95)),
            "scan_max_ms": int(max(arr)) if arr else 0,
            "heartbeat_fail_total": int(self._loop_heartbeat_fail_total),
            "heartbeat_recoveries_total": int(self._loop_heartbeat_recoveries),
        }

    def _emit_runtime_metrics(self, st: Dict[str, Any], *, eco_active: bool, warn_active: bool) -> None:
        self._metrics_roll_day()
        if bool(eco_active):
            self._metrics_eco_scans_day = int(self._metrics_eco_scans_day) + 1
        if bool(warn_active):
            self._metrics_warn_scans_day = int(self._metrics_warn_scans_day) + 1

        now_ts = float(time.time())
        interval_s = max(60, int(getattr(CFG, "runtime_metrics_interval_sec", 600)))

        if not self._metrics_10m_anchor:
            # Lightweight anchor init: snapshot strategy/execution counters only once.
            strat_metrics = {}
            exec_metrics = {}
            try:
                strat_metrics = self.strategy.metrics_snapshot()
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                strat_metrics = {}
            try:
                exec_metrics = self.execution_engine.metrics_snapshot()
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                exec_metrics = {}
            self._metrics_10m_anchor = {
                "ts": now_ts,
                "price_requests_day": int(st.get("price_requests_day", 0) or 0),
                "sys_requests_day": int(st.get("sys_requests_day", 0) or 0),
                "order_actions_day": int(st.get("order_actions_day", 0) or 0),
                "entries_day": int(strat_metrics.get("entries_day", 0) or 0),
                "rejects_day": int(exec_metrics.get("rejects_day", 0) or 0),
                "eco_scans_day": int(self._metrics_eco_scans_day),
                "warn_scans_day": int(self._metrics_warn_scans_day),
            }
            self._metrics_10m_last_emit_ts = now_ts
            return

        if (now_ts - float(self._metrics_10m_last_emit_ts or 0.0)) < float(interval_s):
            return

        strat_metrics = {}
        exec_metrics = {}
        try:
            strat_metrics = self.strategy.metrics_snapshot()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            strat_metrics = {}
        try:
            exec_metrics = self.execution_engine.metrics_snapshot()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            exec_metrics = {}
        queue_metrics = {}
        try:
            if getattr(self, "execution_queue", None) is not None:
                queue_metrics = self.execution_queue.metrics_snapshot()
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            queue_metrics = {}
        loop_metrics = self._loop_metrics_snapshot()

        a = dict(self._metrics_10m_anchor)
        cur_price = int(st.get("price_requests_day", 0) or 0)
        cur_sys = int(st.get("sys_requests_day", 0) or 0)
        cur_order = int(st.get("order_actions_day", 0) or 0)
        cur_entries = int(strat_metrics.get("entries_day", 0) or 0)
        cur_rejects = int(exec_metrics.get("rejects_day", 0) or 0)
        d_price = max(0, cur_price - int(a.get("price_requests_day", 0)))
        d_sys = max(0, cur_sys - int(a.get("sys_requests_day", 0)))
        d_order = max(0, cur_order - int(a.get("order_actions_day", 0)))
        d_entries = max(0, cur_entries - int(a.get("entries_day", 0)))
        d_rejects = max(0, cur_rejects - int(a.get("rejects_day", 0)))
        d_eco = max(0, int(self._metrics_eco_scans_day) - int(a.get("eco_scans_day", 0)))
        d_warn = max(0, int(self._metrics_warn_scans_day) - int(a.get("warn_scans_day", 0)))
        skip_day = dict(strat_metrics.get("skip_day", {}) or {})
        top_rejects = list(exec_metrics.get("top_rejects", []) or [])

        logging.info(
            "RUNTIME_METRICS_10M day=%s price_requests_10m=%s sys_requests_10m=%s order_actions_10m=%s "
            "entries_10m=%s rejects_10m=%s entries_day=%s rejects_day=%s avg_spread_entry_points_day=%.3f "
            "skip_no_signal_day=%s skip_m5_same_bar_day=%s skip_m5_pull_wait_day=%s skip_m5_wait_new_bar_day=%s "
            "eco_scans_10m=%s warn_scans_10m=%s top_rejects_day=%s "
            "scan_p50_ms=%s scan_p95_ms=%s scan_max_ms=%s hb_fail_total=%s hb_recoveries_total=%s "
            "q_fill_ratio=%.3f q_backpressure_drops=%s q_timeouts=%s q_full=%s",
            str(self._metrics_day_key),
            int(d_price),
            int(d_sys),
            int(d_order),
            int(d_entries),
            int(d_rejects),
            int(cur_entries),
            int(cur_rejects),
            float(strat_metrics.get("avg_spread_entry_points_day", 0.0) or 0.0),
            int(skip_day.get("NO_SIGNAL", 0)),
            int(skip_day.get("M5_SAME_BAR", 0)),
            int(skip_day.get("M5_PULL_WAIT", 0)),
            int(skip_day.get("M5_WAIT_NEW_BAR", 0)),
            int(d_eco),
            int(d_warn),
            str(top_rejects),
            int(loop_metrics.get("scan_p50_ms", 0)),
            int(loop_metrics.get("scan_p95_ms", 0)),
            int(loop_metrics.get("scan_max_ms", 0)),
            int(loop_metrics.get("heartbeat_fail_total", 0)),
            int(loop_metrics.get("heartbeat_recoveries_total", 0)),
            float(queue_metrics.get("fill_ratio", 0.0) or 0.0),
            int(queue_metrics.get("backpressure_drops", 0)),
            int(queue_metrics.get("queue_timeout", 0)),
            int(queue_metrics.get("queue_full", 0)),
        )
        sec = self._section_metrics_snapshot()
        logging.info(
            "RUNTIME_SECTION_METRICS_10M "
            "tick_ingest_p50_ms=%s tick_ingest_p95_ms=%s tick_ingest_p99_ms=%s "
            "bridge_send_p50_ms=%s bridge_send_p95_ms=%s bridge_send_p99_ms=%s "
            "bridge_wait_p50_ms=%s bridge_wait_p95_ms=%s bridge_wait_p99_ms=%s "
            "bridge_parse_p50_ms=%s bridge_parse_p95_ms=%s bridge_parse_p99_ms=%s "
            "session_gate_p50_ms=%s session_gate_p95_ms=%s session_gate_p99_ms=%s "
            "cost_gate_p50_ms=%s cost_gate_p95_ms=%s cost_gate_p99_ms=%s "
            "decision_core_p50_ms=%s decision_core_p95_ms=%s decision_core_p99_ms=%s "
            "execution_call_p50_ms=%s execution_call_p95_ms=%s execution_call_p99_ms=%s "
            "io_log_p50_ms=%s io_log_p95_ms=%s io_log_p99_ms=%s",
            int((sec.get("tick_ingest") or {}).get("p50_ms", 0)),
            int((sec.get("tick_ingest") or {}).get("p95_ms", 0)),
            int((sec.get("tick_ingest") or {}).get("p99_ms", 0)),
            int((sec.get("bridge_send") or {}).get("p50_ms", 0)),
            int((sec.get("bridge_send") or {}).get("p95_ms", 0)),
            int((sec.get("bridge_send") or {}).get("p99_ms", 0)),
            int((sec.get("bridge_wait") or {}).get("p50_ms", 0)),
            int((sec.get("bridge_wait") or {}).get("p95_ms", 0)),
            int((sec.get("bridge_wait") or {}).get("p99_ms", 0)),
            int((sec.get("bridge_parse") or {}).get("p50_ms", 0)),
            int((sec.get("bridge_parse") or {}).get("p95_ms", 0)),
            int((sec.get("bridge_parse") or {}).get("p99_ms", 0)),
            int((sec.get("session_gate") or {}).get("p50_ms", 0)),
            int((sec.get("session_gate") or {}).get("p95_ms", 0)),
            int((sec.get("session_gate") or {}).get("p99_ms", 0)),
            int((sec.get("cost_gate") or {}).get("p50_ms", 0)),
            int((sec.get("cost_gate") or {}).get("p95_ms", 0)),
            int((sec.get("cost_gate") or {}).get("p99_ms", 0)),
            int((sec.get("decision_core") or {}).get("p50_ms", 0)),
            int((sec.get("decision_core") or {}).get("p95_ms", 0)),
            int((sec.get("decision_core") or {}).get("p99_ms", 0)),
            int((sec.get("execution_call") or {}).get("p50_ms", 0)),
            int((sec.get("execution_call") or {}).get("p95_ms", 0)),
            int((sec.get("execution_call") or {}).get("p99_ms", 0)),
            int((sec.get("io_log") or {}).get("p50_ms", 0)),
            int((sec.get("io_log") or {}).get("p95_ms", 0)),
            int((sec.get("io_log") or {}).get("p99_ms", 0)),
        )

        self._metrics_10m_anchor = {
            "ts": now_ts,
            "price_requests_day": int(cur_price),
            "sys_requests_day": int(cur_sys),
            "order_actions_day": int(cur_order),
            "entries_day": int(cur_entries),
            "rejects_day": int(cur_rejects),
            "eco_scans_day": int(self._metrics_eco_scans_day),
            "warn_scans_day": int(self._metrics_warn_scans_day),
        }
        self._metrics_10m_last_emit_ts = now_ts

    def _dispatch_order(self, symbol: str, grp: str, request: dict, emergency: bool = False):
        """
        Dispatches orders with synchronous REQ/REP semantics for DEAL opens.
        """
        if not isinstance(getattr(self, "_live_window_trade_counts", None), dict):
            self._live_window_trade_counts = {}
        if not isinstance(getattr(self, "_pending_cache", None), dict):
            self._pending_cache = {}
        if not isinstance(getattr(self, "_positions_cache", None), dict):
            self._positions_cache = {}
        if not hasattr(self, "live_canary_contract_path"):
            self.live_canary_contract_path = Path("RUN/live_canary_contract.json")
        if not hasattr(self, "no_live_drift_path"):
            self.no_live_drift_path = Path("RUN/no_live_drift.json")

        action = request.get("action")
        close_ticket = int(request.get("position") or 0)
        # Agent MQL5 currently supports TRADE opens only.
        # Position-close DEAL requests stay on legacy path to preserve behavior.
        if action == mt5.TRADE_ACTION_DEAL and close_ticket <= 0:
            signal = "BUY" if request.get("type") == mt5.ORDER_TYPE_BUY else "SELL"
            grp_u = _group_key(grp)
            live_contract = self._live_entry_contract(symbol, grp_u)
            if not bool(live_contract.get("entry_allowed", False)):
                reason_code = str(live_contract.get("reason_code") or "LIVE_CONTRACT_BLOCK")
                logging.warning(
                    "ENTRY_BLOCK_HARD_LIVE symbol=%s group=%s reason=%s module_state=%s module_reasons=%s",
                    symbol,
                    grp_u,
                    reason_code,
                    str(live_contract.get("module_state") or "UNKNOWN"),
                    ",".join([str(x) for x in (live_contract.get("module_state_reasons") or [])]),
                )
                self._append_execution_telemetry(
                    {
                        "event_type": "ENTRY_BLOCK_HARD_LIVE",
                        "symbol_raw": str(symbol),
                        "symbol_canonical": str(live_contract.get("symbol_canonical") or canonical_symbol(symbol)),
                        "group": str(grp_u),
                        "reason_code": reason_code,
                        "module_state": str(live_contract.get("module_state") or "UNKNOWN"),
                        "module_state_reasons": list(live_contract.get("module_state_reasons") or []),
                        "cost_gate_policy_mode": str(getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY")),
                        "source_list": [str(self.live_canary_contract_path), str(self.no_live_drift_path)],
                        "method": "hard_live_gate",
                        "sample_size_n": 1,
                        "low_stat_power": True,
                    }
                )
                return self._blocked_result_stub(
                    retcode=int(getattr(mt5, "TRADE_RETCODE_TRADE_DISABLED", 10017)),
                    comment=f"HARD_LIVE_BLOCK:{reason_code}",
                    symbol=symbol,
                    request=request,
                )

            session_gate_t0 = time.perf_counter()
            session_liq = self._session_liquidity_gate_eval(symbol, grp_u, request)
            self._record_section_duration("session_gate", int((time.perf_counter() - session_gate_t0) * 1000.0))
            request["session_liquidity_gate"] = dict(session_liq)
            slg_mode = str(session_liq.get("mode") or "SHADOW_ONLY").upper()
            slg_allow = bool(session_liq.get("allow_trade", True))
            slg_state = str(session_liq.get("gate_state") or "ALLOW").upper()
            slg_reason = str(session_liq.get("reason_code") or "SLG_UNKNOWN")
            emit_caution = bool(getattr(CFG, "session_liquidity_emit_caution_event", True))

            if slg_mode == "GATE_ENFORCE":
                if not slg_allow:
                    logging.warning(
                        "ENTRY_BLOCK_SESSION_LIQUIDITY symbol=%s group=%s reason=%s state=%s phase=%s window=%s spread=%s tick_age=%s",
                        symbol,
                        grp_u,
                        slg_reason,
                        slg_state,
                        str(session_liq.get("trade_window_phase") or "UNKNOWN"),
                        str(session_liq.get("trade_window_id") or "NONE"),
                        str(session_liq.get("spread_points") if session_liq.get("spread_points") is not None else "NA"),
                        str(session_liq.get("tick_age_sec") if session_liq.get("tick_age_sec") is not None else "NA"),
                    )
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_BLOCK_SESSION_LIQUIDITY",
                            **dict(session_liq),
                            "method": "session_liquidity_gate",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
                    return self._blocked_result_stub(
                        retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                        comment=f"SESSION_LIQUIDITY:{slg_reason}",
                        symbol=symbol,
                        request=request,
                    )
                if slg_state == "CAUTION" and emit_caution:
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_CAUTION_SESSION_LIQUIDITY",
                            **dict(session_liq),
                            "method": "session_liquidity_gate",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
            elif slg_mode == "SHADOW_ONLY":
                if (not slg_allow) or (slg_state == "CAUTION" and emit_caution):
                    self._append_execution_telemetry(
                        {
                            "event_type": (
                                "ENTRY_SHADOW_BLOCK_SESSION_LIQUIDITY"
                                if not slg_allow
                                else "ENTRY_SHADOW_CAUTION_SESSION_LIQUIDITY"
                            ),
                            **dict(session_liq),
                            "method": "session_liquidity_gate_shadow",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )

            cost_gate_t0 = time.perf_counter()
            cost_micro = self._cost_microstructure_gate_eval(symbol, grp_u, request)
            self._record_section_duration("cost_gate", int((time.perf_counter() - cost_gate_t0) * 1000.0))
            request["cost_microstructure_gate"] = dict(cost_micro)
            cmg_mode = str(cost_micro.get("mode") or "SHADOW_ONLY").upper()
            cmg_allow = bool(cost_micro.get("cost_allow_trade", True))
            cmg_reason = str(cost_micro.get("reason_code") or "CMG_UNKNOWN")
            cmg_grade = str(cost_micro.get("cost_grade") or "UNKNOWN")
            cmg_emit_caution = bool(getattr(CFG, "cost_microstructure_emit_caution_event", True))
            if cmg_mode == "GATE_ENFORCE":
                if not cmg_allow:
                    logging.warning(
                        "ENTRY_BLOCK_COST_MICROSTRUCTURE symbol=%s group=%s reason=%s grade=%s spread=%s tick_age=%s jump=%s gap=%s",
                        symbol,
                        grp_u,
                        cmg_reason,
                        cmg_grade,
                        str(cost_micro.get("spread_points") if cost_micro.get("spread_points") is not None else "NA"),
                        str(cost_micro.get("tick_age_sec") if cost_micro.get("tick_age_sec") is not None else "NA"),
                        str(cost_micro.get("price_jump_points") if cost_micro.get("price_jump_points") is not None else "NA"),
                        str(cost_micro.get("tick_gap_sec") if cost_micro.get("tick_gap_sec") is not None else "NA"),
                    )
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_BLOCK_COST_MICROSTRUCTURE",
                            **dict(cost_micro),
                            "method": "cost_microstructure_gate",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
                    return self._blocked_result_stub(
                        retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                        comment=f"COST_MICRO:{cmg_reason}",
                        symbol=symbol,
                        request=request,
                    )
                if cmg_emit_caution and str(cmg_reason).upper() == "CMG_CAUTION":
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_CAUTION_COST_MICROSTRUCTURE",
                            **dict(cost_micro),
                            "method": "cost_microstructure_gate",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
            elif cmg_mode == "SHADOW_ONLY":
                if (not cmg_allow) or (cmg_emit_caution and str(cmg_reason).upper() == "CMG_CAUTION"):
                    self._append_execution_telemetry(
                        {
                            "event_type": (
                                "ENTRY_SHADOW_BLOCK_COST_MICROSTRUCTURE"
                                if not cmg_allow
                                else "ENTRY_SHADOW_CAUTION_COST_MICROSTRUCTURE"
                            ),
                            **dict(cost_micro),
                            "method": "cost_microstructure_gate_shadow",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )

            # Hard throttle: per-window max trades per module.
            grp_count = int(self._live_window_trade_counts.get(grp_u, 0))
            grp_limit = int(max(1, getattr(CFG, "max_trades_per_window_per_module", 8)))
            if grp_count >= grp_limit:
                logging.warning(
                    "ENTRY_BLOCK_THROTTLE symbol=%s group=%s reason=MODULE_TRADES_WINDOW_CAP count=%s limit=%s",
                    symbol,
                    grp_u,
                    grp_count,
                    grp_limit,
                )
                self._append_execution_telemetry(
                    {
                        "event_type": "ENTRY_BLOCK_THROTTLE",
                        "symbol_raw": str(symbol),
                        "symbol_canonical": canonical_symbol(symbol),
                        "group": str(grp_u),
                        "reason_code": "MODULE_TRADES_WINDOW_CAP",
                        "current_value": int(grp_count),
                        "limit_value": int(grp_limit),
                        "method": "hard_live_throttle",
                        "sample_size_n": 1,
                        "low_stat_power": True,
                    }
                )
                return self._blocked_result_stub(
                    retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                    comment="THROTTLE:MODULE_TRADES_WINDOW_CAP",
                    symbol=symbol,
                    request=request,
                )

            # Active cost gate in canary mode (no strategy mutation; execution feasibility only).
            cost_mode = str(getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY") or "DIAGNOSTIC_ONLY").strip().upper()
            if cost_mode == "CANARY_ACTIVE" and cmg_mode != "GATE_ENFORCE":
                est_rt = request.get("estimated_round_trip_cost") if isinstance(request.get("estimated_round_trip_cost"), dict) else {}
                est_comp = request.get("estimated_entry_cost_components") if isinstance(request.get("estimated_entry_cost_components"), dict) else {}
                quality = str(
                    est_comp.get("cost_estimation_quality")
                    or est_rt.get("cost_estimation_quality")
                    or "UNKNOWN"
                ).upper()
                cost_unknown = quality in {"UNKNOWN", "HEURISTIC", "PARTIAL"}
                cost_value = est_rt.get("value_price")
                target_move = request.get("target_move_price")
                feasible_shadow = request.get("cost_feasibility_shadow")
                ratio = None
                try:
                    if cost_value is not None and target_move is not None and float(cost_value) > 0.0:
                        ratio = float(target_move) / float(cost_value)
                except Exception:
                    ratio = None
                cost_guard_effective = self._cost_gate_effective_params()
                min_ratio = float(max(0.0, cost_guard_effective.get("min_target_to_cost_ratio", getattr(CFG, "cost_gate_min_target_to_cost_ratio", 1.10))))
                block_unknown_quality = bool(
                    cost_guard_effective.get(
                        "block_unknown_quality",
                        getattr(CFG, "cost_gate_block_on_unknown_quality", True),
                    )
                )
                block_reason = ""
                if bool(block_unknown_quality) and cost_unknown:
                    block_reason = "BLOCK_TRADE_COST_UNKNOWN"
                elif feasible_shadow is False:
                    block_reason = "BLOCK_TRADE_COST"
                elif ratio is not None and ratio < min_ratio:
                    block_reason = "BLOCK_TRADE_COST_RATIO"
                if block_reason:
                    logging.warning(
                        "ENTRY_BLOCK_COST symbol=%s group=%s reason=%s quality=%s ratio=%s min_ratio=%.3f",
                        symbol,
                        grp_u,
                        block_reason,
                        quality,
                        ("%.4f" % float(ratio)) if ratio is not None else "NA",
                        float(min_ratio),
                    )
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_BLOCK_COST",
                            "symbol_raw": str(symbol),
                            "symbol_canonical": canonical_symbol(symbol),
                            "group": str(grp_u),
                            "reason_code": str(block_reason),
                            "cost_gate_policy_mode": str(cost_mode),
                            "cost_estimation_quality": str(quality),
                            "cost_feasibility_shadow": feasible_shadow,
                            "cost_target_to_estimated_ratio": ratio,
                            "cost_ratio_min_required": float(min_ratio),
                            "cost_guard_auto_relax_active": bool(cost_guard_effective.get("active", False)),
                            "cost_guard_auto_relax_reason": str(cost_guard_effective.get("reason") or "UNKNOWN"),
                            "cost_guard_block_unknown_effective": bool(block_unknown_quality),
                            "method": "cost_gate",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
                    return self._blocked_result_stub(
                        retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                        comment=f"{block_reason}:{quality}",
                        symbol=symbol,
                        request=request,
                    )

            # JPY basket exposure cap (Wave-1).
            sym_canon = canonical_symbol(symbol)
            jpy_set = self._resolve_intents_to_canonical(
                tuple(getattr(CFG, "jpy_basket_symbol_intents", ()) or ())
            )
            if sym_canon in jpy_set:
                max_pos = int(max(1, getattr(CFG, "jpy_basket_max_concurrent_positions", 1)))
                max_budget = float(max(0.0, getattr(CFG, "jpy_basket_max_risk_budget", 0.0)))
                eq_now = 0.0
                try:
                    acc_info = self.execution_engine.account_info()
                    eq_now = float(getattr(acc_info, "equity", 0.0) or 0.0) if acc_info is not None else 0.0
                except Exception:
                    eq_now = 0.0
                positions = self.execution_engine.positions_get(emergency=False) or []
                basket_positions = []
                for p in positions:
                    try:
                        if int(getattr(p, "magic", 0) or 0) != int(CFG.magic_number):
                            continue
                        if canonical_symbol(str(getattr(p, "symbol", "") or "")) in jpy_set:
                            basket_positions.append(p)
                    except Exception:
                        continue
                if len(basket_positions) >= max_pos:
                    self._append_execution_telemetry(
                        {
                            "event_type": "ENTRY_BLOCK_BASKET",
                            "symbol_raw": str(symbol),
                            "symbol_canonical": str(sym_canon),
                            "group": str(grp_u),
                            "reason_code": "JPY_BASKET_MAX_POSITIONS",
                            "basket_positions": int(len(basket_positions)),
                            "basket_limit": int(max_pos),
                            "selection_mode": str(getattr(CFG, "jpy_basket_selection_mode", "TOP_1")),
                            "ranking_basis_for_top_k": str(getattr(CFG, "jpy_basket_ranking_basis_for_top_k", "")),
                            "method": "jpy_basket_cap",
                            "sample_size_n": 1,
                            "low_stat_power": True,
                        }
                    )
                    return self._blocked_result_stub(
                        retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                        comment="JPY_BASKET_MAX_POSITIONS",
                        symbol=symbol,
                        request=request,
                    )
                if max_budget > 0.0 and eq_now > 0.0:
                    cur_risk = 0.0
                    for p in basket_positions:
                        try:
                            p_sym = str(getattr(p, "symbol", "") or "")
                            p_grp = guess_group(p_sym)
                            p_info = self.execution_engine.symbol_info_cached(p_sym, p_grp, self.db)
                            if p_info is None:
                                continue
                            tick_sz = float(getattr(p_info, "trade_tick_size", 0.0) or 0.0)
                            tick_val = float(getattr(p_info, "trade_tick_value", 0.0) or 0.0)
                            p_vol = float(getattr(p, "volume", 0.0) or 0.0)
                            p_sl = float(getattr(p, "sl", 0.0) or 0.0)
                            p_open = float(getattr(p, "price_open", 0.0) or 0.0)
                            if tick_sz > 0.0 and tick_val > 0.0 and p_vol > 0.0 and p_sl > 0.0 and p_open > 0.0:
                                cur_risk += float(abs(p_open - p_sl) / tick_sz) * float(tick_val) * float(p_vol)
                        except Exception:
                            continue
                    req_risk = 0.0
                    try:
                        info_req = self.execution_engine.symbol_info_cached(symbol, grp_u, self.db)
                        tick_sz = float(getattr(info_req, "trade_tick_size", 0.0) or 0.0) if info_req is not None else 0.0
                        tick_val = float(getattr(info_req, "trade_tick_value", 0.0) or 0.0) if info_req is not None else 0.0
                        vol_req = float(request.get("volume", 0.0) or 0.0)
                        px_req = float(request.get("price", 0.0) or 0.0)
                        sl_req = float(request.get("sl", 0.0) or 0.0)
                        if tick_sz > 0.0 and tick_val > 0.0 and vol_req > 0.0 and px_req > 0.0 and sl_req > 0.0:
                            req_risk = float(abs(px_req - sl_req) / tick_sz) * float(tick_val) * float(vol_req)
                    except Exception:
                        req_risk = 0.0
                    budget_ratio = float((cur_risk + req_risk) / eq_now) if eq_now > 0.0 else 0.0
                    if budget_ratio > max_budget:
                        self._append_execution_telemetry(
                            {
                                "event_type": "ENTRY_BLOCK_BASKET",
                                "symbol_raw": str(symbol),
                                "symbol_canonical": str(sym_canon),
                                "group": str(grp_u),
                                "reason_code": "JPY_BASKET_RISK_BUDGET",
                                "basket_risk_ratio_after": float(budget_ratio),
                                "basket_risk_budget_limit": float(max_budget),
                                "selection_mode": str(getattr(CFG, "jpy_basket_selection_mode", "TOP_1")),
                                "ranking_basis_for_top_k": str(getattr(CFG, "jpy_basket_ranking_basis_for_top_k", "")),
                                "method": "jpy_basket_cap",
                                "sample_size_n": 1,
                                "low_stat_power": True,
                            }
                        )
                        return self._blocked_result_stub(
                            retcode=int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006)),
                            comment="JPY_BASKET_RISK_BUDGET",
                            symbol=symbol,
                            request=request,
                        )

            risk_state = group_market_risk_state(grp_u)
            risk_entry_allowed = bool(risk_state.get("entry_allowed", True))
            risk_reason = str(risk_state.get("reason", "NONE"))
            risk_friday = bool(risk_state.get("friday_risk", False))
            risk_reopen = bool(risk_state.get("reopen_guard", False))
            if bool(getattr(self, "_black_swan_block_new_entries", False)):
                risk_entry_allowed = False
                v2_reason = str(getattr(self, "_black_swan_v2_reason", "BLACK_SWAN_GUARD") or "BLACK_SWAN_GUARD").strip().upper()
                if v2_reason == "NONE":
                    v2_reason = "BLACK_SWAN_GUARD"
                risk_reason = f"BLACK_SWAN_{v2_reason}"
                risk_friday = bool(risk_friday)
                risk_reopen = bool(risk_reopen)
            if (not risk_entry_allowed) and str(risk_reason).upper() == "NONE" and (not risk_friday) and (not risk_reopen):
                logging.warning(
                    "RISK_STATE_INCONSISTENT symbol=%s group=%s entry_allowed=0 reason=NONE friday=0 reopen=0 forcing_entry_allowed=1",
                    symbol,
                    grp_u,
                )
                risk_entry_allowed = True
            logging.info(
                "HYBRID_DISPATCH_RISK symbol=%s group=%s entry_allowed=%s reason=%s friday=%s reopen=%s shadow=%s",
                symbol,
                grp_u,
                int(risk_entry_allowed),
                risk_reason,
                int(risk_friday),
                int(risk_reopen),
                int(bool(getattr(CFG, "policy_shadow_mode_enabled", True))),
            )
            logging.info(f"HYBRID_DISPATCH | DEAL over ZMQ symbol={symbol} signal={signal}")
            req_dev_points = int(request.get("deviation") or request.get("deviation_points") or 0)
            if req_dev_points <= 0:
                req_dev_points = int(max(1, _cfg_group_int(grp_u, "order_deviation_points", 20, symbol=symbol)))
                self._emit_unit_diagnostic(
                    parameter_name="order_deviation_points",
                    current_unit="AMBIGUOUS_UNIT",
                    expected_unit="points",
                    risk_level="MED",
                    details={
                        "symbol": str(symbol),
                        "group": str(grp_u),
                        "fallback_deviation_points": int(req_dev_points),
                    },
                )
            exec_call_t0 = time.perf_counter()
            reply = self._send_trade_command(
                signal=signal,
                symbol=symbol,
                volume=request.get("volume"),
                sl_price=request.get("sl"),
                tp_price=request.get("tp"),
                request_price=float(request.get("price", 0.0) or 0.0),
                deviation_points=int(req_dev_points),
                spread_at_decision_points=request.get("spread_at_decision_points"),
                spread_unit=str(request.get("spread_at_decision_unit") or "AMBIGUOUS_UNIT"),
                spread_provenance=str(request.get("spread_at_decision_provenance") or "UNKNOWN"),
                estimated_entry_cost_components=request.get("estimated_entry_cost_components"),
                estimated_round_trip_cost=request.get("estimated_round_trip_cost"),
                cost_feasibility_shadow=request.get("cost_feasibility_shadow"),
                net_cost_feasible=request.get("net_cost_feasible"),
                cost_gate_policy_mode=str(request.get("cost_gate_policy_mode") or getattr(CFG, "cost_gate_policy_mode", "DIAGNOSTIC_ONLY")),
                cost_gate_reason_code=str(request.get("cost_gate_reason_code") or "NONE"),
                magic=request.get("magic"),
                comment=request.get("comment"),
                group=grp_u,
                risk_entry_allowed=risk_entry_allowed,
                risk_reason=risk_reason,
                risk_friday=risk_friday,
                risk_reopen=risk_reopen,
                policy_shadow_mode=bool(getattr(CFG, "policy_shadow_mode_enabled", True)),
            )
            self._record_section_duration("execution_call", int((time.perf_counter() - exec_call_t0) * 1000.0))
            if not isinstance(reply, dict):
                logging.error(f"HYBRID_DISPATCH_FAIL | No valid reply for symbol={symbol}")
                return None

            status = str(reply.get("status") or "").upper()
            details = reply.get("details")
            if not isinstance(details, dict):
                details = {}

            def _as_int(val: Any, default: int = 0) -> int:
                try:
                    return int(val)
                except Exception:
                    return int(default)

            reject_code = int(getattr(mt5, "TRADE_RETCODE_REJECT", 10006))
            error_code = int(getattr(mt5, "TRADE_RETCODE_ERROR", 10011))

            retcode = _as_int(details.get("retcode"), default=0)
            order = _as_int(details.get("order"), default=0)
            deal = _as_int(details.get("deal"), default=0)
            comment = str(details.get("comment") or reply.get("error") or "")
            request_ctx = reply.get("__request_context") if isinstance(reply.get("__request_context"), dict) else {}
            request_price = float(details.get("request_price", request_ctx.get("request_price", 0.0)) or 0.0)
            executed_price = float(details.get("executed_price", 0.0) or 0.0)
            deviation_requested_points = _as_int(
                details.get("deviation_requested_points"),
                default=_as_int(request_ctx.get("deviation_requested_points"), default=0),
            )
            deviation_effective_points = _as_int(details.get("deviation_effective_points"), default=0)
            point_size = float(details.get("point_size", 0.0) or 0.0)
            tick_size = float(details.get("tick_size", 0.0) or 0.0)

            if status == "PROCESSED":
                if retcode <= 0:
                    retcode = error_code
                logging.info(
                    "HYBRID_DISPATCH_ACK | symbol=%s retcode=%s retcode_str=%s order=%s deal=%s",
                    symbol,
                    retcode,
                    str(details.get("retcode_str") or ""),
                    order,
                    deal,
                )
            elif status == "REJECTED":
                retcode = _as_int(reply.get("retcode"), default=retcode or reject_code)
                if retcode <= 0:
                    retcode = reject_code
                order = 0
                deal = 0
                logging.warning(
                    "HYBRID_DISPATCH_REJECT | symbol=%s retcode=%s comment=%s",
                    symbol,
                    retcode,
                    comment,
                )
            elif status == "SKIPPED":
                retcode = _as_int(
                    reply.get("retcode"),
                    default=retcode or int(getattr(mt5, "TRADE_RETCODE_TRADE_DISABLED", 10017)),
                )
                if retcode <= 0:
                    retcode = int(getattr(mt5, "TRADE_RETCODE_TRADE_DISABLED", 10017))
                order = 0
                deal = 0
                logging.info(
                    "HYBRID_DISPATCH_SKIPPED | symbol=%s retcode=%s reason=%s",
                    symbol,
                    retcode,
                    str(details.get("retcode_str") or "MQL5_ACTIVE_BRIDGE_BYPASS"),
                )
            else:
                retcode = _as_int(reply.get("retcode"), default=retcode or error_code)
                if retcode <= 0:
                    retcode = error_code
                order = 0
                deal = 0
                logging.error(
                    "HYBRID_DISPATCH_ERROR | symbol=%s status=%s comment=%s",
                    symbol,
                    status or "UNKNOWN",
                    comment,
                )

            try:
                done_codes = {
                    int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
                    int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
                    int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008)),
                }
                if int(retcode) in done_codes:
                    self._live_window_trade_counts[grp_u] = int(self._live_window_trade_counts.get(grp_u, 0)) + 1
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            class ResultStub:
                def __init__(
                    self,
                    rc: int,
                    cm: str,
                    ord_id: int,
                    deal_id: int,
                    req_ctx: Dict[str, Any],
                    req_price: float,
                    fill_price: float,
                    dev_req: int,
                    dev_eff: int,
                    point_val: float,
                    tick_val: float,
                ):
                    self.retcode = int(rc)
                    self.comment = str(cm or "")
                    self.order = int(ord_id)
                    self.deal = int(deal_id)
                    self.request_context = dict(req_ctx or {})
                    self.message_id = str(self.request_context.get("message_id") or "")
                    self.command_id = str(self.request_context.get("command_id") or self.message_id)
                    self.request_id = str(self.request_context.get("request_id") or self.message_id)
                    self.symbol_raw = str(self.request_context.get("symbol_raw") or symbol)
                    self.symbol_canonical = str(self.request_context.get("symbol_canonical") or canonical_symbol(symbol))
                    self.request_price = float(req_price or 0.0)
                    self.executed_price = float(fill_price or 0.0)
                    self.deviation_requested_points = int(dev_req)
                    self.deviation_effective_points = int(dev_eff)
                    self.point_size = float(point_val or 0.0)
                    self.tick_size = float(tick_val or 0.0)
                    self.spread_at_decision = self.request_context.get("spread_at_decision")
                    self.spread_unit = str(self.request_context.get("spread_unit") or "UNKNOWN")
                    self.spread_provenance = str(self.request_context.get("spread_provenance") or "UNKNOWN")
                    self.estimated_entry_cost_components = dict(self.request_context.get("estimated_entry_cost_components") or {})
                    self.estimated_round_trip_cost = dict(self.request_context.get("estimated_round_trip_cost") or {})
                    self.cost_feasibility_shadow = self.request_context.get("cost_feasibility_shadow")
                    self.net_cost_feasible = self.request_context.get("net_cost_feasible")
                    self.cost_gate_policy_mode = str(self.request_context.get("cost_gate_policy_mode") or "DIAGNOSTIC_ONLY")
                    self.cost_gate_reason_code = str(self.request_context.get("cost_gate_reason_code") or "NONE")
                    self.timestamp_utc = str(self.request_context.get("timestamp_utc") or "")
                    self.timestamp_semantics = str(self.request_context.get("timestamp_semantics") or "UTC")
                    self.slippage_abs_price = None
                    self.slippage_points = None
                    self.slippage_ticks = None
                    if self.request_price > 0.0 and self.executed_price > 0.0:
                        self.slippage_abs_price = float(abs(self.executed_price - self.request_price))
                    if self.slippage_abs_price is not None and self.point_size > 0.0:
                        self.slippage_points = float(self.slippage_abs_price / self.point_size)
                    if self.slippage_abs_price is not None and self.tick_size > 0.0:
                        self.slippage_ticks = float(self.slippage_abs_price / self.tick_size)
                    self.realized_cost_components = {
                        "spread_component_points": self.spread_at_decision,
                        "slippage_points": self.slippage_points,
                        "slippage_abs_price": self.slippage_abs_price,
                    }
                    self.cost_estimation_quality = "PARTIAL"

            return ResultStub(
                retcode,
                comment,
                order,
                deal,
                request_ctx,
                request_price,
                executed_price,
                deviation_requested_points,
                deviation_effective_points,
                point_size,
                tick_size,
            )

        # Fallback do standardowej kolejki/silnika dla innych akcji (np. SLTP modify)
        if getattr(self, "execution_queue", None) is not None:
            return self.execution_queue.submit(symbol, grp, request, emergency=bool(emergency))
        return self.execution_engine.order_send(symbol, grp, request, emergency=bool(emergency))

    def poll_deals(self):
        # SYS — rzadziej (10 min)
        now_ts = int(time.time())
        last_poll = self.db.get_last_ts("last_deals_poll_ts")
        if now_ts - last_poll < CFG.deals_poll_interval_sec:
            return

        # jeśli SYS budżet słaby — odpuść
        if self.gov.sys_soft_mode():
            self.db.set_last_ts("last_deals_poll_ts", now_ts)
            return

        from_ts = last_poll if last_poll > 0 else now_ts - 3600
        from_dt = dt.datetime.fromtimestamp(from_ts, tz=UTC)
        to_dt = dt.datetime.fromtimestamp(now_ts, tz=UTC)

        deals = self.execution_engine.history_deals_get(from_dt, to_dt)
        self.db.set_last_ts("last_deals_poll_ts", now_ts)
        if not deals:
            return

        for d in deals:
            try:
                if int(getattr(d, "magic", 0)) != int(CFG.magic_number):
                    continue
                ticket = int(getattr(d, "ticket", 0))
                tsec = int(getattr(d, "time", 0))
                sym = str(getattr(d, "symbol", ""))
                grp = guess_group(sym)
                profit = float(getattr(d, "profit", 0.0))
                commission = float(getattr(d, "commission", 0.0))
                swap = float(getattr(d, "swap", 0.0))
                fee = float(getattr(d, "fee", 0.0) or getattr(d, "fees", 0.0) or 0.0)
                # Map deal -> decision event via order comment (SBOT-EVT-<id>)
                try:
                    comment = str(getattr(d, "comment", "") or "")
                    m = re.search(r"EVT[-=]([0-9a-fA-F]{6,})", comment)
                    if m and hasattr(self, "decision_store") and self.decision_store is not None:
                        eid = m.group(1)
                        self.decision_store.apply_deal(eid, profit, commission, swap, fee, dt.datetime.fromtimestamp(tsec, tz=UTC).replace(microsecond=0).isoformat().replace("+00:00","Z"))
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                self.db.upsert_deal(ticket, tsec, grp, sym, profit, commission, swap)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                continue

    def positions_snapshot(self, mode_global: str, force: bool = False) -> Dict[str, List]:
        """Snapshot pozycji.
        V1.10: jeśli mamy otwarte pozycje (cache) -> wymuszamy minimalny cykl nadzoru (open_positions_guard_sec),
        nawet w ECO, aby nie zostawić pozycji bez opieki.
        """
        now_ts = int(time.time())
        last = self.db.get_last_ts("last_positions_poll_ts")
        period = self.ctrl.positions_poll_period(mode_global)

        # jeśli mamy otwarte pozycje z poprzedniego snapshotu -> strażnik skraca okres
        if self._positions_cache:
            period = min(int(period), int(CFG.open_positions_guard_sec))

        # w force-close window / krytycznych oknach możemy wymusić odświeżenie (z rezerwy SYS)
        if force:
            period = 0

        if now_ts - last < period:
            return dict(self._positions_cache)

        pos = self.execution_engine.positions_get(emergency=bool(force))
        if pos is None:
            # jeśli nie możemy pobrać (brak budżetu SYS), zwróć cache (lepsze to niż nic)
            return dict(self._positions_cache)

        self.db.set_last_ts("last_positions_poll_ts", now_ts)

        prev_map = dict(self._positions_cache)
        m: Dict[str, List] = {}
        if pos:
            for p in pos:
                m.setdefault(p.symbol, []).append(p)

        try:
            def _tickets(src: Dict[str, List]) -> set[int]:
                out: set[int] = set()
                for vals in src.values():
                    for pp in vals:
                        try:
                            out.add(int(getattr(pp, "ticket", 0) or 0))
                        except Exception:
                            continue
                return out
            prev_t = _tickets(prev_map)
            now_t = _tickets(m)
            if prev_t != now_t:
                added = sorted(x for x in (now_t - prev_t) if int(x) > 0)
                removed = sorted(x for x in (prev_t - now_t) if int(x) > 0)
                logging.info(
                    "RECONCILE_POSITIONS changed=%s added=%s removed=%s prev_total=%s now_total=%s",
                    int(bool(added or removed)),
                    int(len(added)),
                    int(len(removed)),
                    int(len(prev_t)),
                    int(len(now_t)),
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        self._positions_cache = dict(m)
        return dict(self._positions_cache)

    def pending_snapshot(self, mode_global: str, force: bool = False) -> Dict[str, List]:
        """Dedicated pending-orders reconciliation loop.

        WHY: positions reconcile alone does not detect pending-order drift.
        This loop tracks pending ticket lifecycle and logs deterministic deltas.
        """
        now_ts = int(time.time())
        base_period = max(1, int(getattr(CFG, "pending_reconcile_poll_sec", 60)))
        force_period = max(1, int(getattr(CFG, "pending_reconcile_force_poll_sec", 20)))
        period = int(force_period if force else base_period)
        if self._pending_cache:
            period = min(int(period), int(max(1, CFG.open_positions_guard_sec)))
        last = self.db.get_last_ts("last_pending_poll_ts")
        if now_ts - int(last) < int(period):
            return dict(self._pending_cache)

        ords = self.execution_engine.orders_get(emergency=bool(force))
        if ords is None:
            return dict(self._pending_cache)

        self.db.set_last_ts("last_pending_poll_ts", now_ts)
        pending_types = {
            getattr(mt5, "ORDER_TYPE_BUY_LIMIT", None),
            getattr(mt5, "ORDER_TYPE_SELL_LIMIT", None),
            getattr(mt5, "ORDER_TYPE_BUY_STOP", None),
            getattr(mt5, "ORDER_TYPE_SELL_STOP", None),
            getattr(mt5, "ORDER_TYPE_BUY_STOP_LIMIT", None),
            getattr(mt5, "ORDER_TYPE_SELL_STOP_LIMIT", None),
        }
        pending_types = {t for t in pending_types if t is not None}
        current: Dict[str, List] = {}
        if ords:
            for o in ords:
                try:
                    if int(getattr(o, "type", -1)) not in pending_types:
                        continue
                    sym = str(getattr(o, "symbol", "") or "")
                    if not sym:
                        continue
                    current.setdefault(sym, []).append(o)
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    continue

        try:
            def _pending_tickets(src: Dict[str, List]) -> set[int]:
                out: set[int] = set()
                for vals in src.values():
                    for oo in vals:
                        try:
                            out.add(int(getattr(oo, "ticket", 0) or 0))
                        except Exception:
                            continue
                return out

            prev_t = _pending_tickets(self._pending_cache)
            now_t = _pending_tickets(current)
            if prev_t != now_t:
                added = sorted(x for x in (now_t - prev_t) if int(x) > 0)
                removed = sorted(x for x in (prev_t - now_t) if int(x) > 0)
                logging.info(
                    "RECONCILE_PENDING changed=%s added=%s removed=%s prev_total=%s now_total=%s",
                    int(bool(added or removed)),
                    int(len(added)),
                    int(len(removed)),
                    int(len(prev_t)),
                    int(len(now_t)),
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        self._pending_cache = dict(current)
        return dict(self._pending_cache)

    def _effective_mode_for_symbol(self, grp: str, sym: str, global_mode: str, rollover_safe: bool) -> str:
        mode = str(global_mode).upper()
        try:
            local_mode = str(self.ctrl.mode(grp, sym, rollover_safe)).upper()
            mode_rank = {"ECO": 0, "WARM": 1, "HOT": 2}
            if mode in mode_rank and local_mode in mode_rank:
                mode = local_mode if mode_rank[local_mode] <= mode_rank[mode] else mode
            elif local_mode in mode_rank:
                mode = local_mode
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return str(mode).upper()

    def _manage_adaptive_exits(self, positions_map: Dict[str, List], global_mode: str, rollover_safe: bool) -> None:
        """Apply trailing SL and one-shot partial TP for our open positions."""
        if mt5 is None:
            return
        if not positions_map:
            return
        if (not bool(getattr(CFG, "trailing_stop_enabled", True))) and (not bool(getattr(CFG, "partial_tp_enabled", True))):
            return

        now_ts = int(time.time())
        trail_retry_sec_base = max(1, int(getattr(CFG, "trailing_update_retry_sec", 60)))
        partial_retry_sec_base = max(1, int(getattr(CFG, "partial_tp_retry_sec", 120)))
        only_magic = bool(getattr(CFG, "position_time_stop_only_magic", True))
        trailing_activation_r_base = float(max(0.0, float(getattr(CFG, "trailing_activation_r", 0.8))))
        trailing_atr_mult_base = float(max(0.1, float(getattr(CFG, "trailing_atr_mult", 1.0))))
        partial_tp_r_base = float(max(0.1, float(getattr(CFG, "partial_tp_r", 1.0))))
        partial_fraction_base = float(min(0.95, max(0.05, float(getattr(CFG, "partial_tp_fraction", 0.5)))))

        open_tickets: Dict[int, bool] = {}

        for sym, positions in positions_map.items():
            if not positions:
                continue
            grp = guess_group(sym)
            trail_retry_sec = max(1, _cfg_group_int(grp, "trailing_update_retry_sec", trail_retry_sec_base, symbol=sym))
            partial_retry_sec = max(1, _cfg_group_int(grp, "partial_tp_retry_sec", partial_retry_sec_base, symbol=sym))
            trailing_activation_r = float(
                max(0.0, _cfg_group_float(grp, "trailing_activation_r", trailing_activation_r_base, symbol=sym))
            )
            trailing_atr_mult = float(
                max(0.1, _cfg_group_float(grp, "trailing_atr_mult", trailing_atr_mult_base, symbol=sym))
            )
            partial_tp_r = float(max(0.1, _cfg_group_float(grp, "partial_tp_r", partial_tp_r_base, symbol=sym)))
            partial_fraction = float(
                min(0.95, max(0.05, _cfg_group_float(grp, "partial_tp_fraction", partial_fraction_base, symbol=sym)))
            )
            trailing_enabled = _cfg_group_bool(
                grp, "trailing_stop_enabled", bool(getattr(CFG, "trailing_stop_enabled", True)), symbol=sym
            )
            partial_enabled = _cfg_group_bool(
                grp, "partial_tp_enabled", bool(getattr(CFG, "partial_tp_enabled", True)), symbol=sym
            )
            close_dev = int(
                max(
                    1,
                    _cfg_group_int(
                        grp,
                        "position_time_stop_deviation_points",
                        int(getattr(CFG, "position_time_stop_deviation_points", 30)),
                        symbol=sym,
                    ),
                )
            )
            info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
            if info is None:
                continue
            point = float(getattr(info, "point", 0.0) or 0.0)
            if point <= 0.0:
                point = 1e-5
            vol_min = float(getattr(info, "volume_min", 0.0) or 0.0)
            vol_step = float(getattr(info, "volume_step", 0.0) or 0.0)

            ind = None
            try:
                ind = self.strategy.last_indicators.get(symbol_base(sym))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                ind = None
            atr_value = None
            if isinstance(ind, dict):
                try:
                    atr_raw = float(ind.get("atr", 0.0) or 0.0)
                    if np.isfinite(atr_raw) and atr_raw > 0.0:
                        atr_value = atr_raw
                except Exception:
                    atr_value = None

            for pos in positions:
                try:
                    ticket = int(getattr(pos, "ticket", 0) or 0)
                except Exception:
                    ticket = 0
                if ticket <= 0:
                    continue
                open_tickets[ticket] = True

                if only_magic:
                    try:
                        if int(getattr(pos, "magic", 0) or 0) != int(CFG.magic_number):
                            continue
                    except Exception:
                        continue

                pos_type = int(getattr(pos, "type", -1) or -1)
                if pos_type == getattr(mt5, "ORDER_TYPE_BUY", -999):
                    close_side = int(getattr(mt5, "ORDER_TYPE_SELL", -1))
                    tick = self.execution_engine.tick(sym, grp, emergency=False)
                    mkt = float(getattr(tick, "bid", 0.0) or 0.0) if tick is not None else 0.0
                    direction = 1.0
                elif pos_type == getattr(mt5, "ORDER_TYPE_SELL", -999):
                    close_side = int(getattr(mt5, "ORDER_TYPE_BUY", -1))
                    tick = self.execution_engine.tick(sym, grp, emergency=False)
                    mkt = float(getattr(tick, "ask", 0.0) or 0.0) if tick is not None else 0.0
                    direction = -1.0
                else:
                    continue
                if mkt <= 0.0:
                    continue

                entry = float(getattr(pos, "price_open", 0.0) or 0.0)
                if entry <= 0.0:
                    continue
                current_sl = float(getattr(pos, "sl", 0.0) or 0.0)
                current_tp = float(getattr(pos, "tp", 0.0) or 0.0)
                pos_volume = float(getattr(pos, "volume", 0.0) or 0.0)
                if pos_volume <= 0.0:
                    continue

                risk_dist = abs(entry - current_sl)
                if risk_dist <= 0.0:
                    fallback_sl_pts = int(max(1, int(getattr(CFG, "fixed_sl_points", 1) or 1)))
                    risk_dist = float(fallback_sl_pts) * float(point)
                if atr_value is not None and atr_value > 0.0:
                    risk_dist = max(risk_dist, 0.5 * float(atr_value))

                favorable_move = (mkt - entry) if direction > 0 else (entry - mkt)
                if favorable_move <= 0.0:
                    continue

                if bool(partial_enabled) and (ticket not in self._partial_tp_done_tickets):
                    last_partial_try = int(self._partial_close_attempt_ts.get(ticket, 0) or 0)
                    if (now_ts - last_partial_try) >= partial_retry_sec and favorable_move >= (partial_tp_r * risk_dist):
                        part_vol = partial_close_volume(pos_volume, partial_fraction, vol_min, vol_step)
                        if part_vol > 0.0 and part_vol < pos_volume:
                            req = {
                                "action": mt5.TRADE_ACTION_DEAL,
                                "symbol": sym,
                                "volume": float(part_vol),
                                "type": int(close_side),
                                "position": int(ticket),
                                "price": float(mkt),
                                "deviation": int(close_dev),
                                "magic": CFG.magic_number,
                                "comment": "PARTIAL_TP",
                                "type_time": mt5.ORDER_TIME_GTC,
                                "type_filling": mt5.ORDER_FILLING_IOC,
                            }
                            self._partial_close_attempt_ts[ticket] = now_ts
                            res = self._dispatch_order(sym, grp, req, emergency=False)
                            ok = bool(res and getattr(res, "retcode", None) == mt5.TRADE_RETCODE_DONE)
                            if ok:
                                self._partial_tp_done_tickets[ticket] = True
                                logging.info(
                                    f"PARTIAL_TP_DONE symbol={sym} ticket={ticket} volume={part_vol:.4f} "
                                    f"move={favorable_move:.6f} risk={risk_dist:.6f}"
                                )
                            else:
                                logging.warning(
                                    f"PARTIAL_TP_FAIL symbol={sym} ticket={ticket} volume={part_vol:.4f} "
                                    f"retcode={getattr(res, 'retcode', None)} comment={getattr(res, 'comment', '')}"
                                )

                if not bool(trailing_enabled):
                    continue
                last_trail_try = int(self._trail_update_attempt_ts.get(ticket, 0) or 0)
                if (now_ts - last_trail_try) < trail_retry_sec:
                    continue
                if favorable_move < (trailing_activation_r * risk_dist):
                    continue

                trail_dist = float(risk_dist)
                if atr_value is not None and atr_value > 0.0:
                    trail_dist = max(float(risk_dist) * 0.5, float(atr_value) * trailing_atr_mult)
                desired_sl = (mkt - trail_dist) if direction > 0 else (mkt + trail_dist)
                improve = False
                if direction > 0:
                    improve = (current_sl <= 0.0) or (desired_sl > (current_sl + point))
                else:
                    improve = (current_sl <= 0.0) or (desired_sl < (current_sl - point))
                if not improve:
                    continue

                req_mod = {
                    "action": mt5.TRADE_ACTION_SLTP,
                    "symbol": sym,
                    "position": int(ticket),
                    "sl": float(desired_sl),
                    "tp": float(current_tp) if current_tp > 0.0 else 0.0,
                    "magic": CFG.magic_number,
                    "comment": "TRAIL_ATR",
                }
                self._trail_update_attempt_ts[ticket] = now_ts
                res_mod = self._dispatch_order(sym, grp, req_mod, emergency=False)
                ok_mod = bool(res_mod and getattr(res_mod, "retcode", None) in (
                    mt5.TRADE_RETCODE_DONE,
                    mt5.TRADE_RETCODE_PLACED,
                ))
                if ok_mod:
                    logging.info(
                        f"TRAIL_UPDATE_DONE symbol={sym} ticket={ticket} sl_old={current_sl:.6f} "
                        f"sl_new={desired_sl:.6f} move={favorable_move:.6f}"
                    )
                else:
                    logging.warning(
                        f"TRAIL_UPDATE_FAIL symbol={sym} ticket={ticket} sl_new={desired_sl:.6f} "
                        f"retcode={getattr(res_mod, 'retcode', None)} comment={getattr(res_mod, 'comment', '')}"
                    )

        if open_tickets:
            to_drop = [t for t in self._partial_tp_done_tickets.keys() if int(t) not in open_tickets]
            for t in to_drop:
                self._partial_tp_done_tickets.pop(t, None)
                self._partial_close_attempt_ts.pop(t, None)
                self._trail_update_attempt_ts.pop(t, None)
        else:
            self._partial_tp_done_tickets.clear()
            self._partial_close_attempt_ts.clear()
            self._trail_update_attempt_ts.clear()

    def _close_stale_positions(self, positions_map: Dict[str, List], global_mode: str, rollover_safe: bool) -> None:
        if mt5 is None:
            return
        if not bool(getattr(CFG, "position_time_stop_enabled", True)):
            return
        if not positions_map:
            return

        now_ts = int(time.time())
        retry_sec = max(1, int(getattr(CFG, "position_time_stop_retry_sec", 120)))
        only_magic = bool(getattr(CFG, "position_time_stop_only_magic", True))
        for sym, positions in positions_map.items():
            if not positions:
                continue
            grp = guess_group(sym)
            deviation = int(
                max(
                    1,
                    _cfg_group_int(
                        grp,
                        "position_time_stop_deviation_points",
                        int(
                            getattr(
                                CFG,
                                "position_time_stop_deviation_points",
                                getattr(CFG, "kill_close_deviation_points", 30),
                            )
                        ),
                        symbol=sym,
                    ),
                )
            )
            mode = self._effective_mode_for_symbol(grp, symbol_base(sym), global_mode, rollover_safe)
            max_hold_min = position_time_stop_minutes_for_mode(mode, grp=grp, symbol=sym)
            if max_hold_min <= 0:
                continue
            max_hold_sec = int(max_hold_min) * 60
            cnt_total = 0
            cnt_skip_retry = 0
            cnt_skip_magic = 0
            cnt_skip_age = 0
            cnt_skip_type = 0
            cnt_skip_notick = 0
            cnt_skip_vol = 0
            cnt_stale_due = 0
            cnt_attempt = 0
            cnt_done = 0
            cnt_fail = 0

            for pos in positions:
                cnt_total += 1
                try:
                    ticket = int(getattr(pos, "ticket", 0) or 0)
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    ticket = 0
                if ticket > 0:
                    last_try = int(self._position_close_attempt_ts.get(ticket, 0) or 0)
                    if (now_ts - last_try) < retry_sec:
                        cnt_skip_retry += 1
                        continue

                if only_magic:
                    try:
                        magic = int(getattr(pos, "magic", 0) or 0)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        magic = 0
                    if magic != int(CFG.magic_number):
                        cnt_skip_magic += 1
                        continue

                age_s = position_age_sec(pos, now_ts=now_ts)
                if age_s is None or int(age_s) < int(max_hold_sec):
                    cnt_skip_age += 1
                    continue
                cnt_stale_due += 1

                pos_type = int(getattr(pos, "type", -1) or -1)
                if pos_type == getattr(mt5, "ORDER_TYPE_BUY", -999):
                    close_type = getattr(mt5, "ORDER_TYPE_SELL", None)
                    side_price = float(getattr(self.execution_engine.tick(sym, grp, emergency=False), "bid", 0.0) or 0.0)
                elif pos_type == getattr(mt5, "ORDER_TYPE_SELL", -999):
                    close_type = getattr(mt5, "ORDER_TYPE_BUY", None)
                    side_price = float(getattr(self.execution_engine.tick(sym, grp, emergency=False), "ask", 0.0) or 0.0)
                else:
                    cnt_skip_type += 1
                    continue
                if close_type is None or side_price <= 0.0:
                    cnt_skip_notick += 1
                    logging.warning(
                        f"TIME_STOP_CLOSE_SKIP symbol={sym} ticket={ticket} reason=NO_TICK_OR_TYPE age_s={int(age_s)}"
                    )
                    continue

                vol = float(getattr(pos, "volume", 0.0) or 0.0)
                if vol <= 0.0:
                    cnt_skip_vol += 1
                    continue

                req = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": sym,
                    "volume": float(vol),
                    "type": int(close_type),
                    "position": int(ticket),
                    "price": float(side_price),
                    "deviation": int(deviation),
                    "magic": CFG.magic_number,
                    "comment": f"TIME_STOP_{mode}",
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": mt5.ORDER_FILLING_IOC,
                }

                cnt_attempt += 1
                if ticket > 0:
                    self._position_close_attempt_ts[ticket] = now_ts
                res = self._dispatch_order(sym, grp, req, emergency=False)
                ok = bool(res and getattr(res, "retcode", None) == mt5.TRADE_RETCODE_DONE)
                if ok:
                    cnt_done += 1
                    logging.warning(
                        f"TIME_STOP_CLOSE_DONE symbol={sym} ticket={ticket} age_s={int(age_s)} mode={mode} hold_min={int(max_hold_min)}"
                    )
                else:
                    cnt_fail += 1
                    logging.warning(
                        f"TIME_STOP_CLOSE_FAIL symbol={sym} ticket={ticket} age_s={int(age_s)} mode={mode} "
                        f"retcode={getattr(res, 'retcode', None)} comment={getattr(res, 'comment', '')}"
                    )
            if cnt_total > 0:
                logging.info(
                    f"TIME_STOP_AUDIT symbol={sym} mode={mode} hold_min={int(max_hold_min)} total={cnt_total} "
                    f"skip_magic={cnt_skip_magic} skip_age={cnt_skip_age} skip_retry={cnt_skip_retry} "
                    f"skip_type={cnt_skip_type} skip_notick={cnt_skip_notick} skip_vol={cnt_skip_vol} "
                    f"stale_due={cnt_stale_due} attempt={cnt_attempt} done={cnt_done} fail={cnt_fail}"
                )
            # Safety fallback: stale positions detected, but regular close path made no attempts.
            if cnt_stale_due > 0 and cnt_attempt == 0:
                try:
                    logging.warning(
                        f"TIME_STOP_FALLBACK_TRIGGER symbol={sym} stale_due={cnt_stale_due} "
                        f"reason=no_regular_close_attempt"
                    )
                    ok_flat = bool(
                        self.execution_engine.force_flat_symbol(
                            symbol=sym,
                            db=self.db,
                            retries=max(1, int(CFG.close_retries)),
                            delay=float(CFG.close_retry_delay_sec),
                            deviation=int(deviation),
                        )
                    )
                    logging.warning(
                        f"TIME_STOP_FALLBACK_RESULT symbol={sym} stale_due={cnt_stale_due} ok={int(ok_flat)}"
                    )
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _collect_black_swan_inputs(self) -> Tuple[Dict[str, float], Dict[str, float]]:
        vols: Dict[str, float] = {}
        spreads: Dict[str, float] = {}
        for raw, sym, _grp in self.universe:
            key = str(raw)
            ind = self.strategy.last_indicators.get(key) if hasattr(self.strategy, "last_indicators") else None
            if isinstance(ind, dict):
                try:
                    close = float(ind.get("close", 0.0))
                    atr = float(ind.get("atr", 0.0))
                    if np.isfinite(close) and np.isfinite(atr) and close > 0.0 and atr > 0.0:
                        vols[key] = float(atr / close)
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

            try:
                cached = self.execution_engine._sym_info_cache.get(sym) if hasattr(self.execution_engine, "_sym_info_cache") else None
                info = cached[1] if isinstance(cached, tuple) and len(cached) == 2 else None
                if info is not None:
                    spread = float(getattr(info, "spread", 0.0) or 0.0)
                    if np.isfinite(spread) and spread > 0.0:
                        spreads[key] = float(spread)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return vols, spreads

    def _build_black_swan_v2_snapshot(
        self,
        vols: Dict[str, float],
        spreads: Dict[str, float],
    ) -> BlackSwanMarketSnapshotV2:
        now_wall = float(time.time())
        now_mono = float(time.perf_counter())

        vol_values = [float(v) for v in (vols or {}).values() if np.isfinite(float(v))]
        spread_values = [float(v) for v in (spreads or {}).values() if np.isfinite(float(v))]
        vol_score = float(np.mean(vol_values)) if vol_values else float(self.black_swan_guard.baseline.mean_volatility)
        spread_points = float(np.mean(spread_values)) if spread_values else float(self.black_swan_guard.baseline.mean_spread)
        if spread_points < 0.0:
            spread_points = 0.0

        bridge_wait_arr = list((self._loop_section_durations_ms.get("bridge_wait") or []))
        bridge_wait_ms = float(self._percentile_int(bridge_wait_arr, 0.95)) if bridge_wait_arr else 0.0

        heartbeat_age_ms = 0.0
        if float(self._last_heartbeat_ok_ts) > 0.0:
            heartbeat_age_ms = max(0.0, (now_wall - float(self._last_heartbeat_ok_ts)) * 1000.0)

        micro_rows = list((self._micro_tick_state or {}).values())
        tick_gap_ms = 0.0
        price_jump_points = 0.0
        tick_rate_per_sec = 0.0
        stale_tick_flag = False
        burst_flag = False
        ask_lt_bid_flag = False
        if micro_rows:
            tick_gaps = [
                float(r.get("tick_gap_sec"))
                for r in micro_rows
                if r.get("tick_gap_sec") is not None and np.isfinite(float(r.get("tick_gap_sec")))
            ]
            tick_gap_ms = (max(tick_gaps) * 1000.0) if tick_gaps else 0.0
            jumps = [
                float(r.get("price_jump_points"))
                for r in micro_rows
                if r.get("price_jump_points") is not None and np.isfinite(float(r.get("price_jump_points")))
            ]
            price_jump_points = max(jumps) if jumps else 0.0
            rates = [
                float(r.get("tick_rate_1s"))
                for r in micro_rows
                if r.get("tick_rate_1s") is not None and np.isfinite(float(r.get("tick_rate_1s")))
            ]
            tick_rate_per_sec = float(np.mean(rates)) if rates else 0.0
            stale_tick_flag = any(bool(r.get("stale_tick_flag", False)) for r in micro_rows)
            burst_flag = any(bool(r.get("burst_flag", False)) for r in micro_rows)
            ask_lt_bid_flag = any(bool(r.get("ask_lt_bid", False)) for r in micro_rows)

        reject_ratio = float((self._live_guard_snapshot or {}).get("reject_ratio", 0.0) or 0.0)
        reject_samples = int((self._live_guard_snapshot or {}).get("reject_samples", 0) or 0)
        if reject_ratio < 0.0:
            reject_ratio = 0.0
        reject_count_recent = int(round(reject_ratio * float(max(1, reject_samples))))

        spread_baseline = float(self.black_swan_guard.baseline.mean_spread or 0.0)
        spread_ratio = (spread_points / spread_baseline) if spread_baseline > 0.0 else 1.0
        liquidity_score = 1.0 / (1.0 + max(0.0, spread_ratio - 1.0))
        if stale_tick_flag:
            liquidity_score = min(liquidity_score, 0.20)
        liquidity_score = max(0.0, min(1.0, float(liquidity_score)))

        slippage_points = max(0.0, float(self._last_trade_slippage_points or 0.0))

        return BlackSwanMarketSnapshotV2(
            ts_monotonic=now_mono,
            symbol="__GLOBAL__",
            volatility_score=vol_score,
            spread_points=float(spread_points),
            slippage_points=slippage_points,
            liquidity_score=liquidity_score,
            tick_rate_per_sec=float(max(0.0, tick_rate_per_sec)),
            tick_gap_ms=float(max(0.0, tick_gap_ms)),
            price_jump_points=float(max(0.0, price_jump_points)),
            bridge_wait_ms=float(max(0.0, bridge_wait_ms)),
            heartbeat_age_ms=float(max(0.0, heartbeat_age_ms)),
            reject_count_recent=int(max(0, reject_count_recent)),
            stale_tick_flag=bool(stale_tick_flag),
            burst_flag=bool(burst_flag),
            ask_lt_bid_flag=bool(ask_lt_bid_flag),
        )

    def _evaluate_black_swan(self):
        vols, spreads = self._collect_black_swan_inputs()
        min_vol = max(0, int(getattr(CFG, "black_swan_min_vol_samples", 1)))
        if len(vols) < min_vol:
            thr = max(0.0, float(getattr(CFG, "black_swan_threshold", 0.0)))
            prec = max(0.0, float(thr * float(getattr(CFG, "black_swan_precaution_fraction", 0.8))))
            signal = BlackSwanSignal(
                stress_index=0.0,
                threshold=float(thr),
                precaution_threshold=float(prec),
                precaution=False,
                black_swan=False,
                reasons=("INSUFFICIENT_VOL_DATA",),
            )
            logging.info(
                f"BLACK_SWAN stress={signal.stress_index:.3f} thr={signal.threshold:.3f} "
                f"prec_thr={signal.precaution_threshold:.3f} black_swan={int(signal.black_swan)} "
                f"precaution={int(signal.precaution)} n_vol={len(vols)} n_spread={len(spreads)} "
                f"reason={','.join(signal.reasons)}"
            )
            base_signal = signal
        else:
            base_signal = self.black_swan_guard.evaluate(vols, spreads)
            logging.info(
                f"BLACK_SWAN stress={base_signal.stress_index:.3f} thr={base_signal.threshold:.3f} "
                f"prec_thr={base_signal.precaution_threshold:.3f} black_swan={int(base_signal.black_swan)} "
                f"precaution={int(base_signal.precaution)} n_vol={len(vols)} n_spread={len(spreads)} "
                f"reason={','.join(base_signal.reasons)}"
            )

        self._black_swan_v2_last_decision = None
        self._black_swan_block_new_entries = False
        self._black_swan_v2_reason = "NONE"
        self._black_swan_v2_state = "NORMAL"
        self._black_swan_v2_action = "ALLOW"

        v2_enabled = bool(getattr(CFG, "black_swan_v2_enabled", True))
        if not v2_enabled or self.black_swan_guard_v2 is None:
            return base_signal

        try:
            snap = self._build_black_swan_v2_snapshot(vols, spreads)
            v2 = self.black_swan_guard_v2.evaluate(snap)
            self._black_swan_v2_last_decision = v2
            self._black_swan_v2_state = str(v2.state.value)
            self._black_swan_v2_action = str(v2.action.value)
            self._black_swan_v2_reason = str(v2.dominant_reason or "NONE")
            self._black_swan_block_new_entries = bool(
                v2.action in (
                    BlackSwanGuardActionV2.BLOCK_NEW_TRADES,
                    BlackSwanGuardActionV2.CLOSE_ONLY,
                    BlackSwanGuardActionV2.FORCE_FLAT,
                )
            )
            logging.info(
                "BLACK_SWAN_V2 state=%s action=%s trigger=%s stress=%.3f cooldown_s=%.1f reason=%s warm=%s block_new=%s",
                str(v2.state.value),
                str(v2.action.value),
                str(v2.trigger.value),
                float(v2.stress_score),
                float(v2.cooldown_remaining_sec),
                str(v2.dominant_reason),
                int(bool(v2.warm)),
                int(bool(self._black_swan_block_new_entries)),
            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            return base_signal

        # v2 guard is advisory-only in runtime path; it can block new entries but
        # does not autonomously escalate to force-flat execution.
        merged_black_swan = bool(base_signal.black_swan)
        merged_precaution = bool(
            base_signal.precaution
            or self._black_swan_v2_state in {"CAUTION", "DEFENSIVE", "CLOSE_ONLY"}
        )
        merged_reasons = tuple(
            dict.fromkeys(
                list(base_signal.reasons)
                + [f"V2_STATE_{self._black_swan_v2_state}", f"V2_ACTION_{self._black_swan_v2_action}"]
                + [str(self._black_swan_v2_reason)]
            ).keys()
        )
        merged_stress = float(max(float(base_signal.stress_index), float(getattr(v2, "stress_score", 0.0))))
        return BlackSwanSignal(
            stress_index=merged_stress,
            threshold=float(base_signal.threshold),
            precaution_threshold=float(base_signal.precaution_threshold),
            precaution=bool(merged_precaution),
            black_swan=bool(merged_black_swan),
            reasons=merged_reasons,
        )

    def _evaluate_self_heal(self):
        now_ts = int(time.time())
        try:
            limit = int(max(1, int(getattr(CFG, "self_heal_recent_deals_limit", 64))))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            limit = 64

        deals_desc = self.db.recent_deals_for_self_heal(limit=limit)
        signal = self.self_heal_guard.evaluate(deals_desc=deals_desc, now_ts=now_ts)

        logging.info(
            f"SELF_HEAL active={int(signal.active)} deals={signal.deals_in_window} "
            f"streak={signal.loss_streak} net_pnl={signal.net_pnl:.2f} "
            f"reasons={','.join(signal.reasons)}"
        )

        if not signal.active:
            return signal

        try:
            current_until = int(self.db.get_global_backoff_until_ts())
            backoff_until = int(now_ts + int(max(1, signal.backoff_seconds)))
            if backoff_until > current_until:
                reason = f"self_heal:{','.join(signal.reasons)}"
                self.db.set_global_backoff(until_ts=backoff_until, reason=reason)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        try:
            cooldown_s = int(max(1, signal.symbol_cooldown_seconds))
            for sym in signal.streak_symbols:
                if not sym:
                    continue
                self.db.set_cooldown(str(sym), cooldown_s, "self_heal_streak")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return signal

    def _read_learner_qa_light(self) -> str:
        """Read optional anti-overfit light from META/learner_advice.json."""
        p = self.meta_dir / "learner_advice.json"
        if not p.exists():
            return "UNKNOWN"
        try:
            obj = _safe_read_json(p)
            if not isinstance(obj, dict):
                return "UNKNOWN"
            ts_raw = str(obj.get("ts_utc") or "").strip()
            if ts_raw.endswith("Z"):
                ts_raw = ts_raw[:-1] + "+00:00"
            ts = dt.datetime.fromisoformat(ts_raw) if ts_raw else None
            if ts is not None and ts.tzinfo is None:
                ts = ts.replace(tzinfo=UTC)
            if ts is not None:
                ts = ts.astimezone(UTC)
            ttl = int(obj.get("ttl_sec") or 0)
            if ts is None or ttl <= 0:
                return "UNKNOWN"
            wall_now_utc = dt.datetime.now(tz=UTC)
            age = (wall_now_utc - ts).total_seconds()
            if age < -5.0:
                return "UNKNOWN"
            age = max(0.0, float(age))
            if age > float(ttl):
                return "UNKNOWN"
            qa = str(obj.get("qa_light") or "").strip().upper()
            if qa in {"GREEN", "YELLOW", "RED"}:
                return qa
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return "UNKNOWN"

    def _evaluate_canary_rollout(self):
        now_ts = int(time.time())
        try:
            promoted = str(self.db.state_get("canary_rollout_promoted", "0")).strip() == "1"
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            promoted = False
        try:
            recent_limit = max(64, int(CFG.canary_promote_min_deals) * 4)
            deals_desc = self.db.recent_deals_for_self_heal(limit=recent_limit)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            deals_desc = []
        err_cnt = 0
        try:
            if self.incident_journal is not None:
                cnt = self.incident_journal.recent_counts(lookback_sec=int(CFG.canary_lookback_sec))
                err_cnt = int(cnt.get("error_or_worse") or 0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            err_cnt = 0

        signal = self.canary_guard.evaluate(
            deals_desc=deals_desc,
            now_ts=now_ts,
            promoted_state=bool(promoted),
            incident_error_count=int(err_cnt),
        )
        if signal.promoted_now:
            try:
                self.db.state_set("canary_rollout_promoted", "1")
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        logging.info(
            f"CANARY active={int(signal.canary_active)} promoted={int(signal.promoted)} "
            f"pause={int(signal.pause)} deals={signal.deals_in_window} streak={signal.loss_streak} "
            f"net_pnl={signal.net_pnl:.2f} errors={signal.error_incidents} reasons={','.join(signal.reasons)}"
        )
        if signal.pause and signal.backoff_seconds > 0:
            try:
                until = int(now_ts + int(signal.backoff_seconds))
                self.db.set_global_backoff(until_ts=until, reason=f"canary:{','.join(signal.reasons)}")
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return signal

    def _evaluate_drift(self):
        try:
            n = int(CFG.drift_baseline_window) + int(CFG.drift_recent_window) + 40
            deals_desc = self.db.recent_deals_for_self_heal(limit=max(40, n))
            vals = [float(pnl) for (_t, _s, pnl) in reversed(deals_desc)]
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            vals = []

        signal = self.drift_guard.evaluate(vals)
        logging.info(
            f"DRIFT active={int(signal.active)} n={signal.samples} "
            f"mu_base={signal.baseline_mean:.6f} mu_recent={signal.recent_mean:.6f} "
            f"drop={signal.mean_drop:.6f} z={signal.zscore:.3f} reasons={','.join(signal.reasons)}"
        )
        if signal.active and signal.backoff_seconds > 0:
            try:
                now_ts = int(time.time())
                until = int(now_ts + int(signal.backoff_seconds))
                self.db.set_global_backoff(until_ts=until, reason=f"drift:{','.join(signal.reasons)}")
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return signal

    # -------------------------------------------------------------------------
    # Trade windows (P0): OFF/ACTIVE/CLOSEOUT routing
    # -------------------------------------------------------------------------
    def _trade_window_off_maintenance(self, ctx: Dict[str, object]) -> None:
        """Outside windows: do not scan or pull prices.

        We still do low-frequency SYS reconciliation to detect unexpected open positions/orders
        and, if needed, perform emergency closeout (safety > no-ops).
        """
        try:
            off_poll = int(getattr(CFG, "trade_off_sys_poll_sec", 900))
        except Exception:
            off_poll = 900
        off_poll = max(60, int(off_poll))

        now_ts = int(time.time())
        last = int(self.db.get_last_ts("last_trade_window_off_sys_ts") or 0)
        if (now_ts - last) < int(off_poll):
            return
        self.db.set_last_ts("last_trade_window_off_sys_ts", now_ts)

        # Minimal SYS snapshot: if anything is open, close it (emergency).
        # Outside trading windows use emergency SYS pool for safety reconciliation.
        positions_map = self.positions_snapshot(mode_global="ECO", force=True)
        pending_map = self.pending_snapshot(mode_global="ECO", force=True)
        open_total = 0
        pend_total = 0
        try:
            open_total = int(sum(len(v) for v in (positions_map or {}).values()))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            open_total = 0
        try:
            pend_total = int(sum(len(v) for v in (pending_map or {}).values()))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            pend_total = 0

        if open_total > 0 or pend_total > 0:
            logging.critical(
                "WINDOW_OFF_NOT_FLAT positions=%s pending=%s => EMERGENCY_CLOSEOUT",
                int(open_total),
                int(pend_total),
            )
            self._trade_window_closeout(reason="outside_window_not_flat", ctx=ctx)

    def _trade_window_closeout(self, *, reason: str, ctx: Optional[Dict[str, object]] = None) -> None:
        """Close all positions and cancel pending orders. Always uses emergency budgets."""
        now_ts = int(time.time())
        last = int(self.db.get_last_ts("last_trade_window_closeout_ts") or 0)
        # Avoid spamming closeout attempts every scan loop.
        if (now_ts - last) < 30:
            return
        self.db.set_last_ts("last_trade_window_closeout_ts", now_ts)

        # 1) Cancel pending orders (if any).
        try:
            if mt5 is not None and hasattr(mt5, "TRADE_ACTION_REMOVE"):
                ords = self.execution_engine.orders_get(emergency=True) or ()
                if ords:
                    pending_types = {
                        getattr(mt5, "ORDER_TYPE_BUY_LIMIT", None),
                        getattr(mt5, "ORDER_TYPE_SELL_LIMIT", None),
                        getattr(mt5, "ORDER_TYPE_BUY_STOP", None),
                        getattr(mt5, "ORDER_TYPE_SELL_STOP", None),
                        getattr(mt5, "ORDER_TYPE_BUY_STOP_LIMIT", None),
                        getattr(mt5, "ORDER_TYPE_SELL_STOP_LIMIT", None),
                    }
                    pending_types = {t for t in pending_types if t is not None}
                    for o in ords:
                        try:
                            if int(getattr(o, "type", -1)) not in pending_types:
                                continue
                            ticket = int(getattr(o, "ticket", 0) or 0)
                            sym = str(getattr(o, "symbol", "") or "")
                            if ticket <= 0 or not sym:
                                continue
                            grp = guess_group(sym)
                            req = {
                                "action": mt5.TRADE_ACTION_REMOVE,
                                "order": ticket,
                                "symbol": sym,
                                "magic": int(getattr(CFG, "magic_number", 0) or 0),
                                "comment": f"WINDOW_CLOSEOUT:{reason}",
                            }
                            self.execution_engine.order_send(sym, grp, req, emergency=True)
                        except Exception as e:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # 2) Close all open positions (kill-switch style).
        ok = self.execution_engine.force_flat_all(
            self.db,
            retries=int(getattr(CFG, "close_retries", 2)),
            delay=float(getattr(CFG, "close_retry_delay_sec", 0.5)),
            deviation=int(getattr(CFG, "kill_close_deviation_points", 30)),
        )
        if ok:
            logging.warning("WINDOW_CLOSEOUT_DONE reason=%s", str(reason))
        else:
            logging.critical("WINDOW_CLOSEOUT_INCOMPLETE reason=%s", str(reason))

    def _hybrid_snapshot_health(self, symbols: List[str]) -> Dict[str, Any]:
        tick_max_age = max(5, int(getattr(CFG, "hybrid_snapshot_max_age_sec", 180)))
        bar_max_age = max(
            int(tick_max_age),
            int(getattr(CFG, "hybrid_snapshot_bar_max_age_sec", 900)),
        )
        startup_grace_sec = max(0, int(getattr(CFG, "hybrid_snapshot_startup_grace_sec", 120)))
        now_ts = float(time.time())
        uptime_sec = max(0.0, float(now_ts - float(getattr(self, "_startup_ts", now_ts))))
        startup_grace_active = bool(uptime_sec < float(startup_grace_sec))
        stale_tick = 0
        stale_bar = 0
        seen_tick = 0
        seen_bar = 0
        total = 0
        for sym in symbols:
            base = symbol_base(sym)
            total += 1
            t_tick = float(self._zmq_last_tick_ts.get(base, 0.0) or 0.0)
            t_bar = float(self._zmq_last_bar_ts.get(base, 0.0) or 0.0)
            if t_tick > 0.0:
                seen_tick += 1
                if (now_ts - t_tick) > float(tick_max_age):
                    stale_tick += 1
            if t_bar > 0.0:
                seen_bar += 1
                if (now_ts - t_bar) > float(bar_max_age):
                    stale_bar += 1
        tick_critical = bool((seen_tick == 0 and total > 0) or (seen_tick > 0 and stale_tick == seen_tick))
        bar_critical = bool((seen_bar == 0 and total > 0) or (seen_bar > 0 and stale_bar == seen_bar))
        critical_raw = bool(total > 0 and (tick_critical or bar_critical))
        if total > 0 and not bool(getattr(CFG, "hybrid_snapshot_block_on_bar_only", True)):
            # In relaxed mode, block only when tick stream is stale for all tracked symbols.
            critical_raw = bool(tick_critical)
        critical = bool(critical_raw and (not startup_grace_active))
        return {
            "max_age_sec": int(tick_max_age),
            "bar_max_age_sec": int(bar_max_age),
            "startup_grace_sec": int(startup_grace_sec),
            "startup_grace_active": bool(startup_grace_active),
            "uptime_sec": int(uptime_sec),
            "symbols_total": int(total),
            "seen_tick": int(seen_tick),
            "seen_bar": int(seen_bar),
            "stale_tick": int(stale_tick),
            "stale_bar": int(stale_bar),
            "critical_raw": bool(critical_raw),
            "critical": bool(critical),
        }

    def _policy_runtime_common_path(self) -> Optional[Path]:
        return build_mt5_common_file_path(
            enabled=bool(getattr(CFG, "policy_runtime_emit_common_file", True)),
            subdir=str(getattr(CFG, "policy_runtime_common_subdir", "OANDA_MT5_SYSTEM") or "OANDA_MT5_SYSTEM"),
            file_name=str(getattr(CFG, "policy_runtime_file_name", "policy_runtime.json") or "policy_runtime.json"),
        )

    def _kernel_config_common_path(self) -> Optional[Path]:
        return build_mt5_common_file_path(
            enabled=bool(getattr(CFG, "kernel_config_emit_common_file", True)),
            subdir=str(getattr(CFG, "kernel_config_common_subdir", "OANDA_MT5_SYSTEM") or "OANDA_MT5_SYSTEM"),
            file_name=str(getattr(CFG, "kernel_config_file_name", "kernel_config_v1.json") or "kernel_config_v1.json"),
        )

    def _trade_trigger_mode_info(self) -> Tuple[str, str]:
        mode, reason = resolve_trade_trigger_mode(
            getattr(CFG, "trade_trigger_mode", "BRIDGE_ACTIVE"),
            allow_mql5_active=bool(getattr(CFG, "trade_trigger_mode_allow_mql5_active", False)),
        )
        return mode, reason

    def _trade_trigger_mode(self) -> str:
        mode, _reason = self._trade_trigger_mode_info()
        return mode

    def _kernel_spread_cap_points(self, symbol: str, grp_u: str) -> float:
        grp_u = _group_key(grp_u)
        if grp_u == "FX":
            return float(fx_spread_cap_points(symbol, grp=grp_u))
        if grp_u == "METAL":
            return float(metal_spread_cap_points(symbol, grp=grp_u))
        return float(max(0.0, _cfg_group_float(grp_u, "spread_cap_points", 0.0, symbol=symbol)))

    def _kernel_group_float(self, grp_u: str, key: str, default: float, symbol: str) -> float:
        return float(_cfg_group_float(grp_u, key, default, symbol=symbol))

    def _kernel_group_int(self, grp_u: str, key: str, default: int, symbol: str) -> int:
        return int(_cfg_group_int(grp_u, key, default, symbol=symbol))

    def _build_kernel_config_symbol_rows(
        self,
        group_risk: Dict[str, Dict[str, Any]],
        *,
        now_dt: Optional[dt.datetime] = None,
    ) -> List[Dict[str, Any]]:
        ref = (now_dt or now_utc()).astimezone(UTC)
        return build_kernel_symbol_rows(
            self.universe or [],
            group_risk,
            black_swan_action=str(getattr(self, "_black_swan_v2_action", "ALLOW") or "ALLOW"),
            black_swan_reason=str(getattr(self, "_black_swan_v2_reason", "NONE") or "NONE"),
            black_swan_blocks=bool(getattr(self, "_black_swan_block_new_entries", False)),
            group_risk_fallback=group_market_risk_state,
            spread_cap_resolver=self._kernel_spread_cap_points,
            group_float_resolver=self._kernel_group_float,
            group_int_resolver=self._kernel_group_int,
            canonical_symbol_func=canonical_symbol,
            group_key_func=_group_key,
            now_dt=ref,
        )

    def _build_kernel_config_payload(
        self,
        group_risk: Dict[str, Dict[str, Any]],
        *,
        now_dt: Optional[dt.datetime] = None,
    ) -> Dict[str, Any]:
        ref = (now_dt or now_utc()).astimezone(UTC)
        meta = {
            "trade_trigger_mode": self._trade_trigger_mode(),
            "source": "SafetyBot",
            "runtime_root": str(self.runtime_root),
            "stage1_loaded_symbols": int(getattr(self, "_stage1_live_last_loaded_symbols", 0)),
            "stage1_config_hash": str((_STAGE1_LIVE_META or {}).get("config_hash") or ""),
            "black_swan_v2_state": str(getattr(self, "_black_swan_v2_state", "NORMAL") or "NORMAL"),
            "black_swan_v2_action": str(getattr(self, "_black_swan_v2_action", "ALLOW") or "ALLOW"),
            "black_swan_v2_reason": str(getattr(self, "_black_swan_v2_reason", "NONE") or "NONE"),
        }
        return build_kernel_runtime_payload(
            self.universe or [],
            group_risk,
            black_swan_action=str(getattr(self, "_black_swan_v2_action", "ALLOW") or "ALLOW"),
            black_swan_reason=str(getattr(self, "_black_swan_v2_reason", "NONE") or "NONE"),
            black_swan_blocks=bool(getattr(self, "_black_swan_block_new_entries", False)),
            group_risk_fallback=group_market_risk_state,
            spread_cap_resolver=self._kernel_spread_cap_points,
            group_float_resolver=self._kernel_group_float,
            group_int_resolver=self._kernel_group_int,
            canonical_symbol_func=canonical_symbol,
            group_key_func=_group_key,
            generated_at_utc=ref.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            meta=meta,
            policy_version=KERNEL_CONFIG_POLICY_VERSION,
        )

    def _build_policy_runtime_payload(
        self,
        group_arb: Dict[str, Dict[str, Any]],
        group_risk: Dict[str, Dict[str, Any]],
        *,
        now_dt: Optional[dt.datetime] = None,
    ) -> Dict[str, Any]:
        ref = (now_dt or now_utc()).astimezone(UTC)
        return build_policy_runtime_payload(
            group_arb,
            group_risk,
            flags={
                "policy_windows_v2_enabled": bool(getattr(CFG, "policy_windows_v2_enabled", True)),
                "policy_risk_windows_enabled": bool(getattr(CFG, "policy_risk_windows_enabled", True)),
                "policy_group_arbitration_enabled": bool(getattr(CFG, "policy_group_arbitration_enabled", True)),
                "policy_overlap_arbitration_enabled": bool(getattr(CFG, "policy_overlap_arbitration_enabled", True)),
                "policy_shadow_mode_enabled": bool(getattr(CFG, "policy_shadow_mode_enabled", True)),
            },
            ts_utc=ref.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            us_overlap_active=bool(us_overlap_window_active(ref)),
        )

    def _emit_policy_runtime(
        self,
        group_arb: Dict[str, Dict[str, Any]],
        group_risk: Dict[str, Dict[str, Any]],
        *,
        now_dt: Optional[dt.datetime] = None,
    ) -> None:
        if not bool(getattr(CFG, "policy_runtime_emit_enabled", True)):
            return
        now_ts = float(time.time())
        interval_s = max(1, int(getattr(CFG, "policy_runtime_emit_interval_sec", 15)))
        last_ts = float(getattr(self, "_last_policy_runtime_emit_ts", 0.0))
        if not should_emit_interval(now_ts=now_ts, last_ts=last_ts, interval_s=interval_s):
            return
        self._last_policy_runtime_emit_ts = now_ts

        payload = self._build_policy_runtime_payload(group_arb, group_risk, now_dt=now_dt)
        file_name = str(getattr(CFG, "policy_runtime_file_name", "policy_runtime.json") or "policy_runtime.json").strip()
        if not file_name:
            file_name = "policy_runtime.json"

        try:
            atomic_write_json(self.meta_dir / file_name, payload)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        common_path = self._policy_runtime_common_path()
        if common_path is not None:
            try:
                # Use atomic writer also for MT5 Common\Files to avoid transient read/open races in EA.
                atomic_write_json(common_path, payload)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _emit_kernel_config(
        self,
        group_risk: Dict[str, Dict[str, Any]],
        *,
        now_dt: Optional[dt.datetime] = None,
    ) -> None:
        if not bool(getattr(CFG, "kernel_config_emit_enabled", True)):
            return
        now_ts = float(time.time())
        interval_s = max(1, int(getattr(CFG, "kernel_config_emit_interval_sec", 15)))
        if not should_emit_interval(
            now_ts=now_ts,
            last_ts=float(getattr(self, "_last_kernel_config_emit_ts", 0.0)),
            interval_s=interval_s,
        ):
            return
        self._last_kernel_config_emit_ts = now_ts

        payload = self._build_kernel_config_payload(group_risk, now_dt=now_dt)
        file_name = str(getattr(CFG, "kernel_config_file_name", "kernel_config_v1.json") or "kernel_config_v1.json").strip()
        if not file_name:
            file_name = "kernel_config_v1.json"

        try:
            atomic_write_json(self.meta_dir / file_name, payload)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        common_path = self._kernel_config_common_path()
        if common_path is not None:
            try:
                atomic_write_json(common_path, payload)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _runtime_maintenance_step(self) -> bool:
        try:
            # Control-plane emit poza sekcją decyzyjną scan_once (mniej I/O w decision core).
            group_arb = dict(getattr(self, "_runtime_cached_group_arb", {}) or {})
            group_risk = dict(getattr(self, "_runtime_cached_group_risk", {}) or {})
            self._emit_policy_runtime(group_arb, group_risk, now_dt=now_utc())
            self._emit_kernel_config(group_risk, now_dt=now_utc())
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        try:
            self._reload_stage1_live_config(force=False)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        if self.manual_kill_switch_path.exists():
            logging.info("BOT STOP | Wykryto plik kill_switch.")
            return False
        return True

    def _runtime_ingest_step(
        self,
        *,
        now: float,
        last_market_data_ts: float,
        receive_timeout_ms: int = 100,
    ) -> Tuple[Any, float]:
        tick_ingest_t0 = time.perf_counter()
        market_data = self.zmq_bridge.receive_data(timeout=int(receive_timeout_ms))
        next_market_data_ts = float(last_market_data_ts)
        if market_data:
            next_market_data_ts = float(now)
            self._handle_market_data(market_data)
        self._record_section_duration("tick_ingest", int((time.perf_counter() - tick_ingest_t0) * 1000.0))
        return market_data, float(next_market_data_ts)

    def _runtime_loop_step(self, *, loop_cfg: Any, loop_state: Dict[str, Any]) -> bool:
        now = float(time.time())
        loop_state["loop_id"] = int(loop_state.get("loop_id", 0) or 0) + 1
        self._runtime_loop_id = int(loop_state["loop_id"])

        market_data, next_market_data_ts = self._runtime_ingest_step(
            now=float(now),
            last_market_data_ts=float(loop_state.get("last_market_data_ts", 0.0) or 0.0),
            receive_timeout_ms=100,
        )
        loop_state["last_market_data_ts"] = float(next_market_data_ts)

        (
            next_last_heartbeat_ts,
            next_heartbeat_failures,
            next_heartbeat_fail_safe_active,
            next_heartbeat_fail_safe_until,
        ) = self._runtime_heartbeat_step_from_state(
            now=float(now),
            loop_cfg=loop_cfg,
            loop_state=loop_state,
        )
        loop_state["last_heartbeat_ts"] = float(next_last_heartbeat_ts)
        loop_state["heartbeat_failures"] = int(next_heartbeat_failures)
        loop_state["heartbeat_fail_safe_active"] = bool(next_heartbeat_fail_safe_active)
        loop_state["heartbeat_fail_safe_until"] = float(next_heartbeat_fail_safe_until)

        next_probe_ts, next_probe_sent = self._runtime_trade_probe_step(
            now=float(now),
            heartbeat_fail_safe_active=bool(loop_state["heartbeat_fail_safe_active"]),
            trade_probe_enabled=bool(loop_cfg.trade_probe_enabled),
            trade_probe_interval_sec=int(loop_cfg.trade_probe_interval_sec),
            trade_probe_max_per_run=int(loop_cfg.trade_probe_max_per_run),
            trade_probe_sent=int(loop_state.get("trade_probe_sent", 0) or 0),
            last_trade_probe_ts=float(loop_state.get("last_trade_probe_ts", 0.0) or 0.0),
            trade_probe_signal=str(loop_cfg.trade_probe_signal),
            trade_probe_symbol=str(loop_cfg.trade_probe_symbol),
            trade_probe_volume=float(loop_cfg.trade_probe_volume),
            trade_probe_deviation_points=int(loop_cfg.trade_probe_deviation_points),
            trade_probe_comment=str(loop_cfg.trade_probe_comment),
            trade_probe_group=str(loop_cfg.trade_probe_group),
        )
        loop_state["last_trade_probe_ts"] = float(next_probe_ts)
        loop_state["trade_probe_sent"] = int(next_probe_sent)

        next_scan_ts = self._runtime_scan_step(
            now=float(now),
            last_scan_ts=float(loop_state.get("last_scan_ts", 0.0) or 0.0),
            scan_interval=int(loop_cfg.scan_interval),
            heartbeat_fail_safe_active=bool(loop_state["heartbeat_fail_safe_active"]),
            heartbeat_failures=int(loop_state["heartbeat_failures"]),
            heartbeat_fail_safe_until=float(loop_state["heartbeat_fail_safe_until"]),
            scan_suppressed_log_interval=int(loop_cfg.scan_suppressed_log_interval),
            scan_slow_warn_ms=int(loop_cfg.scan_slow_warn_ms),
        )
        loop_state["last_scan_ts"] = float(next_scan_ts)

        if not self._runtime_maintenance_step():
            return False
        self._runtime_idle_step(bool(market_data), float(loop_cfg.run_loop_idle_sleep))
        return True

    def _runtime_scan_step(
        self,
        *,
        now: float,
        last_scan_ts: float,
        scan_interval: int,
        heartbeat_fail_safe_active: bool,
        heartbeat_failures: int,
        heartbeat_fail_safe_until: float,
        scan_suppressed_log_interval: int,
        scan_slow_warn_ms: int,
    ) -> float:
        if float(now) - float(last_scan_ts) < float(scan_interval):
            return float(last_scan_ts)

        if bool(heartbeat_fail_safe_active):
            if (float(now) - float(self._last_scan_suppressed_log_ts or 0.0)) >= float(scan_suppressed_log_interval):
                self._last_scan_suppressed_log_ts = float(now)
                logging.warning(
                    "SCAN_SUPPRESSED | reason=heartbeat_fail_safe failures=%s cooldown_remain_s=%s",
                    int(heartbeat_failures),
                    int(max(0, round(float(heartbeat_fail_safe_until) - float(now)))),
                )
            return float(now)

        self._loop_scan_runs = int(self._loop_scan_runs) + 1
        scan_start_ts = float(time.perf_counter())
        try:
            self.scan_once()
        except Exception as e:
            self._loop_scan_errors = int(self._loop_scan_errors) + 1
            logging.error(f"scan_once error: {e}", exc_info=True)
        finally:
            scan_ms = int((time.perf_counter() - scan_start_ts) * 1000.0)
            self._record_scan_duration(scan_ms)
            self._record_section_duration("decision_core", scan_ms)
            if scan_ms >= int(scan_slow_warn_ms):
                logging.warning(
                    "SCAN_SLOW scan_ms=%s threshold_ms=%s",
                    int(scan_ms),
                    int(scan_slow_warn_ms),
                )
        return float(now)

    def _runtime_heartbeat_step(
        self,
        *,
        now: float,
        loop_id: int,
        last_heartbeat_ts: float,
        last_market_data_ts: float,
        heartbeat_interval: int,
        heartbeat_fail_safe_active: bool,
        heartbeat_failures: int,
        heartbeat_fail_safe_until: float,
        heartbeat_fail_threshold: int,
        heartbeat_fail_safe_cooldown: int,
        heartbeat_fail_log_interval: int,
        heartbeat_timeout_budget_ms: int,
        heartbeat_retries_budget: int,
        heartbeat_queue_lock_timeout_ms: int,
        heartbeat_worker_stale_sec: int,
    ) -> Tuple[float, int, bool, float]:
        if (float(now) - float(last_heartbeat_ts)) < float(heartbeat_interval):
            return (
                float(last_heartbeat_ts),
                int(heartbeat_failures),
                bool(heartbeat_fail_safe_active),
                float(heartbeat_fail_safe_until),
            )

        if bool(heartbeat_fail_safe_active) and float(now) < float(heartbeat_fail_safe_until):
            return (
                float(now),
                int(heartbeat_failures),
                bool(heartbeat_fail_safe_active),
                float(heartbeat_fail_safe_until),
            )

        heartbeat_loop_lag_ms = 0
        if float(last_heartbeat_ts) > 0:
            heartbeat_loop_lag_ms = int(
                max(0.0, (float(now) - float(last_heartbeat_ts) - float(heartbeat_interval)) * 1000.0)
            )
        market_data_stale_ms = -1
        if float(last_market_data_ts) > 0.0:
            market_data_stale_ms = int(max(0.0, (float(now) - float(last_market_data_ts)) * 1000.0))

        heartbeat_suppressed = (
            bool(heartbeat_fail_safe_active)
            and market_data_stale_ms >= int(heartbeat_worker_stale_sec * 1000)
        )
        if heartbeat_suppressed:
            heartbeat_fail_safe_until = float(now) + float(heartbeat_fail_safe_cooldown)
            if (float(now) - float(self._last_heartbeat_fail_log_ts or 0.0)) >= float(heartbeat_fail_log_interval):
                self._last_heartbeat_fail_log_ts = float(now)
                logging.warning(
                    "HEARTBEAT_SUPPRESSED reason=HB_NO_WORKER_RESPONSE stale_ms=%s cooldown_s=%s",
                    int(market_data_stale_ms),
                    int(heartbeat_fail_safe_cooldown),
                )
            return (
                float(now),
                int(heartbeat_failures),
                bool(heartbeat_fail_safe_active),
                float(heartbeat_fail_safe_until),
            )

        hb_reply = self.zmq_bridge.send_command(
            {
                "action": "HEARTBEAT",
                "loop_id": int(loop_id),
                "hb_loop_lag_ms": int(heartbeat_loop_lag_ms),
                "hb_market_data_stale_ms": int(market_data_stale_ms),
            },
            timeout_ms=int(heartbeat_timeout_budget_ms),
            max_retries=int(heartbeat_retries_budget),
            loop_id=str(int(loop_id)),
            queue_lock_timeout_ms=int(heartbeat_queue_lock_timeout_ms),
            reconnect_on_timeout=bool(
                getattr(CFG, "bridge_heartbeat_reconnect_on_timeout", False)
            ),
        )
        hb_diag: Dict[str, Any] = self.zmq_bridge.get_last_command_diag()
        self._record_bridge_diag(hb_diag, action="HEARTBEAT")
        hb_reason = str((hb_diag.get("bridge_timeout_reason") if isinstance(hb_diag, dict) else "") or "").strip().upper()
        hb_subreason = str((hb_diag.get("bridge_timeout_subreason") if isinstance(hb_diag, dict) else "") or "").strip().upper()
        hb_skipped_lock = bool(hb_reason == "QUEUE_LOCK_TIMEOUT")
        hb_timeout_nonfatal = (
            bool(getattr(CFG, "bridge_heartbeat_timeout_nonfatal", True))
            and hb_reason in ("TIMEOUT_NO_RESPONSE", "SEND_TIMEOUT")
            and (
                int(market_data_stale_ms) < 0
                or int(market_data_stale_ms) < int(heartbeat_worker_stale_sec * 1000)
            )
        )
        hb_hash_ok = False
        try:
            hb_hash = str(hb_reply.get("response_hash") or "") if isinstance(hb_reply, dict) else ""
            hb_hash_ok = bool(hb_hash) and hb_hash == str(build_response_hash(hb_reply))  # type: ignore[arg-type]
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            hb_hash_ok = False
        hb_ok = (
            isinstance(hb_reply, dict)
            and str(hb_reply.get("action") or "").upper() == "HEARTBEAT_REPLY"
            and str(hb_reply.get("status") or "").upper() == "OK"
            and bool(hb_hash_ok)
        )

        if hb_skipped_lock:
            logging.info(
                "HEARTBEAT_SKIP reason=queue_lock_busy queue_wait_ms=%s subreason=%s",
                int((hb_diag.get("command_queue_wait_ms") if isinstance(hb_diag, dict) else 0) or 0),
                hb_subreason or "LOCK_BUSY",
            )
            return (
                float(now),
                int(heartbeat_failures),
                bool(heartbeat_fail_safe_active),
                float(heartbeat_fail_safe_until),
            )

        if hb_timeout_nonfatal:
            logging.info(
                "HEARTBEAT_SKIP reason=timeout_nonfatal reason=%s subreason=%s wait_ms=%s timeout_budget_ms=%s",
                hb_reason or "TIMEOUT_NO_RESPONSE",
                hb_subreason or "NO_RESPONSE",
                int((hb_diag.get("bridge_wait_ms") if isinstance(hb_diag, dict) else 0) or 0),
                int((hb_diag.get("timeout_budget_ms") if isinstance(hb_diag, dict) else 0) or 0),
            )
            return (
                float(now),
                int(heartbeat_failures),
                bool(heartbeat_fail_safe_active),
                float(heartbeat_fail_safe_until),
            )

        if hb_ok:
            if bool(heartbeat_fail_safe_active) or int(heartbeat_failures) > 0:
                logging.warning(
                    "HEARTBEAT_RECOVERED | previous_failures=%s",
                    int(heartbeat_failures),
                )
                self._loop_heartbeat_recoveries = int(self._loop_heartbeat_recoveries) + 1
            self._last_heartbeat_ok_ts = float(now)
            return float(now), 0, False, 0.0

        heartbeat_failures = int(heartbeat_failures) + 1
        self._loop_heartbeat_fail_total = int(self._loop_heartbeat_fail_total) + 1
        if (float(now) - float(self._last_heartbeat_fail_log_ts or 0.0)) >= float(heartbeat_fail_log_interval):
            self._last_heartbeat_fail_log_ts = float(now)
            logging.error(
                "HEARTBEAT_FAIL | consecutive=%s threshold=%s cooldown_s=%s reply=%s",
                int(heartbeat_failures),
                int(heartbeat_fail_threshold),
                int(heartbeat_fail_safe_cooldown),
                hb_reply,
            )
        if int(heartbeat_failures) >= int(heartbeat_fail_threshold) and not bool(heartbeat_fail_safe_active):
            heartbeat_fail_safe_active = True
            logging.critical(
                "HEARTBEAT_FAILSAFE_ACTIVE | consecutive=%s threshold=%s mode=NO_TRADE cooldown_s=%s",
                int(heartbeat_failures),
                int(heartbeat_fail_threshold),
                int(heartbeat_fail_safe_cooldown),
            )
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="zmq_heartbeat",
                        reason="consecutive_heartbeat_failures",
                        severity="CRITICAL",
                        category="system",
                        symbol="__ALL__",
                        extra={
                            "failures": int(heartbeat_failures),
                            "threshold": int(heartbeat_fail_threshold),
                            "cooldown_sec": int(heartbeat_fail_safe_cooldown),
                        },
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        if bool(heartbeat_fail_safe_active):
            heartbeat_fail_safe_until = float(now) + float(heartbeat_fail_safe_cooldown)
        return (
            float(now),
            int(heartbeat_failures),
            bool(heartbeat_fail_safe_active),
            float(heartbeat_fail_safe_until),
        )

    def _runtime_heartbeat_step_from_state(
        self,
        *,
        now: float,
        loop_cfg: Any,
        loop_state: Dict[str, Any],
    ) -> Tuple[float, int, bool, float]:
        return self._runtime_heartbeat_step(
            now=float(now),
            loop_id=int(loop_state.get("loop_id", 0) or 0),
            last_heartbeat_ts=float(loop_state.get("last_heartbeat_ts", 0.0) or 0.0),
            last_market_data_ts=float(loop_state.get("last_market_data_ts", 0.0) or 0.0),
            heartbeat_interval=int(loop_cfg.heartbeat_interval),
            heartbeat_fail_safe_active=bool(loop_state.get("heartbeat_fail_safe_active", False)),
            heartbeat_failures=int(loop_state.get("heartbeat_failures", 0) or 0),
            heartbeat_fail_safe_until=float(loop_state.get("heartbeat_fail_safe_until", 0.0) or 0.0),
            heartbeat_fail_threshold=int(loop_cfg.heartbeat_fail_threshold),
            heartbeat_fail_safe_cooldown=int(loop_cfg.heartbeat_fail_safe_cooldown),
            heartbeat_fail_log_interval=int(loop_cfg.heartbeat_fail_log_interval),
            heartbeat_timeout_budget_ms=int(loop_cfg.heartbeat_timeout_budget_ms),
            heartbeat_retries_budget=int(loop_cfg.heartbeat_retries_budget),
            heartbeat_queue_lock_timeout_ms=int(loop_cfg.heartbeat_queue_lock_timeout_ms),
            heartbeat_worker_stale_sec=int(loop_cfg.heartbeat_worker_stale_sec),
        )

    def _runtime_trade_probe_step(
        self,
        *,
        now: float,
        heartbeat_fail_safe_active: bool,
        trade_probe_enabled: bool,
        trade_probe_interval_sec: int,
        trade_probe_max_per_run: int,
        trade_probe_sent: int,
        last_trade_probe_ts: float,
        trade_probe_signal: str,
        trade_probe_symbol: str,
        trade_probe_volume: float,
        trade_probe_deviation_points: int,
        trade_probe_comment: str,
        trade_probe_group: str,
    ) -> Tuple[float, int]:
        if (
            (not bool(trade_probe_enabled))
            or bool(heartbeat_fail_safe_active)
            or ((float(now) - float(last_trade_probe_ts)) < float(trade_probe_interval_sec))
        ):
            return float(last_trade_probe_ts), int(trade_probe_sent)

        if trade_probe_max_per_run > 0 and int(trade_probe_sent) >= int(trade_probe_max_per_run):
            return float(last_trade_probe_ts), int(trade_probe_sent)

        probe_reply = self._send_trade_command(
            signal=str(trade_probe_signal),
            symbol=str(trade_probe_symbol),
            volume=float(trade_probe_volume),
            sl_price=0.0,
            tp_price=0.0,
            request_price=0.0,
            deviation_points=int(trade_probe_deviation_points),
            spread_at_decision_points=None,
            spread_unit="points",
            spread_provenance="trade_probe",
            estimated_entry_cost_components={},
            estimated_round_trip_cost={},
            cost_feasibility_shadow=None,
            net_cost_feasible=None,
            cost_gate_policy_mode="DIAGNOSTIC_ONLY",
            cost_gate_reason_code="TRADE_PROBE",
            magic=int(getattr(CFG, "magic_number", 0) or 0),
            comment=str(trade_probe_comment),
            group=str(trade_probe_group),
            risk_entry_allowed=True,
            risk_reason="TRADE_PROBE",
            risk_friday=False,
            risk_reopen=False,
            policy_shadow_mode=True,
        )
        self._record_bridge_diag(self.zmq_bridge.get_last_command_diag(), action="TRADE")
        next_trade_probe_sent = int(trade_probe_sent) + 1
        next_trade_probe_ts = float(now)
        if isinstance(probe_reply, dict):
            p_status = str(probe_reply.get("status") or "UNKNOWN").upper()
            p_ret = ""
            try:
                p_ret = str((probe_reply.get("details") or {}).get("retcode_str") or "")
            except Exception:
                p_ret = ""
            logging.info(
                "TRADE_PROBE_REPLY status=%s retcode_str=%s sent=%s/%s symbol=%s",
                p_status,
                p_ret or "NONE",
                int(next_trade_probe_sent),
                int(trade_probe_max_per_run),
                str(trade_probe_symbol),
            )
        else:
            logging.warning(
                "TRADE_PROBE_FAIL sent=%s/%s symbol=%s reason=no_reply",
                int(next_trade_probe_sent),
                int(trade_probe_max_per_run),
                str(trade_probe_symbol),
            )

        return next_trade_probe_ts, int(next_trade_probe_sent)

    def _runtime_idle_step(self, had_market_data: bool, idle_sleep_sec: float) -> None:
        if not had_market_data:
            time.sleep(float(idle_sleep_sec))

    def scan_once(self):
        st = self.gov.day_state()

        # Trade windows (P0): time windows + optional strict group routing.
        tw_ctx = trade_window_ctx(now_utc())
        tw_phase = str(tw_ctx.get("phase") or "OFF").upper()
        tw_window_id = str(tw_ctx.get("window_id") or "")
        tw_group = str(tw_ctx.get("group") or "").upper()
        tw_entry_allowed = bool(tw_ctx.get("entry_allowed"))
        tw_strict_group = bool(getattr(CFG, "trade_window_strict_group_routing", True))

        # Log only on transition (avoid spam).
        try:
            prev = getattr(self, "_last_tw_phase", None)
            prev_wid = getattr(self, "_last_tw_window_id", None)
            prev_grp = getattr(self, "_last_tw_group", None)
            if (prev != tw_phase) or (prev_wid != tw_window_id) or (prev_grp != tw_group):
                setattr(self, "_last_tw_phase", tw_phase)
                setattr(self, "_last_tw_window_id", tw_window_id)
                setattr(self, "_last_tw_group", tw_group)
                logging.info(
                    "WINDOW_PHASE phase=%s window=%s group=%s entry_allowed=%s strict_group=%s pl_now=%s",
                    tw_phase,
                    tw_window_id or "NONE",
                    tw_group or "NONE",
                    int(bool(tw_entry_allowed)),
                    int(bool(tw_strict_group)),
                    str(tw_ctx.get("pl_now")),
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # Track window switches (in-memory only) for optional carryover logic.
        try:
            cur_wid = getattr(self, "_tw_cur_window_id", None)
            cur_grp = getattr(self, "_tw_cur_group", None)
            if (cur_wid != tw_window_id) or (cur_grp != tw_group):
                setattr(self, "_tw_prev_window_id", cur_wid)
                setattr(self, "_tw_prev_group", cur_grp)
                setattr(self, "_tw_switch_ts", float(time.time()))
                setattr(self, "_tw_cur_window_id", tw_window_id)
                setattr(self, "_tw_cur_group", tw_group)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # ECO on budget pressure (PRICE / SYS / ORDER)
        eco_by_budget = False
        eco_reason = ""
        price_pct = 0.0
        sys_pct = 0.0
        order_pct = 0.0
        try:
            thr_default = float(getattr(CFG, "eco_threshold_pct", getattr(CFG, "order_eco_threshold_pct", 0.80)))
            thr_price = float(getattr(CFG, "eco_threshold_price_pct", thr_default))
            thr_order = float(getattr(CFG, "eco_threshold_order_pct", thr_default))
            thr_sys = float(getattr(CFG, "eco_threshold_sys_pct", thr_default))
            price_pct = (float(st.get("price_requests_day") or 0) / float(max(1, st.get("price_budget") or 1)))
            sys_pct = (float(st.get("sys_requests_day") or 0) / float(max(1, st.get("sys_budget") or 1)))
            order_pct = (float(st.get("order_actions_day") or 0) / float(max(1, st.get("order_budget") or 1)))

            reasons = []
            if price_pct >= thr_price:
                reasons.append("PRICE")
            if sys_pct >= thr_sys:
                reasons.append("SYS")
            if order_pct >= thr_order:
                reasons.append("ORDER")

            if reasons:
                eco_by_budget = True
                eco_reason = ",".join(reasons)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            eco_by_budget = False
            eco_reason = ""

        # P0 BUDGET log (hard-required fields: day_ny + utc_day + eco), z ograniczeniem szumu.
        budget_log_interval_s = max(
            5,
            int(getattr(CFG, "budget_log_interval_sec", 60)),
        )
        now_budget_ts = float(time.time())
        if (now_budget_ts - float(getattr(self, "_last_budget_log_ts", 0.0))) >= float(budget_log_interval_s):
            self._last_budget_log_ts = now_budget_ts
            logging.info(
                f"BUDGET day_ny={st['day_ny']} utc_day={st['utc_day']} eco={int(bool(eco_by_budget))} pl_day={st.get('pl_day','')} "
                f"price_requests_day={st['price_requests_day']} order_actions_day={st['order_actions_day']} sys_requests_day={st['sys_requests_day']} "
                f"price_budget={st['price_budget']} order_budget={st['order_budget']} sys_budget={st['sys_budget']}"
            )

        # Group-level arbitration snapshot (budget pressure + dynamic priority factor).
        group_arb: Dict[str, Dict[str, Any]] = {}
        group_risk: Dict[str, Dict[str, Any]] = {}
        try:
            now_arb = now_utc()
            groups_cfg = sorted(
                {
                    _group_key(str(g))
                    for g in (getattr(CFG, "group_price_shares", {}) or {}).keys()
                    if str(g).strip()
                }
            )
            for g in groups_cfg:
                st_g = self.gov.group_budget_state(g, now_dt=now_arb)
                st_g["priority_factor"] = float(self.gov.group_priority_factor(g, now_dt=now_arb))
                group_arb[g] = st_g
                group_risk[g] = group_market_risk_state(g, now_dt=now_arb)

            log_interval_s = max(60, int(getattr(CFG, "scan_interval_sec", 30)) * 4)
            now_ts = float(time.time())
            if (now_ts - float(getattr(self, "_last_group_budget_log_ts", 0.0))) >= float(log_interval_s):
                self._last_group_budget_log_ts = now_ts
                for g in sorted(group_arb.keys()):
                    gs = group_arb[g]
                    logging.info(
                        "GROUP_ARB grp=%s prio_factor=%.3f unlock=%.3f risk_entry=%s risk_borrow_block=%s "
                        "risk_friday=%s risk_reopen=%s reason=%s price=%s/%s+%s order=%s/%s+%s sys=%s/%s+%s",
                        g,
                        float(gs.get("priority_factor", 1.0)),
                        float(gs.get("unlock_ratio", 0.0)),
                        int(gs.get("risk_entry_allowed", 1.0)),
                        int(gs.get("risk_borrow_blocked", 0.0)),
                        int(gs.get("risk_friday", 0.0)),
                        int(gs.get("risk_reopen", 0.0)),
                        str(gs.get("risk_reason", "NONE")),
                        int(gs.get("price_used", 0.0)),
                        int(gs.get("price_cap", 0.0)),
                        int(gs.get("price_borrow", 0.0)),
                        int(gs.get("order_used", 0.0)),
                        int(gs.get("order_cap", 0.0)),
                        int(gs.get("order_borrow", 0.0)),
                        int(gs.get("sys_used", 0.0)),
                        int(gs.get("sys_cap", 0.0)),
                        int(gs.get("sys_borrow", 0.0)),
                    )
            self._runtime_cached_group_arb = {
                str(g): dict(v or {}) for g, v in (group_arb or {}).items()
            }
            self._runtime_cached_group_risk = {
                str(g): dict(v or {}) for g, v in (group_risk or {}).items()
            }
            self._runtime_cached_group_ts_utc = now_arb.replace(microsecond=0).isoformat().replace("+00:00", "Z")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        warn_degrade_active = False
        # OANDA warning threshold (price requests/day): emit one warning per primary day key.
        try:
            if self.limits.warn_level_reached():
                day_key = str(st.get("day_primary") or st.get("pl_day") or st.get("utc_day") or "")
                state_key = "oanda_limits:last_warn_logged_day"
                last_warn_day = str(self.db.state_get(state_key, ""))
                if day_key and day_key != last_warn_day:
                    price_used = int(st.get("price_requests_day_guard") or st.get("price_requests_day") or 0)
                    price_budget = int(st.get("price_budget") or 0)
                    warn_level = int(getattr(self.limits, "warn_day", 0) or 0)
                    logging.warning(
                        f"OANDA_PRICE_WARN day={day_key} used={price_used} warn_level={warn_level} "
                        f"price_budget={price_budget} safe_mode={int(bool(self.limits.safe_mode_active()))}"
                    )
                    self.db.state_set(state_key, day_key)
            warn_degrade_active = bool(self.limits.warn_degrade_active())
            if warn_degrade_active and bool(getattr(CFG, "oanda_warn_degrade_enabled", True)):
                eco_by_budget = True
                eco_reason = ",".join([x for x in (eco_reason.split(",") if eco_reason else []) if x] + ["OANDA_WARN"])
            try:
                pb_log_interval_s = max(
                    5,
                    int(getattr(CFG, "oanda_price_breakdown_log_interval_sec", 60)),
                )
                now_pb_ts = float(time.time())
                if (now_pb_ts - float(getattr(self, "_last_oanda_price_breakdown_log_ts", 0.0))) >= float(pb_log_interval_s):
                    self._last_oanda_price_breakdown_log_ts = now_pb_ts
                    pb = self.limits.get_price_breakdown()
                    logging.info(
                        "OANDA_PRICE_BREAKDOWN day=%s total=%s tick=%s rates=%s other=%s warn_active=%s",
                        str(st.get("day_primary") or st.get("pl_day") or st.get("utc_day") or ""),
                        int(pb.get("total", 0)),
                        int(pb.get("tick", 0)),
                        int(pb.get("rates", 0)),
                        int(pb.get("other", 0)),
                        int(bool(warn_degrade_active)),
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        if eco_by_budget:
            logging.warning(
                f"ECO_MODE reason={eco_reason} price_pct={price_pct:.3f} sys_pct={sys_pct:.3f} order_pct={order_pct:.3f} "
                f"thr_price={thr_price:.3f} thr_sys={thr_sys:.3f} thr_order={thr_order:.3f}"
            )
        self._emit_runtime_metrics(st, eco_active=bool(eco_by_budget), warn_active=bool(warn_degrade_active))

# Additional legacy line kept for continuity (informational only)
        logging.info(
            f"PRICE used={st['price_used']}/{self.gov.price_trade_budget} + em={st['price_em_used']}/{self.gov.price_emergency} "
            f"| SYS used={st['sys_used']}/{self.gov.sys_trade_budget} + em={st['sys_em_used']}/{self.gov.sys_emergency} "
            f"| price_soft={self.gov.price_soft_mode()}"
        )
        try:
            self._refresh_live_module_states(tw_ctx=tw_ctx, st=st)
            self._refresh_no_live_drift_check(tw_ctx=tw_ctx)
            self._refresh_cost_guard_auto_relax_state(tw_ctx=tw_ctx)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # Trade windows gate:
        # - OFF: no training/scanning and no PRICE polling; keep minimal SYS safety reconciliation.
        # - CLOSEOUT: close/cancel only; no new entries.
        if tw_phase == "OFF":
            self._trade_window_off_maintenance(tw_ctx)
            return
        if tw_phase == "CLOSEOUT":
            self._trade_window_closeout(reason="closeout_buffer", ctx=tw_ctx)
            return

        # deals (SYS)
        self.poll_deals()
        self_heal_signal = self._evaluate_self_heal()
        canary_signal = self._evaluate_canary_rollout()
        # If canary is disabled in config, do not keep stale canary backoff from prior runs.
        if not bool(getattr(CFG, "canary_rollout_enabled", True)):
            try:
                gb_until = int(self.db.get_global_backoff_until_ts())
                gb_reason = str(self.db.get_global_backoff_reason() or "")
                if gb_until > 0 and gb_reason.startswith("canary:"):
                    self.db.set_global_backoff(until_ts=0, reason="canary_disabled_autoclear")
                    logging.info(
                        f"GLOBAL_BACKOFF_AUTOCLR reason=canary_disabled prev_until_ts={gb_until} prev_reason={gb_reason}"
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        drift_signal = self._evaluate_drift()
        learner_qa_light = self._read_learner_qa_light()
        unified_learning = (
            load_unified_learning_advice(self.meta_dir)
            if bool(getattr(CFG, "unified_learning_runtime_enabled", True))
            else None
        )

        # rollover global
        rollover_safe = self.strategy.rollover_safe()
        if not rollover_safe:
            logging.warning("ROLLOVER_BLOCK global=1 reason=window_active")

        # Tryb globalny: w aktywnym oknie handlu domyślnie HOT (szybsze skanowanie),
        # poza oknami scan_once już zwraca wcześniej.
        global_mode = "HOT" if tw_phase == "ACTIVE" else "ECO"
        if not rollover_safe:
            global_mode = "ECO"
        if eco_by_budget:
            global_mode = "ECO"
        if self_heal_signal.active:
            global_mode = "ECO"
            logging.warning(
                f"SELF_HEAL_PAUSE streak={self_heal_signal.loss_streak} "
                f"net_pnl={self_heal_signal.net_pnl:.2f} reasons={','.join(self_heal_signal.reasons)}"
            )
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="self_heal",
                        reason=";".join(self_heal_signal.reasons),
                        severity="WARN",
                        category="model",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        if canary_signal.pause:
            global_mode = "ECO"
            logging.warning(
                f"CANARY_PAUSE streak={canary_signal.loss_streak} net_pnl={canary_signal.net_pnl:.2f} "
                f"errors={canary_signal.error_incidents} reasons={','.join(canary_signal.reasons)}"
            )
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="canary_rollout",
                        reason=";".join(canary_signal.reasons),
                        # Avoid self-reinforcing INCIDENTS loop in canary gating.
                        severity="WARN",
                        category="model",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        if drift_signal.active:
            global_mode = "ECO"
            logging.warning(
                f"DRIFT_PAUSE drop={drift_signal.mean_drop:.6f} z={drift_signal.zscore:.3f} "
                f"reasons={','.join(drift_signal.reasons)}"
            )
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="drift_guard",
                        reason=";".join(drift_signal.reasons),
                        severity="ERROR",
                        category="regime",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        # Learner QA is telemetry-only for trading path. It must not block or downgrade entries.
        if learner_qa_light == "RED":
            logging.info("LEARNER_QA_RED telemetry_only=1 no_mode_override=1")
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="learner_qa",
                        reason="RED_TELEMETRY_ONLY",
                        severity="INFO",
                        category="model",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # V1.10: okresowa synchronizacja czasu serwera (rzadko, tylko jeśli budżet pozwala)
        self._time_anchor_sync_if_due(st)

        # pozycje (SYS): ECO nie może odciąć opieki nad otwartymi pozycjami
        in_force_close = self.strategy.force_close_window()
        positions_map = self.positions_snapshot(global_mode, force=bool(in_force_close))
        pending_map = self.pending_snapshot(global_mode, force=bool(in_force_close))
        open_syms = set(positions_map.keys()) if positions_map else set()
        if open_syms and (not in_force_close):
            try:
                in_force_close = any(self.strategy.force_close_window(symbol=s) for s in open_syms)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                in_force_close = False
        try:
            pending_total = int(sum(len(v) for v in (pending_map or {}).values()))
            if pending_total > 0:
                logging.info(
                    "PENDING_SNAPSHOT symbols=%s pending_total=%s",
                    int(len(pending_map or {})),
                    int(pending_total),
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # jeśli mamy pozycje i wchodzimy w force-close window => pilnuj (użyj rezerwy awaryjnej)
        if open_syms and in_force_close:
            logging.warning("ROLLOVER force-close window: zamykanie pozycji.")
            ok = self.execution_engine.force_flat_all(self.db, retries=CFG.close_retries, delay=CFG.close_retry_delay_sec,
                                        deviation=CFG.kill_close_deviation_points)
            if not ok:
                logging.critical("FORCE FLAT incomplete.")
            return

        # Adaptive open-position management (partial TP + trailing SL) before stale-close logic.
        self._manage_adaptive_exits(positions_map, global_mode=global_mode, rollover_safe=rollover_safe)

        # Position time-stop guard (scalp discipline): close stale positions deterministically.
        self._close_stale_positions(positions_map, global_mode=global_mode, rollover_safe=rollover_safe)

        black_swan_signal = self._evaluate_black_swan()
        if black_swan_signal.black_swan:
            global_mode = "ECO"
            threshold = float(getattr(CFG, "black_swan_threshold", black_swan_signal.threshold))
            multiplier = float(getattr(CFG, "kill_switch_black_swan_multiplier", 1.0))
            multiplier = max(0.0, min(multiplier, 10.0))
            kill_threshold = threshold * multiplier
            kill_switch_enabled = bool(getattr(CFG, "kill_switch_on_black_swan_stress", True))
            if kill_switch_enabled and black_swan_signal.stress_index >= kill_threshold:
                logging.critical(
                    f"BLACK_SWAN_KILL_SWITCH stress={black_swan_signal.stress_index:.3f} "
                    f"threshold={threshold:.3f} multiplier={multiplier:.3f} kill_threshold={kill_threshold:.3f}"
                )
                if open_syms:
                    ok = self.execution_engine.force_flat_all(self.db, retries=CFG.close_retries, delay=CFG.close_retry_delay_sec,
                                                deviation=CFG.kill_close_deviation_points)
                    if not ok:
                        logging.critical("KILL SWITCH | FORCE FLAT incomplete.")
                return
            logging.warning(
                f"BLACK_SWAN_STRESS stress={black_swan_signal.stress_index:.3f} "
                f"threshold={threshold:.3f} => ECO/VETO_NEW_ENTRIES"
            )
        elif black_swan_signal.precaution:
            global_mode = "ECO"
            logging.warning(
                f"STRESS_PRECAUTION stress={black_swan_signal.stress_index:.3f} "
                f"threshold={black_swan_signal.precaution_threshold:.3f} => ECO"
            )

        if self._manual_kill_switch_active():
            return

        snapshot_health = self._hybrid_snapshot_health([sym for (_raw, sym, _grp) in self.universe])
        black_swan_block_new_entries = bool(getattr(self, "_black_swan_block_new_entries", False))
        snapshot_block_new_entries = bool(snapshot_health.get("critical")) or bool(black_swan_block_new_entries)
        now_ts = float(time.time())
        snapshot_log_interval = max(5, int(getattr(CFG, "hybrid_snapshot_health_log_interval_sec", 60)))
        snapshot_log_due = bool((now_ts - float(getattr(self, "_last_snapshot_health_log_ts", 0.0))) >= float(snapshot_log_interval))
        if bool(snapshot_health.get("critical_raw")) and bool(snapshot_health.get("startup_grace_active")) and snapshot_log_due:
            self._last_snapshot_health_log_ts = now_ts
            logging.info(
                "SNAPSHOT_HEALTH_WARMUP_GRACE stale_tick=%s/%s stale_bar=%s/%s total=%s uptime_sec=%s grace_sec=%s => NO_BLOCK_YET",
                int(snapshot_health.get("stale_tick", 0)),
                int(snapshot_health.get("seen_tick", 0)),
                int(snapshot_health.get("stale_bar", 0)),
                int(snapshot_health.get("seen_bar", 0)),
                int(snapshot_health.get("symbols_total", 0)),
                int(snapshot_health.get("uptime_sec", 0)),
                int(snapshot_health.get("startup_grace_sec", 0)),
            )
        if snapshot_block_new_entries:
            global_mode = "ECO"
            if bool(snapshot_health.get("critical")) and snapshot_log_due:
                self._last_snapshot_health_log_ts = now_ts
                logging.warning(
                    "SNAPSHOT_HEALTH_DEGRADED stale_tick=%s/%s stale_bar=%s/%s total=%s tick_max_age_sec=%s bar_max_age_sec=%s uptime_sec=%s => NO_NEW_ENTRIES",
                    int(snapshot_health.get("stale_tick", 0)),
                    int(snapshot_health.get("seen_tick", 0)),
                    int(snapshot_health.get("stale_bar", 0)),
                    int(snapshot_health.get("seen_bar", 0)),
                    int(snapshot_health.get("symbols_total", 0)),
                    int(snapshot_health.get("max_age_sec", 0)),
                    int(snapshot_health.get("bar_max_age_sec", 0)),
                    int(snapshot_health.get("uptime_sec", 0)),
                )
            if black_swan_block_new_entries:
                logging.warning(
                    "BLACK_SWAN_BLOCK_NEW_ENTRIES state=%s action=%s reason=%s",
                    str(getattr(self, "_black_swan_v2_state", "UNKNOWN")),
                    str(getattr(self, "_black_swan_v2_action", "UNKNOWN")),
                    str(getattr(self, "_black_swan_v2_reason", "NONE")),
                )

        candidates: List[Tuple[float, str, str, str]] = []  # (priority, raw, sym, grp)
        unified_rank_map: Dict[str, Dict[str, Any]] = {}
        policy_shadow = bool(getattr(CFG, "policy_shadow_mode_enabled", True))
        use_windows_v2_hard = bool(getattr(CFG, "policy_windows_v2_enabled", True)) and (not policy_shadow)
        use_risk_windows_hard = bool(getattr(CFG, "policy_risk_windows_enabled", True)) and (not policy_shadow)
        use_group_arb_hard = bool(getattr(CFG, "policy_group_arbitration_enabled", True)) and (not policy_shadow)
        now_prio = now_utc()

        # --- Trade-window extensions (P0 deterministic; defaults = no behavior change) ---
        allowed_groups: Optional[set[str]] = None
        if tw_strict_group and tw_group:
            allowed_groups = {str(tw_group).upper()}
        allowed_symbols_by_group: Dict[str, set[str]] = {}
        # Exposed to scan_meta (for DB/telemetry), even when trade is disabled.
        carryover_active = 0
        fx_bucket_idx = 0       # 1-based when active, else 0
        fx_bucket_count = 0

        # Carryover: grace window after switch (optional limited cross-group entries).
        try:
            carry_enabled = bool(getattr(CFG, "trade_window_carryover_enabled", False))
            carry_trade = bool(getattr(CFG, "trade_window_carryover_trade_enabled", False))
            carry_min = max(0, int(getattr(CFG, "trade_window_carryover_minutes", 0)))
            carry_max = max(0, int(getattr(CFG, "trade_window_carryover_max_symbols", 0)))
            carry_groups = tuple(getattr(CFG, "trade_window_carryover_groups", ()) or ())
            carry_prev_grp = str(getattr(self, "_tw_prev_group", "") or "").upper()
            carry_prev_wid = str(getattr(self, "_tw_prev_window_id", "") or "")
            carry_age_min = 9999.0
            carry_syms: List[str] = []
            if carry_enabled and carry_prev_grp and carry_prev_grp != str(tw_group).upper() and carry_min > 0 and carry_max > 0:
                sw_ts = float(getattr(self, "_tw_switch_ts", 0.0) or 0.0)
                if sw_ts > 0:
                    carry_age_min = max(0.0, (time.time() - sw_ts) / 60.0)
                if carry_age_min <= float(carry_min):
                    carryover_active = 1
                    if (not carry_groups) or (_group_key(carry_prev_grp) in {_group_key(x) for x in carry_groups}):
                        # Select a small, deterministic shortlist from the previous group.
                        carry_rank: List[Tuple[float, str]] = []
                        for _raw2, _sym2, _grp2 in self.universe:
                            if _group_key(_grp2) != _group_key(carry_prev_grp):
                                continue
                            try:
                                if use_group_arb_hard:
                                    gf = float(
                                        group_arb.get(_group_key(_grp2), {}).get(
                                            "priority_factor", effective_group_priority_factor(_group_key(_grp2), now_dt=now_prio)
                                        )
                                    )
                                else:
                                    gf = float(group_arb.get(_group_key(_grp2), {}).get("priority_factor", self.gov.group_priority_factor(_group_key(_grp2))))
                            except Exception:
                                gf = 1.0
                            try:
                                twt = float(group_window_weight(_grp2, _sym2, now_dt=now_prio)) if use_windows_v2_hard else float(self.ctrl.time_weight(_grp2, _sym2))
                            except Exception:
                                twt = 1.0
                            try:
                                sf = float(self.ctrl.score_factor(_grp2, _sym2))
                            except Exception:
                                sf = 1.0
                            carry_rank.append((float(twt) * float(sf) * float(gf), str(_sym2)))
                        carry_rank.sort(reverse=True, key=lambda x: x[0])
                        carry_syms = [s for (_p, s) in carry_rank[:carry_max]]

                    sig = f"{tw_window_id}:{carry_prev_wid}:{carry_prev_grp}:{int(carry_trade)}:{','.join(carry_syms)}"
                    if sig != str(getattr(self, "_last_carryover_sig", "")):
                        setattr(self, "_last_carryover_sig", sig)
                        logging.info(
                            "WINDOW_CARRYOVER window=%s group=%s prev_window=%s prev_group=%s age_min=%.2f trade=%s symbols=%s",
                            tw_window_id or "NONE",
                            tw_group or "NONE",
                            carry_prev_wid or "NONE",
                            carry_prev_grp or "NONE",
                            float(carry_age_min),
                            int(bool(carry_trade)),
                            ",".join(carry_syms) if carry_syms else "NONE",
                        )

                    if carry_trade and carry_syms:
                        if allowed_groups is None:
                            allowed_groups = {str(tw_group).upper()}
                        allowed_groups.add(_group_key(carry_prev_grp))
                        allowed_symbols_by_group[_group_key(carry_prev_grp)] = {
                            canonical_symbol(s) for s in carry_syms if str(s).strip()
                        }
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # FX rotation: only when FX is over scan capacity (unless overridden).
        try:
            fx_rot_enabled = bool(getattr(CFG, "trade_window_fx_rotation_enabled", False))
            fx_bucket_size = max(1, int(getattr(CFG, "trade_window_fx_rotation_bucket_size", 4)))
            fx_period = max(1, int(getattr(CFG, "trade_window_fx_rotation_period_sec", 180)))
            fx_only_over = bool(getattr(CFG, "trade_window_fx_rotation_only_when_over_capacity", True))
            if fx_rot_enabled and _group_key(tw_group) == "FX":
                fx_syms_all = [str(s) for (_r, s, g) in self.universe if _group_key(g) == "FX"]
                fx_cap = max(1, int(self.ctrl.max_symbols_per_iter(global_mode)))
                if (not fx_only_over) or (len(fx_syms_all) > int(fx_cap)):
                    bidx, bucket_syms, bcount = fx_rotation_bucket(
                        fx_syms_all,
                        now_ts=time.time(),
                        bucket_size=int(fx_bucket_size),
                        period_sec=int(fx_period),
                    )
                    fx_bucket_idx = int(bidx) + 1
                    fx_bucket_count = int(bcount)
                    allowed_symbols_by_group["FX"] = {
                        canonical_symbol(s) for s in bucket_syms if str(s).strip()
                    }
                    # Always keep open symbols visible to policy telemetry.
                    allowed_symbols_by_group["FX"].update(
                        {canonical_symbol(s) for s in open_syms if str(s).strip()}
                    )
                    fx_sig = f"{bidx}/{bcount}:{','.join(sorted(bucket_syms))}"
                    if fx_sig != str(getattr(self, "_last_fx_rot_sig", "")):
                        setattr(self, "_last_fx_rot_sig", fx_sig)
                        logging.info(
                            "FX_ROTATION window=%s group=FX bucket=%s/%s period_sec=%s bucket_size=%s cap=%s total=%s symbols=%s",
                            tw_window_id or "NONE",
                            int(bidx) + 1,
                            int(bcount),
                            int(fx_period),
                            int(fx_bucket_size),
                            int(fx_cap),
                            int(len(fx_syms_all)),
                            ",".join(sorted(bucket_syms)) if bucket_syms else "NONE",
                        )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # Prefetch: compute (and optionally warm) next window shortlist (observation-only).
        try:
            prefetch_enabled = bool(getattr(CFG, "trade_window_prefetch_enabled", False))
            prefetch_lead = max(0, int(getattr(CFG, "trade_window_prefetch_lead_min", 15)))
            prefetch_max = max(0, int(getattr(CFG, "trade_window_prefetch_max_symbols", 4)))
            prefetch_warm = bool(getattr(CFG, "trade_window_prefetch_warm_store_indicators", False))
            if prefetch_enabled and prefetch_lead > 0 and prefetch_max > 0:
                nxt = trade_window_next_ctx(now_prio)
                if isinstance(nxt, dict):
                    t_minus = float(nxt.get("minutes_to_start", 9999.0))
                    nxt_wid = str(nxt.get("window_id") or "")
                    nxt_grp = _group_key(str(nxt.get("group") or ""))
                    nxt_start = nxt.get("start_utc")
                    if nxt_wid and nxt_grp and isinstance(nxt_start, dt.datetime) and 0.0 <= t_minus <= float(prefetch_lead):
                        # Priority for prefetch uses the *next window start time* (future time-weight).
                        rank: List[Tuple[float, str]] = []
                        for _raw2, _sym2, _grp2 in self.universe:
                            if _group_key(_grp2) != nxt_grp:
                                continue
                            try:
                                if use_group_arb_hard:
                                    gf = float(effective_group_priority_factor(nxt_grp, now_dt=nxt_start))
                                else:
                                    gf = float(self.gov.group_priority_factor(nxt_grp))
                            except Exception:
                                gf = 1.0
                            try:
                                twt = float(group_window_weight(_grp2, _sym2, now_dt=nxt_start))
                            except Exception:
                                twt = 1.0
                            try:
                                sf = float(self.ctrl.score_factor(_grp2, _sym2))
                            except Exception:
                                sf = 1.0
                            rank.append((float(twt) * float(sf) * float(gf), str(_sym2)))
                        rank.sort(reverse=True, key=lambda x: x[0])
                        pre_syms = [s for (_p, s) in rank[:prefetch_max]]

                        # Best-effort store-only indicator warmup (no MT5 fetch).
                        warm_ok = False
                        if pre_syms and prefetch_warm and getattr(self.execution_engine, "bars_store", None) is not None:
                            warmed = 0
                            for s in pre_syms:
                                try:
                                    df_store = self.execution_engine.bars_store.read_recent_df(symbol_base(s), 120)
                                    if df_store is None or len(df_store) < 60:
                                        continue
                                    # Compute minimal M5 indicators for warm-start (same as m5_indicators_if_due()).
                                    sma_fast_win = max(
                                        2, _cfg_group_int(nxt_grp, "sma_fast", int(getattr(CFG, "sma_fast", 20)), symbol=s)
                                    )
                                    adx_period = max(
                                        2, _cfg_group_int(nxt_grp, "adx_period", int(getattr(CFG, "adx_period", 14)), symbol=s)
                                    )
                                    atr_period = max(
                                        2, _cfg_group_int(nxt_grp, "atr_period", int(getattr(CFG, "atr_period", 14)), symbol=s)
                                    )
                                    df_store = df_store.copy()
                                    df_store["sma_fast"] = ta.trend.sma_indicator(df_store["close"], window=sma_fast_win)
                                    adx = ta.trend.ADXIndicator(df_store["high"], df_store["low"], df_store["close"], window=adx_period)
                                    df_store["adx"] = adx.adx()
                                    atr_val = None
                                    try:
                                        tr1 = (df_store["high"] - df_store["low"]).abs()
                                        tr2 = (df_store["high"] - df_store["close"].shift(1)).abs()
                                        tr3 = (df_store["low"] - df_store["close"].shift(1)).abs()
                                        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
                                        atr_val = float(tr.rolling(window=atr_period, min_periods=atr_period).mean().iloc[-1])
                                    except Exception:
                                        atr_val = None
                                    ind = {
                                        "close": float(df_store["close"].iloc[-1]),
                                        "open": float(df_store["open"].iloc[-1]),
                                        "high": float(df_store["high"].iloc[-1]),
                                        "low": float(df_store["low"].iloc[-1]),
                                        "sma": float(df_store["sma_fast"].iloc[-1]),
                                        "adx": float(df_store["adx"].iloc[-1]),
                                        "atr": float(atr_val) if atr_val is not None else None,
                                    }
                                    self.strategy.last_indicators[symbol_base(s)] = dict(ind)
                                    warmed += 1
                                except Exception:
                                    continue
                            warm_ok = bool(warmed > 0)

                        sig = f"{tw_window_id}->{nxt_wid}:{','.join(pre_syms)}:{int(bool(prefetch_warm))}:{int(bool(warm_ok))}"
                        if sig != str(getattr(self, "_last_prefetch_sig", "")):
                            setattr(self, "_last_prefetch_sig", sig)
                            logging.info(
                                "WINDOW_PREFETCH active_window=%s active_group=%s next_window=%s next_group=%s t_minus_min=%.1f selected=%s warm_store=%s",
                                tw_window_id or "NONE",
                                tw_group or "NONE",
                                nxt_wid,
                                nxt_grp,
                                float(t_minus),
                                ",".join(pre_syms) if pre_syms else "NONE",
                                int(bool(warm_ok)) if prefetch_warm else 0,
                            )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # Optional per-window symbol routing (policy-only): e.g. JPY set for Asia window.
        try:
            if bool(getattr(CFG, "trade_window_symbol_filter_enabled", False)):
                wid = str(tw_window_id or "")
                if wid:
                    tw_map_raw = getattr(CFG, "trade_window_symbol_intents", {}) or {}
                    intents = tuple(tw_map_raw.get(wid) or ())
                    if intents:
                        resolved = self._resolve_intents_to_canonical(tuple(intents))
                        gk = _group_key(str(tw_group or ""))
                        if gk and resolved:
                            current = allowed_symbols_by_group.get(gk)
                            if current is None:
                                allowed_symbols_by_group[gk] = set(resolved)
                            else:
                                allowed_symbols_by_group[gk] = {s for s in current if s in resolved}
                            # Keep open symbols visible to policy telemetry and closes.
                            allowed_symbols_by_group[gk].update(
                                {
                                    canonical_symbol(s)
                                    for s in open_syms
                                    if str(s).strip() and _group_key(guess_group(str(s))) == gk
                                }
                            )
                            sig = f"{wid}:{gk}:{','.join(sorted(intents))}:{','.join(sorted(allowed_symbols_by_group[gk]))}"
                            if sig != str(getattr(self, "_last_window_symbol_filter_sig", "")):
                                setattr(self, "_last_window_symbol_filter_sig", sig)
                                logging.info(
                                    "WINDOW_SYMBOL_FILTER window=%s group=%s intents=%s resolved=%s",
                                    wid,
                                    gk,
                                    ",".join(intents),
                                    ",".join(sorted(allowed_symbols_by_group[gk])) if allowed_symbols_by_group[gk] else "NONE",
                                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        for raw, sym, grp in self.universe:
            grp_u = _group_key(grp)
            if allowed_groups is not None and grp_u not in allowed_groups:
                continue
            sym_allow = allowed_symbols_by_group.get(grp_u)
            if sym_allow is not None and canonical_symbol(sym) not in sym_allow:
                continue
            risk_state = group_risk.get(grp_u) or group_market_risk_state(grp_u, now_dt=now_prio)
            skip_entry, skip_tag = risk_window_skip_decision(
                symbol=sym,
                group=grp_u,
                risk_state=risk_state,
                is_open_symbol=(sym in open_syms),
                use_risk_windows_hard=use_risk_windows_hard,
                policy_risk_windows_enabled=bool(getattr(CFG, "policy_risk_windows_enabled", True)),
            )
            if skip_tag:
                logging.info(
                    "%s symbol=%s group=%s friday=%s reopen=%s reason=%s",
                    skip_tag,
                    sym,
                    grp_u,
                    int(bool(risk_state.get("friday_risk"))),
                    int(bool(risk_state.get("reopen_guard"))),
                    str(risk_state.get("reason", "NONE")),
                )
            if skip_entry:
                continue

            # priorytet: time_weight * score_factor * effective_group_priority_factor (+ bonus przy otwartej pozycji)
            try:
                if use_group_arb_hard:
                    group_factor = float(
                        group_arb.get(grp_u, {}).get("priority_factor", effective_group_priority_factor(grp_u, now_dt=now_prio))
                    )
                else:
                    group_factor = float(group_arb.get(grp_u, {}).get("priority_factor", self.gov.group_priority_factor(grp_u)))
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                group_factor = 1.0
            if use_windows_v2_hard:
                time_weight = float(group_window_weight(grp, sym, now_dt=now_prio))
            else:
                time_weight = float(self.ctrl.time_weight(grp, sym))
            score_factor = float(self.ctrl.score_factor(grp, sym))
            prio = float(time_weight) * float(score_factor) * float(group_factor)
            if sym in open_syms:
                prio += 5.0
            rank_adj: Dict[str, Any] = {}
            if bool(getattr(CFG, "unified_learning_rank_enabled", True)):
                rank_adj = resolve_unified_learning_rank_adjustment(
                    unified=unified_learning if isinstance(unified_learning, dict) else None,
                    symbol=sym,
                    window_id=str(tw_window_id or ""),
                    window_phase=str(tw_phase or ""),
                    min_samples=int(getattr(CFG, "unified_learning_rank_min_samples", 20)),
                    max_bonus_pct=float(getattr(CFG, "unified_learning_rank_max_bonus_pct", 0.08)),
                )
                if bool(getattr(CFG, "unified_learning_rank_paper_only", True)) and (not bool(self.is_paper)):
                    rank_adj = {}
                rank_mult = float(rank_adj.get("prio_multiplier") or 1.0) if isinstance(rank_adj, dict) else 1.0
                if rank_mult <= 0.0:
                    rank_mult = 1.0
                prio = float(prio) * float(rank_mult)
                if rank_adj:
                    unified_rank_map[str(symbol_base(sym))] = dict(rank_adj)
                    pct_bonus = float(rank_adj.get("pct_bonus") or 0.0)
                    if abs(pct_bonus) >= 0.001:
                        logging.info(
                            "UNIFIED_LEARNING_RANK symbol=%s window=%s base_prio=%.6f pct_bonus=%.4f adjusted_prio=%.6f leader=%s reasons=%s",
                            str(symbol_base(sym)),
                            str(rank_adj.get("window") or "UNKNOWN"),
                            float((float(time_weight) * float(score_factor) * float(group_factor)) + (5.0 if sym in open_syms else 0.0)),
                            float(pct_bonus),
                            float(prio),
                            str(rank_adj.get("feedback_leader") or "UNKNOWN"),
                            ",".join([str(x) for x in (rank_adj.get("reasons") or [])]) or "NONE",
                        )
            candidates.append((prio, raw, sym, grp))

        candidates.sort(reverse=True, key=lambda x: x[0])
        if not candidates:
            logging.info("NO_CANDIDATES_AFTER_POLICY_FILTER")
            return

        # V1.10: Spend-down pod koniec dnia NY — jeśli zostało dużo niewykorzystanego PRICE budżetu,
        # możemy chwilowo zwiększyć aktywność (bez podnoszenia CAP).
        spenddown_active = False
        try:
            if (CFG.spenddown_enabled and global_mode != "HOT"
                and now_ny().hour >= int(CFG.spenddown_start_hour_ny)
                and int(st.get("price_remaining", 0)) >= int(CFG.spenddown_min_remaining_price)):
                spenddown_active = True
                if global_mode == "ECO" and str(CFG.spenddown_boost_mode).upper() == "WARM":
                    global_mode = "WARM"
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            spenddown_active = False

        # ile symboli "pełnych" w tej iteracji
        n_max = self.ctrl.max_symbols_per_iter(global_mode)

        # jeśli jest ECO — nie marnuj PRICE na skan, tylko monitoring pozycji (i ewentualne domknięcia)
        # V1.10: ale nie "odcinaj" opieki nad pozycjami – zostaw ślad w logach.
        if n_max <= 0:
            if open_syms:
                for sym in sorted(open_syms):
                    try:
                        cnt_pos = len(positions_map.get(sym, []))
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        cnt_pos = 0
                    logging.info(f"OPEN GUARD (ECO) | {sym} | positions={cnt_pos}")
            return

        # V1.10: Spend-down — niewielki boost liczby symboli, jeśli i tak budżet by się zmarnował.
        n_limit = int(n_max) + (int(CFG.spenddown_extra_symbols) if spenddown_active else 0)
        if snapshot_block_new_entries:
            n_limit = 0
        if warn_degrade_active and bool(getattr(CFG, "oanda_warn_degrade_enabled", True)):
            n_limit = min(int(n_limit), max(0, int(getattr(CFG, "oanda_warn_symbols_cap", 1))))
        if canary_signal.canary_active:
            n_limit = min(int(n_limit), int(max(0, canary_signal.allowed_symbols)))
        if learner_qa_light == "YELLOW":
            logging.info("LEARNER_QA_YELLOW telemetry_only=1 no_scan_cap=1")

        if n_limit <= 0 and (not open_syms):
            probe_min = max(0, int(getattr(CFG, "eco_probe_symbols_when_flat", 1)))
            if probe_min > 0:
                n_limit = int(probe_min)
                logging.warning(f"ECO_PROBE_ENABLE symbols={n_limit} reason=flat_book")

        if n_limit <= 0:
            if open_syms:
                for sym in sorted(open_syms):
                    try:
                        cnt_pos = len(positions_map.get(sym, []))
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        cnt_pos = 0
                    logging.info(f"OPEN GUARD (P0/P1/P2) | {sym} | positions={cnt_pos}")
            return

        logging.info(
            f"SCAN_LIMIT global_mode={global_mode} n_max={int(n_max)} n_limit={int(n_limit)} "
            f"canary_active={int(canary_signal.canary_active)} learner_qa={learner_qa_light}"
        )

        base_topk = candidates[:n_limit]
        verdict_light = "INSUFFICIENT_DATA"
        scout = None

        # Query SCUD/tie-break path only on real near-tie cases.
        if has_near_tie_in_topk(candidates, n_limit):
            verdict = load_verdict(self.meta_dir)
            verdict_light = (verdict.get("light") if verdict else "INSUFFICIENT_DATA")
            if verdict_light == "GREEN":
                scout = load_scout_advice(self.meta_dir)
                # Tie-break (mode B): only for GREEN + near-tie (also in LIVE).
                candidates = apply_scout_tiebreak(
                    candidates=candidates,
                    scout=scout,
                    verdict=verdict,
                    top_k=n_limit,
                    is_live=(not self.is_paper),
                    run_dir=self.run_dir,
                )
            else:
                logging.info(f"TIEBREAK_SKIP verdict_light={verdict_light} reason=not_green")
        final_topk = candidates[:n_limit]

        shadowB = None
        if scout and scout.get("preferred_symbol"):
            pref = str(scout.get("preferred_symbol")).strip().upper()
            for (_prio, raw, _sym, _grp) in base_topk:
                if str(raw).upper() == pref:
                    shadowB = pref
                    break

        # Metadane dla logowania decyzji (Strategy.try_trade → DecisionEventStore)
        try:
            def _topk_rows(src: List[Tuple[float, str, str, str]]) -> List[Dict[str, Any]]:
                out: List[Dict[str, Any]] = []
                for (p, r, s, g) in src:
                    gk = _group_key(g)
                    rs = group_risk.get(gk) or group_market_risk_state(gk)
                    rank_adj = unified_rank_map.get(str(symbol_base(s))) if isinstance(unified_rank_map, dict) else None
                    out.append(
                        {
                            "prio": float(p),
                            "raw": r,
                            "sym": s,
                            "grp": g,
                            "risk_entry_allowed": bool(rs.get("entry_allowed", True)),
                            "risk_reason": str(rs.get("reason", "NONE")),
                            "risk_friday": bool(rs.get("friday_risk", False)),
                            "risk_reopen": bool(rs.get("reopen_guard", False)),
                            "unified_rank_adjustment": (dict(rank_adj) if isinstance(rank_adj, dict) else None),
                        }
                    )
                return out

            self.strategy._scan_meta = {
                "server_time_anchor": self.time_anchor.server_now_utc().replace(tzinfo=UTC).isoformat().replace("+00:00", "Z"),
                "trade_window": {
                    "phase": str(tw_phase),
                    "window_id": str(tw_window_id),
                    "group": str(tw_group),
                    "entry_allowed": bool(tw_entry_allowed),
                    "strict_group": bool(tw_strict_group),
                },
                "global_mode": str(global_mode),
                "eco_by_budget": bool(eco_by_budget),
                "eco_reason": str(eco_reason),
                "fx_rotation": {"bucket_idx": int(fx_bucket_idx), "bucket_count": int(fx_bucket_count)},
                "carryover": {"active": bool(carryover_active)},
                "verdict_light": verdict_light,
                "choice_shadowB": shadowB,
                "policy_shadow_mode": bool(getattr(CFG, "policy_shadow_mode_enabled", True)),
                "policy_flags": {
                    "windows_v2_enabled": bool(getattr(CFG, "policy_windows_v2_enabled", True)),
                    "risk_windows_enabled": bool(getattr(CFG, "policy_risk_windows_enabled", True)),
                    "group_arbitration_enabled": bool(getattr(CFG, "policy_group_arbitration_enabled", True)),
                    "overlap_arbitration_enabled": bool(getattr(CFG, "policy_overlap_arbitration_enabled", True)),
                },
                "black_swan_stress": float(black_swan_signal.stress_index),
                "black_swan_flag": bool(black_swan_signal.black_swan),
                "black_swan_precaution": bool(black_swan_signal.precaution),
                "black_swan_reasons": list(black_swan_signal.reasons),
                "black_swan_v2_state": str(getattr(self, "_black_swan_v2_state", "NORMAL")),
                "black_swan_v2_action": str(getattr(self, "_black_swan_v2_action", "ALLOW")),
                "black_swan_v2_reason": str(getattr(self, "_black_swan_v2_reason", "NONE")),
                "black_swan_v2_block_new_entries": bool(getattr(self, "_black_swan_block_new_entries", False)),
                "self_heal_active": bool(self_heal_signal.active),
                "self_heal_reasons": list(self_heal_signal.reasons),
                "self_heal_loss_streak": int(self_heal_signal.loss_streak),
                "self_heal_net_pnl": float(self_heal_signal.net_pnl),
                "canary_active": bool(canary_signal.canary_active),
                "canary_pause": bool(canary_signal.pause),
                "canary_reasons": list(canary_signal.reasons),
                "canary_allowed_symbols": int(canary_signal.allowed_symbols),
                "drift_active": bool(drift_signal.active),
                "drift_reasons": list(drift_signal.reasons),
                "drift_zscore": float(drift_signal.zscore),
                "snapshot_health": dict(snapshot_health),
                "snapshot_block_new_entries": bool(snapshot_block_new_entries),
                "learner_qa_light": str(learner_qa_light),
                "unified_learning": unified_learning,
                "unified_learning_rank_map": dict(unified_rank_map),
                "topk_base": _topk_rows(base_topk),
                "topk_final": _topk_rows(final_topk),
                "proposals": {},
                "group_arb": {
                    str(g): {
                        "risk_entry_allowed": bool((group_risk.get(str(g), {}) or {}).get("entry_allowed", True)),
                        "risk_reason": str((group_risk.get(str(g), {}) or {}).get("reason", "NONE")),
                        "risk_friday": bool((group_risk.get(str(g), {}) or {}).get("friday_risk", False)),
                        "risk_reopen": bool((group_risk.get(str(g), {}) or {}).get("reopen_guard", False)),
                        "priority_factor": float((group_arb.get(str(g), {}) or {}).get("priority_factor", 1.0)),
                    }
                    for g in sorted(set(list(group_arb.keys()) + list(group_risk.keys())))
                },
            }
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        cnt = 0
        for prio, raw, sym, grp in candidates:
            if cnt >= n_limit:
                break

            live_gate = self._live_entry_contract(sym, grp)
            if not bool(live_gate.get("entry_allowed", False)):
                self.strategy._metric_inc_skip(str(live_gate.get("reason_code") or "LIVE_GATE_BLOCK"))
                logging.info(
                    "ENTRY_SKIP_HARD_LIVE symbol=%s grp=%s reason=%s module_state=%s module_reasons=%s",
                    sym,
                    _group_key(grp),
                    str(live_gate.get("reason_code") or "UNKNOWN"),
                    str(live_gate.get("module_state") or "UNKNOWN"),
                    ",".join([str(x) for x in (live_gate.get("module_state_reasons") or [])]),
                )
                self._append_execution_telemetry(
                    {
                        "event_type": "ENTRY_SKIP_HARD_LIVE",
                        "symbol_raw": str(sym),
                        "symbol_canonical": str(live_gate.get("symbol_canonical") or canonical_symbol(sym)),
                        "group": str(_group_key(grp)),
                        "reason_code": str(live_gate.get("reason_code") or "UNKNOWN"),
                        "module_state": str(live_gate.get("module_state") or "UNKNOWN"),
                        "module_state_reasons": list(live_gate.get("module_state_reasons") or []),
                        "method": "live_contract_gate",
                        "sample_size_n": 1,
                        "low_stat_power": True,
                        "source_list": [str(self.live_canary_contract_path), str(self.no_live_drift_path)],
                        "timezone_basis": "UTC",
                        "exact_window": str(
                            f"{tw_ctx.get('phase') or 'UNKNOWN'}:{tw_ctx.get('window_id') or 'NONE'}"
                        ),
                        "symbol_filter": str(canonical_symbol(sym)),
                    }
                )
                cnt += 1
                continue

            # V1.10: jeśli jest już otwarta pozycja na symbolu, nie otwieraj kolejnej (bez świadomej decyzji).
            if sym in open_syms:
                logging.debug(f"SKIP NEW ENTRY (open position) | {sym}")
                continue

            mode = self._effective_mode_for_symbol(grp, sym, global_mode, rollover_safe)
            info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
            if info is None:
                logging.warning(f"SYMBOL INFO missing | {sym} | skip")
                cnt += 1
                continue
            try:
                self.strategy.set_skip_capture_context(sym, grp, mode, stage="EVALUATE")
                self.strategy.evaluate_symbol(sym, grp, mode, info, self.is_paper)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                logging.exception("Exception in evaluate_symbol")
                traceback.print_exc()
            finally:
                self.strategy.clear_skip_capture_context()
            cnt += 1

        # Export market snapshot for Scout (no extra MT5 requests; uses cached info/indicators)
        try:
            now_iso = now_utc().isoformat().replace('+00:00','Z')
            topk_for_snapshot = []
            for (p, raw, sym, grp) in candidates[:n_limit]:
                info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
                ind = self.strategy.last_indicators.get(str(raw)) if hasattr(self.strategy, 'last_indicators') else None
                gk = _group_key(grp)
                rs = group_risk.get(gk) or group_market_risk_state(gk)
                topk_for_snapshot.append({
                    'raw': raw,
                    'sym': sym,
                    'grp': grp,
                    'prio': float(p),
                    'adx': (ind.get('adx') if isinstance(ind, dict) else None),
                    'atr': (ind.get('atr') if isinstance(ind, dict) else None),
                    'risk_entry_allowed': bool(rs.get("entry_allowed", True)),
                    'risk_reason': str(rs.get("reason", "NONE")),
                    'risk_friday': bool(rs.get("friday_risk", False)),
                    'risk_reopen': bool(rs.get("reopen_guard", False)),
                })
            snapshot = {
                'version': '1.0',
                'schema_version': '1.0',
                'ts_utc': now_iso,
                'ttl_sec': SCOUT_MAX_AGE_SEC,
                'server_time_anchor': self.time_anchor.server_now_utc().replace(tzinfo=UTC).isoformat().replace('+00:00','Z'),
                'global_mode': global_mode,
                'verdict_light': (self.strategy._scan_meta.get('verdict_light') if hasattr(self.strategy, '_scan_meta') else None),
                'black_swan_stress': (self.strategy._scan_meta.get('black_swan_stress') if hasattr(self.strategy, '_scan_meta') else None),
                'black_swan_flag': (self.strategy._scan_meta.get('black_swan_flag') if hasattr(self.strategy, '_scan_meta') else None),
                'black_swan_precaution': (self.strategy._scan_meta.get('black_swan_precaution') if hasattr(self.strategy, '_scan_meta') else None),
                'self_heal_active': (self.strategy._scan_meta.get('self_heal_active') if hasattr(self.strategy, '_scan_meta') else None),
                'self_heal_loss_streak': (self.strategy._scan_meta.get('self_heal_loss_streak') if hasattr(self.strategy, '_scan_meta') else None),
                'self_heal_net_pnl': (self.strategy._scan_meta.get('self_heal_net_pnl') if hasattr(self.strategy, '_scan_meta') else None),
                'canary_active': (self.strategy._scan_meta.get('canary_active') if hasattr(self.strategy, '_scan_meta') else None),
                'canary_pause': (self.strategy._scan_meta.get('canary_pause') if hasattr(self.strategy, '_scan_meta') else None),
                'drift_active': (self.strategy._scan_meta.get('drift_active') if hasattr(self.strategy, '_scan_meta') else None),
                'drift_zscore': (self.strategy._scan_meta.get('drift_zscore') if hasattr(self.strategy, '_scan_meta') else None),
                'snapshot_health': (self.strategy._scan_meta.get('snapshot_health') if hasattr(self.strategy, '_scan_meta') else None),
                'snapshot_block_new_entries': (self.strategy._scan_meta.get('snapshot_block_new_entries') if hasattr(self.strategy, '_scan_meta') else None),
                'learner_qa_light': (self.strategy._scan_meta.get('learner_qa_light') if hasattr(self.strategy, '_scan_meta') else None),
                'policy_shadow_mode': (self.strategy._scan_meta.get('policy_shadow_mode') if hasattr(self.strategy, '_scan_meta') else None),
                'policy_flags': (self.strategy._scan_meta.get('policy_flags') if hasattr(self.strategy, '_scan_meta') else None),
                'topk': topk_for_snapshot,
            }
            # P0 numeric limits: truncate topk deterministically if needed
            try:
                guard_obj_limits(snapshot)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                try:
                    topk = snapshot.get('topk')
                    if isinstance(topk, list):
                        while topk and True:
                            try:
                                guard_obj_limits(snapshot)
                                break
                            except Exception as e:
                                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                                topk.pop()
                        snapshot['topk'] = topk
                    # final attempt; if still failing, drop topk
                    try:
                        guard_obj_limits(snapshot)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        snapshot['topk'] = []
                except Exception as e:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    snapshot['topk'] = []
            
            atomic_write_json(self.meta_dir / MARKET_SNAPSHOT_FILE_NAME, snapshot)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _idle_sleep_with_usb_watch(self, seconds: int):
        base = int(max(0, seconds))
        if base < 10:
            logging.info(f"SLEEP_CLAMP | requested={base}s clamped=10s")
            base = 10
        step = int(max(1, getattr(CFG, "usb_watch_check_interval_sec", 1)))
        elapsed = 0
        while elapsed < base:
            wait_s = min(step, base - elapsed)
            time.sleep(wait_s)
            elapsed += wait_s
            if not usb_present():
                logging.critical("USB MISSING | KILL SWITCH => FORCE FLAT + STOP")
                ok = self.execution_engine.force_flat_all(self.db, retries=CFG.close_retries, delay=CFG.close_retry_delay_sec,
                                            deviation=CFG.kill_close_deviation_points)
                if not ok:
                    logging.critical("KILL SWITCH | FORCE FLAT incomplete.")
                sys.exit(2)

    def _send_trade_command(
        self,
        signal: str,
        symbol: str,
        volume: float,
        sl_price: float,
        tp_price: float,
        request_price: float,
        deviation_points: int,
        spread_at_decision_points: Optional[float],
        spread_unit: str,
        spread_provenance: str,
        estimated_entry_cost_components: Optional[Dict[str, Any]],
        estimated_round_trip_cost: Optional[Dict[str, Any]],
        cost_feasibility_shadow: Optional[bool],
        net_cost_feasible: Optional[bool],
        cost_gate_policy_mode: str,
        cost_gate_reason_code: str,
        magic: int,
        comment: str,
        group: str = "",
        risk_entry_allowed: bool = True,
        risk_reason: str = "NONE",
        risk_friday: bool = False,
        risk_reopen: bool = False,
        policy_shadow_mode: bool = True,
    ) -> Optional[Dict[str, Any]]:
        """Sends a synchronous trade command to MQL5 and returns parsed reply."""
        effective_trigger_mode = self._trade_trigger_mode()
        if effective_trigger_mode == "MQL5_ACTIVE":
            # Docelowy cutover: brak współdecydowania Python/bridge na ticku.
            logging.info(
                "TRADE_BRIDGE_BYPASS mode=%s symbol=%s signal=%s",
                effective_trigger_mode,
                str(symbol or ""),
                str(signal or "").upper(),
            )
            return {
                "status": "SKIPPED",
                "action": "TRADE_REPLY",
                "retcode": int(getattr(mt5, "TRADE_RETCODE_TRADE_DISABLED", 10017)),
                "retcode_str": "MQL5_ACTIVE_BRIDGE_BYPASS",
                "comment": "Bridge bypass enabled in MQL5_ACTIVE mode.",
                "symbol": str(symbol or ""),
                "request_hash": "",
                "details": {
                    "retcode": int(getattr(mt5, "TRADE_RETCODE_TRADE_DISABLED", 10017)),
                    "retcode_str": "MQL5_ACTIVE_BRIDGE_BYPASS",
                    "comment": "Bridge bypass enabled in MQL5_ACTIVE mode.",
                },
            }

        def _f(v: Any, default: float = 0.0) -> float:
            try:
                return float(v)
            except Exception:
                return float(default)

        def _i(v: Any, default: int = 0) -> int:
            try:
                return int(v)
            except Exception:
                return int(default)

        command = {
            "action": "TRADE",
            "msg_id": str(uuid.uuid4()),
            "command_id": "",
            "request_id": "",
            "schema_version": "1.0",
            "policy_version": "runtime.v1",
            "timestamp_semantics": "UTC",
            "payload": {
                "signal": str(signal).upper(),
                # Preserve broker symbol casing/suffix as resolved by MT5 (e.g. ".pro").
                "symbol": str(symbol).strip(),
                "symbol_raw": str(symbol).strip(),
                "symbol_canonical": canonical_symbol(symbol),
                "volume": _f(volume, 0.0),
                "sl_price": _f(sl_price, 0.0),
                "tp_price": _f(tp_price, 0.0),
                "request_price": _f(request_price, 0.0),
                "deviation_points": _i(deviation_points, 0),
                "deviation_unit": "points",
                "spread_at_decision": (
                    None if spread_at_decision_points is None else _f(spread_at_decision_points, 0.0)
                ),
                "spread_unit": str(spread_unit or "AMBIGUOUS_UNIT"),
                "spread_provenance": str(spread_provenance or "UNKNOWN"),
                "estimated_entry_cost_components": dict(estimated_entry_cost_components or {}),
                "estimated_round_trip_cost": dict(estimated_round_trip_cost or {}),
                "cost_feasibility_shadow": (
                    None if cost_feasibility_shadow is None else bool(cost_feasibility_shadow)
                ),
                "net_cost_feasible": (None if net_cost_feasible is None else bool(net_cost_feasible)),
                "cost_gate_policy_mode": str(cost_gate_policy_mode or "DIAGNOSTIC_ONLY"),
                "cost_gate_reason_code": str(cost_gate_reason_code or "NONE"),
                "magic": _i(magic, 0),
                "comment": str(comment),
                "group": str(group or ""),
                "risk_entry_allowed": bool(risk_entry_allowed),
                "risk_reason": str(risk_reason or "NONE"),
                "risk_friday": bool(risk_friday),
                "risk_reopen": bool(risk_reopen),
                "policy_shadow_mode": bool(policy_shadow_mode),
            }
        }
        command["command_id"] = str(command["msg_id"])
        command["request_id"] = str(command["msg_id"])
        command["loop_id"] = int(getattr(self, "_runtime_loop_id", 0) or 0)
        command["bridge_contract_version"] = "bridge.safe.v1"
        command["request_ts_utc"] = now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")
        command["request_ts_semantics"] = "UTC"
        command["request_hash"] = str(build_request_hash(command))
        logging.info(
            "ZMQ_SEND | action=TRADE signal=%s symbol=%s volume=%.6f deviation_points=%s",
            command["payload"]["signal"],
            command["payload"]["symbol"],
            float(command["payload"]["volume"]),
            int(command["payload"]["deviation_points"]),
        )
        if str(command["payload"].get("spread_unit") or "").strip().upper() in {"", "UNKNOWN", "AMBIGUOUS_UNIT"}:
            self._emit_unit_diagnostic(
                parameter_name="spread_at_decision",
                current_unit=str(command["payload"].get("spread_unit") or "AMBIGUOUS_UNIT"),
                expected_unit="points",
                risk_level="HIGH",
                details={"symbol": str(command["payload"].get("symbol") or ""), "phase": "send_trade_command"},
            )
        reply = self.zmq_bridge.send_command(
            command,
            timeout_ms=int(max(1, getattr(CFG, "bridge_trade_timeout_ms", getattr(CFG, "bridge_default_timeout_ms", 1200)))),
            max_retries=int(max(1, getattr(CFG, "bridge_trade_retries", getattr(CFG, "bridge_default_retries", 1)))),
            loop_id=str(int(command.get("loop_id") or 0)),
        )
        self._record_bridge_diag(self.zmq_bridge.get_last_command_diag(), action="TRADE")
        if not isinstance(reply, dict):
            logging.error("ZMQ_SEND_FAIL | No reply from MQL5 for TRADE command.")
            return None
        if str(reply.get("correlation_id") or "") != str(command.get("msg_id") or ""):
            logging.error(
                "ZMQ_REPLY_FAIL | correlation mismatch expected=%s got=%s",
                str(command.get("msg_id") or ""),
                str(reply.get("correlation_id") or ""),
            )
            return None
        req_hash_reply = str(reply.get("request_hash") or "")
        if req_hash_reply and req_hash_reply != str(command.get("request_hash") or ""):
            logging.error(
                "ZMQ_REPLY_FAIL | request_hash mismatch expected=%s got=%s",
                str(command.get("request_hash") or ""),
                req_hash_reply,
            )
            return None
        got_resp_hash = str(reply.get("response_hash") or "")
        if not got_resp_hash:
            logging.error("ZMQ_REPLY_FAIL | missing response_hash")
            return None
        exp_resp_hash = str(build_response_hash(reply))
        if got_resp_hash != exp_resp_hash:
            logging.error(
                "ZMQ_REPLY_FAIL | response_hash mismatch expected=%s got=%s",
                exp_resp_hash,
                got_resp_hash,
            )
            return None
        details_obj = reply.get("details") if isinstance(reply.get("details"), dict) else {}
        try:
            dev_req = int(details_obj.get("deviation_requested_points", 0) or 0)
            dev_eff = int(details_obj.get("deviation_effective_points", 0) or 0)
            if dev_eff >= 0:
                self._last_trade_slippage_points = float(dev_eff)
            expected_dev = int(command["payload"].get("deviation_points") or 0)
            if dev_req > 0 and expected_dev > 0 and dev_req != expected_dev:
                self._emit_unit_diagnostic(
                    parameter_name="order_deviation_points",
                    current_unit="points",
                    expected_unit="points",
                    risk_level="HIGH",
                    details={
                        "msg_id": str(command.get("msg_id") or ""),
                        "symbol": str(command["payload"].get("symbol") or ""),
                        "deviation_expected_points": expected_dev,
                        "deviation_requested_points": dev_req,
                    },
                )
            if dev_req > 0 and dev_eff > (dev_req * 4):
                self._emit_unit_diagnostic(
                    parameter_name="deviation_effective_points",
                    current_unit="points",
                    expected_unit="points",
                    risk_level="MED",
                    details={
                        "msg_id": str(command.get("msg_id") or ""),
                        "symbol": str(command["payload"].get("symbol") or ""),
                        "deviation_requested_points": dev_req,
                        "deviation_effective_points": dev_eff,
                    },
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        reply["__request_context"] = {
            "message_id": str(command.get("msg_id") or ""),
            "command_id": str(command.get("command_id") or ""),
            "request_id": str(command.get("request_id") or ""),
            "symbol_raw": str(command["payload"].get("symbol_raw") or ""),
            "symbol_canonical": str(command["payload"].get("symbol_canonical") or ""),
            "request_price": _f(command["payload"].get("request_price"), 0.0),
            "deviation_requested_points": _i(command["payload"].get("deviation_points"), 0),
            "spread_at_decision": command["payload"].get("spread_at_decision"),
            "spread_unit": str(command["payload"].get("spread_unit") or "UNKNOWN"),
            "spread_provenance": str(command["payload"].get("spread_provenance") or "UNKNOWN"),
            "estimated_entry_cost_components": dict(command["payload"].get("estimated_entry_cost_components") or {}),
            "estimated_round_trip_cost": dict(command["payload"].get("estimated_round_trip_cost") or {}),
            "cost_feasibility_shadow": command["payload"].get("cost_feasibility_shadow"),
            "net_cost_feasible": command["payload"].get("net_cost_feasible"),
            "cost_gate_policy_mode": str(command["payload"].get("cost_gate_policy_mode") or "DIAGNOSTIC_ONLY"),
            "cost_gate_reason_code": str(command["payload"].get("cost_gate_reason_code") or "NONE"),
            "timestamp_utc": str(command.get("request_ts_utc") or ""),
            "timestamp_semantics": "UTC",
        }
        logging.info(
            "ZMQ_REPLY | status=%s correlation_id=%s",
            str(reply.get("status") or "UNKNOWN"),
            str(reply.get("correlation_id") or ""),
        )
        return reply

    def _handle_market_data(self, data: Dict[str, Any]):
        """
        Główny punkt wejścia dla danych rynkowych przychodzących z Agenta MQL5.
        Integruje przychodzące dane z logiką SafetyBot.
        """
        msg_type = str(data.get("type") or "").upper()
        symbol = data.get("symbol")
        schema_v = str(data.get("schema_version") or data.get("__v") or "").strip()

        if schema_v and schema_v != "1.0":
            logging.warning("ZMQ_DATA_SCHEMA_MISMATCH symbol=%s type=%s schema_version=%s", symbol, msg_type, schema_v)
            return

        now_ts = float(time.time())

        if msg_type == "ACCOUNT":
            self._handle_account_snapshot(data, now_ts=now_ts)
            return

        if not symbol:
            return

        base_symbol = symbol_base(symbol)
        if msg_type == "TICK":
            self._handle_tick_snapshot(symbol=symbol, base_symbol=base_symbol, data=data, now_ts=now_ts)
            return
        if msg_type == "BAR":
            self._handle_bar_snapshot(symbol=symbol, base_symbol=base_symbol, data=data, now_ts=now_ts)

    def _handle_account_snapshot(self, data: Dict[str, Any], *, now_ts: float) -> None:
        try:
            self._zmq_account_cache.clear()
            self._zmq_account_cache.update(
                {
                    "recv_ts": now_ts,
                    "balance": float(data.get("balance", 0.0) or 0.0),
                    "equity": float(data.get("equity", 0.0) or 0.0),
                    "margin_free": float(data.get("margin_free", 0.0) or 0.0),
                    "margin_level": float(data.get("margin_level", 0.0) or 0.0),
                }
            )
            if isinstance(self.execution_engine._account_info_static_cache, dict):
                self.execution_engine._account_info_static_cache.clear()
                self.execution_engine._account_info_static_cache.update(
                    {
                        "recv_ts": now_ts,
                        "seed_static": False,
                        "balance": float(data.get("balance", 0.0) or 0.0),
                        "equity": float(data.get("equity", 0.0) or 0.0),
                        "margin_free": float(data.get("margin_free", 0.0) or 0.0),
                        "margin_level": float(data.get("margin_level", 0.0) or 0.0),
                    }
                )
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

    def _handle_tick_snapshot(self, *, symbol: str, base_symbol: str, data: Dict[str, Any], now_ts: float) -> None:
        if hasattr(self.execution_engine, "_zmq_tick_cache"):
            self.execution_engine._zmq_tick_cache[symbol] = data
            self.execution_engine._zmq_tick_cache[base_symbol] = data
        self._zmq_last_tick_ts[base_symbol] = now_ts
        tick_persisted = False

        try:
            point = float(data.get("point", 0.0) or 0.0)
            bid = float(data.get("bid", 0.0) or 0.0)
            ask = float(data.get("ask", 0.0) or 0.0)
            spread_pts = float(data.get("spread_points", 0.0) or 0.0)
            if spread_pts <= 0.0 and point > 0.0:
                spread_pts = max(0.0, float((ask - bid) / point))
            self._zmq_symbol_info_cache[base_symbol] = {
                "recv_ts": now_ts,
                "point": point,
                "digits": int(data.get("digits", 0) or 0),
                "spread": spread_pts,
                "trade_tick_size": float(data.get("trade_tick_size", 0.0) or 0.0),
                "trade_tick_value": float(data.get("trade_tick_value", 0.0) or 0.0),
                "volume_min": float(data.get("volume_min", 0.0) or 0.0),
                "volume_max": float(data.get("volume_max", 0.0) or 0.0),
                "volume_step": float(data.get("volume_step", 0.0) or 0.0),
                "trade_stops_level": int(data.get("trade_stops_level", 0) or 0),
                "trade_freeze_level": int(data.get("trade_freeze_level", 0) or 0),
            }
            prev = dict(self._micro_tick_state.get(base_symbol) or {})
            prev_ts = float(prev.get("recv_ts", 0.0) or 0.0)
            prev_mid = float(prev.get("mid", 0.0) or 0.0)
            mql5_tick_gap_sec: Optional[float] = None
            mql5_price_jump_points: Optional[float] = None
            mql5_ask_lt_bid: Optional[bool] = None
            try:
                if data.get("tick_gap_sec") is not None:
                    mql5_tick_gap_sec = max(0.0, float(data.get("tick_gap_sec") or 0.0))
            except Exception:
                mql5_tick_gap_sec = None
            try:
                if data.get("price_jump_points") is not None:
                    mql5_price_jump_points = max(0.0, float(data.get("price_jump_points") or 0.0))
            except Exception:
                mql5_price_jump_points = None
            try:
                if data.get("ask_lt_bid") is not None:
                    mql5_ask_lt_bid = bool(data.get("ask_lt_bid"))
            except Exception:
                mql5_ask_lt_bid = None
            tick_gap_sec = None
            if prev_ts > 0.0:
                tick_gap_sec = max(0.0, float(now_ts) - float(prev_ts))
            mid = 0.0
            if bid > 0.0 and ask > 0.0:
                mid = (bid + ask) * 0.5
            price_jump_points = None
            if point > 0.0 and prev_mid > 0.0 and mid > 0.0:
                price_jump_points = abs(float(mid) - float(prev_mid)) / float(point)
            if mql5_tick_gap_sec is not None:
                tick_gap_sec = float(mql5_tick_gap_sec)
            if mql5_price_jump_points is not None:
                price_jump_points = float(mql5_price_jump_points)
            ask_lt_bid_flag = bool((ask > 0.0 and bid > 0.0) and (ask < bid))
            if mql5_ask_lt_bid is not None:
                ask_lt_bid_flag = bool(mql5_ask_lt_bid)
            self._micro_tick_state[base_symbol] = {
                "recv_ts": float(now_ts),
                "mid": float(mid),
                "tick_gap_sec": tick_gap_sec,
                "price_jump_points": price_jump_points,
                "ask_lt_bid": bool(ask_lt_bid_flag),
                "tick_rate_1s": (
                    None if data.get("tick_rate_1s") is None else int(max(0, int(data.get("tick_rate_1s") or 0)))
                ),
                "spread_roll_mean_points": (
                    None
                    if data.get("spread_roll_mean_points") is None
                    else float(max(0.0, float(data.get("spread_roll_mean_points") or 0.0)))
                ),
                "spread_roll_p95_points": (
                    None
                    if data.get("spread_roll_p95_points") is None
                    else float(max(0.0, float(data.get("spread_roll_p95_points") or 0.0)))
                ),
                "stale_tick_flag": bool(data.get("stale_tick_flag", False)),
                "burst_flag": bool(data.get("burst_flag", False)),
                "quality_flags": str(data.get("quality_flags") or "UNKNOWN"),
            }
            if bool(getattr(CFG, "renko_tick_store_enabled", True)) and getattr(self, "tick_store", None) is not None:
                tick_persisted = bool(self.tick_store.upsert_tick_snapshot(base_symbol, data, recv_ts=now_ts))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        logging.debug(
            "ZMQ_TICK | %s | Bid: %s Ask: %s persisted=%s",
            symbol,
            data.get("bid"),
            data.get("ask"),
            int(bool(tick_persisted)),
        )

    def _handle_bar_snapshot(self, *, symbol: str, base_symbol: str, data: Dict[str, Any], now_ts: float) -> None:
        self._zmq_last_bar_ts[base_symbol] = now_ts
        persisted = False
        try:
            if getattr(self, "bars_store", None) is not None:
                persisted = bool(self.bars_store.upsert_bar_snapshot(base_symbol, data))
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        try:
            if all(k in data for k in ("open", "close", "sma_fast", "adx", "atr", "time")):
                ts = int(data.get("time") or 0)
                if ts > 0:
                    _maybe_update_mt5_server_epoch_offset(
                        int(ts),
                        source="zmq_feature_bar",
                        max_age_s=max(300, int(getattr(CFG, "hybrid_snapshot_bar_max_age_sec", 900))),
                    )
                    bar_ts_pl = pd.Timestamp(mt5_epoch_to_utc_dt(int(ts)).astimezone(TZ_PL))
                    self._zmq_m5_feature_cache[base_symbol] = {
                        "recv_ts": now_ts,
                        "bar_time_pl": bar_ts_pl,
                        "open": float(data.get("open")),
                        "close": float(data.get("close")),
                        "sma_fast": float(data.get("sma_fast")),
                        "adx": float(data.get("adx")),
                        "atr": float(data.get("atr")),
                    }
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        logging.info(
            "ZMQ_BAR | %s | Time: %s Close: %s persisted=%s",
            symbol,
            data.get("time"),
            data.get("close"),
            int(bool(persisted)),
        )

    def run(self):
        self._runtime_log_startup()
        loop_cfg = build_runtime_loop_settings(CFG)
        loop_state: Dict[str, Any] = build_runtime_loop_state()
        logging.info(
            "BRIDGE_BUDGETS trade_timeout_ms=%s trade_retries=%s heartbeat_timeout_ms=%s heartbeat_retries=%s hb_lock_timeout_ms=%s",
            int(loop_cfg.trade_timeout_budget_ms),
            int(loop_cfg.trade_retries_budget),
            int(loop_cfg.heartbeat_timeout_budget_ms),
            int(loop_cfg.heartbeat_retries_budget),
            int(loop_cfg.heartbeat_queue_lock_timeout_ms),
        )

        try:
            while True:
                if not self._runtime_loop_step(loop_cfg=loop_cfg, loop_state=loop_state):
                    break

        except KeyboardInterrupt:
            logging.info("BOT STOP | manual (Ctrl+C)")
        except Exception as e:
            cg.tlog(None, "CRITICAL", "SB_FATAL", "Błąd krytyczny pętli głównej", e)
            logging.error(f"MAIN LOOP ERROR | {e}", exc_info=True)
        finally:
            logging.info("Zamykanie bota i zwalnianie zasobów...")
            if self.execution_queue:
                self.execution_queue.stop()

    def _runtime_log_startup(self) -> None:
        logging.info(f"BOT START | HYBRID MODE | MT5 SAFETY BOT {CFG.BOT_VERSION}")
        logging.info("Uruchamianie pętli hybrydowej (ZMQ + Periodic Scan)...")
        requested_trigger_mode = str(getattr(CFG, "trade_trigger_mode", "BRIDGE_ACTIVE") or "BRIDGE_ACTIVE").strip().upper()
        effective_trigger_mode, trigger_mode_reason = self._trade_trigger_mode_info()
        if requested_trigger_mode != effective_trigger_mode:
            logging.warning(
                "TRADE_TRIGGER_MODE_FALLBACK requested=%s effective=%s reason=%s",
                requested_trigger_mode,
                effective_trigger_mode,
                str(trigger_mode_reason or "UNKNOWN"),
            )
        logging.info("TRADE_TRIGGER_MODE mode=%s", effective_trigger_mode)


if __name__ == "__main__":
    
    # --- Dependency Injection Container ---
    run_mode = get_run_mode()
    runtime_root = get_runtime_root(enforce=True)
    _paths = project_paths(runtime_root)
    
    config = ConfigManager(_paths["config"])
    strategy_cfg = getattr(config, "strategy", {}) or {}
    raw_per_group = strategy_cfg.get("per_group", {}) if isinstance(strategy_cfg, dict) else {}
    if raw_per_group is None:
        raw_per_group = {}
    if not isinstance(raw_per_group, dict):
        raise SystemExit("CONFIG_STRATEGY_FAIL: per_group must be object")

    norm_per_group: Dict[str, Dict[str, Any]] = {}
    for gk, gv in raw_per_group.items():
        g = _group_key(gk)
        if g not in {"FX", "INDEX", "METAL"}:
            continue
        if gv is None:
            continue
        if not isinstance(gv, dict):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: per_group.{g} must be object")
        norm_per_group[g] = dict(gv)
    CFG.per_group = norm_per_group

    raw_per_symbol = strategy_cfg.get("per_symbol", {}) if isinstance(strategy_cfg, dict) else {}
    if raw_per_symbol is None:
        raw_per_symbol = {}
    if not isinstance(raw_per_symbol, dict):
        raise SystemExit("CONFIG_STRATEGY_FAIL: per_symbol must be object")
    norm_per_symbol: Dict[str, Dict[str, Any]] = {}
    for sk, sv in raw_per_symbol.items():
        if sv is None:
            continue
        if not isinstance(sv, dict):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: per_symbol.{sk} must be object")
        base = _symbol_key(str(sk))
        if not base:
            continue
        norm_per_symbol[base] = dict(sv)
    CFG.per_symbol = norm_per_symbol

    def _cfg_int(key: str, fallback: int | None = None) -> int:
        raw = strategy_cfg.get(key, fallback)
        try:
            return int(raw)
        except Exception:
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be int (got {raw!r})")

    def _cfg_bool(key: str, fallback: bool | None = None) -> bool:
        raw = strategy_cfg.get(key, fallback)
        if isinstance(raw, bool):
            return raw
        txt = str(raw).strip().lower()
        if txt in {"1", "true", "yes", "y", "on"}:
            return True
        if txt in {"0", "false", "no", "n", "off"}:
            return False
        raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be bool (got {raw!r})")

    def _cfg_float(key: str, fallback: float | None = None) -> float:
        raw = strategy_cfg.get(key, fallback)
        try:
            return float(raw)
        except Exception:
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be float (got {raw!r})")

    def _cfg_str_list(key: str, fallback: List[str]) -> List[str]:
        raw = strategy_cfg.get(key, fallback)
        if raw is None:
            return list(fallback)
        if not isinstance(raw, list):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be list (got {raw!r})")
        out: List[str] = []
        for item in raw:
            txt = str(item or "").strip().upper()
            if txt:
                out.append(txt)
        return out or list(fallback)

    def _cfg_hm(key: str, fallback: Tuple[int, int]) -> Tuple[int, int]:
        raw = strategy_cfg.get(key, fallback)
        if isinstance(raw, (list, tuple)) and len(raw) == 2:
            try:
                hh = int(raw[0])
                mm = int(raw[1])
            except Exception:
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be [HH,MM] or 'HH:MM'")
            if hh < 0 or hh > 23 or mm < 0 or mm > 59:
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} invalid HH/MM")
            return int(hh), int(mm)
        if isinstance(raw, str) and ":" in raw:
            hh, mm = _parse_hhmm(raw, default_hour=int(fallback[0]), default_minute=int(fallback[1]))
            return int(hh), int(mm)
        raise SystemExit(f"CONFIG_STRATEGY_FAIL: {key} must be [HH,MM] or 'HH:MM'")

    def _apply_runtime_loop_and_bridge_cfg() -> None:
        CFG.scan_interval_sec = _cfg_int("scan_interval_sec", CFG.scan_interval_sec)
        CFG.m5_wait_new_bar_max_sec = _cfg_int(
            "m5_wait_new_bar_max_sec",
            CFG.m5_wait_new_bar_max_sec,
        )
        CFG.zmq_heartbeat_interval_sec = _cfg_int(
            "zmq_heartbeat_interval_sec", CFG.zmq_heartbeat_interval_sec
        )
        CFG.zmq_heartbeat_fail_threshold = _cfg_int(
            "zmq_heartbeat_fail_threshold", CFG.zmq_heartbeat_fail_threshold
        )
        CFG.zmq_heartbeat_fail_safe_cooldown_sec = _cfg_int(
            "zmq_heartbeat_fail_safe_cooldown_sec",
            CFG.zmq_heartbeat_fail_safe_cooldown_sec,
        )
        CFG.zmq_heartbeat_fail_log_interval_sec = _cfg_int(
            "zmq_heartbeat_fail_log_interval_sec",
            CFG.zmq_heartbeat_fail_log_interval_sec,
        )
        CFG.zmq_scan_suppressed_log_interval_sec = _cfg_int(
            "zmq_scan_suppressed_log_interval_sec",
            CFG.zmq_scan_suppressed_log_interval_sec,
        )
        CFG.bridge_default_timeout_ms = _cfg_int("bridge_default_timeout_ms", CFG.bridge_default_timeout_ms)
        CFG.bridge_default_retries = _cfg_int("bridge_default_retries", CFG.bridge_default_retries)
        CFG.bridge_heartbeat_timeout_ms = _cfg_int("bridge_heartbeat_timeout_ms", CFG.bridge_heartbeat_timeout_ms)
        CFG.bridge_heartbeat_retries = _cfg_int("bridge_heartbeat_retries", CFG.bridge_heartbeat_retries)
        CFG.bridge_heartbeat_queue_lock_timeout_ms = _cfg_int(
            "bridge_heartbeat_queue_lock_timeout_ms",
            CFG.bridge_heartbeat_queue_lock_timeout_ms,
        )
        CFG.bridge_heartbeat_reconnect_on_timeout = _cfg_bool(
            "bridge_heartbeat_reconnect_on_timeout",
            CFG.bridge_heartbeat_reconnect_on_timeout,
        )
        CFG.bridge_heartbeat_timeout_nonfatal = _cfg_bool(
            "bridge_heartbeat_timeout_nonfatal",
            CFG.bridge_heartbeat_timeout_nonfatal,
        )
        CFG.bridge_heartbeat_trade_priority_window_ms = _cfg_int(
            "bridge_heartbeat_trade_priority_window_ms",
            CFG.bridge_heartbeat_trade_priority_window_ms,
        )
        CFG.bridge_audit_async_enabled = _cfg_bool(
            "bridge_audit_async_enabled",
            CFG.bridge_audit_async_enabled,
        )
        CFG.bridge_audit_queue_maxsize = _cfg_int(
            "bridge_audit_queue_maxsize",
            CFG.bridge_audit_queue_maxsize,
        )
        CFG.bridge_audit_queue_put_timeout_ms = _cfg_int(
            "bridge_audit_queue_put_timeout_ms",
            CFG.bridge_audit_queue_put_timeout_ms,
        )
        CFG.bridge_audit_batch_size = _cfg_int(
            "bridge_audit_batch_size",
            CFG.bridge_audit_batch_size,
        )
        CFG.bridge_audit_flush_interval_ms = _cfg_int(
            "bridge_audit_flush_interval_ms",
            CFG.bridge_audit_flush_interval_ms,
        )
        CFG.bridge_trade_timeout_ms = _cfg_int("bridge_trade_timeout_ms", CFG.bridge_trade_timeout_ms)
        CFG.bridge_trade_retries = _cfg_int("bridge_trade_retries", CFG.bridge_trade_retries)
        CFG.bridge_trade_probe_enabled = _cfg_bool(
            "bridge_trade_probe_enabled", CFG.bridge_trade_probe_enabled
        )
        CFG.bridge_trade_probe_interval_sec = _cfg_int(
            "bridge_trade_probe_interval_sec", CFG.bridge_trade_probe_interval_sec
        )
        CFG.bridge_trade_probe_max_per_run = _cfg_int(
            "bridge_trade_probe_max_per_run", CFG.bridge_trade_probe_max_per_run
        )
        CFG.bridge_trade_probe_signal = str(
            strategy_cfg.get("bridge_trade_probe_signal", CFG.bridge_trade_probe_signal)
            or CFG.bridge_trade_probe_signal
        ).strip().upper()
        if CFG.bridge_trade_probe_signal not in {"BUY", "SELL"}:
            CFG.bridge_trade_probe_signal = "BUY"
        CFG.bridge_trade_probe_symbol = str(
            strategy_cfg.get("bridge_trade_probe_symbol", CFG.bridge_trade_probe_symbol)
            or CFG.bridge_trade_probe_symbol
        ).strip()
        CFG.bridge_trade_probe_group = str(
            strategy_cfg.get("bridge_trade_probe_group", CFG.bridge_trade_probe_group)
            or CFG.bridge_trade_probe_group
        ).strip().upper()
        CFG.bridge_trade_probe_volume = _cfg_float(
            "bridge_trade_probe_volume", CFG.bridge_trade_probe_volume
        )
        CFG.bridge_trade_probe_deviation_points = _cfg_int(
            "bridge_trade_probe_deviation_points", CFG.bridge_trade_probe_deviation_points
        )
        CFG.bridge_trade_probe_comment = str(
            strategy_cfg.get("bridge_trade_probe_comment", CFG.bridge_trade_probe_comment)
            or CFG.bridge_trade_probe_comment
        ).strip()
        CFG.run_loop_idle_sleep_sec = _cfg_float("run_loop_idle_sleep_sec", CFG.run_loop_idle_sleep_sec)
        CFG.run_loop_scan_slow_warn_ms = _cfg_int(
            "run_loop_scan_slow_warn_ms",
            CFG.run_loop_scan_slow_warn_ms,
        )
        CFG.run_loop_scan_stats_window = _cfg_int(
            "run_loop_scan_stats_window",
            CFG.run_loop_scan_stats_window,
        )

    # Required runtime fields (previously declared-only) are now sourced from CONFIG/strategy.json.
    CFG.fixed_sl_points = _cfg_int("fixed_sl_points", CFG.fixed_sl_points)
    CFG.fixed_tp_points = _cfg_int("fixed_tp_points", CFG.fixed_tp_points)
    CFG.atr_period = _cfg_int("atr_period", CFG.atr_period)
    CFG.cooldown_stops_s = _cfg_int("cooldown_stops_s", CFG.cooldown_stops_s)
    CFG.paper_trading = _cfg_bool("paper_trading", CFG.paper_trading)
    CFG.eco_probe_symbols_when_flat = _cfg_int("eco_probe_symbols_when_flat", CFG.eco_probe_symbols_when_flat)
    CFG.sys_budget_day = _cfg_int("sys_budget_day", CFG.sys_budget_day)
    CFG.price_budget_day = _cfg_int("price_budget_day", CFG.price_budget_day)
    CFG.order_budget_day = _cfg_int("order_budget_day", CFG.order_budget_day)
    CFG.sys_emergency_reserve = _cfg_int("sys_emergency_reserve", CFG.sys_emergency_reserve)
    _apply_runtime_loop_and_bridge_cfg()
    CFG.runtime_metrics_interval_sec = _cfg_int(
        "runtime_metrics_interval_sec", CFG.runtime_metrics_interval_sec
    )
    CFG.min_seconds_between_orders = _cfg_float(
        "min_seconds_between_orders", CFG.min_seconds_between_orders
    )
    CFG.max_orders_per_minute = _cfg_int("max_orders_per_minute", CFG.max_orders_per_minute)
    CFG.max_orders_per_hour = _cfg_int("max_orders_per_hour", CFG.max_orders_per_hour)
    CFG.cooldown_no_money_s = _cfg_int("cooldown_no_money_s", CFG.cooldown_no_money_s)
    CFG.global_backoff_no_money_s = _cfg_int("global_backoff_no_money_s", CFG.global_backoff_no_money_s)
    CFG.fx_signal_score_enabled = _cfg_bool("fx_signal_score_enabled", CFG.fx_signal_score_enabled)
    CFG.fx_signal_score_threshold = _cfg_int("fx_signal_score_threshold", CFG.fx_signal_score_threshold)
    CFG.fx_signal_score_hot_relaxed_enabled = _cfg_bool(
        "fx_signal_score_hot_relaxed_enabled", CFG.fx_signal_score_hot_relaxed_enabled
    )
    CFG.fx_signal_score_hot_relaxed_threshold = _cfg_int(
        "fx_signal_score_hot_relaxed_threshold", CFG.fx_signal_score_hot_relaxed_threshold
    )
    CFG.fx_spread_cap_points_default = _cfg_float(
        "fx_spread_cap_points_default", CFG.fx_spread_cap_points_default
    )
    CFG.fx_atr_points_min = _cfg_float("fx_atr_points_min", CFG.fx_atr_points_min)
    CFG.fx_atr_points_max = _cfg_float("fx_atr_points_max", CFG.fx_atr_points_max)
    CFG.fx_impulse_atr_fraction_min = _cfg_float(
        "fx_impulse_atr_fraction_min", CFG.fx_impulse_atr_fraction_min
    )
    CFG.fx_body_range_ratio_min = _cfg_float("fx_body_range_ratio_min", CFG.fx_body_range_ratio_min)
    CFG.fx_body_vs_atr_clip_max = _cfg_float("fx_body_vs_atr_clip_max", CFG.fx_body_vs_atr_clip_max)
    CFG.fx_budget_pacing_enabled = _cfg_bool("fx_budget_pacing_enabled", CFG.fx_budget_pacing_enabled)
    CFG.fx_budget_pacing_phase1_progress = _cfg_float(
        "fx_budget_pacing_phase1_progress", CFG.fx_budget_pacing_phase1_progress
    )
    CFG.fx_budget_pacing_phase2_progress = _cfg_float(
        "fx_budget_pacing_phase2_progress", CFG.fx_budget_pacing_phase2_progress
    )
    CFG.fx_budget_pacing_phase1_ratio = _cfg_float(
        "fx_budget_pacing_phase1_ratio", CFG.fx_budget_pacing_phase1_ratio
    )
    CFG.fx_budget_pacing_phase2_ratio = _cfg_float(
        "fx_budget_pacing_phase2_ratio", CFG.fx_budget_pacing_phase2_ratio
    )
    CFG.fx_budget_pacing_slack = _cfg_float("fx_budget_pacing_slack", CFG.fx_budget_pacing_slack)
    CFG.metal_signal_score_enabled = _cfg_bool("metal_signal_score_enabled", CFG.metal_signal_score_enabled)
    CFG.metal_signal_score_threshold = _cfg_int("metal_signal_score_threshold", CFG.metal_signal_score_threshold)
    CFG.metal_signal_score_hot_relaxed_enabled = _cfg_bool(
        "metal_signal_score_hot_relaxed_enabled", CFG.metal_signal_score_hot_relaxed_enabled
    )
    CFG.metal_signal_score_hot_relaxed_threshold = _cfg_int(
        "metal_signal_score_hot_relaxed_threshold", CFG.metal_signal_score_hot_relaxed_threshold
    )
    CFG.metal_spread_cap_points_default = _cfg_float(
        "metal_spread_cap_points_default", CFG.metal_spread_cap_points_default
    )
    CFG.metal_atr_points_min = _cfg_float("metal_atr_points_min", CFG.metal_atr_points_min)
    CFG.metal_atr_points_max = _cfg_float("metal_atr_points_max", CFG.metal_atr_points_max)
    CFG.metal_impulse_atr_fraction_min = _cfg_float(
        "metal_impulse_atr_fraction_min", CFG.metal_impulse_atr_fraction_min
    )
    CFG.metal_body_range_ratio_min = _cfg_float("metal_body_range_ratio_min", CFG.metal_body_range_ratio_min)
    CFG.metal_body_vs_atr_clip_max = _cfg_float("metal_body_vs_atr_clip_max", CFG.metal_body_vs_atr_clip_max)
    CFG.metal_wick_rejection_ratio_min = _cfg_float(
        "metal_wick_rejection_ratio_min", CFG.metal_wick_rejection_ratio_min
    )
    CFG.metal_retest_distance_atr_max = _cfg_float(
        "metal_retest_distance_atr_max", CFG.metal_retest_distance_atr_max
    )
    CFG.metal_budget_pacing_enabled = _cfg_bool("metal_budget_pacing_enabled", CFG.metal_budget_pacing_enabled)
    CFG.metal_budget_pacing_phase1_progress = _cfg_float(
        "metal_budget_pacing_phase1_progress", CFG.metal_budget_pacing_phase1_progress
    )
    CFG.metal_budget_pacing_phase2_progress = _cfg_float(
        "metal_budget_pacing_phase2_progress", CFG.metal_budget_pacing_phase2_progress
    )
    CFG.metal_budget_pacing_phase1_ratio = _cfg_float(
        "metal_budget_pacing_phase1_ratio", CFG.metal_budget_pacing_phase1_ratio
    )
    CFG.metal_budget_pacing_phase2_ratio = _cfg_float(
        "metal_budget_pacing_phase2_ratio", CFG.metal_budget_pacing_phase2_ratio
    )
    CFG.metal_budget_pacing_slack = _cfg_float("metal_budget_pacing_slack", CFG.metal_budget_pacing_slack)
    CFG.crypto_signal_score_enabled = _cfg_bool(
        "crypto_signal_score_enabled", CFG.crypto_signal_score_enabled
    )
    CFG.crypto_signal_score_threshold = _cfg_int(
        "crypto_signal_score_threshold", CFG.crypto_signal_score_threshold
    )
    CFG.crypto_signal_score_hot_relaxed_enabled = _cfg_bool(
        "crypto_signal_score_hot_relaxed_enabled", CFG.crypto_signal_score_hot_relaxed_enabled
    )
    CFG.crypto_signal_score_hot_relaxed_threshold = _cfg_int(
        "crypto_signal_score_hot_relaxed_threshold", CFG.crypto_signal_score_hot_relaxed_threshold
    )
    CFG.crypto_major_risk_mult = _cfg_float("crypto_major_risk_mult", CFG.crypto_major_risk_mult)
    CFG.crypto_major_min_margin_free_pct = _cfg_float(
        "crypto_major_min_margin_free_pct", CFG.crypto_major_min_margin_free_pct
    )
    CFG.crypto_major_max_open_positions = _cfg_int(
        "crypto_major_max_open_positions", CFG.crypto_major_max_open_positions
    )
    CFG.crypto_no_money_backoff_s = _cfg_int("crypto_no_money_backoff_s", CFG.crypto_no_money_backoff_s)
    CFG.crypto_no_money_cooldown_s = _cfg_int("crypto_no_money_cooldown_s", CFG.crypto_no_money_cooldown_s)
    CFG.usb_watch_check_interval_sec = _cfg_int(
        "usb_watch_check_interval_sec", CFG.usb_watch_check_interval_sec
    )
    CFG.hybrid_use_zmq_m5_bars = _cfg_bool("hybrid_use_zmq_m5_bars", CFG.hybrid_use_zmq_m5_bars)
    CFG.hybrid_use_zmq_m5_features = _cfg_bool("hybrid_use_zmq_m5_features", CFG.hybrid_use_zmq_m5_features)
    CFG.hybrid_use_mtf_resample_from_m5_store = _cfg_bool(
        "hybrid_use_mtf_resample_from_m5_store",
        CFG.hybrid_use_mtf_resample_from_m5_store,
    )
    CFG.hybrid_m5_no_fetch_strict = _cfg_bool("hybrid_m5_no_fetch_strict", CFG.hybrid_m5_no_fetch_strict)
    CFG.hybrid_no_mt5_data_fetch_hard = _cfg_bool(
        "hybrid_no_mt5_data_fetch_hard",
        CFG.hybrid_no_mt5_data_fetch_hard,
    )
    CFG.hybrid_snapshot_max_age_sec = _cfg_int("hybrid_snapshot_max_age_sec", CFG.hybrid_snapshot_max_age_sec)
    CFG.hybrid_snapshot_bar_max_age_sec = _cfg_int(
        "hybrid_snapshot_bar_max_age_sec",
        CFG.hybrid_snapshot_bar_max_age_sec,
    )
    CFG.hybrid_snapshot_block_on_bar_only = _cfg_bool(
        "hybrid_snapshot_block_on_bar_only",
        CFG.hybrid_snapshot_block_on_bar_only,
    )
    CFG.hybrid_snapshot_startup_grace_sec = _cfg_int(
        "hybrid_snapshot_startup_grace_sec",
        CFG.hybrid_snapshot_startup_grace_sec,
    )
    CFG.hybrid_snapshot_health_log_interval_sec = _cfg_int(
        "hybrid_snapshot_health_log_interval_sec",
        CFG.hybrid_snapshot_health_log_interval_sec,
    )
    CFG.hybrid_snapshot_missing_log_interval_sec = _cfg_int(
        "hybrid_snapshot_missing_log_interval_sec",
        CFG.hybrid_snapshot_missing_log_interval_sec,
    )
    CFG.hybrid_symbol_snapshot_max_age_sec = _cfg_int(
        "hybrid_symbol_snapshot_max_age_sec",
        CFG.hybrid_symbol_snapshot_max_age_sec,
    )
    CFG.hybrid_symbol_static_snapshot_max_age_sec = _cfg_int(
        "hybrid_symbol_static_snapshot_max_age_sec",
        CFG.hybrid_symbol_static_snapshot_max_age_sec,
    )
    CFG.hybrid_account_snapshot_max_age_sec = _cfg_int(
        "hybrid_account_snapshot_max_age_sec",
        CFG.hybrid_account_snapshot_max_age_sec,
    )
    CFG.hybrid_account_static_snapshot_max_age_sec = _cfg_int(
        "hybrid_account_static_snapshot_max_age_sec",
        CFG.hybrid_account_static_snapshot_max_age_sec,
    )
    CFG.time_anchor_max_backward_sec = _cfg_int("time_anchor_max_backward_sec", CFG.time_anchor_max_backward_sec)
    CFG.eco_threshold_pct = _cfg_float("eco_threshold_pct", CFG.eco_threshold_pct)
    CFG.eco_threshold_price_pct = _cfg_float("eco_threshold_price_pct", CFG.eco_threshold_price_pct)
    CFG.eco_threshold_order_pct = _cfg_float("eco_threshold_order_pct", CFG.eco_threshold_order_pct)
    CFG.eco_threshold_sys_pct = _cfg_float("eco_threshold_sys_pct", CFG.eco_threshold_sys_pct)
    CFG.price_soft_fraction = _cfg_float("price_soft_fraction", CFG.price_soft_fraction)
    CFG.order_emergency_reserve_fraction = _cfg_float(
        "order_emergency_reserve_fraction", CFG.order_emergency_reserve_fraction
    )
    CFG.sys_emergency_reserve_fraction = _cfg_float(
        "sys_emergency_reserve_fraction", CFG.sys_emergency_reserve_fraction
    )
    CFG.price_emergency_reserve_fraction = _cfg_float(
        "price_emergency_reserve_fraction", CFG.price_emergency_reserve_fraction
    )
    CFG.group_borrow_fraction = _cfg_float("group_borrow_fraction", CFG.group_borrow_fraction)
    CFG.group_borrow_unlock_power = _cfg_float("group_borrow_unlock_power", CFG.group_borrow_unlock_power)
    CFG.group_priority_min_factor = _cfg_float("group_priority_min_factor", CFG.group_priority_min_factor)
    CFG.group_priority_max_factor = _cfg_float("group_priority_max_factor", CFG.group_priority_max_factor)
    CFG.group_priority_pressure_weight = _cfg_float(
        "group_priority_pressure_weight", CFG.group_priority_pressure_weight
    )
    CFG.policy_windows_v2_enabled = _cfg_bool("policy_windows_v2_enabled", CFG.policy_windows_v2_enabled)
    CFG.policy_risk_windows_enabled = _cfg_bool("policy_risk_windows_enabled", CFG.policy_risk_windows_enabled)
    CFG.policy_group_arbitration_enabled = _cfg_bool(
        "policy_group_arbitration_enabled", CFG.policy_group_arbitration_enabled
    )
    CFG.policy_overlap_arbitration_enabled = _cfg_bool(
        "policy_overlap_arbitration_enabled", CFG.policy_overlap_arbitration_enabled
    )
    if "policy_shadow_mode_enabled" in strategy_cfg:
        CFG.policy_shadow_mode_enabled = _cfg_bool("policy_shadow_mode_enabled", CFG.policy_shadow_mode_enabled)
    else:
        CFG.policy_shadow_mode_enabled = bool(not _cfg_bool("paper_trading", False))
    CFG.policy_runtime_emit_enabled = _cfg_bool("policy_runtime_emit_enabled", CFG.policy_runtime_emit_enabled)
    CFG.policy_runtime_emit_interval_sec = _cfg_int(
        "policy_runtime_emit_interval_sec", CFG.policy_runtime_emit_interval_sec
    )
    CFG.policy_runtime_file_name = str(strategy_cfg.get("policy_runtime_file_name", CFG.policy_runtime_file_name) or CFG.policy_runtime_file_name)
    CFG.policy_runtime_emit_common_file = _cfg_bool(
        "policy_runtime_emit_common_file", CFG.policy_runtime_emit_common_file
    )
    CFG.policy_runtime_common_subdir = str(
        strategy_cfg.get("policy_runtime_common_subdir", CFG.policy_runtime_common_subdir)
        or CFG.policy_runtime_common_subdir
    )
    CFG.budget_log_interval_sec = _cfg_int("budget_log_interval_sec", CFG.budget_log_interval_sec)
    CFG.oanda_price_breakdown_log_interval_sec = _cfg_int(
        "oanda_price_breakdown_log_interval_sec", CFG.oanda_price_breakdown_log_interval_sec
    )
    CFG.kernel_config_emit_enabled = _cfg_bool("kernel_config_emit_enabled", CFG.kernel_config_emit_enabled)
    CFG.kernel_config_emit_interval_sec = _cfg_int(
        "kernel_config_emit_interval_sec", CFG.kernel_config_emit_interval_sec
    )
    CFG.kernel_config_file_name = str(
        strategy_cfg.get("kernel_config_file_name", CFG.kernel_config_file_name) or CFG.kernel_config_file_name
    )
    CFG.kernel_config_emit_common_file = _cfg_bool(
        "kernel_config_emit_common_file", CFG.kernel_config_emit_common_file
    )
    CFG.kernel_config_common_subdir = str(
        strategy_cfg.get("kernel_config_common_subdir", CFG.kernel_config_common_subdir)
        or CFG.kernel_config_common_subdir
    )
    CFG.trade_trigger_mode = str(
        strategy_cfg.get("trade_trigger_mode", CFG.trade_trigger_mode) or CFG.trade_trigger_mode
    ).strip().upper()
    if CFG.trade_trigger_mode not in {"BRIDGE_ACTIVE", "MQL5_SHADOW_COMPARE", "MQL5_ACTIVE"}:
        CFG.trade_trigger_mode = "BRIDGE_ACTIVE"
    CFG.trade_trigger_mode_allow_mql5_active = _cfg_bool(
        "trade_trigger_mode_allow_mql5_active", CFG.trade_trigger_mode_allow_mql5_active
    )
    CFG.stage1_live_config_enabled = _cfg_bool(
        "stage1_live_config_enabled", CFG.stage1_live_config_enabled
    )
    CFG.stage1_live_reload_interval_sec = _cfg_int(
        "stage1_live_reload_interval_sec", CFG.stage1_live_reload_interval_sec
    )
    CFG.stage1_live_audit_enabled = _cfg_bool(
        "stage1_live_audit_enabled", CFG.stage1_live_audit_enabled
    )
    CFG.stage1_live_config_file = str(
        strategy_cfg.get("stage1_live_config_file", CFG.stage1_live_config_file)
        or CFG.stage1_live_config_file
    ).strip()
    CFG.stage1_live_status_file = str(
        strategy_cfg.get("stage1_live_status_file", CFG.stage1_live_status_file)
        or CFG.stage1_live_status_file
    ).strip()
    CFG.stage1_live_audit_file = str(
        strategy_cfg.get("stage1_live_audit_file", CFG.stage1_live_audit_file)
        or CFG.stage1_live_audit_file
    ).strip()
    CFG.friday_risk_enabled = _cfg_bool("friday_risk_enabled", CFG.friday_risk_enabled)
    CFG.friday_risk_ny_start_hm = _cfg_hm("friday_risk_ny_start_hm", CFG.friday_risk_ny_start_hm)
    CFG.friday_risk_ny_end_hm = _cfg_hm("friday_risk_ny_end_hm", CFG.friday_risk_ny_end_hm)
    CFG.friday_risk_groups = tuple(_cfg_str_list("friday_risk_groups", list(CFG.friday_risk_groups)))
    CFG.friday_risk_close_only_groups = tuple(
        _cfg_str_list("friday_risk_close_only_groups", list(CFG.friday_risk_close_only_groups))
    )
    CFG.friday_risk_close_only = _cfg_bool("friday_risk_close_only", CFG.friday_risk_close_only)
    CFG.friday_risk_borrow_block = _cfg_bool("friday_risk_borrow_block", CFG.friday_risk_borrow_block)
    CFG.friday_risk_priority_factor = _cfg_float("friday_risk_priority_factor", CFG.friday_risk_priority_factor)
    CFG.reopen_guard_enabled = _cfg_bool("reopen_guard_enabled", CFG.reopen_guard_enabled)
    CFG.reopen_guard_ny_start_hm = _cfg_hm("reopen_guard_ny_start_hm", CFG.reopen_guard_ny_start_hm)
    CFG.reopen_guard_groups = tuple(_cfg_str_list("reopen_guard_groups", list(CFG.reopen_guard_groups)))
    CFG.reopen_guard_close_only_groups = tuple(
        _cfg_str_list("reopen_guard_close_only_groups", list(CFG.reopen_guard_close_only_groups))
    )
    CFG.reopen_guard_minutes = _cfg_int("reopen_guard_minutes", CFG.reopen_guard_minutes)
    CFG.reopen_guard_close_only = _cfg_bool("reopen_guard_close_only", CFG.reopen_guard_close_only)
    CFG.reopen_guard_borrow_block = _cfg_bool("reopen_guard_borrow_block", CFG.reopen_guard_borrow_block)
    CFG.reopen_guard_priority_factor = _cfg_float("reopen_guard_priority_factor", CFG.reopen_guard_priority_factor)
    CFG.trade_window_strict_group_routing = _cfg_bool(
        "trade_window_strict_group_routing", CFG.trade_window_strict_group_routing
    )
    CFG.trade_closeout_buffer_min = _cfg_int("trade_closeout_buffer_min", CFG.trade_closeout_buffer_min)
    CFG.hard_no_mt5_outside_windows = _cfg_bool(
        "hard_no_mt5_outside_windows", CFG.hard_no_mt5_outside_windows
    )
    CFG.trade_off_sys_poll_sec = _cfg_int("trade_off_sys_poll_sec", CFG.trade_off_sys_poll_sec)
    # Trade-window extensions (v1)
    CFG.trade_window_prefetch_enabled = _cfg_bool(
        "trade_window_prefetch_enabled", CFG.trade_window_prefetch_enabled
    )
    CFG.trade_window_prefetch_lead_min = _cfg_int(
        "trade_window_prefetch_lead_min", CFG.trade_window_prefetch_lead_min
    )
    CFG.trade_window_prefetch_max_symbols = _cfg_int(
        "trade_window_prefetch_max_symbols", CFG.trade_window_prefetch_max_symbols
    )
    CFG.trade_window_prefetch_warm_store_indicators = _cfg_bool(
        "trade_window_prefetch_warm_store_indicators", CFG.trade_window_prefetch_warm_store_indicators
    )
    CFG.trade_window_carryover_enabled = _cfg_bool(
        "trade_window_carryover_enabled", CFG.trade_window_carryover_enabled
    )
    CFG.trade_window_carryover_minutes = _cfg_int(
        "trade_window_carryover_minutes", CFG.trade_window_carryover_minutes
    )
    CFG.trade_window_carryover_max_symbols = _cfg_int(
        "trade_window_carryover_max_symbols", CFG.trade_window_carryover_max_symbols
    )
    CFG.trade_window_carryover_trade_enabled = _cfg_bool(
        "trade_window_carryover_trade_enabled", CFG.trade_window_carryover_trade_enabled
    )
    try:
        raw_cg = _cfg_str_list("trade_window_carryover_groups", list(CFG.trade_window_carryover_groups))
        cg_out: List[str] = []
        for g in raw_cg:
            gg = _group_key(g)
            if gg in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"} and gg not in cg_out:
                cg_out.append(gg)
        CFG.trade_window_carryover_groups = tuple(cg_out)
    except Exception:
        CFG.trade_window_carryover_groups = tuple(getattr(CFG, "trade_window_carryover_groups", ()) or ())
    CFG.trade_window_fx_rotation_enabled = _cfg_bool(
        "trade_window_fx_rotation_enabled", CFG.trade_window_fx_rotation_enabled
    )
    CFG.trade_window_fx_rotation_bucket_size = _cfg_int(
        "trade_window_fx_rotation_bucket_size", CFG.trade_window_fx_rotation_bucket_size
    )
    CFG.trade_window_fx_rotation_period_sec = _cfg_int(
        "trade_window_fx_rotation_period_sec", CFG.trade_window_fx_rotation_period_sec
    )
    CFG.trade_window_fx_rotation_only_when_over_capacity = _cfg_bool(
        "trade_window_fx_rotation_only_when_over_capacity", CFG.trade_window_fx_rotation_only_when_over_capacity
    )
    CFG.trade_window_symbol_filter_enabled = _cfg_bool(
        "trade_window_symbol_filter_enabled", CFG.trade_window_symbol_filter_enabled
    )
    raw_tw_intents = strategy_cfg.get("trade_window_symbol_intents", None)
    if raw_tw_intents is not None:
        if not isinstance(raw_tw_intents, dict):
            raise SystemExit("CONFIG_STRATEGY_FAIL: trade_window_symbol_intents must be object")
        tw_intents_out: Dict[str, Tuple[str, ...]] = {}
        for k, v in raw_tw_intents.items():
            wid = str(k or "").strip()
            if not wid:
                continue
            if not isinstance(v, (list, tuple)):
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: trade_window_symbol_intents.{wid} must be list")
            lst: List[str] = []
            seen: Set[str] = set()
            for item in v:
                s = str(item or "").strip().upper()
                if s and s not in seen:
                    seen.add(s)
                    lst.append(s)
            tw_intents_out[wid] = tuple(lst)
        CFG.trade_window_symbol_intents = dict(tw_intents_out)
    elif not isinstance(getattr(CFG, "trade_window_symbol_intents", {}), dict):
        CFG.trade_window_symbol_intents = {}
    CFG.adx_threshold = _cfg_int("adx_threshold", CFG.adx_threshold)
    CFG.adx_range_max = _cfg_int("adx_range_max", CFG.adx_range_max)
    CFG.regime_switch_enabled = _cfg_bool("regime_switch_enabled", CFG.regime_switch_enabled)
    CFG.mean_reversion_enabled = _cfg_bool("mean_reversion_enabled", CFG.mean_reversion_enabled)
    CFG.structure_filter_enabled = _cfg_bool("structure_filter_enabled", CFG.structure_filter_enabled)
    CFG.sma_structure_fast = _cfg_int("sma_structure_fast", CFG.sma_structure_fast)
    CFG.sma_structure_slow = _cfg_int("sma_structure_slow", CFG.sma_structure_slow)
    CFG.trend_short_fallback_enabled = _cfg_bool(
        "trend_short_fallback_enabled", CFG.trend_short_fallback_enabled
    )
    CFG.trend_short_fallback_min_h4_rows = _cfg_int(
        "trend_short_fallback_min_h4_rows", CFG.trend_short_fallback_min_h4_rows
    )
    CFG.trend_short_fallback_min_d1_rows = _cfg_int(
        "trend_short_fallback_min_d1_rows", CFG.trend_short_fallback_min_d1_rows
    )
    CFG.atr_exit_enabled = _cfg_bool("atr_exit_enabled", CFG.atr_exit_enabled)
    CFG.atr_exit_use_override = _cfg_bool("atr_exit_use_override", CFG.atr_exit_use_override)
    CFG.atr_sl_mult_hot = _cfg_float("atr_sl_mult_hot", CFG.atr_sl_mult_hot)
    CFG.atr_sl_mult_warm = _cfg_float("atr_sl_mult_warm", CFG.atr_sl_mult_warm)
    CFG.atr_sl_mult_eco = _cfg_float("atr_sl_mult_eco", CFG.atr_sl_mult_eco)
    CFG.atr_tp_mult_hot = _cfg_float("atr_tp_mult_hot", CFG.atr_tp_mult_hot)
    CFG.atr_tp_mult_warm = _cfg_float("atr_tp_mult_warm", CFG.atr_tp_mult_warm)
    CFG.atr_tp_mult_eco = _cfg_float("atr_tp_mult_eco", CFG.atr_tp_mult_eco)
    CFG.atr_sl_min_points = _cfg_int("atr_sl_min_points", CFG.atr_sl_min_points)
    CFG.atr_tp_min_points = _cfg_int("atr_tp_min_points", CFG.atr_tp_min_points)
    CFG.trailing_stop_enabled = _cfg_bool("trailing_stop_enabled", CFG.trailing_stop_enabled)
    CFG.trailing_activation_r = _cfg_float("trailing_activation_r", CFG.trailing_activation_r)
    CFG.trailing_atr_mult = _cfg_float("trailing_atr_mult", CFG.trailing_atr_mult)
    CFG.trailing_update_retry_sec = _cfg_int("trailing_update_retry_sec", CFG.trailing_update_retry_sec)
    CFG.partial_tp_enabled = _cfg_bool("partial_tp_enabled", CFG.partial_tp_enabled)
    CFG.partial_tp_r = _cfg_float("partial_tp_r", CFG.partial_tp_r)
    CFG.partial_tp_fraction = _cfg_float("partial_tp_fraction", CFG.partial_tp_fraction)
    CFG.partial_tp_retry_sec = _cfg_int("partial_tp_retry_sec", CFG.partial_tp_retry_sec)
    CFG.learner_qa_gate_enabled = _cfg_bool("learner_qa_gate_enabled", CFG.learner_qa_gate_enabled)
    CFG.learner_qa_red_to_eco = _cfg_bool("learner_qa_red_to_eco", CFG.learner_qa_red_to_eco)
    CFG.unified_learning_runtime_enabled = _cfg_bool(
        "unified_learning_runtime_enabled", CFG.unified_learning_runtime_enabled
    )
    CFG.unified_learning_runtime_paper_only = _cfg_bool(
        "unified_learning_runtime_paper_only", CFG.unified_learning_runtime_paper_only
    )
    CFG.unified_learning_runtime_min_samples = _cfg_int(
        "unified_learning_runtime_min_samples", CFG.unified_learning_runtime_min_samples
    )
    CFG.unified_learning_runtime_max_abs_score_delta = _cfg_int(
        "unified_learning_runtime_max_abs_score_delta", CFG.unified_learning_runtime_max_abs_score_delta
    )
    CFG.unified_learning_rank_enabled = _cfg_bool(
        "unified_learning_rank_enabled", CFG.unified_learning_rank_enabled
    )
    CFG.unified_learning_rank_paper_only = _cfg_bool(
        "unified_learning_rank_paper_only", CFG.unified_learning_rank_paper_only
    )
    CFG.unified_learning_rank_min_samples = _cfg_int(
        "unified_learning_rank_min_samples", CFG.unified_learning_rank_min_samples
    )
    CFG.unified_learning_rank_max_bonus_pct = _cfg_float(
        "unified_learning_rank_max_bonus_pct", CFG.unified_learning_rank_max_bonus_pct
    )
    CFG.canary_rollout_enabled = _cfg_bool("canary_rollout_enabled", CFG.canary_rollout_enabled)
    CFG.canary_max_symbols_per_iter = _cfg_int("canary_max_symbols_per_iter", CFG.canary_max_symbols_per_iter)
    CFG.live_canary_enabled = _cfg_bool("live_canary_enabled", CFG.live_canary_enabled)
    CFG.cost_gate_policy_mode = str(
        strategy_cfg.get("cost_gate_policy_mode", CFG.cost_gate_policy_mode) or CFG.cost_gate_policy_mode
    ).strip().upper()
    if CFG.cost_gate_policy_mode not in {"CANARY_ACTIVE", "DIAGNOSTIC_ONLY", "DISABLED"}:
        CFG.cost_gate_policy_mode = "DIAGNOSTIC_ONLY"
    CFG.session_liquidity_gate_enabled = _cfg_bool(
        "session_liquidity_gate_enabled", CFG.session_liquidity_gate_enabled
    )
    CFG.session_liquidity_gate_mode = str(
        strategy_cfg.get("session_liquidity_gate_mode", CFG.session_liquidity_gate_mode)
        or CFG.session_liquidity_gate_mode
    ).strip().upper()
    if CFG.session_liquidity_gate_mode not in {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}:
        CFG.session_liquidity_gate_mode = "SHADOW_ONLY"
    CFG.session_liquidity_block_on_missing_snapshot = _cfg_bool(
        "session_liquidity_block_on_missing_snapshot",
        CFG.session_liquidity_block_on_missing_snapshot,
    )
    CFG.session_liquidity_emit_caution_event = _cfg_bool(
        "session_liquidity_emit_caution_event",
        CFG.session_liquidity_emit_caution_event,
    )
    CFG.cost_microstructure_gate_enabled = _cfg_bool(
        "cost_microstructure_gate_enabled",
        CFG.cost_microstructure_gate_enabled,
    )
    CFG.cost_microstructure_gate_mode = str(
        strategy_cfg.get("cost_microstructure_gate_mode", CFG.cost_microstructure_gate_mode)
        or CFG.cost_microstructure_gate_mode
    ).strip().upper()
    if CFG.cost_microstructure_gate_mode not in {"SHADOW_ONLY", "GATE_ENFORCE", "DISABLED"}:
        CFG.cost_microstructure_gate_mode = "SHADOW_ONLY"
    CFG.cost_microstructure_block_on_missing_snapshot = _cfg_bool(
        "cost_microstructure_block_on_missing_snapshot",
        CFG.cost_microstructure_block_on_missing_snapshot,
    )
    CFG.cost_microstructure_block_on_unknown_quality = _cfg_bool(
        "cost_microstructure_block_on_unknown_quality",
        CFG.cost_microstructure_block_on_unknown_quality,
    )
    CFG.cost_microstructure_emit_caution_event = _cfg_bool(
        "cost_microstructure_emit_caution_event",
        CFG.cost_microstructure_emit_caution_event,
    )
    CFG.candle_adapter_enabled = _cfg_bool("candle_adapter_enabled", CFG.candle_adapter_enabled)
    CFG.candle_adapter_mode = str(
        strategy_cfg.get("candle_adapter_mode", CFG.candle_adapter_mode) or CFG.candle_adapter_mode
    ).strip().upper()
    if CFG.candle_adapter_mode not in {"SHADOW_ONLY", "ADVISORY_SCORE", "DISABLED"}:
        CFG.candle_adapter_mode = "SHADOW_ONLY"
    CFG.candle_adapter_emit_event = _cfg_bool(
        "candle_adapter_emit_event",
        CFG.candle_adapter_emit_event,
    )
    CFG.candle_adapter_score_weight = _cfg_float(
        "candle_adapter_score_weight", CFG.candle_adapter_score_weight
    )
    CFG.candle_adapter_min_body_to_range = _cfg_float(
        "candle_adapter_min_body_to_range", CFG.candle_adapter_min_body_to_range
    )
    CFG.candle_adapter_pin_wick_ratio_min = _cfg_float(
        "candle_adapter_pin_wick_ratio_min", CFG.candle_adapter_pin_wick_ratio_min
    )
    CFG.renko_adapter_enabled = _cfg_bool("renko_adapter_enabled", CFG.renko_adapter_enabled)
    CFG.renko_adapter_mode = str(
        strategy_cfg.get("renko_adapter_mode", CFG.renko_adapter_mode) or CFG.renko_adapter_mode
    ).strip().upper()
    if CFG.renko_adapter_mode not in {"SHADOW_ONLY", "ADVISORY_SCORE", "DISABLED"}:
        CFG.renko_adapter_mode = "SHADOW_ONLY"
    CFG.renko_adapter_emit_event = _cfg_bool(
        "renko_adapter_emit_event", CFG.renko_adapter_emit_event
    )
    CFG.renko_adapter_score_weight = _cfg_float(
        "renko_adapter_score_weight", CFG.renko_adapter_score_weight
    )
    CFG.renko_adapter_price_source = str(
        strategy_cfg.get("renko_adapter_price_source", CFG.renko_adapter_price_source)
        or CFG.renko_adapter_price_source
    ).strip().upper()
    if CFG.renko_adapter_price_source not in {"MID", "BID", "ASK"}:
        CFG.renko_adapter_price_source = "MID"
    CFG.renko_adapter_tick_limit = _cfg_int(
        "renko_adapter_tick_limit", CFG.renko_adapter_tick_limit
    )
    CFG.renko_adapter_cache_ttl_sec = _cfg_float(
        "renko_adapter_cache_ttl_sec", CFG.renko_adapter_cache_ttl_sec
    )
    CFG.renko_adapter_min_bricks_ready = _cfg_int(
        "renko_adapter_min_bricks_ready", CFG.renko_adapter_min_bricks_ready
    )
    CFG.renko_adapter_brick_size_points_default = _cfg_float(
        "renko_adapter_brick_size_points_default", CFG.renko_adapter_brick_size_points_default
    )
    def _cfg_group_float_map(name: str, fallback: Dict[str, float]) -> Dict[str, float]:
        raw = strategy_cfg.get(name, None)
        if raw is None:
            return dict(fallback)
        if not isinstance(raw, dict):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {name} must be object")
        out: Dict[str, float] = {}
        for k, v in raw.items():
            g = _group_key(str(k or ""))
            if g not in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                continue
            try:
                out[g] = float(v)
            except Exception:
                continue
        return dict(out) if out else dict(fallback)
    CFG.renko_adapter_brick_size_points_by_group = _cfg_group_float_map(
        "renko_adapter_brick_size_points_by_group",
        dict(getattr(CFG, "renko_adapter_brick_size_points_by_group", {}) or {}),
    )
    CFG.renko_tick_store_enabled = _cfg_bool(
        "renko_tick_store_enabled", CFG.renko_tick_store_enabled
    )
    CFG.renko_tick_store_min_interval_ms = _cfg_int(
        "renko_tick_store_min_interval_ms", CFG.renko_tick_store_min_interval_ms
    )
    CFG.renko_tick_store_min_price_delta_points = _cfg_float(
        "renko_tick_store_min_price_delta_points",
        CFG.renko_tick_store_min_price_delta_points,
    )
    CFG.renko_tick_store_max_rows_per_symbol = _cfg_int(
        "renko_tick_store_max_rows_per_symbol", CFG.renko_tick_store_max_rows_per_symbol
    )
    CFG.renko_tick_store_prune_every = _cfg_int(
        "renko_tick_store_prune_every", CFG.renko_tick_store_prune_every
    )
    CFG.cost_gate_min_target_to_cost_ratio = _cfg_float(
        "cost_gate_min_target_to_cost_ratio", CFG.cost_gate_min_target_to_cost_ratio
    )
    CFG.cost_gate_block_on_unknown_quality = _cfg_bool(
        "cost_gate_block_on_unknown_quality", CFG.cost_gate_block_on_unknown_quality
    )
    CFG.cost_guard_auto_relax_enabled = _cfg_bool(
        "cost_guard_auto_relax_enabled", CFG.cost_guard_auto_relax_enabled
    )
    CFG.cost_guard_auto_relax_window_minutes = _cfg_int(
        "cost_guard_auto_relax_window_minutes", CFG.cost_guard_auto_relax_window_minutes
    )
    CFG.cost_guard_auto_relax_min_total_decisions = _cfg_int(
        "cost_guard_auto_relax_min_total_decisions", CFG.cost_guard_auto_relax_min_total_decisions
    )
    CFG.cost_guard_auto_relax_min_wave1_decisions = _cfg_int(
        "cost_guard_auto_relax_min_wave1_decisions", CFG.cost_guard_auto_relax_min_wave1_decisions
    )
    CFG.cost_guard_auto_relax_min_unknown_blocks = _cfg_int(
        "cost_guard_auto_relax_min_unknown_blocks", CFG.cost_guard_auto_relax_min_unknown_blocks
    )
    CFG.cost_guard_auto_relax_max_critical_incidents = _cfg_int(
        "cost_guard_auto_relax_max_critical_incidents", CFG.cost_guard_auto_relax_max_critical_incidents
    )
    CFG.cost_guard_auto_relax_max_error_incidents = _cfg_int(
        "cost_guard_auto_relax_max_error_incidents", CFG.cost_guard_auto_relax_max_error_incidents
    )
    CFG.cost_guard_auto_relax_relaxed_min_ratio = _cfg_float(
        "cost_guard_auto_relax_relaxed_min_ratio", CFG.cost_guard_auto_relax_relaxed_min_ratio
    )
    CFG.cost_guard_auto_relax_block_on_unknown_quality = _cfg_bool(
        "cost_guard_auto_relax_block_on_unknown_quality", CFG.cost_guard_auto_relax_block_on_unknown_quality
    )
    CFG.cost_guard_auto_relax_hysteresis_enabled = _cfg_bool(
        "cost_guard_auto_relax_hysteresis_enabled", CFG.cost_guard_auto_relax_hysteresis_enabled
    )
    CFG.cost_guard_auto_relax_hysteresis_total_ratio = _cfg_float(
        "cost_guard_auto_relax_hysteresis_total_ratio", CFG.cost_guard_auto_relax_hysteresis_total_ratio
    )
    CFG.cost_guard_auto_relax_hysteresis_wave1_ratio = _cfg_float(
        "cost_guard_auto_relax_hysteresis_wave1_ratio", CFG.cost_guard_auto_relax_hysteresis_wave1_ratio
    )
    CFG.cost_guard_auto_relax_hysteresis_unknown_ratio = _cfg_float(
        "cost_guard_auto_relax_hysteresis_unknown_ratio", CFG.cost_guard_auto_relax_hysteresis_unknown_ratio
    )
    CFG.cost_guard_auto_relax_flap_window_minutes = _cfg_int(
        "cost_guard_auto_relax_flap_window_minutes", CFG.cost_guard_auto_relax_flap_window_minutes
    )
    CFG.cost_guard_auto_relax_flap_alert_threshold = _cfg_int(
        "cost_guard_auto_relax_flap_alert_threshold", CFG.cost_guard_auto_relax_flap_alert_threshold
    )
    CFG.cost_guard_auto_relax_status_file_name = str(
        strategy_cfg.get("cost_guard_auto_relax_status_file_name", CFG.cost_guard_auto_relax_status_file_name)
        or CFG.cost_guard_auto_relax_status_file_name
    ).strip()
    CFG.max_daily_loss_account = _cfg_float("max_daily_loss_account", CFG.max_daily_loss_account)
    CFG.max_session_loss_account = _cfg_float("max_session_loss_account", CFG.max_session_loss_account)
    CFG.max_daily_loss_per_module = _cfg_float("max_daily_loss_per_module", CFG.max_daily_loss_per_module)
    CFG.max_consecutive_losses_per_module = _cfg_int(
        "max_consecutive_losses_per_module", CFG.max_consecutive_losses_per_module
    )
    CFG.max_trades_per_window_per_module = _cfg_int(
        "max_trades_per_window_per_module", CFG.max_trades_per_window_per_module
    )
    CFG.max_execution_anomalies_per_window = _cfg_int(
        "max_execution_anomalies_per_window", CFG.max_execution_anomalies_per_window
    )
    CFG.max_ipc_failures_per_window = _cfg_int(
        "max_ipc_failures_per_window", CFG.max_ipc_failures_per_window
    )
    CFG.max_reject_ratio_threshold = _cfg_float(
        "max_reject_ratio_threshold", CFG.max_reject_ratio_threshold
    )
    CFG.max_reject_ratio_min_samples = _cfg_int(
        "max_reject_ratio_min_samples", CFG.max_reject_ratio_min_samples
    )
    CFG.jpy_basket_max_concurrent_positions = _cfg_int(
        "jpy_basket_max_concurrent_positions", CFG.jpy_basket_max_concurrent_positions
    )
    CFG.jpy_basket_max_risk_budget = _cfg_float(
        "jpy_basket_max_risk_budget", CFG.jpy_basket_max_risk_budget
    )
    CFG.jpy_basket_selection_mode = str(
        strategy_cfg.get("jpy_basket_selection_mode", CFG.jpy_basket_selection_mode) or CFG.jpy_basket_selection_mode
    ).strip().upper()
    CFG.jpy_basket_ranking_basis_for_top_k = str(
        strategy_cfg.get("jpy_basket_ranking_basis_for_top_k", CFG.jpy_basket_ranking_basis_for_top_k)
        or CFG.jpy_basket_ranking_basis_for_top_k
    ).strip()
    CFG.hard_live_contract_file_name = str(
        strategy_cfg.get("hard_live_contract_file_name", CFG.hard_live_contract_file_name)
        or CFG.hard_live_contract_file_name
    ).strip()
    CFG.no_live_drift_file_name = str(
        strategy_cfg.get("no_live_drift_file_name", CFG.no_live_drift_file_name)
        or CFG.no_live_drift_file_name
    ).strip()
    def _cfg_group_bool_map(name: str, fallback: Dict[str, bool]) -> Dict[str, bool]:
        raw = strategy_cfg.get(name, None)
        if raw is None:
            return dict(fallback)
        if not isinstance(raw, dict):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {name} must be object")
        out: Dict[str, bool] = {}
        for k, v in raw.items():
            g = _group_key(str(k or ""))
            if g not in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                continue
            out[g] = bool(v)
        return dict(out) if out else dict(fallback)
    CFG.module_live_enabled_map = _cfg_group_bool_map(
        "module_live_enabled_map", dict(getattr(CFG, "module_live_enabled_map", {}) or {})
    )
    CFG.live_canary_allowed_groups = tuple(
        _cfg_str_list("live_canary_allowed_groups", list(CFG.live_canary_allowed_groups))
    )
    CFG.live_canary_allowed_symbol_intents = tuple(
        _cfg_str_list("live_canary_allowed_symbol_intents", list(CFG.live_canary_allowed_symbol_intents))
    )
    CFG.hard_live_disabled_groups = tuple(
        _cfg_str_list("hard_live_disabled_groups", list(CFG.hard_live_disabled_groups))
    )
    CFG.hard_live_disabled_symbol_intents = tuple(
        _cfg_str_list("hard_live_disabled_symbol_intents", list(CFG.hard_live_disabled_symbol_intents))
    )
    CFG.jpy_basket_symbol_intents = tuple(
        _cfg_str_list("jpy_basket_symbol_intents", list(CFG.jpy_basket_symbol_intents))
    )
    CFG.asia_wave1_symbol_intents = tuple(
        _cfg_str_list("asia_wave1_symbol_intents", list(CFG.asia_wave1_symbol_intents))
    )
    CFG.position_time_stop_enabled = _cfg_bool("position_time_stop_enabled", CFG.position_time_stop_enabled)
    CFG.position_time_stop_only_magic = _cfg_bool("position_time_stop_only_magic", CFG.position_time_stop_only_magic)
    CFG.position_time_stop_hot_min = _cfg_int("position_time_stop_hot_min", CFG.position_time_stop_hot_min)
    CFG.position_time_stop_warm_min = _cfg_int("position_time_stop_warm_min", CFG.position_time_stop_warm_min)
    CFG.position_time_stop_eco_min = _cfg_int("position_time_stop_eco_min", CFG.position_time_stop_eco_min)
    CFG.position_time_stop_retry_sec = _cfg_int("position_time_stop_retry_sec", CFG.position_time_stop_retry_sec)
    CFG.position_time_stop_deviation_points = _cfg_int(
        "position_time_stop_deviation_points", CFG.position_time_stop_deviation_points
    )
    CFG.sltp_modify_min_interval_sec = _cfg_int("sltp_modify_min_interval_sec", CFG.sltp_modify_min_interval_sec)
    CFG.sltp_modify_max_per_sec = _cfg_int("sltp_modify_max_per_sec", CFG.sltp_modify_max_per_sec)
    CFG.signal_dedupe_enabled = _cfg_bool("signal_dedupe_enabled", CFG.signal_dedupe_enabled)
    CFG.signal_dedupe_ttl_sec = _cfg_int("signal_dedupe_ttl_sec", CFG.signal_dedupe_ttl_sec)
    CFG.use_order_check = _cfg_bool("use_order_check", CFG.use_order_check)
    CFG.execution_queue_enabled = _cfg_bool("execution_queue_enabled", CFG.execution_queue_enabled)
    CFG.execution_queue_maxsize = _cfg_int("execution_queue_maxsize", CFG.execution_queue_maxsize)
    CFG.execution_queue_submit_timeout_sec = _cfg_int(
        "execution_queue_submit_timeout_sec", CFG.execution_queue_submit_timeout_sec
    )
    CFG.execution_queue_backpressure_enabled = _cfg_bool(
        "execution_queue_backpressure_enabled",
        CFG.execution_queue_backpressure_enabled,
    )
    CFG.execution_queue_backpressure_high_watermark = _cfg_float(
        "execution_queue_backpressure_high_watermark",
        CFG.execution_queue_backpressure_high_watermark,
    )
    CFG.execution_queue_backpressure_warn_interval_sec = _cfg_int(
        "execution_queue_backpressure_warn_interval_sec",
        CFG.execution_queue_backpressure_warn_interval_sec,
    )
    CFG.execution_queue_wait_warn_ms = _cfg_int(
        "execution_queue_wait_warn_ms", CFG.execution_queue_wait_warn_ms
    )
    CFG.pending_reconcile_poll_sec = _cfg_int("pending_reconcile_poll_sec", CFG.pending_reconcile_poll_sec)
    CFG.pending_reconcile_force_poll_sec = _cfg_int(
        "pending_reconcile_force_poll_sec", CFG.pending_reconcile_force_poll_sec
    )
    CFG.fx_only_mode = _cfg_bool("fx_only_mode", CFG.fx_only_mode)
    CFG.oanda_warn_symbols_cap = _cfg_int("oanda_warn_symbols_cap", CFG.oanda_warn_symbols_cap)
    CFG.symbols_to_trade = _cfg_str_list("symbols_to_trade", list(CFG.symbols_to_trade))

    # Optional advanced config blocks (dict/list) for LIVE process control.
    # NOTE: These must be set before RequestGovernor is created.
    raw_groups = strategy_cfg.get("symbol_policy_allowed_groups", None)
    if raw_groups is not None:
        if not isinstance(raw_groups, list):
            raise SystemExit("CONFIG_STRATEGY_FAIL: symbol_policy_allowed_groups must be list")
        groups_out: List[str] = []
        for item in raw_groups:
            g = _group_key(str(item or ""))
            if g in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                groups_out.append(g)
        if groups_out:
            CFG.symbol_policy_allowed_groups = tuple(groups_out)

    raw_shares = strategy_cfg.get("group_price_shares", None)
    if raw_shares is not None:
        if not isinstance(raw_shares, dict):
            raise SystemExit("CONFIG_STRATEGY_FAIL: group_price_shares must be object")
        shares_out: Dict[str, float] = {}
        for k, v in raw_shares.items():
            g = _group_key(str(k or ""))
            if g not in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                continue
            try:
                shares_out[g] = float(v)
            except Exception:
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: group_price_shares.{g} must be number")
        if shares_out:
            CFG.group_price_shares = dict(shares_out)

    def _cfg_group_map(name: str, fallback: Dict[str, float]) -> Dict[str, float]:
        raw = strategy_cfg.get(name, None)
        if raw is None:
            return dict(fallback)
        if not isinstance(raw, dict):
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: {name} must be object")
        out: Dict[str, float] = {}
        for k, v in raw.items():
            g = _group_key(str(k or ""))
            if g not in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                continue
            try:
                out[g] = float(v)
            except Exception:
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: {name}.{g} must be number")
        return dict(out) if out else dict(fallback)

    CFG.group_borrow_fraction_by_group = _cfg_group_map(
        "group_borrow_fraction_by_group", dict(getattr(CFG, "group_borrow_fraction_by_group", {}) or {})
    )
    CFG.group_priority_boost = _cfg_group_map(
        "group_priority_boost", dict(getattr(CFG, "group_priority_boost", {}) or {})
    )
    CFG.group_overlap_priority_factor = _cfg_group_map(
        "group_overlap_priority_factor", dict(getattr(CFG, "group_overlap_priority_factor", {}) or {})
    )
    CFG.session_liquidity_spread_caution_by_group = _cfg_group_map(
        "session_liquidity_spread_caution_by_group",
        dict(getattr(CFG, "session_liquidity_spread_caution_by_group", {}) or {}),
    )
    CFG.session_liquidity_spread_block_by_group = _cfg_group_map(
        "session_liquidity_spread_block_by_group",
        dict(getattr(CFG, "session_liquidity_spread_block_by_group", {}) or {}),
    )
    CFG.session_liquidity_max_tick_age_sec_by_group = _cfg_group_map(
        "session_liquidity_max_tick_age_sec_by_group",
        dict(getattr(CFG, "session_liquidity_max_tick_age_sec_by_group", {}) or {}),
    )
    CFG.cost_microstructure_spread_caution_by_group = _cfg_group_map(
        "cost_microstructure_spread_caution_by_group",
        dict(getattr(CFG, "cost_microstructure_spread_caution_by_group", {}) or {}),
    )
    CFG.cost_microstructure_spread_block_by_group = _cfg_group_map(
        "cost_microstructure_spread_block_by_group",
        dict(getattr(CFG, "cost_microstructure_spread_block_by_group", {}) or {}),
    )
    CFG.cost_microstructure_max_tick_age_sec_by_group = _cfg_group_map(
        "cost_microstructure_max_tick_age_sec_by_group",
        dict(getattr(CFG, "cost_microstructure_max_tick_age_sec_by_group", {}) or {}),
    )
    CFG.cost_microstructure_gap_block_sec_by_group = _cfg_group_map(
        "cost_microstructure_gap_block_sec_by_group",
        dict(getattr(CFG, "cost_microstructure_gap_block_sec_by_group", {}) or {}),
    )
    CFG.cost_microstructure_jump_block_points_by_group = _cfg_group_map(
        "cost_microstructure_jump_block_points_by_group",
        dict(getattr(CFG, "cost_microstructure_jump_block_points_by_group", {}) or {}),
    )

    raw_tw = strategy_cfg.get("trade_windows", None)
    if raw_tw is not None:
        if not isinstance(raw_tw, dict):
            raise SystemExit("CONFIG_STRATEGY_FAIL: trade_windows must be object")
        tw_out: Dict[str, Dict[str, object]] = {}

        def _hm(x: object, *, label: str) -> Tuple[int, int]:
            if isinstance(x, (list, tuple)) and len(x) == 2:
                try:
                    hh = int(x[0])
                    mm = int(x[1])
                except Exception:
                    raise SystemExit(f"CONFIG_STRATEGY_FAIL: trade_windows.*.{label} must be [HH,MM]")
                if hh < 0 or hh > 23 or mm < 0 or mm > 59:
                    raise SystemExit(f"CONFIG_STRATEGY_FAIL: trade_windows.*.{label} invalid HH/MM")
                return int(hh), int(mm)
            if isinstance(x, str) and ":" in x:
                hh, mm = _parse_hhmm(x, default_hour=0, default_minute=0)
                return int(hh), int(mm)
            raise SystemExit(f"CONFIG_STRATEGY_FAIL: trade_windows.*.{label} must be [HH,MM] or 'HH:MM'")

        for wid in raw_tw.keys():
            w = raw_tw.get(wid)
            if w is None:
                continue
            if not isinstance(w, dict):
                raise SystemExit(f"CONFIG_STRATEGY_FAIL: trade_windows.{wid} must be object")
            grp = _group_key(str(w.get("group") or ""))
            # Allow null/empty group for "all groups" or "no specific group" windows
            # but enforce valid group if specified.
            if grp and grp not in {"FX", "METAL", "INDEX", "CRYPTO", "EQUITY"}:
                raise SystemExit(
                    f"CONFIG_STRATEGY_FAIL: trade_windows.{wid}.group must be FX, METAL, INDEX, CRYPTO or EQUITY"
                )
            anchor_tz = str(w.get("anchor_tz") or "Europe/Warsaw")
            start_hm = _hm(w.get("start_hm"), label="start_hm")
            end_hm = _hm(w.get("end_hm"), label="end_hm")
            tw_out[wid] = {"group": grp, "anchor_tz": anchor_tz, "start_hm": start_hm, "end_hm": end_hm}
        if tw_out:
            CFG.trade_windows = dict(tw_out)

    CFG.black_swan_threshold = float(config.risk.get("black_swan_threshold", CFG.black_swan_threshold))
    CFG.black_swan_precaution_fraction = float(
        config.risk.get("black_swan_precaution_fraction", config.risk.get("precaution_fraction", CFG.black_swan_precaution_fraction))
    )
    CFG.black_swan_min_vol_samples = int(config.risk.get("black_swan_min_vol_samples", CFG.black_swan_min_vol_samples))
    CFG.kill_switch_on_black_swan_stress = bool(
        config.risk.get("kill_switch_on_black_swan_stress", CFG.kill_switch_on_black_swan_stress)
    )
    CFG.kill_switch_black_swan_multiplier = float(
        config.risk.get("kill_switch_black_swan_multiplier", CFG.kill_switch_black_swan_multiplier)
    )
    CFG.black_swan_v2_enabled = bool(config.risk.get("black_swan_v2_enabled", CFG.black_swan_v2_enabled))
    CFG.black_swan_v2_hard_max_spread_points = float(
        config.risk.get("black_swan_v2_hard_max_spread_points", CFG.black_swan_v2_hard_max_spread_points)
    )
    CFG.black_swan_v2_hard_max_slippage_points = float(
        config.risk.get("black_swan_v2_hard_max_slippage_points", CFG.black_swan_v2_hard_max_slippage_points)
    )
    CFG.black_swan_v2_hard_max_bridge_wait_ms = float(
        config.risk.get("black_swan_v2_hard_max_bridge_wait_ms", CFG.black_swan_v2_hard_max_bridge_wait_ms)
    )
    CFG.black_swan_v2_hard_max_heartbeat_age_ms = float(
        config.risk.get("black_swan_v2_hard_max_heartbeat_age_ms", CFG.black_swan_v2_hard_max_heartbeat_age_ms)
    )
    CFG.black_swan_v2_hard_max_tick_gap_ms = float(
        config.risk.get("black_swan_v2_hard_max_tick_gap_ms", CFG.black_swan_v2_hard_max_tick_gap_ms)
    )
    CFG.black_swan_v2_crash_bridge_streak_required = int(
        config.risk.get(
            "black_swan_v2_crash_bridge_streak_required",
            CFG.black_swan_v2_crash_bridge_streak_required,
        )
    )
    CFG.black_swan_v2_liquidity_floor_score = float(
        config.risk.get("black_swan_v2_liquidity_floor_score", CFG.black_swan_v2_liquidity_floor_score)
    )
    CFG.black_swan_v2_liquidity_floor_streak_required = int(
        config.risk.get(
            "black_swan_v2_liquidity_floor_streak_required",
            CFG.black_swan_v2_liquidity_floor_streak_required,
        )
    )
    CFG.black_swan_v2_min_tick_rate_fraction = float(
        config.risk.get("black_swan_v2_min_tick_rate_fraction", CFG.black_swan_v2_min_tick_rate_fraction)
    )
    CFG.black_swan_v2_required_stable_ticks_for_recovery = int(
        config.risk.get(
            "black_swan_v2_required_stable_ticks_for_recovery",
            CFG.black_swan_v2_required_stable_ticks_for_recovery,
        )
    )
    CFG.black_swan_v2_halt_cooldown_sec = int(
        config.risk.get("black_swan_v2_halt_cooldown_sec", CFG.black_swan_v2_halt_cooldown_sec)
    )
    CFG.black_swan_v2_close_only_cooldown_sec = int(
        config.risk.get("black_swan_v2_close_only_cooldown_sec", CFG.black_swan_v2_close_only_cooldown_sec)
    )
    CFG.black_swan_v2_defensive_cooldown_sec = int(
        config.risk.get("black_swan_v2_defensive_cooldown_sec", CFG.black_swan_v2_defensive_cooldown_sec)
    )
    CFG.black_swan_v2_caution_cooldown_sec = int(
        config.risk.get("black_swan_v2_caution_cooldown_sec", CFG.black_swan_v2_caution_cooldown_sec)
    )
    CFG.oanda_price_warning_per_day = int(config.limits.get("house_price_warn_per_day", CFG.oanda_price_warning_per_day))
    CFG.oanda_price_cutoff_per_day = int(config.limits.get("house_price_hard_stop_per_day", CFG.oanda_price_cutoff_per_day))
    CFG.oanda_market_orders_per_sec = int(config.limits.get("house_orders_per_sec", CFG.oanda_market_orders_per_sec))
    CFG.oanda_positions_pending_limit = int(
        config.limits.get("house_positions_pending_limit", CFG.oanda_positions_pending_limit)
    )
    db = Persistence(_paths["db"] / DECISION_EVENTS_DB_NAME)
    gov = RequestGovernor(db)
    risk_manager = RiskManager(config, db)
    
    limits = OandaLimitsGuard(
        db,
        _paths["evidence"],
        warn_day=int(config.limits["house_price_warn_per_day"]),
        hard_stop_day=int(config.limits["house_price_hard_stop_per_day"]),
        orders_per_sec=int(config.limits["house_orders_per_sec"]),
        positions_pending_limit=int(config.limits["house_positions_pending_limit"]),
    )
    
    black_swan_guard = BlackSwanGuard(
        BlackSwanPolicy(
            black_swan_threshold=float(CFG.black_swan_threshold),
            precaution_fraction=float(CFG.black_swan_precaution_fraction),
        )
    )
    heartbeat_interval_ms = float(max(1, getattr(CFG, "zmq_heartbeat_interval_sec", 15))) * 1000.0
    # Guard against false HALT: heartbeat age cap must be larger than heartbeat cadence.
    heartbeat_age_floor_ms = max(5000.0, heartbeat_interval_ms * 3.0)
    black_swan_guard_v2 = CapitalProtectionBlackSwanGuardV2(
        BlackSwanGuardConfigV2(
            hard_max_spread_points=float(max(1.0, CFG.black_swan_v2_hard_max_spread_points)),
            hard_max_slippage_points=float(max(1.0, CFG.black_swan_v2_hard_max_slippage_points)),
            hard_max_bridge_wait_ms=float(max(50.0, CFG.black_swan_v2_hard_max_bridge_wait_ms)),
            hard_max_heartbeat_age_ms=float(
                max(heartbeat_age_floor_ms, CFG.black_swan_v2_hard_max_heartbeat_age_ms)
            ),
            hard_max_tick_gap_ms=float(max(200.0, CFG.black_swan_v2_hard_max_tick_gap_ms)),
            crash_bridge_streak_required=int(max(1, CFG.black_swan_v2_crash_bridge_streak_required)),
            liquidity_floor_score=float(min(0.50, max(0.01, CFG.black_swan_v2_liquidity_floor_score))),
            liquidity_floor_streak_required=int(max(1, CFG.black_swan_v2_liquidity_floor_streak_required)),
            min_tick_rate_fraction=float(min(1.0, max(0.05, CFG.black_swan_v2_min_tick_rate_fraction))),
            required_stable_ticks_for_recovery=int(max(1, CFG.black_swan_v2_required_stable_ticks_for_recovery)),
            halt_cooldown_sec=int(max(1, CFG.black_swan_v2_halt_cooldown_sec)),
            close_only_cooldown_sec=int(max(1, CFG.black_swan_v2_close_only_cooldown_sec)),
            defensive_cooldown_sec=int(max(1, CFG.black_swan_v2_defensive_cooldown_sec)),
            caution_cooldown_sec=int(max(1, CFG.black_swan_v2_caution_cooldown_sec)),
        )
    )
    
    self_heal_guard = SelfHealGuard(
        SelfHealPolicy(
            enabled=bool(CFG.self_heal_enabled),
            lookback_sec=int(CFG.self_heal_lookback_sec),
            min_deals_in_window=int(CFG.self_heal_min_deals_in_window),
            loss_streak_trigger=int(CFG.self_heal_loss_streak_trigger),
            max_net_loss_abs=float(config.risk["self_heal_max_net_loss_abs"]),
            backoff_seconds=int(CFG.self_heal_backoff_s),
            symbol_cooldown_seconds=int(CFG.self_heal_symbol_cooldown_s),
        )
    )

    canary_guard = CanaryRolloutGuard(
        CanaryPolicy(
            enabled=bool(CFG.canary_rollout_enabled),
            lookback_sec=int(CFG.canary_lookback_sec),
            promote_min_deals=int(CFG.canary_promote_min_deals),
            promote_min_net_pnl=float(CFG.canary_promote_min_net_pnl),
            pause_loss_streak=int(CFG.canary_pause_loss_streak),
            pause_net_loss_abs=float(CFG.canary_pause_net_loss_abs),
            max_error_incidents=int(CFG.canary_max_error_incidents),
            canary_max_symbols=int(CFG.canary_max_symbols_per_iter),
            backoff_seconds=int(CFG.canary_backoff_s),
        )
    )

    drift_guard = DriftGuard(
        DriftPolicy(
            enabled=bool(CFG.drift_guard_enabled),
            min_samples=int(CFG.drift_min_samples),
            baseline_window=int(CFG.drift_baseline_window),
            recent_window=int(CFG.drift_recent_window),
            mean_drop_fraction=float(CFG.drift_mean_drop_fraction),
            zscore_threshold=float(CFG.drift_zscore_threshold),
            backoff_seconds=int(CFG.drift_backoff_s),
        )
    )

    incident_journal = IncidentJournal(_paths["logs"])

    zmq_bridge = ZMQBridge(
        req_timeout_ms=int(max(1, getattr(CFG, "bridge_default_timeout_ms", 1200))),
        req_retries=int(max(1, getattr(CFG, "bridge_default_retries", 1))),
        heartbeat_trade_priority_window_ms=int(
            max(0, getattr(CFG, "bridge_heartbeat_trade_priority_window_ms", 300))
        ),
        audit_async=bool(getattr(CFG, "bridge_audit_async_enabled", True)),
        audit_queue_maxsize=int(max(128, getattr(CFG, "bridge_audit_queue_maxsize", 8192))),
        audit_queue_put_timeout_ms=int(max(0, getattr(CFG, "bridge_audit_queue_put_timeout_ms", 2))),
        audit_batch_size=int(max(1, getattr(CFG, "bridge_audit_batch_size", 64))),
        audit_flush_interval_ms=int(max(10, getattr(CFG, "bridge_audit_flush_interval_ms", 200))),
    )
    zmq_bridge.setup_sockets()

    bot = SafetyBot(
        config=config,
        db=db,
        gov=gov,
        risk_manager=risk_manager,
        limits=limits,
        black_swan_guard=black_swan_guard,
        self_heal_guard=self_heal_guard,
        canary_guard=canary_guard,
        drift_guard=drift_guard,
        incident_journal=incident_journal,
        zmq_bridge=zmq_bridge,
        black_swan_guard_v2=black_swan_guard_v2,
    )
    try:
        bot.run()
    finally:
        zmq_bridge.close()

