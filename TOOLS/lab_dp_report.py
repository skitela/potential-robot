#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def find_latest_bridge_report(root: Path) -> Optional[Path]:
    p = (root / "EVIDENCE" / "bridge_audit").resolve()
    if not p.exists():
        return None
    items = [x for x in p.glob("bridge_soak_compare_*.json") if x.is_file()]
    if not items:
        return None
    items.sort(key=lambda x: x.stat().st_mtime, reverse=True)
    return items[0]


def _f(val: Any, default: float = 0.0) -> float:
    try:
        return float(val)
    except Exception:
        return float(default)


def build_recommendations(metrics: Dict[str, Any]) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    bw = metrics.get("bridge_wait") or {}
    p95 = _f(bw.get("p95_ms"), 0.0)
    p99 = _f(bw.get("p99_ms"), 0.0)
    timeout_rate = _f(metrics.get("timeout_rate_all", metrics.get("timeout_rate", 0.0)), 0.0)
    decision = metrics.get("decision_core") or {}
    decision_n = int(decision.get("n") or 0)

    if p95 >= 700.0:
        out.append(
            {
                "type_primary": "DP",
                "type_change": "L",
                "readiness": "HOLD",
                "summary": "bridge_wait p95 przekracza cel inżynierski",
                "reason": "BRIDGE_WAIT_P95_HIGH",
                "touches_hot_path": True,
                "review_required": True,
            }
        )
    if p99 >= 850.0:
        out.append(
            {
                "type_primary": "DP",
                "type_change": "L",
                "readiness": "HOLD",
                "summary": "bridge_wait p99 przekracza cel inżynierski",
                "reason": "BRIDGE_WAIT_P99_HIGH",
                "touches_hot_path": True,
                "review_required": True,
            }
        )
    if timeout_rate > 0.05:
        out.append(
            {
                "type_primary": "DP",
                "type_change": "L",
                "readiness": "HOLD",
                "summary": "timeout-rate za wysoki dla hot path",
                "reason": "TIMEOUT_RATE_HIGH",
                "touches_hot_path": True,
                "review_required": True,
            }
        )
    if decision_n < 30:
        out.append(
            {
                "type_primary": "DP",
                "type_change": "L",
                "readiness": "LAB_ONLY",
                "summary": "za mała próbka decision_core do twardego werdyktu",
                "reason": "DECISION_CORE_LOW_SAMPLE",
                "touches_hot_path": False,
                "review_required": False,
            }
        )
    if not out:
        out.append(
            {
                "type_primary": "DP",
                "type_change": "L",
                "readiness": "SHADOW_CANDIDATE",
                "summary": "metryki DP w granicach celu inżynierskiego",
                "reason": "DP_TARGETS_MET",
                "touches_hot_path": False,
                "review_required": True,
            }
        )
    return out


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate LAB DP (Decision Path) report from existing bridge telemetry.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--bridge-report", default="")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")

    bridge_report_path = (
        Path(args.bridge_report).resolve()
        if str(args.bridge_report).strip()
        else find_latest_bridge_report(root)
    )
    if bridge_report_path is None or not bridge_report_path.exists():
        raise FileNotFoundError("No bridge soak comparison report found for DP analysis.")

    bridge = load_json(bridge_report_path)
    metrics = ((bridge.get("after_soak_window") or {}).get("metrics") or {})
    reasons = ((bridge.get("after_soak_window") or {}).get("reasons") or {})
    recs = build_recommendations(metrics)

    report = {
        "schema": "oanda_mt5.lab_dp_report.v1",
        "generated_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "source_bridge_report": str(bridge_report_path),
        "dp_metrics": {
            "bridge_send": metrics.get("bridge_send") or {},
            "bridge_wait": metrics.get("bridge_wait") or {},
            "bridge_parse": metrics.get("bridge_parse") or {},
            "timeout_rate_all": metrics.get("timeout_rate_all", metrics.get("timeout_rate")),
            "timeout_rate_heartbeat": metrics.get("timeout_rate_heartbeat"),
            "timeout_rate_trade_path": metrics.get("timeout_rate_trade_path"),
            "decision_core": metrics.get("decision_core") or {},
            "full_loop": metrics.get("full_loop") or {},
        },
        "timeout_reason_top": (reasons.get("bridge_timeout_reason_top") or [])[:10],
        "timeout_reason_by_command_type": (reasons.get("bridge_timeout_reason_by_command_type") or [])[:10],
        "timeout_reason_by_timeout_budget_ms": (reasons.get("bridge_timeout_reason_by_timeout_budget_ms") or [])[:10],
        "recommendations": recs,
        "notes": [
            "MVP DP bazuje na istniejącej telemetryce bridge_audit.",
            "To nie jest pełny profiler kodu hot-path; rekomendacje mają status roboczy.",
        ],
    }

    if str(args.out).strip():
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = (root / out_path).resolve()
    else:
        out_path = (lab_data_root / "reports" / "dp" / f"lab_dp_report_{stamp}.json").resolve()
    out_path = ensure_write_parent(out_path, root=root, lab_data_root=lab_data_root)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    txt = [
        "LAB_DP_REPORT",
        f"Generated UTC: {report['generated_at_utc']}",
        f"Source bridge report: {bridge_report_path}",
        "",
        "METRICS",
        f"- bridge_wait_p95_ms: {((report['dp_metrics'].get('bridge_wait') or {}).get('p95_ms'))}",
        f"- bridge_wait_p99_ms: {((report['dp_metrics'].get('bridge_wait') or {}).get('p99_ms'))}",
        f"- timeout_rate_all: {report['dp_metrics'].get('timeout_rate_all')}",
        f"- decision_core_n: {((report['dp_metrics'].get('decision_core') or {}).get('n'))}",
        "",
        "RECOMMENDATIONS",
    ]
    for rec in recs:
        txt.append(
            f"- {rec.get('type_primary')}+{rec.get('type_change')} readiness={rec.get('readiness')} "
            f"reason={rec.get('reason')} summary={rec.get('summary')}"
        )
    out_path.with_suffix(".txt").write_text("\n".join(txt) + "\n", encoding="utf-8")

    print(f"LAB_DP_REPORT_OK out={out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
