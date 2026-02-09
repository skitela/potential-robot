# -*- coding: utf-8 -*-
"""
COMMON_CONTRACT — RUN tie-break contract pv=2 (strict).

This module enforces:
- pv must be exactly 2 (reject pv!=2)
- exact keys (strict schema)
- type/range constraints
- compact JSON length <= 2048 is enforced by callers via common_guards.guard_max_json_len()
"""
from __future__ import annotations

import re
from typing import Any, Dict, List, Optional
try:
    from . import common_guards as cg  # type: ignore
except ImportError:
    import common_guards as cg  # noqa: F401

RUN_REQ_KEYS_V2 = {"pv","ts_utc","rid","ttl_sec","cands","mode","ctx"}
RUN_RES_KEYS_V2 = {"pv","ts_utc","rid","tb","pref","reasons"}

RID_RE = re.compile(r"^[A-Za-z0-9_-]{8,64}$")

def _is_iso_utc_z(s: str) -> bool:
    # Minimal, deterministic check: endswith Z and contains 'T'
    if not isinstance(s, str):
        return False
    s = s.strip()
    if not s.endswith("Z"):
        return False
    if "T" not in s:
        return False
    if len(s) < 16 or len(s) > 30:
        return False
    return True

def _norm_sym(s: str) -> str:
    return str(s or "").strip().upper()

def validate_run_request_v2(obj: Any) -> Optional[Dict[str, Any]]:
    try:
        if not isinstance(obj, dict):
            return None
        if set(obj.keys()) != RUN_REQ_KEYS_V2:
            return None
        if int(obj.get("pv") or 0) != 2:
            return None
        rid = str(obj.get("rid") or "").strip()
        if not RID_RE.match(rid):
            return None
        ts = obj.get("ts_utc")
        if not _is_iso_utc_z(ts):
            return None
        ttl = int(obj.get("ttl_sec") or 0)
        if ttl < 1 or ttl > 60:
            return None
        mode = str(obj.get("mode") or "").strip().upper()
        if mode not in {"LIVE","PAPER"}:
            return None
        cands = obj.get("cands")
        if not isinstance(cands, list) or len(cands) != 2:
            return None
        a = _norm_sym(cands[0])
        b = _norm_sym(cands[1])
        if not a or not b or a == b:
            return None
        if len(a) > 32 or len(b) > 32:
            return None
        ctx = obj.get("ctx")
        if not isinstance(ctx, dict):
            return None
        # ctx allowed keys: mode (str) and note (str<=128)
        for k in ctx.keys():
            if k not in {"mode","note"}:
                return None
        if "mode" in ctx and not isinstance(ctx["mode"], str):
            return None
        if "note" in ctx:
            if not isinstance(ctx["note"], str):
                return None
            if len(ctx["note"]) > 128:
                return None
        return {
            "pv": 2,
            "ts_utc": str(ts).strip(),
            "rid": rid,
            "ttl_sec": ttl,
            "cands": [a, b],
            "mode": mode,
            "ctx": {"mode": ctx.get("mode",""), "note": ctx.get("note","")}.copy()
        }
    except Exception as e:
        cg.tlog(None, "WARN", "CONTRACT_EXC", "nonfatal exception swallowed", e)
        return None

def validate_run_response_v2(obj: Any, rid_expected: str = "") -> Optional[Dict[str, Any]]:
    try:
        if not isinstance(obj, dict):
            return None
        if set(obj.keys()) != RUN_RES_KEYS_V2:
            return None
        if int(obj.get("pv") or 0) != 2:
            return None
        rid = str(obj.get("rid") or "").strip()
        if not RID_RE.match(rid):
            return None
        if rid_expected and rid != str(rid_expected).strip():
            return None
        ts = obj.get("ts_utc")
        if not _is_iso_utc_z(ts):
            return None
        tb = int(obj.get("tb") or 0)
        if tb not in {0,1,2}:
            return None
        pref = _norm_sym(obj.get("pref") or "")
        if pref and len(pref) > 32:
            return None
        reasons = obj.get("reasons")
        if not isinstance(reasons, list) or len(reasons) > 8:
            return None
        out_reasons: List[str] = []
        for r in reasons:
            if not isinstance(r, str):
                return None
            rr = r.strip()
            if len(rr) > 32:
                return None
            out_reasons.append(rr)
        return {
            "pv": 2,
            "ts_utc": str(ts).strip(),
            "rid": rid,
            "tb": tb,
            "pref": pref,
            "reasons": out_reasons
        }
    except Exception as e:
        cg.tlog(None, "WARN", "CONTRACT_EXC", "nonfatal exception swallowed", e)
        return None
