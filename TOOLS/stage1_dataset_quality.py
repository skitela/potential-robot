#!/usr/bin/env python3
"""
Stage-1 learning dataset quality gate.

Reads latest stage1_learning_*.jsonl (or explicit input) and verifies:
- per-symbol sample volume
- per-symbol no-trade / trade-path balance
- minimal bucket coverage (window_id + window_phase)

Outputs PASS/HOLD + blockers for learning automation.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from datetime import datetime, timezone
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


def _iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                yield obj
        except Exception:
            continue


def _find_latest_dataset(base: Path) -> Path:
    files = sorted(base.glob("stage1_learning_*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not files:
        raise FileNotFoundError(f"Brak datasetu stage1 w: {base}")
    return files[0]


def _main() -> int:
    ap = argparse.ArgumentParser(description="Quality gate for stage-1 learning dataset.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM")
    ap.add_argument("--dataset-jsonl", default="")
    ap.add_argument("--min-total-per-symbol", type=int, default=30)
    ap.add_argument("--min-no-trade-per-symbol", type=int, default=10)
    ap.add_argument("--min-trade-path-per-symbol", type=int, default=1)
    ap.add_argument("--min-buckets-per-symbol", type=int, default=2)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-txt", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    ds_base = root / "EVIDENCE" / "learning_dataset"
    ds_path = Path(args.dataset_jsonl).resolve() if str(args.dataset_jsonl).strip() else _find_latest_dataset(ds_base)
    if not ds_path.exists():
        raise SystemExit(f"Dataset missing: {ds_path}")

    min_total = max(1, int(args.min_total_per_symbol))
    min_no_trade = max(0, int(args.min_no_trade_per_symbol))
    min_trade_path = max(0, int(args.min_trade_path_per_symbol))
    min_buckets = max(1, int(args.min_buckets_per_symbol))

    by_symbol_total: Dict[str, int] = defaultdict(int)
    by_symbol_no_trade: Dict[str, int] = defaultdict(int)
    by_symbol_trade: Dict[str, int] = defaultdict(int)
    by_symbol_buckets: Dict[str, set[str]] = defaultdict(set)
    reason_class_counts: Counter[str] = Counter()
    command_type_counts: Counter[str] = Counter()

    rows_total = 0
    for row in _iter_jsonl(ds_path):
        rows_total += 1
        sym = _symbol_base(str(row.get("instrument") or row.get("symbol") or ""))
        if not sym:
            continue
        st = str(row.get("sample_type") or "").upper()
        reason_class = str(row.get("reason_class") or "UNKNOWN").upper()
        command_type = str(row.get("command_type") or "OTHER").upper()
        wid = str(row.get("window_id") or "UNKNOWN")
        wph = str(row.get("window_phase") or "UNKNOWN")

        by_symbol_total[sym] += 1
        if st == "NO_TRADE":
            by_symbol_no_trade[sym] += 1
        elif st == "TRADE_PATH":
            by_symbol_trade[sym] += 1
        by_symbol_buckets[sym].add(f"{wid}|{wph}")
        reason_class_counts[reason_class] += 1
        command_type_counts[command_type] += 1

    symbols = sorted(by_symbol_total.keys())
    blockers: List[str] = []
    symbol_rows: List[Dict[str, Any]] = []
    for sym in symbols:
        n_total = int(by_symbol_total.get(sym, 0))
        n_no_trade = int(by_symbol_no_trade.get(sym, 0))
        n_trade = int(by_symbol_trade.get(sym, 0))
        n_buckets = int(len(by_symbol_buckets.get(sym, set())))
        reasons: List[str] = []
        status = "PASS"
        if n_total < min_total:
            reasons.append(f"TOTAL_LT_MIN:{n_total}<{min_total}")
        if n_no_trade < min_no_trade:
            reasons.append(f"NO_TRADE_LT_MIN:{n_no_trade}<{min_no_trade}")
        if n_trade < min_trade_path:
            reasons.append(f"TRADE_PATH_LT_MIN:{n_trade}<{min_trade_path}")
        if n_buckets < min_buckets:
            reasons.append(f"BUCKETS_LT_MIN:{n_buckets}<{min_buckets}")
        if reasons:
            status = "HOLD"
            blockers.append(f"{sym}:{'|'.join(reasons)}")
        symbol_rows.append(
            {
                "symbol": sym,
                "status": status,
                "rows_total": n_total,
                "rows_no_trade": n_no_trade,
                "rows_trade_path": n_trade,
                "bucket_coverage_n": n_buckets,
                "reasons": reasons,
            }
        )

    verdict = "PASS" if not blockers else "HOLD"
    payload = {
        "schema": "oanda.mt5.stage1_dataset_quality.v1",
        "ts_utc": _iso_z(_utc_now()),
        "dataset_path": str(ds_path),
        "thresholds": {
            "min_total_per_symbol": min_total,
            "min_no_trade_per_symbol": min_no_trade,
            "min_trade_path_per_symbol": min_trade_path,
            "min_buckets_per_symbol": min_buckets,
        },
        "summary": {
            "rows_total": int(rows_total),
            "symbols_total": int(len(symbols)),
            "symbols_pass": int(sum(1 for x in symbol_rows if x["status"] == "PASS")),
            "symbols_hold": int(sum(1 for x in symbol_rows if x["status"] == "HOLD")),
            "reason_class_counts": dict(reason_class_counts),
            "command_type_counts": dict(command_type_counts),
        },
        "verdict": {
            "status": verdict,
            "blockers": blockers[:200],
        },
        "symbols": symbol_rows,
    }

    out_dir = root / "EVIDENCE" / "learning_dataset_quality"
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
    out_json = Path(args.out_json) if str(args.out_json).strip() else (out_dir / f"stage1_dataset_quality_{stamp}.json")
    out_txt = Path(args.out_txt) if str(args.out_txt).strip() else (out_dir / f"stage1_dataset_quality_{stamp}.txt")
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "STAGE1 DATASET QUALITY",
        f"Dataset: {ds_path}",
        f"Verdict: {verdict}",
        "Thresholds: total>={0}, no_trade>={1}, trade_path>={2}, buckets>={3}".format(
            min_total, min_no_trade, min_trade_path, min_buckets
        ),
        "",
    ]
    for row in symbol_rows:
        lines.append(
            "[{0}] {1} total={2} no_trade={3} trade_path={4} buckets={5}".format(
                row["symbol"],
                row["status"],
                row["rows_total"],
                row["rows_no_trade"],
                row["rows_trade_path"],
                row["bucket_coverage_n"],
            )
        )
        if row["reasons"]:
            lines.append("  reasons=" + ";".join(row["reasons"]))
    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"STAGE1_DATASET_QUALITY_OK verdict={verdict} json={out_json} txt={out_txt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
