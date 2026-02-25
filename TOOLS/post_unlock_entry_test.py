from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import time
from pathlib import Path
from typing import Dict, List


ENTRY_SIGNAL_RX = re.compile(r"\bENTRY_SIGNAL\b", re.IGNORECASE)
ENTRY_READY_RX = re.compile(r"\bENTRY_READY\b", re.IGNORECASE)
DISPATCH_RX = re.compile(r"\bHYBRID_DISPATCH\b", re.IGNORECASE)
DISPATCH_REJECT_RX = re.compile(r"\bHYBRID_DISPATCH_REJECT\b", re.IGNORECASE)
ORDER_SUCCESS_RX = re.compile(r"\bOrder executed:\s*10009\b|\bTRADE_RETCODE_DONE\b", re.IGNORECASE)
ORDER_FAIL_RX = re.compile(r"\bOrder failed:\b", re.IGNORECASE)
SKIP_REASON_RX = re.compile(r"\bENTRY_SKIP(?:_PRE)?\b.*?\breason=([A-Z0-9_]+)\b", re.IGNORECASE)
RETCODE_RX = re.compile(r"\bretcode=(\d+)\b", re.IGNORECASE)


def _read_appended(path: Path, offset: int) -> tuple[str, int]:
    if not path.exists():
        return "", offset
    size = path.stat().st_size
    if offset < 0:
        offset = 0
    if size < offset:
        offset = 0
    if size == offset:
        return "", offset
    with path.open("rb") as f:
        f.seek(offset)
        data = f.read()
    return data.decode("utf-8", errors="ignore"), size


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _to_top_pairs(d: Dict[str, int], n: int = 8) -> List[Dict[str, int | str]]:
    out = [{"key": k, "count": int(v)} for k, v in d.items()]
    out.sort(key=lambda x: int(x["count"]), reverse=True)
    return out[:n]


def _write_report_json_txt(out_json: Path, payload: dict) -> Path:
    out_json.parent.mkdir(parents=True, exist_ok=True)
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    out_txt = out_json.with_suffix(".txt")
    lines: List[str] = []
    lines.append("===== POST UNLOCK ENTRY TEST =====")
    lines.append(f"start_utc: {payload.get('start_utc')}")
    lines.append(f"end_utc: {payload.get('end_utc')}")
    lines.append(f"duration_sec: {payload.get('duration_sec')}")
    lines.append(f"log_path: {payload.get('log_path')}")
    lines.append("")
    lines.append("[Counts]")
    counts = payload.get("counts", {}) or {}
    for k in (
        "entry_ready",
        "entry_signal",
        "dispatch",
        "dispatch_reject",
        "order_success",
        "order_failed",
    ):
        lines.append(f"{k}={int(counts.get(k, 0))}")
    lines.append("")
    lines.append("[Retcodes]")
    retcodes = payload.get("retcodes", {}) or {}
    if not retcodes:
        lines.append("none")
    else:
        for k in sorted(retcodes.keys(), key=lambda x: int(x)):
            lines.append(f"{k}={int(retcodes[k])}")
    lines.append("")
    lines.append("[Top Skip Reasons]")
    top_skip = payload.get("top_skip_reasons", []) or []
    if not top_skip:
        lines.append("none")
    else:
        for it in top_skip:
            lines.append(f"{it.get('key')}={int(it.get('count', 0))}")
    lines.append("")
    lines.append("[Verdict]")
    lines.append(f"verdict={payload.get('verdict')}")
    lines.append(f"reason={payload.get('reason')}")
    lines.append("")
    lines.append("[Hints]")
    for h in payload.get("hints", []) or []:
        lines.append(f"- {h}")
    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out_txt


