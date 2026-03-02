#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
from typing import Any, Dict

UTC = dt.timezone.utc


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_utc(raw: str | None) -> dt.datetime | None:
    if not raw:
        return None
    try:
        return dt.datetime.fromisoformat(str(raw).replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def load_json(path: Path) -> Dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return None


def latest_json(root: Path, pattern: str = "*.json") -> Path | None:
    if not root.exists():
        return None
    files = [p for p in root.glob(pattern) if p.is_file()]
    if not files:
        return None
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0]


def latest_json_prefer_status(root: Path, *, preferred_status: str = "PASS") -> Path | None:
    if not root.exists():
        return None
    files = [p for p in root.glob("*.json") if p.is_file()]
    if not files:
        return None
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    preferred = str(preferred_status).upper()
    for p in files:
        payload = load_json(p) or {}
        if str(payload.get("status", "")).upper() == preferred:
            return p
    return files[0]


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate lightweight LAB insights digest for operator panel.")
    ap.add_argument("--root", default=r"C:\OANDA_MT5_SYSTEM")
    ap.add_argument("--lab-data-root", default=r"C:\OANDA_MT5_LAB_DATA")
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve()
    now = dt.datetime.now(tz=UTC)
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    reports_ingest = lab_data_root / "reports" / "ingest"
    reports_daily = lab_data_root / "reports" / "daily"
    reports_retention = lab_data_root / "reports" / "retention"
    run_status = lab_data_root / "run" / "lab_scheduler_status.json"
    pointer_json = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.json"
    pointer_txt = root / "LAB" / "EVIDENCE" / "lab_insights" / "lab_insights_latest.txt"

    ingest_path = latest_json(reports_ingest)
    daily_path = latest_json_prefer_status(reports_daily, preferred_status="PASS")
    retention_path = latest_json(reports_retention)
    status_payload = load_json(run_status) or {}
    ingest_payload = load_json(ingest_path) if ingest_path else {}
    daily_payload = load_json(daily_path) if daily_path else {}
    retention_payload = load_json(retention_path) if retention_path else {}

    ingest_summary = dict((ingest_payload or {}).get("summary") or {})
    daily_summary = dict((daily_payload or {}).get("summary") or {})
    retention_summary = dict((retention_payload or {}).get("summary") or {})
    scheduler_status = str((status_payload or {}).get("status") or "UNKNOWN").upper()
    scheduler_reason = str((status_payload or {}).get("reason") or "UNKNOWN")

    pairs_ready = int(float(daily_summary.get("pairs_ready_for_shadow", 0) or 0))
    pairs_total = int(float(daily_summary.get("pairs_total", 0) or 0))
    explore_trades = int(float(daily_summary.get("explore_total_trades", 0) or 0))
    quality_grade = str(ingest_summary.get("quality_grade", "UNKNOWN")).upper()

    if pairs_ready > 0 and quality_grade == "OK":
        recommendation = "MASZ KANDYDATOW DO SHADOW: sprawdz top ranking per symbol/okno."
    elif scheduler_status == "PASS" and explore_trades > 0:
        recommendation = "TRYB UCZENIA DZIALA: zbieraj dane i monitoruj ranking co kilka godzin."
    elif scheduler_status == "SKIP":
        recommendation = "SCHEDULER POMINAL RUN: sprawdz powod i uruchom recznie, jesli trzeba."
    else:
        recommendation = "WYMAGANY PRZEGLAD: sprawdz status scheduler/ingest i logi."

    report = {
        "schema": "oanda_mt5.lab_insights_digest.v1",
        "generated_at_utc": iso_utc(now),
        "status": "PASS",
        "workspace_root": str(root),
        "lab_data_root": str(lab_data_root),
        "sources": {
            "scheduler_status_path": str(run_status),
            "latest_ingest_report_path": str(ingest_path) if ingest_path else "",
            "latest_daily_report_path": str(daily_path) if daily_path else "",
            "latest_retention_report_path": str(retention_path) if retention_path else "",
        },
        "snapshot": {
            "scheduler_status": scheduler_status,
            "scheduler_reason": scheduler_reason,
            "ingest_quality_grade": quality_grade,
            "ingest_rows_fetched_total": int(float(ingest_summary.get("rows_fetched_total", 0) or 0)),
            "ingest_rows_inserted_total": int(float(ingest_summary.get("rows_inserted_total", 0) or 0)),
            "ingest_symbols_resolved": int(float(ingest_summary.get("symbols_resolved", 0) or 0)),
            "pairs_ready_for_shadow": pairs_ready,
            "pairs_total": pairs_total,
            "explore_total_trades": explore_trades,
            "retention_removed_dirs": int(
                float((retention_summary.get("snapshot_dirs_removed", 0) if isinstance(retention_summary, dict) else 0) or 0)
            ),
        },
        "recommendation": recommendation,
    }

    if str(args.out).strip():
        out_path = Path(args.out).resolve()
    else:
        out_path = (lab_data_root / "reports" / "insights" / f"lab_insights_{stamp}.json").resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    pointer_payload = {
        "schema": "oanda_mt5.lab_insights_pointer.v1",
        "generated_at_utc": report["generated_at_utc"],
        "status": report["status"],
        "report_path": str(out_path),
        "snapshot": report["snapshot"],
        "recommendation": report["recommendation"],
    }
    pointer_json.parent.mkdir(parents=True, exist_ok=True)
    pointer_json.write_text(json.dumps(pointer_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    txt_lines = [
        "WNIOSEK Z LABORATORIUM",
        f"Generated UTC: {report['generated_at_utc']}",
        "",
        "[1] STAN RUNDY",
        f"- Scheduler: {scheduler_status} ({scheduler_reason})",
        f"- Jakosc ingestu: {quality_grade}",
        f"- Wiersze pobrane/wstawione: {report['snapshot']['ingest_rows_fetched_total']} / {report['snapshot']['ingest_rows_inserted_total']}",
        f"- Symbole rozwiazane: {report['snapshot']['ingest_symbols_resolved']}",
        "",
        "[2] STAN UCZENIA",
        f"- Pary gotowe do shadow: {pairs_ready}/{pairs_total}",
        f"- Explore trades: {explore_trades}",
        "",
        "[3] REKOMENDACJA",
        f"- {recommendation}",
        "",
        f"Pelny raport: {out_path}",
    ]
    pointer_txt.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

    print(json.dumps({"status": "PASS", "report_path": str(out_path), "pointer_path": str(pointer_json)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
