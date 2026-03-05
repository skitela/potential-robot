#!/usr/bin/env python3
"""
Stage-1 learning gate:
- checks per-symbol data coverage for rejected candidates and trade-path samples
- emits PASS/HOLD verdict for next learning cycle
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple


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


def _infer_group(sym: str) -> str:
    s = _symbol_base(sym)
    if not s:
        return ""
    if s in {"XAUUSD", "XAGUSD", "PLATIN", "PALLAD"} or s.startswith("COPPER") or s.startswith("GOLD"):
        return "METAL"
    if s.startswith("US") and any(ch.isdigit() for ch in s):
        return "INDEX"
    if len(s) == 6 and s.isalpha():
        return "FX"
    return ""


def _load_strategy_scope(root: Path) -> Tuple[List[str], Dict[str, str]]:
    cfg = root / "CONFIG" / "strategy.json"
    expected: List[str] = []
    groups: Dict[str, str] = {}
    try:
        obj = json.loads(cfg.read_text(encoding="utf-8"))
        syms = obj.get("symbols_to_trade")
        if isinstance(syms, list):
            expected = sorted({_symbol_base(x) for x in syms if str(x).strip()})
        raw_groups = obj.get("groups")
        if isinstance(raw_groups, dict):
            for k, v in raw_groups.items():
                kb = _symbol_base(str(k))
                if kb:
                    groups[kb] = str(v or "").upper()
    except Exception as exc:
        _ = exc
    return expected, groups


def _symbol_in_focus(sym: str, focus_group: str, sym_group: Dict[str, str]) -> bool:
    if str(focus_group).upper() == "ANY":
        return True
    g = str(sym_group.get(sym, "")).upper()
    if not g:
        g = _infer_group(sym)
    if not g:
        # Unknown group should not contaminate focused gate.
        return False
    return g == str(focus_group).upper()


_ENTRY_SKIP_RE = re.compile(
    r"ENTRY_SKIP(?:_PRE)?\s+symbol=(?P<symbol>\S+)\s+grp=(?P<grp>\S+)\s+mode=(?P<mode>\S+)\s+reason=(?P<reason>[A-Z0-9_]+)"
)


def _fallback_rejects_from_log(root: Path, focus_group: str, sym_group: Dict[str, str]) -> Dict[str, int]:
    out: Dict[str, int] = defaultdict(int)
    log_path = root / "LOGS" / "safetybot.log"
    if not log_path.exists():
        return out
    try:
        for line in log_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            m = _ENTRY_SKIP_RE.search(line)
            if not m:
                continue
            sym = _symbol_base(m.group("symbol"))
            if not sym:
                continue
            if not _symbol_in_focus(sym, focus_group, sym_group):
                continue
            out[sym] += 1
    except Exception:
        return defaultdict(int)
    return out


def _main() -> int:
    ap = argparse.ArgumentParser(description="Coverage gate for rejected candidates and trade-path samples.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM")
    ap.add_argument("--lookback-hours", type=int, default=24)
    ap.add_argument("--focus-group", default="ANY")
    ap.add_argument("--symbol-scope", choices=["strategy", "active"], default="strategy")
    ap.add_argument("--min-active-symbols", type=int, default=2)
    ap.add_argument("--min-total-per-symbol", type=int, default=30)
    ap.add_argument("--min-rejects-per-symbol", type=int, default=10)
    ap.add_argument("--min-trade-events-per-symbol", type=int, default=1)
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-txt", default="")
    args = ap.parse_args()

    root = Path(args.root).resolve()
    db_path = root / "DB" / "decision_events.sqlite"
    if not db_path.exists():
        raise SystemExit(f"DB missing: {db_path}")

    focus_group = str(args.focus_group or "ANY").upper()
    expected, sym_group = _load_strategy_scope(root)
    if focus_group != "ANY":
        expected = [s for s in expected if _symbol_in_focus(s, focus_group, sym_group)]

    since = _utc_now() - timedelta(hours=max(1, int(args.lookback_hours)))
    since_iso = _iso_z(since)

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    try:
        has_rejections = bool(
            conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='decision_rejections' LIMIT 1").fetchone()
        )

        rejects: Dict[str, int] = defaultdict(int)
        trades: Dict[str, int] = defaultdict(int)
        windows: Dict[str, set[str]] = defaultdict(set)

        if has_rejections:
            for r in conn.execute(
                "SELECT symbol, window_id FROM decision_rejections WHERE ts_utc >= ?",
                (since_iso,),
            ).fetchall():
                sym = _symbol_base(str(r["symbol"] or ""))
                if not sym:
                    continue
                if not _symbol_in_focus(sym, focus_group, sym_group):
                    continue
                rejects[sym] += 1
                wid = str(r["window_id"] or "").upper()
                if wid:
                    windows[sym].add(wid)

        for r in conn.execute(
            "SELECT choice_A FROM decision_events WHERE ts_utc >= ?",
            (since_iso,),
        ).fetchall():
            sym = _symbol_base(str(r["choice_A"] or ""))
            if not sym:
                continue
            if not _symbol_in_focus(sym, focus_group, sym_group):
                continue
            trades[sym] += 1

        if sum(rejects.values()) == 0:
            log_fallback = _fallback_rejects_from_log(root, focus_group, sym_group)
            for k, v in log_fallback.items():
                rejects[k] += int(v)

        observed = set(rejects.keys()) | set(trades.keys())
        scope_requested = str(args.symbol_scope or "strategy").lower()
        min_active_symbols = max(1, int(args.min_active_symbols))
        if scope_requested == "active":
            symbols = sorted(observed)
            scope_effective = "active"
            # Bezpieczny fallback: jeżeli aktywnych symboli prawie nie ma, nie luzujemy bramki.
            if len(symbols) < min_active_symbols:
                symbols = sorted(set(expected) | observed)
                scope_effective = "strategy_fallback_low_active"
        else:
            symbols = sorted(set(expected) | observed)
            scope_effective = "strategy"

        min_total = max(1, int(args.min_total_per_symbol))
        min_rejects = max(0, int(args.min_rejects_per_symbol))
        min_trades = max(0, int(args.min_trade_events_per_symbol))

        symbols_rows: List[Dict[str, Any]] = []
        blockers: List[str] = []
        for sym in symbols:
            rej = int(rejects.get(sym, 0))
            trd = int(trades.get(sym, 0))
            total = rej + trd
            active_windows = sorted(windows.get(sym, set()))
            row_status = "PASS"
            reasons: List[str] = []
            if total < min_total:
                row_status = "HOLD"
                reasons.append(f"TOTAL_LT_MIN:{total}<{min_total}")
            if rej < min_rejects:
                row_status = "HOLD"
                reasons.append(f"REJECTS_LT_MIN:{rej}<{min_rejects}")
            if trd < min_trades:
                row_status = "HOLD"
                reasons.append(f"TRADES_LT_MIN:{trd}<{min_trades}")
            if row_status != "PASS":
                blockers.append(f"{sym}:{'|'.join(reasons)}")
            symbols_rows.append(
                {
                    "symbol": sym,
                    "status": row_status,
                    "total_events_n": total,
                    "rejected_candidates_n": rej,
                    "trade_events_n": trd,
                    "active_windows": active_windows,
                    "reasons": reasons,
                }
            )

        verdict = "PASS" if not blockers else "HOLD"
        payload = {
            "schema": "oanda.mt5.rejected_coverage_gate.v1",
            "ts_utc": _iso_z(_utc_now()),
            "lookback_hours": int(args.lookback_hours),
            "since_utc": since_iso,
            "focus_group": focus_group,
            "thresholds": {
                "min_total_per_symbol": min_total,
                "min_rejects_per_symbol": min_rejects,
                "min_trade_events_per_symbol": min_trades,
            },
            "summary": {
                "symbols_total": len(symbols_rows),
                "symbols_pass": int(sum(1 for x in symbols_rows if x["status"] == "PASS")),
                "symbols_hold": int(sum(1 for x in symbols_rows if x["status"] != "PASS")),
                "decision_rejections_table_present": bool(has_rejections),
                "scope_mode_requested": scope_requested,
                "scope_mode_effective": scope_effective,
                "active_symbols_observed_n": len(observed),
            },
            "verdict": {
                "status": verdict,
                "blockers": blockers[:100],
            },
            "symbols": symbols_rows,
        }

        out_dir = root / "EVIDENCE" / "learning_coverage"
        out_dir.mkdir(parents=True, exist_ok=True)
        stamp = _utc_now().strftime("%Y%m%dT%H%M%SZ")
        out_json = Path(args.out_json) if str(args.out_json).strip() else (out_dir / f"rejected_coverage_gate_{stamp}.json")
        out_txt = Path(args.out_txt) if str(args.out_txt).strip() else (out_dir / f"rejected_coverage_gate_{stamp}.txt")
        out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

        lines = [
            "REJECTED COVERAGE GATE",
            f"Verdict: {verdict}",
            f"Lookback: {int(args.lookback_hours)}h | Focus group: {focus_group}",
            f"Scope mode: {scope_effective} (requested={scope_requested}, active_symbols={len(observed)})",
            "Thresholds: total>={0}, rejects>={1}, trades>={2}".format(min_total, min_rejects, min_trades),
            "",
        ]
        for row in symbols_rows:
            lines.append(
                "[{0}] {1} total={2} rejects={3} trades={4} windows={5}".format(
                    row["symbol"],
                    row["status"],
                    row["total_events_n"],
                    row["rejected_candidates_n"],
                    row["trade_events_n"],
                    ",".join(row["active_windows"]) if row["active_windows"] else "NONE",
                )
            )
            if row["reasons"]:
                lines.append("  reasons=" + ";".join(row["reasons"]))
        out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")

        print(f"REJECTED_COVERAGE_GATE_OK verdict={verdict} json={out_json} txt={out_txt}")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
