from __future__ import annotations

import copy
import datetime as dt
import json
import os
import sqlite3
import tempfile
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

try:
    from .runtime_root import get_runtime_root
    from .training_scope import load_training_scope, symbol_in_scope, window_in_scope
except Exception:  # pragma: no cover
    from runtime_root import get_runtime_root
    from training_scope import load_training_scope, symbol_in_scope, window_in_scope

UTC = dt.timezone.utc
SCHEMA = "oanda_mt5.unified_learning_advice.v1"
RUNTIME_LIGHT_MAX_RANKS = 8


def _now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def iso_utc(ts: Optional[dt.datetime] = None) -> str:
    return (ts or _now_utc()).astimezone(UTC).isoformat().replace("+00:00", "Z")


def parse_ts_utc(raw: Any) -> Optional[dt.datetime]:
    s = str(raw or "").strip()
    if not s:
        return None
    try:
        parsed = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=UTC)
    return parsed.astimezone(UTC)


def _resolve_lab_data_root(root: Path, explicit: Optional[Path] = None) -> Path:
    if explicit is not None:
        return Path(explicit).resolve()
    env = str(os.environ.get("OANDA_MT5_LAB_DATA_ROOT") or os.environ.get("OANDA_MT5_LAB_DATA") or "").strip()
    if env:
        return Path(env).resolve()
    fallback = Path(r"C:\OANDA_MT5_LAB_DATA")
    if fallback.exists():
        return fallback.resolve()
    return (root / "LAB_DATA").resolve()


def _safe_load_json(path: Path) -> Dict[str, Any]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _symbol_base(raw: Any) -> str:
    s = str(raw or "").strip().upper()
    if not s:
        return ""
    for sep in (".", "-", "_"):
        if sep in s:
            s = s.split(sep, 1)[0]
    if s.endswith(".PRO"):
        s = s[:-4]
    return s


def _safe_float(raw: Any, default: float = 0.0) -> float:
    try:
        return float(raw)
    except Exception:
        return float(default)


def _safe_int(raw: Any, default: int = 0) -> int:
    try:
        return int(raw)
    except Exception:
        return int(default)


def _clamp(v: float, lo: float, hi: float) -> float:
    return max(float(lo), min(float(hi), float(v)))


def _freshness_dict(path: Path, payload: Dict[str, Any]) -> Dict[str, Any]:
    ts = parse_ts_utc(payload.get("generated_at_utc") or payload.get("ts_utc") or payload.get("started_at_utc"))
    ttl = _safe_int(payload.get("ttl_sec"), 0)
    age_sec: Optional[float] = None
    fresh: Optional[bool] = None
    if ts is not None:
        age_sec = max(0.0, (_now_utc() - ts).total_seconds())
    if ttl > 0 and age_sec is not None:
        fresh = bool(age_sec <= float(ttl))
    return {
        "path": str(path),
        "exists": bool(path.exists()),
        "ts_utc": iso_utc(ts) if ts is not None else "",
        "ttl_sec": int(ttl),
        "age_sec": (round(float(age_sec), 3) if age_sec is not None else None),
        "fresh": fresh,
    }


def _signed_clip(x: float, *, scale: float) -> float:
    if float(scale) <= 0.0:
        return 0.0
    return max(-1.0, min(1.0, float(x) / float(scale)))


def _rank_map(rows: Iterable[Dict[str, Any]], *, symbol_key: str = "symbol") -> Dict[str, Dict[str, Any]]:
    out: Dict[str, Dict[str, Any]] = {}
    for idx, row in enumerate(rows, start=1):
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(row.get(symbol_key))
        if not sym or sym in out:
            continue
        item = dict(row)
        item["rank_pos"] = int(idx)
        out[sym] = item
    return out


def _rank_bonus(rank_pos: int) -> float:
    if rank_pos <= 0:
        return 0.0
    return max(0.0, 1.0 - ((float(rank_pos) - 1.0) * 0.12))


def _feedback_bucket() -> Dict[str, Any]:
    return {
        "learning_assist_n": 0,
        "learning_assist_positive_n": 0,
        "learning_assist_net_total": 0.0,
        "safetybot_core_n": 0,
        "safetybot_core_positive_n": 0,
        "safetybot_core_net_total": 0.0,
        "learning_suppress_override_n": 0,
        "learning_suppress_override_positive_n": 0,
        "learning_suppress_override_net_total": 0.0,
        "closed_paper_n": 0,
    }


