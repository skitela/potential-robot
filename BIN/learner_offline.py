# -*- coding: utf-8 -*-
r"""LEARNER-OFFLINE — cięższa statystyka ex-post z DB SafetyBota (read-only).

Cel:
- czyta wyłącznie DB\\decision_events.sqlite (zamknięte zdarzenia),
- liczy metryki "jak u quantów" (średnia + ogon ryzyka + maks. obsunięcie + PSR),
- zapisuje mały, price-free destylat do META\\learner_advice.json,
- opcjonalnie zapisuje rozszerzony raport do LOGS\\learner_offline_report.json,
- fail-open: błąd => brak nowego pliku (SCUD/SafetyBot działają dalej).

WAŻNE (zgodność z P0):
- wyjście do META ma <= 50 tokenów liczbowych i bez price-like kluczy/tekstów.

Uruchomienie:
  python learner_offline.py once
  python learner_offline.py loop 3600

"""

from __future__ import annotations

import os, sys, json, time, math, sqlite3, logging, shutil, ctypes
import datetime as dt
from pathlib import Path

# Keep runtime/audit workspace clean when running learner from repo root.
sys.dont_write_bytecode = True

try:
    from .runtime_root import get_runtime_root
except Exception:  # pragma: no cover
    from runtime_root import get_runtime_root

from typing import Any, Dict, List, Optional, Tuple
try:
    from . import common_guards as cg
except Exception:  # pragma: no cover
    import common_guards as cg

UTC = dt.timezone.utc

DETERMINISTIC_MODE = os.environ.get("OFFLINE_DETERMINISTIC", "").strip() == "1"

STAGE1_SUGGESTIONS_SCHEMA = "oanda_mt5.learner_policy_suggestions.v1"
STAGE1_MILESTONES_SCHEMA = "oanda_mt5.learner_milestones.v1"
STAGE1_SUGGESTIONS_FILE = "learner_policy_suggestions_v1.json"
STAGE1_MILESTONES_FILE = "learner_milestones_v1.json"

def _now_utc() -> dt.datetime:
    if DETERMINISTIC_MODE:
        return dt.datetime(1970, 1, 1, tzinfo=UTC)
    return dt.datetime.now(tz=UTC)

def _env_bool(name: str, default: bool) -> bool:
    raw = str(os.environ.get(name, "1" if default else "0") or "").strip().lower()
    if raw in {"1", "true", "yes", "y", "on"}:
        return True
    if raw in {"0", "false", "no", "n", "off"}:
        return False
    return bool(default)

def _env_int(name: str, default: int, *, vmin: int, vmax: int) -> int:
    try:
        raw = os.environ.get(name, str(default))
        val = int(str(raw).strip() or str(default))
    except Exception:
        val = int(default)
    return max(vmin, min(vmax, int(val)))

def _env_float(name: str, default: float, *, vmin: float, vmax: float) -> float:
    try:
        raw = os.environ.get(name, str(default))
        val = float(str(raw).strip() or str(default))
    except Exception:
        val = float(default)
    return max(vmin, min(vmax, float(val)))

def _cpu_pct_windows(sample_sec: float = 0.15) -> Optional[float]:
    # Lightweight CPU snapshot without external deps (Windows GetSystemTimes).
    try:
        class FILETIME(ctypes.Structure):
            _fields_ = [("dwLowDateTime", ctypes.c_uint32), ("dwHighDateTime", ctypes.c_uint32)]

        def _ft_to_int(ft: FILETIME) -> int:
            return (int(ft.dwHighDateTime) << 32) | int(ft.dwLowDateTime)

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        idle1, kern1, user1 = FILETIME(), FILETIME(), FILETIME()
        ok1 = kernel32.GetSystemTimes(ctypes.byref(idle1), ctypes.byref(kern1), ctypes.byref(user1))
        if not ok1:
            return None
        time.sleep(max(0.05, min(0.5, float(sample_sec))))
        idle2, kern2, user2 = FILETIME(), FILETIME(), FILETIME()
        ok2 = kernel32.GetSystemTimes(ctypes.byref(idle2), ctypes.byref(kern2), ctypes.byref(user2))
        if not ok2:
            return None

        idle_delta = _ft_to_int(idle2) - _ft_to_int(idle1)
        kern_delta = _ft_to_int(kern2) - _ft_to_int(kern1)
        user_delta = _ft_to_int(user2) - _ft_to_int(user1)
        total = kern_delta + user_delta
        if total <= 0:
            return None
        busy = max(0, total - idle_delta)
        pct = 100.0 * (float(busy) / float(total))
        return float(max(0.0, min(100.0, pct)))
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return None

def _cpu_pct_posix() -> Optional[float]:
    # Approximation from load average when available.
    try:
        la1, _, _ = os.getloadavg()
        cpus = int(os.cpu_count() or 1)
        if cpus <= 0:
            return None
        pct = 100.0 * (float(la1) / float(cpus))
        return float(max(0.0, min(100.0, pct)))
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return None

def read_cpu_percent(sample_sec: float = 0.15) -> Optional[float]:
    if os.name == "nt":
        return _cpu_pct_windows(sample_sec=sample_sec)
    return _cpu_pct_posix()

def read_mem_available_mb() -> Optional[float]:
    # Available physical memory only, no external deps.
    try:
        if os.name == "nt":
            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_uint32),
                    ("dwMemoryLoad", ctypes.c_uint32),
                    ("ullTotalPhys", ctypes.c_uint64),
                    ("ullAvailPhys", ctypes.c_uint64),
                    ("ullTotalPageFile", ctypes.c_uint64),
                    ("ullAvailPageFile", ctypes.c_uint64),
                    ("ullTotalVirtual", ctypes.c_uint64),
                    ("ullAvailVirtual", ctypes.c_uint64),
                    ("ullAvailExtendedVirtual", ctypes.c_uint64),
                ]

            ms = MEMORYSTATUSEX()
            ms.dwLength = ctypes.sizeof(MEMORYSTATUSEX)
            ok = ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(ms))
            if not ok:
                return None
            return float(ms.ullAvailPhys) / float(1024 ** 2)

        page_size = os.sysconf("SC_PAGE_SIZE")
        avail_pages = os.sysconf("SC_AVPHYS_PAGES")
        return float(page_size * avail_pages) / float(1024 ** 2)
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return None

def decide_resource_mode(
    cpu_pct: Optional[float],
    mem_available_mb: Optional[float],
    *,
    cpu_soft_max_pct: float,
    cpu_hard_max_pct: float,
    mem_min_mb: float,
) -> Tuple[str, str]:
    # Priority: hard memory/cpu stop, then soft cpu throttling.
    if mem_available_mb is not None and float(mem_available_mb) < float(mem_min_mb):
        return ("skip", "mem_low")
    if cpu_pct is not None and float(cpu_pct) >= float(cpu_hard_max_pct):
        return ("skip", "cpu_hard")
    if cpu_pct is not None and float(cpu_pct) >= float(cpu_soft_max_pct):
        return ("light", "cpu_soft")
    return ("normal", "ok")

def effective_scan_params(
    *,
    base_window_days: int,
    base_row_limit: int,
    load_mode: str,
    light_window_days: int,
    light_row_limit: int,
) -> Tuple[int, int]:
    mode = str(load_mode or "").strip().lower()
    if mode == "light":
        wd = min(int(base_window_days), int(light_window_days))
        rl = min(int(base_row_limit), int(light_row_limit))
        return (max(1, wd), max(1, rl))
    return (max(1, int(base_window_days)), max(1, int(base_row_limit)))

MAX_NUMERIC_TOKENS = 50
MAX_NUMERIC_LIST_LEN = 50
ATOMIC_REPLACE_RETRIES = 6
ATOMIC_REPLACE_RETRY_SLEEP_S = 0.05

BANNED_KEY_TOKENS = {
    "bid","ask","ohlc","open","high","low","close","price","prices","rate","rates","tick","ticks","quote","quotes","spread"
}

def runtime_root() -> Path:
    return get_runtime_root(enforce=True)

def ensure_dirs(root: Path) -> Dict[str, Path]:
    meta = root / "META"
    db = root / "DB"
    logs = root / "LOGS"
    run = root / "RUN"
    for p in (meta, db, logs, run):
        p.mkdir(parents=True, exist_ok=True)
    return {"root": root, "META": meta, "DB": db, "LOGS": logs, "RUN": run}

