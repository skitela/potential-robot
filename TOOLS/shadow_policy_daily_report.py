#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import sqlite3
from collections import defaultdict
from dataclasses import dataclass
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from zoneinfo import ZoneInfo

UTC = dt.timezone.utc


@dataclass(frozen=True)
class ReplayOutcome:
    exit_reason: str
    gross_pips: float
    cost_pips: float
    net_pips: float


def now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_ts_utc(text: Any) -> Optional[dt.datetime]:
    if text is None:
        return None
    s = str(text).strip()
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(payload, ensure_ascii=False, indent=2)
    try:
        tmp.write_text(data + "\n", encoding="utf-8")
        tmp.replace(path)
    except Exception:
        path.write_text(data + "\n", encoding="utf-8")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def sqlite_connect(path: Path) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=10000;")
    return conn


def infer_point_and_pip(entry_price: float) -> Tuple[float, float]:
    d = Decimal(str(entry_price)).normalize()
    exp = int(d.as_tuple().exponent)
    decimals = -exp if exp < 0 else 0
    point = (10.0 ** -decimals) if decimals > 0 else 1.0
    pip = point * 10.0 if decimals in (3, 5) else point
    return float(point), float(pip)


def replay_one_trade(
    *,
    conn_bars: sqlite3.Connection,
    symbol: str,
    ts_open: dt.datetime,
    signal: str,
    entry_price: float,
    sl: float,
    tp: float,
    spread_points: float,
    horizon_minutes: int,
) -> ReplayOutcome:
    t1 = ts_open.astimezone(UTC).replace(microsecond=0)
    t2 = t1 + dt.timedelta(minutes=max(1, int(horizon_minutes)))
    rows = conn_bars.execute(
        """
        SELECT t_utc, h, l, c
        FROM m5_bars
        WHERE symbol = ?
          AND t_utc >= ?
          AND t_utc <= ?
        ORDER BY t_utc ASC
        """,
        [symbol, t1.strftime("%Y-%m-%dT%H:%M:%SZ"), t2.strftime("%Y-%m-%dT%H:%M:%SZ")],
    ).fetchall()

    point, pip = infer_point_and_pip(float(entry_price))
    cost_pips = (float(spread_points) * point / pip) if pip > 0.0 else 0.0
    side = str(signal or "").upper()

    if not rows:
        return ReplayOutcome(exit_reason="NO_DATA", gross_pips=0.0, cost_pips=cost_pips, net_pips=-cost_pips)

    exit_reason = "TIME_EXIT"
    exit_price = float(rows[-1]["c"] if rows[-1]["c"] is not None else entry_price)

    for row in rows:
        high = row["h"]
        low = row["l"]
        if high is None or low is None:
            continue
        h = float(high)
        l = float(low)
        if side == "BUY":
            tp_hit = h >= float(tp)
            sl_hit = l <= float(sl)
            if tp_hit and sl_hit:
                exit_price = float(sl)
                exit_reason = "AMBIGUOUS_WORST_SL"
                break
            if tp_hit:
                exit_price = float(tp)
                exit_reason = "TP_HIT"
                break
            if sl_hit:
                exit_price = float(sl)
                exit_reason = "SL_HIT"
                break
        else:
            tp_hit = l <= float(tp)
            sl_hit = h >= float(sl)
            if tp_hit and sl_hit:
                exit_price = float(sl)
                exit_reason = "AMBIGUOUS_WORST_SL"
                break
            if tp_hit:
                exit_price = float(tp)
                exit_reason = "TP_HIT"
                break
            if sl_hit:
                exit_price = float(sl)
                exit_reason = "SL_HIT"
                break

    if side == "BUY":
        gross_pips = (float(exit_price) - float(entry_price)) / pip if pip > 0.0 else 0.0
    else:
        gross_pips = (float(entry_price) - float(exit_price)) / pip if pip > 0.0 else 0.0
    net_pips = gross_pips - cost_pips
    return ReplayOutcome(exit_reason=exit_reason, gross_pips=float(gross_pips), cost_pips=cost_pips, net_pips=float(net_pips))