def _extract_choice_runtime_influence(topk_json_raw: Any, choice_symbol: Any) -> Dict[str, Any]:
    out = {
        "score_delta": 0,
        "rank_pct_bonus": 0.0,
        "learning_assist": False,
        "learning_suppress": False,
    }
    choice = _symbol_base(choice_symbol)
    if not choice:
        return out
    try:
        payload = json.loads(str(topk_json_raw or "[]"))
    except Exception:
        return out
    if not isinstance(payload, list):
        return out
    for row in payload:
        if not isinstance(row, dict):
            continue
        raw_sym = _symbol_base(row.get("raw") or row.get("sym"))
        if raw_sym != choice:
            continue
        proposal = row.get("proposal") if isinstance(row.get("proposal"), dict) else {}
        rank_adj = row.get("unified_rank_adjustment") if isinstance(row.get("unified_rank_adjustment"), dict) else {}
        score_delta = _safe_int(proposal.get("unified_learning_score_delta"))
        rank_pct_bonus = _safe_float(rank_adj.get("pct_bonus"))
        out["score_delta"] = int(score_delta)
        out["rank_pct_bonus"] = float(rank_pct_bonus)
        out["learning_assist"] = bool(score_delta > 0 or rank_pct_bonus > 0.0)
        out["learning_suppress"] = bool(score_delta < 0 or rank_pct_bonus < 0.0)
        return out
    return out


def _bucket_note(
    bucket: Dict[str, Any],
    *,
    pnl_net: float,
    learning_assist: bool,
    learning_suppress: bool,
) -> None:
    bucket["closed_paper_n"] = int(bucket.get("closed_paper_n", 0)) + 1
    if learning_assist:
        bucket["learning_assist_n"] = int(bucket.get("learning_assist_n", 0)) + 1
        if pnl_net > 0.0:
            bucket["learning_assist_positive_n"] = int(bucket.get("learning_assist_positive_n", 0)) + 1
        bucket["learning_assist_net_total"] = float(bucket.get("learning_assist_net_total", 0.0)) + float(pnl_net)
    else:
        bucket["safetybot_core_n"] = int(bucket.get("safetybot_core_n", 0)) + 1
        if pnl_net > 0.0:
            bucket["safetybot_core_positive_n"] = int(bucket.get("safetybot_core_positive_n", 0)) + 1
        bucket["safetybot_core_net_total"] = float(bucket.get("safetybot_core_net_total", 0.0)) + float(pnl_net)
    if learning_suppress:
        bucket["learning_suppress_override_n"] = int(bucket.get("learning_suppress_override_n", 0)) + 1
        if pnl_net > 0.0:
            bucket["learning_suppress_override_positive_n"] = int(bucket.get("learning_suppress_override_positive_n", 0)) + 1
        bucket["learning_suppress_override_net_total"] = float(bucket.get("learning_suppress_override_net_total", 0.0)) + float(pnl_net)


