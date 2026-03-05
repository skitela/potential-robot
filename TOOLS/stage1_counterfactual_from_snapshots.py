#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_ts(raw: Any) -> Optional[dt.datetime]:
    s = str(raw or "").strip()
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def symbol_base(sym: str) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def infer_side(row: Dict[str, Any]) -> str:
    side = str(row.get("side") or "").strip().upper()
    if side in {"LONG", "SHORT"}:
        return side
    sig = str(row.get("signal") or "").strip().upper()
    if "BUY" in sig or "LONG" in sig:
        return "LONG"
    if "SELL" in sig or "SHORT" in sig:
        return "SHORT"
    return "UNKNOWN"


def infer_point_size(price: float) -> float:
    s = f"{float(price):.10f}".rstrip("0")
    if "." not in s:
        return 0.01
    dec = len(s.split(".", 1)[1])
    if dec >= 5:
        return 0.00001
    if dec == 4:
        return 0.0001
    if dec == 3:
        return 0.001
    return 0.01


def find_latest_stage1_dataset(root: Path) -> Optional[Path]:
    base = (root / "EVIDENCE" / "learning_dataset").resolve()
    if not base.exists():
        return None
    files = sorted(base.glob("stage1_learning_*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def find_latest_snapshot_db(lab_data_root: Path, name: str) -> Optional[Path]:
    snapshots_root = (lab_data_root / "snapshots").resolve()
    if not snapshots_root.exists():
        return None
    dirs = sorted((p for p in snapshots_root.iterdir() if p.is_dir()), key=lambda p: p.name, reverse=True)
    for d in dirs:
        cand = (d / name).resolve()
        if cand.exists():
            return cand
    return None


def _db_has_table(db_path: Path, table: str) -> bool:
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)
        try:
            row = conn.execute(
                "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
                [table],
            ).fetchone()
            return row is not None
        finally:
            conn.close()
    except Exception:
        return False


def build_market_sources(*, root: Path, lab_data_root: Path, history_db: Path, requested_timeframe: str) -> List[Dict[str, Any]]:
    # Priority:
    # 1) curated mt5_history (M1/M5/etc. in mt5_rates)
    # 2) latest LAB snapshot m5_bars (M5)
    # 3) live runtime DB m5_bars (M5)
    out: List[Dict[str, Any]] = []
    req_tf = str(requested_timeframe or "M1").upper()

    if history_db.exists() and _db_has_table(history_db, "mt5_rates"):
        out.append(
            {
                "name": "curated_mt5_rates",
                "kind": "mt5_rates",
                "db_path": history_db,
                "timeframe": req_tf,
            }
        )

    snap_m5 = find_latest_snapshot_db(lab_data_root, "m5_bars.sqlite")
    if snap_m5 is not None and _db_has_table(snap_m5, "m5_bars"):
        out.append(
            {
                "name": "snapshot_m5_bars",
                "kind": "m5_bars",
                "db_path": snap_m5,
                "timeframe": "M5",
            }
        )

    runtime_m5 = (root / "DB" / "m5_bars.sqlite").resolve()
    if runtime_m5.exists() and _db_has_table(runtime_m5, "m5_bars"):
        # Avoid duplicate path if snapshot already points to the same file.
        if not any(str(s.get("db_path")) == str(runtime_m5) for s in out):
            out.append(
                {
                    "name": "runtime_m5_bars",
                    "kind": "m5_bars",
                    "db_path": runtime_m5,
                    "timeframe": "M5",
                }
            )
    return out


def fetch_source_max_ts(conn: sqlite3.Connection, *, source: Dict[str, Any]) -> Optional[dt.datetime]:
    kind = str(source.get("kind") or "").strip().lower()
    if kind == "mt5_rates":
        row = conn.execute(
            """
            SELECT MAX(ts_utc) AS max_ts
            FROM mt5_rates
            WHERE timeframe = ?
            """,
            [str(source.get("timeframe") or "M1").upper()],
        ).fetchone()
        return parse_ts((row or {}).get("max_ts") if isinstance(row, dict) else (row["max_ts"] if row else None))
    if kind == "m5_bars":
        row = conn.execute("SELECT MAX(t_utc) AS max_ts FROM m5_bars").fetchone()
        return parse_ts((row or {}).get("max_ts") if isinstance(row, dict) else (row["max_ts"] if row else None))
    return None


def iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        raw = line.strip()
        if not raw:
            continue
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                yield obj
        except Exception:
            continue


def load_no_trade_rows(dataset_jsonl: Path, max_rows: int) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for row in iter_jsonl(dataset_jsonl):
        if str(row.get("sample_type") or "").upper() != "NO_TRADE":
            continue
        out.append(row)
        if len(out) >= max_rows:
            break
    return out


def fetch_entry_and_path(
    conn: sqlite3.Connection,
    *,
    source: Dict[str, Any],
    symbol: str,
    ts_start: str,
    ts_end: str,
) -> Tuple[Optional[Dict[str, Any]], List[Dict[str, Any]]]:
    kind = str(source.get("kind") or "").strip().lower()
    if kind == "mt5_rates":
        entry = conn.execute(
            """
            SELECT ts_utc, open, high, low, close, spread
            FROM mt5_rates
            WHERE symbol = ? AND timeframe = ? AND ts_utc >= ?
            ORDER BY ts_utc ASC
            LIMIT 1
            """,
            [symbol, str(source.get("timeframe") or "M1").upper(), ts_start],
        ).fetchone()

        if entry is None:
            return None, []

        rows = conn.execute(
            """
            SELECT ts_utc, open, high, low, close, spread
            FROM mt5_rates
            WHERE symbol = ? AND timeframe = ? AND ts_utc >= ? AND ts_utc <= ?
            ORDER BY ts_utc ASC
            """,
            [symbol, str(source.get("timeframe") or "M1").upper(), str(entry["ts_utc"]), ts_end],
        ).fetchall()
        return dict(entry), [dict(r) for r in rows]

    if kind == "m5_bars":
        entry = conn.execute(
            """
            SELECT t_utc AS ts_utc, o AS open, h AS high, l AS low, c AS close, NULL AS spread
            FROM m5_bars
            WHERE symbol = ? AND t_utc >= ?
            ORDER BY t_utc ASC
            LIMIT 1
            """,
            [symbol, ts_start],
        ).fetchone()

        if entry is None:
            return None, []

        rows = conn.execute(
            """
            SELECT t_utc AS ts_utc, o AS open, h AS high, l AS low, c AS close, NULL AS spread
            FROM m5_bars
            WHERE symbol = ? AND t_utc >= ? AND t_utc <= ?
            ORDER BY t_utc ASC
            """,
            [symbol, str(entry["ts_utc"]), ts_end],
        ).fetchall()
        return dict(entry), [dict(r) for r in rows]

    return None, []


def evaluate_counterfactual(
    *,
    side: str,
    entry_price: float,
    point_size: float,
    spread_points: float,
    slippage_points: float,
    tp_points: float,
    sl_points: float,
    path_rows: List[Dict[str, Any]],
) -> Tuple[str, float]:
    if point_size <= 0.0:
        return "NO_POINT_SIZE", 0.0
    if not path_rows:
        return "NO_PATH", 0.0

    cost_delta = (float(max(0.0, spread_points)) + float(max(0.0, slippage_points))) * point_size
    if side == "LONG":
        entry_eff = entry_price + cost_delta
        tp_price = entry_eff + (float(tp_points) * point_size)
        sl_price = entry_eff - (float(sl_points) * point_size)
    else:
        entry_eff = entry_price - cost_delta
        tp_price = entry_eff - (float(tp_points) * point_size)
        sl_price = entry_eff + (float(sl_points) * point_size)

    exit_price = entry_eff
    hit_state = "TIMEOUT"
    for bar in path_rows:
        hi = float(bar.get("high") or 0.0)
        lo = float(bar.get("low") or 0.0)
        # Conservative ordering: if TP and SL in the same bar, assume SL first.
        if side == "LONG":
            if lo <= sl_price:
                hit_state = "SL"
                exit_price = sl_price
                break
            if hi >= tp_price:
                hit_state = "TP"
                exit_price = tp_price
                break
        else:
            if hi >= sl_price:
                hit_state = "SL"
                exit_price = sl_price
                break
            if lo <= tp_price:
                hit_state = "TP"
                exit_price = tp_price
                break
    if hit_state == "TIMEOUT":
        exit_price = float(path_rows[-1].get("close") or entry_eff)

    if side == "LONG":
        pnl_points = (exit_price - entry_eff) / point_size
    else:
        pnl_points = (entry_eff - exit_price) / point_size

    if hit_state == "TP":
        return "MISSED_OPPORTUNITY", float(pnl_points)
    if hit_state == "SL":
        return "SAVED_LOSS", float(pnl_points)
    return "NEUTRAL_TIMEOUT", float(pnl_points)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Light counterfactual labeling on Stage-1 NO_TRADE samples from LAB snapshots.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--dataset-jsonl", default="")
    ap.add_argument("--history-db", default="")
    ap.add_argument("--timeframe", default="M1")
    ap.add_argument("--horizon-minutes", type=int, default=15)
    ap.add_argument("--tp-points", type=float, default=150.0)
    ap.add_argument("--sl-points", type=float, default=100.0)
    ap.add_argument("--slippage-points", type=float, default=3.0)
    ap.add_argument("--max-source-lag-hours", type=float, default=12.0)
    ap.add_argument("--fail-on-all-stale", action="store_true")
    ap.add_argument("--max-no-trade-samples", type=int, default=1000)
    ap.add_argument("--out-jsonl", default="")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"CF_STAGE1_{stamp}"

    dataset_jsonl = Path(args.dataset_jsonl).resolve() if str(args.dataset_jsonl).strip() else find_latest_stage1_dataset(root)
    history_db = (
        Path(args.history_db).resolve()
        if str(args.history_db).strip()
        else (lab_data_root / "data_curated" / "mt5_history.sqlite").resolve()
    )
    out_jsonl = (
        Path(args.out_jsonl).resolve()
        if str(args.out_jsonl).strip()
        else (lab_data_root / "reports" / "stage1" / f"stage1_counterfactual_rows_{stamp}.jsonl").resolve()
    )
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (lab_data_root / "reports" / "stage1" / f"stage1_counterfactual_report_{stamp}.json").resolve()
    )
    out_jsonl = ensure_write_parent(out_jsonl, root=root, lab_data_root=lab_data_root)
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "NO_DATASET"
    details: Dict[str, Any] = {}
    annotated_rows: List[Dict[str, Any]] = []
    market_sources = build_market_sources(
        root=root,
        lab_data_root=lab_data_root,
        history_db=history_db,
        requested_timeframe=str(args.timeframe).upper(),
    )

    if dataset_jsonl is None or not dataset_jsonl.exists():
        reason = "DATASET_MISSING"
    elif not market_sources:
        reason = "MARKET_SOURCE_MISSING"
    else:
        no_trade = load_no_trade_rows(dataset_jsonl, max_rows=max(1, int(args.max_no_trade_samples)))
        if not no_trade:
            reason = "NO_NO_TRADE_ROWS"
        else:
            opened_sources: List[Tuple[Dict[str, Any], sqlite3.Connection]] = []
            no_trade_ts = [t for t in (parse_ts(r.get("ts_utc")) for r in no_trade) if t is not None]
            dataset_min_ts = min(no_trade_ts) if no_trade_ts else None
            dataset_max_ts = max(no_trade_ts) if no_trade_ts else None
            freshness_info: List[Dict[str, Any]] = []
            stale_sources: List[str] = []
            fresh_sources = 0
            max_lag_h = float(max(0.0, float(args.max_source_lag_hours)))
            for src in market_sources:
                c = sqlite3.connect(str(Path(str(src.get("db_path")))))
                c.row_factory = sqlite3.Row
                opened_sources.append((src, c))
                max_ts = fetch_source_max_ts(c, source=src)
                lag_h = None
                is_stale = False
                if dataset_max_ts is not None and max_ts is not None:
                    lag_h = (dataset_max_ts - max_ts).total_seconds() / 3600.0
                    is_stale = lag_h > max_lag_h
                if is_stale:
                    stale_sources.append(str(src.get("name") or "unknown"))
                else:
                    fresh_sources += 1
                freshness_info.append(
                    {
                        "name": str(src.get("name") or ""),
                        "kind": str(src.get("kind") or ""),
                        "db_path": str(src.get("db_path") or ""),
                        "timeframe": str(src.get("timeframe") or ""),
                        "max_ts_utc": iso_utc(max_ts) if max_ts is not None else "",
                        "lag_hours_vs_dataset_max": (round(float(lag_h), 3) if lag_h is not None else None),
                        "is_stale": bool(is_stale),
                    }
                )

            if stale_sources:
                print(
                    "STAGE1_COUNTERFACTUAL_PRECHECK_ALERT "
                    f"stale_sources={','.join(stale_sources)} "
                    f"threshold_h={max_lag_h:.3f} "
                    f"dataset_max_ts={iso_utc(dataset_max_ts) if dataset_max_ts is not None else 'UNKNOWN'}"
                )

            by_status: Dict[str, int] = {}
            by_source_hits: Dict[str, int] = {}
            no_market_path_by_symbol: Dict[str, int] = {}
            evaluated = 0
            skipped = 0
            total_pnl_points = 0.0
            try:
                if dataset_max_ts is not None and fresh_sources <= 0:
                    if bool(args.fail_on_all_stale):
                        status = "FAIL"
                        reason = "STALE_MARKET_DATA_FATAL"
                        print(
                            "STAGE1_COUNTERFACTUAL_PRECHECK_FAIL "
                            f"all_sources_stale=true threshold_h={max_lag_h:.3f} "
                            f"dataset_max_ts={iso_utc(dataset_max_ts)}"
                        )
                    else:
                        status = "SKIP"
                        reason = "STALE_MARKET_DATA"
                else:
                    horizon_min = max(1, int(args.horizon_minutes))
                    for row in no_trade:
                        ts = parse_ts(row.get("ts_utc"))
                        sym = symbol_base(str(row.get("instrument") or row.get("symbol") or ""))
                        side = infer_side(row)
                        if ts is None or not sym:
                            skipped += 1
                            st = "SKIP_CONTEXT"
                            by_status[st] = int(by_status.get(st, 0)) + 1
                            continue

                        end_ts = ts + dt.timedelta(minutes=horizon_min)
                        entry: Optional[Dict[str, Any]] = None
                        path: List[Dict[str, Any]] = []
                        selected_source: Optional[Dict[str, Any]] = None
                        for src, c in opened_sources:
                            entry, path = fetch_entry_and_path(
                                c,
                                source=src,
                                symbol=sym,
                                ts_start=iso_utc(ts),
                                ts_end=iso_utc(end_ts),
                            )
                            if entry is not None and path:
                                selected_source = src
                                break
                        if entry is None or not path:
                            skipped += 1
                            st = "NO_MARKET_PATH"
                            by_status[st] = int(by_status.get(st, 0)) + 1
                            no_market_path_by_symbol[sym] = int(no_market_path_by_symbol.get(sym, 0)) + 1
                            continue

                        entry_price = float(entry.get("close") or 0.0)
                        if entry_price <= 0.0:
                            skipped += 1
                            st = "INVALID_ENTRY_PRICE"
                            by_status[st] = int(by_status.get(st, 0)) + 1
                            continue

                        point_size = infer_point_size(entry_price)
                        spread_points = 0.0
                        try:
                            ctx = row.get("context") if isinstance(row.get("context"), dict) else {}
                            spread_points = float(ctx.get("spread_points") or 0.0)
                        except Exception:
                            spread_points = 0.0

                        long_eval = evaluate_counterfactual(
                            side="LONG",
                            entry_price=entry_price,
                            point_size=point_size,
                            spread_points=spread_points,
                            slippage_points=float(args.slippage_points),
                            tp_points=float(args.tp_points),
                            sl_points=float(args.sl_points),
                            path_rows=path,
                        )
                        short_eval = evaluate_counterfactual(
                            side="SHORT",
                            entry_price=entry_price,
                            point_size=point_size,
                            spread_points=spread_points,
                            slippage_points=float(args.slippage_points),
                            tp_points=float(args.tp_points),
                            sl_points=float(args.sl_points),
                            path_rows=path,
                        )
                        if side in {"LONG", "SHORT"}:
                            label, pnl_points = long_eval if side == "LONG" else short_eval
                            side_effective = side
                        else:
                            # Conservative fallback for unknown side: pick worse outcome (lower pnl).
                            label, pnl_points = (long_eval if float(long_eval[1]) <= float(short_eval[1]) else short_eval)
                            side_effective = "BOTH_CONSERVATIVE"
                        evaluated += 1
                        total_pnl_points += float(pnl_points)
                        by_status[label] = int(by_status.get(label, 0)) + 1
                        src_name = str((selected_source or {}).get("name") or "unknown_source")
                        by_source_hits[src_name] = int(by_source_hits.get(src_name, 0)) + 1

                        annotated_rows.append(
                            {
                                "ts_utc": str(row.get("ts_utc") or ""),
                                "symbol": sym,
                                "side": side_effective,
                                "side_source": side,
                                "reason_code": str(row.get("label") or ""),
                                "reason_class": str(row.get("reason_class") or ""),
                                "window_id": str(row.get("window_id") or ""),
                                "window_phase": str(row.get("window_phase") or ""),
                                "counterfactual_status": label,
                                "counterfactual_pnl_points": float(round(pnl_points, 5)),
                                "counterfactual_long_status": str(long_eval[0]),
                                "counterfactual_long_pnl_points": float(round(long_eval[1], 5)),
                                "counterfactual_short_status": str(short_eval[0]),
                                "counterfactual_short_pnl_points": float(round(short_eval[1], 5)),
                                "entry_ts_utc": str(entry.get("ts_utc") or ""),
                                "entry_price": float(entry_price),
                                "point_size": float(point_size),
                                "path_bars_n": len(path),
                                "horizon_minutes": int(horizon_min),
                                "market_source": src_name,
                                "market_timeframe": str((selected_source or {}).get("timeframe") or ""),
                            }
                        )
            finally:
                for _, c in opened_sources:
                    try:
                        c.close()
                    except Exception as exc:
                        _ = exc
            if reason not in {"STALE_MARKET_DATA", "STALE_MARKET_DATA_FATAL"}:
                status = "PASS" if evaluated > 0 else "SKIP"
                reason = "COUNTERFACTUAL_OK" if evaluated > 0 else "COUNTERFACTUAL_NO_EVAL"
            details = {
                "rows_no_trade_seen": len(no_trade),
                "rows_evaluated": int(evaluated),
                "rows_skipped": int(skipped),
                "status_counts": by_status,
                "counterfactual_pnl_points_total": float(round(total_pnl_points, 5)),
                "counterfactual_pnl_points_avg": float(round(total_pnl_points / evaluated, 5)) if evaluated > 0 else 0.0,
                "market_source_hits": by_source_hits,
                "no_market_path_by_symbol": no_market_path_by_symbol,
                "market_sources": [
                    {
                        "name": str(src.get("name") or ""),
                        "kind": str(src.get("kind") or ""),
                        "db_path": str(src.get("db_path") or ""),
                        "timeframe": str(src.get("timeframe") or ""),
                    }
                    for src in market_sources
                ],
                "freshness_precheck": {
                    "dataset_min_ts_utc": (iso_utc(dataset_min_ts) if dataset_min_ts is not None else ""),
                    "dataset_max_ts_utc": (iso_utc(dataset_max_ts) if dataset_max_ts is not None else ""),
                    "max_source_lag_hours": max_lag_h,
                    "fresh_sources": int(fresh_sources),
                    "stale_sources": stale_sources,
                    "sources": freshness_info,
                },
            }

    with out_jsonl.open("w", encoding="utf-8") as f:
        for row in annotated_rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    report = {
        "schema": "oanda.mt5.stage1_counterfactual.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "dataset_jsonl": str(dataset_jsonl) if dataset_jsonl is not None else "",
        "history_db": str(history_db),
        "output_rows_jsonl": str(out_jsonl),
        "details": details,
        "params": {
            "timeframe": str(args.timeframe).upper(),
            "horizon_minutes": int(max(1, int(args.horizon_minutes))),
            "tp_points": float(args.tp_points),
            "sl_points": float(args.sl_points),
            "slippage_points": float(args.slippage_points),
            "max_source_lag_hours": float(max(0.0, float(args.max_source_lag_hours))),
            "fail_on_all_stale": bool(args.fail_on_all_stale),
            "max_no_trade_samples": int(max(1, int(args.max_no_trade_samples))),
        },
    }
    out_report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    txt_lines = [
        "STAGE1_COUNTERFACTUAL",
        f"Status: {status}",
        f"Reason: {reason}",
        f"Dataset: {dataset_jsonl}" if dataset_jsonl is not None else "Dataset: NONE",
        f"History DB: {history_db}",
        f"Max source lag hours: {float(max(0.0, float(args.max_source_lag_hours))):.3f}",
        f"Fail on all stale: {bool(args.fail_on_all_stale)}",
        f"Evaluated: {int((details or {}).get('rows_evaluated', 0))}",
        f"Skipped: {int((details or {}).get('rows_skipped', 0))}",
        f"Output rows: {out_jsonl}",
    ]
    out_report.with_suffix(".txt").write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

    # Registry (best effort).
    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash(report.get("params") if isinstance(report.get("params"), dict) else {})
        ds_hash = file_sha256(dataset_jsonl) if dataset_jsonl is not None and dataset_jsonl.exists() else ""
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_COUNTERFACTUAL",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": ds_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps(details, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_COUNTERFACTUAL_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
