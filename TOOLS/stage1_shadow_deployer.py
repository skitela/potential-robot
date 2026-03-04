#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import connect_registry, init_registry_schema, insert_job_run
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import connect_registry, init_registry_schema, insert_job_run

UTC = dt.timezone.utc
APPROVAL_SCHEMA = "oanda.mt5.stage1_manual_approval.v1"
EVAL_SCHEMA = "oanda.mt5.stage1_profile_pack_eval.v1"
PACK_SCHEMA = "oanda.mt5.stage1_profile_pack.v1"
PLAN_SCHEMA = "oanda.mt5.stage1_shadow_deployer_plan.v1"
STATE_SCHEMA = "oanda.mt5.stage1_shadow_deployer_state.v1"

RISK_LOCKED_KEYS = {
    "risk_per_trade",
    "risk_per_trade_pct",
    "risk_per_trade_max_pct",
    "max_daily_drawdown",
    "max_daily_drawdown_pct",
    "max_weekly_drawdown",
    "max_weekly_drawdown_pct",
    "max_open_positions",
    "max_global_exposure",
    "max_series_loss",
    "account_risk_mode",
    "capital_risk_mode",
    "lot_sizing_mode",
    "fixed_lot",
    "kelly_fraction",
    "max_loss_account_ccy_day",
    "max_loss_account_ccy_week",
    "crypto_major_max_open_positions",
}

ALLOWED_THRESHOLD_KEYS = {
    "spread_cap_points",
    "signal_score_threshold",
    "max_latency_ms",
    "min_tradeability_score",
    "min_setup_quality_score",
}