def _finalize_feedback_bucket(bucket: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(bucket)
    assist_n = max(0, _safe_int(bucket.get("learning_assist_n")))
    core_n = max(0, _safe_int(bucket.get("safetybot_core_n")))
    assist_avg = _safe_float(bucket.get("learning_assist_net_total")) / float(assist_n) if assist_n > 0 else 0.0
    core_avg = _safe_float(bucket.get("safetybot_core_net_total")) / float(core_n) if core_n > 0 else 0.0
    assist_wr = (float(_safe_int(bucket.get("learning_assist_positive_n"))) / float(assist_n)) if assist_n > 0 else 0.0
    core_wr = (float(_safe_int(bucket.get("safetybot_core_positive_n"))) / float(core_n)) if core_n > 0 else 0.0

    learning_weight = 1.0
    leader = "INSUFFICIENT_DATA"
    if assist_n >= 6 and core_n >= 6:
        edge_score = (
            0.65 * _signed_clip(assist_avg - core_avg, scale=8.0)
            + 0.35 * _signed_clip(assist_wr - core_wr, scale=0.18)
        )
        learning_weight = _clamp(1.0 + (0.25 * edge_score), 0.75, 1.25)
        if learning_weight >= 1.03:
            leader = "LEARNING"
        elif learning_weight <= 0.97:
            leader = "SAFETYBOT"
        else:
            leader = "BALANCED"
    elif assist_n == 0 and core_n >= 6:
        leader = "SAFETYBOT"
        learning_weight = 0.90

    out["learning_assist_net_avg"] = round(float(assist_avg), 6)
    out["safetybot_core_net_avg"] = round(float(core_avg), 6)
    out["learning_assist_win_rate"] = round(float(assist_wr), 6)
    out["safetybot_core_win_rate"] = round(float(core_wr), 6)
    out["learning_weight"] = round(float(learning_weight), 6)
    out["leader"] = str(leader)
    return out


def _source_feedback_payload(root: Path, *, lookback_days: int = 30) -> Dict[str, Any]:
    db_path = (Path(root).resolve() / "DB" / "decision_events.sqlite").resolve()
    out: Dict[str, Any] = {
        "schema": "oanda_mt5.unified_learning_source_feedback.v1",
        "lookback_days": int(max(1, int(lookback_days))),
        "db_path": str(db_path),
        "exists": bool(db_path.exists()),
        "global": _finalize_feedback_bucket(_feedback_bucket()),
        "by_symbol": {},
    }
    if not db_path.exists():
        return out

    cutoff = iso_utc(_now_utc() - dt.timedelta(days=max(1, int(lookback_days))))
    global_bucket = _feedback_bucket()
    symbol_buckets: Dict[str, Dict[str, Any]] = {}
    symbol_window_buckets: Dict[str, Dict[str, Dict[str, Any]]] = {}
    symbol_window_family_buckets: Dict[str, Dict[Tuple[str, str], Dict[str, Any]]] = {}

    try:
        conn = sqlite3.connect(str(db_path))
        cur = conn.cursor()
        rows = cur.execute(
            """
            SELECT choice_A, window_id, window_phase, strategy_family, outcome_pnl_net, topk_json
            FROM decision_events
            WHERE is_paper = 1
              AND outcome_closed_ts_utc IS NOT NULL
              AND ts_utc >= ?
            """,
            (cutoff,),
        ).fetchall()
        conn.close()
    except Exception:
        return out

    training_scope = load_training_scope(root)
    for choice_A, window_id, window_phase, strategy_family, pnl_net, topk_json_raw in rows:
        symbol = _symbol_base(choice_A)
        if not symbol:
            continue
        if not symbol_in_scope(training_scope, symbol):
            continue
        if not window_in_scope(training_scope, symbol, window_id):
            continue
        pnl_val = _safe_float(pnl_net)
        influence = _extract_choice_runtime_influence(topk_json_raw, symbol)
        learning_assist = bool(influence.get("learning_assist"))
        learning_suppress = bool(influence.get("learning_suppress"))
        target_window = f"{str(window_id or '').strip().upper()}|{str(window_phase or '').strip().upper()}".strip("|")
        target_family = str(strategy_family or "UNKNOWN").strip().upper() or "UNKNOWN"

        _bucket_note(global_bucket, pnl_net=pnl_val, learning_assist=learning_assist, learning_suppress=learning_suppress)

        sym_bucket = symbol_buckets.setdefault(symbol, _feedback_bucket())
        _bucket_note(sym_bucket, pnl_net=pnl_val, learning_assist=learning_assist, learning_suppress=learning_suppress)

        if target_window:
            win_bucket = symbol_window_buckets.setdefault(symbol, {}).setdefault(target_window, _feedback_bucket())
            _bucket_note(win_bucket, pnl_net=pnl_val, learning_assist=learning_assist, learning_suppress=learning_suppress)

            fam_bucket = symbol_window_family_buckets.setdefault(symbol, {}).setdefault(
                (target_window, target_family),
                _feedback_bucket(),
            )
            _bucket_note(fam_bucket, pnl_net=pnl_val, learning_assist=learning_assist, learning_suppress=learning_suppress)

    out["global"] = _finalize_feedback_bucket(global_bucket)
    symbol_payload: Dict[str, Any] = {}
    for symbol in sorted(symbol_buckets):
        symbol_payload[symbol] = {
            "summary": _finalize_feedback_bucket(symbol_buckets[symbol]),
            "window_feedback": [
                {
                    "window": window,
                    **_finalize_feedback_bucket(bucket),
                }
                for window, bucket in sorted(symbol_window_buckets.get(symbol, {}).items())
            ],
            "strategy_family_feedback": [
                {
                    "window": window,
                    "strategy_family": family,
                    **_finalize_feedback_bucket(bucket),
                }
                for (window, family), bucket in sorted(symbol_window_family_buckets.get(symbol, {}).items())
            ],
        }
    out["by_symbol"] = symbol_payload
    return out


def _extract_stage1_eval_map(payload: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    rows = payload.get("evaluation_by_symbol") if isinstance(payload.get("evaluation_by_symbol"), list) else []
    out: Dict[str, Dict[str, Any]] = {}
    for row in rows:
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(row.get("symbol"))
        if not sym:
            continue
        ranking = row.get("ranking") if isinstance(row.get("ranking"), list) else []
        rec = row.get("recommendation_for_tomorrow") if isinstance(row.get("recommendation_for_tomorrow"), dict) else {}
        recommended = str(rec.get("recommended_profile") or "").strip().upper()
        recommended_final = 0.0
        for item in ranking:
            if not isinstance(item, dict):
                continue
            if str(item.get("profile_name") or "").strip().upper() == recommended:
                recommended_final = _safe_float(item.get("final_score"))
                break
        out[sym] = {
            "recommended_profile": recommended,
            "guard_reason": str(rec.get("guard_reason") or ""),
            "recommended_final_score": recommended_final,
            "shadow_trades_n": _safe_int(((row.get("shadow") or {}).get("shadow_trades_n"))),
            "shadow_net_pips_per_trade": _safe_float(((row.get("shadow") or {}).get("shadow_net_pips_per_trade"))),
            "shadow_stability_score": _safe_float(((row.get("shadow") or {}).get("shadow_stability_score"))),
        }
    return out


def _extract_counterfactual_maps(
    payload: Dict[str, Any],
) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, List[Dict[str, Any]]], Dict[str, List[Dict[str, Any]]]]:
    agg = payload.get("aggregates") if isinstance(payload.get("aggregates"), dict) else {}
    by_symbol_rows = agg.get("by_symbol") if isinstance(agg.get("by_symbol"), list) else []
    by_symbol_window_rows = agg.get("by_symbol_window") if isinstance(agg.get("by_symbol_window"), list) else []
    by_symbol_window_family_rows = (
        agg.get("by_symbol_window_family") if isinstance(agg.get("by_symbol_window_family"), list) else []
    )

    by_symbol: Dict[str, Dict[str, Any]] = {}
    for row in by_symbol_rows:
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(row.get("symbol"))
        if not sym:
            continue
        by_symbol[sym] = {
            "samples_n": _safe_int(row.get("samples_n")),
            "saved_loss_n": _safe_int(row.get("saved_loss_n")),
            "missed_opportunity_n": _safe_int(row.get("missed_opportunity_n")),
            "neutral_timeout_n": _safe_int(row.get("neutral_timeout_n")),
            "avg_points": _safe_float(row.get("counterfactual_pnl_points_avg")),
            "total_points": _safe_float(row.get("counterfactual_pnl_points_total")),
            "recommendation": str(row.get("recommendation") or ""),
        }

    by_symbol_window: Dict[str, List[Dict[str, Any]]] = {}
    for row in by_symbol_window_rows:
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(row.get("symbol"))
        if not sym:
            continue
        by_symbol_window.setdefault(sym, []).append(
            {
                "window": str(row.get("window") or ""),
                "samples_n": _safe_int(row.get("samples_n")),
                "avg_points": _safe_float(row.get("counterfactual_pnl_points_avg")),
                "recommendation": str(row.get("recommendation") or ""),
            }
        )

    by_symbol_window_family: Dict[str, List[Dict[str, Any]]] = {}
    for row in by_symbol_window_family_rows:
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(row.get("symbol"))
        if not sym:
            continue
        by_symbol_window_family.setdefault(sym, []).append(
            {
                "window": str(row.get("window") or ""),
                "strategy_family": str(row.get("strategy_family") or "UNKNOWN"),
                "samples_n": _safe_int(row.get("samples_n")),
                "avg_points": _safe_float(row.get("counterfactual_pnl_points_avg")),
                "recommendation": str(row.get("recommendation") or ""),
            }
        )
    return by_symbol, by_symbol_window, by_symbol_window_family


