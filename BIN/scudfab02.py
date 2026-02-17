# -*- coding: utf-8 -*-
"""
SCUD-FAB02 — Monitor lampki + Shadow-B + online research (PRICE-FREE OUTPUT)

Runtime root: C:\\OANDA_MT5_SYSTEM (hard; override forbidden)
USB is NOT used for runtime. USB may exist only for key handling by SafetyBot.

Reads (local):
- META\\market_snapshot.json
- DB\\decision_events.sqlite
- DB\\m5_bars.sqlite (optional)
- META\\learner_advice.json (optional offline stats)

Writes (local, PRICE-FREE keys & values):
- META\\scout_advice.json   (TTL 900s)
- META\\verdict.json        (TTL 48h)
- META\\scout_shadowb.jsonl (append-only)
- META\\research_signals.json (append-only snapshot file)

Network:
- Allowed only for non-price research (RSS). Output is hashed & scrubbed.
"""
from __future__ import annotations

import os, sys, json, time, random, hashlib, logging, sqlite3, shutil
import concurrent.futures as cf
import datetime as dt
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
try:
    from . import common_guards as cg
    from . import common_contract as cc
except Exception:  # pragma: no cover
    import common_guards as cg
    import common_contract as cc

import subprocess
import re
UTC = dt.timezone.utc

DETERMINISTIC_MODE = os.environ.get("OFFLINE_DETERMINISTIC", "").strip() == "1"
ALLOW_RSS_RESEARCH = os.environ.get("SCUD_ALLOW_RSS", "").strip() == "1"
if DETERMINISTIC_MODE:
    random.seed(0)

def _now_utc() -> dt.datetime:
    if DETERMINISTIC_MODE:
        return dt.datetime(1970, 1, 1, tzinfo=UTC)
    return dt.datetime.now(tz=UTC)

try:
    from .runtime_root import get_runtime_root
except Exception:
    from runtime_root import get_runtime_root

MAX_JSONL_LINE_LEN = 2048  # hard limit for a single JSONL line (P0/P1 gate)
JSONL_LOCK_TIMEOUT_S = 3.0
LOCK_ACQUIRE_MAX_SECONDS = 5.0

MAX_NUMERIC_TOKENS = 50
MAX_NUMERIC_LIST_LEN = 50

MIN_SAMPLE_N = 50  # minimum sample size for stable stats / tie-break
JSON_READ_RETRIES = 5
JSON_READ_RETRY_SLEEP_S = 0.04
ATOMIC_REPLACE_RETRIES = 6
ATOMIC_REPLACE_RETRY_SLEEP_S = 0.05

# Cached stats for fast tiebreak responses
LAST_RANKS: List[Dict[str, Any]] = []
LAST_VERDICT_LIGHT = "INSUFFICIENT_DATA"
LAST_METRICS_N = 0

def parse_ts_utc(s: str) -> Optional[dt.datetime]:
    """Parse ISO timestamp in UTC. Accepts 'Z' suffix or '+00:00'."""
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
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return None

def _read_json_file_retry(path: Path, *, retries: int = JSON_READ_RETRIES, sleep_s: float = JSON_READ_RETRY_SLEEP_S) -> Optional[Dict[str, Any]]:
    """Best-effort JSON reader for files concurrently written by other processes."""
    attempts = max(1, int(retries))
    for i in range(attempts):
        try:
            raw = path.read_text(encoding='utf-8', errors='ignore')
            raw_s = str(raw or "").strip()
            if not raw_s:
                return None
            obj = json.loads(raw_s)
            if isinstance(obj, dict):
                return obj
            return None
        except json.JSONDecodeError:
            if i + 1 >= attempts:
                return None
            time.sleep(float(sleep_s))
            continue
        except PermissionError:
            if i + 1 >= attempts:
                return None
            time.sleep(float(sleep_s))
            continue
        except OSError:
            if i + 1 >= attempts:
                return None
            time.sleep(float(sleep_s))
            continue
    return None

def read_learner_advice(meta_dir: Path) -> Optional[Dict[str, Any]]:
    """Read optional offline learner advice from META/learner_advice.json.

    Fail-open: any error => None.
    Must be fresh (ts_utc + ttl_sec).
    """
    p = meta_dir / 'learner_advice.json'
    if not p.exists():
        return None
    try:
        obj = _read_json_file_retry(p)
        if obj is None:
            return None
        if not isinstance(obj, dict):
            return None
        guard_obj_no_price_like(obj)
        guard_obj_limits(obj)

        ts = parse_ts_utc(str(obj.get('ts_utc') or ''))
        ttl = int(obj.get('ttl_sec') or 0)
        if not ts or ttl <= 0:
            return None
        now = _now_utc()
        if (now - ts).total_seconds() > float(ttl):
            return None

        ranks = obj.get('ranks')
        metrics = obj.get('metrics')
        if not isinstance(ranks, list) or not isinstance(metrics, dict):
            return None
        return {
            'metrics': {
                'n': int(metrics.get('n') or 0),
                'mean_edge_fuel': float(metrics.get('mean_edge_fuel') or 0.0),
                'es95': float(metrics.get('es95') or 0.0),
                'mdd': float(metrics.get('mdd') or 0.0),
            },
            'ranks': ranks,
            'qa_light': str(obj.get('qa_light') or "").strip().upper(),
            'source': 'offline_learner',
        }
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return None

def _count_numeric_tokens(obj) -> int:
    """Count numeric tokens in nested JSON-like object."""
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
        # list of numerics
        if len(obj) > limit and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            return True
        return any(_has_numeric_list_over_limit(v, limit) for v in obj)
    if isinstance(obj, dict):
        return any(_has_numeric_list_over_limit(v, limit) for v in obj.values())
    return False