def run(root: Path, minutes: int, poll_sec: int) -> int:
    log_path = root / "LOGS" / "safetybot.log"
    out_dir = root / "RUN" / "DIAG_REPORTS"
    out_dir.mkdir(parents=True, exist_ok=True)

    start = _utc_now()
    deadline = time.time() + max(1, int(minutes)) * 60
    offset = log_path.stat().st_size if log_path.exists() else 0

    counts = {
        "entry_ready": 0,
        "entry_signal": 0,
        "dispatch": 0,
        "dispatch_reject": 0,
        "order_success": 0,
        "order_failed": 0,
    }
    retcodes: Dict[str, int] = {}
    skip_reasons: Dict[str, int] = {}

    while time.time() < deadline:
        chunk, offset = _read_appended(log_path, offset)
        if chunk:
            for raw_line in chunk.splitlines():
                line = str(raw_line)
                if ENTRY_READY_RX.search(line):
                    counts["entry_ready"] += 1
                if ENTRY_SIGNAL_RX.search(line):
                    counts["entry_signal"] += 1
                if DISPATCH_RX.search(line):
                    counts["dispatch"] += 1
                if DISPATCH_REJECT_RX.search(line):
                    counts["dispatch_reject"] += 1
                if ORDER_SUCCESS_RX.search(line):
                    counts["order_success"] += 1
                if ORDER_FAIL_RX.search(line):
                    counts["order_failed"] += 1
                m_code = RETCODE_RX.search(line)
                if m_code:
                    code = str(m_code.group(1))
                    retcodes[code] = int(retcodes.get(code, 0)) + 1
                m_skip = SKIP_REASON_RX.search(line)
                if m_skip:
                    reason = str(m_skip.group(1)).upper()
                    skip_reasons[reason] = int(skip_reasons.get(reason, 0)) + 1
        time.sleep(max(1, int(poll_sec)))

    end = _utc_now()
    duration_sec = int((end - start).total_seconds())

    verdict = "WARN_NO_ACTIVITY"
    reason = "No entry signal during observation window."
    hints: List[str] = []
    if counts["order_success"] > 0:
        verdict = "PASS_EXECUTED"
        reason = "At least one order was executed."
    elif int(retcodes.get("10017", 0)) > 0:
        verdict = "FAIL_TRADE_DISABLED"
        reason = "retcode=10017 seen (account trade disabled or broker-side block)."
        hints.append("Sprawdz ponownie logowanie haslem MASTER (nie inwestorskim).")
        hints.append("Potwierdz u brokera flage trade_allowed=True dla rachunku MT5.")
    elif counts["entry_signal"] > 0 and counts["dispatch_reject"] > 0:
        verdict = "FAIL_REJECTED"
        reason = "Entry signals exist, but all dispatches were rejected."
        hints.append("Sprawdz retcode i comment w safetybot.log.")
    elif counts["entry_signal"] > 0:
        verdict = "WARN_SIGNAL_NO_RESULT"
        reason = "Entry signals were produced, but no final execution/fail line was seen."
    else:
        hints.append("Brak sygnalow: sprawdz okno czasowe i powody ENTRY_SKIP.")

    ts = end.strftime("%Y%m%d_%H%M%S")
    out_json = out_dir / f"POST_UNLOCK_ENTRY_TEST_{ts}.json"
    payload = {
        "start_utc": start.isoformat().replace("+00:00", "Z"),
        "end_utc": end.isoformat().replace("+00:00", "Z"),
        "duration_sec": duration_sec,
        "log_path": str(log_path),
        "counts": counts,
        "retcodes": retcodes,
        "top_skip_reasons": _to_top_pairs(skip_reasons, n=8),
        "verdict": verdict,
        "reason": reason,
        "hints": hints,
    }
    out_txt = _write_report_json_txt(out_json, payload)

    print("POST_UNLOCK_ENTRY_TEST_DONE")
    print(f"report_json={out_json}")
    print(f"report_txt={out_txt}")
    print(f"verdict={verdict}")

    if verdict == "PASS_EXECUTED":
        return 0
    if verdict == "FAIL_TRADE_DISABLED":
        return 2
    if verdict == "FAIL_REJECTED":
        return 3
    return 4


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path("C:/OANDA_MT5_SYSTEM"))
    parser.add_argument("--minutes", type=int, default=6)
    parser.add_argument("--poll-sec", type=int, default=2)
    args = parser.parse_args()

    root = args.root.resolve()
    if not root.exists():
        print(f"ERROR: root not found: {root}", file=sys.stderr)
        return 10
    return run(root=root, minutes=int(args.minutes), poll_sec=int(args.poll_sec))


if __name__ == "__main__":
    raise SystemExit(main())
