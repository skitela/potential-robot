#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Tuple

try:
    from TOOLS.lab_guardrails import ensure_write_parent, resolve_lab_data_root
except Exception:  # pragma: no cover
    from lab_guardrails import ensure_write_parent, resolve_lab_data_root

UTC = dt.timezone.utc
SCHEMA = "oanda.mt5.stage1_manual_approval.v1"
ALLOWED_PROFILES = {"AUTO", "BEZPIECZNY", "SREDNI", "ODWAZNIEJSZY"}
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


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _parse_bool(text: str) -> bool:
    t = str(text or "").strip().lower()
    if t in {"1", "true", "t", "yes", "y"}:
        return True
    if t in {"0", "false", "f", "no", "n"}:
        return False
    raise ValueError(f"Invalid bool value: {text!r}")


def _load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json_atomic(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True)
    fd, tmp = tempfile.mkstemp(prefix=".tmp_stage1_approve_", suffix=".json", dir=str(path.parent))
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


def _parse_pairs(pairs: List[str]) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for raw in pairs:
        text = str(raw or "").strip()
        if not text or "=" not in text:
            raise ValueError(f"Invalid --instrument-profile format: {raw!r}")
        sym, prof = text.split("=", 1)
        symbol = str(sym).strip().upper()
        profile = str(prof).strip().upper()
        if not symbol:
            raise ValueError(f"Invalid symbol in --instrument-profile: {raw!r}")
        if profile not in ALLOWED_PROFILES:
            raise ValueError(f"Invalid profile for {symbol}: {profile!r}")
        out[symbol] = profile
    return out


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
            hits.extend(_deep_find_locked(v, f"{path}[{idx}]"))
    return hits


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Create/update Stage-1 manual approval file with validation.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--approval-file", default="")
    ap.add_argument("--approved", default="true", help="true/false")
    ap.add_argument("--ticket", default="")
    ap.add_argument("--comment", default="")
    ap.add_argument(
        "--instrument-profile",
        action="append",
        default=[],
        help="repeatable: SYMBOL=PROFILE, PROFILE in {AUTO,BEZPIECZNY,SREDNI,ODWAZNIEJSZY}",
    )
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    now = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    run_dir = (lab_data_root / "run").resolve()
    approval_path = (
        Path(args.approval_file).resolve()
        if str(args.approval_file).strip()
        else (run_dir / "stage1_manual_approval.json").resolve()
    )
    audit_path = (run_dir / "stage1_manual_approval_audit.jsonl").resolve()
    approval_path = ensure_write_parent(approval_path, root=root, lab_data_root=lab_data_root)
    audit_path = ensure_write_parent(audit_path, root=root, lab_data_root=lab_data_root)

    template_path = (root / "LAB" / "CONFIG" / "stage1_manual_approval.template.json").resolve()
    base: Dict[str, Any] = {}
    if template_path.exists():
        try:
            base = _load_json(template_path)
        except Exception:
            base = {}
    if approval_path.exists():
        try:
            existing = _load_json(approval_path)
            if isinstance(existing, dict):
                base.update(existing)
        except Exception as exc:
            _ = exc
    try:
        approved = _parse_bool(str(args.approved))
    except Exception as exc:
        print(f"STAGE1_APPROVE_DONE status=FAIL reason=INVALID_APPROVED value={args.approved!r} err={exc}")
        return 1

    try:
        updates = _parse_pairs(list(args.instrument_profile or []))
    except Exception as exc:
        print(f"STAGE1_APPROVE_DONE status=FAIL reason=INVALID_INSTRUMENT_PROFILE err={exc}")
        return 1

    instruments = base.get("instruments") if isinstance(base.get("instruments"), dict) else {}
    instruments = {str(k).strip().upper(): str(v).strip().upper() for k, v in instruments.items() if str(k).strip()}
    for k, v in updates.items():
        instruments[k] = v
    for k, v in list(instruments.items()):
        if v not in ALLOWED_PROFILES:
            instruments[k] = "AUTO"

    ticket = str(args.ticket).strip() or str(base.get("ticket") or "").strip() or f"MANUAL-{now.strftime('%Y%m%dT%H%M%SZ')}"
    comment = str(args.comment).strip() or str(base.get("comment") or "").strip() or ""

    payload = {
        "schema": SCHEMA,
        "generated_at_utc": iso_utc(now),
        "approved": bool(approved),
        "ticket": ticket,
        "comment": comment,
        "instruments": instruments,
    }
    locked = _deep_find_locked(payload)
    if locked:
        print(f"STAGE1_APPROVE_DONE status=FAIL reason=FORBIDDEN_KEYS hits={locked}")
        return 1

    _write_json_atomic(approval_path, payload)
    _append_jsonl(
        audit_path,
        {
            "ts_utc": iso_utc(now),
            "event_type": "stage1_manual_approval_update",
            "approval_file": str(approval_path),
            "approved": bool(approved),
            "ticket": ticket,
            "instruments_n": len(instruments),
        },
    )
    print(
        "STAGE1_APPROVE_DONE status=PASS approved={0} instruments_n={1} approval_file={2}".format(
            str(bool(approved)).lower(),
            len(instruments),
            str(approval_path),
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