def setup_logging(root: Path) -> None:
    log_dir = root / "LOGS"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "learner_offline.log"
    try:
        from logging.handlers import RotatingFileHandler
        h = RotatingFileHandler(str(log_file), maxBytes=5_000_000, backupCount=5, encoding="utf-8")
        handlers = [h]
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        handlers = [logging.FileHandler(str(log_file), encoding="utf-8")]
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)s | %(message)s", handlers=handlers)

def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    last_exc: Optional[Exception] = None
    for i in range(max(1, int(ATOMIC_REPLACE_RETRIES))):
        tmp = path.with_name(f"{path.name}.tmp.{os.getpid()}.{int(time.time() * 1_000_000)}.{i}")
        wrote_tmp = False
        try:
            with open(tmp, "w", encoding="utf-8", newline="\n") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            wrote_tmp = True
        except Exception as e:
            last_exc = e
            time.sleep(float(ATOMIC_REPLACE_RETRY_SLEEP_S))
            continue
        try:
            os.replace(tmp, path)
            return
        except Exception as e:
            last_exc = e
            try:
                shutil.move(str(tmp), str(path))
                return
            except Exception as e2:
                last_exc = e2
        finally:
            if wrote_tmp:
                try:
                    tmp.unlink(missing_ok=True)
                except Exception as e:
                    cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        time.sleep(float(ATOMIC_REPLACE_RETRY_SLEEP_S))
    # Fallback for environments where atomic rename/move is blocked.
    try:
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        return
    except Exception as e:
        last_exc = e
    if last_exc is not None:
        raise last_exc

def parse_ts_utc(s: str) -> Optional[dt.datetime]:
    if not s:
        return None
    try:
        ss = str(s).strip()
        if ss.endswith('Z'):
            ss = ss[:-1] + '+00:00'
        t = dt.datetime.fromisoformat(ss)
        if t.tzinfo is None:
            t = t.replace(tzinfo=UTC)
        return t.astimezone(UTC)
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return None

def _safe_read_json(path: Path) -> Any:
    try:
        if not path.exists():
            return None
        txt = path.read_text(encoding="utf-8", errors="replace")
        return json.loads(txt)
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", f"read_json_failed path={path}", e)
        return None

def _clamp_int(x: int, lo: int, hi: int) -> int:
    try:
        return int(max(lo, min(hi, int(x))))
    except Exception:
        return int(lo)

def _median_int(xs: List[int]) -> Optional[int]:
    if not xs:
        return None
    ys = sorted(int(x) for x in xs)
    mid = len(ys) // 2
    if len(ys) % 2 == 1:
        return int(ys[mid])
    return int(round(0.5 * (float(ys[mid - 1]) + float(ys[mid]))))

def _quantile_int(xs: List[int], q: float) -> Optional[int]:
    if not xs:
        return None
    qf = float(max(0.0, min(1.0, float(q))))
    ys = sorted(int(x) for x in xs)
    if len(ys) == 1:
        return int(ys[0])
    pos = qf * float(len(ys) - 1)
    lo = int(math.floor(pos))
    hi = int(math.ceil(pos))
    if lo == hi:
        return int(ys[lo])
    w = float(pos - lo)
    return int(round((1.0 - w) * float(ys[lo]) + w * float(ys[hi])))

def _seg_norm(s: Any, *, fallback: str = "UNK", max_len: int = 32) -> str:
    try:
        out = str(s or "").strip().upper()
        out = out.replace(" ", "")
        if not out:
            out = fallback
        if len(out) > max_len:
            out = out[:max_len]
        return out
    except Exception:
        return str(fallback)

def _seg_id_group(grp: str, window_id: str, phase: str) -> str:
    return f"G|{_seg_norm(grp)}|{_seg_norm(window_id)}|{_seg_norm(phase)}"

def _seg_id_symbol(symbol: str, window_id: str, phase: str) -> str:
    return f"S|{_seg_norm(symbol, max_len=40)}|{_seg_norm(window_id)}|{_seg_norm(phase)}"

def _stage1_load_milestones(path: Path) -> Dict[str, Any]:
    obj = _safe_read_json(path)
    if not isinstance(obj, dict):
        return {"schema": STAGE1_MILESTONES_SCHEMA, "updated_ts_utc": "", "segments": {}}
    segs = obj.get("segments")
    if not isinstance(segs, dict):
        segs = {}
    return {
        "schema": str(obj.get("schema") or STAGE1_MILESTONES_SCHEMA),
        "updated_ts_utc": str(obj.get("updated_ts_utc") or ""),
        "segments": segs,
    }

def _stage1_due(n_cur: int, n_next_eval: int) -> bool:
    return int(n_cur) >= int(max(1, n_next_eval))

def _stage1_next_eval_n(n_cur: int, *, n_min: int, growth: float) -> int:
    n = int(max(0, n_cur))
    base = int(max(1, n_min))
    if n < base:
        return base
    g = float(max(1.05, min(2.00, float(growth))))
    return int(max(base, int(math.ceil(float(n) * g))))

def _stage1_partition_segments(rows: List[Dict[str, Any]]) -> Tuple[Dict[str, Dict[str, Any]], Dict[str, Dict[str, Any]]]:
    """
    Build segment index maps (disjoint by design):
      - Group segments: grp + window_id + window_phase
      - Symbol segments: symbol + window_id + window_phase
    Each entry: {"idxs":[...], "meta":{...}}
    """
    group: Dict[str, Dict[str, Any]] = {}
    sym: Dict[str, Dict[str, Any]] = {}
    for i, r in enumerate(rows):
        grp = _seg_norm(r.get("grp"))
        win = _seg_norm(r.get("window_id"))
        ph = _seg_norm(r.get("window_phase"))
        s = _seg_norm(r.get("symbol"), max_len=40)
        if grp != "UNK" and win != "UNK" and ph != "UNK":
            sid = _seg_id_group(grp, win, ph)
            ent = group.setdefault(sid, {"idxs": [], "meta": {"kind": "GROUP_WINDOW_PHASE", "grp": grp, "window_id": win, "phase": ph}})
            ent["idxs"].append(int(i))
        if s != "UNK" and win != "UNK" and ph != "UNK":
            sid2 = _seg_id_symbol(s, win, ph)
            ent2 = sym.setdefault(sid2, {"idxs": [], "meta": {"kind": "SYMBOL_WINDOW_PHASE", "symbol": s, "window_id": win, "phase": ph}})
            ent2["idxs"].append(int(i))
    return group, sym

def _stage1_suggest_entry_threshold(
    rows: List[Dict[str, Any]],
    *,
    n_min_subset: int,
) -> Dict[str, Any]:
    """
    Suggest entry_min_score threshold based on realized outcomes in this segment.
    Note: data is censored below the current threshold (trades are only present when the gate passed).
    """
    entry_scores: List[int] = []
    entry_mins: List[int] = []
    # Use edge proxy consistent with build_advice (pnl_net / reqs_trade).
    data: List[Tuple[int, float]] = []  # (entry_score, edge)
    for r in rows:
        es = r.get("entry_score")
        if es is None:
            continue
        try:
            es_i = int(es)
        except Exception:
            continue
        try:
            em = r.get("entry_min_score")
            if em is not None:
                entry_mins.append(int(em))
        except Exception as e:
            cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        try:
            reqs_i = int(r.get("reqs_trade") or 0)
            pnl = float(r.get("pnl_net") or 0.0)
            edge = (pnl / float(reqs_i)) if reqs_i > 0 else 0.0
        except Exception:
            continue
        entry_scores.append(es_i)
        data.append((es_i, float(edge)))

    base_thr = _median_int(entry_mins)
    if not entry_scores or not data:
        return {"ok": False, "reason": "NO_ENTRY_SCORE"}

    es_min = int(min(entry_scores))
    es_max = int(max(entry_scores))
    censored_below_current = 0
    if base_thr is not None and int(es_min) >= int(base_thr):
        censored_below_current = 1

    candidates: List[int] = []
    if base_thr is not None:
        for d in (-12, -8, -4, 0, 4, 8, 12):
            candidates.append(int(base_thr) + int(d))
        # also add a couple of quantiles to adapt to score scale
        for q in (0.25, 0.50, 0.75):
            qi = _quantile_int(entry_scores, q)
            if qi is not None:
                candidates.append(int(qi))
    else:
        for q in (0.10, 0.25, 0.50, 0.75, 0.90):
            qi = _quantile_int(entry_scores, q)
            if qi is not None:
                candidates.append(int(qi))

    # Clamp to plausible range [0..100] and to observed min/max.
    cand2 = []
    for c in candidates:
        cc = _clamp_int(int(c), 0, 100)
        if cc < es_min:
            cc = es_min
        if cc > es_max:
            cc = es_max
        cand2.append(int(cc))
    candidates = sorted(set(cand2))
    if not candidates:
        return {"ok": False, "reason": "NO_CANDIDATES"}

    best = None
    for t in candidates:
        subset = [edge for (es_i, edge) in data if int(es_i) >= int(t)]
        if len(subset) < int(max(5, n_min_subset)):
            continue
        mu = float(sum(subset) / len(subset))
        psr = float(probabilistic_sharpe_ratio(subset, sr_benchmark=0.0))
        score = float(mu) * float(psr)
        item = {"t": int(t), "n": int(len(subset)), "mu": float(mu), "psr": float(psr), "score": float(score)}
        if best is None or float(item["score"]) > float(best["score"]):
            best = item

    if best is None:
        return {"ok": False, "reason": "INSUFFICIENT_SUBSET"}

    # Prefer the smallest threshold within 95% of the best score (avoid overly strict gate).
    best_score = float(best["score"])
    chosen = int(best["t"])
    for t in candidates:
        subset = [edge for (es_i, edge) in data if int(es_i) >= int(t)]
        if len(subset) < int(max(5, n_min_subset)):
            continue
        mu = float(sum(subset) / len(subset))
        psr = float(probabilistic_sharpe_ratio(subset, sr_benchmark=0.0))
        score = float(mu) * float(psr)
        if best_score <= 0.0:
            continue
        if float(score) >= (0.95 * best_score):
            chosen = int(t)
            break

    return {
        "ok": True,
        "entry_min_score_current": None if base_thr is None else int(base_thr),
        "entry_min_score_suggested": int(chosen),
        "censored_below_current": int(censored_below_current),
        "observed_min": int(es_min),
        "observed_max": int(es_max),
        "best": best,
    }

