from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest


def _write_parquet(path: Path, rows: list[dict]) -> None:
    duckdb = pytest.importorskip("duckdb")
    import pandas as pd

    path.parent.mkdir(parents=True, exist_ok=True)
    df = pd.DataFrame(rows)
    con = duckdb.connect()
    con.register("df_view", df)
    con.execute("copy df_view to ? (format parquet)", [str(path)])
    con.close()


def test_ml_overlay_supervision_smoke(tmp_path: Path):
    pytest.importorskip("pandas")

    repo = tmp_path / "MAKRO_I_MIKRO_BOT"
    research = tmp_path / "TRADING_DATA" / "RESEARCH"
    common = tmp_path / "CommonFiles"

    (repo / "CONFIG").mkdir(parents=True)
    (repo / "EVIDENCE" / "OPS").mkdir(parents=True)
    (repo / "MQL5" / "Experts" / "MicroBots").mkdir(parents=True)
    (research / "models" / "paper_gate_acceptor").mkdir(parents=True)
    (research / "models" / "paper_gate_acceptor_by_symbol" / "EURUSD").mkdir(parents=True)
    (common / "MAKRO_I_MIKRO_BOT" / "state" / "_global").mkdir(parents=True)
    (common / "MAKRO_I_MIKRO_BOT" / "state" / "EURUSD").mkdir(parents=True)

    registry = {
        "schema_version": "1.1",
        "symbols": [
            {"symbol": "EURUSD", "code_symbol": "EURUSD", "expert": "MicroBot_EURUSD", "session_profile": "FX_MAIN"},
            {"symbol": "GBPJPY", "code_symbol": "GBPJPY", "expert": "MicroBot_GBPJPY", "session_profile": "FX_CROSS"},
        ],
    }
    (repo / "CONFIG" / "microbots_registry.json").write_text(json.dumps(registry), encoding="utf-8")

    (repo / "MQL5" / "Experts" / "MicroBots" / "MicroBot_EURUSD.mq5").write_text(
        '#include "..\\\\..\\\\Include\\\\Core\\\\MbMlRuntimeBridge.mqh"\nvoid x(){MbMlRuntimeBridgeApplyStudentGate(a,b,c,d,e,f,g,h,0.1);}\n',
        encoding="utf-8",
    )
    (repo / "MQL5" / "Experts" / "MicroBots" / "MicroBot_GBPJPY.mq5").write_text(
        '#include "..\\\\..\\\\Include\\\\Core\\\\MbMlRuntimeBridge.mqh"\n',
        encoding="utf-8",
    )

    _write_parquet(
        research / "datasets" / "contracts" / "server_parity_tail_bridge_latest.parquet",
        [
            {"symbol_alias": "EURUSD", "state": "OK"},
            {"symbol_alias": "GBPJPY", "state": "BRAK_SWIEZEGO_OGONA"},
        ],
    )
    _write_parquet(
        research / "datasets" / "contracts" / "broker_net_ledger_latest.parquet",
        [
            {"symbol_alias": "EURUSD", "net_pln": 1.0},
            {"symbol_alias": "EURUSD", "net_pln": 2.0},
        ],
    )
    _write_parquet(
        research / "datasets" / "contracts" / "candidate_signals_norm_latest.parquet",
        [{"symbol_alias": "EURUSD"}],
    )
    _write_parquet(
        research / "datasets" / "contracts" / "onnx_observations_norm_latest.parquet",
        [{"symbol_alias": "EURUSD"}],
    )
    _write_parquet(
        research / "datasets" / "contracts" / "learning_observations_v2_norm_latest.parquet",
        [{"symbol_alias": "EURUSD"}],
    )

    (research / "models" / "paper_gate_acceptor" / "paper_gate_acceptor_latest.onnx").write_text("x", encoding="utf-8")
    (research / "models" / "paper_gate_acceptor" / "paper_gate_acceptor_latest.joblib").write_text("x", encoding="utf-8")
    (research / "models" / "paper_gate_acceptor_mt5_package_latest.json").write_text(json.dumps({"symbols": ["EURUSD"]}), encoding="utf-8")
    (research / "models" / "paper_gate_acceptor_by_symbol" / "EURUSD" / "model.onnx").write_text("x", encoding="utf-8")

    sys.path.insert(0, str((Path(__file__).resolve().parents[1] / "TOOLS")))
    from mb_ml_supervision.paths import OverlayPaths
    from mb_ml_supervision.audits import build_overlay_audit
    from mb_ml_supervision.sync_runtime_state import sync_runtime_state

    paths = OverlayPaths.create(project_root=repo, research_root=research, common_state_root=common)
    audit = build_overlay_audit(paths)
    assert audit["active_fleet"]["count"] == 2
    assert audit["symbol_activity"]["training_modes"]["GBPJPY"] == "FALLBACK_ONLY"
    registry_payload = sync_runtime_state(paths)
    assert "EURUSD" in registry_payload["symbols"]
