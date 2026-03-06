#!/usr/bin/env python3
from __future__ import annotations

import argparse
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
    global_obj = payload.get("global") if isinstance(payload.get("global"), dict) else {}
    runtime_light = payload.get("runtime_light") if isinstance(payload.get("runtime_light"), dict) else {}
    summary = {
        "qa_light": str(global_obj.get("qa_light") or "UNKNOWN"),
        "preferred_symbol": str(runtime_light.get("preferred_symbol") or ""),
        "symbols_n": int(global_obj.get("instruments_n") or 0),
        "stage": str(global_obj.get("progress_stage") or "UNKNOWN"),
        "gonogo_verdict": str(global_obj.get("gonogo_verdict") or "UNKNOWN"),
        "out": str(out),
    }
    print("UNIFIED_LEARNING_PACK_OK " + json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
