#!/usr/bin/env python3
"""
Build a lightweight stage-1 learning dataset from runtime DB:
- rejected candidates (NO_TRADE)
- trade-path decision events (TRADE_PATH)

This dataset is advisory/learning-only (no direct execution impact).
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List


def _utc_now() -> datetime:
    return datetime.now(timezone.utc)


def _iso_z(dt_obj: datetime) -> str:
    return dt_obj.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _symbol_base(sym: str) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def _infer_side(signal: str) -> str:
    s = str(signal or "").strip().upper()
    if "BUY" in s or "LONG" in s:
        return "LONG"
    if "SELL" in s or "SHORT" in s:
        return "SHORT"
    return "UNKNOWN"


def _normalize_command_type(raw: str, default: str) -> str:
    ct = str(raw or "").strip().upper()
    if not ct:
        return str(default).upper()
    if ct in {"HEARTBEAT", "TRADE_PATH", "OTHER"}:
        return ct
    if "TRADE" in ct:
        return "TRADE_PATH"
    if "HEARTBEAT" in ct:
        return "HEARTBEAT"
    return "OTHER"


_ENTRY_SKIP_RE = re.compile(
    r"ENTRY_SKIP(?:_PRE)?\s+symbol=(?P<symbol>\S+)\s+grp=(?P<grp>\S+)\s+mode=(?P<mode>\S+)\s+reason=(?P<reason>[A-Z0-9_]+)"
)
_LOG_TS_RE = re.compile(
    r"(?P<y>\d{4})[.\-](?P<m>\d{2})[.\-](?P<d>\d{2})\s+"
    r"(?P<h>\d{2}):(?P<mi>\d{2}):(?P<s>\d{2})(?:[.,](?P<ms>\d{1,6}))?"
)


def _extract_ts_from_log_line(line: str) -> str:
    m = _LOG_TS_RE.search(str(line or ""))
    if not m:
        return ""
    try:
        micros = str(m.group("ms") or "0").ljust(6, "0")[:6]
        local_tz = dt.datetime.now().astimezone().tzinfo or timezone.utc
        parsed = dt.datetime(
            int(m.group("y")),
            int(m.group("m")),
            int(m.group("d")),
            int(m.group("h")),
            int(m.group("mi")),
            int(m.group("s")),
            int(micros),
            tzinfo=local_tz,
        ).astimezone(timezone.utc)
        return parsed.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    except Exception:
        return ""


def _fallback_no_trade_from_log(root: Path) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    log_path = root / "LOGS" / "safetybot.log"
    if not log_path.exists():
        return out
    try:
        for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = _ENTRY_SKIP_RE.search(line)
            if not m:
                continue
            out.append(
                {
                    "ts_utc": _extract_ts_from_log_line(line),
                    "symbol": _symbol_base(m.group("symbol")),
                    "instrument": _symbol_base(m.group("symbol")),
                    "grp": str(m.group("grp") or ""),
                    "mode": str(m.group("mode") or ""),
                    "sample_type": "NO_TRADE",
                    "label": str(m.group("reason") or "UNKNOWN"),
                    "reason_class": "LOG_FALLBACK",
                    "stage": "UNKNOWN",
                    "decision_stage": "UNKNOWN",
                    "gate_result": "BLOCK",
                    "side": "UNKNOWN",
                    "signal": "",
                    "session_state": "",
                    "regime": "",
                    "regime_state": "",
                    "command_type": "OTHER",
                    "source_module": "RUNTIME_LOG",
                    "label_quality": "OBSERVED",
                    "window_id": "",
                    "window_phase": "",
                    "context": {"source": "safetybot.log"},
                }
            )
    except Exception:
        return []
    return out


def _main() -> int:
    ap = argparse.ArgumentParser(description="Build stage-1 learning dataset from runtime DB.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM")
    ap.add_argument("--lookback-hours", type=int, default=24)
    ap.add_argument("--out-jsonl", default="")
    ap.add_argument("--out-meta", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    db_path = root / "DB" / "decision_events.sqlite"
    if not db_path.exists():
        raise SystemExit(f"DB missing: {db_path}")

    since = _utc_now() - timedelta(hours=max(1, int(args.lookback_hours)))
    since_iso = _iso_z(since)
    now_iso = _iso_z(_utc_now())

    out_dir = root / "EVIDENCE" / "learning_dataset"
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
    out_jsonl = Path(args.out_jsonl) if str(args.out_jsonl).strip() else (out_dir / f"stage1_learning_{stamp}.jsonl")
    out_meta = Path(args.out_meta) if str(args.out_meta).strip() else (out_dir / f"stage1_learning_{stamp}.meta.json")

    rows_out: List[Dict[str, Any]] = []
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        has_rejections = bool(
            conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='decision_rejections' LIMIT 1").fetchone()
        )
        if has_rejections:
            for r in conn.execute(
                """SELECT ts_utc,symbol,grp,mode,reason_code,reason_class,stage,signal,regime,window_id,window_phase,context_json
                   FROM decision_rejections
                   WHERE ts_utc >= ?""",
                (since_iso,),
            ).fetchall():
                ctx_obj: Dict[str, Any] = {}
                try:
                    ctx_obj = json.loads(str(r["context_json"] or "{}"))
                    if not isinstance(ctx_obj, dict):
                        ctx_obj = {}
                except Exception:
                    ctx_obj = {}
                rows_out.append(
                    {
                        "ts_utc": str(r["ts_utc"]),
                        "symbol": _symbol_base(str(r["symbol"] or "")),
                        "instrument": _symbol_base(str(r["symbol"] or "")),
                        "grp": str(r["grp"] or ""),
                        "mode": str(r["mode"] or ""),
                        "sample_type": "NO_TRADE",
                        "label": str(r["reason_code"] or "UNKNOWN"),
                        "reason_class": str(r["reason_class"] or "OTHER"),
                        "stage": str(r["stage"] or ""),
                        "decision_stage": str(r["stage"] or ""),
                        "gate_result": "BLOCK",
                        "side": "UNKNOWN",
                        "signal": str(r["signal"] or ""),
                        "session_state": str(r["window_phase"] or ""),
                        "regime": str(r["regime"] or ""),
                        "regime_state": str(r["regime"] or ""),
                        "command_type": _normalize_command_type(ctx_obj.get("command_type"), "OTHER"),
                        "source_module": str(ctx_obj.get("source_module") or "RUNTIME_DB"),
                        "label_quality": "OBSERVED",
                        "window_id": str(r["window_id"] or ""),
                        "window_phase": str(r["window_phase"] or ""),
                        "context": ctx_obj,
                    }
                )

        for r in conn.execute(
            """SELECT ts_utc,choice_A,grp,symbol_mode,signal,signal_reason,regime,window_id,window_phase,entry_score,entry_min_score,spread_points,outcome_pnl_net
               FROM decision_events
               WHERE ts_utc >= ?""",
            (since_iso,),
        ).fetchall():
            rows_out.append(
                {
                    "ts_utc": str(r["ts_utc"]),
                    "symbol": _symbol_base(str(r["choice_A"] or "")),
                    "instrument": _symbol_base(str(r["choice_A"] or "")),
                    "grp": str(r["grp"] or ""),
                    "mode": str(r["symbol_mode"] or ""),
                    "sample_type": "TRADE_PATH",
                    "label": "TRADE_ATTEMPT",
                    "reason_class": "TRADE_PATH",
                    "stage": "EXECUTION",
                    "decision_stage": "EXECUTION",
                    "gate_result": "ALLOW",
                    "side": _infer_side(str(r["signal"] or "")),
                    "signal": str(r["signal"] or ""),
                    "session_state": str(r["window_phase"] or ""),
                    "regime": str(r["regime"] or ""),
                    "regime_state": str(r["regime"] or ""),
                    "command_type": "TRADE_PATH",
                    "source_module": "RUNTIME_DB",
                    "label_quality": "REALIZED" if r["outcome_pnl_net"] is not None else "OBSERVED",
                    "window_id": str(r["window_id"] or ""),
                    "window_phase": str(r["window_phase"] or ""),
                    "context": {
                        "signal_reason": str(r["signal_reason"] or ""),
                        "entry_score": r["entry_score"],
                        "entry_min_score": r["entry_min_score"],
                        "spread_points": r["spread_points"],
                        "outcome_pnl_net": r["outcome_pnl_net"],
                    },
                }
            )
    finally:
        conn.close()

    with out_jsonl.open("w", encoding="utf-8") as f:
        for row in rows_out:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    symbols = sorted({str(r.get("symbol") or "") for r in rows_out if str(r.get("symbol") or "")})
    no_trade_n = int(sum(1 for r in rows_out if r.get("sample_type") == "NO_TRADE"))
    if no_trade_n == 0:
        fallback_rows = _fallback_no_trade_from_log(root)
        if fallback_rows:
            rows_out.extend(fallback_rows)
            with out_jsonl.open("a", encoding="utf-8") as f:
                for row in fallback_rows:
                    f.write(json.dumps(row, ensure_ascii=False) + "\n")
            symbols = sorted({str(r.get("symbol") or "") for r in rows_out if str(r.get("symbol") or "")})
            no_trade_n = int(sum(1 for r in rows_out if r.get("sample_type") == "NO_TRADE"))
    trade_path_n = int(sum(1 for r in rows_out if r.get("sample_type") == "TRADE_PATH"))
    reason_class_counts: Dict[str, int] = {}
    command_type_counts: Dict[str, int] = {}
    for r in rows_out:
        rc = str(r.get("reason_class") or "UNKNOWN").upper()
        ct = _normalize_command_type(str(r.get("command_type") or ""), "OTHER")
        reason_class_counts[rc] = int(reason_class_counts.get(rc, 0)) + 1
        command_type_counts[ct] = int(command_type_counts.get(ct, 0)) + 1
    meta = {
        "schema": "oanda.mt5.stage1_learning_dataset.v2",
        "ts_utc": now_iso,
        "since_utc": since_iso,
        "lookback_hours": int(args.lookback_hours),
        "rows_total": len(rows_out),
        "rows_no_trade": no_trade_n,
        "rows_trade_path": trade_path_n,
        "symbols": symbols,
        "reason_class_counts": reason_class_counts,
        "command_type_counts": command_type_counts,
        "source_db": str(db_path),
        "dataset_path": str(out_jsonl),
    }
    out_meta.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"STAGE1_DATASET_OK rows={len(rows_out)} no_trade={no_trade_n} trade_path={trade_path_n} jsonl={out_jsonl}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
