from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

from mb_ml_core.paths import CompatPaths
from mb_ml_core.registry import load_paper_live_active_symbols, load_retired_symbols, load_scalping_universe_plan, load_training_universe_symbols
from mb_ml_supervision.audits import load_active_registry_symbols
from mb_ml_supervision.io_utils import dump_json, read_json, utc_now_iso
from mb_ml_supervision.paths import OverlayPaths


TEXT_SUFFIXES = {".json", ".txt", ".md", ".ini", ".csv", ".set", ".mqh", ".mq5"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Standalone audit zgodnosci active universe po realignment scalpingu.")
    parser.add_argument("--project-root", default=r"C:\MAKRO_I_MIKRO_BOT")
    parser.add_argument("--research-root", default=r"C:\TRADING_DATA\RESEARCH")
    parser.add_argument("--common-state-root", default=None)
    parser.add_argument("--output-json", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\active_universe_parity_audit_latest.json")
    parser.add_argument("--output-md", default=r"C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\active_universe_parity_audit_latest.md")
    return parser.parse_args()


def _find_symbol_registry(paths: OverlayPaths) -> Path | None:
    for candidate in paths.onnx_symbol_registry_candidates:
        if candidate.exists():
            return candidate
    return None


def _infer_active_live_symbols(paths: OverlayPaths, registry_rows: list[dict[str, Any]]) -> list[str]:
    if not paths.server_profile_active_live_root.exists():
        return []
    preset_to_symbol = {
        f"{Path(str(row.get('preset') or '')).stem}_ACTIVE.set": str(row.get("symbol") or "").strip()
        for row in registry_rows
        if str(row.get("preset") or "").strip() and str(row.get("symbol") or "").strip()
    }
    out: list[str] = []
    for preset_path in sorted(paths.server_profile_active_live_root.glob("*.set")):
        symbol = preset_to_symbol.get(preset_path.name)
        if symbol and symbol not in out:
            out.append(symbol)
    return out


def _scan_file_for_symbols(path: Path, symbols_upper: set[str]) -> bool:
    if path.suffix.lower() not in TEXT_SUFFIXES:
        return False
    try:
        text = path.read_text(encoding="utf-8", errors="ignore").upper()
    except Exception:
        return False
    return any(symbol in text for symbol in symbols_upper)


def _collect_tree_hits(root: Path, symbols: list[str], location: str) -> list[dict[str, str]]:
    if not root.exists():
        return []
    symbol_set = {str(symbol).strip().upper() for symbol in symbols if str(symbol).strip()}
    hits: list[dict[str, str]] = []
    for path in root.rglob("*"):
        if path.is_dir():
            continue
        path_upper = str(path).upper()
        matched = sorted(symbol for symbol in symbol_set if symbol in path_upper)
        if not matched and not _scan_file_for_symbols(path, symbol_set):
            continue
        if not matched:
            matched = sorted(symbol_set)
        for symbol in matched:
            hits.append({"symbol": symbol, "location": location, "path": str(path)})
    return hits


def _load_symbol_registry_symbols(paths: OverlayPaths) -> list[str]:
    registry_path = _find_symbol_registry(paths)
    payload = read_json(registry_path, default={}) if registry_path else {}
    if not isinstance(payload, dict):
        return []
    symbols_payload = payload.get("symbols")
    if isinstance(symbols_payload, dict):
        return sorted(str(symbol).strip() for symbol in symbols_payload.keys() if str(symbol).strip())
    return []


def _load_expected_symbols_from_metrics(paths: OverlayPaths) -> list[str]:
    payload = read_json(paths.global_metrics_path, default={})
    if not isinstance(payload, dict):
        return []
    summary = payload.get("summary")
    if not isinstance(summary, dict):
        return []
    values = summary.get("expected_symbols")
    if not isinstance(values, list):
        return []
    return [str(item).strip() for item in values if str(item).strip()]


def _load_runtime_registry_universe(paths: OverlayPaths) -> dict[str, list[str]]:
    payload = read_json(paths.sync_runtime_registry_path, default={})
    if not isinstance(payload, dict):
        return {}
    keys = [
        "training_universe",
        "paper_live_universe",
        "paper_live_second_wave",
        "paper_live_hold",
        "global_teacher_only",
        "retired_symbols",
    ]
    out: dict[str, list[str]] = {}
    for key in keys:
        values = payload.get(key)
        out[key] = [str(item).strip() for item in values] if isinstance(values, list) else []
    return out


def _collect_direct_leaks(paths: OverlayPaths, retired_symbols: list[str]) -> list[dict[str, str]]:
    hits: list[dict[str, str]] = []
    for symbol in retired_symbols:
        for root, location in [
            (paths.runtime_symbol_state_root / symbol, "state"),
            (paths.runtime_symbol_key_root / symbol, "key"),
        ]:
            if root.exists():
                hits.append({"symbol": symbol, "location": location, "path": str(root)})
    hits.extend(_collect_tree_hits(paths.server_profile_handoff_root, retired_symbols, "handoff"))
    hits.extend(_collect_tree_hits(paths.server_profile_remote_sim_root, retired_symbols, "remote_sim"))
    return hits


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
    paper_live_universe = load_paper_live_active_symbols(compat_paths)
    retired_symbols = load_retired_symbols(compat_paths)
    registry_rows = load_active_registry_symbols(paths)
    registry_symbols = sorted(str(row["symbol"]).strip() for row in registry_rows if str(row.get("symbol") or "").strip())
    package_payload = read_json(paths.package_json_path, default={})
    package_training_universe = package_payload.get("training_universe", []) if isinstance(package_payload, dict) else []
    package_paper_live_universe = package_payload.get("paper_live_universe", []) if isinstance(package_payload, dict) else []
    runtime_registry_universe = _load_runtime_registry_universe(paths)
    symbol_registry_symbols = _load_symbol_registry_symbols(paths)
    active_live_symbols = _infer_active_live_symbols(paths, registry_rows)
    expected_symbols_in_metrics = _load_expected_symbols_from_metrics(paths)
    leak_locations = _collect_direct_leaks(paths, retired_symbols)

    training_universe_ok = (
        set(registry_symbols) == set(training_universe)
        and set(package_training_universe) == set(training_universe)
        and set(symbol_registry_symbols) == set(training_universe)
        and set(runtime_registry_universe.get("training_universe", [])) == set(training_universe)
    )
    paper_live_universe_ok = (
        set(package_paper_live_universe) == set(paper_live_universe)
        and set(runtime_registry_universe.get("paper_live_universe", [])) == set(paper_live_universe)
        and set(active_live_symbols) == set(paper_live_universe)
    )
    expected_symbols_mismatch = bool(expected_symbols_in_metrics) and (
        set(expected_symbols_in_metrics) != set(training_universe)
    )

    payload = {
        "schema_version": "1.0",
        "generated_at_utc": utc_now_iso(),
        "universe_version": str(universe_plan["universe_version"]),
        "plan_hash": str(universe_plan["plan_hash"]),
        "training_universe_ok": training_universe_ok,
        "paper_live_universe_ok": paper_live_universe_ok,
        "retired_symbols_leak_count": len(leak_locations),
        "leak_locations": leak_locations,
        "expected_symbols_mismatch": expected_symbols_mismatch,
        "training_universe": training_universe,
        "paper_live_universe": paper_live_universe,
        "retired_symbols": retired_symbols,
        "state": {
            "registry_symbols": registry_symbols,
            "package_training_universe": package_training_universe,
            "package_paper_live_universe": package_paper_live_universe,
            "runtime_training_universe": runtime_registry_universe.get("training_universe", []),
            "runtime_paper_live_universe": runtime_registry_universe.get("paper_live_universe", []),
            "symbol_registry_symbols": symbol_registry_symbols,
            "active_live_symbols": active_live_symbols,
            "expected_symbols_in_metrics": expected_symbols_in_metrics,
        },
    }

    output_json = Path(args.output_json)
    output_md = Path(args.output_md)
    dump_json(output_json, payload)

    lines = [
        "# Active Universe Parity Audit",
        "",
        f"- generated_at_utc: {payload['generated_at_utc']}",
        f"- universe_version: {payload['universe_version']}",
        f"- training_universe_ok: {payload['training_universe_ok']}",
        f"- paper_live_universe_ok: {payload['paper_live_universe_ok']}",
        f"- retired_symbols_leak_count: {payload['retired_symbols_leak_count']}",
        f"- expected_symbols_mismatch: {payload['expected_symbols_mismatch']}",
        "",
        "## Training Universe",
        "",
        f"- contract: {', '.join(training_universe)}",
        f"- registry: {', '.join(registry_symbols)}",
        f"- package: {', '.join(package_training_universe)}",
        f"- runtime: {', '.join(runtime_registry_universe.get('training_universe', []))}",
        f"- onnx registry: {', '.join(symbol_registry_symbols)}",
        "",
        "## Paper Live Universe",
        "",
        f"- contract: {', '.join(paper_live_universe)}",
        f"- package: {', '.join(package_paper_live_universe)}",
        f"- runtime: {', '.join(runtime_registry_universe.get('paper_live_universe', []))}",
        f"- ActiveLive presets: {', '.join(active_live_symbols)}",
        "",
        "## Retired Leaks",
        "",
    ]
    if leak_locations:
        for leak in leak_locations[:200]:
            lines.append(f"- {leak['symbol']} -> {leak['location']} -> {leak['path']}")
    else:
        lines.append("- brak aktywnych wyciekow retired symbols")
    output_md.parent.mkdir(parents=True, exist_ok=True)
    output_md.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(output_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
