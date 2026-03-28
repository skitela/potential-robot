from __future__ import annotations

import argparse
import csv
from pathlib import Path
from typing import Any

from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import load_paper_live_bucket_for_symbol, load_scalping_universe_plan, load_training_universe_symbols
from mb_ml_supervision.audits import load_active_registry_symbols
from mb_ml_supervision.io_utils import dump_json, read_json, utc_now_iso
from mb_ml_supervision.paths import OverlayPaths


THRESHOLD_KEYS = [
    "min_gate_probability",
    "min_decision_score_pln",
    "max_spread_points",
    "max_server_ping_ms",
    "max_server_latency_us_avg",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Standalone audit parytetu realizmu brokera laptop <-> runtime MT5.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\broker_realism_parity_audit_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\broker_realism_parity_audit_latest.md")
    return parser.parse_args()


def _read_runtime_contract(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle):
            if len(row) >= 2:
                values[str(row[0]).strip()] = str(row[1]).strip()
    return values


def _parse_package_thresholds(payload: Any) -> dict[str, float]:
    defaults = {
        "min_gate_probability": 0.53,
        "min_decision_score_pln": 0.0,
        "max_spread_points": 999.0,
        "max_server_ping_ms": 35.0,
        "max_server_latency_us_avg": 250000.0,
    }
    if not isinstance(payload, dict):
        return defaults
    threshold_payload = payload.get("decision_thresholds")
    if isinstance(threshold_payload, dict):
        for key in THRESHOLD_KEYS:
            try:
                defaults[key] = float(threshold_payload.get(key, defaults[key]))
            except Exception:
                pass
    return defaults


def _load_outcome_rows(paths: OverlayPaths) -> dict[str, dict[str, Any]]:
    payload = read_json(paths.outcome_closure_audit_path, default={})
    if not isinstance(payload, dict):
        return {}
    rows = payload.get("items", [])
    if not isinstance(rows, list):
        return {}
    out: dict[str, dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        symbol = str(row.get("symbol_alias") or "").strip()
        if symbol:
            out[symbol] = row
    return out


def _threshold_mismatch(package_thresholds: dict[str, float], runtime_contract: dict[str, str]) -> list[str]:
    mismatches: list[str] = []
    for key in THRESHOLD_KEYS:
        try:
            runtime_value = float(runtime_contract.get(key, "nan"))
        except Exception:
            mismatches.append(key)
            continue
        if abs(runtime_value - package_thresholds[key]) > 1e-9:
            mismatches.append(key)
    return mismatches


def main() -> int:
    args = parse_args()
    paths = OverlayPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=args.common_state_root,
    )
    compat_paths = CompatPaths.create(
        project_root=args.project_root,
        research_root=args.research_root,
        common_state_root=paths.runtime_root,
    )

    universe_plan = load_scalping_universe_plan(compat_paths)
    training_universe = load_training_universe_symbols(compat_paths)
    registry_rows = load_active_registry_symbols(paths)
    registry_by_symbol = {str(row["symbol"]).strip(): row for row in registry_rows if str(row.get("symbol") or "").strip()}
    package_payload = read_json(paths.package_json_path, default={})
    package_thresholds = _parse_package_thresholds(package_payload)
    outcome_rows = _load_outcome_rows(paths)

    items: list[dict[str, Any]] = []
    reason_counts: dict[str, int] = {}
    for symbol in training_universe:
        runtime_contract_path = paths.runtime_symbol_state_root / symbol / "student_gate_contract.csv"
        runtime_contract = _read_runtime_contract(runtime_contract_path)
        bucket_expected = load_paper_live_bucket_for_symbol(compat_paths, symbol)
        runtime_scope_expected = "PAPER_LIVE" if bucket_expected == "FIRST_WAVE" else "LAPTOP_ONLY"
        runtime_bucket = runtime_contract.get("paper_live_bucket", "")
        runtime_scope = runtime_contract.get("runtime_scope", "")
        threshold_mismatches = _threshold_mismatch(package_thresholds, runtime_contract) if runtime_contract else THRESHOLD_KEYS.copy()
        ledger_row = outcome_rows.get(symbol, {})
        reasons: list[str] = []

        if int(ledger_row.get("spread_rows", 0) or 0) <= 0:
            reasons.append("SPREAD_GAP")
        if int(ledger_row.get("slippage_rows", 0) or 0) <= 0:
            reasons.append("SLIPPAGE_GAP")
        if int(ledger_row.get("commission_rows", 0) or 0) <= 0:
            reasons.append("COMMISSION_GAP")
        if int(ledger_row.get("swap_rows", 0) or 0) <= 0:
            reasons.append("SWAP_GAP")
        if threshold_mismatches:
            reasons.append("PRECHECK_THRESHOLD_MISMATCH")
        if not str(registry_by_symbol.get(symbol, {}).get("session_profile") or "").strip():
            reasons.append("SESSION_PROFILE_MISSING")
        if runtime_bucket != bucket_expected:
            reasons.append("RUNTIME_BUCKET_MISMATCH")
        if runtime_scope != runtime_scope_expected:
            reasons.append("RUNTIME_SCOPE_MISMATCH")
        if runtime_contract.get("universe_version", "") != str(universe_plan["universe_version"]):
            reasons.append("UNIVERSE_VERSION_MISMATCH")
        if runtime_contract.get("plan_hash", "") != str(universe_plan["plan_hash"]):
            reasons.append("PLAN_HASH_MISMATCH")

        broker_realism_ok = len(reasons) == 0
        if not broker_realism_ok:
            for reason in reasons:
                reason_counts[reason] = reason_counts.get(reason, 0) + 1

        items.append(
            {
                "symbol_alias": symbol,
                "session_profile": str(registry_by_symbol.get(symbol, {}).get("session_profile") or ""),
                "broker_symbol": str(registry_by_symbol.get(symbol, {}).get("broker_symbol") or ""),
                "runtime_contract_path": str(runtime_contract_path),
                "paper_live_bucket_expected": bucket_expected,
                "paper_live_bucket_runtime": runtime_bucket,
                "runtime_scope_expected": runtime_scope_expected,
                "runtime_scope": runtime_scope,
                "paper_live_enabled": runtime_contract.get("paper_live_enabled", "0"),
                "ledger_full_costs": bool(ledger_row.get("ledger_full_costs", False)),
                "spread_rows": int(ledger_row.get("spread_rows", 0) or 0),
                "slippage_rows": int(ledger_row.get("slippage_rows", 0) or 0),
                "commission_rows": int(ledger_row.get("commission_rows", 0) or 0),
                "swap_rows": int(ledger_row.get("swap_rows", 0) or 0),
                "threshold_mismatches": threshold_mismatches,
                "universe_version_runtime": runtime_contract.get("universe_version", ""),
                "plan_hash_runtime": runtime_contract.get("plan_hash", ""),
                "broker_realism_ok": broker_realism_ok,
                "gap_reasons": reasons,
            }
        )

    dominant_gap_reason = ""
    if reason_counts:
        dominant_gap_reason = sorted(reason_counts.items(), key=lambda item: (-item[1], item[0]))[0][0]

    payload = {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "universe_version": str(universe_plan["universe_version"]),
        "plan_hash": str(universe_plan["plan_hash"]),
        "broker_realism_ok": all(item["broker_realism_ok"] for item in items),
        "broker_realism_gap_symbols": [item["symbol_alias"] for item in items if not item["broker_realism_ok"]],
        "dominant_gap_reason": dominant_gap_reason,
        "package_thresholds": package_thresholds,
        "reason_counts": reason_counts,
        "items": items,
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    dump_json(output_json, payload)

    lines = [
        "# Broker Realism Parity Audit",
        "",
        f"- generated_at_utc: {payload['generated_at_utc']}",
        f"- universe_version: {payload['universe_version']}",
        f"- broker_realism_ok: {payload['broker_realism_ok']}",
        f"- dominant_gap_reason: {payload['dominant_gap_reason']}",
        "",
    ]
    for item in items:
        verdict = "OK" if item["broker_realism_ok"] else "GAP"
        lines.append(f"## {item['symbol_alias']} [{verdict}]")
        lines.append(f"- bucket runtime/expected: {item['paper_live_bucket_runtime']} / {item['paper_live_bucket_expected']}")
        lines.append(f"- runtime_scope runtime/expected: {item['runtime_scope']} / {item['runtime_scope_expected']}")
        lines.append(f"- threshold_mismatches: {', '.join(item['threshold_mismatches']) if item['threshold_mismatches'] else 'brak'}")
        lines.append(f"- gap_reasons: {', '.join(item['gap_reasons']) if item['gap_reasons'] else 'brak'}")
        lines.append("")
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
