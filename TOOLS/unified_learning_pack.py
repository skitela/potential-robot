#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path


def _load_builder():
    root = Path(__file__).resolve().parents[1]
    root_str = str(root)
    if root_str not in sys.path:
        sys.path.insert(0, root_str)
    from BIN.unified_learning_pack import build_unified_learning_pack
    return build_unified_learning_pack


build_unified_learning_pack = _load_builder()


def _iso_now_utc() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _render_feedback_txt(payload: dict) -> str:
    global_obj = payload.get("global") if isinstance(payload.get("global"), dict) else {}
    feedback = payload.get("source_feedback") if isinstance(payload.get("source_feedback"), dict) else {}
    global_feedback = feedback.get("global") if isinstance(feedback.get("global"), dict) else {}
    lines = [
        "UNIFIED_LEARNING_SOURCE_FEEDBACK",
        f"qa_light={global_obj.get('qa_light') or 'UNKNOWN'}",
        f"preferred_symbol={global_obj.get('preferred_symbol') or ''}",
        f"leader={global_feedback.get('leader') or 'INSUFFICIENT_DATA'}",
        f"learning_weight={global_feedback.get('learning_weight') or 1.0}",
        f"learning_assist_n={global_feedback.get('learning_assist_n') or 0}",
        f"safetybot_core_n={global_feedback.get('safetybot_core_n') or 0}",
        f"learning_assist_net_avg={global_feedback.get('learning_assist_net_avg') or 0.0}",
        f"safetybot_core_net_avg={global_feedback.get('safetybot_core_net_avg') or 0.0}",
        "",
        "TOP_SYMBOLS",
    ]
    instruments = payload.get("instruments") if isinstance(payload.get("instruments"), dict) else {}
    shown = 0
    for symbol in sorted(instruments.keys()):
        row = instruments.get(symbol) if isinstance(instruments.get(symbol), dict) else {}
        feedback_row = row.get("source_feedback") if isinstance(row.get("source_feedback"), dict) else {}
        lines.append(
            f"- {symbol}: bias={row.get('advisory_bias') or 'NEUTRAL'} "
            f"consensus={row.get('consensus_score') or 0.0} "
            f"leader={feedback_row.get('leader') or 'INSUFFICIENT_DATA'} "
            f"learning_weight={feedback_row.get('learning_weight') or 1.0}"
        )
        shown += 1
        if shown >= 12:
            break
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build one unified learning advisory pack for paper/shadow runtime.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else None
    out_path = Path(args.out).resolve() if str(args.out).strip() else None
    out, payload = build_unified_learning_pack(root=root, lab_data_root=lab_data_root, out_path=out_path)
    lab_root = Path(payload.get("lab_data_root") or (lab_data_root or "")).resolve() if (payload.get("lab_data_root") or lab_data_root) else None
    if lab_root is not None:
        stage1_dir = lab_root / "reports" / "stage1"
        stage1_dir.mkdir(parents=True, exist_ok=True)
        stamp = _iso_now_utc()
        report_json = stage1_dir / f"unified_learning_source_feedback_{stamp}.json"
        report_txt = stage1_dir / f"unified_learning_source_feedback_{stamp}.txt"
        report_json.write_text(json.dumps(payload.get("source_feedback") or {}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        report_txt.write_text(_render_feedback_txt(payload), encoding="utf-8")
        (stage1_dir / "unified_learning_source_feedback_latest.json").write_text(
            json.dumps(payload.get("source_feedback") or {}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        (stage1_dir / "unified_learning_source_feedback_latest.txt").write_text(
            _render_feedback_txt(payload),
            encoding="utf-8",
        )
    global_obj = payload.get("global") if isinstance(payload.get("global"), dict) else {}
    runtime_light = payload.get("runtime_light") if isinstance(payload.get("runtime_light"), dict) else {}
    global_feedback = ((payload.get("source_feedback") or {}).get("global") if isinstance((payload.get("source_feedback") or {}).get("global"), dict) else {})
    summary = {
        "qa_light": str(global_obj.get("qa_light") or "UNKNOWN"),
        "preferred_symbol": str(runtime_light.get("preferred_symbol") or ""),
        "symbols_n": int(global_obj.get("instruments_n") or 0),
        "stage": str(global_obj.get("progress_stage") or "UNKNOWN"),
        "gonogo_verdict": str(global_obj.get("gonogo_verdict") or "UNKNOWN"),
        "feedback_leader": str(global_feedback.get("leader") or "INSUFFICIENT_DATA"),
        "learning_weight": float(global_feedback.get("learning_weight") or 1.0),
        "out": str(out),
    }
    print("UNIFIED_LEARNING_PACK_OK " + json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
