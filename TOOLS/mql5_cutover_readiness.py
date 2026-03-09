from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


SCHEMA = "oanda.mt5.cutover_readiness.v1"


def _utc_iso_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def _write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _write_txt(path: Path, lines: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines).strip() + "\n", encoding="utf-8")


def _find_latest_parity(root: Path) -> Optional[Path]:
    direct = root / "EVIDENCE" / "kernel_shadow" / "kernel_shadow_parity_report_latest.json"
    if direct.exists():
        return direct
    files = sorted((root / "EVIDENCE" / "kernel_shadow").glob("kernel_shadow_parity_report_*.json"))
    if not files:
        return None
    return files[-1]


def build_readiness(
    parity_report: Dict[str, Any],
    *,
    min_parity_rows: int,
    max_mismatch_ratio: float,
    min_active_windows: int = 1,
    min_window_parity_rows: int = 20,
    max_window_mismatch_ratio: float = 0.05,
) -> Dict[str, Any]:
    summary = dict(parity_report.get("summary") or {})
    counts = dict(parity_report.get("counts") or {})
    parity_rows = int(summary.get("parity_rows") or 0)
    mismatch_rows = int(summary.get("parity_mismatch") or 0)
    mismatch_ratio_raw = summary.get("parity_mismatch_ratio")
    mismatch_ratio = float(mismatch_ratio_raw) if mismatch_ratio_raw is not None else None
    state_rows = int(summary.get("state_rows") or 0)
    parity_by_window = {
        str(k): int(v)
        for k, v in (counts.get("parity_by_window") or {}).items()
        if str(k).strip()
    }
    mismatch_by_window = {
        str(k): int(v)
        for k, v in (counts.get("parity_mismatch_by_window") or {}).items()
        if str(k).strip()
    }
    active_windows = [
        w
        for w, cnt in parity_by_window.items()
        if int(cnt) > 0 and str(w).upper() not in {"OFF", "WINDOWS_UNCONFIGURED", "UNKNOWN_TS"}
    ]
    active_window_count = int(len(active_windows))

    reasons: List[str] = []
    status = "PASS"

    if parity_rows <= 0:
        status = "REVIEW_REQUIRED"
        reasons.append("NO_PARITY_DATA")
    elif parity_rows < int(min_parity_rows):
        status = "REVIEW_REQUIRED"
        reasons.append("PARITY_SAMPLE_TOO_LOW")

    if mismatch_ratio is not None and mismatch_ratio > float(max_mismatch_ratio):
        status = "NO_GO"
        reasons.append("PARITY_MISMATCH_RATIO_HIGH")

    if active_window_count < int(max(0, min_active_windows)):
        if status == "PASS":
            status = "REVIEW_REQUIRED"
        reasons.append("WINDOW_COVERAGE_TOO_LOW")

    worst_window_ratio: Optional[float] = None
    worst_window_name: str = ""
    for window_name, window_rows in parity_by_window.items():
        w_rows = int(window_rows)
        if w_rows < int(max(1, min_window_parity_rows)):
            continue
        w_mismatch = int(mismatch_by_window.get(window_name, 0))
        w_ratio = float(w_mismatch) / float(max(1, w_rows))
        if worst_window_ratio is None or w_ratio > worst_window_ratio:
            worst_window_ratio = w_ratio
            worst_window_name = str(window_name)
    if worst_window_ratio is not None and worst_window_ratio > float(max_window_mismatch_ratio):
        status = "NO_GO"
        reasons.append("WINDOW_MISMATCH_RATIO_HIGH")

    notes: List[str] = []
    if not reasons:
        notes.append("Shadow parity spełnia aktualne progi cutover.")
    else:
        notes.append("Cutover do MQL5_ACTIVE wymaga dalszych pomiarów/korekty.")
    if worst_window_ratio is not None:
        notes.append(
            f"Najgorsze okno parity: {worst_window_name} ratio={worst_window_ratio:.4f} "
            f"(prog={float(max_window_mismatch_ratio):.4f})"
        )

    return {
        "schema": SCHEMA,
        "generated_at_utc": _utc_iso_now(),
        "inputs": {
            "min_parity_rows": int(min_parity_rows),
            "max_mismatch_ratio": float(max_mismatch_ratio),
            "min_active_windows": int(max(0, min_active_windows)),
            "min_window_parity_rows": int(max(1, min_window_parity_rows)),
            "max_window_mismatch_ratio": float(max_window_mismatch_ratio),
        },
        "summary": {
            "parity_rows": parity_rows,
            "parity_mismatch": mismatch_rows,
            "parity_mismatch_ratio": mismatch_ratio,
            "state_rows": state_rows,
            "active_windows": active_window_count,
            "worst_window": worst_window_name or None,
            "worst_window_mismatch_ratio": worst_window_ratio,
        },
        "status": status,
        "reasons": reasons,
        "top_state_reason": list(parity_report.get("counts", {}).get("state_by_reason_top10", []))[:5],
        "top_mismatch_reason": list(parity_report.get("counts", {}).get("parity_mismatch_kernel_reason_top10", []))[:5],
        "top_window_mismatch": list(parity_report.get("counts", {}).get("parity_mismatch_by_window_top10", []))[:5],
        "notes": notes,
    }