def read_scope_config(strategy_cfg: Dict[str, Any]) -> Dict[str, Any]:
    raw_windows = strategy_cfg.get("trade_windows") or {}
    window_defs: Dict[str, Dict[str, Any]] = {}
    for wid, cfg in raw_windows.items():
        if not isinstance(cfg, dict):
            continue
        sh = cfg.get("start_hm") or [0, 0]
        eh = cfg.get("end_hm") or [0, 0]
        try:
            start_h = int(sh[0])
            start_m = int(sh[1])
            end_h = int(eh[0])
            end_m = int(eh[1])
        except Exception:
            continue
        window_defs[str(wid).upper()] = {
            "group": str(cfg.get("group") or "").upper(),
            "anchor_tz": str(cfg.get("anchor_tz") or "UTC"),
            "start_h": start_h,
            "start_m": start_m,
            "end_h": end_h,
            "end_m": end_m,
        }

    return {
        "symbols_to_trade": set(str(x).upper() for x in (strategy_cfg.get("symbols_to_trade") or [])),
        "allowed_groups": set(str(x).upper() for x in (strategy_cfg.get("symbol_policy_allowed_groups") or [])),
        "hard_disabled_groups": set(str(x).upper() for x in (strategy_cfg.get("hard_live_disabled_groups") or [])),
        "hard_disabled_symbols": set(str(x).upper() for x in (strategy_cfg.get("hard_live_disabled_symbol_intents") or [])),
        "trade_windows": set(str(x).upper() for x in (strategy_cfg.get("trade_windows") or {}).keys()),
        "window_symbol_intents": {
            str(k).upper(): set(str(s).upper() for s in (v or []))
            for k, v in (strategy_cfg.get("trade_window_symbol_intents") or {}).items()
        },
        "window_defs": window_defs,
        "live_canary_enabled": bool(strategy_cfg.get("live_canary_enabled")),
        "live_canary_allowed_groups": set(str(x).upper() for x in (strategy_cfg.get("live_canary_allowed_groups") or [])),
        "live_canary_allowed_symbols": set(str(x).upper() for x in (strategy_cfg.get("live_canary_allowed_symbol_intents") or [])),
    }


def _window_active(ts_utc: dt.datetime, win: Dict[str, Any]) -> bool:
    try:
        tz = ZoneInfo(str(win.get("anchor_tz") or "UTC"))
    except Exception:
        tz = ZoneInfo("UTC")
    local = ts_utc.astimezone(tz)
    cur_min = int(local.hour * 60 + local.minute)
    start_min = int(win.get("start_h", 0) * 60 + win.get("start_m", 0))
    end_min = int(win.get("end_h", 0) * 60 + win.get("end_m", 0))
    if start_min == end_min:
        return True
    if start_min < end_min:
        return start_min <= cur_min < end_min
    return cur_min >= start_min or cur_min < end_min


def derive_scope_if_missing(
    *,
    ts_utc: dt.datetime,
    symbol: str,
    window_id: str,
    group_name: str,
    scope_cfg: Dict[str, Any],
) -> Tuple[str, str, str]:
    wid = str(window_id or "").upper()
    grp = str(group_name or "").upper()
    if wid and grp:
        return wid, grp, "ORIGINAL"

    sym = str(symbol or "").upper()
    intents = scope_cfg.get("window_symbol_intents") or {}
    defs = scope_cfg.get("window_defs") or {}
    candidates: List[Tuple[str, str]] = []
    for candidate_wid, candidate_def in defs.items():
        sym_intents = intents.get(candidate_wid)
        if sym_intents and sym not in sym_intents:
            continue
        if _window_active(ts_utc, candidate_def):
            candidate_grp = str(candidate_def.get("group") or "").upper()
            if candidate_grp:
                candidates.append((candidate_wid, candidate_grp))

    if not candidates:
        return wid, grp, "NONE"
    if len(candidates) == 1:
        return candidates[0][0], candidates[0][1], "DERIVED_SINGLE"
    candidates.sort()
    return candidates[0][0], candidates[0][1], "DERIVED_MULTI_FIRST"


