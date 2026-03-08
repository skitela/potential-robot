#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

SCHEMA = "oanda.mt5.kernel_shadow_parity_report.v1"

STATE_RE = re.compile(
    r"KERNEL_SHADOW_STATE\s+src=(?P<src>[A-Z_]+)\s+symbol=(?P<symbol>[A-Z0-9_.\-]+)\s+"
    r"action=(?P<action>[A-Z_]+)\s+reason=(?P<reason>[A-Z0-9_]+)\s+profile_loaded=(?P<profile_loaded>[01])"
)
PARITY_RE = re.compile(
    r"KERNEL_SHADOW_TRADE_PARITY\s+parity=(?P<parity>MATCH|MISMATCH)\s+symbol=(?P<symbol>[A-Z0-9_.\-]+)\s+"
    r"legacy_allowed=(?P<legacy_allowed>[01])\s+legacy_reason=(?P<legacy_reason>[A-Z0-9_]+)\s+"
    r"kernel_action=(?P<kernel_action>[A-Z_]+)\s+kernel_reason=(?P<kernel_reason>[A-Z0-9_]+)"
)
TIME_RE = re.compile(r"\b(?P<hh>\d{2}):(?P<mm>\d{2}):(?P<ss>\d{2})(?:\.(?P<ms>\d{1,3}))?\b")


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso_utc(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _safe_read_json(path: Path) -> Dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
    except Exception:
        return {}


def _dig_for_str(obj: Any, key: str) -> Optional[str]:
    if isinstance(obj, dict):
        if key in obj and isinstance(obj.get(key), str) and str(obj.get(key)).strip():
            return str(obj.get(key)).strip()
        for value in obj.values():
            found = _dig_for_str(value, key)
            if found:
                return found
    elif isinstance(obj, list):
        for value in obj:
            found = _dig_for_str(value, key)
            if found:
                return found
    return None


def _resolve_mt5_data_dir(root: Path) -> Optional[Path]:
    # 1) session guard status
    status_path = root / "RUN" / "mt5_session_guard_status.json"
    if status_path.exists():
        status = _safe_read_json(status_path)
        value = _dig_for_str(status, "mt5_data_dir")
        if value:
            p = Path(value)
            if p.exists():
                return p

    # 2) latest full diagnostic
    diag_dir = root / "RUN" / "DIAG_REPORTS"
    if diag_dir.exists():
        diag_files = sorted(diag_dir.glob("MT5_FULL_DIAG_*.json"), key=lambda x: x.stat().st_mtime, reverse=True)
        for diag in diag_files[:10]:
            payload = _safe_read_json(diag)
            value = _dig_for_str(payload, "terminal_data_dir")
            if value:
                p = Path(value)
                if p.exists():
                    return p

    # 3) APPDATA fallback
    appdata = Path.home() / "AppData" / "Roaming" / "MetaQuotes" / "Terminal"
    if appdata.exists():
        candidates = sorted(
            [p for p in appdata.glob("*") if (p / "config" / "common.ini").exists()],
            key=lambda x: x.stat().st_mtime,
            reverse=True,
        )
        if candidates:
            return candidates[0]
    return None


def _resolve_latest_mql_log(mt5_data_dir: Path) -> Optional[Path]:
    log_dir = mt5_data_dir / "MQL5" / "Logs"
    if not log_dir.exists():
        return None
    files = sorted(log_dir.glob("*.log"), key=lambda x: x.stat().st_mtime, reverse=True)
    return files[0] if files else None


def _parse_line_ts_utc(line: str, log_date_utc: datetime) -> Optional[datetime]:
    m = TIME_RE.search(line)
    if not m:
        return None
    try:
        hh = int(m.group("hh"))
        mm = int(m.group("mm"))
        ss = int(m.group("ss"))
        ms_raw = str(m.group("ms") or "0")
        ms = int((ms_raw + "000")[:3])
        return datetime(
            log_date_utc.year,
            log_date_utc.month,
            log_date_utc.day,
            hh,
            mm,
            ss,
            ms * 1000,
            tzinfo=timezone.utc,
        )
    except Exception:
        return None


def _parse_state_line(line: str) -> Optional[Dict[str, Any]]:
    m = STATE_RE.search(line)
    if not m:
        return None
    return {
        "src": str(m.group("src")),
        "symbol": str(m.group("symbol")).upper(),
        "action": str(m.group("action")).upper(),
        "reason": str(m.group("reason")).upper(),
        "profile_loaded": bool(int(m.group("profile_loaded"))),
    }


def _parse_parity_line(line: str) -> Optional[Dict[str, Any]]:
    m = PARITY_RE.search(line)
    if not m:
        return None
    return {
        "parity": str(m.group("parity")).upper(),
        "symbol": str(m.group("symbol")).upper(),
        "legacy_allowed": bool(int(m.group("legacy_allowed"))),
        "legacy_reason": str(m.group("legacy_reason")).upper(),
        "kernel_action": str(m.group("kernel_action")).upper(),
        "kernel_reason": str(m.group("kernel_reason")).upper(),
    }


def _iter_lines(path: Path) -> Iterable[str]:
    if not path.exists():
        return []
    try:
        return path.read_text(encoding="utf-16", errors="ignore").splitlines()
    except Exception:
        return path.read_text(encoding="utf-8", errors="ignore").splitlines()


def build_report(root: Path, *, hours: int, mt5_data_dir: Optional[Path], log_path: Optional[Path]) -> Dict[str, Any]:
    now_utc = _utc_now()
    window_hours = max(1, int(hours))
    cutoff = now_utc - timedelta(hours=window_hours)

    resolved_data_dir = mt5_data_dir or _resolve_mt5_data_dir(root)
    resolved_log = log_path or (_resolve_latest_mql_log(resolved_data_dir) if resolved_data_dir else None)

    if not resolved_log or not resolved_log.exists():
        return {
            "schema": SCHEMA,
            "generated_at_utc": _iso_utc(now_utc),
            "root": str(root),
            "status": "NO_LOG",
            "inputs": {
                "hours": window_hours,
                "mt5_data_dir": str(resolved_data_dir) if resolved_data_dir else "MISSING",
                "mql_log": str(resolved_log) if resolved_log else "MISSING",
            },
            "summary": {},
            "counts": {},
            "notes": ["Brak logu MQL5 do analizy parity kernela."],
        }

    log_date = datetime.strptime(resolved_log.stem, "%Y%m%d").replace(tzinfo=timezone.utc)
    state_count = 0
    state_profile_not_loaded = 0
    state_by_action: Counter[str] = Counter()
    state_by_reason: Counter[str] = Counter()
    state_by_symbol: Dict[str, Counter[str]] = defaultdict(Counter)

    parity_count = 0
    parity_match = 0
    parity_mismatch = 0
    mismatch_by_symbol: Counter[str] = Counter()
    mismatch_kernel_reason: Counter[str] = Counter()

    for line in _iter_lines(resolved_log):
        ts = _parse_line_ts_utc(line, log_date)
        if ts and ts < cutoff:
            continue

        state = _parse_state_line(line)
        if state:
            state_count += 1
            state_by_action[state["action"]] += 1
            state_by_reason[state["reason"]] += 1
            state_by_symbol[state["symbol"]][state["action"]] += 1
            if not bool(state["profile_loaded"]):
                state_profile_not_loaded += 1
            continue

        parity = _parse_parity_line(line)
        if parity:
            parity_count += 1
            if parity["parity"] == "MATCH":
                parity_match += 1
            else:
                parity_mismatch += 1
                mismatch_by_symbol[parity["symbol"]] += 1
                mismatch_kernel_reason[parity["kernel_reason"]] += 1

    mismatch_ratio = (float(parity_mismatch) / float(parity_count)) if parity_count > 0 else None
    status = "PASS"
    notes = []
    if parity_count == 0:
        status = "NO_PARITY_DATA"
        notes.append("Brak wpisow KERNEL_SHADOW_TRADE_PARITY w oknie analizy.")
    if state_profile_not_loaded > 0:
        if status == "PASS":
            status = "WARN"
        notes.append("Wykryto KERNEL_SHADOW_STATE z reason=PROFILE_NOT_LOADED.")
    if mismatch_ratio is not None and mismatch_ratio > 0.10:
        status = "WARN"
        notes.append("Parity mismatch ratio przekracza 10%.")

    return {
        "schema": SCHEMA,
        "generated_at_utc": _iso_utc(now_utc),
        "root": str(root),
        "status": status,
        "inputs": {
            "hours": window_hours,
            "window_start_utc": _iso_utc(cutoff),
            "window_end_utc": _iso_utc(now_utc),
            "mt5_data_dir": str(resolved_data_dir) if resolved_data_dir else "MISSING",
            "mql_log": str(resolved_log),
        },
        "summary": {
            "state_rows": state_count,
            "state_profile_not_loaded_rows": state_profile_not_loaded,
            "parity_rows": parity_count,
            "parity_match": parity_match,
            "parity_mismatch": parity_mismatch,
            "parity_mismatch_ratio": mismatch_ratio,
        },
        "counts": {
            "state_by_action": dict(state_by_action),
            "state_by_reason_top10": [{"reason": k, "count": int(v)} for k, v in state_by_reason.most_common(10)],
            "state_by_symbol_top10": [
                {"symbol": sym, "actions": dict(cnt)}
                for sym, cnt in sorted(state_by_symbol.items(), key=lambda kv: sum(kv[1].values()), reverse=True)[:10]
            ],
            "parity_mismatch_by_symbol_top10": [
                {"symbol": sym, "count": int(cnt)} for sym, cnt in mismatch_by_symbol.most_common(10)
            ],
            "parity_mismatch_kernel_reason_top10": [
                {"reason": reason, "count": int(cnt)} for reason, cnt in mismatch_kernel_reason.most_common(10)
            ],
        },
        "notes": notes,
    }


def render_txt(report: Dict[str, Any]) -> str:
    summary = dict(report.get("summary") or {})
    lines = [
        "KERNEL SHADOW PARITY REPORT",
        f"Status: {report.get('status', 'UNKNOWN')}",
        f"Window: {report.get('inputs', {}).get('window_start_utc', 'UNKNOWN')} -> {report.get('inputs', {}).get('window_end_utc', 'UNKNOWN')}",
        (
            "Rows: "
            f"state={summary.get('state_rows', 0)} "
            f"profile_not_loaded={summary.get('state_profile_not_loaded_rows', 0)} "
            f"parity={summary.get('parity_rows', 0)} "
            f"match={summary.get('parity_match', 0)} "
            f"mismatch={summary.get('parity_mismatch', 0)} "
            f"mismatch_ratio={summary.get('parity_mismatch_ratio', 'UNKNOWN')}"
        ),
    ]
    reasons = report.get("counts", {}).get("state_by_reason_top10", [])
    lines.append("Top state reasons:")
    if isinstance(reasons, list) and reasons:
        for item in reasons:
            if isinstance(item, dict):
                lines.append(f"- {item.get('reason')}: {item.get('count')}")
    else:
        lines.append("- brak danych")

    notes = report.get("notes", [])
    lines.append("Notes:")
    if isinstance(notes, list) and notes:
        for item in notes:
            lines.append(f"- {item}")
    else:
        lines.append("- brak")
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Build kernel shadow parity report from MT5 MQL logs.")
    ap.add_argument("--root", default="C:/OANDA_MT5_SYSTEM")
    ap.add_argument("--hours", type=int, default=6)
    ap.add_argument("--mt5-data-dir", default="")
    ap.add_argument("--mql-log", default="")
    ap.add_argument("--out-json", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
    out_json = Path(args.out_json).resolve() if str(args.out_json).strip() else (
        root / "EVIDENCE" / "kernel_shadow" / f"kernel_shadow_parity_report_{stamp}.json"
    ).resolve()
    out_txt = out_json.with_suffix(".txt")
    out_json.parent.mkdir(parents=True, exist_ok=True)

    mt5_data_dir = Path(args.mt5_data_dir).resolve() if str(args.mt5_data_dir).strip() else None
    mql_log = Path(args.mql_log).resolve() if str(args.mql_log).strip() else None

    report = build_report(root, hours=int(args.hours), mt5_data_dir=mt5_data_dir, log_path=mql_log)
    out_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    out_txt.write_text(render_txt(report), encoding="utf-8")

    latest_json = out_json.parent / "kernel_shadow_parity_report_latest.json"
    latest_txt = out_json.parent / "kernel_shadow_parity_report_latest.txt"
    latest_json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    latest_txt.write_text(render_txt(report), encoding="utf-8")

    print(
        "KERNEL_SHADOW_PARITY_REPORT_DONE "
        f"status={report.get('status')} "
        f"parity_rows={report.get('summary', {}).get('parity_rows', 0)} "
        f"mismatch={report.get('summary', {}).get('parity_mismatch', 0)} "
        f"json={out_json}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
