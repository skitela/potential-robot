#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import math
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

UTC = dt.timezone.utc


@dataclass
class KeyStats:
    window_id: str
    symbol: str
    days: set[str] = field(default_factory=set)
    trades: int = 0
    wins: int = 0
    losses: int = 0
    net_pips_sum: float = 0.0
    gross_pips_sum: float = 0.0
    cost_pips_sum: float = 0.0
    negative_days: int = 0

    @property
    def win_rate(self) -> float:
        if self.trades <= 0:
            return 0.0
        return float(self.wins) / float(self.trades)

    @property
    def net_pips_per_trade(self) -> float:
        if self.trades <= 0:
            return 0.0
        return float(self.net_pips_sum) / float(self.trades)

    @property
    def loss_day_ratio(self) -> float:
        if not self.days:
            return 1.0
        return float(self.negative_days) / float(len(self.days))

    @property
    def cost_share(self) -> float:
        gross_abs = abs(float(self.gross_pips_sum))
        if gross_abs <= 1e-12:
            return 1.0 if self.cost_pips_sum > 0.0 else 0.0
        return max(0.0, min(1.5, float(self.cost_pips_sum) / gross_abs))


def now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def write_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    text = json.dumps(payload, indent=2, ensure_ascii=False)
    try:
        tmp.write_text(text + "\n", encoding="utf-8")
        tmp.replace(path)
    except Exception:
        path.write_text(text + "\n", encoding="utf-8")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def should_skip_daily(state_path: Path, current: dt.datetime) -> bool:
    if not state_path.exists():
        return False
    try:
        payload = load_json(state_path)
    except Exception:
        return False
    raw = str(payload.get("last_run_ts_utc") or "").strip()
    if not raw:
        return False
    try:
        ts = dt.datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return False
    return ts.date() == current.date()


def update_daily_state(state_path: Path, current: dt.datetime, status: str, report_path: Path) -> None:
    write_json(
        state_path,
        {
            "last_run_ts_utc": iso_utc(current),
            "last_status": str(status),
            "last_report_path": str(report_path),
        },
    )


def resolve_python_exe(raw: str) -> str:
    candidate = str(raw or "").strip()
    if candidate:
        p = Path(candidate)
        if p.is_file():
            return str(p)
    return str(sys.executable)


def read_window_groups(strategy_path: Path) -> Dict[str, str]:
    cfg = load_json(strategy_path)
    windows = cfg.get("trade_windows") or {}
    out: Dict[str, str] = {}
    for k, v in windows.items():
        if not isinstance(v, dict):
            continue
        out[str(k).upper()] = str(v.get("group") or "").upper()
    return out


def run_shadow_policy_report(
    *,
    root: Path,
    python_exe: str,
    lookback_days: int,
    horizon_minutes: int,
    out_path: Path,
    timeout_sec: int,
) -> Tuple[int, List[str], List[str]]:
    cmd = [
        python_exe,
        "-B",
        str((root / "TOOLS" / "shadow_policy_daily_report.py").resolve()),
        "--root",
        str(root),
        "--lookback-days",
        str(max(1, int(lookback_days))),
        "--horizon-minutes",
        str(max(1, int(horizon_minutes))),
        "--force",
        "--out",
        str(out_path),
    ]
    cp = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        timeout=max(60, int(timeout_sec)),
        check=False,
    )
    stdout_tail = (cp.stdout or "").splitlines()[-40:]
    stderr_tail = (cp.stderr or "").splitlines()[-40:]
    return int(cp.returncode), stdout_tail, stderr_tail


def build_stats(rows: List[Dict[str, Any]]) -> Dict[Tuple[str, str], KeyStats]:
    by_key: Dict[Tuple[str, str], KeyStats] = {}
    per_day_net: Dict[Tuple[str, str, str], float] = {}

    for row in rows:
        window_id = str(row.get("window_id") or "NONE").upper()
        symbol = str(row.get("symbol") or "UNKNOWN").upper()
        day = str(row.get("date_utc") or "UNKNOWN")
        key = (window_id, symbol)

        st = by_key.get(key)
        if st is None:
            st = KeyStats(window_id=window_id, symbol=symbol)
            by_key[key] = st

        trades = int(row.get("trades") or 0)
        st.trades += trades
        st.wins += int(row.get("wins") or 0)
        st.losses += int(row.get("losses") or 0)
        st.net_pips_sum += float(row.get("net_pips_sum") or 0.0)
        st.gross_pips_sum += float(row.get("gross_pips_sum") or 0.0)
        st.cost_pips_sum += float(row.get("cost_pips_sum") or 0.0)
        if trades > 0 and day != "UNKNOWN":
            st.days.add(day)
            per_day_net[(window_id, symbol, day)] = per_day_net.get((window_id, symbol, day), 0.0) + float(
                row.get("net_pips_sum") or 0.0
            )

    for st in by_key.values():
        neg = 0
        for day in st.days:
            if per_day_net.get((st.window_id, st.symbol, day), 0.0) < 0.0:
                neg += 1
        st.negative_days = int(neg)

    return by_key


