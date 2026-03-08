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
) -> Dict[str, Any]:
    summary = dict(parity_report.get("summary") or {})
    parity_rows = int(summary.get("parity_rows") or 0)
    mismatch_rows = int(summary.get("parity_mismatch") or 0)
    mismatch_ratio_raw = summary.get("parity_mismatch_ratio")
    mismatch_ratio = float(mismatch_ratio_raw) if mismatch_ratio_raw is not None else None
    state_rows = int(summary.get("state_rows") or 0)

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

    notes: List[str] = []
    if not reasons:
        notes.append("Shadow parity spełnia aktualne progi cutover.")
    else:
        notes.append("Cutover do MQL5_ACTIVE wymaga dalszych pomiarów/korekty.")

    return {
        "schema": SCHEMA,
        "generated_at_utc": _utc_iso_now(),
        "inputs": {
            "min_parity_rows": int(min_parity_rows),
            "max_mismatch_ratio": float(max_mismatch_ratio),
        },
        "summary": {
            "parity_rows": parity_rows,
            "parity_mismatch": mismatch_rows,
            "parity_mismatch_ratio": mismatch_ratio,
            "state_rows": state_rows,
        },
        "status": status,
        "reasons": reasons,
        "top_state_reason": list(parity_report.get("summary", {}).get("state_reason_top10", []))[:5],
        "top_mismatch_reason": list(parity_report.get("summary", {}).get("parity_mismatch_kernel_reason_top10", []))[:5],
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
    ]
    for n in readiness.get("notes") or []:
        lines.append(f"- {n}")
    return lines


def main(argv: Optional[Iterable[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Evaluate MQL5 cutover readiness from kernel shadow parity report.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--min-parity-rows", type=int, default=200)
    ap.add_argument("--max-mismatch-ratio", type=float, default=0.02)
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