def load_external_replay_summary(meta_dir: Path, *, max_age_sec: int) -> Optional[Dict[str, Any]]:
    """Load offline replay summary produced by TOOLS/offline_replay_analytics.py.
    Returns None when missing/stale/invalid.
    """
    path = Path(meta_dir) / "offline_replay_summary.json"
    if not path.exists():
        return None
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(obj, dict):
            return None
        ts = parse_ts_utc(str(obj.get("ts_utc") or ""))
        if ts is None:
            return None
        age = (_now_utc() - ts).total_seconds()
        if age < 0:
            age = 0.0
        if age > float(max_age_sec):
            return None
        return obj
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return None

def apply_external_replay_blend(
    meta_advice: Dict[str, Any],
    external_summary: Dict[str, Any],
    *,
    weight: float,
) -> int:
    """Optional tiny blend of rank score with external replay score.
    Returns number of rank rows updated.
    """
    if float(weight) <= 0.0:
        return 0
    ranks = meta_advice.get("ranks")
    if not isinstance(ranks, list) or not ranks:
        return 0
    src = external_summary.get("symbol_scores")
    if not isinstance(src, list) or not src:
        return 0

    ext_map: Dict[str, float] = {}
    for item in src:
        if not isinstance(item, dict):
            continue
        sym = str(item.get("symbol") or "").strip().upper()
        if not sym:
            continue
        try:
            sc = float(item.get("replay_score") or 0.0)
        except Exception:
            continue
        if not math.isfinite(sc):
            continue
        # Keep external component bounded to avoid unstable rank jumps.
        sc = max(-5.0, min(5.0, sc))
        ext_map[sym] = sc

    if not ext_map:
        return 0

    w = max(0.0, min(1.0, float(weight)))
    touched = 0
    for row in ranks:
        if not isinstance(row, dict):
            continue
        sym = str(row.get("symbol") or "").strip().upper()
        if sym not in ext_map:
            continue
        try:
            base = float(row.get("score") or 0.0)
        except Exception:
            base = 0.0
        blend = (1.0 - w) * base + w * float(ext_map[sym])
        row["score"] = round(float(blend), 12)
        touched += 1

    if touched > 0:
        ranks.sort(
            key=lambda d: (
                float(d.get("score", 0.0)),
                float(d.get("es95", 0.0)),
                -float(d.get("mdd", 0.0)),
                int(d.get("n", 0)),
            ),
            reverse=True,
        )
        meta_advice["ranks"] = ranks[:10]
    return int(touched)

# -------------------------
# Guards (META output)
# -------------------------
def _count_numeric_tokens(obj) -> int:
    if isinstance(obj, bool) or obj is None:
        return 0
    if isinstance(obj, (int, float)):
        return 1
    if isinstance(obj, dict):
        return sum(_count_numeric_tokens(v) for v in obj.values())
    if isinstance(obj, list):
        return sum(_count_numeric_tokens(v) for v in obj)
    return 0

def _has_numeric_list_over_limit(obj, limit: int = MAX_NUMERIC_LIST_LEN) -> bool:
    if isinstance(obj, list):
        if len(obj) > limit and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            return True
        return any(_has_numeric_list_over_limit(v, limit) for v in obj)
    if isinstance(obj, dict):
        return any(_has_numeric_list_over_limit(v, limit) for v in obj.values())
    return False

def guard_obj_limits(obj) -> None:
    if _has_numeric_list_over_limit(obj, MAX_NUMERIC_LIST_LEN):
        raise ValueError("P0_LIMIT_NUMERIC_LIST_GT_50")
    n = _count_numeric_tokens(obj)
    if n > MAX_NUMERIC_TOKENS:
        raise ValueError(f"P0_LIMIT_NUMERIC_TOKENS_GT_50:{n}")

def looks_pricey_text(s: str) -> bool:
    import re
    pat = re.compile(r"(\b\d{1,3}[.,]\d{2,6}\b)|(\b\d{1,5}\.\d{1,6}\b)|([$€£]\s*\d)|(\b\d+\s*(USD|EUR|PLN|GBP|JPY)\b)", re.IGNORECASE)
    return bool(pat.search(s or ""))

def guard_obj_no_price_like(obj: Any) -> None:
    """Fail-fast if any key/value is price-like. Boundary/token match (no substring traps)."""
    if isinstance(obj, dict):
        for k, v in obj.items():
            if cg.key_has_price_like_token(str(k)):
                raise ValueError(f"PRICE_LIKE_KEY:{k}")
            guard_obj_no_price_like(v)
    elif isinstance(obj, list):
        if len(obj) > 50 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            raise ValueError("PRICE_LIKE_LONG_NUM_LIST")
        for v in obj:
            guard_obj_no_price_like(v)
    elif isinstance(obj, str):
        if cg.text_has_price_like_token(obj):
            raise ValueError("PRICE_LIKE_TEXT_TOKEN")
        if looks_pricey_text(obj):
            raise ValueError("PRICE_LIKE_TEXT_NUMERIC")
    else:
        return

# -------------------------
# Stats
# -------------------------
def es95(values: List[float]) -> float:
    if not values:
        return 0.0
    xs = sorted(values)
    k = max(1, int(0.05 * len(xs)))
    return float(sum(xs[:k])) / float(k)

def max_drawdown(pnls: List[float]) -> float:
    peak = -1e18
    mdd = 0.0
    s = 0.0
    for x in pnls:
        s += x
        peak = max(peak, s)
        mdd = min(mdd, s - peak)
    return float(mdd)

def moments(values: List[float]) -> Tuple[float, float, float, float]:
    """mean, std(ddof=1), skewness, kurtosis (non-excess)"""
    n = len(values)
    if n < 2:
        return (0.0, 0.0, 0.0, 0.0)
    mu = sum(values) / n
    c2 = sum((x - mu) ** 2 for x in values) / (n - 1)
    sd = math.sqrt(max(0.0, c2))
    if sd <= 0:
        return (mu, 0.0, 0.0, 0.0)
    m3 = sum((x - mu) ** 3 for x in values) / n
    m4 = sum((x - mu) ** 4 for x in values) / n
    g3 = m3 / (sd ** 3)
    g4 = m4 / (sd ** 4)
    return (mu, sd, g3, g4)

def norm_cdf(x: float) -> float:
    return 0.5 * (1.0 + math.erf(x / math.sqrt(2.0)))

def probabilistic_sharpe_ratio(values: List[float], sr_benchmark: float = 0.0) -> float:
    """Probabilistic Sharpe Ratio (Bailey, López de Prado).

    PSR = Phi( (SR - SR*) * sqrt(n-1) / sqrt(1 - g3*SR + (g4-1)/4 * SR^2) )
    gdzie g3=skewness, g4=kurtosis (non-excess).
    """
    n = len(values)
    if n < 10:
        return 0.5
    mu, sd, g3, g4 = moments(values)
    if sd <= 0:
        return 0.5
    sr = mu / sd
    denom = 1.0 - (g3 * sr) + ((g4 - 1.0) / 4.0) * (sr ** 2)
    if denom <= 1e-12:
        return 0.5
    z = (sr - sr_benchmark) * math.sqrt(max(1.0, n - 1.0)) / math.sqrt(denom)
    psr = norm_cdf(z)
    return float(min(0.9999, max(0.0001, psr)))