def guard_obj_limits(obj) -> None:
    """Enforce Rulebook limits: >50 numeric tokens total OR any numeric list >50 => FAIL (raise)."""
    if _has_numeric_list_over_limit(obj, MAX_NUMERIC_LIST_LEN):
        raise ValueError("P0_LIMIT_NUMERIC_LIST_GT_50")
    n = _count_numeric_tokens(obj)
    if n > MAX_NUMERIC_TOKENS:
        raise ValueError(f"P0_LIMIT_NUMERIC_TOKENS_GT_50:{n}")
# -------------------------
# Paths / Lock
# -------------------------
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

def pid_is_running(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            cp = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"],
                               capture_output=True, text=True, check=False, timeout=3)
            return str(pid) in (cp.stdout or "")
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError as e:
        # Conservative: if we cannot probe the PID, treat as running.
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return True
    except Exception as e:
        # Conservative: unknown OS errors => treat as running (avoid stale-lock false positives).
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return True

def pid_exists(pid: int) -> bool:
    """Backward-compatible alias used by lock cleanup."""
    return pid_is_running(pid)

def acquire_lock(lock_path: Path, *, timeout_s: float = LOCK_ACQUIRE_MAX_SECONDS) -> None:
    """Exclusive lock with stale-PID cleanup. Hard timeout: timeout_s."""
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    my_pid = os.getpid()
    my_pid_txt = str(my_pid)
    t0 = time.time()
    while (time.time() - t0) <= float(timeout_s):
        try:
            fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, my_pid_txt.encode("utf-8", errors="ignore"))
            os.close(fd)
            return
        except FileExistsError:
            old_pid = 0
            try:
                raw = lock_path.read_text(encoding="utf-8", errors="ignore").strip()
                old_pid = int(raw) if raw.isdigit() else 0
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                old_pid = 0
            if old_pid <= 0:
                # Empty/invalid lock payload must not block startup.
                try:
                    lock_path.write_text(my_pid_txt, encoding="utf-8")
                    return
                except Exception as e:
                    cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            if old_pid and not pid_is_running(old_pid):
                try:
                    lock_path.unlink(missing_ok=True)
                except Exception as e:
                    cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                    # ACL fallback: claim stale lock by in-place overwrite.
                    try:
                        lock_path.write_text(my_pid_txt, encoding="utf-8")
                        return
                    except Exception as e:
                        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                time.sleep(0.05 + random.random() * 0.05)
                continue
            time.sleep(0.05 + random.random() * 0.10)
            continue
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            time.sleep(0.05 + random.random() * 0.10)
            continue
    raise RuntimeError(f"ALREADY_RUNNING: lock exists at {lock_path}")

def release_lock(lock_path: Path) -> None:
    try:
        lock_path.unlink(missing_ok=True)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        try:
            lock_path.write_text("", encoding="utf-8")
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)

# -------------------------
# Logging
# -------------------------
def setup_logging(runtime_root: Path) -> None:
    """
    Logging is always local (C:\\OANDA_MT5_SYSTEM\\LOGS). USB is never used for logs.
    Unified log name: LOGS\\scudfab02.log
    """
    log_dir = runtime_root / "LOGS"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "scudfab02.log"

    handlers = []
    try:
        from logging.handlers import RotatingFileHandler
        handlers.append(RotatingFileHandler(str(log_file), maxBytes=10_000_000, backupCount=10, encoding="utf-8"))
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        handlers.append(logging.FileHandler(str(log_file), encoding="utf-8"))

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s | %(levelname)s | %(message)s",
        handlers=handlers
    )

