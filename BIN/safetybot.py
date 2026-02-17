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
import shutil
import subprocess
import platform
import getpass
import re
import base64
import ctypes

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
from pathlib import Path
from typing import Dict, Optional, List, Tuple, Any
try:
    import common_guards as cg
    import common_contract as cc
    from black_swan_guard import BlackSwanGuard, BlackSwanPolicy, BlackSwanSignal
    from self_heal_guard import SelfHealGuard, SelfHealPolicy
    from canary_rollout_guard import CanaryRolloutGuard, CanaryPolicy
    from drift_guard import DriftGuard, DriftPolicy
    from incident_guard import IncidentJournal, classify_retcode
    from oanda_limits_guard import OandaLimitsGuard
    from config_manager import ConfigManager
    from risk_manager import RiskManager
except Exception:  # pragma: no cover
    import common_guards as cg
    import common_contract as cc
    from black_swan_guard import BlackSwanGuard, BlackSwanPolicy, BlackSwanSignal
    from self_heal_guard import SelfHealGuard, SelfHealPolicy
    from canary_rollout_guard import CanaryRolloutGuard, CanaryPolicy
    from drift_guard import DriftGuard, DriftPolicy
    from incident_guard import IncidentJournal, classify_retcode
    from oanda_limits_guard import OandaLimitsGuard
    from config_manager import ConfigManager
    from risk_manager import RiskManager
try:
    from runtime_root import (
        REQUIRED_OANDA_MT5_EXE,
        ensure_dirs,
        get_run_mode,
        get_runtime_root,
        project_paths,
        require_live_oanda_terminal,
    )
