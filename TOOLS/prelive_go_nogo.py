#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import datetime as dt
import json
import sqlite3
import sys
from pathlib import Path
from typing import Any, Dict, Optional

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

try:
    from TOOLS import dependency_hygiene as _dep_hygiene
except Exception:
    _dep_hygiene = None  # type: ignore

UTC = dt.timezone.utc


def _now_utc_iso() -> str:
    return dt.datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _parse_ts_utc(s: str) -> Optional[dt.datetime]:
    if not s:
        return None
    try:
        ss = str(s).strip()
        if ss.endswith("Z"):
            ss = ss[:-1] + "+00:00"
        d = dt.datetime.fromisoformat(ss)
        if d.tzinfo is None:
            d = d.replace(tzinfo=UTC)
        return d.astimezone(UTC)
    except Exception:
        return None


def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    if not path.exists():
        return None
    try:
        obj = json.loads(path.read_text(encoding="utf-8", errors="ignore") or "{}")
        return obj if isinstance(obj, dict) else None
    except Exception:
        return None


def _flag_enabled(path: Path) -> bool:
    if not path.exists():
        return False
    try:
        raw = (path.read_text(encoding="utf-8", errors="ignore") or "").strip().lower()
    except Exception:
        # If the file exists but cannot be read, keep legacy conservative behavior.
        return True
    if raw in {"0", "false", "off", "no", "disable", "disabled"}:
        return False
    return True


def _read_canary_promoted(db_path: Path) -> Optional[bool]:
    if not db_path.exists():
        return None
    try:
        conn = sqlite3.connect(str(db_path), timeout=3)
        cur = conn.cursor()
        cur.execute("SELECT value FROM system_state WHERE key='canary_rollout_promoted'")
        row = cur.fetchone()
        conn.close()
        if not row:
            return None
        return str(row[0]).strip() == "1"
    except Exception:
        return None


def _incident_counts(log_path: Path, lookback_sec: int = 24 * 3600) -> Dict[str, int]:
    out = {"total": 0, "error_or_worse": 0, "critical": 0}
    if not log_path.exists():
        return out
    now = dt.datetime.now(tz=UTC)
    cutoff = now - dt.timedelta(seconds=max(1, int(lookback_sec)))
    try:
        lines = log_path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return out
    for ln in lines[-4000:]:
        ln = str(ln or "").strip()
        if not ln:
            continue
        try:
            obj = json.loads(ln)
            ts = _parse_ts_utc(str(obj.get("ts_utc") or ""))
            if ts is None or ts < cutoff:
                continue
            out["total"] += 1
            sev = str(obj.get("severity") or "").upper()
            if sev in {"ERROR", "CRITICAL"}:
                out["error_or_worse"] += 1
            if sev == "CRITICAL":
                out["critical"] += 1
        except Exception:
            continue
    return out


def _dependency_hygiene_check(root: Path) -> Dict[str, Any]:
    req = root / "requirements.txt"
    if not req.exists():
        return {
            "ok_requirements": True,
            "ok_local_links": True,
            "missing_requirements": [],
            "local_unresolved_total": 0,
            "status": "SKIPPED_NO_REQUIREMENTS",
        }
    if _dep_hygiene is None:
        return {
            "ok_requirements": False,
            "ok_local_links": False,
            "missing_requirements": ["DEPENDENCY_HYGIENE_IMPORT_FAIL"],
            "local_unresolved_total": 1,
            "status": "IMPORT_FAIL",
        }
    rep = _dep_hygiene.detect_hygiene(root, _dep_hygiene.REQUIREMENT_FILES_DEFAULT)
    missing = list(rep.get("missing_requirements") or [])
    local_modules = {str(x).strip().lower() for x in (rep.get("local_modules_detected") or []) if str(x).strip()}
    top_level_dirs = {
        p.name.strip().lower() for p in root.iterdir() if p.is_dir() and p.name.strip()
    }
    observer_roots = [
        root / "OBSERVERS_DRAFT",
        root / "OBSERVERS_IMPLEMENTATION_CANDIDATE",
    ]

    def _is_local_name(name: str) -> bool:
        nm = str(name or "").strip()
        if not nm:
            return False
        nml = nm.lower()
        if nml in local_modules or nml in top_level_dirs:
            return True
        if (root / nm).exists():
            return True
        for obs in observer_roots:
            if not obs.exists():
                continue
            if (obs / nm).exists():
                return True
            if any(obs.glob(f"{nm}.py")):
                return True
        return False

    missing_filtered = [m for m in missing if not _is_local_name(str(m))]
    unresolved = int(rep.get("local_unresolved_total") or 0)
    return {
        "ok_requirements": len(missing_filtered) == 0,
        "ok_local_links": unresolved == 0,
        "missing_requirements": missing_filtered,
        "missing_requirements_raw": missing,
        "local_unresolved_total": unresolved,
        "status": str(rep.get("status") or "UNKNOWN"),
    }


