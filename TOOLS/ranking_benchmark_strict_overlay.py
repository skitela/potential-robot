#!/usr/bin/env python
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any

UTC = dt.UTC
ROOT = Path(__file__).resolve().parents[1]
SCHEMA_PATH = ROOT / "SCHEMAS" / "ranking_benchmark_strict_overlay_v1.json"
DEFAULT_TRADING_WORKERS = {"scud_once", "db_writer", "dyrygent_trace"}
DEFAULT_ORCHESTRATION_WORKERS = {"dyrygent_external", "dyrygent_scan", "learner_once"}


def _now_utc() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8", errors="replace") or "{}")


def _latest_file(pattern: str, base: Path) -> Path | None:
    files = sorted(base.glob(pattern), key=lambda p: p.stat().st_mtime)
    return files[-1] if files else None


def _ok(ok: bool, value: Any, threshold: Any, code: str, note: str = "") -> dict[str, Any]:
    return {
        "check_id": code,
        "ok": bool(ok),
        "value": value,
        "threshold": threshold,
        "note": note,
    }


def _is_runtime_code_path(path_str: str) -> bool:
    path = path_str.upper().replace("/", "\\")
    return (
        "\\BIN\\" in path
        or "\\MQL5\\" in path
        or "\\CONFIG\\" in path
    )


def _split_latency_profile(stress_report: dict[str, Any]) -> dict[str, Any]:
    workers = dict(stress_report.get("workers") or {})

    def _bucket(names: set[str]) -> dict[str, Any]:
        rows: list[dict[str, Any]] = []
        for n in sorted(names):
            w = dict(workers.get(n) or {})
            if not w:
                continue
            rows.append(
                {
                    "worker": n,
                    "ok_runs": int(w.get("ok_runs") or 0),
                    "latency_p50_sec": float(w.get("latency_p50_sec") or 0.0),
                    "latency_p95_sec": float(w.get("latency_p95_sec") or 0.0),
                }
            )
        if not rows:
            return {
                "workers": [],
                "latency_p50_sec_weighted": "UNKNOWN",
                "latency_p95_sec_weighted": "UNKNOWN",
                "latency_p50_sec_max": "UNKNOWN",
                "latency_p95_sec_max": "UNKNOWN",
            }
        total_w = sum(max(1, int(r["ok_runs"])) for r in rows)
        p50_w = sum(float(r["latency_p50_sec"]) * max(1, int(r["ok_runs"])) for r in rows) / float(total_w)
        p95_w = sum(float(r["latency_p95_sec"]) * max(1, int(r["ok_runs"])) for r in rows) / float(total_w)
        return {
            "workers": rows,
            "latency_p50_sec_weighted": round(float(p50_w), 6),
            "latency_p95_sec_weighted": round(float(p95_w), 6),
            "latency_p50_sec_max": round(max(float(r["latency_p50_sec"]) for r in rows), 6),
            "latency_p95_sec_max": round(max(float(r["latency_p95_sec"]) for r in rows), 6),
        }

    return {
        "trading_path": _bucket(DEFAULT_TRADING_WORKERS),
        "orchestration_path": _bucket(DEFAULT_ORCHESTRATION_WORKERS),
    }


