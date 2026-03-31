from __future__ import annotations

import argparse
import csv
import json
from bisect import bisect_right
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple


DEFAULT_PROJECT_ROOT = Path(r"C:\MAKRO_I_MIKRO_BOT")
DEFAULT_COMMON_ROOT = Path(
    r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Builds offline training dataset scaffold.")
    parser.add_argument("--project-root", default=str(DEFAULT_PROJECT_ROOT))
    parser.add_argument("--common-root", default=str(DEFAULT_COMMON_ROOT))
    return parser.parse_args()


def detect_delimiter(path: Path) -> str:
    header = path.read_text(encoding="utf-8-sig", errors="ignore").splitlines()[0]
    return "\t" if "\t" in header else ","


def read_csv_rows(path: Path) -> List[Dict[str, str]]:
    if not path.exists():
        return []
    delimiter = detect_delimiter(path)
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def read_jsonl_rows(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    if not path.exists():
        return rows
    for raw in path.read_text(encoding="utf-8-sig", errors="ignore").splitlines():
        line = raw.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def parse_ts(value: Any) -> int:
    try:
        return int(float(str(value)))
    except Exception:
        return 0


def build_index(rows: List[Dict[str, Any]], ts_key: str) -> Tuple[List[int], List[Dict[str, Any]]]:
    ordered = sorted(rows, key=lambda row: parse_ts(row.get(ts_key)))
    return [parse_ts(row.get(ts_key)) for row in ordered], ordered


def find_latest_before(ts_values: List[int], rows: List[Dict[str, Any]], target_ts: int) -> Dict[str, Any]:
    if not ts_values:
        return {}
    idx = bisect_right(ts_values, target_ts) - 1
    if idx < 0:
        return {}
    return rows[idx]


def main() -> int:
    args = parse_args()
    project_root = Path(args.project_root)
    common_root = Path(args.common_root)
    logs_root = common_root / "logs"
    output_root = project_root / "EVIDENCE" / "ML"
    output_root.mkdir(parents=True, exist_ok=True)

    dataset_rows: List[Dict[str, Any]] = []
    symbol_summaries: List[Dict[str, Any]] = []

    for symbol_dir in sorted([p for p in logs_root.iterdir() if p.is_dir() and not p.name.startswith("_")]):
        symbol = symbol_dir.name
        learning_rows = read_csv_rows(symbol_dir / "learning_observations_v2.csv")
        onnx_rows = read_csv_rows(symbol_dir / "onnx_observations.csv")
        ledger_rows = read_csv_rows(symbol_dir / "broker_net_ledger_runtime.csv")
        transaction_rows = read_jsonl_rows(symbol_dir / "trade_transactions.jsonl")

        onnx_ts, onnx_index = build_index(onnx_rows, "ts")
        ledger_ts, ledger_index = build_index(ledger_rows, "ts")
        txn_ts, txn_index = build_index(transaction_rows, "ts")

        for learning in learning_rows:
            lesson_ts = parse_ts(learning.get("ts"))
            nearest_onnx = find_latest_before(onnx_ts, onnx_index, lesson_ts)
            nearest_ledger = find_latest_before(ledger_ts, ledger_index, lesson_ts)
            nearest_txn = find_latest_before(txn_ts, txn_index, lesson_ts)
            dataset_rows.append(
                {
                    "symbol": symbol,
                    "lesson_ts": lesson_ts,
                    "setup_type": learning.get("setup_type", ""),
                    "market_regime": learning.get("market_regime", ""),
                    "spread_regime": learning.get("spread_regime", ""),
                    "execution_regime": learning.get("execution_regime", ""),
                    "confidence_bucket": learning.get("confidence_bucket", ""),
                    "confidence_score": learning.get("confidence_score", ""),
                    "side": learning.get("side", ""),
                    "pnl": learning.get("pnl", ""),
                    "close_reason": learning.get("close_reason", ""),
                    "teacher_score": nearest_onnx.get("teacher_score", ""),
                    "symbol_score": nearest_onnx.get("symbol_score", ""),
                    "onnx_reason_code": nearest_onnx.get("reason_code", ""),
                    "ledger_net_pln": nearest_ledger.get("net_pln", ""),
                    "ledger_side": nearest_ledger.get("side", ""),
                    "trade_txn_type": nearest_txn.get("trans_type", ""),
                }
            )

        symbol_summaries.append(
            {
                "symbol": symbol,
                "learning_rows": len(learning_rows),
                "onnx_rows": len(onnx_rows),
                "ledger_rows": len(ledger_rows),
                "trade_transaction_rows": len(transaction_rows),
            }
        )

    csv_path = output_root / "training_dataset_latest.csv"
    json_path = output_root / "training_dataset_latest.json"

    fieldnames = [
        "symbol",
        "lesson_ts",
        "setup_type",
        "market_regime",
        "spread_regime",
        "execution_regime",
        "confidence_bucket",
        "confidence_score",
        "side",
        "pnl",
        "close_reason",
        "teacher_score",
        "symbol_score",
        "onnx_reason_code",
        "ledger_net_pln",
        "ledger_side",
        "trade_txn_type",
    ]
    with csv_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(dataset_rows)

    manifest = {
        "schema_version": "1.0",
        "generated_at_local": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "dataset_csv": str(csv_path),
        "row_count": len(dataset_rows),
        "symbols": symbol_summaries,
    }
    json_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"WROTE {csv_path} and {json_path} rows={len(dataset_rows)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
