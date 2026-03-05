#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def symbol_base(sym: str) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def find_latest_rows_file(stage1_reports_dir: Path) -> Optional[Path]:
    files = sorted(stage1_reports_dir.glob("stage1_counterfactual_rows_*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0] if files else None


def iter_jsonl(path: Path) -> Iterable[Dict[str, Any]]:
    for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, dict):
                yield obj
        except Exception:
            continue


def _recommend(saved_loss_n: int, missed_opp_n: int, net_pnl_points: float) -> str:
    if missed_opp_n > saved_loss_n and net_pnl_points > 0.0:
        return "ROZWAZ_LUZOWANIE_W_SHADOW"
    if saved_loss_n >= missed_opp_n and net_pnl_points < 0.0:
        return "DOCISKAJ_FILTRY"
    return "OBSERWUJ_BEZ_ZMIAN"


def _collect_summary(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    by_symbol: Dict[str, Dict[str, Any]] = defaultdict(lambda: {"saved": 0, "missed": 0, "neutral": 0, "pnl": 0.0, "n": 0})
    by_window: Dict[str, Dict[str, Any]] = defaultdict(lambda: {"saved": 0, "missed": 0, "neutral": 0, "pnl": 0.0, "n": 0})
    by_symbol_window: Dict[Tuple[str, str], Dict[str, Any]] = defaultdict(
        lambda: {"saved": 0, "missed": 0, "neutral": 0, "pnl": 0.0, "n": 0}
    )

    for row in rows:
        sym = symbol_base(str(row.get("symbol") or ""))
        wid = str(row.get("window_id") or "UNKNOWN").upper()
        wph = str(row.get("window_phase") or "UNKNOWN").upper()
        win = f"{wid}|{wph}"
        st = str(row.get("counterfactual_status") or "UNKNOWN").upper()
        pnl = float(row.get("counterfactual_pnl_points") or 0.0)

        if not sym:
            continue
        for bucket in (by_symbol[sym], by_window[win], by_symbol_window[(sym, win)]):
            bucket["n"] += 1
            bucket["pnl"] = float(bucket["pnl"]) + pnl
            if st == "SAVED_LOSS":
                bucket["saved"] += 1
            elif st == "MISSED_OPPORTUNITY":
                bucket["missed"] += 1
            else:
                bucket["neutral"] += 1

    symbol_rows: List[Dict[str, Any]] = []
    for sym in sorted(by_symbol.keys()):
        b = by_symbol[sym]
        n = int(b["n"])
        pnl = float(b["pnl"])
        symbol_rows.append(
            {
                "symbol": sym,
                "samples_n": n,
                "saved_loss_n": int(b["saved"]),
                "missed_opportunity_n": int(b["missed"]),
                "neutral_timeout_n": int(b["neutral"]),
                "counterfactual_pnl_points_total": float(round(pnl, 5)),
                "counterfactual_pnl_points_avg": float(round(pnl / n, 5)) if n > 0 else 0.0,
                "recommendation": _recommend(int(b["saved"]), int(b["missed"]), pnl),
            }
        )

    window_rows: List[Dict[str, Any]] = []
    for win in sorted(by_window.keys()):
        b = by_window[win]
        n = int(b["n"])
        pnl = float(b["pnl"])
        window_rows.append(
            {
                "window": win,
                "samples_n": n,
                "saved_loss_n": int(b["saved"]),
                "missed_opportunity_n": int(b["missed"]),
                "neutral_timeout_n": int(b["neutral"]),
                "counterfactual_pnl_points_total": float(round(pnl, 5)),
                "counterfactual_pnl_points_avg": float(round(pnl / n, 5)) if n > 0 else 0.0,
                "recommendation": _recommend(int(b["saved"]), int(b["missed"]), pnl),
            }
        )

    symbol_window_rows: List[Dict[str, Any]] = []
    for key in sorted(by_symbol_window.keys()):
        sym, win = key
        b = by_symbol_window[key]
        n = int(b["n"])
        pnl = float(b["pnl"])
        symbol_window_rows.append(
            {
                "symbol": sym,
                "window": win,
                "samples_n": n,
                "saved_loss_n": int(b["saved"]),
                "missed_opportunity_n": int(b["missed"]),
                "neutral_timeout_n": int(b["neutral"]),
                "counterfactual_pnl_points_total": float(round(pnl, 5)),
                "counterfactual_pnl_points_avg": float(round(pnl / n, 5)) if n > 0 else 0.0,
                "recommendation": _recommend(int(b["saved"]), int(b["missed"]), pnl),
            }
        )

    return {
        "by_symbol": symbol_rows,
        "by_window": window_rows,
        "by_symbol_window": symbol_window_rows,
    }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Aggregate Stage-1 counterfactual rows into per-symbol/window summary.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--rows-jsonl", default="")
    ap.add_argument("--out-report", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"CF_SUMMARY_{stamp}"

    rows_jsonl = Path(args.rows_jsonl).resolve() if str(args.rows_jsonl).strip() else find_latest_rows_file(stage1_reports)
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_counterfactual_summary_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "ROWS_FILE_MISSING"
    rows: List[Dict[str, Any]] = []
    summary: Dict[str, Any] = {"by_symbol": [], "by_window": [], "by_symbol_window": []}
    if rows_jsonl is not None and rows_jsonl.exists():
        rows = list(iter_jsonl(rows_jsonl))
        if rows:
            summary = _collect_summary(rows)
            status = "PASS"
            reason = "SUMMARY_OK"
        else:
            reason = "ROWS_EMPTY"

    report = {
        "schema": "oanda.mt5.stage1_counterfactual_summary.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "rows_source": str(rows_jsonl) if rows_jsonl is not None else "",
        "summary": {
            "rows_total": int(len(rows)),
            "symbols_n": int(len(summary["by_symbol"])),
            "windows_n": int(len(summary["by_window"])),
        },
        "aggregates": summary,
    }
    out_report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    # latest pointers for panel/information module
    latest_json = ensure_write_parent(
        (stage1_reports / "stage1_counterfactual_summary_latest.json").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_txt = ensure_write_parent(
        (stage1_reports / "stage1_counterfactual_summary_latest.txt").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines: List[str] = []
    lines.append("STAGE1_COUNTERFACTUAL_SUMMARY")
    lines.append(f"Status: {status}")
    lines.append(f"Reason: {reason}")
    lines.append(f"Rows source: {rows_jsonl if rows_jsonl is not None else 'NONE'}")
    lines.append(f"Rows total: {report['summary']['rows_total']}")
    lines.append("")
    lines.append("PER_SYMBOL")
    for item in report["aggregates"]["by_symbol"]:
        lines.append(
            "- {0}: saved={1} missed={2} neutral={3} pnl_pts={4:.2f} rec={5}".format(
                item["symbol"],
                item["saved_loss_n"],
                item["missed_opportunity_n"],
                item["neutral_timeout_n"],
                float(item["counterfactual_pnl_points_total"]),
                item["recommendation"],
            )
        )
    lines.append("")
    lines.append("PER_WINDOW")
    for item in report["aggregates"]["by_window"]:
        lines.append(
            "- {0}: saved={1} missed={2} neutral={3} pnl_pts={4:.2f} rec={5}".format(
                item["window"],
                item["saved_loss_n"],
                item["missed_opportunity_n"],
                item["neutral_timeout_n"],
                float(item["counterfactual_pnl_points_total"]),
                item["recommendation"],
            )
        )
    latest_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    out_report.with_suffix(".txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # registry
    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash({"tool": "stage1_counterfactual_summary.v1"})
        ds_hash = file_sha256(rows_jsonl) if rows_jsonl is not None and rows_jsonl.exists() else ""
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_COUNTERFACTUAL_SUMMARY",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": ds_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps(report.get("summary") or {}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception as exc:
        _ = exc
    print(f"STAGE1_COUNTERFACTUAL_SUMMARY_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