def _extract_stage1_apply_map(payload: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
    instruments = payload.get("instruments") if isinstance(payload.get("instruments"), dict) else {}
    out: Dict[str, Dict[str, Any]] = {}
    for sym_raw, row in instruments.items():
        if not isinstance(row, dict):
            continue
        sym = _symbol_base(sym_raw)
        if not sym:
            continue
        out[sym] = {
            "active_profile": str(row.get("active_profile") or ""),
            "profile_label_pl": str(row.get("profile_label_pl") or ""),
            "profile_id": str(row.get("profile_id") or ""),
            "reason_for_change": str(row.get("reason_for_change") or ""),
        }
    return out


def _extract_strategy_scope(payload: Dict[str, Any], stage1_apply: Dict[str, Dict[str, Any]]) -> List[str]:
    if stage1_apply:
        return sorted(stage1_apply.keys())
    rows = payload.get("symbols_to_trade") if isinstance(payload.get("symbols_to_trade"), list) else []
    return sorted({_symbol_base(x) for x in rows if _symbol_base(x)})


def _global_qa(
    *,
    learner_qa: str,
    verdict_light: str,
    gonogo_verdict: str,
    stage_name: str,
) -> str:
    lq = str(learner_qa or "").strip().upper()
    vq = str(verdict_light or "").strip().upper()
    gv = str(gonogo_verdict or "").strip().upper()
    st = str(stage_name or "").strip().upper()
    if "NO_GO" in gv or "REVIEW" in gv:
        return "RED"
    if lq == "RED" or vq == "RED":
        return "RED"
    if st == "WARMUP":
        return "YELLOW"
    if lq == "YELLOW" or vq == "YELLOW":
        return "YELLOW"
    if lq == "GREEN" and vq == "GREEN":
        return "GREEN"
    return "YELLOW"


def _consensus_row(
    *,
    symbol: str,
    learner_rank: Optional[Dict[str, Any]],
    scud_rank: Optional[Dict[str, Any]],
    stage1_eval: Optional[Dict[str, Any]],
    counterfactual: Optional[Dict[str, Any]],
    counterfactual_windows: List[Dict[str, Any]],
    counterfactual_window_families: List[Dict[str, Any]],
    stage1_apply: Optional[Dict[str, Any]],
    source_feedback_global: Optional[Dict[str, Any]],
    source_feedback_symbol: Optional[Dict[str, Any]],
) -> Dict[str, Any]:
    score = 0.0
    details: Dict[str, Any] = {}
    symbol_feedback_summary = (
        dict((source_feedback_symbol or {}).get("summary"))
        if isinstance((source_feedback_symbol or {}).get("summary"), dict)
        else {}
    )
    global_feedback_summary = dict(source_feedback_global or {})
    window_feedback_map: Dict[str, Dict[str, Any]] = {}
    family_feedback_map: Dict[Tuple[str, str], Dict[str, Any]] = {}
    if isinstance(source_feedback_symbol, dict):
        for row in (source_feedback_symbol.get("window_feedback") or []):
            if not isinstance(row, dict):
                continue
            key = str(row.get("window") or "").strip().upper()
            if key:
                window_feedback_map[key] = dict(row)
        for row in (source_feedback_symbol.get("strategy_family_feedback") or []):
            if not isinstance(row, dict):
                continue
            key = (
                str(row.get("window") or "").strip().upper(),
                str(row.get("strategy_family") or "UNKNOWN").strip().upper() or "UNKNOWN",
            )
            family_feedback_map[key] = dict(row)

    if stage1_eval is not None:
        stage_score = max(-1.0, min(1.0, _safe_float(stage1_eval.get("recommended_final_score"))))
        score += 0.55 * stage_score
        details["stage1_eval"] = dict(stage1_eval)

    if counterfactual is not None:
        cf_score = _signed_clip(_safe_float(counterfactual.get("avg_points")), scale=20.0)
        score += 0.20 * cf_score
        details["counterfactual"] = dict(counterfactual)

    if learner_rank is not None:
        rank_pos = _safe_int(learner_rank.get("rank_pos"))
        score += 0.15 * _rank_bonus(rank_pos)
        details["learner_rank"] = {
            "rank_pos": rank_pos,
            "score": _safe_float(learner_rank.get("score")),
            "n": _safe_int(learner_rank.get("n")),
        }

    if scud_rank is not None:
        rank_pos = _safe_int(scud_rank.get("rank_pos"))
        score += 0.10 * _rank_bonus(rank_pos)
        details["scud_rank"] = {
            "rank_pos": rank_pos,
            "score": _safe_float(scud_rank.get("score")),
            "n": _safe_int(scud_rank.get("n")),
        }

    if stage1_apply is not None:
        ap = str(stage1_apply.get("active_profile") or "").strip().lower()
        if ap == "balanced":
            score += 0.04
        elif ap == "conservative":
            score -= 0.02
        elif ap == "emergency":
            score -= 0.15
        details["stage1_apply"] = dict(stage1_apply)

    advisory_bias = "NEUTRAL"
    if score >= 0.20:
        advisory_bias = "PROMOTE"
    elif score <= -0.10:
        advisory_bias = "SUPPRESS"

    details["window_advisory"] = [
        {
            **dict(row),
            "source_feedback": window_feedback_map.get(str(row.get("window") or "").strip().upper(), symbol_feedback_summary or global_feedback_summary),
        }
        for row in list(counterfactual_windows or [])
    ]
    details["strategy_family_advisory"] = [
        {
            **dict(row),
            "source_feedback": family_feedback_map.get(
                (
                    str(row.get("window") or "").strip().upper(),
                    str(row.get("strategy_family") or "UNKNOWN").strip().upper() or "UNKNOWN",
                ),
                symbol_feedback_summary or global_feedback_summary,
            ),
        }
        for row in list(counterfactual_window_families or [])
    ]
    details["source_feedback"] = symbol_feedback_summary or global_feedback_summary
    details["consensus_score"] = round(float(score), 6)
    details["advisory_bias"] = advisory_bias
    details["symbol"] = str(symbol)
    return details


def _build_runtime_light(
    *,
    global_qa: str,
    learner_metrics: Dict[str, Any],
    verdict_metrics: Dict[str, Any],
    ranked_rows: List[Dict[str, Any]],
) -> Dict[str, Any]:
    metrics_src = learner_metrics if learner_metrics else verdict_metrics
    metrics = {
        "n": _safe_int(metrics_src.get("n")),
        "mean_edge_fuel": round(_safe_float(metrics_src.get("mean_edge_fuel")), 12),
        "es95": round(_safe_float(metrics_src.get("es95")), 12),
        "mdd": round(_safe_float(metrics_src.get("mdd")), 6),
        "symbols_n": int(len(ranked_rows)),
    }
    ranks: List[Dict[str, Any]] = []
    for row in ranked_rows[:RUNTIME_LIGHT_MAX_RANKS]:
        ranks.append(
            {
                "symbol": str(row.get("symbol") or ""),
                "score": round(_safe_float(row.get("consensus_score")), 6),
                "n": _safe_int((((row.get("learner_rank") or {}).get("n")) or 0)),
            }
        )
    preferred_symbol = str(ranks[0].get("symbol") or "") if ranks else ""
    return {
        "qa_light": str(global_qa),
        "preferred_symbol": preferred_symbol,
        "metrics": metrics,
        "ranks": ranks,
        "notes": [
            "source=unified_learning_pack",
            "mode=shadow_advisory",
            "no_live_mutation=1",
        ],
    }


def compute_hash_excluding_field(payload: Dict[str, Any], field_name: str = "config_hash") -> str:
    import hashlib

    obj = copy.deepcopy(payload)
    obj.pop(field_name, None)
    raw = json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def atomic_write_json(path: Path, payload: Dict[str, Any]) -> str:
    obj = copy.deepcopy(payload)
    obj["config_hash"] = compute_hash_excluding_field(obj, "config_hash")
    raw = json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True)
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=".tmp_unified_learning_", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, path)
    finally:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass
    return str(obj["config_hash"])