def evaluate(bench: dict[str, Any], stress: dict[str, Any], policy: dict[str, Any], stress_detailed: dict[str, Any] | None = None) -> dict[str, Any]:
    thr = dict(policy.get("thresholds") or {})
    criteria = dict(((bench.get("gh_v1") or {}).get("criteria")) or {})
    signals = dict(((bench.get("gh_v1") or {}).get("signals")) or {})
    prelive = dict(((bench.get("gh_v1") or {}).get("prelive")) or {})
    go_nogo = dict(bench.get("go_nogo") or {})
    stress_metrics = dict(stress.get("metrics") or {})

    checks: list[dict[str, Any]] = []

    score = float(((bench.get("gh_v1") or {}).get("score_100")) or 0.0)
    min_score = float(thr.get("min_score_100") or 0.0)
    target_top = float(thr.get("min_score_top_target_100") or 0.0)
    checks.append(_ok(score >= min_score, round(score, 2), min_score, "SCORE_MIN"))
    checks.append(_ok(score >= target_top, round(score, 2), target_top, "SCORE_TOP_TARGET"))

    require_prelive = bool(thr.get("require_prelive_go", True))
    prelive_go = bool(prelive.get("go"))
    checks.append(_ok((not require_prelive) or prelive_go, prelive_go, require_prelive, "PRELIVE_GO_REQUIRED"))

    for cid, min_v in dict(thr.get("min_criteria_0_10") or {}).items():
        score_v = float((criteria.get(cid) or {}).get("score_0_10") or 0.0)
        checks.append(_ok(score_v >= float(min_v), round(score_v, 2), float(min_v), f"CRITERION_{cid}"))

    code_hits = list(signals.get("hardcoded_runtime_code_hits") or [])
    max_code_hits = int(thr.get("max_code_hardcoded_path_hits") or 0)
    checks.append(_ok(len(code_hits) <= max_code_hits, len(code_hits), max_code_hits, "CODE_HARDCODED_PATH_HITS"))

    p50 = float(stress_metrics.get("stress_latency_p50_sec") or 0.0)
    p95 = float(stress_metrics.get("stress_latency_p95_sec") or 0.0)
    tmo = int(stress_metrics.get("stress_timeout_count") or 0)
    crash = int(stress_metrics.get("stress_crash_count") or 0)
    dead = int(stress_metrics.get("stress_deadlock_suspect_count") or 0)
    checks.append(_ok(p50 <= float(thr.get("stress_max_latency_p50_sec") or 0.0), round(p50, 6), float(thr.get("stress_max_latency_p50_sec") or 0.0), "STRESS_P50"))
    checks.append(_ok(p95 <= float(thr.get("stress_max_latency_p95_sec") or 0.0), round(p95, 6), float(thr.get("stress_max_latency_p95_sec") or 0.0), "STRESS_P95"))
    checks.append(_ok(tmo <= int(thr.get("stress_timeout_count_max") or 0), tmo, int(thr.get("stress_timeout_count_max") or 0), "STRESS_TIMEOUTS"))
    checks.append(_ok(crash <= int(thr.get("stress_crash_count_max") or 0), crash, int(thr.get("stress_crash_count_max") or 0), "STRESS_CRASH"))
    checks.append(_ok(dead <= int(thr.get("stress_deadlock_suspect_count_max") or 0), dead, int(thr.get("stress_deadlock_suspect_count_max") or 0), "STRESS_DEADLOCK"))

    pass_all = all(bool(c["ok"]) for c in checks)
    blockers = [c["check_id"] for c in checks if not bool(c["ok"])]

    vps_recommendation = {
        "recommended": bool(p95 > float(thr.get("stress_max_latency_p95_sec") or 0.0)),
        "reason": (
            "Local jitter/latency p95 above strict threshold; VPS near broker can reduce tail-latency."
            if p95 > float(thr.get("stress_max_latency_p95_sec") or 0.0)
            else "Local latency tail within strict threshold."
        ),
        "local_laptop_constraint_ack": True,
    }

    latency_split = _split_latency_profile(stress_detailed or {})

    return {
        "schema": "oanda_mt5.ranking_benchmark_strict_overlay.v1",
        "ts_utc": _now_utc(),
        "status": ("PASS" if pass_all else "FAIL"),
        "checks": checks,
        "blockers": blockers,
        "summary": {
            "score_100": round(score, 2),
            "segment": str(((bench.get("gh_v1") or {}).get("segment")) or "UNKNOWN"),
            "go_nogo_status": str(go_nogo.get("status") or "UNKNOWN"),
            "prelive_go": prelive_go,
            "code_hardcoded_path_hits": len(code_hits),
            "stress_latency_p50_sec": round(p50, 6),
            "stress_latency_p95_sec": round(p95, 6),
        },
        "latency_split_diagnostics": latency_split,
        "vps_recommendation": vps_recommendation,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Strict overlay for ranking benchmark V1.")
    ap.add_argument("--root", default=str(ROOT), help="Repo/runtime root.")
    ap.add_argument("--benchmark-json", default="", help="Path to ranking_benchmark_v1 json (latest if empty).")
    ap.add_argument("--stress-json", default="", help="Path to HARD_XCROSS_SUMMARY.json (latest/default if empty).")
    ap.add_argument("--out", default="", help="Output JSON path.")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    evidence = root / "EVIDENCE"

    benchmark_path = Path(args.benchmark_json).resolve() if str(args.benchmark_json).strip() else _latest_file("ranking_benchmark_v1_*.json", evidence)
    if benchmark_path is None or not benchmark_path.exists():
        raise SystemExit("BENCHMARK_JSON_MISSING")

    if str(args.stress_json).strip():
        stress_path = Path(args.stress_json).resolve()
    else:
        stress_path = (evidence / "HARD_XCROSS_SUMMARY.json")
        if not stress_path.exists():
            latest = _latest_file("*XROSS*SUMMARY*.json", evidence)
            stress_path = latest if latest is not None else stress_path
    if not stress_path.exists():
        raise SystemExit("STRESS_JSON_MISSING")

    policy = _load_json(SCHEMA_PATH)
    bench = _load_json(benchmark_path)
    stress = _load_json(stress_path)
    stress_detailed_path = (root / "EVIDENCE" / "03_stress" / "stress_report.json")
    stress_detailed = _load_json(stress_detailed_path) if stress_detailed_path.exists() else {}
    report = evaluate(bench, stress, policy, stress_detailed=stress_detailed)
    report["inputs"] = {
        "benchmark_json": str(benchmark_path),
        "stress_json": str(stress_path),
        "stress_detailed_json": str(stress_detailed_path) if stress_detailed_path.exists() else "MISSING",
        "policy_json": str(SCHEMA_PATH),
    }

    out_path = Path(args.out).resolve() if str(args.out).strip() else (evidence / f"ranking_benchmark_strict_overlay_{dt.datetime.now(tz=UTC).strftime('%Y%m%dT%H%M%SZ')}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print(
        "RANKING_BENCHMARK_STRICT_OVERLAY_DONE | "
        f"status={report['status']} | score={report['summary']['score_100']:.2f} | "
        f"p95={report['summary']['stress_latency_p95_sec']:.6f}s | out={out_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