def evaluate_policy_scope(
    *,
    symbol: str,
    group_name: str,
    window_id: str,
    scope_cfg: Dict[str, Any],
    mode: str,
    relax_reasons: set[str],
) -> Tuple[bool, str]:
    sym = str(symbol or "").upper()
    grp = str(group_name or "").upper()
    wid = str(window_id or "").upper()

    if not sym or not grp or not wid:
        reason = "MISSING_SCOPE"
    elif sym not in scope_cfg["symbols_to_trade"]:
        reason = "SYMBOL_NOT_IN_SCOPE"
    elif grp not in scope_cfg["allowed_groups"]:
        reason = "GROUP_NOT_ALLOWED"
    elif wid not in scope_cfg["trade_windows"]:
        reason = "WINDOW_NOT_CONFIGURED"
    elif grp in scope_cfg["hard_disabled_groups"]:
        reason = "GROUP_HARD_DISABLED"
    elif sym in scope_cfg["hard_disabled_symbols"]:
        reason = "SYMBOL_HARD_DISABLED"
    else:
        intents = scope_cfg["window_symbol_intents"].get(wid)
        if intents and sym not in intents:
            reason = "SYMBOL_NOT_IN_WINDOW_INTENT"
        elif scope_cfg["live_canary_enabled"] and grp not in scope_cfg["live_canary_allowed_groups"]:
            reason = "CANARY_GROUP_BLOCK"
        elif scope_cfg["live_canary_enabled"] and sym not in scope_cfg["live_canary_allowed_symbols"]:
            reason = "CANARY_SYMBOL_BLOCK"
        else:
            return True, "OK"

    if str(mode).upper() == "EXPLORE" and reason in relax_reasons:
        return True, f"RELAXED_{reason}"
    return False, reason


def update_bucket(
    buckets: Dict[Tuple[str, str, str], Dict[str, Any]],
    key: Tuple[str, str, str],
    outcome: ReplayOutcome,
    recorded_pnl_net: Optional[float],
    eligibility_reason: str,
) -> None:
    b = buckets.setdefault(
        key,
        {
            "trades": 0,
            "wins": 0,
            "losses": 0,
            "flat": 0,
            "tp_hits": 0,
            "sl_hits": 0,
            "time_exits": 0,
            "no_data": 0,
            "ambiguous_worst_sl": 0,
            "gross_pips_sum": 0.0,
            "cost_pips_sum": 0.0,
            "net_pips_sum": 0.0,
            "recorded_pnl_sum": 0.0,
            "recorded_pnl_nonnull": 0,
            "eligibility_reasons": defaultdict(int),
        },
    )
    b["trades"] += 1
    if outcome.net_pips > 1e-12:
        b["wins"] += 1
    elif outcome.net_pips < -1e-12:
        b["losses"] += 1
    else:
        b["flat"] += 1

    if outcome.exit_reason == "TP_HIT":
        b["tp_hits"] += 1
    elif outcome.exit_reason == "SL_HIT":
        b["sl_hits"] += 1
    elif outcome.exit_reason == "TIME_EXIT":
        b["time_exits"] += 1
    elif outcome.exit_reason == "NO_DATA":
        b["no_data"] += 1
    elif outcome.exit_reason == "AMBIGUOUS_WORST_SL":
        b["ambiguous_worst_sl"] += 1

    b["gross_pips_sum"] += float(outcome.gross_pips)
    b["cost_pips_sum"] += float(outcome.cost_pips)
    b["net_pips_sum"] += float(outcome.net_pips)
    if recorded_pnl_net is not None:
        b["recorded_pnl_nonnull"] += 1
        b["recorded_pnl_sum"] += float(recorded_pnl_net)
    b["eligibility_reasons"][str(eligibility_reason)] += 1