# -------------------------
# DB read-only
# -------------------------
def sqlite_connect_ro(db_path: Path) -> sqlite3.Connection:
    uri = f"file:{db_path.as_posix()}?mode=ro"
    conn = sqlite3.connect(uri, uri=True, timeout=5)
    try:
        conn.execute("PRAGMA busy_timeout=5000;")
        conn.execute("PRAGMA query_only=ON;")
        conn.execute("PRAGMA temp_store=MEMORY;")
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
    return conn

def sqlite_fetchall_retry(conn: sqlite3.Connection, q: str, params: Tuple = (), *, tries: int = 6, base_sleep: float = 0.15):
    for i in range(tries):
        try:
            cur = conn.execute(q, params)
            return cur.fetchall()
        except sqlite3.OperationalError as e:
            msg = str(e).lower()
            if ("locked" in msg) or ("busy" in msg):
                time.sleep(base_sleep * (2 ** i))
                continue
            raise
    cur = conn.execute(q, params)
    return cur.fetchall()

def _available_columns(db_path: Path, table: str) -> List[str]:
    try:
        conn = sqlite_connect_ro(db_path)
        cols = [r[1] for r in conn.execute(f"PRAGMA table_info({table});").fetchall()]
        return [str(c) for c in cols]
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        return []
    finally:
        try:
            conn.close()
        except Exception as e:
            cg.tlog(None, "WARN", "LEARN_EXC", "conn.close failed in fetch_columns", e)

def fetch_closed_events(db_path: Path, since_iso_utc: str, limit: int = 20000) -> List[Dict[str, Any]]:
    """Rows ordered ASC by closed_ts_utc. Price-free fields only."""
    if not db_path.exists():
        return []
    cols = _available_columns(db_path, "decision_events")
    if not cols:
        return []

    base_cols = [
        "outcome_closed_ts_utc",
        "choice_A",
        "price_requests_trade",
        "outcome_pnl_net",
        "outcome_commission",
        "outcome_swap",
        "outcome_fee",
        # v3 optional context (safe, non price-like)
        "grp",
        "window_id",
        "window_phase",
        "window_group",
        "regime",
        "entry_score",
        "entry_min_score",
        "risk_entry_allowed",
        "eco_active",
        "black_swan_flag",
        "self_heal_active",
        "canary_active",
        "drift_active",
        "snapshot_block_new_entries",
        "mt5_retcode",
        "mt5_retcode_name",
        "prio",
        "time_weight",
        "score_factor",
        "group_factor",
    ]
    select_cols = [c for c in base_cols if c in cols]
    if "outcome_closed_ts_utc" not in select_cols or "choice_A" not in select_cols:
        return []

    cols_sql = ", ".join(select_cols)
    conn = sqlite_connect_ro(db_path)
    try:
        rows = sqlite_fetchall_retry(
            conn,
                        f"""
                        SELECT {cols_sql}
                        FROM decision_events
                        WHERE outcome_closed_ts_utc IS NOT NULL AND outcome_closed_ts_utc != ''
                            AND outcome_closed_ts_utc >= ?
                        ORDER BY outcome_closed_ts_utc ASC
                        LIMIT ?
                        """,
            (since_iso_utc, int(limit),),
        )
        out: List[Dict[str, Any]] = []
        for r in rows:
            row = dict(zip(select_cols, r))
            closed_ts = str(row.get("outcome_closed_ts_utc") or "")
            sym = str(row.get("choice_A") or "").strip().upper()
            if not closed_ts or not sym:
                continue
            out.append({
                "closed_ts_utc": closed_ts,
                "symbol": sym,
                "reqs_trade": int(row.get("price_requests_trade") or 0),
                "pnl_net": float(row.get("outcome_pnl_net") or 0.0),
                "commission": float(row.get("outcome_commission") or 0.0),
                "swap": float(row.get("outcome_swap") or 0.0),
                "fee": float(row.get("outcome_fee") or 0.0),
                # optional v3 context
                "grp": (str(row.get("grp") or "").strip().upper() if "grp" in select_cols else ""),
                "window_id": (str(row.get("window_id") or "").strip().upper() if "window_id" in select_cols else ""),
                "window_phase": (str(row.get("window_phase") or "").strip().upper() if "window_phase" in select_cols else ""),
                "window_group": (str(row.get("window_group") or "").strip().upper() if "window_group" in select_cols else ""),
                "regime": (str(row.get("regime") or "").strip().upper() if "regime" in select_cols else ""),
                "entry_score": (None if "entry_score" not in select_cols else (None if row.get("entry_score") is None else int(row.get("entry_score") or 0))),
                "entry_min_score": (None if "entry_min_score" not in select_cols else (None if row.get("entry_min_score") is None else int(row.get("entry_min_score") or 0))),
                "risk_entry_allowed": (None if "risk_entry_allowed" not in select_cols else int(row.get("risk_entry_allowed") or 0)),
                "eco_active": (None if "eco_active" not in select_cols else int(row.get("eco_active") or 0)),
                "black_swan_flag": (None if "black_swan_flag" not in select_cols else int(row.get("black_swan_flag") or 0)),
                "self_heal_active": (None if "self_heal_active" not in select_cols else int(row.get("self_heal_active") or 0)),
                "canary_active": (None if "canary_active" not in select_cols else int(row.get("canary_active") or 0)),
                "drift_active": (None if "drift_active" not in select_cols else int(row.get("drift_active") or 0)),
                "snapshot_block_new_entries": (None if "snapshot_block_new_entries" not in select_cols else int(row.get("snapshot_block_new_entries") or 0)),
                "mt5_retcode": (None if "mt5_retcode" not in select_cols else (None if row.get("mt5_retcode") is None else int(row.get("mt5_retcode") or 0))),
                "mt5_retcode_name": (None if "mt5_retcode_name" not in select_cols else (None if row.get("mt5_retcode_name") is None else str(row.get("mt5_retcode_name") or ""))),
                "prio": (None if "prio" not in select_cols else (None if row.get("prio") is None else float(row.get("prio") or 0.0))),
                "time_weight": (None if "time_weight" not in select_cols else (None if row.get("time_weight") is None else float(row.get("time_weight") or 0.0))),
                "score_factor": (None if "score_factor" not in select_cols else (None if row.get("score_factor") is None else float(row.get("score_factor") or 0.0))),
                "group_factor": (None if "group_factor" not in select_cols else (None if row.get("group_factor") is None else float(row.get("group_factor") or 0.0))),
            })
        return out
    finally:
        try:
            conn.close()
        except Exception as e:
            cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)

def _streak_stats(pnls: List[float]) -> Dict[str, Any]:
    max_loss = 0
    max_win = 0
    loss_runs: List[int] = []
    win_runs: List[int] = []

    cur = 0
    cur_is_loss = None
    for p in pnls:
        is_loss = (float(p) <= 0.0)
        if cur_is_loss is None or is_loss != cur_is_loss:
            if cur_is_loss is True:
                loss_runs.append(cur)
                max_loss = max(max_loss, cur)
            elif cur_is_loss is False:
                win_runs.append(cur)
                max_win = max(max_win, cur)
            cur = 1
            cur_is_loss = is_loss
        else:
            cur += 1

    if cur_is_loss is True:
        loss_runs.append(cur)
        max_loss = max(max_loss, cur)
    elif cur_is_loss is False:
        win_runs.append(cur)
        max_win = max(max_win, cur)

    def _prob_ge(runs: List[int], n: int) -> float:
        if not runs:
            return 0.0
        return float(sum(1 for x in runs if x >= n)) / float(len(runs))

    return {
        "max_loss_streak": int(max_loss),
        "max_win_streak": int(max_win),
        "loss_streak_p3": round(_prob_ge(loss_runs, 3), 6),
        "loss_streak_p5": round(_prob_ge(loss_runs, 5), 6),
        "loss_streak_p7": round(_prob_ge(loss_runs, 7), 6),
    }

