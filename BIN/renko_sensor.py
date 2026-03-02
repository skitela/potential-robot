from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sqlite3
from typing import Any, Iterable, List


_VALID_PRICE_SOURCES = {"MID", "BID", "ASK"}


@dataclass(frozen=True)
class RenkoSensorConfig:
    brick_size_points: float
    point: float
    price_source: str = "MID"


@dataclass(frozen=True)
class RenkoTick:
    ts_msc: int
    bid: float
    ask: float


def _norm_price_source(raw: Any) -> str:
    mode = str(raw or "MID").strip().upper()
    return mode if mode in _VALID_PRICE_SOURCES else "MID"


def _tick_price(tick: RenkoTick, source: str) -> float:
    if source == "BID":
        return float(tick.bid)
    if source == "ASK":
        return float(tick.ask)
    return (float(tick.bid) + float(tick.ask)) * 0.5


def build_renko_bricks(cfg: RenkoSensorConfig, ticks: Iterable[RenkoTick]) -> dict[str, Any]:
    src = _norm_price_source(cfg.price_source)
    point = float(cfg.point or 0.0)
    brick_points = float(cfg.brick_size_points or 0.0)
    brick_size_price = point * brick_points
    if point <= 0.0 or brick_points <= 0.0 or brick_size_price <= 0.0:
        return {
            "ready": False,
            "reason_code": "RENKO_INVALID_CONFIG",
            "price_source": src,
            "brick_size_price": 0.0,
            "bricks": [],
        }

    seq_ticks: List[RenkoTick] = sorted(list(ticks), key=lambda x: int(x.ts_msc))
    if not seq_ticks:
        return {
            "ready": False,
            "reason_code": "RENKO_NO_TICKS",
            "price_source": src,
            "brick_size_price": float(brick_size_price),
            "bricks": [],
        }

    non_monotonic_ts = 0
    ask_lt_bid = 0
    for i in range(1, len(seq_ticks)):
        if int(seq_ticks[i].ts_msc) < int(seq_ticks[i - 1].ts_msc):
            non_monotonic_ts += 1
    for t in seq_ticks:
        if float(t.ask) < float(t.bid):
            ask_lt_bid += 1

    first_price = _tick_price(seq_ticks[0], src)
    last_close = float(first_price)
    last_dir = 0
    run_len = 0
    out: List[dict[str, Any]] = []

    for tick in seq_ticks:
        px = _tick_price(tick, src)
        ts_msc = int(tick.ts_msc)

        while px >= (last_close + brick_size_price):
            brick_open = float(last_close)
            brick_close = float(last_close + brick_size_price)
            direction = 1
            reversal = bool(last_dir == -1)
            run_len = 1 if reversal else (run_len + 1 if last_dir == 1 else 1)
            out.append(
                {
                    "idx": int(len(out) + 1),
                    "ts_msc_close": ts_msc,
                    "direction": "UP",
                    "open_price": brick_open,
                    "close_price": brick_close,
                    "reversal": reversal,
                    "run_length_after_close": int(run_len),
                }
            )
            last_close = brick_close
            last_dir = direction

        while px <= (last_close - brick_size_price):
            brick_open = float(last_close)
            brick_close = float(last_close - brick_size_price)
            direction = -1
            reversal = bool(last_dir == 1)
            run_len = 1 if reversal else (run_len + 1 if last_dir == -1 else 1)
            out.append(
                {
                    "idx": int(len(out) + 1),
                    "ts_msc_close": ts_msc,
                    "direction": "DOWN",
                    "open_price": brick_open,
                    "close_price": brick_close,
                    "reversal": reversal,
                    "run_length_after_close": int(run_len),
                }
            )
            last_close = brick_close
            last_dir = direction

    if not out:
        return {
            "ready": False,
            "reason_code": "RENKO_NOT_ENOUGH_MOVE",
            "price_source": src,
            "brick_size_price": float(brick_size_price),
            "bricks": [],
            "quality_flags": {
                "ask_lt_bid_count": int(ask_lt_bid),
                "non_monotonic_ts_count": int(non_monotonic_ts),
            },
        }

    last_brick = out[-1]
    prev_brick = out[-2] if len(out) > 1 else None
    reversal_flag = bool(prev_brick is not None and prev_brick.get("direction") != last_brick.get("direction"))

    return {
        "ready": True,
        "reason_code": "RENKO_OK",
        "price_source": src,
        "brick_size_price": float(brick_size_price),
        "bricks_count": int(len(out)),
        "last_brick_dir": str(last_brick.get("direction") or "NONE"),
        "run_length": int(last_brick.get("run_length_after_close") or 0),
        "reversal_flag": bool(reversal_flag),
        "bricks_generated_this_tick": 0,
        "quality_flags": {
            "ask_lt_bid_count": int(ask_lt_bid),
            "non_monotonic_ts_count": int(non_monotonic_ts),
        },
        "bricks": out,
    }


def load_ticks_from_sqlite(db_path: Path, symbol: str, limit: int = 4000) -> List[RenkoTick]:
    path = Path(db_path)
    if not path.exists():
        return []
    lim = max(1, int(limit))
    conn = sqlite3.connect(str(path), timeout=5)
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT ts_msc, bid, ask
            FROM tick_snapshots
            WHERE symbol = ?
            ORDER BY ts_msc DESC
            LIMIT ?
            """,
            (str(symbol), int(lim)),
        )
        rows = cur.fetchall()
    except sqlite3.Error:
        rows = []
    finally:
        conn.close()
    rows = list(reversed(rows))
    out: List[RenkoTick] = []
    for row in rows:
        try:
            out.append(RenkoTick(ts_msc=int(row[0]), bid=float(row[1]), ask=float(row[2])))
        except Exception:
            continue
    return out

