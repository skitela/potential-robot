#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import platform
import sqlite3
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Tuple

try:
    from TOOLS.lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from TOOLS.lab_registry import (
        connect_registry,
        get_ingest_watermark,
        init_registry_schema,
        insert_job_run,
        upsert_ingest_watermark,
    )
except Exception:  # pragma: no cover
    from lab_guardrails import canonical_json_hash, ensure_write_parent, file_sha256, resolve_lab_data_root
    from lab_registry import (
        connect_registry,
        get_ingest_watermark,
        init_registry_schema,
        insert_job_run,
        upsert_ingest_watermark,
    )

UTC = dt.timezone.utc
DEFAULT_MT5_EXE = r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"


def iso_utc(ts: dt.datetime) -> str:
    return ts.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _reexec_with_py312_if_available() -> int | None:
    if platform.system().lower() != "windows":
        return None
    if str(os.environ.get("OANDA_MT5_PY312_REEXEC", "0")).strip() == "1":
        return None
    script_path = Path(str(sys.argv[0] if sys.argv else "")).resolve()
    if not script_path.exists():
        return None
    try:
        chk = subprocess.run(
            ["py", "-3.12", "-c", "import MetaTrader5 as mt5; print(mt5.__version__)"],
            capture_output=True,
            text=True,
            timeout=12,
            check=False,
        )
    except Exception:
        return None
    if int(chk.returncode) != 0:
        return None
    env = dict(os.environ)
    env["OANDA_MT5_PY312_REEXEC"] = "1"
    cmd = ["py", "-3.12", str(script_path)] + list(sys.argv[1:])
    cp = subprocess.run(cmd, env=env, check=False)
    return int(cp.returncode)


def load_json(path: Path) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_ts_utc(raw: str | None) -> dt.datetime | None:
    if not raw:
        return None
    s = str(raw).strip()
    if not s:
        return None
    try:
        return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(UTC)
    except Exception:
        return None


def _tf_to_mt5(tf: str, mt5: Any) -> int:
    upper = str(tf or "").strip().upper()
    mapping = {
        "M1": getattr(mt5, "TIMEFRAME_M1", 1),
        "M5": getattr(mt5, "TIMEFRAME_M5", 5),
        "M15": getattr(mt5, "TIMEFRAME_M15", 15),
        "H1": getattr(mt5, "TIMEFRAME_H1", 16385),
    }
    if upper not in mapping:
        raise ValueError(f"Unsupported timeframe: {tf}")
    return int(mapping[upper])


def _symbols_for_group(strategy_cfg: Dict[str, Any], focus_group: str) -> List[str]:
    windows = strategy_cfg.get("trade_windows") or {}
    intents = strategy_cfg.get("trade_window_symbol_intents") or {}
    selected: List[str] = []
    for win_id, wcfg in windows.items():
        if not isinstance(wcfg, dict):
            continue
        grp = str(wcfg.get("group") or "").upper()
        if grp != str(focus_group).upper():
            continue
        for s in intents.get(str(win_id), []) or []:
            ss = str(s).upper()
            if ss and ss not in selected:
                selected.append(ss)
    return selected


