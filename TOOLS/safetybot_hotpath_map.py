from __future__ import annotations

import argparse
import ast
import json
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


SCHEMA = "oanda.mt5.safetybot.hotpath_map.v1"
DEFAULT_SOURCE = Path("BIN") / "safetybot.py"


# Etap 0 planu migracji:
# - HOT  = logika, która finalnie ma trafić do lokalnego kernela MQL5.
# - WARM = maintenance/cache/loader poza tickiem.
# - SLOW = diagnostyka, emit, raportowanie, control-plane.
HOT = "HOT"
WARM = "WARM"
SLOW = "SLOW"

OWNER_PY_RUNTIME = "PYTHON_RUNTIME"
OWNER_PY_SUPERVISOR = "PYTHON_SUPERVISOR"
OWNER_MQL5_KERNEL = "MQL5_KERNEL"
OWNER_MQL5_WARM = "MQL5_WARM_PATH"


@dataclass(frozen=True)
class MethodRow:
    name: str
    line: int
    bucket: str
    owner_now: str
    owner_target: str
    reason: str


BUCKET_OVERRIDES: Dict[str, Tuple[str, str, str]] = {
    "scan_once": (HOT, OWNER_MQL5_KERNEL, "finalna decyzja wejścia/odmowy"),
    "_send_trade_command": (HOT, OWNER_MQL5_KERNEL, "wysyłka komendy trade"),
    "_trade_window_closeout": (HOT, OWNER_MQL5_KERNEL, "akcje close-only/closeout"),
    "_trade_window_off_maintenance": (WARM, OWNER_MQL5_WARM, "maintenance okna handlowego"),
    "_runtime_maintenance_step": (WARM, OWNER_PY_SUPERVISOR, "housekeeping control-plane"),
    "_runtime_idle_step": (WARM, OWNER_PY_SUPERVISOR, "idle step control-plane"),
    "_reload_stage1_live_config": (WARM, OWNER_PY_SUPERVISOR, "reload configu etapu 1"),
    "_emit_policy_runtime": (SLOW, OWNER_PY_SUPERVISOR, "emit control-plane policy_runtime"),
    "_emit_kernel_config": (SLOW, OWNER_PY_SUPERVISOR, "emit control-plane kernel_config"),
    "_loop_metrics_snapshot": (SLOW, OWNER_PY_SUPERVISOR, "telemetria pętli"),
    "_emit_runtime_metrics": (SLOW, OWNER_PY_SUPERVISOR, "telemetria runtime"),
    "_emit_stage1_live_loader_event": (SLOW, OWNER_PY_SUPERVISOR, "audit loadera etapu 1"),
    "_emit_unit_diagnostic": (SLOW, OWNER_PY_SUPERVISOR, "log diagnostyczny"),
    "run": (WARM, OWNER_PY_SUPERVISOR, "orchestrator pętli"),
}


KEYWORDS_HOT = ("scan", "trade", "entry", "execute", "position", "tick")
KEYWORDS_WARM = ("maintenance", "idle", "reload", "load", "cache", "window", "loop")
KEYWORDS_SLOW = (
    "emit",
    "metrics",
    "diagnostic",
    "report",
    "audit",
    "shadow",
    "learning",
    "policy",
    "config",
)


def _utc_iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _canonical_json(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)


def _sha256_hex(data: str) -> str:
    import hashlib

    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def _method_rows_from_ast(tree: ast.AST) -> List[ast.FunctionDef]:
    for node in getattr(tree, "body", []):
        if isinstance(node, ast.ClassDef) and node.name == "SafetyBot":
            return [x for x in node.body if isinstance(x, ast.FunctionDef)]
    return []


def _infer_bucket(name: str) -> Tuple[str, str, str]:
    override = BUCKET_OVERRIDES.get(name)
    if override:
        return override

    lname = name.lower()
    if any(k in lname for k in KEYWORDS_SLOW):
        return SLOW, OWNER_PY_SUPERVISOR, "heurystyka slow/control-plane"
    if any(k in lname for k in KEYWORDS_HOT):
        return HOT, OWNER_MQL5_KERNEL, "heurystyka hot/decyzja"
    if any(k in lname for k in KEYWORDS_WARM):
        return WARM, OWNER_MQL5_WARM, "heurystyka warm/maintenance"
    return SLOW, OWNER_PY_SUPERVISOR, "domyślnie slow (review)"