def _chop_risk_bucket(edges: List[float]) -> str:
    n = len(edges)
    if n < 20:
        return "UNKNOWN"
    sign_changes = 0
    for i in range(1, n):
        if edges[i] * edges[i - 1] < 0:
            sign_changes += 1
    sign_rate = float(sign_changes) / float(max(1, n - 1))

    abs_edges = sorted(abs(float(x)) for x in edges)
    p25 = abs_edges[int(0.25 * (n - 1))] if n > 1 else 0.0
    small_frac = float(sum(1 for x in edges if abs(float(x)) <= p25)) / float(n)

    small_frac_adj = small_frac if sign_rate > 0.0 else 0.0
    chop_score = 0.6 * sign_rate + 0.4 * small_frac_adj
    if chop_score < 0.33:
        return "LOW"
    if chop_score < 0.66:
        return "MED"
    return "HIGH"

def _rank_scores(rows: List[Dict[str, Any]]) -> Dict[str, float]:
    per_sym_edges: Dict[str, List[float]] = {}
    for r in rows:
        sym = str(r.get("symbol") or "").strip().upper()
        reqs_i = int(r.get("reqs_trade") or 0)
        pnl = float(r.get("pnl_net") or 0.0)
        edge = (pnl / float(reqs_i)) if reqs_i > 0 else 0.0
        if sym:
            per_sym_edges.setdefault(sym, []).append(edge)
    scores: Dict[str, float] = {}
    for sym, edges in per_sym_edges.items():
        if not edges:
            continue
        mu = float(sum(edges) / len(edges))
        psr = probabilistic_sharpe_ratio(edges, sr_benchmark=0.0)
        scores[sym] = float(mu * psr)
    return scores

def _rank_corr(a: Dict[str, float], b: Dict[str, float]) -> Optional[float]:
    if not a or not b:
        return None
    common = [s for s in a.keys() if s in b]
    if len(common) < 5:
        return None
    a_sorted = sorted(common, key=lambda s: a.get(s, 0.0), reverse=True)
    b_sorted = sorted(common, key=lambda s: b.get(s, 0.0), reverse=True)
    rank_a = {s: i + 1 for i, s in enumerate(a_sorted)}
    rank_b = {s: i + 1 for i, s in enumerate(b_sorted)}
    n = len(common)
    d2 = sum((rank_a[s] - rank_b[s]) ** 2 for s in common)
    return 1.0 - (6.0 * d2) / float(n * (n * n - 1))

def _score_delta_mean(a: Dict[str, float], b: Dict[str, float]) -> Optional[float]:
    if not a or not b:
        return None
    common = [s for s in a.keys() if s in b]
    if len(common) < 5:
        return None
    deltas = [float(a.get(s, 0.0)) - float(b.get(s, 0.0)) for s in common]
    return float(sum(deltas) / len(deltas))

def _walk_forward(rows: List[Dict[str, Any]], parts: int = 3) -> List[Dict[str, Any]]:
    if len(rows) < 30:
        return []
    rows_sorted = sorted(rows, key=lambda r: str(r.get("closed_ts_utc") or ""))
    n = len(rows_sorted)
    step = max(1, n // parts)
    out: List[Dict[str, Any]] = []
    for i in range(parts - 1):
        train = rows_sorted[: (i + 1) * step]
        test = rows_sorted[(i + 1) * step : (i + 2) * step]
        if len(train) < 10 or len(test) < 10:
            continue
        scores = _rank_scores(train)
        top = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:3]
        top_syms = [s for s, _ in top]
        test_pnls = [float(r.get("pnl_net") or 0.0) for r in test if r.get("symbol") in top_syms]
        mean_test = float(sum(test_pnls) / len(test_pnls)) if test_pnls else 0.0
        out.append({
            "fold": i + 1,
            "train_n": int(len(train)),
            "test_n": int(len(test)),
            "top_syms": top_syms,
            "test_mean_pnl": round(mean_test, 8),
        })
    return out