def build_unified_learning_payload(root: Path, *, lab_data_root: Optional[Path] = None) -> Dict[str, Any]:
    root = Path(root).resolve()
    lab_root = _resolve_lab_data_root(root, explicit=lab_data_root)
    meta_dir = (root / "META").resolve()
    stage1_reports = (lab_root / "reports" / "stage1").resolve()
    lab_reports_profiles = (lab_root / "reports" / "profiles").resolve()
    lab_reports_insights = (lab_root / "reports" / "insights").resolve()

    learner_path = meta_dir / "learner_advice.json"
    scout_path = meta_dir / "scout_advice.json"
    verdict_path = meta_dir / "verdict.json"
    stage1_apply_path = (root / "LAB" / "RUN" / "live_config_stage1_apply.json").resolve()
    strategy_path = (root / "CONFIG" / "strategy.json").resolve()
    stage1_eval_path = stage1_reports / "stage1_profile_pack_eval_latest.json"
    stage1_pack_path = stage1_reports / "stage1_profile_pack_latest.json"
    cf_summary_path = stage1_reports / "stage1_counterfactual_summary_latest.json"
    gonogo_path = stage1_reports / "stage1_shadow_gonogo_latest.json"
    progression_path = stage1_reports / "shadow_plus_progression_latest.json"

    learner = _safe_load_json(learner_path)
    scout = _safe_load_json(scout_path)
    verdict = _safe_load_json(verdict_path)
    stage1_apply = _safe_load_json(stage1_apply_path)
    strategy = _safe_load_json(strategy_path)
    stage1_eval = _safe_load_json(stage1_eval_path)
    stage1_pack = _safe_load_json(stage1_pack_path)
    cf_summary = _safe_load_json(cf_summary_path)
    gonogo = _safe_load_json(gonogo_path)
    progression = _safe_load_json(progression_path)
    source_feedback = _source_feedback_payload(root)
    training_scope = load_training_scope(root)
    if isinstance(source_feedback.get("by_symbol"), dict):
        source_feedback["by_symbol"] = {
            str(sym): row
            for sym, row in source_feedback.get("by_symbol", {}).items()
            if symbol_in_scope(training_scope, sym)
        }

    learner_ranks = _rank_map(learner.get("ranks") if isinstance(learner.get("ranks"), list) else [])
    scout_ranks = _rank_map(scout.get("ranks") if isinstance(scout.get("ranks"), list) else [])
    stage1_eval_map = _extract_stage1_eval_map(stage1_eval)
    counterfactual_map, counterfactual_window_map, counterfactual_window_family_map = _extract_counterfactual_maps(cf_summary)
    stage1_apply_map = _extract_stage1_apply_map(stage1_apply)
    scoped_symbols = [sym for sym in _extract_strategy_scope(strategy, stage1_apply_map) if symbol_in_scope(training_scope, sym)]
    source_feedback_global = source_feedback.get("global") if isinstance(source_feedback.get("global"), dict) else {}
    source_feedback_by_symbol = source_feedback.get("by_symbol") if isinstance(source_feedback.get("by_symbol"), dict) else {}

    symbol_universe = set(scoped_symbols)
    symbol_universe.update(stage1_eval_map.keys())
    symbol_universe.update(counterfactual_map.keys())
    symbol_universe.update(learner_ranks.keys())
    symbol_universe.update(scout_ranks.keys())
    symbol_universe = {sym for sym in symbol_universe if symbol_in_scope(training_scope, sym)}

    instrument_rows: List[Dict[str, Any]] = []
    for sym in sorted(symbol_universe):
        row = _consensus_row(
            symbol=sym,
            learner_rank=learner_ranks.get(sym),
            scud_rank=scout_ranks.get(sym),
            stage1_eval=stage1_eval_map.get(sym),
            counterfactual=counterfactual_map.get(sym),
            counterfactual_windows=counterfactual_window_map.get(sym, []),
            counterfactual_window_families=counterfactual_window_family_map.get(sym, []),
            stage1_apply=stage1_apply_map.get(sym),
            source_feedback_global=source_feedback_global,
            source_feedback_symbol=(source_feedback_by_symbol.get(sym) if isinstance(source_feedback_by_symbol, dict) else None),
        )
        instrument_rows.append(row)

    instrument_rows.sort(
        key=lambda item: (
            _safe_float(item.get("consensus_score")),
            _safe_int((((item.get("learner_rank") or {}).get("n")) or 0)),
            -len(item.get("window_advisory") or []),
            -len(item.get("strategy_family_advisory") or []),
            str(item.get("symbol") or ""),
        ),
        reverse=True,
    )

    learner_qa = str(learner.get("qa_light") or "").strip().upper()
    verdict_light = str(verdict.get("light") or scout.get("light") or "").strip().upper()
    gonogo_verdict = str(gonogo.get("verdict") or "").strip().upper()
    stage_name = str(((progression.get("progress") or {}).get("stage")) or "").strip().upper()
    global_qa = _global_qa(
        learner_qa=learner_qa,
        verdict_light=verdict_light,
        gonogo_verdict=gonogo_verdict,
        stage_name=stage_name,
    )

    runtime_light = _build_runtime_light(
        global_qa=global_qa,
        learner_metrics=(learner.get("metrics") if isinstance(learner.get("metrics"), dict) else {}),
        verdict_metrics=(verdict.get("metrics") if isinstance(verdict.get("metrics"), dict) else {}),
        ranked_rows=instrument_rows,
    )

    instruments_payload: Dict[str, Any] = {str(row["symbol"]): row for row in instrument_rows}
    sources = {
        "learner_advice": _freshness_dict(learner_path, learner),
        "scout_advice": _freshness_dict(scout_path, scout),
        "verdict": _freshness_dict(verdict_path, verdict),
        "stage1_apply": _freshness_dict(stage1_apply_path, stage1_apply),
        "stage1_eval": _freshness_dict(stage1_eval_path, stage1_eval),
        "stage1_profile_pack": _freshness_dict(stage1_pack_path, stage1_pack),
        "counterfactual_summary": _freshness_dict(cf_summary_path, cf_summary),
        "shadow_gonogo": _freshness_dict(gonogo_path, gonogo),
        "shadow_progression": _freshness_dict(progression_path, progression),
        "lab_profiles_dir": {"path": str(lab_reports_profiles), "exists": bool(lab_reports_profiles.exists())},
        "lab_insights_dir": {"path": str(lab_reports_insights), "exists": bool(lab_reports_insights.exists())},
    }

    return {
        "schema": SCHEMA,
        "generated_at_utc": iso_utc(),
        "ttl_sec": 3600,
        "root": str(root),
        "lab_data_root": str(lab_root),
        "global": {
            "qa_light": global_qa,
            "preferred_symbol": str(runtime_light.get("preferred_symbol") or ""),
            "paper_trading": bool(strategy.get("paper_trading", True)),
            "policy_shadow_mode_enabled": bool(strategy.get("policy_shadow_mode_enabled", True)),
            "gonogo_verdict": gonogo_verdict or "UNKNOWN",
            "progress_stage": stage_name or "UNKNOWN",
            "scoped_symbols_n": int(len(scoped_symbols)),
            "instruments_n": int(len(instruments_payload)),
            "source_feedback": source_feedback_global,
        },
        "training_scope": {
            "enabled": bool(training_scope.get("enabled", False)),
            "allowed_symbols": list(training_scope.get("allowed_symbols") or []),
            "active_symbols": list(training_scope.get("active_symbols") or []),
            "secondary_symbols": list(training_scope.get("secondary_symbols") or []),
            "shadow_only_symbols": list(training_scope.get("shadow_only_symbols") or []),
        },
        "runtime_light": runtime_light,
        "sources": sources,
        "source_feedback": source_feedback,
        "instruments": instruments_payload,
        "notes": [
            "Unified learning bus for paper/shadow only.",
            "No live mutation and no direct order control.",
            "SCUD may consume runtime_light as a single advisory signal.",
        ],
    }


