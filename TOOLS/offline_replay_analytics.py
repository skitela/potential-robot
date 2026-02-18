#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sqlite3
import datetime as dt
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

UTC = dt.timezone.utc


def now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def now_utc_iso() -> str:
    return now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_ts_utc(text: str) -> Optional[dt.datetime]:
    if not text:
        return None
    try:
        s = str(text).strip()
        if s.endswith("Z"):
            s = s[:-1] + "+00:00"
        t = dt.datetime.fromisoformat(s)
        if t.tzinfo is None:
            t = t.replace(tzinfo=UTC)
        return t.astimezone(UTC)
    except Exception:
        return None


def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(obj, ensure_ascii=False, indent=2)
    try:
        tmp.write_text(data + "\n", encoding="utf-8")
        tmp.replace(path)
        return
    except Exception:
        path.write_text(data + "\n", encoding="utf-8")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass


def sqlite_connect_ro(db_path: Path) -> sqlite3.Connection:
    uri = f"file:{db_path.as_posix()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    conn.execute("PRAGMA busy_timeout=5000;")
    conn.execute("PRAGMA query_only=ON;")
    return conn


def available_columns(db_path: Path, table: str) -> List[str]:
    if not db_path.exists():
        return []
    conn = sqlite_connect_ro(db_path)
    try:
        rows = conn.execute(f"PRAGMA table_info({table});").fetchall()
        return [str(r[1]) for r in rows]
    finally:
        conn.close()


def fetch_closed_events(db_path: Path, since_iso_utc: str, limit: int) -> List[Dict[str, Any]]:
    if not db_path.exists():
        return []
    cols = available_columns(db_path, "decision_events")
    if not cols:
        return []
    wanted = [
        "outcome_closed_ts_utc",
        "choice_A",
        "price_requests_trade",
        "outcome_pnl_net",
        "outcome_commission",
        "outcome_swap",
        "outcome_fee",
    ]
    selected = [c for c in wanted if c in cols]
    if "outcome_closed_ts_utc" not in selected or "choice_A" not in selected:
        return []

    q = f"""
        SELECT {", ".join(selected)}
        FROM decision_events
        WHERE outcome_closed_ts_utc IS NOT NULL AND outcome_closed_ts_utc != ''
          AND outcome_closed_ts_utc >= ?
        ORDER BY outcome_closed_ts_utc ASC
        LIMIT ?
    """
    conn = sqlite_connect_ro(db_path)
    try:
        rows = conn.execute(q, (since_iso_utc, int(limit))).fetchall()
    finally:
        conn.close()

    out: List[Dict[str, Any]] = []
    for row in rows:
        obj = dict(zip(selected, row))
        out.append(
            {
                "closed_ts_utc": str(obj.get("outcome_closed_ts_utc") or ""),
                "symbol": str(obj.get("choice_A") or "").strip().upper(),
                "reqs_trade": int(obj.get("price_requests_trade") or 0),
                "pnl_net": float(obj.get("outcome_pnl_net") or 0.0),
                "commission": float(obj.get("outcome_commission") or 0.0),
                "swap": float(obj.get("outcome_swap") or 0.0),
                "fee": float(obj.get("outcome_fee") or 0.0),
            }
        )
    return out


def max_drawdown_from_pnl(pnls: List[float]) -> float:
    peak = -1e18
    eq = 0.0
    mdd = 0.0
    for v in pnls:
        eq += float(v)
        peak = max(peak, eq)
        mdd = min(mdd, eq - peak)
    return float(mdd)


