#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
PROFILE_NAMES = ("BEZPIECZNY", "SREDNI", "ODWAZNIEJSZY")


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def symbol_base(sym: Any) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def safe_float(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except Exception:
        return float(default)


def safe_int(v: Any, default: int = 0) -> int:
    try:
        return int(v)
    except Exception:
        return int(default)


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _find_latest_summary(stage1_reports_dir: Path) -> Optional[Path]:
    files = sorted(
        stage1_reports_dir.glob("stage1_counterfactual_summary_*.json"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    return files[0] if files else None


def _group_defaults(strategy: Dict[str, Any], symbol: str) -> Tuple[float, float]:
    base = symbol_base(symbol)
    if base == "XAUUSD":
        return safe_float(strategy.get("metal_spread_cap_points_default"), 120.0), safe_float(
            strategy.get("metal_signal_score_threshold"), 66.0
        )
    return safe_float(strategy.get("fx_spread_cap_points_default"), 24.0), safe_float(
        strategy.get("fx_signal_score_threshold"), 64.0
    )


def _score_for_profile(
    profile: str,
    *,
    pnl_avg: float,
    saved_ratio: float,
    missed_ratio: float,
) -> float:
    if profile == "BEZPIECZNY":
        return float(pnl_avg + 0.70 * saved_ratio - 0.30 * missed_ratio)
    if profile == "ODWAZNIEJSZY":
        return float(pnl_avg + 0.70 * missed_ratio - 0.55 * saved_ratio)
    return float(pnl_avg + 0.10 * (missed_ratio - saved_ratio))


def _profile_payload(
    profile: str,
    *,
    spread_cap_default: float,
    signal_thr_default: float,
    max_latency_ms: float,
    pnl_avg: float,
    saved_ratio: float,
    missed_ratio: float,
) -> Dict[str, Any]:
    if profile == "BEZPIECZNY":
        spread_mult = 0.88
        signal_delta = +4.0
        tradeability_min = 0.62
        setup_quality_min = 0.62
    elif profile == "ODWAZNIEJSZY":
        spread_mult = 1.14
        signal_delta = -3.0
        tradeability_min = 0.48
        setup_quality_min = 0.48
    else:
        spread_mult = 1.00
        signal_delta = 0.0
        tradeability_min = 0.55
        setup_quality_min = 0.55

    return {
        "profile_name": profile,
        "thresholds": {
            "spread_cap_points": round(spread_cap_default * spread_mult, 3),
            "signal_score_threshold": round(signal_thr_default + signal_delta, 3),
            "max_latency_ms": round(max_latency_ms, 3),
            "min_tradeability_score": round(tradeability_min, 4),
            "min_setup_quality_score": round(setup_quality_min, 4),
        },
        "evaluation": {
            "score_estimate": round(_score_for_profile(profile, pnl_avg=pnl_avg, saved_ratio=saved_ratio, missed_ratio=missed_ratio), 6),
            "evaluation_basis": "counterfactual_summary_v1",
        },
    }


def _build_for_symbol(
    symbol_row: Dict[str, Any],
    strategy: Dict[str, Any],
    *,
    min_samples: int,
    allow_aggressive_when_samples_low: bool,
) -> Dict[str, Any]:
    symbol = symbol_base(symbol_row.get("symbol"))
    samples_n = safe_int(symbol_row.get("samples_n"))
    saved_n = safe_int(symbol_row.get("saved_loss_n"))
    missed_n = safe_int(symbol_row.get("missed_opportunity_n"))
    neutral_n = safe_int(symbol_row.get("neutral_timeout_n"))
    pnl_avg = safe_float(symbol_row.get("counterfactual_pnl_points_avg"))
    pnl_total = safe_float(symbol_row.get("counterfactual_pnl_points_total"))

    denom = float(max(1, samples_n))
    saved_ratio = float(saved_n) / denom
    missed_ratio = float(missed_n) / denom
    neutral_ratio = float(neutral_n) / denom

    spread_cap_default, signal_thr_default = _group_defaults(strategy, symbol)
    max_latency_base = safe_float(strategy.get("bridge_trade_timeout_ms"), 1400.0)
    if symbol == "XAUUSD":
        max_latency_base = max(max_latency_base, 1500.0)

    profiles = {
        "bezpieczny": _profile_payload(
            "BEZPIECZNY",
            spread_cap_default=spread_cap_default,
            signal_thr_default=signal_thr_default,
            max_latency_ms=min(max_latency_base, 850.0),
            pnl_avg=pnl_avg,
            saved_ratio=saved_ratio,
            missed_ratio=missed_ratio,
        ),
        "sredni": _profile_payload(
            "SREDNI",
            spread_cap_default=spread_cap_default,
            signal_thr_default=signal_thr_default,
            max_latency_ms=min(max_latency_base, 950.0),
            pnl_avg=pnl_avg,
            saved_ratio=saved_ratio,
            missed_ratio=missed_ratio,
        ),
        "odwazniejszy": _profile_payload(
            "ODWAZNIEJSZY",
            spread_cap_default=spread_cap_default,
            signal_thr_default=signal_thr_default,
            max_latency_ms=min(max_latency_base, 1100.0),
            pnl_avg=pnl_avg,
            saved_ratio=saved_ratio,
            missed_ratio=missed_ratio,
        ),
    }

    if samples_n < min_samples and not allow_aggressive_when_samples_low:
        profiles["odwazniejszy"]["eligibility"] = {
            "status": "HOLD_LOW_SAMPLES",
            "samples_n": samples_n,
            "min_required": min_samples,
        }

    ranked = sorted(
        profiles.values(),
        key=lambda p: safe_float(((p.get("evaluation") or {}).get("score_estimate"))),
        reverse=True,
    )
    recommended = str((ranked[0].get("profile_name") if ranked else "SREDNI")).upper()
    if samples_n < min_samples and recommended == "ODWAZNIEJSZY" and not allow_aggressive_when_samples_low:
        recommended = "SREDNI"

    return {
        "symbol": symbol,
        "samples_n": samples_n,
        "saved_loss_n": saved_n,
        "missed_opportunity_n": missed_n,
        "neutral_timeout_n": neutral_n,
        "counterfactual_pnl_points_total": round(pnl_total, 6),
        "counterfactual_pnl_points_avg": round(pnl_avg, 6),
        "saved_ratio": round(saved_ratio, 6),
        "missed_ratio": round(missed_ratio, 6),
        "neutral_ratio": round(neutral_ratio, 6),
        "recommendation_for_tomorrow": {
            "recommended_profile": recommended,
            "human_decision_required": True,
            "auto_apply": False,
        },
        "profiles": profiles,
    }


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_PROFILE_PACK")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append(f"Source summary: {report.get('counterfactual_summary_source')}")
    lines.append("")
    for item in report.get("profiles_by_symbol", []):
        lines.append(
            "- {0}: N={1} avg_pts={2:.3f} saved={3} missed={4} rec={5}".format(
                item.get("symbol"),
                safe_int(item.get("samples_n")),
                safe_float(item.get("counterfactual_pnl_points_avg")),
                safe_int(item.get("saved_loss_n")),
                safe_int(item.get("missed_opportunity_n")),
                ((item.get("recommendation_for_tomorrow") or {}).get("recommended_profile") or "UNKNOWN"),
            )
        )
    lines.append("")
    lines.append("UWAGA: proposal only / auto_apply=false")
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build per-symbol tomorrow profile pack (safe/medium/aggressive) from Stage-1 reports.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--counterfactual-summary", default="")
    ap.add_argument("--strategy-path", default="")
    ap.add_argument("--min-samples", type=int, default=30)
    ap.add_argument("--allow-aggressive-when-samples-low", action="store_true")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_PROFILE_PACK_{stamp}"

    summary_path = (
        Path(args.counterfactual_summary).resolve()
        if str(args.counterfactual_summary).strip()
        else _find_latest_summary(stage1_reports)
    )
    strategy_path = Path(args.strategy_path).resolve() if str(args.strategy_path).strip() else (root / "CONFIG" / "strategy.json").resolve()
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_profile_pack_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "COUNTERFACTUAL_SUMMARY_MISSING"
    profiles_by_symbol: List[Dict[str, Any]] = []
    cf_hash = ""
    if summary_path is not None and summary_path.exists():
        payload = load_json(summary_path)
        by_symbol = (((payload.get("aggregates") or {}).get("by_symbol")) or [])
        if isinstance(by_symbol, list) and by_symbol:
            strategy = load_json(strategy_path) if strategy_path.exists() else {}
            for row in by_symbol:
                if not isinstance(row, dict):
                    continue
                entry = _build_for_symbol(
                    row,
                    strategy,
                    min_samples=max(1, int(args.min_samples)),
                    allow_aggressive_when_samples_low=bool(args.allow_aggressive_when_samples_low),
                )
                if str(entry.get("symbol") or "").strip():
                    profiles_by_symbol.append(entry)
            if profiles_by_symbol:
                status = "PASS"
                reason = "PROFILE_PACK_READY"
                try:
                    cf_hash = file_sha256(summary_path)
                except Exception:
                    cf_hash = ""
            else:
                reason = "NO_VALID_SYMBOLS"
        else:
            reason = "COUNTERFACTUAL_SUMMARY_EMPTY"

    report = {
        "schema": "oanda.mt5.stage1_profile_pack.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "counterfactual_summary_source": str(summary_path) if summary_path is not None else "",
        "counterfactual_summary_hash": cf_hash,
        "strategy_source": str(strategy_path),
        "min_samples": int(max(1, int(args.min_samples))),
        "profiles_by_symbol": profiles_by_symbol,
        "notes": [
            "Autonomous apply disabled: proposal only.",
            "Human review required before any runtime change.",
            "No runtime execution path mutation.",
        ],
    }

    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")

    latest_json = ensure_write_parent(
        (stage1_reports / "stage1_profile_pack_latest.json").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_txt = ensure_write_parent(
        (stage1_reports / "stage1_profile_pack_latest.txt").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash(
            {
                "tool": "stage1_profile_pack.v1",
                "min_samples": int(max(1, int(args.min_samples))),
                "allow_aggressive_when_samples_low": bool(args.allow_aggressive_when_samples_low),
            }
        )
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_PROFILE_PACK",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": cf_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"symbols_n": len(profiles_by_symbol)}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_PROFILE_PACK_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