except Exception:  # pragma: no cover
    from .runtime_root import (
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
    # częstotliwość sprawdzania obecności klucza USB podczas uśpienia pętli
    usb_watch_check_interval_sec: int = 3
    # Legacy pull cadence values still referenced in strategy hot/warm/eco path.
    # Keep explicit defaults aligned with CONFIG/scheduler.json.
    m5_pull_sec_hot: int = 60
    m5_pull_sec_warm: int = 120
    m5_pull_sec_eco: int = 300
    # If ECO limits collapse to zero while flat, keep at least minimal market probing alive.
    eco_probe_symbols_when_flat: int = 1

    # --- V1.10: Time anchoring + open-position always-on guard ---
    open_positions_guard_sec: int = 60

    # Okresowa synchronizacja zegara z czasem serwera (koszt: 1 PRICE na sync)
    time_anchor_sync_sec: int = 900   # 15 min
    time_anchor_min_price_remaining: int = 40  # nie syncuj, jeśli budżet niski

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
    oanda_market_orders_per_sec: int = 50     # applies to market Orders only
    oanda_positions_pending_limit: int = 450  # house stop before 500 (positions + pending orders, excl. TP/SL)

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
    price_emergency_reserve_fraction: float = 0.12

    sys_soft_fraction: float = 0.90
    sys_emergency_reserve: int = 40  # stała rezerwa awaryjna SYS (w ramach sys_budget_day)

    # Progi ECO (P0): ECO gdy dowolny licznik >= eco_threshold_pct swojego budżetu
    eco_threshold_pct: float = 0.80

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
    execution_burst_guard_enabled: bool = True
    execution_burst_lookback_sec: int = 120
    execution_burst_error_threshold: int = 4
    execution_burst_backoff_s: int = 180
    execution_burst_symbol_cooldown_s: int = 180

    # --- Grupy i profile ---
    symbols_to_trade = ["EURUSD", "GBPUSD", "XAUUSD", "DAX40", "US500"]
    symbol_group_map = {
        "EURUSD": "FX",
        "GBPUSD": "FX",
        "XAUUSD": "METAL",
        "XAGUSD": "METAL",
        "GOLD": "METAL",
        "SILVER": "METAL",
        "DAX40": "INDEX",
        "DE40": "INDEX",
        "DE30": "INDEX",
        "GER40": "INDEX",
        "GER30": "INDEX",
        "US500": "INDEX",
        "SPX500": "INDEX",
    }
    index_profile_map = {
        "DAX40": "EU",
        "DE40": "EU",
        "DE30": "EU",
        "GER40": "EU",
        "GER30": "EU",
        "US500": "US",
        "SPX500": "US",
    }
    # Broker-specific base aliases (OANDA TMS MT5 may expose DE30/GOLD names).
    symbol_alias_map: Dict[str, Tuple[str, ...]] = {
        "EURUSD": ("EURUSD",),
        "GBPUSD": ("GBPUSD",),
        "XAUUSD": ("XAUUSD", "GOLD"),
        "XAGUSD": ("XAGUSD", "SILVER"),
        "DAX40": ("DAX40", "DE40", "DE30", "GER40", "GER30"),
        "US500": ("US500", "SPX500"),
    }
    symbol_suffixes: Tuple[str, ...] = ("", ".pro", ".stp", ".pl")
    # OANDA MT5 policy guard: block accidental algo on equity/ETF/ETN symbols (non-close only).
    symbol_policy_enabled: bool = True
    symbol_policy_fail_on_other_group: bool = True
    symbol_policy_allowed_groups: Tuple[str, ...] = ("FX", "METAL", "INDEX")
    symbol_policy_forbidden_symbol_markers: Tuple[str, ...] = (".ETF", "_CFD.ETF", ".ETN", "_CFD.ETN")
    symbol_policy_forbidden_path_markers: Tuple[str, ...] = ("STOCK", "AKCJE", "EQUITY", "ETF", "ETN")

    # dzienny podział budżetu PRICE między grupy (z możliwością pożyczania)
    group_price_shares = {"FX": 0.45, "METAL": 0.25, "INDEX": 0.30}
    group_borrow_fraction: float = 0.15  # ile z niewykorzystanych budżetów innych grup można "pożyczyć"

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

    # Learner QA gate (P1): anti-overfit traffic-light from learner_offline.
    learner_qa_gate_enabled: bool = True
    learner_qa_red_to_eco: bool = True
    learner_qa_yellow_symbol_cap: int = 1

    # Legacy/backward compatibility names (deprecated; do not use for sizing)
    max_risk_cap_acct: float = 0.0
    max_risk_cap_pln: float = max_risk_cap_acct

    sma_fast: int = 20
    sma_trend: int = 200
    adx_period: int = 14
    adx_threshold: int = 22

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
        self._server_utc = server_utc
        self._mono = time.monotonic()
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

def pl_day_start_utc_ts(ts_utc: Optional[dt.datetime] = None) -> int:
    """Start of PL day (00:00 Europe/Warsaw) expressed as UTC epoch seconds."""
    if ts_utc is None:
        ts_utc = now_utc()
    p = ts_utc.astimezone(TZ_PL)
    start_pl = p.replace(hour=0, minute=0, second=0, microsecond=0)
    start_utc = start_pl.astimezone(UTC)
    return int(start_utc.timestamp())

def in_window(local_dt: dt.datetime, start_hm: Tuple[int, int], end_hm: Tuple[int, int]) -> bool:
    s = local_dt.replace(hour=start_hm[0], minute=start_hm[1], second=0, microsecond=0)
    e = local_dt.replace(hour=end_hm[0], minute=end_hm[1], second=0, microsecond=0)
    return s <= local_dt <= e

# =============================================================================
# USB
# =============================================================================

def get_usb_path(label: Optional[str] = None) -> Optional[Path]:
    """Return the root path of the USB key (by filesystem label), or None.

    Timeout-protected to avoid hangs on PowerShell/WMIC calls.
    """
    label = (label or "OANDAKEY").strip()
    drive_letter: Optional[str] = None

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
                        lock_path.unlink(missing_ok=True)
                        time.sleep(0.05)
                        continue
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        # ACL fallback: overwrite stale lock in place and claim ownership.
                        try:
                            payload = json.dumps({"pid": os.getpid(), "ts_utc": now_utc().isoformat().replace('+00:00','Z')}, separators=(",", ":"))
                            lock_path.write_text(payload, encoding="utf-8")
                            return
                        except Exception as e:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                            time.sleep(0.1)
                            continue
                if pid and (not pid_exists(pid)):
                    try:
                        lock_path.unlink(missing_ok=True)
                        time.sleep(0.05)
                        continue
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                        try:
                            payload = json.dumps({"pid": os.getpid(), "ts_utc": now_utc().isoformat().replace('+00:00','Z')}, separators=(",", ":"))
                            lock_path.write_text(payload, encoding="utf-8")
                            return
                        except Exception as e:
                            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
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
        handlers=handlers
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
                cfg[k.strip()] = v.strip()
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

    def group_price_used_today(self, grp: str) -> int:
        ny_date, _ = ny_day_hour_key()
        c = self.conn.cursor()
        c.execute("""SELECT COALESCE(SUM(count), 0) FROM req_hourly
                     WHERE ny_date=? AND category='PRICE' AND grp=?""", (ny_date, grp))
        row = c.fetchone()
        return int(row[0] if row else 0)

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
        for x in (getattr(CFG, "symbol_policy_allowed_groups", ("FX", "METAL", "INDEX")) or ())
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

# --- DB migration constants (P0) ---
LEGACY_DB_NAMES = [
    "mt5_v1_10_1.sqlite",
    "mt5_state.sqlite",
    "safetybot_state.sqlite",
]

# SQLite PRAGMA user_version target for decision_events.sqlite
CURRENT_SCHEMA_VERSION = 2


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
    """Atomic JSON write (best-effort fsync): write to .tmp in same dir then os.replace()."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(data)
            f.flush()
            try:
                os.fsync(f.fileno())
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        try:
            os.replace(tmp, path)
        except PermissionError as e:
            # Windows can deny atomic replace under transient AV/ACL locks; fallback to direct overwrite.
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            with open(path, "w", encoding="utf-8", newline="\n") as f2:
                f2.write(data)
                f2.flush()
                try:
                    os.fsync(f2.fileno())
                except Exception as e2:
                    cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e2)
    finally:
        try:
            if tmp.exists():
                tmp.unlink(missing_ok=True)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

def build_runtime_boot_snapshot_payload(runtime_root: Path, universe: List[Tuple[str, str, str]]) -> Dict[str, Any]:
    allowed_groups = [
        str(x).strip().upper()
        for x in (getattr(CFG, "symbol_policy_allowed_groups", ("FX", "METAL", "INDEX")) or ())
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
            "house_price_warn_per_day": int(getattr(CFG, "house_price_warn_per_day", 0)),
            "house_price_hard_stop_per_day": int(getattr(CFG, "house_price_hard_stop_per_day", 0)),
            "house_orders_per_sec": int(getattr(CFG, "house_orders_per_sec", 0)),
            "house_positions_pending_limit": int(getattr(CFG, "house_positions_pending_limit", 0)),
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
    try:
        if not path.exists():
            return None
        sz = path.stat().st_size
        if sz <= 0 or sz > SCOUT_MAX_BYTES:
            return None
        raw = path.read_text(encoding="utf-8", errors="replace")
        obj = json.loads(raw)
        if not isinstance(obj, dict):
            return None
        return obj
    except Exception as e:
        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
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
        age = (now_utc() - ts).total_seconds()
        if age < 0 or age > ttl:
            return None
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
        age = (now_utc() - ts).total_seconds()
        if age < 0:
            return None
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

    view = candidates[:top_k]
    rest = candidates[top_k:]
    if len(view) < 2:
        return candidates

    def _median(vals: List[float]) -> float:
        v = sorted(float(x) for x in vals)
        n = len(v)
        if n <= 0:
            return 0.0
        mid = n // 2
        return v[mid] if (n % 2 == 1) else 0.5 * (v[mid - 1] + v[mid])

    # Near-tie detector (no fixed epsilon): compare gap(top1-top2) to median gap across Top-K
    prios = [float(x[0]) for x in view]
    pr_sorted = sorted(prios, reverse=True)
    gaps = [pr_sorted[i] - pr_sorted[i + 1] for i in range(len(pr_sorted) - 1)]
    gap12 = pr_sorted[0] - pr_sorted[1]
    med_gap = _median(gaps) if gaps else 0.0
    near_tie = (len(gaps) == 0) or (gap12 <= med_gap)

    if not near_tie:
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
def is_price_kind(kind: str) -> bool:
    return kind == "tick" or kind.startswith("rates_")

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
                outcome_closed_ts_utc TEXT
            );"""
        )
        self.conn.execute("CREATE INDEX IF NOT EXISTS ix_decision_events_ts ON decision_events(ts_utc);")

    def insert_event(self, row: Dict[str, Any]) -> None:
        cols = [
            "event_id","ts_utc","server_time_anchor","topk_json","choice_A","choice_shadowB","verdict_light",
            "signal","sl","tp","entry_price","volume","spread_points",
            "price_used","price_requests_trade","sys_used","is_paper","mt5_order","mt5_deal",
            "outcome_pnl_net","outcome_profit","outcome_commission","outcome_swap","outcome_fee","outcome_closed_ts_utc"
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

class M5BarsStore:
    """Lightweight SQLite store for M5 bars (used by Scout evaluator)."""
    def __init__(self, db_dir: Path):
        self.db_dir = db_dir
        self.db_dir.mkdir(parents=True, exist_ok=True)
        self.db_path = self.db_dir / M5_BARS_DB_NAME
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
        self.conn.executemany("INSERT OR REPLACE INTO m5_bars(symbol,t_utc,o,h,l,c) VALUES (?,?,?,?,?,?)", rows)

    

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

        self.sys_day_cap = int(getattr(CFG, 'sys_budget_day', CFG.sys_day_cap))
        self.sys_emergency = int(min(int(getattr(CFG, 'sys_emergency_reserve', 0)), max(0, self.sys_day_cap)))
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

    def _group_borrow_allowance(self, grp: str) -> int:
        """Ile grupa może \"pożyczyć\" z niewykorzystanych capów innych grup (CFG.group_borrow_fraction)."""
        shares = dict(getattr(CFG, "group_price_shares", {}) or {})
        if not shares:
            return 0
        try:
            frac = float(getattr(CFG, "group_borrow_fraction", 0.0) or 0.0)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            frac = 0.0
        frac = max(0.0, min(1.0, frac))
        if frac <= 0.0:
            return 0
        unused_other = 0
        for g in shares.keys():
            if g == grp:
                continue
            cap_g = int(self._group_price_cap(g))
            used_g = int(self.db.group_price_used_today(g))
            unused_other += max(0, cap_g - used_g)
        return int(unused_other * frac)


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
                    if used_g + cost > cap_g + self._group_borrow_allowance(grp):
                        return False
        else:
            if emergency:
                if st["sys_em_remaining"] < cost:
                    return False
            else:
                if st["sys_remaining"] < cost:
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
        # Rate-limit helper for Appendix 4 (market orders/sec)
        self._deal_ts: List[float] = []
        self._exec_error_ts: List[float] = []
        self.incident_journal: Optional[IncidentJournal] = None

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

    def symbol_info_cached(self, symbol: str, grp: str, db: Persistence) -> Optional[object]:
        now = time.time()
        cached = self._sym_info_cache.get(symbol)
        if cached and (now - cached[0] < CFG.symbol_info_cache_ttl_sec):
            return cached[1]
        if self.limits is not None:
            if not self.limits.note_price_request(now_ts=now, emergency=False):
                logging.info(f"SKIP_PRICE_LIMIT kind=symbol_info symbol={symbol}")
                return None
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
        if not self.gov.consume("SYS", "__POSITIONS__", "positions_get", 1, emergency=bool(emergency)):
            return None
        return mt5.positions_get()

    def orders_get(self, emergency: bool = False) -> Optional[Tuple]:
        """Pending orders (does not include SL/TP as separate objects in typical MT5 setups)."""
        if mt5 is None:
            return None
        if not self.gov.consume("SYS", "__ORDERS__", "orders_get", 1, emergency=bool(emergency)):
            return None
        return mt5.orders_get()

    def account_info(self):
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
        kind = f"rates_{timeframe}"
        if self.limits is not None:
            if not self.limits.note_price_request(now_ts=time.time(), emergency=False):
                logging.info(f"SKIP_PRICE_LIMIT kind=copy_rates symbol={symbol}")
                return None
        if not self.gov.consume(grp, symbol, kind, 1, emergency=False):
            return None
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, n)
        if rates is None:
            return None
        df = pd.DataFrame(rates)
        t_series = pd.to_datetime(df["time"], unit="s", utc=True)
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
        if self.limits is not None:
            if not self.limits.note_price_request(now_ts=time.time(), emergency=bool(emergency)):
                logging.info(f"SKIP_PRICE_LIMIT kind=tick symbol={symbol} emergency={int(bool(emergency))}")
                return None
        if not self.gov.consume(grp, symbol, "tick", 1, emergency=bool(emergency)):
            return None
        t = mt5.symbol_info_tick(symbol)
        # V1.10: time anchor update (server tick time)
        if t is not None and _TIME_ANCHOR is not None:
            try:
                _TIME_ANCHOR.update(dt.datetime.fromtimestamp(int(t.time), tz=UTC))
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
            # Keep margin: use 90% of Appendix limit.
            limit = max(1, int(CFG.oanda_market_orders_per_sec * 0.90))
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
        now_ts = int(time.time())

        # GLOBAL_BACKOFF gate (allow emergency closes to attempt, but still log state)
        backoff_until = int(self.gov.db.get_global_backoff_until_ts())
        if (not emergency) and backoff_until and now_ts < backoff_until:
            reason = self.gov.db.get_global_backoff_reason()
            logging.info(f"SKIP_GLOBAL_BACKOFF symbol={symbol} until_ts={backoff_until} reason={reason}")
            return None

        if self.limits is not None:
            if not self.limits.allow_order_submit(now_ts=float(now_ts), emergency=bool(emergency)):
                logging.info(f"SKIP_ORDER_RATE_LIMIT symbol={symbol} emergency={int(bool(emergency))}")
                return None

        # SYS: fresh symbol_info right before order_send
        if self.limits is not None:
            if not self.limits.note_price_request(now_ts=time.time(), emergency=bool(emergency)):
                logging.info(f"SKIP_PRICE_LIMIT kind=symbol_info symbol={symbol} emergency={int(bool(emergency))}")
                return None
        if not self.gov.consume("SYS", symbol, "symbol_info", 1, emergency=bool(emergency)):
            logging.info(f"SKIP_SYS_BUDGET symbol={symbol} kind=symbol_info emergency={int(bool(emergency))}")
            return None
        info = mt5.symbol_info(symbol)
        if info is None:
            logging.info(f"SKIP_SYMBOL_INFO_NONE symbol={symbol} emergency={int(bool(emergency))}")
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
            if stops_level_raw is None or freeze_level_raw is None or point_raw is None:
                raise ValueError("missing stops/freeze/point")
            stops_level = int(stops_level_raw)
            freeze_level = int(freeze_level_raw)
            point = float(point_raw)
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
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                point = 0.0
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
            # Required one-liner (P0)
            logging.info(
                f"SKIP_PRECHECK_STOPS symbol={symbol} side={side} sl_pts={sl_pts:.2f} tp_pts={tp_pts:.2f} "
                f"min_required_pts={min_required_pts} stops_level={stops_level} freeze_level={freeze_level} "
                f"buffer_pts={buffer_pts} cooldown_s={cooldown_s}"
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
            order_st = self.gov.db.get_order_actions_state(now_dt=now_dt)
            used = int(order_st.get("used") or 0)
            if used >= int(CFG.order_budget_day):
                exhausted = []
                if int(order_st.get("ny") or 0) >= int(CFG.order_budget_day):
                    exhausted.append(_seconds_until_next_ny_midnight(now_dt))
                if int(order_st.get("utc") or 0) >= int(CFG.order_budget_day):
                    exhausted.append(_seconds_until_next_utc_midnight(now_dt))
                if int(order_st.get("pl") or 0) >= int(CFG.order_budget_day):
                    exhausted.append(_seconds_until_next_pl_midnight(now_dt))
                cooldown_s = int(min(exhausted) if exhausted else _seconds_until_next_ny_midnight(now_dt))
                self.gov.db.set_cooldown(symbol, cooldown_s, "order_budget_exhausted")
                logging.info(
                    f"SKIP_ORDER_BUDGET symbol={symbol} order_actions_day={used} order_budget={int(CFG.order_budget_day)} "
                    f"order_ny={int(order_st.get('ny') or 0)} order_utc={int(order_st.get('utc') or 0)} order_pl={int(order_st.get('pl') or 0)} "
                    f"cooldown_s={cooldown_s}"
                )
                return None

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
        }
        symbol_cooldown_cfg = {
            10018: (int(CFG.cooldown_market_closed_s), "market_closed"),
            10021: (int(CFG.cooldown_no_quotes_s), "no_quotes"),
            10033: (int(CFG.cooldown_limit_s), "limit_orders"),
            10034: (int(CFG.cooldown_limit_s), "limit_volume"),
            10040: (int(CFG.cooldown_limit_s), "limit_positions"),
            10042: (int(CFG.cooldown_trade_mode_s), "long_only"),
            10043: (int(CFG.cooldown_trade_mode_s), "short_only"),
            10044: (int(CFG.cooldown_trade_mode_s), "close_only"),
            10045: (int(CFG.cooldown_trade_mode_s), "fifo_close"),
            10046: (int(CFG.cooldown_trade_mode_s), "hedge_prohibited"),
        }
        attempt = 0
        last_res = None
        while True:
            # Budget check per attempt (non-emergency; strict-guard across NY/UTC/PL)
            if not emergency:
                order_st = self.gov.db.get_order_actions_state(now_dt=now_dt)
                used = int(order_st.get("used") or 0)
                if (used + 1) > int(CFG.order_budget_day):
                    exhausted = []
                    if int(order_st.get("ny") or 0) >= int(CFG.order_budget_day):
                        exhausted.append(_seconds_until_next_ny_midnight(now_dt))
                    if int(order_st.get("utc") or 0) >= int(CFG.order_budget_day):
                        exhausted.append(_seconds_until_next_utc_midnight(now_dt))
                    if int(order_st.get("pl") or 0) >= int(CFG.order_budget_day):
                        exhausted.append(_seconds_until_next_pl_midnight(now_dt))
                    cooldown_s = int(min(exhausted) if exhausted else _seconds_until_next_ny_midnight(now_dt))
                    self.gov.db.set_cooldown(symbol, cooldown_s, "order_budget_exhausted")
                    logging.info(
                        f"SKIP_ORDER_BUDGET symbol={symbol} order_actions_day={used} order_budget={int(CFG.order_budget_day)} "
                        f"order_ny={int(order_st.get('ny') or 0)} order_utc={int(order_st.get('utc') or 0)} order_pl={int(order_st.get('pl') or 0)} "
                        f"cooldown_s={cooldown_s}"
                    )
                    return None

            # Count every mt5.order_send call as ORDER action/day (P0)
            self.gov.db.inc_order_action(1, now_dt=now_dt)

            attempt += 1
            # Appendix 4: market orders/sec guard
            self._rate_limit_market_orders(request)
            res = mt5.order_send(request)
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
            logging.info(f"ORDER_SEND symbol={symbol} attempt={attempt} retcode_num={ret_num} retcode_name={ret_name}")
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

                        _TIME_ANCHOR.update(dt.datetime.fromtimestamp(int(t.time), tz=UTC))

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


