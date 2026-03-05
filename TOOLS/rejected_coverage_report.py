#!/usr/bin/env python3
"""
Generate per-instrument coverage report for rejected setup candidates.

Inputs:
- DB/decision_events.sqlite
- decision_rejections table (new skip-capture feed)
- decision_events table (trade-path feed)

Outputs:
- EVIDENCE/learning_coverage/rejected_coverage_<ts>.json
- EVIDENCE/learning_coverage/rejected_coverage_<ts>.txt
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso_z(dt_obj: datetime) -> str:
    return dt_obj.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _symbol_base(sym: str) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def _load_expected_symbols(root: Path) -> List[str]:
    cfg_path = root / "CONFIG" / "strategy.json"
    try:
        obj = json.loads(cfg_path.read_text(encoding="utf-8"))
        raw = obj.get("symbols_to_trade")
        if isinstance(raw, list):
            out = sorted({_symbol_base(str(x)) for x in raw if str(x).strip()})
            return [s for s in out if s]
    except Exception as exc:
        _ = exc
    return []


def _query_rows(conn: sqlite3.Connection, sql: str, params: Tuple[Any, ...]) -> Iterable[sqlite3.Row]:
    cur = conn.execute(sql, params)
    for row in cur.fetchall():
        yield row


def _reason_reco(reason_counts: Counter) -> str:
    if not reason_counts:
        return "Brak odrzucen; sprawdz, czy instrument byl aktywnie skanowany."
    top_reason, top_count = reason_counts.most_common(1)[0]
    top_reason_u = str(top_reason or "").upper()
    if "SPREAD" in top_reason_u or "COST" in top_reason_u:
        return f"Dominuja odrzucenia kosztowe ({top_reason}, n={top_count}); sprawdz spread gate i okno sesyjne."
    if "DATA" in top_reason_u or "TICK" in top_reason_u or "M5_" in top_reason_u:
        return f"Dominuja odrzucenia danych ({top_reason}, n={top_count}); popraw jakosc/ciaglosc feedu."
    if "RISK" in top_reason_u or "LOSS" in top_reason_u:
        return f"Dominuja odrzucenia risk-guard ({top_reason}, n={top_count}); to normalne przy ochronie kapitalu."
    if "NO_SIGNAL" in top_reason_u or "TREND" in top_reason_u:
        return f"Dominuja odrzucenia sygnalu ({top_reason}, n={top_count}); rynek byl bez czystych setupow."
    return f"Najczestszy powod odrzucenia: {top_reason} (n={top_count})."


_ENTRY_SKIP_RE = re.compile(
    r"ENTRY_SKIP(?:_PRE)?\s+symbol=(?P<symbol>\S+)\s+grp=(?P<grp>\S+)\s+mode=(?P<mode>\S+)\s+reason=(?P<reason>[A-Z0-9_]+)"
)


def _classify_reason(reason: str) -> str:
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


def _backfill_from_log(
    root: Path,
    rej_by_symbol: Dict[str, int],
    rej_reason_by_symbol: Dict[str, Counter],
    rej_class_by_symbol: Dict[str, Counter],
) -> int:
    # Fallback when runtime has not restarted yet with decision_rejections enabled.
    log_path = root / "LOGS" / "safetybot.log"
    if not log_path.exists():
        return 0
    added = 0
    try:
        for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = _ENTRY_SKIP_RE.search(line)
            if not m:
                continue
            sym = _symbol_base(m.group("symbol"))
            reason = str(m.group("reason") or "UNKNOWN").upper()
            if not sym:
                continue
            added += 1
            rej_by_symbol[sym] += 1
            rej_reason_by_symbol[sym][reason] += 1
            rej_class_by_symbol[sym][_classify_reason(reason)] += 1
    except Exception:
        return 0
    return added


def _main() -> int:
    ap = argparse.ArgumentParser(description="Per-instrument rejected setup coverage report.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM")
    ap.add_argument("--lookback-hours", type=int, default=24)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-txt", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    db_path = root / "DB" / "decision_events.sqlite"
    if not db_path.exists():
        raise SystemExit(f"DB missing: {db_path}")

    expected = _load_expected_symbols(root)
    since = _utc_now() - timedelta(hours=max(1, int(args.lookback_hours)))
    since_iso = _iso_z(since)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        # Table may not exist on older runtime.
        has_rejections = bool(
            conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name='decision_rejections' LIMIT 1"
            ).fetchone()
        )

        rej_by_symbol: Dict[str, int] = defaultdict(int)
        rej_reason_by_symbol: Dict[str, Counter] = defaultdict(Counter)
        rej_class_by_symbol: Dict[str, Counter] = defaultdict(Counter)
        rej_total = 0
        rejections_source = "decision_rejections_table"
        if has_rejections:
            for r in _query_rows(
                conn,
                """SELECT symbol,reason_code,reason_class
                   FROM decision_rejections
                   WHERE ts_utc >= ?""",
                (since_iso,),
            ):
                sym = _symbol_base(str(r["symbol"] or ""))
                if not sym:
                    continue
                rej_total += 1
                rej_by_symbol[sym] += 1
                rej_reason_by_symbol[sym][str(r["reason_code"] or "UNKNOWN")] += 1
                rej_class_by_symbol[sym][str(r["reason_class"] or "OTHER")] += 1
        if rej_total == 0:
            # Transitional fallback: parse current runtime log until fresh DB rows appear.
            from_log = _backfill_from_log(root, rej_by_symbol, rej_reason_by_symbol, rej_class_by_symbol)
            if from_log > 0:
                rej_total = int(from_log)
                rejections_source = "safetybot_log_fallback"

        trade_events_by_symbol: Dict[str, int] = defaultdict(int)
        closed_events_by_symbol: Dict[str, int] = defaultdict(int)
        decision_total = 0
        for r in _query_rows(
            conn,
            """SELECT choice_A,outcome_closed_ts_utc
               FROM decision_events
               WHERE ts_utc >= ?""",
            (since_iso,),
        ):
            sym = _symbol_base(str(r["choice_A"] or ""))
            if not sym:
                continue
            decision_total += 1
            trade_events_by_symbol[sym] += 1
            if r["outcome_closed_ts_utc"]:
                closed_events_by_symbol[sym] += 1

        observed = set(rej_by_symbol.keys()) | set(trade_events_by_symbol.keys())
        all_symbols = sorted(set(expected) | observed)

        per_symbol: List[Dict[str, Any]] = []
        for sym in all_symbols:
            rejects = int(rej_by_symbol.get(sym, 0))
            trade_events = int(trade_events_by_symbol.get(sym, 0))
            closed_events = int(closed_events_by_symbol.get(sym, 0))
            reasons = rej_reason_by_symbol.get(sym, Counter())
            classes = rej_class_by_symbol.get(sym, Counter())
            if rejects + trade_events == 0:
                status = "MISSING_ALL_DATA"
            elif trade_events == 0:
                status = "TRADE_PATH_STARVATION"
            elif rejects == 0:
                status = "NO_REJECTION_LABELS"
            else:
                status = "OK_BALANCED"
            per_symbol.append(
                {
                    "symbol": sym,
                    "status": status,
                    "rejected_candidates_n": rejects,
                    "trade_events_n": trade_events,
                    "closed_trade_events_n": closed_events,
                    "top_reasons": [{"reason_code": k, "count": int(v)} for k, v in reasons.most_common(5)],
                    "reason_classes": [{"reason_class": k, "count": int(v)} for k, v in classes.most_common(5)],
                    "recommendation": _reason_reco(reasons),
                }
            )

        payload = {
            "schema": "oanda.mt5.rejected_coverage.v1",
            "ts_utc": _iso_z(_utc_now()),
            "lookback_hours": int(args.lookback_hours),
            "since_utc": since_iso,
            "db_path": str(db_path),
            "decision_rejections_table_present": bool(has_rejections),
            "rejections_source": str(rejections_source),
            "summary": {
                "expected_symbols_n": len(expected),
                "symbols_reported_n": len(all_symbols),
                "rejected_candidates_total_n": int(rej_total),
                "decision_events_total_n": int(decision_total),
                "missing_all_data_symbols_n": int(sum(1 for x in per_symbol if x["status"] == "MISSING_ALL_DATA")),
                "trade_path_starvation_symbols_n": int(
                    sum(1 for x in per_symbol if x["status"] == "TRADE_PATH_STARVATION")
                ),
            },
            "symbols": per_symbol,
        }

        out_dir = root / "EVIDENCE" / "learning_coverage"
        out_dir.mkdir(parents=True, exist_ok=True)
        stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
        out_json = Path(args.out_json) if str(args.out_json).strip() else (out_dir / f"rejected_coverage_{stamp}.json")
        out_txt = Path(args.out_txt) if str(args.out_txt).strip() else (out_dir / f"rejected_coverage_{stamp}.txt")
        out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

        lines: List[str] = []
        lines.append("REJECTED COVERAGE REPORT")
        lines.append(f"Lookback: {int(args.lookback_hours)}h | Since: {since_iso}")
        lines.append(
            "Summary: symbols={0} rejects={1} decisions={2} missing={3} starvation={4}".format(
                payload["summary"]["symbols_reported_n"],
                payload["summary"]["rejected_candidates_total_n"],
                payload["summary"]["decision_events_total_n"],
                payload["summary"]["missing_all_data_symbols_n"],
                payload["summary"]["trade_path_starvation_symbols_n"],
            )
        )
        lines.append("")
        for row in per_symbol:
            lines.append(
                "[{0}] status={1} rejects={2} trade_events={3} closed={4}".format(
                    row["symbol"],
                    row["status"],
                    row["rejected_candidates_n"],
                    row["trade_events_n"],
                    row["closed_trade_events_n"],
                )
            )
            top_reason = row["top_reasons"][0] if row["top_reasons"] else None
            if top_reason:
                lines.append(f"  top_reason={top_reason['reason_code']} ({top_reason['count']})")
            lines.append(f"  reco={row['recommendation']}")
        out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")

        print(f"REJECTED_COVERAGE_OK json={out_json} txt={out_txt}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