def compute_lab_score(
    *,
    explore: KeyStats,
    strict: Optional[KeyStats],
    weights: Dict[str, float],
) -> float:
    if explore.trades <= 0:
        return -9999.0

    net_component = float(explore.net_pips_per_trade) * float(weights.get("net_pips_per_trade", 0.45)) * 100.0
    win_component = float(explore.win_rate) * float(weights.get("win_rate", 0.2)) * 100.0
    sample_component = math.log10(1.0 + float(explore.trades)) * float(weights.get("sample_size", 0.15)) * 30.0
    loss_penalty = float(explore.loss_day_ratio) * float(weights.get("loss_day_penalty", 0.1)) * 100.0
    cost_penalty = float(explore.cost_share) * float(weights.get("cost_share_penalty", 0.1)) * 100.0

    strict_bonus = 0.0
    if strict is not None and strict.trades > 0:
        strict_bonus = max(0.0, strict.net_pips_per_trade) * 8.0

    return round(net_component + win_component + sample_component + strict_bonus - loss_penalty - cost_penalty, 4)


def evaluate_lab_to_shadow_gate(
    *,
    explore: KeyStats,
    strict: KeyStats,
    gates: Dict[str, Any],
) -> Tuple[bool, Dict[str, bool], List[str]]:
    checks: Dict[str, bool] = {
        "min_days_covered": len(explore.days) >= int(gates.get("min_days_covered", 10)),
        "min_explore_trades": explore.trades >= int(gates.get("min_explore_trades", 120)),
        "min_strict_trades": strict.trades >= int(gates.get("min_strict_trades", 40)),
        "min_explore_win_rate": explore.win_rate >= float(gates.get("min_explore_win_rate", 0.52)),
        "min_explore_net_pips_per_trade": explore.net_pips_per_trade
        >= float(gates.get("min_explore_net_pips_per_trade", 0.25)),
        "min_strict_net_pips_per_trade": strict.net_pips_per_trade
        >= float(gates.get("min_strict_net_pips_per_trade", 0.05)),
        "max_explore_loss_day_ratio": explore.loss_day_ratio <= float(gates.get("max_explore_loss_day_ratio", 0.4)),
        "max_explore_cost_share": explore.cost_share <= float(gates.get("max_explore_cost_share", 0.65)),
    }
    failed = [k for k, ok in checks.items() if not bool(ok)]
    ready = len(failed) == 0
    return ready, checks, failed