THRESHOLD_GUARDRAILS = {
    "spread_cap_points": {"min": 0.1, "max": 400.0},
    "signal_score_threshold": {"min": 0.0, "max": 100.0},
    "max_latency_ms": {"min": 10.0, "max": 5000.0},
    "min_tradeability_score": {"min": 0.0, "max": 1.0},
    "min_setup_quality_score": {"min": 0.0, "max": 1.0},
}


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_iso_utc(raw: Any) -> Optional[dt.datetime]:
    s = str(raw or "").strip()
    if not s:
        return None
    try:
        out = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if out.tzinfo is None:
            out = out.replace(tzinfo=UTC)
        return out.astimezone(UTC)
    except Exception:
        return None


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def symbol_base(sym: Any) -> str:
    s = str(sym or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    return s


def safe_float(v: Any, default: float = 0.0) -> float:
    try:
        return float(v)
    except Exception:
        return float(default)


def safe_int(v: Any, default: int = 0) -> int:
    try:
        return int(v)
    except Exception:
        return int(default)


def _write_json_atomic(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_stage1_shadow_", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(raw + "\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, str(path))
    finally:
        if os.path.exists(tmp):
            try:
                os.remove(tmp)
            except OSError:
                pass


def _append_jsonl(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(payload, ensure_ascii=False, sort_keys=True) + "\n")


def _deep_find_locked(obj: Any, path: str = "") -> List[str]:
    hits: List[str] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            p = f"{path}.{k}" if path else str(k)
            if str(k) in RISK_LOCKED_KEYS:
                hits.append(p)
            hits.extend(_deep_find_locked(v, p))
    elif isinstance(obj, list):
        for idx, v in enumerate(obj):
            p = f"{path}[{idx}]"
            hits.extend(_deep_find_locked(v, p))
    return hits


def _sanitize_thresholds(thresholds: Dict[str, Any]) -> Dict[str, float]:
    out: Dict[str, float] = {}
    for k, raw_v in thresholds.items():
        key = str(k)
        if key in RISK_LOCKED_KEYS:
            continue
        if key not in ALLOWED_THRESHOLD_KEYS:
            continue
        v = safe_float(raw_v)
        bounds = THRESHOLD_GUARDRAILS.get(key)
        if bounds:
            v = max(float(bounds["min"]), min(float(bounds["max"]), float(v)))
        out[key] = float(v)
    return out


def _load_state(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {"schema": STATE_SCHEMA, "updated_at_utc": iso_utc(dt.datetime.now(tz=UTC)), "instruments": {}}
    try:
        payload = load_json(path)
        if not isinstance(payload, dict):
            raise ValueError("invalid state")
        payload.setdefault("schema", STATE_SCHEMA)
        payload.setdefault("instruments", {})
        return payload
    except Exception:
        return {"schema": STATE_SCHEMA, "updated_at_utc": iso_utc(dt.datetime.now(tz=UTC)), "instruments": {}}


def _state_row(state: Dict[str, Any], symbol: str) -> Dict[str, Any]:
    inst = state.setdefault("instruments", {})
    return inst.setdefault(symbol, {})


def _find_profile_by_name(profile_pack: Dict[str, Any], symbol: str, profile_name: str) -> Optional[Dict[str, Any]]:
    rows = profile_pack.get("profiles_by_symbol") if isinstance(profile_pack.get("profiles_by_symbol"), list) else []
    tgt_sym = symbol_base(symbol)
    tgt_name = str(profile_name or "").strip().upper()
    for row in rows:
        if not isinstance(row, dict):
            continue
        if symbol_base(row.get("symbol")) != tgt_sym:
            continue
        profs = row.get("profiles") if isinstance(row.get("profiles"), dict) else {}
        for _, p in profs.items():
            if not isinstance(p, dict):
                continue
            if str(p.get("profile_name") or "").strip().upper() == tgt_name:
                return p
    return None


def _render_txt(report: Dict[str, Any]) -> str:
    lines: List[str] = []
    lines.append("STAGE1_SHADOW_DEPLOYER")
    lines.append(f"Status: {report.get('status')}")
    lines.append(f"Reason: {report.get('reason')}")
    lines.append(f"Approval source: {report.get('approval_source')}")
    lines.append(f"Mode: {report.get('mode')}")
    lines.append("")
    for row in report.get("instruments", []):
        if not isinstance(row, dict):
            continue
        lines.append(
            "- {0}: decision={1} profile={2} reason={3}".format(
                row.get("symbol"),
                row.get("decision"),
                row.get("selected_profile"),
                row.get("reason"),
            )
        )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Stage-1 bounded shadow deployer (human approval required, no runtime apply).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--profile-eval", default="")
    ap.add_argument("--profile-pack", default="")
    ap.add_argument("--approval-file", default="")
    ap.add_argument("--state-file", default="")
    ap.add_argument("--audit-jsonl", default="")
    ap.add_argument("--cooldown-minutes", type=int, default=60)
    ap.add_argument("--out-report", default="")
    ap.add_argument("--dry-run", action="store_true")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    stage1_reports = (lab_data_root / "reports" / "stage1").resolve()
    run_dir = (lab_data_root / "run").resolve()
    stamp = started.strftime("%Y%m%dT%H%M%SZ")
    run_id = f"STAGE1_SHADOW_DEPLOY_{stamp}"

    profile_eval = (
        Path(args.profile_eval).resolve()
        if str(args.profile_eval).strip()
        else (stage1_reports / "stage1_profile_pack_eval_latest.json").resolve()
    )
    profile_pack = (
        Path(args.profile_pack).resolve()
        if str(args.profile_pack).strip()
        else (stage1_reports / "stage1_profile_pack_latest.json").resolve()
    )
    approval_file = (
        Path(args.approval_file).resolve()
        if str(args.approval_file).strip()
        else (run_dir / "stage1_manual_approval.json").resolve()
    )
    state_file = (
        Path(args.state_file).resolve()
        if str(args.state_file).strip()
        else (run_dir / "stage1_shadow_deployer_state.json").resolve()
    )
    audit_jsonl = (
        Path(args.audit_jsonl).resolve()
        if str(args.audit_jsonl).strip()
        else (stage1_reports / "stage1_shadow_deployer_audit.jsonl").resolve()
    )
    out_report = (
        Path(args.out_report).resolve()
        if str(args.out_report).strip()
        else (stage1_reports / f"stage1_shadow_deployer_{stamp}.json").resolve()
    )
    out_report = ensure_write_parent(out_report, root=root, lab_data_root=lab_data_root)
    state_file = ensure_write_parent(state_file, root=root, lab_data_root=lab_data_root)
    audit_jsonl = ensure_write_parent(audit_jsonl, root=root, lab_data_root=lab_data_root)

    status = "SKIP"
    reason = "EVAL_MISSING"
    mode = "SHADOW_ONLY"
    instruments: List[Dict[str, Any]] = []

    eval_hash = ""
    pack_hash = ""
    approval_hash = ""
    approval_ok = False
    approval_payload: Dict[str, Any] = {}
    eval_payload: Dict[str, Any] = {}
    pack_payload: Dict[str, Any] = {}

    if not profile_eval.exists():
        reason = "EVAL_MISSING"
    elif not profile_pack.exists():
        reason = "PACK_MISSING"
    else:
        eval_payload = load_json(profile_eval)
        pack_payload = load_json(profile_pack)
        if str(eval_payload.get("schema") or "") != EVAL_SCHEMA:
            reason = "EVAL_SCHEMA_MISMATCH"
        elif str(pack_payload.get("schema") or "") != PACK_SCHEMA:
            reason = "PACK_SCHEMA_MISMATCH"
        else:
            try:
                eval_hash = file_sha256(profile_eval)
            except Exception:
                eval_hash = ""
            try:
                pack_hash = file_sha256(profile_pack)
            except Exception:
                pack_hash = ""

            if approval_file.exists():
                try:
                    approval_payload = load_json(approval_file)
                    approval_hash = file_sha256(approval_file)
                except Exception:
                    approval_payload = {}
                    approval_hash = ""
            if not approval_payload:
                reason = "HUMAN_APPROVAL_REQUIRED"
            elif str(approval_payload.get("schema") or "") != APPROVAL_SCHEMA:
                reason = "APPROVAL_SCHEMA_MISMATCH"
            elif not bool(approval_payload.get("approved")):
                reason = "HUMAN_APPROVAL_REQUIRED"
            else:
                locked_hits = _deep_find_locked(approval_payload)
                if locked_hits:
                    reason = "APPROVAL_FORBIDDEN_KEYS"
                else:
                    approval_ok = True

    state = _load_state(state_file)
    now = dt.datetime.now(tz=UTC)
    cooldown_minutes = max(1, int(args.cooldown_minutes))
    approval_instruments = (
        approval_payload.get("instruments")
        if isinstance(approval_payload.get("instruments"), dict)
        else {}
    )

    if approval_ok:
        rows = eval_payload.get("evaluation_by_symbol") if isinstance(eval_payload.get("evaluation_by_symbol"), list) else []
        for row in rows:
            if not isinstance(row, dict):
                continue
            sym = symbol_base(row.get("symbol"))
            if not sym:
                continue
            rec = (
                ((row.get("recommendation_for_tomorrow") or {}).get("recommended_profile"))
                if isinstance(row.get("recommendation_for_tomorrow"), dict)
                else None
            )
            rec_name = str(rec or "SREDNI").strip().upper()
            override = str(approval_instruments.get(sym) or "AUTO").strip().upper()
            selected = rec_name if override in {"", "AUTO"} else override
            profile_obj = _find_profile_by_name(pack_payload, sym, selected)
            if profile_obj is None:
                instruments.append(
                    {
                        "symbol": sym,
                        "decision": "HOLD",
                        "selected_profile": selected,
                        "reason": "PROFILE_NOT_FOUND_IN_PACK",
                        "thresholds": {},
                    }
                )
                continue

            thresholds_raw = profile_obj.get("thresholds") if isinstance(profile_obj.get("thresholds"), dict) else {}
            locked_in_thr = _deep_find_locked(thresholds_raw)
            if locked_in_thr:
                instruments.append(
                    {
                        "symbol": sym,
                        "decision": "HOLD",
                        "selected_profile": selected,
                        "reason": "FORBIDDEN_THRESHOLD_KEYS",
                        "thresholds": {},
                    }
                )
                continue
            thresholds = _sanitize_thresholds(thresholds_raw)

            srow = _state_row(state, sym)
            cur_profile = str(srow.get("active_profile") or "").strip().upper()
            cooldown_until = parse_iso_utc(srow.get("cooldown_until_utc"))
            if cooldown_until is not None and now < cooldown_until and cur_profile and cur_profile != selected:
                instruments.append(
                    {
                        "symbol": sym,
                        "decision": "COOLDOWN_HOLD",
                        "selected_profile": cur_profile,
                        "reason": f"COOLDOWN_UNTIL:{iso_utc(cooldown_until)}",
                        "thresholds": thresholds,
                    }
                )
                continue

            new_cd = now + dt.timedelta(minutes=cooldown_minutes)
            srow["active_profile"] = selected
            srow["cooldown_until_utc"] = iso_utc(new_cd)
            srow["updated_at_utc"] = iso_utc(now)
            instruments.append(
                {
                    "symbol": sym,
                    "decision": "SELECTED_FOR_SHADOW",
                    "selected_profile": selected,
                    "reason": "APPROVED",
                    "thresholds": thresholds,
                }
            )

        if instruments:
            status = "PASS"
            reason = "SHADOW_PLAN_READY"
        else:
            status = "SKIP"
            reason = "NO_SYMBOLS_TO_PROCESS"
    else:
        status = "SKIP"

    state["schema"] = STATE_SCHEMA
    state["updated_at_utc"] = iso_utc(now)

    report = {
        "schema": PLAN_SCHEMA,
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "finished_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
        "status": status,
        "reason": reason,
        "mode": mode,
        "dry_run": bool(args.dry_run),
        "auto_apply": False,
        "human_decision_required": not approval_ok,
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "profile_eval_source": str(profile_eval),
        "profile_eval_hash": eval_hash,
        "profile_pack_source": str(profile_pack),
        "profile_pack_hash": pack_hash,
        "approval_source": str(approval_file),
        "approval_hash": approval_hash,
        "state_path": str(state_file),
        "audit_jsonl": str(audit_jsonl),
        "cooldown_minutes": cooldown_minutes,
        "instruments": instruments,
        "notes": [
            "Human approval gate is mandatory.",
            "No runtime config mutation is performed by this tool.",
            "Output is SHADOW deployment plan only.",
        ],
    }

    _write_json_atomic(out_report, report)
    out_report.with_suffix(".txt").write_text(_render_txt(report), encoding="utf-8")
    latest_json = ensure_write_parent((stage1_reports / "stage1_shadow_deployer_latest.json").resolve(), root=root, lab_data_root=lab_data_root)
    latest_txt = ensure_write_parent((stage1_reports / "stage1_shadow_deployer_latest.txt").resolve(), root=root, lab_data_root=lab_data_root)
    _write_json_atomic(latest_json, report)
    latest_txt.write_text(_render_txt(report), encoding="utf-8")

    # Save state even on SKIP so operator sees timestamps/cooldown state continuity.
    _write_json_atomic(state_file, state)

    _append_jsonl(
        audit_jsonl,
        {
            "ts_utc": iso_utc(dt.datetime.now(tz=UTC)),
            "run_id": run_id,
            "event_type": "shadow_deployer_summary",
            "status": status,
            "reason": reason,
            "approval_ok": approval_ok,
            "symbols_n": len(instruments),
        },
    )
    for row in instruments:
        _append_jsonl(
            audit_jsonl,
            {
                "ts_utc": iso_utc(dt.datetime.now(tz=UTC)),
                "run_id": run_id,
                "event_type": "shadow_deployer_symbol_decision",
                "symbol": row.get("symbol"),
                "decision": row.get("decision"),
                "selected_profile": row.get("selected_profile"),
                "reason": row.get("reason"),
            },
        )

    try:
        registry_path = (lab_data_root / "registry" / "lab_registry.sqlite").resolve()
        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)
        cfg_hash = canonical_json_hash(
            {
                "tool": "stage1_shadow_deployer.v1",
                "cooldown_minutes": cooldown_minutes,
                "dry_run": bool(args.dry_run),
            }
        )
        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "STAGE1_SHADOW_DEPLOYER",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5_SNAPSHOT",
                "dataset_hash": eval_hash or pack_hash,
                "config_hash": cfg_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(out_report),
                "details_json": json.dumps({"symbols_n": len(instruments), "approval_ok": approval_ok}, ensure_ascii=False),
            },
        )
        conn_reg.close()
    except Exception:
        pass

    print(f"STAGE1_SHADOW_DEPLOYER_DONE status={status} reason={reason} report={out_report}")
    return 0 if status in {"PASS", "SKIP"} else 1


if __name__ == "__main__":
    raise SystemExit(main())