def evaluate_prelive(root: Path) -> Dict[str, Any]:
    root = Path(root)
    meta = root / "META"
    logs = root / "LOGS"
    db = root / "DB"
    run = root / "RUN"

    learner = _read_json(meta / "learner_advice.json")
    qa_light = "UNKNOWN"
    learner_fresh = False
    if learner is not None:
        qa_light = str(learner.get("qa_light") or "UNKNOWN").upper()
        ts = _parse_ts_utc(str(learner.get("ts_utc") or ""))
        ttl = int(learner.get("ttl_sec") or 0)
        if ts is not None and ttl > 0:
            learner_fresh = (dt.datetime.now(tz=UTC) - ts).total_seconds() <= float(ttl)

    incidents = _incident_counts(logs / "incident_journal.jsonl", lookback_sec=24 * 3600)
    canary_promoted = _read_canary_promoted(db / "decision_events.sqlite")
    learner_report = _read_json(logs / "learner_offline_report.json") or {}
    reasons_raw = learner_report.get("anti_overfit_reasons") if isinstance(learner_report, dict) else []
    reasons = {
        str(x).strip().upper()
        for x in (reasons_raw if isinstance(reasons_raw, list) else [])
        if str(x).strip()
    }
    try:
        n_total = int((learner_report.get("n_total") if isinstance(learner_report, dict) else None) or 0)
    except Exception:
        n_total = 0
    if n_total <= 0:
        try:
            n_total = int(((learner or {}).get("metrics", {}) or {}).get("n") or 0)
        except Exception:
            n_total = 0

    cold_start_candidate = bool(
        qa_light == "RED" and int(n_total) < 40 and (("N_TOO_LOW" in reasons) or int(n_total) == 0)
    )
    cold_start_flag_path = run / "ALLOW_COLD_START_CANARY.flag"
    cold_start_flag = bool(_flag_enabled(cold_start_flag_path))
    cold_start_override = False
    dep = _dependency_hygiene_check(root)
    if cold_start_candidate and cold_start_flag:
        crit = int(incidents.get("critical") or 0)
        errs = int(incidents.get("error_or_worse") or 0)
        canary_not_promoted = (canary_promoted is None) or (canary_promoted is False)
        if bool(learner_fresh) and crit == 0 and errs == 0 and canary_not_promoted:
            cold_start_override = True

    checks = []
    checks.append(
        {
            "id": "LEARNER_QA_RED",
            "ok": (qa_light != "RED") or bool(cold_start_override),
            "value": (f"{qa_light}->COLD_START_CANARY" if cold_start_override else qa_light),
        }
    )
    checks.append({"id": "LEARNER_FRESH", "ok": bool(learner_fresh), "value": bool(learner_fresh)})
    checks.append(
        {
            "id": "INCIDENT_CRITICAL_24H",
            "ok": int(incidents.get("critical") or 0) == 0,
            "value": int(incidents.get("critical") or 0),
        }
    )
    checks.append(
        {
            "id": "INCIDENT_ERROR_24H",
            "ok": int(incidents.get("error_or_worse") or 0) <= 8,
            "value": int(incidents.get("error_or_worse") or 0),
        }
    )
    checks.append(
        {
            "id": "CANARY_PROMOTED_OR_NOT_REQUIRED",
            "ok": (canary_promoted is None) or bool(canary_promoted),
            "value": None if canary_promoted is None else bool(canary_promoted),
        }
    )
    checks.append(
        {
            "id": "DEPENDENCY_REQUIREMENTS",
            "ok": bool(dep.get("ok_requirements")),
            "value": list(dep.get("missing_requirements") or []),
        }
    )
    checks.append(
        {
            "id": "DEPENDENCY_LOCAL_LINKS",
            "ok": bool(dep.get("ok_local_links")),
            "value": int(dep.get("local_unresolved_total") or 0),
        }
    )
    checks.append(
        {
            "id": "COLD_START_CANARY_OVERRIDE",
            "ok": (not cold_start_candidate) or bool(cold_start_override),
            "value": (
                None
                if not cold_start_candidate
                else {
                    "active": bool(cold_start_override),
                    "flag": bool(cold_start_flag),
                    "n_total": int(n_total),
                    "reasons": sorted(reasons),
                }
            ),
        }
    )

    go = bool(all(bool(c.get("ok")) for c in checks))
    reason = "GO_COLD_START_CANARY" if (go and cold_start_override) else ("GO" if go else "NO_GO")
    return {
        "schema": "oanda_mt5.prelive_go_nogo.v1",
        "ts_utc": _now_utc_iso(),
        "root": str(root),
        "go": bool(go),
        "reason": reason,
        "checks": checks,
        "qa_light": qa_light,
        "n_total": int(n_total),
        "anti_overfit_reasons": sorted(reasons),
        "incidents_24h": incidents,
        "dependency_hygiene": dep,
        "canary_promoted": canary_promoted,
        "cold_start_candidate": bool(cold_start_candidate),
        "cold_start_override": bool(cold_start_override),
        "cold_start_flag_path": str(cold_start_flag_path),
    }


def write_report(root: Path, report: Dict[str, Any]) -> Path:
    ts = str(report.get("ts_utc") or _now_utc_iso()).replace(":", "").replace("-", "")
    out_dir = Path(root) / "EVIDENCE"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"prelive_go_nogo_{ts}.json"
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return out


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Pre-live GO/NO-GO gate for OANDA MT5 runtime root.")
    p.add_argument("--root", type=str, default=".", help="Runtime root path")
    return p.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    rep = evaluate_prelive(root)
    out = write_report(root, rep)
    print(f"PRELIVE_GATE | go={int(bool(rep.get('go')))} | report={out}")
    return 0 if bool(rep.get("go")) else 1


if __name__ == "__main__":
    raise SystemExit(main())
