#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc
DEFAULT_PROFILES = ["BASELINE", "CANDLE_ONLY", "RENKO_ONLY", "CANDLE_RENKO_CONFLUENCE"]


def now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, payload: Dict[str, Any], *, root: Path, lab_data_root: Path) -> None:
    out = ensure_write_parent(path, root=root, lab_data_root=lab_data_root)
    tmp = out.with_suffix(out.suffix + ".tmp")
    txt = json.dumps(payload, indent=2, ensure_ascii=False)
    try:
        tmp.write_text(txt + "\n", encoding="utf-8")
        tmp.replace(out)
    except Exception:
        out.write_text(txt + "\n", encoding="utf-8")
        try:
            if tmp.exists():
                tmp.unlink()
        except Exception:
            pass


def parse_profiles(raw: str) -> List[str]:
    text = str(raw or "").strip()
    if not text:
        return list(DEFAULT_PROFILES)
    out: List[str] = []
    for part in text.replace(";", ",").split(","):
        p = str(part or "").strip().upper()
        if not p:
            continue
        if p not in DEFAULT_PROFILES:
            continue
        if p not in out:
            out.append(p)
    return out or list(DEFAULT_PROFILES)


def run_shadow_report(
    *,
    root: Path,
    python_exe: str,
    strategy_path: Path,
    db_events: Path,
    db_bars: Path,
    lookback_days: int,
    horizon_minutes: int,
    out_path: Path,
    profile: str,
    profile_score_threshold: float,
    profile_require_bias: bool,
    timeout_sec: int,
) -> Tuple[int, List[str], List[str]]:
    cmd: List[str] = [
        python_exe,
        "-B",
        str((root / "TOOLS" / "shadow_policy_daily_report.py").resolve()),
        "--root",
        str(root),
        "--strategy-path",
        str(strategy_path),
        "--db-events",
        str(db_events),
        "--db-bars",
        str(db_bars),
        "--lookback-days",
        str(max(1, int(lookback_days))),
        "--horizon-minutes",
        str(max(1, int(horizon_minutes))),
        "--strategy-profile",
        str(profile).upper(),
        "--profile-score-threshold",
        str(float(profile_score_threshold)),
        "--force",
        "--out",
        str(out_path),
    ]
    if bool(profile_require_bias):
        cmd.append("--profile-require-bias")
    cp = subprocess.run(
        cmd,
        cwd=str(root),
        capture_output=True,
        text=True,
        timeout=max(60, int(timeout_sec)),
        check=False,
    )
    return int(cp.returncode), (cp.stdout or "").splitlines()[-40:], (cp.stderr or "").splitlines()[-40:]