def decide_lab_action(ready: bool, explore: KeyStats, strict: KeyStats, failed: List[str]) -> str:
    if ready:
        return "KANDYDAT_SHADOW"
    if explore.trades < 40:
        return "ZBIERAJ_DANE"
    if explore.net_pips_per_trade < 0.0:
        return "DOCIŚNIJ"
    if strict.trades == 0 and explore.net_pips_per_trade > 0.25:
        return "POLUZUJ_TESTOWO"
    if "max_explore_loss_day_ratio" in failed or "max_explore_cost_share" in failed:
        return "DOCIŚNIJ"
    return "TRZYMAJ"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="LAB daily pipeline (offline learning, no runtime mutation).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--lookback-days", type=int, default=30)
    ap.add_argument("--horizon-minutes", type=int, default=60)
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--daily-guard", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--timeout-sec", type=int, default=180)
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_root = (root / "LAB").resolve()
    now = now_utc()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")

    cfg_path = lab_root / "CONFIG" / "lab_config.json"
    strategy_path = root / "CONFIG" / "strategy.json"
    daily_dir = lab_root / "EVIDENCE" / "daily"
    run_dir = lab_root / "RUN"
    run_dir.mkdir(parents=True, exist_ok=True)
    daily_dir.mkdir(parents=True, exist_ok=True)

    if not cfg_path.exists():
        raise FileNotFoundError(f"Missing LAB config: {cfg_path}")
    if not strategy_path.exists():
        raise FileNotFoundError(f"Missing strategy config: {strategy_path}")

    state_path = run_dir / "lab_daily_state.json"
    if bool(args.daily_guard) and not bool(args.force) and should_skip_daily(state_path, now):
        skip_out = Path(args.out).resolve() if args.out else (daily_dir / f"lab_daily_report_{stamp}.json")
        payload = {
            "schema": "oanda_mt5.lab_daily_pipeline.v1",
            "status": "SKIP_ALREADY_RUN_TODAY",
            "generated_at_utc": iso_utc(now),
            "root": str(root),
            "lab_root": str(lab_root),
            "daily_guard": True,
        }
        write_json(skip_out, payload)
        print(f"LAB_DAILY_PIPELINE_OK status={payload['status']} out={skip_out}")
        return 0

    lab_cfg = load_json(cfg_path)
    window_groups = read_window_groups(strategy_path)
    focus_group = str(args.focus_group or "FX").upper()
    focus_windows = sorted([wid for wid, grp in window_groups.items() if grp == focus_group])

    base_out = daily_dir / f"shadow_policy_base_{stamp}.json"
    python_exe = resolve_python_exe(str(args.python))
    rc, stdout_tail, stderr_tail = run_shadow_policy_report(
        root=root,
        python_exe=python_exe,
        lookback_days=max(1, int(args.lookback_days)),
        horizon_minutes=max(1, int(args.horizon_minutes)),
        out_path=base_out,
        timeout_sec=max(60, int(args.timeout_sec)),
    )
    if rc != 0:
        report = {
            "schema": "oanda_mt5.lab_daily_pipeline.v1",
            "status": "FAIL_BASE_REPORT",
            "generated_at_utc": iso_utc(now),
            "root": str(root),
            "lab_root": str(lab_root),
            "base_report_path": str(base_out),
            "base_report_rc": int(rc),
            "base_stdout_tail": stdout_tail,
            "base_stderr_tail": stderr_tail,
        }
        out_path = Path(args.out).resolve() if args.out else (daily_dir / f"lab_daily_report_{stamp}.json")
        write_json(out_path, report)
        update_daily_state(state_path, now, "FAIL_BASE_REPORT", out_path)
        print(f"LAB_DAILY_PIPELINE_FAIL status=FAIL_BASE_REPORT out={out_path}")
        return int(rc)

    base = load_json(base_out)
    strict_rows_all = list((base.get("results_per_day_window_symbol") or {}).get("strict") or [])
    explore_rows_all = list((base.get("results_per_day_window_symbol") or {}).get("explore") or [])

    strict_rows = [r for r in strict_rows_all if str(r.get("window_id") or "").upper() in set(focus_windows)]
    explore_rows = [r for r in explore_rows_all if str(r.get("window_id") or "").upper() in set(focus_windows)]

    strict_stats = build_stats(strict_rows)
    explore_stats = build_stats(explore_rows)

    rec_map: Dict[Tuple[str, str], Dict[str, Any]] = {}
    for rec in list(base.get("recommendations_tomorrow_per_window_symbol") or []):
        key = (str(rec.get("window_id") or "NONE").upper(), str(rec.get("symbol") or "UNKNOWN").upper())
        rec_map[key] = rec

    gates = (
        (lab_cfg.get("promotion_gates") or {})
        .get("lab_to_shadow", {})
    )
    weights = (lab_cfg.get("objective") or {}).get("weights", {})

    leaderboard: List[Dict[str, Any]] = []
    keys = sorted(set(strict_stats.keys()) | set(explore_stats.keys()))
    ready_count = 0
    explore_total_trades = 0

    for key in keys:
        window_id, symbol = key
        explore = explore_stats.get(key, KeyStats(window_id=window_id, symbol=symbol))
        strict = strict_stats.get(key, KeyStats(window_id=window_id, symbol=symbol))
        ready, checks, failed = evaluate_lab_to_shadow_gate(explore=explore, strict=strict, gates=gates)
        if ready:
            ready_count += 1
        explore_total_trades += int(explore.trades)

        action = decide_lab_action(ready, explore, strict, failed)
        score = compute_lab_score(explore=explore, strict=strict, weights=weights)
        src_rec = rec_map.get(key, {})

        leaderboard.append(
            {
                "window_id": window_id,
                "symbol": symbol,
                "lab_score": score,
                "promotion_status": "READY_FOR_SHADOW" if ready else "NOT_READY",
                "lab_action": action,
                "failed_gates": failed,
                "gate_checks": checks,
                "strict": {
                    "days": len(strict.days),
                    "trades": strict.trades,
                    "win_rate": round(strict.win_rate, 4),
                    "net_pips_per_trade": round(strict.net_pips_per_trade, 3),
                    "net_pips_sum": round(strict.net_pips_sum, 2),
                },
                "explore": {
                    "days": len(explore.days),
                    "trades": explore.trades,
                    "win_rate": round(explore.win_rate, 4),
                    "net_pips_per_trade": round(explore.net_pips_per_trade, 3),
                    "net_pips_sum": round(explore.net_pips_sum, 2),
                    "loss_day_ratio": round(explore.loss_day_ratio, 4),
                    "cost_share": round(explore.cost_share, 4),
                },
                "source_shadow_recommendation": {
                    "action_tomorrow": src_rec.get("action_tomorrow"),
                    "reason_code": src_rec.get("reason_code"),
                    "confidence": src_rec.get("confidence"),
                },
            }
        )

    leaderboard.sort(key=lambda r: (float(r.get("lab_score") or -9999.0), int(r.get("explore", {}).get("trades") or 0)), reverse=True)
    for i, row in enumerate(leaderboard, start=1):
        row["rank"] = i

    summary = {
        "pairs_total": len(leaderboard),
        "pairs_ready_for_shadow": ready_count,
        "pairs_not_ready": max(0, len(leaderboard) - ready_count),
        "explore_total_trades": int(explore_total_trades),
        "focus_group": focus_group,
        "focus_windows": focus_windows,
    }

    out_path = Path(args.out).resolve() if args.out else (daily_dir / f"lab_daily_report_{stamp}.json")
    report = {
        "schema": "oanda_mt5.lab_daily_pipeline.v1",
        "status": "PASS",
        "generated_at_utc": iso_utc(now),
        "root": str(root),
        "lab_root": str(lab_root),
        "objective": lab_cfg.get("objective") or {},
        "range_utc": base.get("range_utc") or {},
        "focus": {
            "active_phase": ((lab_cfg.get("phase_scope") or {}).get("active_phase") or "PHASE_1_FX"),
            "focus_group": focus_group,
            "focus_windows": focus_windows,
        },
        "promotion_gates": gates,
        "base_report": {
            "path": str(base_out),
            "schema": base.get("schema"),
            "status": base.get("status"),
            "strict_trades": ((base.get("summary") or {}).get("strict") or {}).get("trades"),
            "explore_trades": ((base.get("summary") or {}).get("explore") or {}).get("trades"),
        },
        "summary": summary,
        "leaderboard": leaderboard,
        "safeguards": [
            "LAB offline analytics only; no runtime strategy mutation",
            "No capital risk parameter change allowed",
            "Promotion gates are recommendations for operator review",
        ],
        "next_step": [
            "Only READY_FOR_SHADOW pairs can be considered for shadow enable proposal",
            "Keep main runtime unchanged until operator approval",
            "External connectors stay planned/off by default",
        ],
    }
    write_json(out_path, report)

    latest_path = daily_dir / "lab_daily_report_latest.json"
    write_json(latest_path, report)

    txt_lines: List[str] = []
    txt_lines.append("LAB_DAILY_PIPELINE")
    txt_lines.append(f"Generated UTC: {report['generated_at_utc']}")
    txt_lines.append(f"Focus: group={focus_group} windows={','.join(focus_windows) if focus_windows else 'NONE'}")
    txt_lines.append(f"Range UTC: {report['range_utc'].get('start')} -> {report['range_utc'].get('end_exclusive')}")
    txt_lines.append("")
    txt_lines.append("SUMMARY")
    for k, v in summary.items():
        txt_lines.append(f"- {k}: {v}")
    txt_lines.append("")
    txt_lines.append("TOP_20")
    for row in leaderboard[:20]:
        txt_lines.append(
            f"- #{row['rank']} {row['window_id']}|{row['symbol']} score={row['lab_score']} "
            f"status={row['promotion_status']} action={row['lab_action']} "
            f"explore_n={row['explore']['trades']} explore_net_pt={row['explore']['net_pips_per_trade']}"
        )
    txt_path = out_path.with_suffix(".txt")
    txt_path.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")
    latest_txt_path = daily_dir / "lab_daily_report_latest.txt"
    latest_txt_path.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

    update_daily_state(state_path, now, "PASS", out_path)

    print(
        "LAB_DAILY_PIPELINE_OK status=PASS focus_group={0} pairs={1} ready={2} out={3}".format(
            focus_group,
            len(leaderboard),
            ready_count,
            str(out_path),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