def finalize_buckets(buckets: Dict[Tuple[str, str, str], Dict[str, Any]]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for (day, window_id, symbol), b in sorted(buckets.items()):
        n = int(b["trades"])
        out.append(
            {
                "date_utc": day,
                "window_id": window_id,
                "symbol": symbol,
                "trades": n,
                "wins": int(b["wins"]),
                "losses": int(b["losses"]),
                "flat": int(b["flat"]),
                "win_rate": round((float(b["wins"]) / n) if n else 0.0, 4),
                "tp_hits": int(b["tp_hits"]),
                "sl_hits": int(b["sl_hits"]),
                "time_exits": int(b["time_exits"]),
                "no_data": int(b["no_data"]),
                "ambiguous_worst_sl": int(b["ambiguous_worst_sl"]),
                "gross_pips_sum": round(float(b["gross_pips_sum"]), 2),
                "cost_pips_sum": round(float(b["cost_pips_sum"]), 2),
                "net_pips_sum": round(float(b["net_pips_sum"]), 2),
                "net_pips_per_trade": round(float(b["net_pips_sum"]) / n, 3) if n else 0.0,
                "recorded_pnl_sum": round(float(b["recorded_pnl_sum"]), 5),
                "recorded_pnl_nonnull": int(b["recorded_pnl_nonnull"]),
                "eligibility_reasons": dict(sorted(b["eligibility_reasons"].items(), key=lambda kv: kv[1], reverse=True)),
            }
        )
    return out


def aggregate_by_window_symbol(rows: Iterable[Dict[str, Any]]) -> Dict[Tuple[str, str], Dict[str, float]]:
    agg: Dict[Tuple[str, str], Dict[str, float]] = {}
    for row in rows:
        key = (str(row.get("window_id") or "NONE"), str(row.get("symbol") or "UNKNOWN"))
        st = agg.setdefault(
            key,
            {
                "trades": 0.0,
                "wins": 0.0,
                "losses": 0.0,
                "net_pips_sum": 0.0,
                "cost_pips_sum": 0.0,
            },
        )
        st["trades"] += float(row.get("trades") or 0.0)
        st["wins"] += float(row.get("wins") or 0.0)
        st["losses"] += float(row.get("losses") or 0.0)
        st["net_pips_sum"] += float(row.get("net_pips_sum") or 0.0)
        st["cost_pips_sum"] += float(row.get("cost_pips_sum") or 0.0)
    return agg


def recommendation_for_tomorrow(
    *,
    strict_rows: List[Dict[str, Any]],
    explore_rows: List[Dict[str, Any]],
    min_sample: int,
    poluzuj_threshold: float,
    docisnij_threshold: float,
    improvement_margin: float,
) -> List[Dict[str, Any]]:
    strict_agg = aggregate_by_window_symbol(strict_rows)
    explore_agg = aggregate_by_window_symbol(explore_rows)
    keys = sorted(set(strict_agg.keys()) | set(explore_agg.keys()))
    out: List[Dict[str, Any]] = []

    for key in keys:
        window_id, symbol = key
        s = strict_agg.get(key, {"trades": 0.0, "wins": 0.0, "losses": 0.0, "net_pips_sum": 0.0, "cost_pips_sum": 0.0})
        e = explore_agg.get(key, {"trades": 0.0, "wins": 0.0, "losses": 0.0, "net_pips_sum": 0.0, "cost_pips_sum": 0.0})

        s_n = int(s["trades"])
        e_n = int(e["trades"])
        s_wr = (float(s["wins"]) / s_n) if s_n else 0.0
        e_wr = (float(e["wins"]) / e_n) if e_n else 0.0
        s_net_pt = (float(s["net_pips_sum"]) / s_n) if s_n else 0.0
        e_net_pt = (float(e["net_pips_sum"]) / e_n) if e_n else 0.0

        action = "TRZYMAJ"
        reason = "NO_CLEAR_EDGE"
        if e_n < int(min_sample):
            action = "TRZYMAJ"
            reason = "LOW_SAMPLE"
        elif e_net_pt <= float(docisnij_threshold) or e_wr < 0.35:
            action = "DOCIŚNIJ"
            reason = "NEGATIVE_EDGE_EXPLORE"
        elif s_n == 0 and e_net_pt >= float(poluzuj_threshold) and e_wr >= 0.45:
            action = "POLUZUJ"
            reason = "STRICT_ZERO_EXPLORE_POSITIVE"
        elif s_n >= int(min_sample) and s_net_pt <= float(docisnij_threshold) and e_net_pt >= (s_net_pt + float(improvement_margin)):
            action = "POLUZUJ"
            reason = "STRICT_UNDERPERFORMS_EXPLORE"
        elif s_n >= int(min_sample) and s_net_pt >= float(poluzuj_threshold) and s_wr >= 0.45:
            action = "TRZYMAJ"
            reason = "STRICT_WORKS"

        n_max = max(s_n, e_n)
        confidence = "LOW"
        if n_max >= 30:
            confidence = "HIGH"
        elif n_max >= 10:
            confidence = "MEDIUM"

        out.append(
            {
                "window_id": window_id,
                "symbol": symbol,
                "action_tomorrow": action,
                "reason_code": reason,
                "confidence": confidence,
                "strict": {
                    "trades": s_n,
                    "win_rate": round(s_wr, 4),
                    "net_pips_per_trade": round(s_net_pt, 3),
                    "net_pips_sum": round(float(s["net_pips_sum"]), 2),
                },
                "explore": {
                    "trades": e_n,
                    "win_rate": round(e_wr, 4),
                    "net_pips_per_trade": round(e_net_pt, 3),
                    "net_pips_sum": round(float(e["net_pips_sum"]), 2),
                },
            }
        )

    out.sort(
        key=lambda r: (
            {"DOCIŚNIJ": 0, "TRZYMAJ": 1, "POLUZUJ": 2}.get(str(r.get("action_tomorrow")), 9),
            str(r.get("window_id")),
            str(r.get("symbol")),
        )
    )
    return out


def should_skip_daily(state_path: Path, now: dt.datetime) -> bool:
    if not state_path.exists():
        return False
    try:
        payload = load_json(state_path)
    except Exception:
        return False
    last = parse_ts_utc(payload.get("last_run_ts_utc"))
    return bool(last is not None and last.date() == now.date())


def update_daily_state(state_path: Path, now: dt.datetime, status: str, report_path: Path) -> None:
    write_json(
        state_path,
        {
            "last_run_ts_utc": iso_utc(now),
            "last_status": status,
            "last_report_path": str(report_path),
        },
    )


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Daily strict/explore shadow policy replay report (per symbol, per window).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--strategy-path", default="")
    ap.add_argument("--db-events", default="")
    ap.add_argument("--db-bars", default="")
    ap.add_argument("--lookback-days", type=int, default=3)
    ap.add_argument("--start-date", default="", help="Optional UTC date YYYY-MM-DD (inclusive).")
    ap.add_argument("--end-date", default="", help="Optional UTC date YYYY-MM-DD (exclusive).")
    ap.add_argument("--horizon-minutes", type=int, default=60)
    ap.add_argument("--daily-guard", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--out", default="")
    ap.add_argument("--state-file", default="RUN/shadow_policy_daily_state.json")
    ap.add_argument("--min-sample", type=int, default=8)
    ap.add_argument("--poluzuj-threshold-pips-per-trade", type=float, default=0.5)
    ap.add_argument("--docisnij-threshold-pips-per-trade", type=float, default=-1.5)
    ap.add_argument("--improvement-margin-pips", type=float, default=0.75)
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    now = now_utc()
    state_path = (root / str(args.state_file)).resolve()

    if bool(args.daily_guard) and not bool(args.force) and should_skip_daily(state_path, now):
        out_path = Path(args.out).resolve() if args.out else (root / "EVIDENCE" / "offline_replay" / "daily" / f"shadow_policy_daily_report_{now.strftime('%Y%m%dT%H%M%SZ')}.json")
        payload = {
            "schema": "oanda_mt5.shadow_policy_daily_report.v1",
            "status": "SKIP_ALREADY_RUN_TODAY",
            "generated_at_utc": iso_utc(now),
            "root": str(root),
            "daily_guard": True,
        }
        write_json(out_path, payload)
        print(f"SHADOW_POLICY_DAILY_REPORT_OK status={payload['status']} out={out_path}")
        return 0

    strategy_path = Path(args.strategy_path).resolve() if str(args.strategy_path).strip() else (root / "CONFIG" / "strategy.json")
    db_events = Path(args.db_events).resolve() if str(args.db_events).strip() else (root / "DB" / "decision_events.sqlite")
    db_bars = Path(args.db_bars).resolve() if str(args.db_bars).strip() else (root / "DB" / "m5_bars.sqlite")
    if not strategy_path.exists():
        raise FileNotFoundError(f"Missing strategy config: {strategy_path}")
    if not db_events.exists():
        raise FileNotFoundError(f"Missing DB: {db_events}")
    if not db_bars.exists():
        raise FileNotFoundError(f"Missing DB: {db_bars}")

    strategy_cfg = load_json(strategy_path)
    scope_cfg = read_scope_config(strategy_cfg)

    def _parse_date(raw: str) -> Optional[dt.date]:
        s = str(raw or "").strip()
        if not s:
            return None
        try:
            return dt.date.fromisoformat(s)
        except Exception:
            return None

    start_arg = _parse_date(str(args.start_date))
    end_arg = _parse_date(str(args.end_date))
    if start_arg is not None and end_arg is not None:
        if start_arg >= end_arg:
            raise ValueError("--start-date must be < --end-date")
        start_date = start_arg
        end_date = end_arg
    else:
        end_date = now.date()  # exclusive to avoid partial current day.
        start_date = end_date - dt.timedelta(days=max(1, int(args.lookback_days)))
    start_iso = dt.datetime.combine(start_date, dt.time.min, tzinfo=UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    end_iso = dt.datetime.combine(end_date, dt.time.min, tzinfo=UTC).strftime("%Y-%m-%dT%H:%M:%SZ")

    conn_e = sqlite_connect(db_events)
    conn_b = sqlite_connect(db_bars)
    try:
        rows = conn_e.execute(
            """
            SELECT
                ts_utc,
                choice_A,
                signal,
                entry_price,
                sl,
                tp,
                spread_points,
                outcome_pnl_net,
                grp,
                window_group,
                window_id
            FROM decision_events
            WHERE ts_utc >= ?
              AND ts_utc < ?
              AND signal IN ('BUY', 'SELL')
            ORDER BY ts_utc ASC
            """,
            [start_iso, end_iso],
        ).fetchall()

        strict_buckets: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
        explore_buckets: Dict[Tuple[str, str, str], Dict[str, Any]] = {}
        strict_reason_counts: Dict[str, int] = defaultdict(int)
        explore_reason_counts: Dict[str, int] = defaultdict(int)
        quality = {
            "events_total": 0,
            "events_replayed": 0,
            "events_missing_scope": 0,
            "events_scope_derived_single": 0,
            "events_scope_derived_multi_first": 0,
            "events_missing_prices": 0,
            "events_no_bars_in_horizon": 0,
            "events_ambiguous_worst_sl": 0,
        }

        relax_reasons = {
            "CANARY_GROUP_BLOCK",
            "CANARY_SYMBOL_BLOCK",
            "SYMBOL_NOT_IN_WINDOW_INTENT",
            "GROUP_HARD_DISABLED",
            "SYMBOL_HARD_DISABLED",
        }

        for row in rows:
            quality["events_total"] += 1
            ts = parse_ts_utc(row["ts_utc"])
            symbol = str(row["choice_A"] or "").upper()
            signal = str(row["signal"] or "").upper()
            raw_window_id = str(row["window_id"] or "").upper()
            raw_group_name = str((row["window_group"] or row["grp"] or "")).upper()
            day = ts.date().isoformat() if ts else "UNKNOWN"

            entry_price = row["entry_price"]
            sl = row["sl"]
            tp = row["tp"]
            spread_points = float(row["spread_points"] or 0.0)
            if ts is None or entry_price is None or sl is None or tp is None or not symbol or not signal:
                quality["events_missing_prices"] += 1
                continue

            outcome = replay_one_trade(
                conn_bars=conn_b,
                symbol=symbol,
                ts_open=ts,
                signal=signal,
                entry_price=float(entry_price),
                sl=float(sl),
                tp=float(tp),
                spread_points=spread_points,
                horizon_minutes=max(1, int(args.horizon_minutes)),
            )
            quality["events_replayed"] += 1
            if outcome.exit_reason == "NO_DATA":
                quality["events_no_bars_in_horizon"] += 1
            if outcome.exit_reason == "AMBIGUOUS_WORST_SL":
                quality["events_ambiguous_worst_sl"] += 1

            window_id, group_name, scope_origin = derive_scope_if_missing(
                ts_utc=ts,
                symbol=symbol,
                window_id=raw_window_id,
                group_name=raw_group_name,
                scope_cfg=scope_cfg,
            )
            if scope_origin == "DERIVED_SINGLE":
                quality["events_scope_derived_single"] += 1
            elif scope_origin == "DERIVED_MULTI_FIRST":
                quality["events_scope_derived_multi_first"] += 1

            s_ok, s_reason = evaluate_policy_scope(
                symbol=symbol,
                group_name=group_name,
                window_id=window_id,
                scope_cfg=scope_cfg,
                mode="STRICT",
                relax_reasons=relax_reasons,
            )
            e_ok, e_reason = evaluate_policy_scope(
                symbol=symbol,
                group_name=group_name,
                window_id=window_id,
                scope_cfg=scope_cfg,
                mode="EXPLORE",
                relax_reasons=relax_reasons,
            )
            if s_reason == "MISSING_SCOPE":
                quality["events_missing_scope"] += 1
            strict_reason_counts[s_reason] += 1
            explore_reason_counts[e_reason] += 1

            key = (day, window_id, symbol)
            recorded_pnl_net = None if row["outcome_pnl_net"] is None else float(row["outcome_pnl_net"])
            if s_ok:
                update_bucket(strict_buckets, key, outcome, recorded_pnl_net, s_reason)
            if e_ok:
                update_bucket(explore_buckets, key, outcome, recorded_pnl_net, e_reason)

        strict_rows = finalize_buckets(strict_buckets)
        explore_rows = finalize_buckets(explore_buckets)

        recs = recommendation_for_tomorrow(
            strict_rows=strict_rows,
            explore_rows=explore_rows,
            min_sample=max(1, int(args.min_sample)),
            poluzuj_threshold=float(args.poluzuj_threshold_pips_per_trade),
            docisnij_threshold=float(args.docisnij_threshold_pips_per_trade),
            improvement_margin=float(args.improvement_margin_pips),
        )

        strict_trades = int(sum(int(r["trades"]) for r in strict_rows))
        explore_trades = int(sum(int(r["trades"]) for r in explore_rows))

        def summary(rows_in: List[Dict[str, Any]]) -> Dict[str, Any]:
            n = int(sum(int(r["trades"]) for r in rows_in))
            wins = int(sum(int(r["wins"]) for r in rows_in))
            losses = int(sum(int(r["losses"]) for r in rows_in))
            net_sum = float(sum(float(r["net_pips_sum"]) for r in rows_in))
            cost_sum = float(sum(float(r["cost_pips_sum"]) for r in rows_in))
            return {
                "trades": n,
                "wins": wins,
                "losses": losses,
                "win_rate": round((wins / n) if n else 0.0, 4),
                "net_pips_sum": round(net_sum, 2),
                "net_pips_per_trade": round((net_sum / n) if n else 0.0, 3),
                "cost_pips_sum": round(cost_sum, 2),
            }

        summary_strict = summary(strict_rows)
        summary_explore = summary(explore_rows)

        report = {
            "schema": "oanda_mt5.shadow_policy_daily_report.v1",
            "status": "PASS",
            "generated_at_utc": iso_utc(now),
            "root": str(root),
            "range_utc": {"start": start_iso, "end_exclusive": end_iso},
            "days_included": [str(start_date + dt.timedelta(days=i)) for i in range(max(1, int(args.lookback_days)))],
            "replay_method": {
                "name": "m5_bar_replay_tp_sl_60m",
                "horizon_minutes": int(args.horizon_minutes),
                "same_bar_tp_sl_rule": "worst_case_sl",
                "cost_model": "spread_points_to_pips_only",
            },
            "policy_modes": {
                "strict": "current_policy_all_scope_checks",
                "explore": "strict_plus_relax_specific_scope_blocks_only",
                "explore_relax_reasons": sorted(relax_reasons),
            },
            "quality": quality,
            "population": {
                "events_total": int(len(rows)),
                "strict_trades_included": strict_trades,
                "explore_trades_included": explore_trades,
                "strict_reason_counts": dict(sorted(strict_reason_counts.items(), key=lambda kv: kv[1], reverse=True)),
                "explore_reason_counts": dict(sorted(explore_reason_counts.items(), key=lambda kv: kv[1], reverse=True)),
            },
            "summary": {
                "strict": summary_strict,
                "explore": summary_explore,
                "delta_explore_minus_strict_net_pips": round(
                    float(summary_explore["net_pips_sum"]) - float(summary_strict["net_pips_sum"]), 2
                ),
                "delta_explore_minus_strict_trades": int(summary_explore["trades"]) - int(summary_strict["trades"]),
            },
            "results_per_day_window_symbol": {
                "strict": strict_rows,
                "explore": explore_rows,
            },
            "recommendations_tomorrow_per_window_symbol": recs,
            "thresholds": {
                "min_sample": int(args.min_sample),
                "poluzuj_threshold_pips_per_trade": float(args.poluzuj_threshold_pips_per_trade),
                "docisnij_threshold_pips_per_trade": float(args.docisnij_threshold_pips_per_trade),
                "improvement_margin_pips": float(args.improvement_margin_pips),
            },
            "notes": [
                "Shadow analytics only; no runtime strategy mutation performed.",
                "Financial account-currency PnL remains dependent on recorded outcome fields; this report is pip-model replay.",
            ],
        }

        out_path = Path(args.out).resolve() if args.out else (root / "EVIDENCE" / "offline_replay" / "daily" / f"shadow_policy_daily_report_{now.strftime('%Y%m%dT%H%M%SZ')}.json")
        write_json(out_path, report)

        txt_lines: List[str] = []
        txt_lines.append("SHADOW_POLICY_DAILY_REPORT")
        txt_lines.append(f"Generated UTC: {report['generated_at_utc']}")
        txt_lines.append(f"Range UTC: {start_iso} -> {end_iso}")
        txt_lines.append("")
        txt_lines.append("SUMMARY_STRICT")
        for k, v in summary_strict.items():
            txt_lines.append(f"- {k}: {v}")
        txt_lines.append("")
        txt_lines.append("SUMMARY_EXPLORE")
        for k, v in summary_explore.items():
            txt_lines.append(f"- {k}: {v}")
        txt_lines.append("")
        txt_lines.append("TOP_RECOMMENDATIONS")
        for r in recs[:50]:
            txt_lines.append(
                f"- {r['window_id']}|{r['symbol']} => {r['action_tomorrow']} ({r['reason_code']}, conf={r['confidence']}, "
                f"strict_n={r['strict']['trades']}, explore_n={r['explore']['trades']})"
            )
        txt_path = out_path.with_suffix(".txt")
        txt_path.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

        update_daily_state(state_path, now, "PASS", out_path)
        print(
            "SHADOW_POLICY_DAILY_REPORT_OK status=PASS strict_trades={0} explore_trades={1} out={2}".format(
                strict_trades,
                explore_trades,
                str(out_path),
            )
        )
        return 0
    finally:
        conn_e.close()
        conn_b.close()


if __name__ == "__main__":
    raise SystemExit(main())