def _walk_forward_topk(rows: List[Dict[str, Any]], parts: int = 3, k: int = 3) -> List[List[str]]:
    if len(rows) < 30:
        return []
    rows_sorted = sorted(rows, key=lambda r: str(r.get("closed_ts_utc") or ""))
    n = len(rows_sorted)
    step = max(1, n // parts)
    out: List[List[str]] = []
    for i in range(parts - 1):
        train = rows_sorted[: (i + 1) * step]
        if len(train) < 10:
            continue
        scores = _rank_scores(train)
        top = sorted(scores.items(), key=lambda x: x[1], reverse=True)[:k]
        top_syms = [s for s, _ in top]
        out.append(top_syms)
    return out

def _topk_churn(topk_list: List[List[str]]) -> Optional[float]:
    if len(topk_list) < 2:
        return None
    overlaps = []
    for i in range(1, len(topk_list)):
        prev = set(topk_list[i - 1])
        curr = set(topk_list[i])
        denom = max(1, len(prev.union(curr)))
        overlaps.append(float(len(prev.intersection(curr))) / float(denom))
    return float(sum(overlaps) / len(overlaps)) if overlaps else None

def _topk_hit_rates(topk_list: List[List[str]]) -> List[Dict[str, Any]]:
    if not topk_list:
        return []
    counts: Dict[str, int] = {}
    for topk in topk_list:
        for s in topk:
            counts[s] = counts.get(s, 0) + 1
    folds = len(topk_list)
    out = []
    for s, c in counts.items():
        out.append({"symbol": s, "hit_rate": float(c) / float(folds), "folds": folds})
    out.sort(key=lambda d: (float(d.get("hit_rate", 0.0)), d.get("symbol", "")), reverse=True)
    return out


def _anti_overfit_light(
    *,
    n_total: int,
    rank_corr_half: Optional[float],
    topk_churn: Optional[float],
    loss_streak_p5: float,
    stress_pnl_mean_2x: float,
) -> Tuple[str, List[str]]:
    """
    Lightweight anti-overfit gate from stability proxies.

    GREEN: stable ranks / acceptable churn / no severe stress degradation
    YELLOW: single warning
    RED: multiple warnings or very low sample
    """
    reasons: List[str] = []
    n = int(max(0, n_total))
    if n < 40:
        return ("RED", ["N_TOO_LOW"])
    if n < 80:
        reasons.append("N_LOW")

    if rank_corr_half is not None and float(rank_corr_half) < 0.05:
        reasons.append("RANK_UNSTABLE")
    if topk_churn is not None and float(topk_churn) < 0.25:
        reasons.append("TOPK_CHURN_HIGH")
    if float(loss_streak_p5) > 0.35:
        reasons.append("LOSS_CLUSTER")
    if float(stress_pnl_mean_2x) < 0.0:
        reasons.append("COST_STRESS_NEG")

    if len(reasons) >= 2:
        return ("RED", reasons)
    if len(reasons) == 1:
        return ("YELLOW", reasons)
    return ("GREEN", ["STABLE"])

def build_advice(rows: List[Dict[str, Any]], window_days: int) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    per_sym_edges: Dict[str, List[float]] = {}
    per_sym_pnls: Dict[str, List[float]] = {}
    edges_all: List[float] = []
    pnls_all: List[float] = []
    reqs_all: List[int] = []
    costs_all: List[float] = []
    ts_all: List[str] = []

    for r in rows:
        sym = str(r.get("symbol") or "").strip().upper()
        reqs_i = int(r.get("reqs_trade") or 0)
        pnl = float(r.get("pnl_net") or 0.0)
        edge = (pnl / float(reqs_i)) if reqs_i > 0 else 0.0
        cost = float(r.get("commission") or 0.0) + float(r.get("swap") or 0.0) + float(r.get("fee") or 0.0)
        per_sym_edges.setdefault(sym, []).append(edge)
        per_sym_pnls.setdefault(sym, []).append(float(pnl))
        edges_all.append(edge)
        pnls_all.append(float(pnl))
        reqs_all.append(reqs_i)
        costs_all.append(cost)
        ts_all.append(str(r.get("closed_ts_utc") or ""))

    mean_edge = float(sum(edges_all) / len(edges_all)) if edges_all else 0.0
    tail = float(es95(edges_all)) if edges_all else 0.0
    mdd = float(max_drawdown(pnls_all)) if pnls_all else 0.0

    items: List[Dict[str, Any]] = []
    report_syms: List[Dict[str, Any]] = []
    for sym, edges in per_sym_edges.items():
        pnls = per_sym_pnls.get(sym, [])
        n = int(len(edges))
        if n <= 0:
            continue
        mu = float(sum(edges) / n)
        t = float(es95(edges))
        dd = float(max_drawdown(pnls)) if pnls else 0.0
        psr = probabilistic_sharpe_ratio(edges, sr_benchmark=0.0)
        score = mu * psr
        items.append({
            "symbol": sym,
            "score": round(score, 12),
            "es95": round(t, 12),
            "mdd": round(dd, 6),
            "n": n,
        })
        report_syms.append({
            "symbol": sym,
            "n": n,
            "mean_edge": mu,
            "tail": t,
            "dd": dd,
            "psr": psr,
            "score": score,
        })

    # lexicographic sort: score, es95, -mdd, n
    items.sort(key=lambda d: (float(d.get("score", 0.0)), float(d.get("es95", 0.0)), -float(d.get("mdd", 0.0)), int(d.get("n", 0))), reverse=True)
    top = items[:10]

    now = _now_utc().replace(microsecond=0)
    meta_advice = {
        "schema": "oanda_mt5.learner_advice.v1",
        "ts_utc": now.isoformat().replace("+00:00","Z"),
        "ttl_sec": int(3600),
        "window_days": int(window_days),
        "metrics": {
            "n": int(len(edges_all)),
            "mean_edge_fuel": round(mean_edge, 12),
            "es95": round(tail, 12),
            "mdd": round(mdd, 6),
        },
        "ranks": top,
        "notes": [
            "source=decision_events",
            "method=psr_weighted",
            "mode=offline",
        ],
    }

    streaks = _streak_stats(pnls_all)
    chop_bucket = _chop_risk_bucket(edges_all)
    trades_per_day = (float(len(edges_all)) / float(max(1, window_days)))
    costs_mean = float(sum(costs_all) / len(costs_all)) if costs_all else 0.0
    stress_pnl_mean = 0.0
    stress_pnl_mean_2x = 0.0
    if pnls_all:
        stress_pnls = [float(p) - abs(float(c)) for p, c in zip(pnls_all, costs_all)]
        stress_pnls_2x = [float(p) - 2.0 * abs(float(c)) for p, c in zip(pnls_all, costs_all)]
        stress_pnl_mean = float(sum(stress_pnls) / len(stress_pnls))
        stress_pnl_mean_2x = float(sum(stress_pnls_2x) / len(stress_pnls_2x))
    cost_pressure = 0.0
    if pnls_all:
        ratios = []
        for p, c in zip(pnls_all, costs_all):
            denom = max(1e-9, abs(float(p)))
            ratios.append(abs(float(c)) / denom)
        cost_pressure = float(sum(ratios) / len(ratios))
    reqs_mean = float(sum(reqs_all) / len(reqs_all)) if reqs_all else 0.0

    wf = _walk_forward(rows, parts=3)
    wf_topk = _walk_forward_topk(rows, parts=3, k=3)
    topk_churn = _topk_churn(wf_topk)
    topk_hits = _topk_hit_rates(wf_topk)
    wf_corr = None
    score_delta = None
    if len(rows) >= 20:
        r1 = _rank_scores(rows[: max(1, len(rows) // 2)])
        r2 = _rank_scores(rows[max(1, len(rows) // 2) :])
        wf_corr = _rank_corr(r1, r2)
        score_delta = _score_delta_mean(r1, r2)

    qa_light, qa_reasons = _anti_overfit_light(
        n_total=int(len(edges_all)),
        rank_corr_half=wf_corr,
        topk_churn=topk_churn,
        loss_streak_p5=float(streaks.get("loss_streak_p5", 0.0)),
        stress_pnl_mean_2x=float(stress_pnl_mean_2x),
    )
    meta_advice["qa_light"] = str(qa_light)

    expanded_report = {
        "ts_utc": meta_advice["ts_utc"],
        "window_days": int(window_days),
        "n_total": int(len(edges_all)),
        "trades_per_day": round(trades_per_day, 6),
        "reqs_trade_avg": round(reqs_mean, 6),
        "txcost_mean": round(costs_mean, 8),
        "cost_pressure": round(cost_pressure, 6),
        "stress_pnl_mean": round(stress_pnl_mean, 8),
        "stress_pnl_mean_2x": round(stress_pnl_mean_2x, 8),
        "tail_es95": round(tail, 12),
        "loss_streak_max": int(streaks.get("max_loss_streak", 0)),
        "loss_streak_p3": float(streaks.get("loss_streak_p3", 0.0)),
        "loss_streak_p5": float(streaks.get("loss_streak_p5", 0.0)),
        "loss_streak_p7": float(streaks.get("loss_streak_p7", 0.0)),
        "chop_risk_bucket": chop_bucket,
        "rank_corr_half": None if wf_corr is None else round(float(wf_corr), 6),
        "score_delta_half": None if score_delta is None else round(float(score_delta), 8),
        "anti_overfit_light": str(qa_light),
        "anti_overfit_reasons": [str(x) for x in qa_reasons],
        "walk_forward": wf,
        "topk_churn": None if topk_churn is None else round(float(topk_churn), 6),
        "topk_hit_rates": topk_hits,
        "syms": sorted(report_syms, key=lambda d: float(d.get("score", 0.0)), reverse=True)[:200],
    }
    return (meta_advice, expanded_report)


# -------------------------
# Stage 1: policy suggestions + readiness milestones (deterministic, no ML)
# -------------------------
def _stage1_eval_segment(
    rows_all: List[Dict[str, Any]],
    idxs: List[int],
    *,
    window_days: int,
    n_min: int,
    n_min_subset: int,
    canary_mult: float,
) -> Dict[str, Any]:
    n_cur = int(len(idxs))
    if n_cur < int(max(1, n_min)):
        return {
            "n_closed": int(n_cur),
            "qa_light": "RED",
            "qa_reasons": ["N_TOO_LOW"],
            "ready_shadow": 0,
            "ready_canary": 0,
            "metrics": {},
            "suggest": {"ok": False, "reason": "N_TOO_LOW"},
        }
    rows = [rows_all[i] for i in idxs]
    meta_advice, rep = build_advice(rows, window_days=int(window_days))
    qa = str(meta_advice.get("qa_light") or "UNKNOWN").strip().upper()
    qa_reasons = rep.get("anti_overfit_reasons") if isinstance(rep.get("anti_overfit_reasons"), list) else []
    if not isinstance(qa_reasons, list):
        qa_reasons = []
    ready_shadow = 1 if qa in {"GREEN", "YELLOW"} else 0
    canary_min_n = int(max(int(n_min), int(math.ceil(float(n_min) * float(max(1.0, canary_mult))))))
    stress2 = float(rep.get("stress_pnl_mean_2x") or 0.0)
    ready_canary = 1 if (qa == "GREEN" and n_cur >= canary_min_n and stress2 >= 0.0) else 0
    suggest = _stage1_suggest_entry_threshold(rows, n_min_subset=int(n_min_subset))
    # keep report minimal (LOGS only, no META)
    metrics = {
        "n_total": int(rep.get("n_total") or 0),
        "trades_per_day": float(rep.get("trades_per_day") or 0.0),
        "reqs_trade_avg": float(rep.get("reqs_trade_avg") or 0.0),
        "cost_pressure": float(rep.get("cost_pressure") or 0.0),
        "stress_pnl_mean_2x": float(stress2),
        "tail_es95": float(rep.get("tail_es95") or 0.0),
        "loss_streak_p5": float(rep.get("loss_streak_p5") or 0.0),
        "rank_corr_half": rep.get("rank_corr_half"),
        "topk_churn": rep.get("topk_churn"),
    }
    return {
        "n_closed": int(n_cur),
        "qa_light": qa,
        "qa_reasons": [str(x) for x in qa_reasons][:16],
        "ready_shadow": int(ready_shadow),
        "ready_canary": int(ready_canary),
        "metrics": metrics,
        "suggest": suggest,
    }


def _stage1_update_outputs(
    *,
    rows: List[Dict[str, Any]],
    window_days: int,
    logs_dir: Path,
) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    """
    Returns (suggestions_obj, milestones_obj). Writes are performed by caller.
    """
    if not _env_bool("LEARNER_STAGE1_ENABLED", True):
        return (None, None)

    n_min_grp = _env_int("LEARNER_STAGE1_N_MIN_GRP", 80, vmin=10, vmax=1_000_000)
    n_min_sym = _env_int("LEARNER_STAGE1_N_MIN_SYM", 200, vmin=10, vmax=1_000_000)
    n_min_subset = _env_int("LEARNER_STAGE1_SUBSET_N_MIN", 30, vmin=5, vmax=1_000_000)
    growth = _env_float("LEARNER_STAGE1_GROWTH_FACTOR", 1.30, vmin=1.05, vmax=2.00)
    canary_mult = _env_float("LEARNER_STAGE1_CANARY_N_MULT", 1.50, vmin=1.00, vmax=5.00)

    ms_path = logs_dir / STAGE1_MILESTONES_FILE
    ms = _stage1_load_milestones(ms_path)
    seg_state = ms.get("segments")
    if not isinstance(seg_state, dict):
        seg_state = {}
        ms["segments"] = seg_state

    now = _now_utc().replace(microsecond=0).isoformat().replace("+00:00", "Z")
    group_map, sym_map = _stage1_partition_segments(rows)

    segments: List[Tuple[str, Dict[str, Any]]] = []
    for sid, info in group_map.items():
        segments.append((sid, info))
    for sid, info in sym_map.items():
        segments.append((sid, info))
    segments.sort(key=lambda x: x[0])

    out_segments: List[Dict[str, Any]] = []
    ready_shadow_ids: List[str] = []
    ready_canary_ids: List[str] = []
    updated_cnt = 0

    for seg_id, info in segments:
        meta = info.get("meta") if isinstance(info.get("meta"), dict) else {}
        idxs = info.get("idxs") if isinstance(info.get("idxs"), list) else []
        kind = str(meta.get("kind") or "UNKNOWN")
        n_cur = int(len(idxs))
        n_min = int(n_min_grp) if kind == "GROUP_WINDOW_PHASE" else int(n_min_sym)

        prev = seg_state.get(seg_id) if isinstance(seg_state.get(seg_id), dict) else None
        prev_level = str(prev.get("level") or "") if isinstance(prev, dict) else ""
        n_next_eval = int(prev.get("n_next_eval") or n_min) if isinstance(prev, dict) else int(n_min)
        due = _stage1_due(n_cur, n_next_eval)

        if due:
            eval_out = _stage1_eval_segment(
                rows,
                idxs,
                window_days=int(window_days),
                n_min=int(n_min),
                n_min_subset=int(n_min_subset),
                canary_mult=float(canary_mult),
            )
            level = "NOT_READY"
            if int(eval_out.get("ready_canary") or 0) == 1:
                level = "READY_CANARY"
            elif int(eval_out.get("ready_shadow") or 0) == 1:
                level = "READY_SHADOW"
            if eval_out.get("qa_light") == "RED" and n_cur < n_min:
                level = "NOT_READY_TOO_LOW"

            n_next = _stage1_next_eval_n(n_cur, n_min=int(n_min), growth=float(growth))
            st_new = {
                "kind": kind,
                "meta": meta,
                "level": str(level),
                "n_last_eval": int(n_cur),
                "n_next_eval": int(n_next),
                "last_eval_ts_utc": now,
                "qa_light": str(eval_out.get("qa_light") or "UNKNOWN"),
                "qa_reasons": eval_out.get("qa_reasons") if isinstance(eval_out.get("qa_reasons"), list) else [],
                "ready_shadow": int(eval_out.get("ready_shadow") or 0),
                "ready_canary": int(eval_out.get("ready_canary") or 0),
                "metrics": eval_out.get("metrics") if isinstance(eval_out.get("metrics"), dict) else {},
                "suggest": eval_out.get("suggest") if isinstance(eval_out.get("suggest"), dict) else {},
            }
            seg_state[seg_id] = st_new
            updated_cnt += 1

            if level.startswith("READY") and level != prev_level:
                logging.info(
                    "STAGE1_READY segment=%s level=%s prev=%s n=%s",
                    seg_id,
                    level,
                    prev_level or "NONE",
                    int(n_cur),
                )
        else:
            # Cache: ensure we keep at least minimal state for visibility.
            if prev is None:
                seg_state[seg_id] = {
                    "kind": kind,
                    "meta": meta,
                    "level": "NOT_READY_TOO_LOW" if n_cur < n_min else "NOT_READY",
                    "n_last_eval": 0,
                    "n_next_eval": int(_stage1_next_eval_n(n_cur, n_min=int(n_min), growth=float(growth))),
                    "last_eval_ts_utc": "",
                    "qa_light": "UNKNOWN",
                    "qa_reasons": [],
                    "ready_shadow": 0,
                    "ready_canary": 0,
                    "metrics": {},
                    "suggest": {"ok": False, "reason": "NO_EVAL_YET"},
                }

        st = seg_state.get(seg_id) if isinstance(seg_state.get(seg_id), dict) else {}
        level = str(st.get("level") or "")
        if str(level).startswith("READY_SHADOW"):
            ready_shadow_ids.append(seg_id)
        if str(level).startswith("READY_CANARY"):
            ready_canary_ids.append(seg_id)
        out_segments.append(
            {
                "segment": str(seg_id),
                "kind": str(kind),
                "n_closed": int(n_cur),
                "due": int(1 if due else 0),
                "level": str(level),
                "n_next_eval": int(st.get("n_next_eval") or n_min),
                "qa_light": str(st.get("qa_light") or "UNKNOWN"),
                "ready_shadow": int(st.get("ready_shadow") or 0),
                "ready_canary": int(st.get("ready_canary") or 0),
                "metrics": st.get("metrics") if isinstance(st.get("metrics"), dict) else {},
                "suggest": st.get("suggest") if isinstance(st.get("suggest"), dict) else {},
            }
        )

    ms["schema"] = STAGE1_MILESTONES_SCHEMA
    ms["updated_ts_utc"] = now

    suggestions = {
        "schema": STAGE1_SUGGESTIONS_SCHEMA,
        "ts_utc": now,
        "ttl_sec": int(3600),
        "window_days": int(window_days),
        "n_total_closed": int(len(rows)),
        "params": {
            "n_min_grp": int(n_min_grp),
            "n_min_sym": int(n_min_sym),
            "growth_factor": float(growth),
            "subset_n_min": int(n_min_subset),
            "canary_n_mult": float(canary_mult),
        },
        "summary": {
            "segments_total": int(len(out_segments)),
            "segments_updated": int(updated_cnt),
            "ready_shadow_n": int(len(ready_shadow_ids)),
            "ready_canary_n": int(len(ready_canary_ids)),
        },
        "segments": out_segments,
    }
    return (suggestions, ms)

def run_once(root: Path) -> int:
    dirs = ensure_dirs(root)
    meta_dir = dirs["META"]
    db_dir = dirs["DB"]
    logs_dir = dirs["LOGS"]

    base_window_days = _env_int("LEARNER_WINDOW_DAYS", 180, vmin=1, vmax=3650)
    base_row_limit = _env_int("LEARNER_ROW_LIMIT", 20000, vmin=1, vmax=1_000_000)

    guard_enabled = str(os.environ.get("LEARNER_RESOURCE_GUARD", "1")).strip() != "0"
    load_mode = "normal"
    load_reason = "guard_off"
    cpu_pct: Optional[float] = None
    mem_available_mb: Optional[float] = None
    window_days = int(base_window_days)
    row_limit = int(base_row_limit)

    if guard_enabled:
        cpu_sample_sec = _env_float("LEARNER_CPU_SAMPLE_SEC", 0.15, vmin=0.05, vmax=0.50)
        cpu_soft_max_pct = _env_float("LEARNER_CPU_SOFT_MAX_PCT", 70.0, vmin=5.0, vmax=99.0)
        cpu_hard_max_pct = _env_float("LEARNER_CPU_HARD_MAX_PCT", 85.0, vmin=10.0, vmax=100.0)
        mem_min_mb = _env_float("LEARNER_MEM_MIN_MB", 1500.0, vmin=128.0, vmax=131072.0)
        light_window_days = _env_int("LEARNER_LIGHT_WINDOW_DAYS", 90, vmin=1, vmax=3650)
        light_row_limit = _env_int("LEARNER_LIGHT_ROW_LIMIT", 5000, vmin=1, vmax=1_000_000)

        cpu_pct = read_cpu_percent(sample_sec=cpu_sample_sec)
        mem_available_mb = read_mem_available_mb()
        load_mode, load_reason = decide_resource_mode(
            cpu_pct,
            mem_available_mb,
            cpu_soft_max_pct=cpu_soft_max_pct,
            cpu_hard_max_pct=cpu_hard_max_pct,
            mem_min_mb=mem_min_mb,
        )
        window_days, row_limit = effective_scan_params(
            base_window_days=base_window_days,
            base_row_limit=base_row_limit,
            load_mode=load_mode,
            light_window_days=light_window_days,
            light_row_limit=light_row_limit,
        )

        if load_mode == "skip":
            logging.warning(
                "RESOURCE_GUARD_SKIP | "
                f"reason={load_reason} cpu_pct={None if cpu_pct is None else round(cpu_pct, 2)} "
                f"mem_available_mb={None if mem_available_mb is None else round(mem_available_mb, 1)}"
            )
            return 0
        if load_mode == "light":
            logging.info(
                "RESOURCE_GUARD_LIGHT | "
                f"reason={load_reason} cpu_pct={None if cpu_pct is None else round(cpu_pct, 2)} "
                f"mem_available_mb={None if mem_available_mb is None else round(mem_available_mb, 1)} "
                f"window_days={window_days} row_limit={row_limit}"
            )

    now = _now_utc()
    since = (now - dt.timedelta(days=max(1, window_days))).replace(microsecond=0)
    since_iso = since.isoformat().replace("+00:00","Z")

    rows = fetch_closed_events(db_dir / "decision_events.sqlite", since_iso_utc=since_iso, limit=row_limit)
    meta_advice, report = build_advice(rows, window_days=window_days)
    try:
        meta_advice.setdefault("notes", []).append(f"load_mode={load_mode}")
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
    report["resource_guard"] = {
        "enabled": bool(guard_enabled),
        "mode": str(load_mode),
        "reason": str(load_reason),
        "cpu_pct": None if cpu_pct is None else round(float(cpu_pct), 2),
        "mem_available_mb": None if mem_available_mb is None else round(float(mem_available_mb), 1),
        "window_days_effective": int(window_days),
        "row_limit_effective": int(row_limit),
    }

    # Optional handoff from deterministic offline replay analytics.
    # This stage is strictly offline and never touches LIVE execution loop.
    ext_max_age_sec = _env_int("LEARNER_EXT_REPLAY_MAX_AGE_SEC", 7200, vmin=60, vmax=86400)
    ext_weight = _env_float("LEARNER_EXT_REPLAY_WEIGHT", 0.0, vmin=0.0, vmax=1.0)
    ext_summary = load_external_replay_summary(meta_dir, max_age_sec=ext_max_age_sec)
    if isinstance(ext_summary, dict):
        ext_metrics = ext_summary.get("metrics") if isinstance(ext_summary.get("metrics"), dict) else {}
        ext_scores = ext_summary.get("symbol_scores") if isinstance(ext_summary.get("symbol_scores"), list) else []
        touched = apply_external_replay_blend(meta_advice, ext_summary, weight=float(ext_weight))
        report["external_replay"] = {
            "present": True,
            "schema": str(ext_summary.get("schema") or ""),
            "ts_utc": str(ext_summary.get("ts_utc") or ""),
            "weight": float(ext_weight),
            "blend_applied": bool(touched > 0),
            "blend_touched": int(touched),
            "n_total": int(ext_metrics.get("n_total") or 0),
            "trades_per_day": float(ext_metrics.get("trades_per_day") or 0.0),
            "cost_pressure": float(ext_metrics.get("cost_pressure") or 0.0),
            "symbol_scores_n": int(len(ext_scores)),
        }
        try:
            meta_advice.setdefault("notes", []).append("external_replay=present")
            if int(touched) > 0:
                meta_advice.setdefault("notes", []).append("external_replay_blend=on")
        except Exception as e:
            cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
    else:
        report["external_replay"] = {
            "present": False,
            "reason": "missing_or_stale_summary",
            "max_age_sec": int(ext_max_age_sec),
            "weight": float(ext_weight),
        }

    # Stage 1: readiness + policy suggestions (LOGS only; no direct execution impact).
    try:
        stage1_sug, stage1_ms = _stage1_update_outputs(rows=rows, window_days=int(window_days), logs_dir=logs_dir)
        if isinstance(stage1_sug, dict):
            atomic_write_json(logs_dir / STAGE1_SUGGESTIONS_FILE, stage1_sug)
            report["policy_stage_one"] = {
                "enabled": True,
                "schema": str(stage1_sug.get("schema") or ""),
                "summary": stage1_sug.get("summary") if isinstance(stage1_sug.get("summary"), dict) else {},
                "params": stage1_sug.get("params") if isinstance(stage1_sug.get("params"), dict) else {},
                "suggestions_file": str((logs_dir / STAGE1_SUGGESTIONS_FILE).name),
                "milestones_file": str(STAGE1_MILESTONES_FILE),
            }
            try:
                meta_advice.setdefault("notes", []).append("policy_stage_one=see_logs")
                # Minimal, human-friendly readiness signal for next steps (strings only; META guards-safe).
                segs = stage1_sug.get("segments") if isinstance(stage1_sug.get("segments"), list) else []
                ready = []
                for s in segs:
                    if not isinstance(s, dict):
                        continue
                    lvl = str(s.get("level") or "").strip().upper()
                    if lvl in {"READY_SHADOW", "READY_CANARY"}:
                        sid = str(s.get("segment") or "").strip()
                        if sid:
                            ready.append(f"{lvl}:{sid}")
                    if len(ready) >= 12:
                        break
                if ready:
                    meta_advice["stage1_ready"] = ready
                    meta_advice.setdefault("notes", []).append(f"stage1_ready_n={len(ready)}")
            except Exception as e:
                cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
        else:
            report["policy_stage_one"] = {"enabled": False, "reason": "disabled_or_missing"}
        if isinstance(stage1_ms, dict):
            atomic_write_json(logs_dir / STAGE1_MILESTONES_FILE, stage1_ms)
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "stage1_outputs_failed", e)
        report["policy_stage_one"] = {"enabled": False, "reason": f"stage1_exception:{type(e).__name__}"}

    # Hard gates for META output
    guard_obj_no_price_like(meta_advice)
    guard_obj_limits(meta_advice)

    atomic_write_json(meta_dir / "learner_advice.json", meta_advice)
    atomic_write_json(logs_dir / "learner_offline_report.json", report)

    # research-only report (no META/RUN). Always safe to skip on failure.
    try:
        ts = meta_advice.get("ts_utc", "").replace(":", "").replace("-", "")
        if ts:
            log_path = logs_dir / f"TRAINING_RESEARCH_{ts}.json"
            atomic_write_json(log_path, report)
        evid_dir = os.environ.get("TRAINING_EVID_DIR", "").strip()
        if evid_dir:
            evid = Path(evid_dir)
            evid.mkdir(parents=True, exist_ok=True)
            md = [
                "# TRAINING_QUALITY_REPORT",
                f"EVID_DIR: {evid}",
                "",
                f"n_total={report.get('n_total')}",
                f"trades_per_day={report.get('trades_per_day')}",
                f"loss_streak_max={report.get('loss_streak_max')}",
                f"loss_streak_p3={report.get('loss_streak_p3')}",
                f"loss_streak_p5={report.get('loss_streak_p5')}",
                f"loss_streak_p7={report.get('loss_streak_p7')}",
                f"txcost_mean={report.get('txcost_mean')}",
                f"cost_pressure={report.get('cost_pressure')}",
                f"stress_pnl_mean={report.get('stress_pnl_mean')}",
                f"stress_pnl_mean_2x={report.get('stress_pnl_mean_2x')}",
                f"chop_risk_bucket={report.get('chop_risk_bucket')}",
                f"rank_corr_half={report.get('rank_corr_half')}",
                f"score_delta_half={report.get('score_delta_half')}",
                f"topk_churn={report.get('topk_churn')}",
                "",
                "walk_forward:",
            ]
            for wf in (report.get("walk_forward") or []):
                md.append(f"- fold={wf.get('fold')} train_n={wf.get('train_n')} test_n={wf.get('test_n')} test_mean_pnl={wf.get('test_mean_pnl')}")
            (evid / "TRAINING_QUALITY_REPORT.md").write_text("\n".join(md) + "\n", encoding="utf-8")
    except Exception as e:
        cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)

    logging.info(f"RUN_ONCE | rows={len(rows)} window_days={window_days} syms={len(report.get('syms') or [])}")
    return 0

def main() -> None:
    root = runtime_root()
    ensure_dirs(root)
    setup_logging(root)
    mode = (sys.argv[1].strip().lower() if len(sys.argv) >= 2 else "once")
    if mode in {"-h", "--help", "help"}:
        print("Usage: python BIN/learner_offline.py [once|loop] [interval_sec]")
        sys.exit(0)
    interval = int(float(sys.argv[2])) if len(sys.argv) >= 3 else 3600
    interval = max(30, interval)
    if mode == "once":
        sys.exit(run_once(root))
    while True:
        try:
            run_once(root)
        except Exception as e:
            cg.tlog(None, "WARN", "LEARN_EXC", "nonfatal exception swallowed", e)
            logging.exception(f"LOOP_ERR {type(e).__name__}: {e}")
        time.sleep(interval)

if __name__ == "__main__":
    main()