class MT5Client(ExecutionEngine):
    """Backward-compatible alias after extracting MT5 execution logic."""

    def order_send(self, symbol: str, grp: str, request: dict, emergency: bool = False):
        return super().order_send(symbol, grp, request, emergency=emergency)

# =============================================================================
# ACTIVITY CONTROLLER (profile + score + warunki)
# =============================================================================

from scheduler import ActivityController


# =============================================================================
# STRATEGY (H4 trend priority, tick on demand)
# =============================================================================

class StrategyCache:
    def __init__(self):
        self.trend_cache: Dict[str, Tuple[float, str, str]] = {}
        self.last_m5_calc_ts: Dict[str, float] = {}
        self.last_m5_bar_time: Dict[str, pd.Timestamp] = {}

class StandardStrategy:
    def __init__(self, engine: ExecutionEngine, gov: RequestGovernor, throttle: OrderThrottle, db: Persistence, config: ConfigManager, risk_manager: RiskManager):
        self.engine = engine
        self.gov = gov
        self.throttle = throttle
        self.db = db
        self.config = config
        self.risk_manager = risk_manager
        self.cache = StrategyCache()
        self.last_indicators: Dict[str, Dict[str, Any]] = {}
        self._scan_meta: Dict[str, Any] = {}
        self.decision_store: Optional[DecisionEventStore] = None
        self._last_eval_price_before: Optional[int] = None
        self._last_eval_sys_before: Optional[int] = None
        self._last_event_id: Optional[str] = None

    def rollover_safe(self) -> bool:
        n = now_ny()
        start = n.replace(hour=17, minute=0, second=0, microsecond=0) - dt.timedelta(minutes=CFG.rollover_block_minutes_before)
        end = n.replace(hour=17, minute=0, second=0, microsecond=0) + dt.timedelta(minutes=CFG.rollover_block_minutes_after)
        return not (start <= n <= end)

    def force_close_window(self) -> bool:
        n = now_ny()
        start = n.replace(hour=17, minute=0, second=0, microsecond=0) - dt.timedelta(minutes=CFG.force_close_before_rollover_min)
        end = n.replace(hour=17, minute=0, second=0, microsecond=0)
        return start <= n <= end

    def get_trend(self, symbol: str, grp: str) -> Tuple[str, str]:
        now_ts = time.time()
        cached = self.cache.trend_cache.get(symbol)
        if cached and (now_ts - cached[0] < CFG.trend_cache_ttl_sec):
            return cached[1], cached[2]

        df_h4 = self.engine.copy_rates(symbol, grp, CFG.timeframe_trend_h4, 260)
        df_d1 = self.engine.copy_rates(symbol, grp, CFG.timeframe_trend_d1, 260)
        if df_h4 is None or df_d1 is None or len(df_h4) < 220 or len(df_d1) < 220:
            return "NEUTRAL", "NEUTRAL"

        df_h4["sma"] = ta.trend.sma_indicator(df_h4["close"], window=CFG.sma_trend)
        df_d1["sma"] = ta.trend.sma_indicator(df_d1["close"], window=CFG.sma_trend)

        trend_h4 = "BUY" if float(df_h4["close"].iloc[-1]) > float(df_h4["sma"].iloc[-1]) else "SELL"
        trend_d1 = "BUY" if float(df_d1["close"].iloc[-1]) > float(df_d1["sma"].iloc[-1]) else "SELL"
        self.cache.trend_cache[symbol] = (now_ts, trend_h4, trend_d1)
        return trend_h4, trend_d1

    def m5_indicators_if_due(self, symbol: str, grp: str, mode: str) -> Optional[Dict]:
        now_ts = time.time()
        pull = CFG.m5_pull_sec_eco if mode == "ECO" else (CFG.m5_pull_sec_warm if mode == "WARM" else CFG.m5_pull_sec_hot)
        last = self.cache.last_m5_calc_ts.get(symbol, 0.0)
        if now_ts - last < pull:
            return None

        df = self.engine.copy_rates(symbol, grp, CFG.timeframe_trade, 120)
        if df is None or len(df) < 60:
            self.cache.last_m5_calc_ts[symbol] = now_ts
            return None

        self.cache.last_m5_calc_ts[symbol] = now_ts
        last_bar = df["time"].iloc[-1]
        prev_bar = self.cache.last_m5_bar_time.get(symbol)
        if prev_bar is not None and last_bar == prev_bar :
            return None
        self.cache.last_m5_bar_time[symbol] = last_bar

        df["sma_fast"] = ta.trend.sma_indicator(df["close"], window=CFG.sma_fast)
        adx = ta.trend.ADXIndicator(df["high"], df["low"], df["close"], window=CFG.adx_period)
        df["adx"] = adx.adx()

        atr = None
        try:
            tr1 = (df["high"] - df["low"]).abs()
            tr2 = (df["high"] - df["close"].shift(1)).abs()
            tr3 = (df["low"] - df["close"].shift(1)).abs()
            tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1)
            atr = float(tr.rolling(window=CFG.atr_period, min_periods=CFG.atr_period).mean().iloc[-1])
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            atr = None

        ind = {
            "close": float(df["close"].iloc[-1]),
            "open": float(df["open"].iloc[-1]),
            "sma": float(df["sma_fast"].iloc[-1]),
            "adx": float(df["adx"].iloc[-1]),
            "atr": float(atr) if atr is not None else None,
        }
        try:
            self.last_indicators[symbol_base(symbol)] = dict(ind)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
        return ind

    def try_trade(self, symbol: str, grp: str, mode: str, info, signal: str, is_paper: bool):
        # tick na żądanie: spread + cena wykonania
        tick = self.engine.tick(symbol, grp)
        if not tick:
            return

        spread_pts = (tick.ask - tick.bid) / float(info.point)
        self.db.log_spread(symbol, spread_pts)
        p80 = self.db.get_p80_spread(symbol)
        # Execution green gate: scalp (HOT) is only allowed on tight spreads; if spread widens,
        # we either downgrade HOT->WARM (if still acceptable) or skip.
        if p80 > 0:
            m_upper = str(mode).upper()
            if m_upper == "HOT" and spread_pts > float(CFG.spread_gate_hot_factor) * p80:
                if spread_pts <= float(CFG.spread_gate_warm_factor) * p80:
                    mode = "WARM"
                else:
                    return
            elif m_upper == "WARM" and spread_pts > float(CFG.spread_gate_warm_factor) * p80:
                return
            elif m_upper == "ECO" and spread_pts > float(CFG.spread_gate_eco_factor) * p80:
                return

        price = float(tick.ask if signal == "BUY" else tick.bid)

        # account/risk context (no guessing)
        acc = self.engine.account_info()
        if acc is None:
            return
        bal_now = float(getattr(acc, "balance", 0.0) or 0.0)
        eq_now = float(getattr(acc, "equity", bal_now) or bal_now)

        sl_points = CFG.fixed_sl_points
        tp_points = CFG.fixed_tp_points
        point = float(getattr(info, "point", 0.0) or 0.0)
        if point <= 0:
            return
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
            return

        soft_loss = (dd_pct >= float(self.config.risk['daily_loss_soft_pct']))
        risk_pct = self.risk_manager.get_risk_pct(mode, soft_loss)

        risk_money = eq_now * risk_pct
        if risk_money <= 0:
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
            symbol
        )

        if volume is None:
            return
        
        positions = self.engine.positions_get(emergency=False)
        if positions is None:
            return
        
        our_positions = [p for p in positions if int(getattr(p, "magic", 0) or 0) == int(CFG.magic_number)]
        
        if not self.risk_manager.check_portfolio_heat(our_positions, eq_now, symbol, risk_money, self.engine, self.db, grp):
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
        try:
            shadowB = self._scan_meta.get("choice_shadowB")
            verdict_light = self._scan_meta.get("verdict_light")
            server_time_anchor = self._scan_meta.get("server_time_anchor")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        topk_payload = []
        try:
            topk_list = self._scan_meta.get("topk_final") or self._scan_meta.get("topk_base") or []
            proposals = self._scan_meta.get("proposals") or {}
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
                topk_payload.append({
                    "raw": raw,
                    "sym": it.get("sym"),
                    "grp": it.get("grp"),
                    "prio": it.get("prio"),
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
                "outcome_pnl_net": None,
                "outcome_profit": None,
                "outcome_commission": None,
                "outcome_swap": None,
                "outcome_fee": None,
                "outcome_closed_ts_utc": None,
            }
            try:
                self.decision_store.insert_event(row)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        comment = f"SBOT-EVT-{event_id}" if event_id else f"MT5_SAFETY_BOT_{CFG.BOT_VERSION}"

        req = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": volume,
            "type": cmd,
            "price": float(price),
            "sl": float(sl),
            "tp": float(tp),
            "deviation": 20,
            "magic": CFG.magic_number,
            "comment": comment,
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        if is_paper:
            logging.info(f"PAPER TRADE: {signal} {symbol} @ {price} | SL {sl} TP {tp}")
            return

        res = self.engine.order_send(symbol, grp, req)
        if not res or res.retcode != mt5.TRADE_RETCODE_DONE:
            logging.error(f"Order failed: {getattr(res, 'retcode', None)} {getattr(res, 'comment', '')}")
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
                    "outcome_pnl_net": None,
                    "outcome_profit": None,
                    "outcome_commission": None,
                    "outcome_swap": None,
                    "outcome_fee": None,
                    "outcome_closed_ts_utc": None,
                })
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        self.throttle.register_trade()
        logging.info(f"Order executed: {getattr(res, 'order', None)}")
    def evaluate_symbol(self, symbol: str, grp: str, mode: str, info, is_paper: bool) -> None:
        # P0: global backoff + per-symbol cooldown (avoid wasting PRICE budget on repeated skips)
        try:
            now_ts = int(time.time())
            gb_until = int(self.db.get_global_backoff_until_ts())
            if gb_until and now_ts < gb_until:
                reason = self.db.get_global_backoff_reason()
                logging.info(f"SKIP_GLOBAL_BACKOFF symbol={symbol} until_ts={gb_until} reason={reason}")
                return
            if self.db.is_cooldown_active(symbol, now_ts=now_ts):
                cd_until = self.db.get_cooldown_until_ts(symbol)
                cd_reason = self.db.get_cooldown_reason(symbol)
                logging.info(f"SKIP_COOLDOWN symbol={symbol} until_ts={cd_until} reason={cd_reason}")
                return
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # soft-mode price: żadnych nowych wejść
        if self.gov.price_soft_mode():
            return
        if not self.throttle.can_trade():
            return
        if not self.rollover_safe():
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
        if ind["adx"] < CFG.adx_threshold:
            return

        trend_h4, _trend_d1 = self.get_trend(symbol, grp)
        if trend_h4 == "NEUTRAL":
            return

        signal = None
        if trend_h4 == "BUY" and ind["close"] > ind["sma"] and ind["close"] > ind["open"]:
            signal = "BUY"
        elif trend_h4 == "SELL" and ind["close"] < ind["sma"] and ind["close"] < ind["open"]:
            signal = "SELL"

        if signal:
            try:
                base = symbol_base(symbol)
                mid = float(ind.get('close'))
                point = float(getattr(info, 'point', 0.0) or 0.0)
                if point == 0.0:
                    point = 1e-5
                sl_points = CFG.fixed_sl_points
                tp_points = CFG.fixed_tp_points
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
                    'point': point,
                    'tick_size': float(getattr(info, 'trade_tick_size', 0.0) or 0.0),
                    'tick_value': float(getattr(info, 'trade_tick_value', 0.0) or 0.0),
                    'spread_points': float(getattr(info, 'spread', 0.0) or 0.0),
                }
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            self.try_trade(symbol, grp, mode, info, signal, is_paper)

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
    def __init__(self, config, db, gov, risk_manager, limits, black_swan_guard, self_heal_guard, canary_guard, drift_guard, incident_journal):
        self.cfg = CFG
        self.config = config
        self.db = db
        self.gov = gov
        self.risk_manager = risk_manager
        self.limits = limits
        self.black_swan_guard = black_swan_guard
        self.self_heal_guard = self_heal_guard
        self.canary_guard = canary_guard
        self.drift_guard = drift_guard
        self.incident_journal = incident_journal

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
                msg = "CRITICAL: Brak wymaganych pól konfiguracji: " + ", ".join(missing) + ". Uzupełnij CFG i uruchom bramki. SafetyBot nie startuje."
                print(msg)
                logging.getLogger("SafetyBot").error(msg)
                raise SystemExit(3)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            print('CRITICAL: Nie można wczytać TOKEN/BotKey.env. SafetyBot nie startuje.')
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
        self.throttle = OrderThrottle()

        # --- stores for Scout ---
        self.decision_store = DecisionEventStore(self.db_dir)
        self.bars_store = M5BarsStore(self.db_dir)
        self.execution_engine.bars_store = self.bars_store

        # --- strategy / controller ---
        self.ctrl = ActivityController(self.db, self.config)
        self.strategy = StandardStrategy(self.execution_engine, self.gov, self.throttle, self.db, self.config, self.risk_manager)
        self.strategy.decision_store = self.decision_store
        self.resolved_symbols = {}
        # Cache of last known open positions; used by guard polling cadence.
        self._positions_cache: Dict[str, List] = {}

        # --- connect + universe ---
        if not self.execution_engine.connect():
            logging.critical('Nie udało się połączyć z MT5. SafetyBot kończy pracę.')
            raise SystemExit(1)
        self.universe = self._build_universe()
        if not self.universe:
            logging.critical('Universe puste. SafetyBot kończy pracę.')
            raise SystemExit(1)

        # SafetyBot reads Scout outputs ONLY from local runtime (not from USB).
        snap_path = write_runtime_boot_snapshot(self.runtime_root, self.universe)
        if snap_path is not None:
            logging.info(f"RUNTIME_BOOT_SNAPSHOT path={snap_path}")
        self.usb_root = str(self.runtime_root)

        # prime server time anchor (1 tick request)
        self._prime_time_anchor()

        # paper trading mode
        self.is_paper = bool(CFG.paper_trading)
        if self.is_paper:
            self.paper_start_ts = self.db.get_or_set_paper_start()
        else:
            self.paper_start_ts = 0.0

    def resolve_canon_symbol(self, raw_sym: str) -> Optional[str]:
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
                    try:
                        if hasattr(engine, "_sym_info_cache"):
                            engine._sym_info_cache[cand] = (time.time(), info)
                    except Exception as e:
                        cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                    self.resolved_symbols[raw_sym] = cand
                    return cand
        return None

    def _build_universe(self) -> List[Tuple[str, str, str]]:
        """Buduje listę instrumentów (raw, canon, grp) i dodaje je do MarketWatch tylko raz.
        Cel: nie przepalać SYS budżetu na symbol_select w każdej iteracji.
        """
        out: List[Tuple[str, str, str]] = []
        for raw in CFG.symbols_to_trade:
            sym = self.resolve_canon_symbol(raw)
            if not sym:
                logging.warning(f"Nie znaleziono symbolu w MT5: {raw}")
                continue
            grp = guess_group(sym)
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

        m: Dict[str, List] = {}
        if pos:
            for p in pos:
                m.setdefault(p.symbol, []).append(p)

        self._positions_cache = dict(m)
        return dict(self._positions_cache)

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
            return signal

        signal = self.black_swan_guard.evaluate(vols, spreads)
        logging.info(
            f"BLACK_SWAN stress={signal.stress_index:.3f} thr={signal.threshold:.3f} "
            f"prec_thr={signal.precaution_threshold:.3f} black_swan={int(signal.black_swan)} "
            f"precaution={int(signal.precaution)} n_vol={len(vols)} n_spread={len(spreads)} "
            f"reason={','.join(signal.reasons)}"
        )
        return signal

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
            obj = json.loads(p.read_text(encoding="utf-8", errors="ignore") or "{}")
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
            age = (now_utc() - ts).total_seconds()
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

    def scan_once(self):
        st = self.gov.day_state()

        # ECO on budget pressure (PRICE / SYS / ORDER)
        eco_by_budget = False
        eco_reason = ""
        price_pct = 0.0
        sys_pct = 0.0
        order_pct = 0.0
        try:
            thr = float(getattr(CFG, "eco_threshold_pct", getattr(CFG, "order_eco_threshold_pct", 0.80)))
            price_pct = (float(st.get("price_requests_day") or 0) / float(max(1, st.get("price_budget") or 1)))
            sys_pct = (float(st.get("sys_requests_day") or 0) / float(max(1, st.get("sys_budget") or 1)))
            order_pct = (float(st.get("order_actions_day") or 0) / float(max(1, st.get("order_budget") or 1)))

            reasons = []
            if price_pct >= thr:
                reasons.append("PRICE")
            if sys_pct >= thr:
                reasons.append("SYS")
            if order_pct >= thr:
                reasons.append("ORDER")

            if reasons:
                eco_by_budget = True
                eco_reason = ",".join(reasons)
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            eco_by_budget = False
            eco_reason = ""

        # P0 BUDGET log (hard-required fields: day_ny + utc_day + eco)
        logging.info(
            f"BUDGET day_ny={st['day_ny']} utc_day={st['utc_day']} eco={int(bool(eco_by_budget))} pl_day={st.get('pl_day','')} "
            f"price_requests_day={st['price_requests_day']} order_actions_day={st['order_actions_day']} sys_requests_day={st['sys_requests_day']} "
            f"price_budget={st['price_budget']} order_budget={st['order_budget']} sys_budget={st['sys_budget']}"
        )

        if eco_by_budget:
            logging.warning(
                f"ECO_MODE reason={eco_reason} price_pct={price_pct:.3f} sys_pct={sys_pct:.3f} order_pct={order_pct:.3f}"
            )