def atomic_write_json(path: Path, obj: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    data = json.dumps(obj, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    last_exc: Optional[Exception] = None
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        for _ in range(max(1, int(ATOMIC_REPLACE_RETRIES))):
            try:
                os.replace(tmp, path)
                return
            except Exception as e:
                last_exc = e
                time.sleep(float(ATOMIC_REPLACE_RETRY_SLEEP_S))
        for _ in range(max(1, int(ATOMIC_REPLACE_RETRIES))):
            try:
                shutil.move(str(tmp), str(path))
                return
            except Exception as e:
                last_exc = e
                time.sleep(float(ATOMIC_REPLACE_RETRY_SLEEP_S))
        # Fallback for environments where atomic rename/move is blocked.
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        return
    finally:
        try:
            if tmp.exists():
                tmp.unlink(missing_ok=True)
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
    if last_exc is not None:
        raise last_exc

def _update_cached_stats(*, ranks: List[Dict[str, Any]], verdict: str, metrics_n: int) -> None:
    global LAST_RANKS, LAST_VERDICT_LIGHT, LAST_METRICS_N
    try:
        LAST_RANKS = list(ranks or [])
        LAST_VERDICT_LIGHT = str(verdict or "INSUFFICIENT_DATA").upper()
        LAST_METRICS_N = int(metrics_n or 0)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)

def process_tiebreak_fast(run_dir: Path, *, ranks: List[Dict[str, Any]], verdict: str, metrics_n: int, source: str) -> bool:
    """Fast-lane RUN tiebreak: respond quickly using cached ranks only.

    Returns True if a response was written.
    """
    try:
        req = load_tiebreak_request(run_dir)
        if not req:
            return False
        pair = list(req.get("cands") or [])
        preferred, _conf, _notes = choose_preferred_from_ranks(pair, ranks or [])
        allow_tb = (str(verdict).upper() == "GREEN" and int(metrics_n or 0) >= MIN_SAMPLE_N)
        if allow_tb and preferred and preferred in set(pair):
            reasons = ["green_gate", "n_ok", f"src={source}"]
            write_tiebreak_response(run_dir, rid=req["rid"], tb=1, pref=preferred, reasons=reasons)
            logging.info(f"TIEBREAK_RESP_FAST | rid={req['rid']} pref={preferred} src={source}")
            return True
        return False
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return False

def safe_append_jsonl(path: Path, record: Dict[str, Any]) -> bool:
    """Append JSONL line only if it passes P0 gates (price-like + numeric + length)."""
    lock_path = path.with_suffix(path.suffix + ".lock")
    lock_acquired = False
    try:
        guard_obj_no_price_like(record)
        guard_obj_limits(record)
        line = json.dumps(record, ensure_ascii=False, separators=(",", ":"))
        if len(line) > MAX_JSONL_LINE_LEN:
            logging.warning("JSONL_LINE_TOO_LONG")
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        acquire_lock(lock_path, timeout_s=JSONL_LOCK_TIMEOUT_S)
        lock_acquired = True
        with open(path, "a", encoding="utf-8", newline="\n") as f:
            f.write(line + "\n")
            try:
                f.flush(); os.fsync(f.fileno())
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return True
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        logging.warning(f"JSONL_RECORD_REJECTED {type(e).__name__}")
        return False
    finally:
        if lock_acquired:
            release_lock(lock_path)

def _read_tail_bytes(path: Path, max_bytes: int) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            start = max(0, size - max_bytes)
            f.seek(start)
            data = f.read()
        return data.decode("utf-8", errors="ignore")
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return ""

def _shadowb_recent_ids(path: Path, *, limit: int = 500, max_bytes: int = 262144) -> set[str]:
    if not path.exists():
        return set()
    text = _read_tail_bytes(path, max_bytes=max_bytes)
    if not text:
        return set()
    ids: List[str] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            eid = str(obj.get("event_id") or "").strip()
            if eid:
                ids.append(eid)
        except Exception:
            continue
    # keep last N unique
    out: List[str] = []
    seen = set()
    for eid in reversed(ids):
        if eid in seen:
            continue
        seen.add(eid)
        out.append(eid)
        if len(out) >= int(limit):
            break
    return set(out)

def _append_jsonl_batch(path: Path, records: List[Dict[str, Any]]) -> int:
    if not records:
        return 0
    lock_path = path.with_suffix(path.suffix + ".lock")
    lock_acquired = False
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        acquire_lock(lock_path, timeout_s=JSONL_LOCK_TIMEOUT_S)
        lock_acquired = True
        lines = []
        for rec in records:
            guard_obj_no_price_like(rec)
            guard_obj_limits(rec)
            line = json.dumps(rec, ensure_ascii=False, separators=(",", ":"))
            if len(line) > MAX_JSONL_LINE_LEN:
                logging.warning("JSONL_LINE_TOO_LONG")
                continue
            lines.append(line)
        if not lines:
            return 0
        with open(path, "a", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
            try:
                f.flush(); os.fsync(f.fileno())
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return len(lines)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return 0
    finally:
        if lock_acquired:
            release_lock(lock_path)

# -------------------------
# Guards: price-like keys/values
# -------------------------
BANNED_KEY_TOKENS = {
    "bid","ask","ohlc","open","high","low","close","price","prices","rate","rates","tick","ticks","quote","quotes","spread"
}

_price_num_pat = None
def looks_pricey_text(s: str) -> bool:
    """Detect obvious price-like patterns in free text (currency + number or '1.2345')."""
    global _price_num_pat
    if _price_num_pat is None:
        import re
        _price_num_pat = re.compile(r"(\b\d{1,3}[.,]\d{2,6}\b)|(\b\d{1,5}\.\d{1,6}\b)|([$€£]\s*\d)|(\b\d+\s*(USD|EUR|PLN|GBP|JPY)\b)", re.IGNORECASE)
    return bool(_price_num_pat.search(s or ""))

def guard_obj_no_price_like(obj: Any) -> None:
    """Fail-fast if any key path contains banned tokens, or values look like prices.
    Boundary/token match (no substring false-positives).
    """
    if isinstance(obj, dict):
        for k, v in obj.items():
            if cg.key_has_price_like_token(str(k)):
                raise ValueError(f"PRICE_LIKE_KEY: {k}")
            guard_obj_no_price_like(v)
    elif isinstance(obj, list):
        # rule: long numeric series suspicious
        if len(obj) > 50 and all(isinstance(x, (int, float)) and not isinstance(x, bool) for x in obj):
            raise ValueError("SUSPICIOUS_NUMERIC_SERIES")
        for x in obj:
            guard_obj_no_price_like(x)
    elif isinstance(obj, str):
        if cg.text_has_price_like_token(obj):
            raise ValueError("PRICE_LIKE_TEXT_VALUE")
        if looks_pricey_text(obj):
            raise ValueError("PRICE_LIKE_NUMERIC_TEXT")
    else:
        return

# -------------------------
# SQLite retry/backoff
# -------------------------
def sqlite_connect_ro(db_path: Path) -> sqlite3.Connection:
    # Prefer read-only; fallback if URI not supported.
    uri = f"file:{db_path.as_posix()}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, check_same_thread=False, timeout=5.0)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        conn = sqlite3.connect(str(db_path), check_same_thread=False, timeout=5.0)
    try:
        conn.execute("PRAGMA busy_timeout=5000;")
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
    return conn

def sqlite_fetchall_retry(conn: sqlite3.Connection, q: str, params: Tuple = (), *, tries: int = 6, base_sleep: float = 0.15):
    for i in range(tries):
        try:
            cur = conn.execute(q, params)
            return cur.fetchall()
        except sqlite3.OperationalError as e:
            msg = str(e).lower()
            if ("locked" in msg) or ("busy" in msg):
                time.sleep(base_sleep * (2 ** i) + random.random() * 0.05)
                continue
            raise
    cur = conn.execute(q, params)
    return cur.fetchall()

# -------------------------
# Research (RSS allowlist)
# -------------------------
RSS_SOURCES: List[Dict[str, Any]] = [
    {
        "source_id": "reuters_business",
        "url": "https://feeds.reuters.com/reuters/businessNews",
        "instrument_tags": ["EURUSD", "GBPUSD", "XAUUSD", "DAX40", "US500"],
        "keyword_only": True,
    },
    {
        "source_id": "fed_press",
        "url": "https://www.federalreserve.gov/feeds/press_all.xml",
        "instrument_tags": ["EURUSD", "XAUUSD", "US500"],
    },
    {
        "source_id": "ecb_press",
        "url": "https://www.ecb.europa.eu/rss/press.html",
        "instrument_tags": ["EURUSD", "DAX40"],
    },
    {
        "source_id": "boe_news",
        "url": "https://www.bankofengland.co.uk/rss/news",
        "instrument_tags": ["GBPUSD"],
    },
    {
        "source_id": "bundesbank_press",
        "url": "https://www.bundesbank.de/en/rss-feeds/press-releases-624784",
        "instrument_tags": ["DAX40", "EURUSD"],
    },
    {
        "source_id": "bbc_business",
        "url": "https://feeds.bbci.co.uk/news/business/rss.xml",
        "instrument_tags": ["EURUSD", "GBPUSD", "XAUUSD", "DAX40", "US500"],
        "keyword_only": True,
    },
]

RSS_TIMEOUT_SEC = 1.5
RSS_MAX_WORKERS = 3
RSS_MAX_BYTES = 262144  # 256 KiB
RSS_MAX_ITEMS_PER_SOURCE = 8
RSS_MAX_ITEMS_TOTAL = 25
RSS_FRESH_MAX_AGE_SEC = 24 * 3600
RSS_RT_AGE_SEC = 2 * 3600

INSTRUMENT_KEYWORDS: Dict[str, Tuple[str, ...]] = {
    "EURUSD": (
        " euro ",
        " ecb ",
        " eurozone ",
        " euro area ",
        " german bund ",
    ),
    "GBPUSD": (
        " pound ",
        " sterling ",
        " boe ",
        " bank of england ",
        " uk inflation ",
    ),
    "XAUUSD": (
        " gold ",
        " bullion ",
        " safe haven ",
        " precious metal ",
    ),
    "DAX40": (
        " dax ",
        " germany ",
        " german ",
        " eurostoxx ",
        " bundestag ",
    ),
    "US500": (
        " s&p ",
        " sp500 ",
        " us equities ",
        " wall street ",
        " federal reserve ",
    ),
}

def sha256(s: str) -> str:
    return hashlib.sha256((s or "").encode("utf-8", errors="ignore")).hexdigest()

def _entry_ts_utc(entry: Any) -> Optional[dt.datetime]:
    try:
        st = getattr(entry, "published_parsed", None) or getattr(entry, "updated_parsed", None)
        if st:
            return dt.datetime(*st[:6], tzinfo=UTC)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)

    for key in ("published", "updated", "created"):
        raw = getattr(entry, key, None)
        if raw:
            t = parse_ts_utc(str(raw))
            if t is not None:
                return t
    return None

def _iso_utc(t: dt.datetime) -> str:
    return t.replace(microsecond=0).isoformat().replace("+00:00", "Z")

def _guess_instrument_tags(text: str, fallback_tags: List[str], *, allow_fallback: bool = True) -> List[str]:
    s = f" {str(text or '').lower()} "
    tags: List[str] = []
    for sym, kws in INSTRUMENT_KEYWORDS.items():
        for kw in kws:
            if kw in s:
                tags.append(sym)
                break
    if tags:
        return sorted(set(tags))
    if allow_fallback:
        return list(fallback_tags or [])
    return []

def _freshness_label(source_ts: dt.datetime, fetch_ts: dt.datetime) -> str:
    age = (fetch_ts - source_ts).total_seconds()
    if age < 0:
        return "future_skew"
    if age <= RSS_RT_AGE_SEC:
        return "rt_2h"
    if age <= RSS_FRESH_MAX_AGE_SEC:
        return "fresh_24h"
    return "stale"

def _impact_class(source_id: str, freshness: str) -> str:
    if freshness == "rt_2h":
        if source_id in {"fed_press", "ecb_press", "boe_news", "bundesbank_press"}:
            return "major"
        return "normal"
    if freshness == "fresh_24h":
        return "normal"
    return "minor"

def _fetch_one_rss_source(source: Dict[str, Any], timeout_sec: float) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    try:
        import requests
        import feedparser

        source_id = str(source.get("source_id") or "").strip().lower()
        url = str(source.get("url") or "").strip()
        fallback_tags = [str(x).strip().upper() for x in (source.get("instrument_tags") or []) if str(x).strip()]
        allow_fallback = not bool(source.get("keyword_only", False))
        if not source_id or not url:
            return out

        resp = requests.get(url, timeout=timeout_sec, headers={"User-Agent": "scudfab02"}, stream=True)
        buf = bytearray()
        try:
            for chunk in resp.iter_content(chunk_size=16384):
                if not chunk:
                    break
                buf.extend(chunk)
                if len(buf) >= RSS_MAX_BYTES:
                    break
        finally:
            try:
                resp.close()
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)

        txt = bytes(buf).decode("utf-8", errors="ignore")
        feed = feedparser.parse(txt)
        domain = url.split("/")[2].lower() if "/" in url else ""
        fetch_ts = _now_utc()
        fetch_iso = _iso_utc(fetch_ts)

        for entry in (feed.entries or [])[:RSS_MAX_ITEMS_PER_SOURCE]:
            try:
                title = str(getattr(entry, "title", "") or "")
                summary = str(getattr(entry, "summary", "") or "")
                link = str(getattr(entry, "link", "") or "")
                source_ts = _entry_ts_utc(entry)
                if source_ts is None:
                    continue
                freshness = _freshness_label(source_ts, fetch_ts)
                if freshness not in {"rt_2h", "fresh_24h"}:
                    continue
                tags = _guess_instrument_tags(f"{title} {summary}", fallback_tags, allow_fallback=allow_fallback)
                if not tags:
                    continue
                rec = {
                    "source_id": source_id,
                    "domain": domain,
                    "instrument_tags": tags,
                    "ts_source_utc": _iso_utc(source_ts.astimezone(UTC)),
                    "ts_fetch_utc": fetch_iso,
                    "headline_sha256": sha256(title),
                    "summary_sha256": sha256(summary),
                    "link_sha256": sha256(link),
                    "freshness": freshness,
                    "impact_class": _impact_class(source_id, freshness),
                }
                out.append(rec)
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                continue
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        logging.warning(f"RSS_FAIL source={source.get('source_id')} err={type(e).__name__}")
    return out