def build_unified_learning_pack(
    root: Optional[Path] = None,
    *,
    lab_data_root: Optional[Path] = None,
    out_path: Optional[Path] = None,
) -> Tuple[Path, Dict[str, Any]]:
    root_path = Path(root).resolve() if root is not None else get_runtime_root(enforce=True)
    payload = build_unified_learning_payload(root_path, lab_data_root=lab_data_root)
    out = Path(out_path).resolve() if out_path is not None else (root_path / "META" / "unified_learning_advice.json").resolve()
    atomic_write_json(out, payload)
    return out, payload


def read_unified_runtime_advice(meta_dir: Path) -> Optional[Dict[str, Any]]:
    path = Path(meta_dir).resolve() / "unified_learning_advice.json"
    obj = _safe_load_json(path)
    if not obj:
        return None
    ts = parse_ts_utc(obj.get("generated_at_utc") or obj.get("ts_utc"))
    ttl = _safe_int(obj.get("ttl_sec"), 0)
    if ts is None or ttl <= 0:
        return None
    age = (_now_utc() - ts).total_seconds()
    if age < -5.0 or age > float(ttl):
        return None
    runtime_light = obj.get("runtime_light") if isinstance(obj.get("runtime_light"), dict) else {}
    if not runtime_light:
        return None
    qa = str(runtime_light.get("qa_light") or "").strip().upper()
    if qa not in {"GREEN", "YELLOW", "RED"}:
        return None
    ranks = runtime_light.get("ranks") if isinstance(runtime_light.get("ranks"), list) else []
    metrics = runtime_light.get("metrics") if isinstance(runtime_light.get("metrics"), dict) else {}
    return {
        "metrics": {
            "n": _safe_int(metrics.get("n")),
            "mean_edge_fuel": _safe_float(metrics.get("mean_edge_fuel")),
            "es95": _safe_float(metrics.get("es95")),
            "mdd": _safe_float(metrics.get("mdd")),
        },
        "ranks": ranks,
        "qa_light": qa,
        "source": "unified_learning_pack",
    }