def _create_history_schema(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS mt5_rates (
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            ts_utc TEXT NOT NULL,
            open REAL NOT NULL,
            high REAL NOT NULL,
            low REAL NOT NULL,
            close REAL NOT NULL,
            tick_volume INTEGER NOT NULL,
            spread INTEGER NOT NULL,
            real_volume INTEGER NOT NULL,
            source_terminal TEXT NOT NULL,
            ingest_run_id TEXT NOT NULL,
            ingested_at_utc TEXT NOT NULL,
            PRIMARY KEY (symbol, timeframe, ts_utc)
        )
        """
    )
    conn.commit()


def _insert_rates(
    conn: sqlite3.Connection,
    *,
    symbol: str,
    timeframe: str,
    rows: List[Dict[str, Any]],
    source_terminal: str,
    ingest_run_id: str,
    ingested_at_utc: str,
) -> int:
    if not rows:
        return 0
    cur = conn.executemany(
        """
        INSERT OR IGNORE INTO mt5_rates (
            symbol, timeframe, ts_utc, open, high, low, close,
            tick_volume, spread, real_volume, source_terminal, ingest_run_id, ingested_at_utc
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            [
                symbol,
                timeframe,
                str(r["ts_utc"]),
                float(r["open"]),
                float(r["high"]),
                float(r["low"]),
                float(r["close"]),
                int(r.get("tick_volume") or 0),
                int(r.get("spread") or 0),
                int(r.get("real_volume") or 0),
                source_terminal,
                ingest_run_id,
                ingested_at_utc,
            ]
            for r in rows
        ],
    )
    conn.commit()
    return int(cur.rowcount or 0)


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Ingest MT5 historical bars to LAB_DATA_ROOT (no external API).")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--lab-data-root", default="")
    ap.add_argument("--mt5-path", default=DEFAULT_MT5_EXE)
    ap.add_argument("--focus-group", default="FX")
    ap.add_argument("--timeframes", default="M1")
    ap.add_argument("--lookback-days", type=int, default=180)
    ap.add_argument("--overlap-minutes", type=int, default=30)
    ap.add_argument("--symbols", default="")
    ap.add_argument("--max-bars-per-symbol", type=int, default=200000)
    ap.add_argument("--out", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    started = dt.datetime.now(tz=UTC)
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve() if str(args.lab_data_root).strip() else resolve_lab_data_root(root)
    run_id = f"INGEST_{started.strftime('%Y%m%dT%H%M%SZ')}"

    report_path = (
        Path(args.out).resolve()
        if str(args.out).strip()
        else (lab_data_root / "reports" / "ingest" / f"lab_mt5_ingest_{started.strftime('%Y%m%dT%H%M%SZ')}.json").resolve()
    )
    report_path = ensure_write_parent(report_path, root=root, lab_data_root=lab_data_root)
    operator_txt = ensure_write_parent(
        (root / "LAB" / "EVIDENCE" / "ingest" / "lab_mt5_ingest_latest.txt").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    operator_json = ensure_write_parent(
        (root / "LAB" / "EVIDENCE" / "ingest" / "lab_mt5_ingest_latest.json").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )

    registry_path = ensure_write_parent(
        (lab_data_root / "registry" / "lab_registry.sqlite").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )
    dataset_sqlite = ensure_write_parent(
        (lab_data_root / "data_curated" / "mt5_history.sqlite").resolve(),
        root=root,
        lab_data_root=lab_data_root,
    )

    report: Dict[str, Any] = {
        "schema": "oanda_mt5.lab_mt5_ingest.v1",
        "run_id": run_id,
        "started_at_utc": iso_utc(started),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "mt5_path": str(args.mt5_path),
        "status": "INIT",
    }

    try:
        try:
            import MetaTrader5 as mt5  # type: ignore
        except Exception as exc:
            reexec_rc = _reexec_with_py312_if_available()
            if reexec_rc is not None:
                return int(reexec_rc)
            raise RuntimeError(f"Import MetaTrader5 failed: {type(exc).__name__}:{exc}") from exc

        strategy_cfg = load_json((root / "CONFIG" / "strategy.json").resolve())
        symbols = [s.strip().upper() for s in str(args.symbols or "").split(",") if s.strip()]
        if not symbols:
            symbols = _symbols_for_group(strategy_cfg, str(args.focus_group).upper())
        if not symbols:
            raise RuntimeError(f"No symbols resolved for focus_group={args.focus_group}")

        tfs = [x.strip().upper() for x in str(args.timeframes or "M1").split(",") if x.strip()]
        if not tfs:
            tfs = ["M1"]

        ok = bool(mt5.initialize(str(args.mt5_path)))
        if not ok:
            raise RuntimeError(f"mt5.initialize=False last_error={mt5.last_error()!r}")
        account = mt5.account_info()
        if account is None:
            raise RuntimeError(f"mt5.account_info=None last_error={mt5.last_error()!r}")
        term = mt5.terminal_info()
        terminal_name = str(getattr(term, "name", "UNKNOWN")) if term is not None else "UNKNOWN"

        conn_data = sqlite3.connect(str(dataset_sqlite), timeout=20)
        conn_data.row_factory = sqlite3.Row
        conn_data.execute("PRAGMA busy_timeout=20000;")
        conn_data.execute("PRAGMA journal_mode=WAL;")
        _create_history_schema(conn_data)

        conn_reg = connect_registry(registry_path)
        init_registry_schema(conn_reg)

        details: List[Dict[str, Any]] = []
        inserted_total = 0
        dedup_total = 0
        end_utc = dt.datetime.now(tz=UTC)

        for symbol in symbols:
            if not bool(mt5.symbol_select(symbol, True)):
                details.append({"symbol": symbol, "status": "SKIP_SYMBOL_SELECT_FAIL"})
                continue
            for tf in tfs:
                tf_mt5 = _tf_to_mt5(tf, mt5)
                wm = get_ingest_watermark(conn_reg, source_type="MT5", symbol=symbol, timeframe=tf)
                wm_dt = parse_ts_utc(wm)
                if wm_dt is None:
                    start_utc = end_utc - dt.timedelta(days=max(1, int(args.lookback_days)))
                else:
                    start_utc = wm_dt - dt.timedelta(minutes=max(0, int(args.overlap_minutes)))
                rates = mt5.copy_rates_range(symbol, tf_mt5, start_utc, end_utc)
                if rates is None:
                    details.append(
                        {
                            "symbol": symbol,
                            "timeframe": tf,
                            "status": "FAIL_COPY_RATES",
                            "last_error": repr(mt5.last_error()),
                            "start_utc": iso_utc(start_utc),
                            "end_utc": iso_utc(end_utc),
                        }
                    )
                    continue
                rows_raw = rates.tolist() if hasattr(rates, "tolist") else list(rates)
                if len(rows_raw) > int(args.max_bars_per_symbol):
                    rows_raw = rows_raw[-int(args.max_bars_per_symbol) :]
                rows: List[Dict[str, Any]] = []
                for r in rows_raw:
                    ts = int(r["time"]) if isinstance(r, dict) else int(r[0])
                    ts_utc = dt.datetime.fromtimestamp(ts, tz=UTC).replace(microsecond=0)
                    if isinstance(r, dict):
                        rr = r
                    else:
                        rr = {
                            "open": r[1],
                            "high": r[2],
                            "low": r[3],
                            "close": r[4],
                            "tick_volume": r[5],
                            "spread": r[6],
                            "real_volume": r[7],
                        }
                    rows.append(
                        {
                            "ts_utc": iso_utc(ts_utc),
                            "open": float(rr["open"]),
                            "high": float(rr["high"]),
                            "low": float(rr["low"]),
                            "close": float(rr["close"]),
                            "tick_volume": int(rr.get("tick_volume") or 0),
                            "spread": int(rr.get("spread") or 0),
                            "real_volume": int(rr.get("real_volume") or 0),
                        }
                    )
                inserted = _insert_rates(
                    conn_data,
                    symbol=symbol,
                    timeframe=tf,
                    rows=rows,
                    source_terminal=terminal_name,
                    ingest_run_id=run_id,
                    ingested_at_utc=iso_utc(dt.datetime.now(tz=UTC)),
                )
                dedup = max(0, len(rows) - inserted)
                inserted_total += int(inserted)
                dedup_total += int(dedup)

                max_ts = rows[-1]["ts_utc"] if rows else wm
                if max_ts:
                    upsert_ingest_watermark(
                        conn_reg,
                        source_type="MT5",
                        symbol=symbol,
                        timeframe=tf,
                        last_ts_utc=str(max_ts),
                        updated_at_utc=iso_utc(dt.datetime.now(tz=UTC)),
                    )
                details.append(
                    {
                        "symbol": symbol,
                        "timeframe": tf,
                        "status": "PASS",
                        "rows_fetched": len(rows),
                        "rows_inserted": int(inserted),
                        "rows_deduped": int(dedup),
                        "start_utc": iso_utc(start_utc),
                        "end_utc": iso_utc(end_utc),
                        "watermark_after": max_ts,
                    }
                )

        conn_data.close()
        dataset_hash = file_sha256(dataset_sqlite)
        config_hash = canonical_json_hash(
            {
                "focus_group": str(args.focus_group).upper(),
                "timeframes": tfs,
                "symbols": symbols,
                "lookback_days": int(args.lookback_days),
                "overlap_minutes": int(args.overlap_minutes),
                "max_bars_per_symbol": int(args.max_bars_per_symbol),
            }
        )

        finished = dt.datetime.now(tz=UTC)
        status = "PASS" if any(d.get("status") == "PASS" for d in details) else "SKIP"
        reason = "INGEST_OK" if status == "PASS" else "NO_DATA_FETCHED"

        report.update(
            {
                "finished_at_utc": iso_utc(finished),
                "status": status,
                "reason": reason,
                "source_type": "MT5",
                "terminal": {
                    "name": terminal_name,
                    "connected": bool(getattr(term, "connected", False)) if term is not None else None,
                    "trade_allowed": bool(getattr(term, "trade_allowed", False)) if term is not None else None,
                    "account_login": int(getattr(account, "login", 0) or 0),
                    "account_server": str(getattr(account, "server", "") or ""),
                },
                "dataset_path": str(dataset_sqlite),
                "dataset_hash": dataset_hash,
                "config_hash": config_hash,
                "summary": {
                    "symbols_requested": len(symbols),
                    "timeframes_requested": tfs,
                    "rows_inserted_total": int(inserted_total),
                    "rows_deduped_total": int(dedup_total),
                },
                "details": details,
            }
        )
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        insert_job_run(
            conn_reg,
            {
                "run_id": run_id,
                "run_type": "INGEST_MT5",
                "started_at_utc": report["started_at_utc"],
                "finished_at_utc": report["finished_at_utc"],
                "status": status,
                "source_type": "MT5",
                "dataset_hash": dataset_hash,
                "config_hash": config_hash,
                "readiness": "N/A",
                "reason": reason,
                "evidence_path": str(report_path),
                "details_json": json.dumps(
                    {
                        "rows_inserted_total": int(inserted_total),
                        "rows_deduped_total": int(dedup_total),
                        "symbols": symbols,
                        "timeframes": tfs,
                    },
                    ensure_ascii=False,
                ),
            },
        )
        conn_reg.close()

        operator_payload = {
            "schema": "oanda_mt5.lab_mt5_ingest_pointer.v1",
            "generated_at_utc": iso_utc(dt.datetime.now(tz=UTC)),
            "status": status,
            "reason": reason,
            "rows_inserted_total": int(inserted_total),
            "rows_deduped_total": int(dedup_total),
            "symbols_requested": len(symbols),
            "report_path": str(report_path),
            "dataset_path": str(dataset_sqlite),
            "dataset_hash": dataset_hash,
        }
        operator_json.write_text(json.dumps(operator_payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        operator_txt.write_text(
            "\n".join(
                [
                    "LAB_MT5_INGEST",
                    f"Status: {status}",
                    f"Reason: {reason}",
                    f"Rows inserted: {inserted_total}",
                    f"Rows deduped: {dedup_total}",
                    f"Symbols: {len(symbols)}",
                    f"Report: {report_path}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        print(
            f"LAB_MT5_INGEST_OK status={status} rows_inserted={inserted_total} rows_deduped={dedup_total} out={report_path}"
        )
        return 0 if status in {"PASS", "SKIP"} else 1
    except Exception as exc:
        finished = dt.datetime.now(tz=UTC)
        report.update(
            {
                "finished_at_utc": iso_utc(finished),
                "status": "FAIL",
                "reason": f"{type(exc).__name__}",
                "error": str(exc),
            }
        )
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        operator_txt.write_text(
            "\n".join(
                [
                    "LAB_MT5_INGEST",
                    "Status: FAIL",
                    f"Reason: {type(exc).__name__}",
                    f"Error: {exc}",
                    f"Report: {report_path}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )
        try:
            conn_reg = connect_registry(registry_path)
            init_registry_schema(conn_reg)
            insert_job_run(
                conn_reg,
                {
                    "run_id": run_id,
                    "run_type": "INGEST_MT5",
                    "started_at_utc": report.get("started_at_utc", iso_utc(started)),
                    "finished_at_utc": report["finished_at_utc"],
                    "status": "FAIL",
                    "source_type": "MT5",
                    "dataset_hash": "",
                    "config_hash": "",
                    "readiness": "N/A",
                    "reason": f"{type(exc).__name__}",
                    "evidence_path": str(report_path),
                    "details_json": json.dumps({"error": str(exc)}, ensure_ascii=False),
                },
            )
            conn_reg.close()
        except Exception:
            pass
        print(f"LAB_MT5_INGEST_FAIL reason={type(exc).__name__} out={report_path}")
        return 1
    finally:
        try:
            import MetaTrader5 as mt5  # type: ignore

            mt5.shutdown()
        except Exception:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