def fetch_rss_signals(timeout_sec: float = RSS_TIMEOUT_SEC) -> Dict[str, Any]:
    """
    Non-price online research. Returns hashed/scrubbed, normalized signals only.
    """
    out = {"ts_utc": _now_utc().replace(microsecond=0).isoformat().replace("+00:00","Z"), "items": []}
    if DETERMINISTIC_MODE or (not ALLOW_RSS_RESEARCH):
        return out
    items: List[Dict[str, Any]] = []
    futures = []
    max_workers = max(1, min(RSS_MAX_WORKERS, len(RSS_SOURCES)))
    try:
        with cf.ThreadPoolExecutor(max_workers=max_workers, thread_name_prefix="scudrss") as ex:
            for src in RSS_SOURCES:
                futures.append(ex.submit(_fetch_one_rss_source, src, timeout_sec))
            try:
                for fut in cf.as_completed(futures, timeout=max(2.0, timeout_sec * 3.0)):
                    try:
                        items.extend(fut.result() or [])
                    except Exception as e:
                        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            except cf.TimeoutError:
                logging.warning("RSS_TIMEOUT_BATCH")
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        logging.warning(f"NET_DISABLED_OR_FAIL err={type(e).__name__}")

    # Deterministic priority and dedupe:
    # rt_2h first, then fresh_24h, then lexical fallback.
    prio = {"rt_2h": 0, "fresh_24h": 1}
    dedup: Dict[str, Dict[str, Any]] = {}
    for rec in items:
        try:
            key = f"{rec.get('source_id','')}|{rec.get('headline_sha256','')}|{rec.get('link_sha256','')}"
            if key and key not in dedup:
                dedup[key] = rec
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            continue
    out["items"] = sorted(
        list(dedup.values()),
        key=lambda r: (
            prio.get(str(r.get("freshness") or ""), 9),
            str(r.get("source_id") or ""),
            str(r.get("headline_sha256") or ""),
        ),
    )[:RSS_MAX_ITEMS_TOTAL]

    # Guard output (no price-like keys/values)
    guard_obj_no_price_like(out)
    guard_obj_limits(out)
    return out

