#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_utc(raw: str | None) -> dt.datetime | None:
    if not raw:
        return None
    try:
        return dt.datetime.fromisoformat(str(raw).replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def load_json(path: Path) -> Dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None


def report_ts(payload: Dict[str, Any]) -> dt.datetime | None:
    for key in ("generated_at_utc", "started_at_utc", "finished_at_utc", "ts_utc"):
        ts = parse_utc(str(payload.get(key, "")))
        if ts is not None:
            return ts
    return None


def iter_reports(root: Path) -> Iterable[Path]:
    if not root.exists():
        return []
    files = [p for p in root.glob("*.json") if p.is_file()]
    files.sort(key=lambda p: p.stat().st_mtime)
    return files


def reports_in_window(root: Path, start_utc: dt.datetime, end_utc: dt.datetime) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    for path in iter_reports(root):
        payload = load_json(path)
        if not payload:
            continue
        ts = report_ts(payload)
        if ts is None:
            continue
        if start_utc < ts <= end_utc:
            out.append({"path": str(path), "ts_utc": iso_utc(ts), "payload": payload})
    return out


def latest_payload(root: Path) -> Dict[str, Any]:
    files = list(iter_reports(root))
    if not files:
        return {}
    payload = load_json(files[-1])
    return payload or {}


def latest_payload_prefer_status(root: Path, status: str = "PASS") -> Dict[str, Any]:
    files = list(iter_reports(root))
    if not files:
        return {}
    target = str(status).upper()
    for p in reversed(files):
        payload = load_json(p) or {}
        if str(payload.get("status", "")).upper() == target:
            return payload
    return load_json(files[-1]) or {}


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate human-readable LAB insights digest for operator panel.")
    ap.add_argument("--root", default=r"C:\OANDA_MT5_SYSTEM")
    ap.add_argument("--lab-data-root", default=r"C:\OANDA_MT5_SYSTEM\LAB_DATA")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def _safe_int(v: Any) -> int:
    try:
        return int(float(v))
    except Exception:
        return 0


def _safe_float(v: Any) -> float:
    try:
        return float(v)
    except Exception:
        return 0.0


def _load_pln_point_map(root: Path) -> Tuple[float, Dict[str, float]]:
    cfg_path = (root / "LAB" / "CONFIG" / "pln_point_estimates.json").resolve()
    if not cfg_path.exists():
        return 1.0, {}
    try:
        payload = json.loads(cfg_path.read_text(encoding="utf-8"))
    except Exception:
        return 1.0, {}
    default_factor = _safe_float(payload.get("default_pln_per_point"))
    if default_factor <= 0.0:
        default_factor = 1.0
    symbol_map: Dict[str, float] = {}
    raw_overrides = payload.get("symbol_overrides")
    if isinstance(raw_overrides, dict):
        for k, v in raw_overrides.items():
            key = str(k or "").strip().upper()
            val = _safe_float(v)
            if key and val > 0.0:
                symbol_map[key] = val
    return default_factor, symbol_map


def _points_to_pln(points: float, symbol: str, *, default_factor: float, symbol_map: Dict[str, float]) -> float:
    factor = float(symbol_map.get(str(symbol or "").upper(), default_factor))
    if factor <= 0.0:
        factor = 1.0
    return float(points) * factor


def _fmt_signed_pln(value: float) -> str:
    return f"{value:+.2f} zł"


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve()
    now = dt.datetime.now(tz=UTC)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    reports_ingest = lab_data_root / "reports" / "ingest"
    reports_daily = lab_data_root / "reports" / "daily"
    reports_retention = lab_data_root / "reports" / "retention"
    reports_profiles = lab_data_root / "reports" / "profiles"
    reports_stage1 = lab_data_root / "reports" / "stage1"
    run_status = lab_data_root / "run" / "lab_scheduler_status.json"
    pointer_json = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.json"
    pointer_txt = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.txt"
    seen_path = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_seen.json"

    previous_pointer = load_json(pointer_json) or {}
    seen_payload = load_json(seen_path) or {}
    seen_ts = parse_utc(str(seen_payload.get("seen_generated_at_utc", "")))
    prev_start_ts = parse_utc(str((previous_pointer.get("interval") or {}).get("start_utc", "")))
    # Cumulative behavior:
    # - if user opened insights -> window starts from last seen timestamp
    # - if user did not open insights -> keep previous start and extend window
    # - first run fallback -> last 3h
    if seen_ts is not None:
        start_utc = seen_ts
        interval_source = "SINCE_LAST_VIEW"
    elif prev_start_ts is not None:
        start_utc = prev_start_ts
        interval_source = "SINCE_PREVIOUS_DIGEST_UNSEEN"
    else:
        start_utc = now - dt.timedelta(hours=3)
        interval_source = "DEFAULT_3H"
    if start_utc > now:
        start_utc = now - dt.timedelta(hours=3)
    hours_span_exact = max(1.0, round((now - start_utc).total_seconds() / 3600.0, 2))
    # Human summary uses 3h buckets: 3, 6, 9... until insights are viewed.
    hours_bucket_3h = max(3, int((hours_span_exact // 3) * 3))

    ingest_window = reports_in_window(reports_ingest, start_utc, now)
    daily_window = reports_in_window(reports_daily, start_utc, now)
    retention_window = reports_in_window(reports_retention, start_utc, now)
    profile_window = reports_in_window(reports_profiles, start_utc, now)

    latest_ingest = latest_payload(reports_ingest)
    latest_daily_pass = latest_payload_prefer_status(reports_daily, status="PASS")
    latest_retention = latest_payload(reports_retention)
    latest_profile_sweep = latest_payload_prefer_status(reports_profiles, status="PASS")
    latest_cf_summary = latest_payload_prefer_status(reports_stage1, status="PASS")
    status_payload = load_json(run_status) or {}

    # Aggregate ingest window.
    ingest_runs = len(ingest_window)
    rows_fetched = 0
    rows_inserted = 0
    rows_deduped = 0
    gap_events = 0
    invalid_ohlc = 0
    negative_spread = 0
    nonpositive_close = 0
    symbols: set[str] = set()
    for item in ingest_window:
        summ = dict((item["payload"] or {}).get("summary") or {})
        rows_fetched += _safe_int(summ.get("rows_fetched_total"))
        rows_inserted += _safe_int(summ.get("rows_inserted_total"))
        rows_deduped += _safe_int(summ.get("rows_deduped_total"))
        gap_events += _safe_int(summ.get("gap_events_total"))
        invalid_ohlc += _safe_int(summ.get("invalid_ohlc_total"))
        negative_spread += _safe_int(summ.get("negative_spread_total"))
        nonpositive_close += _safe_int(summ.get("nonpositive_close_total"))
        for det in list((item["payload"] or {}).get("details") or []):
            sym = str(det.get("symbol") or "").upper().strip()
            if sym:
                symbols.add(sym)

    # Aggregate daily window.
    daily_runs = len(daily_window)
    daily_pass_runs = 0
    daily_skip_runs = 0
    windows: set[str] = set()
    actions_count: Dict[str, int] = {}
    profitable = 0
    losing = 0
    neutral = 0
    best_row = None
    worst_row = None
    for item in daily_window:
        payload = item["payload"] or {}
        status = str(payload.get("status", "")).upper()
        if status == "PASS":
            daily_pass_runs += 1
        elif status.startswith("SKIP"):
            daily_skip_runs += 1
        for w in list(((payload.get("summary") or {}).get("focus_windows") or [])):
            ww = str(w).upper().strip()
            if ww:
                windows.add(ww)
        for row in list(payload.get("leaderboard") or []):
            act = str(row.get("lab_action") or "UNKNOWN").upper()
            actions_count[act] = int(actions_count.get(act, 0)) + 1
            exp = dict(row.get("explore") or {})
            net_pt = _safe_float(exp.get("net_pips_per_trade"))
            if net_pt > 0:
                profitable += 1
            elif net_pt < 0:
                losing += 1
            else:
                neutral += 1
            if best_row is None or net_pt > _safe_float((best_row.get("explore") or {}).get("net_pips_per_trade")):
                best_row = row
            if worst_row is None or net_pt < _safe_float((worst_row.get("explore") or {}).get("net_pips_per_trade")):
                worst_row = row

    latest_ingest_summary = dict((latest_ingest or {}).get("summary") or {})
    latest_daily_summary = dict((latest_daily_pass or {}).get("summary") or {})
    latest_ret_summary = dict((latest_retention or {}).get("summary") or {})
    latest_profile_status = str((latest_profile_sweep or {}).get("status") or "UNKNOWN").upper()
    latest_profile_winner = str((latest_profile_sweep or {}).get("winner_by_explore_net_pips_per_trade") or "UNKNOWN").upper()
    latest_profile_runs = list((latest_profile_sweep or {}).get("runs") or [])
    latest_cf_status = str((latest_cf_summary or {}).get("status") or "UNKNOWN").upper()
    latest_cf_rows_total = _safe_int(((latest_cf_summary or {}).get("summary") or {}).get("rows_total"))
    cf_by_symbol = list((((latest_cf_summary or {}).get("aggregates") or {}).get("by_symbol") or []))
    scheduler_status = str((status_payload or {}).get("status") or "UNKNOWN").upper()
    scheduler_reason = str((status_payload or {}).get("reason") or "UNKNOWN")
    pairs_ready = _safe_int(latest_daily_summary.get("pairs_ready_for_shadow"))
    pairs_total = _safe_int(latest_daily_summary.get("pairs_total"))
    explore_total_trades_latest = _safe_int(latest_daily_summary.get("explore_total_trades"))
    quality_grade_latest = str(latest_ingest_summary.get("quality_grade", "UNKNOWN")).upper()
    default_pln_per_point, pln_symbol_map = _load_pln_point_map(root)

    cf_symbol_compact: List[Dict[str, Any]] = []
    for row in cf_by_symbol:
        if not isinstance(row, dict):
            continue
        symbol = str(row.get("symbol") or "").upper().strip()
        if not symbol:
            continue
        pnl_pts = _safe_float(row.get("counterfactual_pnl_points_total"))
        pnl_pln = _points_to_pln(
            pnl_pts,
            symbol,
            default_factor=default_pln_per_point,
            symbol_map=pln_symbol_map,
        )
        cf_symbol_compact.append(
            {
                "symbol": symbol,
                "samples_n": _safe_int(row.get("samples_n")),
                "saved_loss_n": _safe_int(row.get("saved_loss_n")),
                "missed_opportunity_n": _safe_int(row.get("missed_opportunity_n")),
                "neutral_timeout_n": _safe_int(row.get("neutral_timeout_n")),
                "counterfactual_pnl_points_total": pnl_pts,
                "counterfactual_pnl_pln_est_total": float(round(pnl_pln, 2)),
                "recommendation": str(row.get("recommendation") or "OBSERWUJ_BEZ_ZMIAN"),
            }
        )
    cf_symbol_compact.sort(key=lambda x: abs(_safe_float(x.get("counterfactual_pnl_pln_est_total"))), reverse=True)
    cf_symbol_compact = cf_symbol_compact[:10]

    if pairs_ready > 0 and quality_grade_latest == "OK":
        recommendation = "Masz kandydatow do shadow. Przejrzyj top ranking i rozważ selektywne poluzowanie tylko tam, gdzie wynik jest stabilnie dodatni."
    elif cf_symbol_compact and any(_safe_float(x.get("counterfactual_pnl_pln_est_total")) > 0 for x in cf_symbol_compact):
        recommendation = "Czesc instrumentow pokazuje dodatni wynik kontrfaktyczny; testuj luzowanie w SHADOW tylko na tych parach i pod kontrola risk."
    elif cf_symbol_compact and all(_safe_float(x.get("counterfactual_pnl_pln_est_total")) <= 0 for x in cf_symbol_compact):
        recommendation = "Kontrfaktyka jest globalnie ujemna; trzymaj lub dociskaj filtry, a nie luzuj ich szeroko."
    elif losing > profitable and daily_pass_runs > 0:
        recommendation = "Wiecej instrumentow ma ujemny wynik netto/trade. Trzymaj obecne ograniczenia lub docisnij filtry dla najslabszych par."
    elif daily_pass_runs > 0 and explore_total_trades_latest > 0:
        recommendation = "Tryb uczenia dziala poprawnie. Kontynuuj zbieranie danych i porownuj score per instrument/per okno."
    elif scheduler_status == "SKIP":
        recommendation = "Scheduler pominąl run. Sprawdz powod i uruchom recznie, jesli to nie byl oczekiwany skip."
    else:
        recommendation = "Wymagany przeglad statusu scheduler/ingest oraz logow runtime."

    report = {
        "schema": "oanda_mt5.lab_insights_digest.v2",
        "generated_at_utc": iso_utc(now),
        "status": "PASS",
        "workspace_root": str(root),
        "lab_data_root": str(lab_data_root),
        "interval": {
            "start_utc": iso_utc(start_utc),
            "end_utc": iso_utc(now),
            "hours": hours_span_exact,
            "hours_bucket_3h": hours_bucket_3h,
            "source": interval_source,
        },
        "sources": {
            "external_history_mt5_oanda_tms": True,
            "internal_persisted_system_data": True,
        },
        "snapshot": {
            "scheduler_status": scheduler_status,
            "scheduler_reason": scheduler_reason,
            "latest_ingest_quality_grade": quality_grade_latest,
            "latest_pairs_ready_for_shadow": pairs_ready,
            "latest_pairs_total": pairs_total,
            "latest_explore_total_trades": explore_total_trades_latest,
            "latest_retention_removed_dirs": _safe_int(latest_ret_summary.get("snapshot_dirs_removed")),
            "latest_profile_sweep_status": latest_profile_status,
            "latest_profile_sweep_winner": latest_profile_winner,
            "latest_counterfactual_summary_status": latest_cf_status,
            "latest_counterfactual_rows_total": latest_cf_rows_total,
        },
        "window_aggregate": {
            "ingest_runs": ingest_runs,
            "daily_runs": daily_runs,
            "daily_pass_runs": daily_pass_runs,
            "daily_skip_runs": daily_skip_runs,
            "retention_runs": len(retention_window),
            "profile_sweep_runs": len(profile_window),
            "symbols_processed": sorted(symbols),
            "windows_processed": sorted(windows),
            "rows_fetched_total": rows_fetched,
            "rows_inserted_total": rows_inserted,
            "rows_deduped_total": rows_deduped,
            "gap_events_total": gap_events,
            "invalid_ohlc_total": invalid_ohlc,
            "negative_spread_total": negative_spread,
            "nonpositive_close_total": nonpositive_close,
            "explore_profitable_rows": profitable,
            "explore_losing_rows": losing,
            "explore_neutral_rows": neutral,
            "lab_action_counts": actions_count,
            "best_row": {
                "window_id": str((best_row or {}).get("window_id", "")),
                "symbol": str((best_row or {}).get("symbol", "")),
                "explore_net_pips_per_trade": _safe_float(((best_row or {}).get("explore") or {}).get("net_pips_per_trade")),
            },
            "worst_row": {
                "window_id": str((worst_row or {}).get("window_id", "")),
                "symbol": str((worst_row or {}).get("symbol", "")),
                "explore_net_pips_per_trade": _safe_float(((worst_row or {}).get("explore") or {}).get("net_pips_per_trade")),
            },
            "profile_sweep_latest_runs": [
                {
                    "profile": str(r.get("profile") or "").upper(),
                    "status": str(r.get("status") or "").upper(),
                    "action_hint": str(r.get("action_hint") or "UNKNOWN"),
                    "explore_net_pips_per_trade": _safe_float((r.get("metrics") or {}).get("explore_net_pips_per_trade")),
                    "explore_trades": _safe_int((r.get("metrics") or {}).get("explore_trades")),
                }
                for r in latest_profile_runs
            ],
            "counterfactual_by_symbol_compact": cf_symbol_compact,
            "counterfactual_pln_point_factor_default": float(round(default_pln_per_point, 6)),
        },
        "recommendation": recommendation,
    }

    if str(args.out).strip():
        out_path = Path(args.out).resolve()
    else:
        out_path = (lab_data_root / "reports" / "insights" / f"lab_insights_{stamp}.json").resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    pointer_payload = {
        "schema": "oanda_mt5.lab_insights_pointer.v2",
        "generated_at_utc": report["generated_at_utc"],
        "status": report["status"],
        "report_path": str(out_path),
        "interval": report["interval"],
        "snapshot": report["snapshot"],
        "window_aggregate": report["window_aggregate"],
        "recommendation": report["recommendation"],
    }
    pointer_json.parent.mkdir(parents=True, exist_ok=True)
    pointer_json.write_text(json.dumps(pointer_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    # Human-readable digest for operator panel.
    wa = report["window_aggregate"]
    txt_lines = [
        "WNIOSEK Z LABORATORIUM",
        f"Generated UTC: {report['generated_at_utc']}",
        "",
        "[1] CZAS I ZRODLA",
        "Przez ostatnie {0} godziny pracowalem na danych historycznych pobranych z OANDA TMS (zrodlo zewnetrzne)".format(
            report["interval"]["hours_bucket_3h"]
        ),
        "oraz na danych zapisanych w systemie (zrodlo wewnetrzne).",
        "Okno raportu: {0} -> {1}".format(report["interval"]["start_utc"], report["interval"]["end_utc"]),
        "Dokladny zakres czasu: {0} h".format(report["interval"]["hours"]),
        "",
        "[2] CO ZROBILEM",
        "- Uruchomienia ingestu MT5: {0}".format(wa["ingest_runs"]),
        "- Uruchomienia analizy LAB: {0} (PASS: {1}, SKIP: {2})".format(wa["daily_runs"], wa["daily_pass_runs"], wa["daily_skip_runs"]),
        "- Uruchomienia retencji snapshotow: {0}".format(wa["retention_runs"]),
        "- Instrumenty: {0}".format(", ".join(wa["symbols_processed"]) if wa["symbols_processed"] else "BRAK"),
        "- Okna: {0}".format(", ".join(wa["windows_processed"]) if wa["windows_processed"] else "BRAK"),
        "",
        "[3] JAKOSC DANYCH I UCZENIE",
        "- Wiersze pobrane/wstawione: {0} / {1} (deduplikacja: {2})".format(
            wa["rows_fetched_total"], wa["rows_inserted_total"], wa["rows_deduped_total"]
        ),
        "- Luki danych (gap events): {0}".format(wa["gap_events_total"]),
        "- Anomalie OHLC/spread/close: {0} / {1} / {2}".format(
            wa["invalid_ohlc_total"], wa["negative_spread_total"], wa["nonpositive_close_total"]
        ),
        "- Wiersze explore: zyskowne={0}, stratne={1}, neutralne={2}".format(
            wa["explore_profitable_rows"], wa["explore_losing_rows"], wa["explore_neutral_rows"]
        ),
    ]
    if wa["best_row"]["symbol"]:
        txt_lines.append(
            "- Najlepszy wynik explore netto/trade: {0} {1} ({2:.3f})".format(
                wa["best_row"]["window_id"], wa["best_row"]["symbol"], wa["best_row"]["explore_net_pips_per_trade"]
            )
        )
    if wa["worst_row"]["symbol"]:
        txt_lines.append(
            "- Najslabszy wynik explore netto/trade: {0} {1} ({2:.3f})".format(
                wa["worst_row"]["window_id"], wa["worst_row"]["symbol"], wa["worst_row"]["explore_net_pips_per_trade"]
            )
        )
    txt_lines.append("")
    txt_lines.append("[4] PROFILE STRATEGII (LAB-ONLY)")
    txt_lines.append(
        "- Sweep profile runs (okno): {0}, ostatni status: {1}, zwyciezca: {2}".format(
            wa.get("profile_sweep_runs", 0),
            report["snapshot"].get("latest_profile_sweep_status", "UNKNOWN"),
            report["snapshot"].get("latest_profile_sweep_winner", "UNKNOWN"),
        )
    )
    profile_rows = list(wa.get("profile_sweep_latest_runs") or [])
    if profile_rows:
        for r in profile_rows:
            txt_lines.append(
                "- {0}: action={1}, explore_n={2}, explore_net/trade={3:.3f}".format(
                    str(r.get("profile") or "UNKNOWN"),
                    str(r.get("action_hint") or "UNKNOWN"),
                    _safe_int(r.get("explore_trades")),
                    _safe_float(r.get("explore_net_pips_per_trade")),
                )
            )
    else:
        txt_lines.append("- Brak danych sweep profili w tym oknie.")
    txt_lines.append("")
    txt_lines.append("[5] KONTRFAKTYCZNE WNIOSKI (NO-TRADE -> co by bylo gdyby)")
    txt_lines.append(
        "- Ostatni status podsumowania: {0}, probki: {1}".format(
            report["snapshot"].get("latest_counterfactual_summary_status", "UNKNOWN"),
            report["snapshot"].get("latest_counterfactual_rows_total", 0),
        )
    )
    cf_rows_txt = list(wa.get("counterfactual_by_symbol_compact") or [])
    if cf_rows_txt:
        for r in cf_rows_txt:
            txt_lines.append(
                "- {0}: {1} | {2}".format(
                    str(r.get("symbol") or "UNKNOWN"),
                    _fmt_signed_pln(_safe_float(r.get("counterfactual_pnl_pln_est_total"))),
                    str(r.get("recommendation") or "OBSERWUJ_BEZ_ZMIAN"),
                )
            )
    else:
        txt_lines.append("- Brak danych kontrfaktycznych w tym oknie.")
    txt_lines.extend(
        [
            "",
            "[6] WNIOSEK",
            "- {0}".format(report["recommendation"]),
            "",
            "Pelny raport: {0}".format(out_path),
        ]
    )
    pointer_txt.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

    print(
        json.dumps(
            {
                "status": "PASS",
                "report_path": str(out_path),
                "pointer_path": str(pointer_json),
                "interval_hours": report["interval"]["hours"],
                "interval_hours_bucket_3h": report["interval"]["hours_bucket_3h"],
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
