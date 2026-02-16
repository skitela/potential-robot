#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path
from typing import Any, Dict


ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from TOOLS import gh_v1_bridge_benchmark as bridge  # noqa: E402


UTC = dt.timezone.utc
METHOD_CONTRACT_REL = Path("SCHEMAS") / "ranking_benchmark_metodyka_v1.json"
METHOD_DOC_REL = Path("DOCS") / "RANKING_BENCHMARK_METODYKA_V1.md"
DEFAULT_GH_ROOT = Path(r"C:\GLOBALNY HANDEL VER1")


def now_utc_iso() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def run_id_utc() -> str:
    return dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            ch = f.read(65536)
            if not ch:
                break
            h.update(ch)
    return h.hexdigest()


def load_method_contract(path: Path) -> Dict[str, Any]:
    obj = json.loads(path.read_text(encoding="utf-8", errors="replace") or "{}")
    if not isinstance(obj, dict):
        raise ValueError("METHOD_CONTRACT_INVALID_TYPE")
    if str(obj.get("method_id") or "") != "RANKING_BENCHMARK_V1":
        raise ValueError("METHOD_CONTRACT_INVALID_METHOD_ID")
    if int(obj.get("version") or 0) != 1:
        raise ValueError("METHOD_CONTRACT_INVALID_VERSION")
    return obj


def default_target_root() -> Path:
    if str(ROOT).lower().rstrip("\\/") == str(DEFAULT_GH_ROOT).lower().rstrip("\\/"):
        return ROOT
    if DEFAULT_GH_ROOT.exists():
        return DEFAULT_GH_ROOT
    return ROOT


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Unified benchmark/ranking runner (method V1).")
    ap.add_argument("--target-root", default="", help="Target runtime root for scoring (default: GH V1 when available).")
    ap.add_argument("--out-json", default="", help="Optional output JSON path.")
    ap.add_argument("--out-md", default="", help="Optional output Markdown path.")
    ap.add_argument("--strict-contract", action="store_true", help="Fail if method contract file is missing/invalid.")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    contract_path = (ROOT / METHOD_CONTRACT_REL).resolve()
    doc_path = (ROOT / METHOD_DOC_REL).resolve()

    contract: Dict[str, Any] = {}
    if contract_path.exists():
        contract = load_method_contract(contract_path)
    elif args.strict_contract:
        raise SystemExit("METHOD_CONTRACT_MISSING")

    if str(args.target_root).strip():
        target_root = Path(args.target_root).resolve()
    else:
        target_root = default_target_root().resolve()

    report = bridge.build_report(target_root)
    report["methodology"] = {
        "method_id": str(contract.get("method_id") or "RANKING_BENCHMARK_V1"),
        "version": int(contract.get("version") or 1),
        "runner_root": str(ROOT),
        "target_root": str(target_root),
        "contract_path": str(contract_path) if contract_path.exists() else "",
        "contract_sha256": sha256_file(contract_path) if contract_path.exists() else "",
        "doc_path": str(doc_path) if doc_path.exists() else "",
        "ts_utc": now_utc_iso(),
    }

    rid = run_id_utc()
    out_json = Path(args.out_json) if str(args.out_json).strip() else (ROOT / "EVIDENCE" / f"ranking_benchmark_v1_{rid}.json")
    out_md = Path(args.out_md) if str(args.out_md).strip() else (ROOT / "EVIDENCE" / f"ranking_benchmark_v1_{rid}.md")
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_md.parent.mkdir(parents=True, exist_ok=True)

    md = bridge.render_markdown(report)
    md += "\n## Method Lock\n"
    md += f"- method_id: `{report['methodology']['method_id']}`\n"
    md += f"- version: `{report['methodology']['version']}`\n"
    if report["methodology"]["contract_path"]:
        md += f"- contract: `{report['methodology']['contract_path']}`\n"
        md += f"- contract_sha256: `{report['methodology']['contract_sha256']}`\n"

    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    out_md.write_text(md, encoding="utf-8")

    print(
        "RANKING_BENCHMARK_V1_DONE | "
        f"target={target_root} | method={report['methodology']['method_id']}@{report['methodology']['version']} | "
        f"score={report['gh_v1']['score_100']:.2f} | segment={report['gh_v1']['segment']} | "
        f"status={report['go_nogo']['status']} | json={out_json} | md={out_md}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