# -------------------------
# Symbol extraction (from SafetyBot signal text)
# -------------------------
def extract_symbol_from_signal(signal: str) -> str:
    """
    Best-effort extraction of raw symbol from a free-text 'signal' field.
    PRICE-FREE: uses only identifiers, no quotes.
    """
    if not signal:
        return ""
    s = str(signal).upper()
    # normalize separators
    s = s.replace("/", " ").replace("|", " ").replace(",", " ").replace(";", " ").replace(":", " ")
    # tokens: alnum + dot (for suffixes like .PRO)
    toks = re.findall(r"[A-Z0-9\.]{3,15}", s)
    for tok in toks:
        if tok in ("BUY", "SELL", "LONG", "SHORT", "NEUTRAL", "ENTRY", "EXIT"):
            continue
        if "." in tok:
            base = tok.split(".", 1)[0]
            if 3 <= len(base) <= 10 and any(c.isalpha() for c in base):
                return tok
        else:
            # common FX/metals patterns: 6 letters (EURUSD), or contains USD (XAUUSD)
            if (len(tok) == 6) or tok.endswith("USD") or tok.startswith("USD"):
                if tok.isalnum() and any(c.isalpha() for c in tok):
                    return tok
    return ""

# -------------------------
# -------------------------
# Tie-break request/response (RUN) — strict contract RUN pv=2 (price-free)
# Request (pv=2 exact keys): pv, ts_utc, rid, ttl_sec, cands, mode, ctx
# Response (pv=2 exact keys): pv, ts_utc, rid, tb (0/1/2), pref, reasons
# -------------------------
TIEBREAK_REQ_NAME = "tiebreak_request.json"
TIEBREAK_RES_NAME = "tiebreak_response.json"
TIEBREAK_RES_TTL_SEC = 30  # response is ephemeral (SafetyBot also guards)

def _now_utc_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def load_tiebreak_request(run_dir: Path) -> Optional[Dict[str, Any]]:
    """Read RUN/tiebreak_request.json if present and fresh. Contract: RUN pv=2 strict."""
    try:
        path = Path(run_dir) / TIEBREAK_REQ_NAME
        if not path.exists():
            return None
        if path.stat().st_size <= 0 or path.stat().st_size > 50_000:
            return None
        data = _read_json_file_retry(path)
        if data is None:
            return None
        if not isinstance(data, dict):
            return None

        # guard: no price-like keys/values + numeric limits
        guard_obj_no_price_like(data)
        guard_obj_limits(data)

        v = cc.validate_run_request_v2(data)
        if not v:
            return None

        rid = str(v.get("rid") or "").strip()
        ttl = int(v.get("ttl_sec") or 30)
        ttl = min(max(1, ttl), 60)  # hard max

        # Use mtime for robustness; ts_utc is informational
        age = dt.datetime.now(dt.timezone.utc).timestamp() - path.stat().st_mtime
        if age < 0 or age > ttl:
            return None

        cands = v.get("cands") or []
        if not isinstance(cands, list) or len(cands) != 2:
            return None

        mode = str(v.get("mode") or "").strip().upper() or "PAPER"
        ctx = v.get("ctx") if isinstance(v.get("ctx"), dict) else {}
        return {"path": path, "rid": rid, "cands": cands, "mode": mode, "ctx": ctx, "raw": v}
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        return None