# Additional legacy line kept for continuity (informational only)
        logging.info(
            f"PRICE used={st['price_used']}/{self.gov.price_trade_budget} + em={st['price_em_used']}/{self.gov.price_emergency} "
            f"| SYS used={st['sys_used']}/{self.gov.sys_trade_budget} + em={st['sys_em_used']}/{self.gov.sys_emergency} "
            f"| price_soft={self.gov.price_soft_mode()}"
        )

        # deals (SYS)
        self.poll_deals()
        self_heal_signal = self._evaluate_self_heal()
        canary_signal = self._evaluate_canary_rollout()
        drift_signal = self._evaluate_drift()
        learner_qa_light = self._read_learner_qa_light()

        # rollover global
        rollover_safe = self.strategy.rollover_safe()

        # tryb globalny: bazujemy na FX w tej chwili (rdzeń), ale to tylko do doboru limitów iteracji
        global_mode = "HOT" if self.ctrl.time_weight("FX", "EURUSD") >= 0.95 else ("WARM" if self.ctrl.time_weight("FX", "EURUSD") >= 0.55 else "ECO")
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
                        severity="ERROR",
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
        if bool(getattr(CFG, "learner_qa_gate_enabled", True)) and learner_qa_light == "RED" and bool(getattr(CFG, "learner_qa_red_to_eco", True)):
            global_mode = "ECO"
            logging.warning("LEARNER_QA_RED => ECO")
            try:
                if self.incident_journal is not None:
                    self.incident_journal.note_guard(
                        guard="learner_qa",
                        reason="RED",
                        severity="WARN",
                        category="model",
                    )
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        # V1.10: okresowa synchronizacja czasu serwera (rzadko, tylko jeśli budżet pozwala)
        self._time_anchor_sync_if_due(st)

        # pozycje (SYS): ECO nie może odciąć opieki nad otwartymi pozycjami
        in_force_close = self.strategy.force_close_window()
        positions_map = self.positions_snapshot(global_mode, force=bool(in_force_close))
        open_syms = set(positions_map.keys()) if positions_map else set()

        # jeśli mamy pozycje i wchodzimy w force-close window => pilnuj (użyj rezerwy awaryjnej)
        if open_syms and in_force_close:
            logging.warning("ROLLOVER force-close window: zamykanie pozycji.")
            ok = self.execution_engine.force_flat_all(self.db, retries=CFG.close_retries, delay=CFG.close_retry_delay_sec,
                                        deviation=CFG.kill_close_deviation_points)
            if not ok:
                logging.critical("FORCE FLAT incomplete.")
            return

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

        candidates: List[Tuple[float, str, str, str]] = []  # (priority, raw, sym, grp)
        for raw, sym, grp in self.universe:
            # priorytet: time_weight * score_factor (+ bonus, jeśli mamy otwartą pozycję)
            prio = self.ctrl.time_weight(grp, sym) * self.ctrl.score_factor(grp, sym)
            if sym in open_syms:
                prio += 5.0
            candidates.append((prio, raw, sym, grp))

        candidates.sort(reverse=True, key=lambda x: x[0])

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
        if canary_signal.canary_active:
            n_limit = min(int(n_limit), int(max(0, canary_signal.allowed_symbols)))
        if bool(getattr(CFG, "learner_qa_gate_enabled", True)) and learner_qa_light == "YELLOW":
            n_limit = min(int(n_limit), int(max(0, int(getattr(CFG, "learner_qa_yellow_symbol_cap", 1)))))

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

        # --- SCOUT read-only (tie-breaker rankingu shortlisty) ---
        verdict = load_verdict(self.meta_dir)
        scout = load_scout_advice(self.meta_dir)

        base_topk = candidates[:n_limit]
        verdict_light = (verdict.get("light") if verdict else "INSUFFICIENT_DATA")

        # Tie-break (mode B): tylko gdy verdict GREEN oraz istnieje 'remis praktyczny' TOP-1 vs TOP-2 (działa także w LIVE)
        candidates = apply_scout_tiebreak(
            candidates=candidates,
            scout=scout,
            verdict=verdict,
            top_k=n_limit,
            is_live=(not self.is_paper),
            run_dir=self.run_dir,
        )
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
            self.strategy._scan_meta = {
                "server_time_anchor": self.time_anchor.server_now_utc().replace(tzinfo=UTC).isoformat().replace("+00:00", "Z"),
                "verdict_light": verdict_light,
                "choice_shadowB": shadowB,
                "black_swan_stress": float(black_swan_signal.stress_index),
                "black_swan_flag": bool(black_swan_signal.black_swan),
                "black_swan_precaution": bool(black_swan_signal.precaution),
                "black_swan_reasons": list(black_swan_signal.reasons),
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
                "learner_qa_light": str(learner_qa_light),
                "topk_base": [{"prio": float(p), "raw": r, "sym": s, "grp": g} for (p, r, s, g) in base_topk],
                "topk_final": [{"prio": float(p), "raw": r, "sym": s, "grp": g} for (p, r, s, g) in final_topk],
                "proposals": {},
            }
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)

        cnt = 0
        for prio, raw, sym, grp in candidates:
            if cnt >= n_limit:
                break

            # V1.10: jeśli jest już otwarta pozycja na symbolu, nie otwieraj kolejnej (bez świadomej decyzji).
            if sym in open_syms:
                logging.debug(f"SKIP NEW ENTRY (open position) | {sym}")
                continue

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
            info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
            if info is None:
                logging.warning(f"SYMBOL INFO missing | {sym} | skip")
                cnt += 1
                continue
            try:
                self.strategy.evaluate_symbol(sym, grp, mode, info, self.is_paper)
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                logging.exception("Exception in evaluate_symbol")
                traceback.print_exc()
            cnt += 1

        # Export market snapshot for Scout (no extra MT5 requests; uses cached info/indicators)
        try:
            now_iso = now_utc().isoformat().replace('+00:00','Z')
            topk_for_snapshot = []
            for (p, raw, sym, grp) in candidates[:n_limit]:
                info = self.execution_engine.symbol_info_cached(sym, grp, self.db)
                ind = self.strategy.last_indicators.get(str(raw)) if hasattr(self.strategy, 'last_indicators') else None
                topk_for_snapshot.append({
                    'raw': raw,
                    'sym': sym,
                    'grp': grp,
                    'prio': float(p),
                    'adx': (ind.get('adx') if isinstance(ind, dict) else None),
                    'atr': (ind.get('atr') if isinstance(ind, dict) else None),
                })
            snapshot = {
                'version': '1.0',
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
                'learner_qa_light': (self.strategy._scan_meta.get('learner_qa_light') if hasattr(self.strategy, '_scan_meta') else None),
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

    def run(self):
        logging.info(f"BOT START | MT5 SAFETY BOT {CFG.BOT_VERSION}")

        # --- STARTUP CHECK (jednorazowo): waluta rachunku / stabilność połączenia ---
        try:
            self.execution_engine.ensure_connected()
            acc = self.execution_engine.account_info()
            if acc is not None:
                ccy = str(getattr(acc, "currency", "")).upper()
                if ccy and ccy != "PLN":
                    logging.warning(
                        f"UWAGA WALUTOWA: Konto w {ccy}. Limit ryzyka CFG.max_risk_cap_acct={CFG.max_risk_cap_acct} "
                        f"jest liczony w {ccy}. Jeśli chcesz limit ~50 PLN na koncie {ccy}, ustaw odpowiednią kwotę."
                    )
            else:
                logging.warning("Nie udało się pobrać info o koncie przy starcie (account_info=None).")
        except Exception as e:
            cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
            logging.error(f"Startup Check Error: {e}")

        # --- PĘTLA GŁÓWNA ---
        while True:
            try:
                self.execution_engine.ensure_connected()
                self.scan_once()
                self._idle_sleep_with_usb_watch(CFG.scan_interval_sec)

            except KeyboardInterrupt:
                logging.info("BOT STOP | manual")
                break
            except SystemExit:
                raise
            except Exception as e:
                cg.tlog(None, "WARN", "SB_EXC", "nonfatal exception swallowed", e)
                logging.error(f"MAIN LOOP ERROR | {e}")
                self._idle_sleep_with_usb_watch(60)

if __name__ == "__main__":
    
    # --- Dependency Injection Container ---
    run_mode = get_run_mode()
    runtime_root = get_runtime_root(enforce=True)
    _paths = project_paths(runtime_root)
    
    config = ConfigManager(_paths["config"])
    strategy_cfg = getattr(config, "strategy", {}) or {}

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

    # Required runtime fields (previously declared-only) are now sourced from CONFIG/strategy.json.
    CFG.fixed_sl_points = _cfg_int("fixed_sl_points", CFG.fixed_sl_points)
    CFG.fixed_tp_points = _cfg_int("fixed_tp_points", CFG.fixed_tp_points)
    CFG.atr_period = _cfg_int("atr_period", CFG.atr_period)
    CFG.cooldown_stops_s = _cfg_int("cooldown_stops_s", CFG.cooldown_stops_s)
    CFG.paper_trading = _cfg_bool("paper_trading", CFG.paper_trading)
    CFG.eco_probe_symbols_when_flat = _cfg_int("eco_probe_symbols_when_flat", CFG.eco_probe_symbols_when_flat)
    CFG.sys_budget_day = _cfg_int("sys_budget_day", CFG.sys_budget_day)

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
    )
    bot.run()