def _render_txt(readiness: Dict[str, Any], parity_path: Path) -> List[str]:
    s = dict(readiness.get("summary") or {})
    lines = [
        f"SCHEMA: {readiness.get('schema')}",
        f"GENERATED_AT_UTC: {readiness.get('generated_at_utc')}",
        f"PARITY_SOURCE: {parity_path}",
        f"STATUS: {readiness.get('status')}",
        f"REASONS: {','.join(readiness.get('reasons') or ['NONE'])}",
        "",
        f"PARITY_ROWS: {s.get('parity_rows', 0)}",
        f"MISMATCH_ROWS: {s.get('parity_mismatch', 0)}",
        f"MISMATCH_RATIO: {s.get('parity_mismatch_ratio', 'UNKNOWN')}",
        f"STATE_ROWS: {s.get('state_rows', 0)}",
        f"ACTIVE_WINDOWS: {s.get('active_windows', 0)}",
        f"WORST_WINDOW: {s.get('worst_window', 'UNKNOWN')}",
        f"WORST_WINDOW_MISMATCH_RATIO: {s.get('worst_window_mismatch_ratio', 'UNKNOWN')}",
    ]
    for n in readiness.get("notes") or []:
        lines.append(f"- {n}")
    return lines


def main(argv: Optional[Iterable[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Evaluate MQL5 cutover readiness from kernel shadow parity report.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--min-parity-rows", type=int, default=200)
    ap.add_argument("--max-mismatch-ratio", type=float, default=0.02)
    ap.add_argument("--min-active-windows", type=int, default=1)
    ap.add_argument("--min-window-parity-rows", type=int, default=20)
    ap.add_argument("--max-window-mismatch-ratio", type=float, default=0.05)
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-txt", default=None)
    args = ap.parse_args(list(argv) if argv is not None else None)

    root = Path(args.root).resolve()
    parity_path = _find_latest_parity(root)
    if parity_path is None:
        print("CUTOVER_READINESS_FAIL reason=NO_PARITY_REPORT")
        return 2

    parity_report = _read_json(parity_path)
    readiness = build_readiness(
        parity_report,
        min_parity_rows=int(args.min_parity_rows),
        max_mismatch_ratio=float(args.max_mismatch_ratio),
        min_active_windows=int(args.min_active_windows),
        min_window_parity_rows=int(args.min_window_parity_rows),
        max_window_mismatch_ratio=float(args.max_window_mismatch_ratio),
    )

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out_json = (
        Path(args.out_json).resolve()
        if args.out_json
        else root / "EVIDENCE" / "cutover" / f"mql5_cutover_readiness_{stamp}.json"
    )
    out_txt = (
        Path(args.out_txt).resolve()
        if args.out_txt
        else root / "EVIDENCE" / "cutover" / f"mql5_cutover_readiness_{stamp}.txt"
    )

    _write_json(out_json, readiness)
    _write_txt(out_txt, _render_txt(readiness, parity_path))
    _write_json(out_json.parent / "mql5_cutover_readiness_latest.json", readiness)
    _write_txt(out_txt.parent / "mql5_cutover_readiness_latest.txt", _render_txt(readiness, parity_path))

    print(
        "CUTOVER_READINESS_OK "
        f"status={readiness.get('status')} "
        f"parity_rows={readiness.get('summary', {}).get('parity_rows', 0)} "
        f"mismatch_ratio={readiness.get('summary', {}).get('parity_mismatch_ratio', 'UNKNOWN')} "
        f"json={out_json}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
