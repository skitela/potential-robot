#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc


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


def _find_latest_report(dir_path: Path, pattern: str) -> Optional[Path]:
    files = sorted(dir_path.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _find_latest_profile_pack(stage1_reports_dir: Path) -> Optional[Path]:
    return _find_latest_report(stage1_reports_dir, "stage1_profile_pack_*.json")


def _find_latest_shadow_report(shadow_reports_dir: Path) -> Optional[Path]:
    baseline = sorted(shadow_reports_dir.glob("shadow_policy_baseline_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in baseline:
        try:
            payload = load_json(p)
            if str(payload.get("status") or "").upper() == "PASS":
                return p
        except Exception:
            continue
    any_reports = sorted(shadow_reports_dir.glob("shadow_policy_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in any_reports:
        try:
            payload = load_json(p)
            if str(payload.get("status") or "").upper() == "PASS":
                return p
        except Exception:
            continue
    return None


def _shadow_metrics_by_symbol(shadow_payload: Dict[str, Any]) -> Dict[str, Dict[str, float]]:
    rows = (((shadow_payload.get("results_per_day_window_symbol") or {}).get("explore")) or [])
    if not isinstance(rows, list):
        rows = []
    by_symbol: Dict[str, Dict[str, Any]] = defaultdict(
        lambda: {"trades": 0, "net_pips_sum": 0.0, "per_trade_values": []}
    )
    for row in rows:
        if not isinstance(row, dict):
            continue
        sym = symbol_base(row.get("symbol"))
        if not sym:
            continue
        trades = max(0, safe_int(row.get("trades")))
        net_sum = safe_float(row.get("net_pips_sum"))
        net_pt = safe_float(row.get("net_pips_per_trade"))
        b = by_symbol[sym]
        b["trades"] = int(b["trades"]) + trades
        b["net_pips_sum"] = float(b["net_pips_sum"]) + net_sum
        if trades > 0:
            b["per_trade_values"].append(net_pt)

    out: Dict[str, Dict[str, float]] = {}
    for sym, agg in by_symbol.items():
        trades = max(0, safe_int(agg.get("trades")))
        net_sum = safe_float(agg.get("net_pips_sum"))
        per_values = agg.get("per_trade_values") if isinstance(agg.get("per_trade_values"), list) else []
        net_pt = (net_sum / float(trades)) if trades > 0 else 0.0
        if len(per_values) >= 2:
            mean_v = sum(float(x) for x in per_values) / float(len(per_values))
            var = sum((float(x) - mean_v) ** 2 for x in per_values) / float(len(per_values))
            std = math.sqrt(max(0.0, var))
        else:
            std = 0.0
        stability = 1.0 / (1.0 + (std / 10.0))
        out[sym] = {
            "shadow_trades_n": float(trades),
            "shadow_net_pips_sum": float(round(net_sum, 6)),
            "shadow_net_pips_per_trade": float(round(net_pt, 6)),
            "shadow_stability_score": float(round(stability, 6)),
        }
    return out


def _normalize_shadow_net(net_pips_per_trade: float) -> float:
    clipped = max(-20.0, min(20.0, float(net_pips_per_trade)))
    return float(clipped / 20.0)


def _profile_bias(profile_name: str) -> float:
    p = str(profile_name or "").upper()
    if p == "BEZPIECZNY":
        return 0.08
    if p == "ODWAZNIEJSZY":
        return -0.08
    return 0.02


def _evaluate_profile(
    *,
    profile_payload: Dict[str, Any],
    shadow: Dict[str, float],
) -> Dict[str, Any]:
    eval_obj = profile_payload.get("evaluation") if isinstance(profile_payload.get("evaluation"), dict) else {}
    score_est = safe_float(eval_obj.get("score_estimate"))
    score_norm = max(-1.0, min(1.0, score_est / 100.0))
    profile_name = str(profile_payload.get("profile_name") or "").upper()

    shadow_trades = max(0.0, safe_float(shadow.get("shadow_trades_n")))
    reliability = min(1.0, shadow_trades / 10.0)
    shadow_net_norm = _normalize_shadow_net(safe_float(shadow.get("shadow_net_pips_per_trade")))
    shadow_stability = max(0.0, min(1.0, safe_float(shadow.get("shadow_stability_score"), 0.5)))
    shadow_component = reliability * (0.70 * shadow_net_norm + 0.30 * ((2.0 * shadow_stability) - 1.0))
    final_score = 0.65 * score_norm + 0.25 * shadow_component + 0.10 * _profile_bias(profile_name)

    return {
        "profile_name": profile_name,
        "base_score_estimate": float(round(score_est, 6)),
        "base_score_normalized": float(round(score_norm, 6)),
        "shadow_component": float(round(shadow_component, 6)),
        "shadow_reliability": float(round(reliability, 6)),
        "final_score": float(round(final_score, 6)),
    }


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_PROFILE_PACK_EVALUATION")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append(f"Profile pack source: {report.get('profile_pack_source')}")
    lines.append(f"Shadow source: {report.get('shadow_report_source')}")
    lines.append("")
    for row in report.get("evaluation_by_symbol", []):
        rec = ((row.get("recommendation_for_tomorrow") or {}).get("recommended_profile") or "UNKNOWN")
        sh = row.get("shadow") if isinstance(row.get("shadow"), dict) else {}
        lines.append(
            "- {0}: rec={1} shadow_trades={2} shadow_net_pt={3:.3f}".format(
                row.get("symbol"),
                rec,
                safe_int(sh.get("shadow_trades_n")),
                safe_float(sh.get("shadow_net_pips_per_trade")),
            )
        )
        ranks = row.get("ranking") if isinstance(row.get("ranking"), list) else []
        for item in ranks:
            if not isinstance(item, dict):
                continue
            lines.append(
                "    * {0}: final={1:.4f} base={2:.4f} shadow={3:.4f}".format(
                    item.get("profile_name"),
                    safe_float(item.get("final_score")),
                    safe_float(item.get("base_score_estimate")),
                    safe_float(item.get("shadow_component")),
                )
            )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Evaluate Stage-1 profile pack with history+shadow ranking (proposal only).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--profile-pack", default="")
    ap.add_argument("--shadow-report", default="")
    ap.add_argument("--min-shadow-trades", type=int, default=3)
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    shadow_reports = (lab_data_root / "reports" / "shadow_policy").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_PROFILE_EVAL_{stamp}"

    profile_pack_path = Path(args.profile_pack).resolve() if str(args.profile_pack).strip() else _find_latest_profile_pack(stage1_reports)
    shadow_report_path = Path(args.shadow_report).resolve() if str(args.shadow_report).strip() else _find_latest_shadow_report(shadow_reports)
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_profile_pack_eval_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "PROFILE_PACK_MISSING"
    evaluation_by_symbol: List[Dict[str, Any]] = []
    profile_pack_hash = ""
    shadow_hash = ""

    if profile_pack_path is None or not profile_pack_path.exists():
        reason = "PROFILE_PACK_MISSING"
    else:
        profile_pack = load_json(profile_pack_path)
        shadow_payload: Dict[str, Any] = {}
        if shadow_report_path is not None and shadow_report_path.exists():
            try:
                shadow_payload = load_json(shadow_report_path)
                shadow_hash = file_sha256(shadow_report_path)
            except Exception:
                shadow_payload = {}
        shadow_metrics = _shadow_metrics_by_symbol(shadow_payload) if shadow_payload else {}
        try:
            profile_pack_hash = file_sha256(profile_pack_path)
        except Exception:
            profile_pack_hash = ""

        rows = profile_pack.get("profiles_by_symbol") if isinstance(profile_pack.get("profiles_by_symbol"), list) else []
        for row in rows:
            if not isinstance(row, dict):
                continue
            sym = symbol_base(row.get("symbol"))
            if not sym:
                continue
            profiles = row.get("profiles") if isinstance(row.get("profiles"), dict) else {}
            shadow = shadow_metrics.get(
                sym,
                {
                    "shadow_trades_n": 0.0,
                    "shadow_net_pips_sum": 0.0,
                    "shadow_net_pips_per_trade": 0.0,
                    "shadow_stability_score": 0.5,
                },
            )
            ranks: List[Dict[str, Any]] = []
            for _, profile_payload in profiles.items():
                if not isinstance(profile_payload, dict):
                    continue
                ranks.append(_evaluate_profile(profile_payload=profile_payload, shadow=shadow))
            ranks.sort(key=lambda x: safe_float(x.get("final_score")), reverse=True)

            rec = "SREDNI"
            if ranks:
                rec = str(ranks[0].get("profile_name") or "SREDNI").upper()
                if rec == "ODWAZNIEJSZY" and safe_int(shadow.get("shadow_trades_n")) < max(1, int(args.min_shadow_trades)):
                    rec = "SREDNI"
                if rec == "ODWAZNIEJSZY" and safe_float(shadow.get("shadow_net_pips_per_trade")) <= 0.0:
                    rec = "SREDNI"
            evaluation_by_symbol.append(
                {
                    "symbol": sym,
                    "shadow": shadow,
                    "ranking": ranks,
                    "recommendation_for_tomorrow": {
                        "recommended_profile": rec,
                        "human_decision_required": True,
                        "auto_apply": False,
                        "guard_reason": (
                            "LOW_SHADOW_TRADES_FOR_AGGRESSIVE"
                            if rec == "SREDNI"
                            and ranks
                            and str(ranks[0].get("profile_name") or "").upper() == "ODWAZNIEJSZY"
                            and safe_int(shadow.get("shadow_trades_n")) < max(1, int(args.min_shadow_trades))
                            else (
                                "NEGATIVE_SHADOW_NET_FOR_AGGRESSIVE"
                                if rec == "SREDNI"
                                and ranks
                                and str(ranks[0].get("profile_name") or "").upper() == "ODWAZNIEJSZY"
                                and safe_float(shadow.get("shadow_net_pips_per_trade")) <= 0.0
                                else "OK"
                            )
                        ),
                    },
                }
            )

        if evaluation_by_symbol:
            status = "PASS"
            reason = "EVALUATION_READY"
        else:
            status = "SKIP"
            reason = "NO_SYMBOLS_IN_PROFILE_PACK"

    report = {
        "schema": "oanda.mt5.stage1_profile_pack_eval.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "profile_pack_source": str(profile_pack_path) if profile_pack_path is not None else "",
        "profile_pack_hash": profile_pack_hash,
        "shadow_report_source": str(shadow_report_path) if shadow_report_path is not None else "",
        "shadow_report_hash": shadow_hash,
        "params": {
            "min_shadow_trades": int(max(1, int(args.min_shadow_trades))),
        },
        "evaluation_by_symbol": evaluation_by_symbol,
        "notes": [
            "Proposal-only ranking. No runtime mutation.",
            "History from Stage-1 profile pack + shadow metrics from shadow_policy report.",
            "Human review required before any profile switch.",
        ],
    }

    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")

    latest_json = ensure_write_parent(
        (stage1_reports / "stage1_profile_pack_eval_latest.json").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_txt = ensure_write_parent(
        (stage1_reports / "stage1_profile_pack_eval_latest.txt").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash(report.get("params") if isinstance(report.get("params"), dict) else {})
        ds_hash = profile_pack_hash
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_PROFILE_EVAL",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": ds_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"symbols_n": len(evaluation_by_symbol)}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception:
        pass

    print(f"STAGE1_PROFILE_PACK_EVAL_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