def write_tiebreak_response(run_dir: Path, rid: str, tb: int, pref: str = "", reasons: Optional[List[str]] = None) -> None:
    """Write RUN/tiebreak_response.json (atomic). Contract: RUN pv=2 strict."""
    out = {
        "pv": 2,
        "ts_utc": _now_utc_iso(),
        "rid": str(rid).strip(),
        "tb": int(tb),
        "pref": str(pref).strip().upper(),
        "reasons": list(reasons or []),
    }

    # strict schema + guards
    if not cc.validate_run_response_v2(out, rid_expected=str(rid).strip()):
        raise ValueError("RUN_V2_RESPONSE_SCHEMA_INVALID")
    guard_obj_no_price_like(out)
    guard_obj_limits(out)

    # enforce compact JSON length <= 2048 deterministically (trim reasons)
    while True:
        s = json.dumps(out, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if len(s) <= int(MAX_JSONL_LINE_LEN):
            break
        if out["reasons"]:
            out["reasons"] = out["reasons"][:-1]
            continue
        # last resort: clear pref
        out["pref"] = ""
        s = json.dumps(out, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
        if len(s) <= int(MAX_JSONL_LINE_LEN):
            break
        raise ValueError("RUN_V2_RESPONSE_LEN_GT_2048")

    atomic_write_json(Path(run_dir) / TIEBREAK_RES_NAME, out)

def choose_preferred_from_ranks(candidates: List[str], ranks: List[Dict[str, Any]]) -> Tuple[str, float, List[str]]:
    """Return (preferred, confidence, notes). PRICE-FREE."""
    cand_set = {c.strip().upper() for c in candidates if str(c).strip()}
    if len(cand_set) < 2:
        return ("", 0.0, ["insufficient_candidates"])
    # Build metric map: (score, es95, -mdd, n)
    mm: Dict[str, Tuple[float, float, float, int]] = {}
    for r in ranks or []:
        if not isinstance(r, dict):
            continue
        sym = str(r.get("symbol") or "").strip().upper()
        if not sym or sym not in cand_set:
            continue
        score = r.get("mean_edge_fuel")
        if not isinstance(score, (int, float)):
            score = r.get("score")
        if not isinstance(score, (int, float)):
            continue
        esv = r.get("es95")
        mdd = r.get("mdd")
        n = r.get("n")
        esv_f = float(esv) if isinstance(esv, (int, float)) else 0.0
        mdd_f = float(mdd) if isinstance(mdd, (int, float)) else 0.0
        n_i = int(n) if isinstance(n, (int, float)) else 0
        mm[sym] = (float(score), esv_f, -mdd_f, n_i)
    if not mm:
        return ("", 0.0, ["no_metrics"])
    # pick max lexicographically
    best = None
    for sym, tpl in mm.items():
        if best is None or tpl > best[1]:
            best = (sym, tpl)
    if best is None:
        return ("", 0.0, ["no_best"])
    # confidence heuristic: 0.55..0.75 based on sample size, capped
    n_i = max(0, int(best[1][3]))
    conf = 0.55 + min(0.20, (n_i / 200.0))
    return (best[0], float(round(conf, 4)), ["rank_based"])

# -------------------------
# Monitor: decision events -> shadowb + verdict
# -------------------------
def read_closed_events(db_path: Path, limit: int = 500) -> List[Dict[str, Any]]:
    if not db_path.exists():
        return []
    conn = sqlite_connect_ro(db_path)
    try:
        rows = sqlite_fetchall_retry(conn, """
            SELECT event_id, ts_utc, choice_A, signal, verdict_light,
                   price_requests_trade, sys_used,
                   outcome_pnl_net, outcome_profit, outcome_commission, outcome_swap, outcome_fee,
                   outcome_closed_ts_utc
            FROM decision_events
            WHERE outcome_closed_ts_utc IS NOT NULL AND outcome_closed_ts_utc != ''
            ORDER BY outcome_closed_ts_utc DESC
            LIMIT ?
        """, (limit,))
        out = []
        for r in rows:
            out.append({
                "event_id": r[0],
                "ts_utc": r[1],
                "choice_A": r[2],
                "signal": r[3],
                "verdict_light": r[4],
                "reqs_trade": int(r[5] or 0),
                "sys_used": int(r[6] or 0),
                "pnl_net": float(r[7] or 0.0),
                "profit": float(r[8] or 0.0),
                "commission": float(r[9] or 0.0),
                "swap": float(r[10] or 0.0),
                "fee": float(r[11] or 0.0),
                "end_ts_utc": r[12],
            })
        return out
    finally:
        try:
            conn.close()
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)

def compute_edge_fuel(pnl_net: float, reqs_trade: int) -> float:
    if reqs_trade <= 0:
        return 0.0
    return float(pnl_net) / float(reqs_trade)

def append_shadowb(runtime_root: Path, records: List[dict]) -> int:
    """Append META/scout_shadowb.jsonl with hard guards (P0).

    Returns number of appended records (accepted by gates). Never raises.
    """
    p = runtime_root / "META" / "scout_shadowb.jsonl"
    if not records:
        return 0
    existing = _shadowb_recent_ids(p, limit=500, max_bytes=262144)
    batch: List[Dict[str, Any]] = []
    for rec in records:
        try:
            eid = str(rec.get("event_id") or "").strip()
            if eid and eid in existing:
                continue
            batch.append(rec)
            if eid:
                existing.add(eid)
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            continue
    appended = _append_jsonl_batch(p, batch)
    return int(appended)

def read_shadowb(shadowb_path: Path, limit: int = 300) -> List[Dict[str, Any]]:
    if not shadowb_path.exists():
        return []
    out = []
    with open(shadowb_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f.readlines()[-limit:]:
            try:
                out.append(json.loads(line))
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                continue
    return out

def es95(values: List[float]) -> float:
    if not values:
        return 0.0
    xs = sorted(values)
    # 5% tail average (loss tail)
    k = max(1, int(0.05 * len(xs)))
    return float(sum(xs[:k])) / float(k)

def max_drawdown(cum: List[float]) -> float:
    peak = -1e18
    mdd = 0.0
    s = 0.0
    for x in cum:
        s += x
        peak = max(peak, s)
        mdd = min(mdd, s - peak)
    return float(mdd)

def compute_verdict(metrics: Dict[str, Any]) -> str:
    """
    Simple conservative traffic light based on edge_fuel mean and tail risk.

    Sample-size gate:
    - if n < MIN_SAMPLE_N => YELLOW (no confidence; no tie-break)

    GREEN: mean_edge > 0 and ES95 not too negative
    YELLOW: mixed
    RED: mean_edge <= 0 or strong negative tail
    """
    qa_light = str(metrics.get("qa_light") or "").strip().upper()
    if qa_light == "RED":
        return "RED"

    n_i = int(metrics.get("n") or 0)
    if n_i < MIN_SAMPLE_N:
        return "YELLOW"

    mean_edge = float(metrics.get("mean_edge_fuel", 0.0))
    tail = float(metrics.get("es95", 0.0))
    if qa_light == "YELLOW":
        if mean_edge <= 0.0 or tail < -0.15:
            return "RED"
        return "YELLOW"
    if mean_edge > 0.0 and tail > -0.05:
        return "GREEN"
    if mean_edge <= 0.0 or tail < -0.15:
        return "RED"
    return "YELLOW"

def build_metrics_from_shadowb(recs: List[Dict[str, Any]]) -> Dict[str, Any]:
    edges = [float(r.get("edge_fuel", 0.0)) for r in recs if isinstance(r.get("edge_fuel", None), (int, float))]
    pnls = [float(r.get("pnl_net", 0.0)) for r in recs if isinstance(r.get("pnl_net", None), (int, float))]
    mean_edge = float(sum(edges) / len(edges)) if edges else 0.0
    tail = es95(edges)
    mdd = max_drawdown(pnls)
    return {
        "n": int(len(edges)),
        "mean_edge_fuel": round(mean_edge, 12),
        "es95": round(tail, 12),
        "mdd": round(mdd, 6),
    }

def build_symbol_ranks(recs: List[Dict[str, Any]], top_n: int = 12) -> List[Dict[str, Any]]:
    """
    Compute PRICE-FREE per-symbol ranking from Shadow-B records.
    Ranking key (lexicographic): higher mean_edge, higher es95, lower mdd, higher n.
    """
    buckets: Dict[str, List[Dict[str, Any]]] = {}
    for r in recs:
        sym = str(r.get("symbol") or "").strip().upper()
        if not sym:
            continue
        buckets.setdefault(sym, []).append(r)

    ranked: List[Tuple[Tuple[float, float, float, int], Dict[str, Any]]] = []
    for sym, rr in buckets.items():
        edges = [float(x.get("edge_fuel", 0.0)) for x in rr if isinstance(x.get("edge_fuel", None), (int, float))]
        pnls = [float(x.get("pnl_net", 0.0)) for x in rr if isinstance(x.get("pnl_net", None), (int, float))]
        n = int(len(edges))
        mean_edge = float(sum(edges) / n) if n > 0 else 0.0
        tail = float(es95(edges)) if edges else 0.0
        mdd = float(max_drawdown(pnls)) if pnls else 0.0
        item = {
            "symbol": sym,
            "score": round(mean_edge, 12),
            "es95": round(tail, 12),
            "mdd": round(mdd, 6),
            "n": n,
        }
        key = (float(item["score"]), float(item["es95"]), -float(item["mdd"]), int(item["n"]))
        ranked.append((key, item))

    ranked.sort(key=lambda x: x[0], reverse=True)
    out = [it for (_k, it) in ranked[:max(0, int(top_n))]]
    guard_obj_no_price_like(out)
    return out

def write_verdict(meta_dir: Path, metrics: Dict[str, Any], verdict: str) -> None:
    now = _now_utc().replace(microsecond=0)
    obj = {
        "schema": "oanda_mt5.verdict.v1",
        "ts_utc": now.isoformat().replace("+00:00","Z"),
        "ttl_sec": int(48 * 3600),
        "light": str(verdict).upper(),
        "metrics": metrics,
    }
    guard_obj_no_price_like(obj)
    guard_obj_limits(obj)
    atomic_write_json(meta_dir / "verdict.json", obj)

def write_advice(meta_dir: Path, verdict: str, metrics: Dict[str, Any], research: Dict[str, Any], ranks: List[Dict[str, Any]]) -> None:
    now = _now_utc().replace(microsecond=0)
    pref = ""
    try:
        if ranks:
            pref = str(ranks[0].get("symbol") or "").strip().upper()
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        pref = ""

    obj = {
        "schema": "oanda_mt5.scout_advice.v2",
        "ts_utc": now.isoformat().replace("+00:00","Z"),
        "ttl_sec": int(900),
        "preferred_symbol": pref,
        "ranks": ranks[:12],
        "light": str(verdict).upper(),
        "notes": [
            "mode=tiebreak",
            "source=shadowb",
            "basis=pnl_es_mdd",
        ],
        "research": {
            "ts_utc": research.get("ts_utc",""),
            "items": (research.get("items",[]) or [])[:25],
        },
    }
    guard_obj_no_price_like(obj)
    guard_obj_limits(obj)
    atomic_write_json(meta_dir / "scout_advice.json", obj)

def write_research(meta_dir: Path, research: Dict[str, Any]) -> None:
    path = meta_dir / "research_signals.json"
    guard_obj_no_price_like(research)
    guard_obj_limits(research)
    atomic_write_json(path, research)

# -------------------------
# Main loop
# -------------------------
def run_once(root: Path) -> int:
    dirs = ensure_dirs(root)
    meta = dirs["META"]; db = dirs["DB"]

    # Fast-lane tiebreak: respond before heavy IO/DB/RSS
    fast_handled = process_tiebreak_fast(
        dirs["RUN"],
        ranks=LAST_RANKS,
        verdict=LAST_VERDICT_LIGHT,
        metrics_n=LAST_METRICS_N,
        source="cache",
    )

    # Fetch research (best-effort)
    research = fetch_rss_signals()

    # Prefer offline Learner output if available & fresh.
    # This shifts heavy DB/statistics out of the SCUD runtime loop.
    offline = read_learner_advice(meta)
    if offline is not None:
        metrics = offline.get('metrics') or {}
        qa_light = str(offline.get('qa_light') or "").strip().upper()
        if qa_light in {"GREEN", "YELLOW", "RED"}:
            metrics["qa_light"] = qa_light
        verdict = compute_verdict(metrics)
        ranks = offline.get('ranks') or []

        _update_cached_stats(ranks=ranks, verdict=verdict, metrics_n=int(metrics.get("n") or 0))

        # Write outputs driven by offline learner + online research
        write_research(meta, research)
        write_verdict(meta, metrics, verdict)
        write_advice(meta, verdict, metrics, research, ranks)

        # Process on-demand tie-break request (RUN) — best-effort, never blocks
        try:
            if fast_handled:
                req = None
            else:
                req = load_tiebreak_request(dirs["RUN"])
            if req:
                pair = list(req.get("cands") or [])
                preferred, _conf, _notes = choose_preferred_from_ranks(pair, ranks)
                allow_tb = (str(verdict).upper() == 'GREEN' and int(metrics.get('n') or 0) >= MIN_SAMPLE_N)
                if allow_tb and preferred and preferred in set(pair):
                    reasons = ["green_gate", "n_ok", "src=offline"]
                    write_tiebreak_response(dirs["RUN"], rid=req["rid"], tb=1, pref=preferred, reasons=reasons)
                    logging.info(f"TIEBREAK_RESP | rid={req['rid']} pref={preferred} tb=1 src=offline")
                else:
                    if str(verdict).upper() != 'GREEN':
                        reasons = ["not_green"]
                    elif int(metrics.get('n') or 0) < MIN_SAMPLE_N:
                        reasons = ["n_low"]
                    else:
                        reasons = ["no_tb"]
                    write_tiebreak_response(dirs["RUN"], rid=req["rid"], tb=0, pref="", reasons=reasons)
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            logging.warning(f"TIEBREAK_ERR {type(e).__name__}")

        logging.info(f"RUN_ONCE | src=offline_learner verdict={verdict} n={metrics.get('n')}")
        return 0

    # Read closed events -> Shadow-B append (from SafetyBot DB)
    events = read_closed_events(db / "decision_events.sqlite", limit=500)

    # Normalize to Shadow-B schema (PRICE-FREE): derive symbol + edge_fuel, drop noisy fields.
    # This is the actual "mini-learner" input stream.
    shadowb: List[Dict[str, Any]] = []
    for e in events:
        try:
            sym = str(e.get("choice_A") or "").strip().upper()
            reqs_trade = int(e.get("reqs_trade") or 0)
            pnl_net = float(e.get("pnl_net") or 0.0)
            rec = {
                "event_id": e.get("event_id"),
                "ts_utc": e.get("ts_utc"),
                "end_ts_utc": e.get("end_ts_utc"),
                "symbol": sym,
                "verdict_light": e.get("verdict_light"),
                "reqs_trade": reqs_trade,
                "pnl_net": pnl_net,
                "edge_fuel": compute_edge_fuel(pnl_net, reqs_trade),
            }
            shadowb.append(rec)
        except Exception as e:
            cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
            continue

    appended = append_shadowb(root, shadowb)

    # Compute verdict from shadowb
    recs = read_shadowb(meta / "scout_shadowb.jsonl", limit=300)
    metrics = build_metrics_from_shadowb(recs)
    verdict = compute_verdict(metrics)

    # Build per-symbol ranks (PRICE-FREE tie-breaker)
    ranks = build_symbol_ranks(recs, top_n=12)

    _update_cached_stats(ranks=ranks, verdict=verdict, metrics_n=int(metrics.get("n") or 0))

    # Write outputs
    write_research(meta, research)
    write_verdict(meta, metrics, verdict)
    write_advice(meta, verdict, metrics, research, ranks)

    # Process on-demand tie-break request (RUN) — best-effort, never blocks
    try:
        if fast_handled:
            req = None
        else:
            req = load_tiebreak_request(dirs["RUN"])
        if req:
            pair = list(req.get("cands") or [])
            preferred, _conf, _notes = choose_preferred_from_ranks(pair, ranks)
            allow_tb = (str(verdict).upper() == 'GREEN' and int(metrics.get('n') or 0) >= MIN_SAMPLE_N)
            if allow_tb and preferred and preferred in set(pair):
                reasons = ["green_gate", "n_ok", "src=loop"]
                write_tiebreak_response(dirs["RUN"], rid=req["rid"], tb=1, pref=preferred, reasons=reasons)
                logging.info(f"TIEBREAK_RESP | rid={req['rid']} pref={preferred} tb=1 src=loop")
            else:
                if str(verdict).upper() != 'GREEN':
                    reasons = ["not_green"]
                elif int(metrics.get('n') or 0) < MIN_SAMPLE_N:
                    reasons = ["n_low"]
                else:
                    reasons = ["no_tb"]
                write_tiebreak_response(dirs["RUN"], rid=req["rid"], tb=0, pref="", reasons=reasons)
    except Exception as e:
        cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
        logging.warning(f"TIEBREAK_ERR {type(e).__name__}")

    logging.info(f"RUN_ONCE | events={len(events)} appended={appended} verdict={verdict} n={metrics.get('n')}")
    return 0

def main():
    root = runtime_root()
    dirs = ensure_dirs(root)
    setup_logging(root)
    lock_path = dirs["RUN"] / "scudfab02.lock"
    acquire_lock(lock_path)
    try:
        mode = "loop"
        interval = 10
        if len(sys.argv) >= 2:
            mode = sys.argv[1].strip().lower()
        if len(sys.argv) >= 3:
            interval = max(10, int(float(sys.argv[2])))
        if mode == "once":
            sys.exit(run_once(root))
        # loop
        while True:
            try:
                run_once(root)
            except Exception as e:
                cg.tlog(None, "WARN", "SCUD_EXC", "nonfatal exception swallowed", e)
                logging.exception(f"LOOP_ERR {type(e).__name__}: {e}")
            time.sleep(interval)
    finally:
        release_lock(lock_path)

if __name__ == "__main__":
    main()