def build_hotpath_map(source_path: Path) -> dict:
    raw = source_path.read_text(encoding="utf-8")
    tree = ast.parse(raw)
    methods = _method_rows_from_ast(tree)

    rows: List[MethodRow] = []
    for method in methods:
        bucket, owner_target, reason = _infer_bucket(method.name)
        rows.append(
            MethodRow(
                name=method.name,
                line=int(method.lineno),
                bucket=bucket,
                owner_now=OWNER_PY_RUNTIME,
                owner_target=owner_target,
                reason=reason,
            )
        )

    rows.sort(key=lambda x: x.line)
    counts_bucket = Counter(x.bucket for x in rows)
    counts_target = Counter(x.owner_target for x in rows)

    report = {
        "schema": SCHEMA,
        "generated_at_utc": _utc_iso_now(),
        "source_path": str(source_path),
        "source_sha256": _sha256_hex(raw),
        "summary": {
            "methods_total": len(rows),
            "bucket_counts": dict(counts_bucket),
            "owner_target_counts": dict(counts_target),
        },
        "rows": [
            {
                "name": row.name,
                "line": row.line,
                "bucket": row.bucket,
                "owner_now": row.owner_now,
                "owner_target": row.owner_target,
                "reason": row.reason,
            }
            for row in rows
        ],
        "notes": [
            "To jest mapa etapu migracji (review), nie automatyczne przeniesienie kodu.",
            "Bucket/owner dla pozycji bez override wymaga przeglądu inżynierskiego.",
        ],
    }
    return report


def _render_txt(report: dict) -> str:
    summary = report.get("summary", {})
    bucket_counts = summary.get("bucket_counts", {})
    owner_counts = summary.get("owner_target_counts", {})
    rows = report.get("rows", [])

    lines: List[str] = []
    lines.append(f"SCHEMA: {report.get('schema')}")
    lines.append(f"GENERATED_AT_UTC: {report.get('generated_at_utc')}")
    lines.append(f"SOURCE: {report.get('source_path')}")
    lines.append(f"SOURCE_SHA256: {report.get('source_sha256')}")
    lines.append("")
    lines.append(f"METHODS_TOTAL: {summary.get('methods_total', 0)}")
    lines.append(
        "BUCKET_COUNTS: "
        + ", ".join(f"{k}={bucket_counts.get(k, 0)}" for k in [HOT, WARM, SLOW])
    )
    lines.append(
        "OWNER_TARGET_COUNTS: "
        + ", ".join(
            f"{k}={owner_counts.get(k, 0)}"
            for k in [OWNER_MQL5_KERNEL, OWNER_MQL5_WARM, OWNER_PY_SUPERVISOR]
        )
    )
    lines.append("")
    lines.append("ROWS:")
    for row in rows:
        lines.append(
            f"- line={row['line']} name={row['name']} bucket={row['bucket']} "
            f"owner_now={row['owner_now']} owner_target={row['owner_target']} reason={row['reason']}"
        )
    return "\n".join(lines) + "\n"


def _write(path: Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def main(argv: Optional[Iterable[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Mapuj metody SafetyBot do bucketów HOT/WARM/SLOW.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM", help="Root repo.")
    ap.add_argument("--source", default=str(DEFAULT_SOURCE), help="Ścieżka źródła względem root.")
    ap.add_argument("--out-json", default=None, help="Docelowy JSON.")
    ap.add_argument("--out-txt", default=None, help="Docelowy TXT.")
    args = ap.parse_args(list(argv) if argv is not None else None)

    root = Path(args.root).resolve()
    source = (root / args.source).resolve()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    out_json = (
        Path(args.out_json).resolve()
        if args.out_json
        else (root / "EVIDENCE" / "hotpath_map" / f"safetybot_hotpath_map_{stamp}.json")
    )
    out_txt = (
        Path(args.out_txt).resolve()
        if args.out_txt
        else (root / "EVIDENCE" / "hotpath_map" / f"safetybot_hotpath_map_{stamp}.txt")
    )

    report = build_hotpath_map(source)
    _write(out_json, _canonical_json(report))
    _write(out_txt, _render_txt(report))

    latest_json = out_json.parent / "safetybot_hotpath_map_latest.json"
    latest_txt = out_txt.parent / "safetybot_hotpath_map_latest.txt"
    _write(latest_json, _canonical_json(report))
    _write(latest_txt, _render_txt(report))

    print(
        "HOTPATH_MAP_OK "
        f"source={source} methods={report.get('summary', {}).get('methods_total', 0)} "
        f"json={out_json} txt={out_txt}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