def recommendation_for_profile(
    *,
    trades: int,
    win_rate: float,
    net_pips_per_trade: float,
    min_sample: int,
    poluzuj_threshold: float,
    docisnij_threshold: float,
) -> str:
    if int(trades) < int(min_sample):
        return "TRZYMAJ_I_ZBIERAJ_DANE"
    if float(net_pips_per_trade) <= float(docisnij_threshold):
        return "DOCIŚNIJ"
    if float(net_pips_per_trade) >= float(poluzuj_threshold) and float(win_rate) >= 0.5:
        return "POLUZUJ"
    return "TRZYMAJ"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="LAB-only strategy profile sweep (baseline/candle/renko/confluence).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--python", default=sys.executable)
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--strategy-path", default="")
    ap.add_argument("--db-events", default="")
    ap.add_argument("--db-bars", default="")
    ap.add_argument("--lookback-days", type=int, default=3)
    ap.add_argument("--horizon-minutes", type=int, default=60)
    ap.add_argument("--profiles", default=",".join(DEFAULT_PROFILES))
    ap.add_argument("--profile-score-threshold", type=float, default=0.55)
    ap.add_argument("--profile-require-bias", action="store_true")
    ap.add_argument("--min-sample", type=int, default=20)
    ap.add_argument("--poluzuj-threshold-pips-per-trade", type=float, default=0.5)
    ap.add_argument("--docisnij-threshold-pips-per-trade", type=float, default=-1.5)
    ap.add_argument("--timeout-sec", type=int, default=1800)
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    now = now_utc()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    out_path = Path(args.out).resolve() if str(args.out).strip() else (
        lab_data_root / "reports" / "profiles" / f"lab_strategy_profile_sweep_{stamp}.json"
    )

    strategy_path = Path(args.strategy_path).resolve() if str(args.strategy_path).strip() else (root / "CONFIG" / "strategy.json")
    db_events = Path(args.db_events).resolve() if str(args.db_events).strip() else (root / "DB" / "decision_events.sqlite")
    db_bars = Path(args.db_bars).resolve() if str(args.db_bars).strip() else (root / "DB" / "m5_bars.sqlite")
    profiles = parse_profiles(str(args.profiles))
    python_exe = str(args.python or "").strip() or str(sys.executable)

    profile_runs: List[Dict[str, Any]] = []
    for profile in profiles:
        profile_out = ensure_write_parent(
            lab_data_root / "reports" / "shadow_policy" / f"shadow_policy_{profile.lower()}_{stamp}.json",
            root=root,
            lab_data_root=lab_data_root,
        )
        rc, stdout_tail, stderr_tail = run_shadow_report(
            root=root,
            python_exe=python_exe,
            strategy_path=strategy_path,
            db_events=db_events,
            db_bars=db_bars,
            lookback_days=max(1, int(args.lookback_days)),
            horizon_minutes=max(1, int(args.horizon_minutes)),
            out_path=profile_out,
            profile=profile,
            profile_score_threshold=float(args.profile_score_threshold),
            profile_require_bias=bool(args.profile_require_bias),
            timeout_sec=max(60, int(args.timeout_sec)),
        )
        status = "PASS" if rc == 0 and profile_out.exists() else "FAIL"
        metrics: Dict[str, Any] = {}
        rec = "HOLD"
        if status == "PASS":
            payload = load_json(profile_out)
            ex = ((payload.get("summary") or {}).get("explore") or {})
            trades = int(ex.get("trades") or 0)
            wr = float(ex.get("win_rate") or 0.0)
            net_pt = float(ex.get("net_pips_per_trade") or 0.0)
            rec = recommendation_for_profile(
                trades=trades,
                win_rate=wr,
                net_pips_per_trade=net_pt,
                min_sample=int(args.min_sample),
                poluzuj_threshold=float(args.poluzuj_threshold_pips_per_trade),
                docisnij_threshold=float(args.docisnij_threshold_pips_per_trade),
            )
            strict_trades = int(((payload.get("summary") or {}).get("strict") or {}).get("trades") or 0)
            profile_filtered_out = int(((payload.get("quality") or {}).get("events_profile_filtered_out") or 0))
            profile_passed = int(((payload.get("quality") or {}).get("events_profile_passed") or 0))
            metrics = {
                "explore_trades": trades,
                "explore_win_rate": wr,
                "explore_net_pips_sum": float(ex.get("net_pips_sum") or 0.0),
                "explore_net_pips_per_trade": net_pt,
                "strict_trades": strict_trades,
                "profile_filtered_out": profile_filtered_out,
                "profile_passed": profile_passed,
            }
        profile_runs.append(
            {
                "profile": profile,
                "status": status,
                "report_path": str(profile_out),
                "rc": int(rc),
                "stdout_tail": stdout_tail,
                "stderr_tail": stderr_tail,
                "metrics": metrics,
                "action_hint": rec,
            }
        )

    ranked = sorted(
        [r for r in profile_runs if r.get("status") == "PASS"],
        key=lambda x: float(((x.get("metrics") or {}).get("explore_net_pips_per_trade") or -1e9)),
        reverse=True,
    )
    winner = ranked[0]["profile"] if ranked else "NONE"

    report = {
        "schema": "oanda_mt5.lab_strategy_profile_sweep.v1",
        "generated_at_utc": iso_utc(now),
        "status": "PASS" if all(r.get("status") == "PASS" for r in profile_runs) else "PARTIAL",
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "range": {
            "lookback_days": int(args.lookback_days),
            "horizon_minutes": int(args.horizon_minutes),
        },
        "profile_filter_config": {
            "score_threshold": float(args.profile_score_threshold),
            "require_bias": bool(args.profile_require_bias),
            "profiles": profiles,
        },
        "runs": profile_runs,
        "winner_by_explore_net_pips_per_trade": winner,
        "notes": [
            "LAB-only comparative experiment. No runtime strategy mutation.",
            "Use this report to decide where to docisnac/poluzowac in SHADOW proposals.",
        ],
    }
    write_json(out_path, report, root=root, lab_data_root=lab_data_root)
    print(
        "LAB_STRATEGY_PROFILE_SWEEP_OK status={0} profiles={1} winner={2} out={3}".format(
            report["status"], len(profile_runs), winner, str(out_path)
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