def build_replay(rows: List[Dict[str, Any]], window_days: int, ttl_sec: int) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    ts_now = now_utc_iso()
    n = int(len(rows))
    pnl_list: List[float] = []
    reqs_list: List[int] = []
    costs_list: List[float] = []
    per_sym: Dict[str, Dict[str, Any]] = {}
    h = hashlib.sha1()

    eq = 0.0
    peak = 0.0
    mdd = 0.0
    curve_tail: List[Dict[str, Any]] = []
    stride = max(1, n // 200) if n > 0 else 1

    first_ts: Optional[dt.datetime] = None
    last_ts: Optional[dt.datetime] = None

    for i, row in enumerate(rows):
        sym = str(row.get("symbol") or "").strip().upper()
        if not sym:
            continue
        t = parse_ts_utc(str(row.get("closed_ts_utc") or ""))
        if t is not None:
            if first_ts is None:
                first_ts = t
            last_ts = t

        pnl = float(row.get("pnl_net") or 0.0)
        reqs = int(row.get("reqs_trade") or 0)
        cost = abs(float(row.get("commission") or 0.0)) + abs(float(row.get("swap") or 0.0)) + abs(float(row.get("fee") or 0.0))

        pnl_list.append(pnl)
        reqs_list.append(reqs)
        costs_list.append(cost)

        eq += pnl
        peak = max(peak, eq)
        mdd = min(mdd, eq - peak)

        if i % stride == 0 or i == (n - 1):
            curve_tail.append(
                {
                    "i": int(i + 1),
                    "ts_utc": str(row.get("closed_ts_utc") or ""),
                    "equity_delta": round(float(eq), 8),
                }
            )
        if len(curve_tail) > 300:
            curve_tail = curve_tail[-300:]

        h.update(f"{row.get('closed_ts_utc','')}|{sym}|{pnl:.8f}|{reqs}|{cost:.8f}".encode("utf-8", errors="ignore"))

        st = per_sym.setdefault(
            sym,
            {
                "symbol": sym,
                "n": 0,
                "wins": 0,
                "pnl_sum": 0.0,
                "reqs_sum": 0,
                "cost_sum": 0.0,
                "pnls": [],
            },
        )
        st["n"] = int(st["n"]) + 1
        st["wins"] = int(st["wins"]) + (1 if pnl > 0 else 0)
        st["pnl_sum"] = float(st["pnl_sum"]) + pnl
        st["reqs_sum"] = int(st["reqs_sum"]) + reqs
        st["cost_sum"] = float(st["cost_sum"]) + cost
        st["pnls"].append(float(pnl))

    gross_abs = float(sum(abs(x) for x in pnl_list))
    cost_total = float(sum(costs_list))
    cost_pressure = float(cost_total / max(1e-9, gross_abs)) if pnl_list else 0.0
    pnl_sum = float(sum(pnl_list))
    pnl_mean = float(pnl_sum / max(1, len(pnl_list)))
    reqs_mean = float(sum(reqs_list) / max(1, len(reqs_list))) if reqs_list else 0.0

    duration_days = 0.0
    if first_ts is not None and last_ts is not None:
        duration_days = max(0.0, float((last_ts - first_ts).total_seconds()) / 86400.0)
    trades_per_day = float(n / max(1e-9, duration_days)) if duration_days > 0 else float(n)

    symbol_scores: List[Dict[str, Any]] = []
    for sym, st in per_sym.items():
        n_sym = int(st["n"])
        pnl_sym = float(st["pnl_sum"])
        reqs_sym = int(st["reqs_sum"])
        costs_sym = float(st["cost_sum"])
        win_rate = float(int(st["wins"]) / max(1, n_sym))
        mean_pnl = float(pnl_sym / max(1, n_sym))
        edge_req = float(pnl_sym / max(1, reqs_sym))
        cp_sym = float(costs_sym / max(1e-9, abs(pnl_sym))) if n_sym > 0 else 0.0
        replay_score = float(edge_req * (1.0 - min(5.0, cp_sym)))
        dd_sym = max_drawdown_from_pnl([float(x) for x in st.get("pnls", [])])
        symbol_scores.append(
            {
                "symbol": sym,
                "n": n_sym,
                "win_rate": round(win_rate, 6),
                "pnl_sum": round(pnl_sym, 8),
                "pnl_mean": round(mean_pnl, 8),
                "reqs_sum": reqs_sym,
                "edge_req": round(edge_req, 12),
                "cost_pressure": round(cp_sym, 8),
                "max_drawdown": round(float(dd_sym), 8),
                "replay_score": round(replay_score, 12),
            }
        )

    symbol_scores.sort(
        key=lambda d: (float(d.get("replay_score", 0.0)), float(d.get("edge_req", 0.0)), int(d.get("n", 0))),
        reverse=True,
    )

    metrics = {
        "n_total": int(n),
        "pnl_sum": round(pnl_sum, 8),
        "pnl_mean": round(pnl_mean, 8),
        "max_drawdown": round(float(mdd), 8),
        "reqs_mean": round(reqs_mean, 6),
        "cost_total": round(cost_total, 8),
        "cost_pressure": round(cost_pressure, 8),
        "trades_per_day": round(float(trades_per_day), 6),
        "deterministic_hash": h.hexdigest(),
    }

    summary = {
        "schema": "oanda_mt5.offline_replay.v1",
        "ts_utc": ts_now,
        "ttl_sec": int(ttl_sec),
        "window_days": int(window_days),
        "metrics": metrics,
        "symbol_scores": symbol_scores[:100],
        "notes": ["mode=offline", "source=decision_events", "method=deterministic_replay"],
    }

    report = {
        "schema": "oanda_mt5.offline_replay.report.v1",
        "ts_utc": ts_now,
        "window_days": int(window_days),
        "metrics": metrics,
        "curve_tail": curve_tail,
        "symbol_scores": symbol_scores,
    }
    return summary, report


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministic offline replay analytics from decision_events.sqlite")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--window-days", type=int, default=180)
    parser.add_argument("--row-limit", type=int, default=20000)
    parser.add_argument("--ttl-sec", type=int, default=5400)
    args = parser.parse_args()

    root = Path(args.root).resolve()
    db = root / "DB" / "decision_events.sqlite"
    meta = root / "META"
    logs = root / "LOGS"
    evid = root / "EVIDENCE" / "offline_replay"
    meta.mkdir(parents=True, exist_ok=True)
    logs.mkdir(parents=True, exist_ok=True)
    evid.mkdir(parents=True, exist_ok=True)

    now_ts = now_utc()
    since = (now_ts - dt.timedelta(days=max(1, int(args.window_days)))).replace(microsecond=0)
    since_iso = since.isoformat().replace("+00:00", "Z")

    rows = fetch_closed_events(db, since_iso_utc=since_iso, limit=max(1, int(args.row_limit)))
    summary, report = build_replay(rows, window_days=max(1, int(args.window_days)), ttl_sec=max(60, int(args.ttl_sec)))
    report["source_rows"] = int(len(rows))
    report["db_path"] = str(db)
    report["since_iso_utc"] = since_iso

    atomic_write_json(meta / "offline_replay_summary.json", summary)
    atomic_write_json(logs / "offline_replay_report.json", report)

    run_id = now_ts.strftime("%Y%m%dT%H%M%SZ")
    atomic_write_json(evid / f"{run_id}_offline_replay_report.json", report)

    print(
        f"OFFLINE_REPLAY_OK n={summary.get('metrics', {}).get('n_total', 0)} "
        f"hash={summary.get('metrics', {}).get('deterministic_hash', '')[:12]}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
