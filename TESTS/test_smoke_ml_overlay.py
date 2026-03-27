from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

import numpy as np
import pandas as pd

PATCH_ROOT = Path(__file__).resolve().parents[1]
os.environ["MB_DISABLE_LIGHTGBM"] = "1"
TOOLS_DIR = PATCH_ROOT / "TOOLS"
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from mb_ml_core.paths import CompatPaths
from mb_ml_core.trainer import train_all_symbol_models, train_global_model, TrainingThresholds


# Środowisko oceny nie ma silnika parquet. W teście podmieniamy parquet na pickle
# przy zachowaniu tych samych nazw plików, żeby zweryfikować logikę patcha.
_ORIG_READ_PARQUET = pd.read_parquet
_ORIG_TO_PARQUET = pd.DataFrame.to_parquet


def _fake_read_parquet(path, *args, **kwargs):
    return pd.read_pickle(path)


def _fake_to_parquet(self, path, *args, **kwargs):
    return self.to_pickle(path)


pd.read_parquet = _fake_read_parquet
pd.DataFrame.to_parquet = _fake_to_parquet



def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def build_fake_repo(tmp_path: Path) -> CompatPaths:
    project_root = tmp_path / "MAKRO_I_MIKRO_BOT"
    research_root = tmp_path / "TRADING_DATA" / "RESEARCH"
    common_state_root = tmp_path / "MT5_COMMON" / "MAKRO_I_MIKRO_BOT"

    for path in [
        project_root / "CONFIG",
        project_root / "MQL5" / "Include" / "Profiles",
        project_root / "EVIDENCE" / "OPS",
        research_root / "datasets" / "contracts",
        research_root / "reports",
        research_root / "models",
        common_state_root / "state" / "_global",
        common_state_root / "state" / "GOLD",
        common_state_root / "state" / "US500",
    ]:
        path.mkdir(parents=True, exist_ok=True)

    symbols = ["GOLD", "US500", "EURUSD"]
    _write_json(project_root / "CONFIG" / "microbots_registry.json", {"symbols": {s: {"enabled": True} for s in symbols}})
    _write_json(project_root / "CONFIG" / "family_policy_registry.json", {"default": {"account_currency": "PLN", "fx_to_pln_default": 1.0}})

    (project_root / "MQL5" / "Include" / "Profiles" / "Profile_GOLD.mqh").write_text(
        "input double TickSize = 0.01;\ninput double TickValue = 1.0;\ninput double CommissionPerLot = 0.0;\n",
        encoding="utf-8",
    )

    _write_json(common_state_root / "state" / "GOLD" / "broker_profile.json", {
        "symbol_alias": "GOLD",
        "broker_symbol": "XAUUSD",
        "tick_size": 0.01,
        "tick_value_account_ccy": 1.0,
        "commission_per_lot_account_ccy": 0.0,
        "swap_long_account_ccy": 0.0,
        "swap_short_account_ccy": 0.0,
        "extra_fee_account_ccy": 0.0,
        "fx_to_pln_default": 1.0,
        "account_currency": "PLN",
    })
    _write_json(common_state_root / "state" / "US500" / "broker_profile.json", {
        "symbol_alias": "US500",
        "broker_symbol": "US500",
        "tick_size": 0.1,
        "tick_value_account_ccy": 1.0,
        "commission_per_lot_account_ccy": 0.0,
        "swap_long_account_ccy": 0.0,
        "swap_short_account_ccy": 0.0,
        "extra_fee_account_ccy": 0.0,
        "fx_to_pln_default": 1.0,
        "account_currency": "PLN",
    })
    _write_json(common_state_root / "paper_live_feedback_latest.json", {"rows": []})

    now = pd.Timestamp("2026-01-01 00:00:00", tz="UTC")
    rows = []
    runtime_rows = []
    learning_rows = []
    qdm_rows = []
    for i in range(400):
        ts = now + pd.Timedelta(minutes=15 * i)
        symbol = "GOLD" if i % 2 == 0 else "US500"
        score = 0.4 + ((i % 11) / 10.0)
        conf = 0.3 + ((i % 7) / 10.0)
        spread = 10.0 + (i % 5)
        pnl = (10 if i % 3 else -8) + (3 if symbol == "GOLD" else -2)
        outcome_key = f"ok_{i}"
        feedback_key = f"fb_{i}"

        rows.append({
            "ts": int(ts.timestamp()),
            "symbol_alias": symbol,
            "stage": "CANDIDATE",
            "accepted": 1,
            "reason_code": "OK",
            "setup_type": "BREAKOUT" if i % 2 == 0 else "PULLBACK",
            "side": "BUY" if i % 2 == 0 else "SELL",
            "side_normalized": "BUY" if i % 2 == 0 else "SELL",
            "score": score,
            "confidence_score": conf,
            "risk_multiplier": 1.0,
            "lots": 1.0,
            "market_regime": "TREND" if i % 4 else "RANGE",
            "spread_regime": "LOW" if spread < 13 else "MID",
            "execution_regime": "NORMAL",
            "confidence_bucket": "MID",
            "candle_bias": "UP",
            "candle_quality_grade": "A",
            "candle_score": score * 0.8,
            "renko_bias": "UP",
            "renko_quality_grade": "B",
            "renko_score": score * 0.7,
            "renko_run_length": i % 6,
            "renko_reversal_flag": int(i % 5 == 0),
            "spread_points": spread,
            "feedback_key": feedback_key,
            "outcome_key": outcome_key,
            "advisory_match_key": outcome_key,
        })
        runtime_rows.append({
            "ts": int(ts.timestamp()),
            "symbol_alias": symbol,
            "stage": "LIVE",
            "runtime_channel": "paper-live",
            "available": 1,
            "teacher_available": 1,
            "teacher_used": 1,
            "teacher_score": 0.52 + (score * 0.1),
            "symbol_score": 0.51 + (conf * 0.1),
            "latency_us": 5000 + (i % 1000),
            "reason_code": "OK",
            "signal_valid": 1,
            "setup_type": "BREAKOUT" if i % 2 == 0 else "PULLBACK",
            "market_regime": "TREND" if i % 4 else "RANGE",
            "spread_regime": "LOW" if spread < 13 else "MID",
            "confidence_bucket": "MID",
            "score": score,
            "confidence_score": conf,
            "spread_points": spread,
            "feedback_key": feedback_key,
        })
        learning_rows.append({
            "schema_version": "2.0",
            "ts": int((ts + pd.Timedelta(minutes=5)).timestamp()),
            "symbol_alias": symbol,
            "setup_type": "BREAKOUT" if i % 2 == 0 else "PULLBACK",
            "market_regime": "TREND" if i % 4 else "RANGE",
            "spread_regime": "LOW" if spread < 13 else "MID",
            "execution_regime": "NORMAL",
            "confidence_bucket": "MID",
            "confidence_score": conf,
            "candle_bias": "UP",
            "candle_quality_grade": "A",
            "candle_score": score * 0.8,
            "renko_bias": "UP",
            "renko_quality_grade": "B",
            "renko_score": score * 0.7,
            "renko_run_length": i % 6,
            "renko_reversal_flag": int(i % 5 == 0),
            "side": "BUY" if i % 2 == 0 else "SELL",
            "side_normalized": "BUY" if i % 2 == 0 else "SELL",
            "pnl": pnl,
            "close_reason": "TP" if pnl > 0 else "SL",
            "outcome_key": outcome_key,
            "advisory_match_key": outcome_key,
        })
        qdm_rows.append({
            "symbol_alias": symbol,
            "bar_minute": ts.floor("min").isoformat(),
            "tick_count": 30 + (i % 10),
            "spread_mean": spread * 0.9,
            "spread_max": spread * 1.2,
            "mid_range_1m": 0.001 + (i % 5) * 0.0001,
            "mid_return_1m": 0.0002 * ((i % 7) - 3),
        })

    pd.DataFrame(rows).to_parquet(research_root / "datasets" / "contracts" / "candidate_signals_norm_latest.parquet", index=False)
    pd.DataFrame(runtime_rows).to_parquet(research_root / "datasets" / "contracts" / "onnx_observations_norm_latest.parquet", index=False)
    pd.DataFrame(learning_rows).to_parquet(research_root / "datasets" / "contracts" / "learning_observations_v2_norm_latest.parquet", index=False)
    pd.DataFrame(qdm_rows).to_parquet(research_root / "datasets" / "qdm_minute_bars_latest.parquet", index=False)
    pd.DataFrame([{
        "symbol_alias": "_global",
        "ts": int(now.timestamp()),
        "server_operational_ping_ms": 7.0,
        "server_terminal_ping_ms": 6.0,
        "server_local_latency_us_avg": 4000.0,
        "server_local_latency_us_max": 8000.0,
        "server_ping_contract_enabled": 1,
    }]).to_csv(common_state_root / "state" / "_global" / "execution_ping_contract.csv", index=False)

    return CompatPaths.create(project_root=project_root, research_root=research_root, common_state_root=common_state_root)


def test_smoke_training_cycle():
    with tempfile.TemporaryDirectory() as tmp:
        paths = build_fake_repo(Path(tmp))
        thresholds = TrainingThresholds(
            global_train_days=2,
            global_valid_days=1,
            global_step_days=1,
            min_train_rows=40,
            min_valid_rows=10,
            min_symbol_labeled_rows=30,
            min_symbol_train_rows=20,
            min_symbol_valid_rows=8,
        )

        global_payload = train_global_model(paths, export_onnx=False, thresholds=thresholds)
        assert (paths.global_model_dir / "paper_gate_acceptor_latest.joblib").exists()
        assert "metrics" in global_payload

        symbol_payload = train_all_symbol_models(paths, export_onnx=False, thresholds=thresholds)
        assert (paths.onnx_symbol_registry_latest).exists()
        assert "symbols" in symbol_payload
        assert "GOLD" in symbol_payload["symbols"]
