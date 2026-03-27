from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


DEFAULT_SYMBOLS = [
    "EURUSD",
    "AUDUSD",
    "GBPUSD",
    "USDJPY",
    "USDCAD",
    "USDCHF",
    "NZDUSD",
    "EURJPY",
    "GBPJPY",
    "EURAUD",
    "GOLD",
    "SILVER",
    "COPPER-US",
    "DE30",
    "US500",
]


@dataclass(slots=True)
class CompatPaths:
    project_root: Path
    research_root: Path
    common_state_root: Path

    @classmethod
    def create(
        cls,
        project_root: str | Path = r"C:\MAKRO_I_MIKRO_BOT",
        research_root: str | Path = r"C:\TRADING_DATA\RESEARCH",
        common_state_root: str | Path | None = None,
    ) -> "CompatPaths":
        if common_state_root is None:
            common_state_root = os.environ.get(
                "MB_MT5_COMMON_FILES",
                r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
            )
        return cls(
            project_root=Path(project_root),
            research_root=Path(research_root),
            common_state_root=Path(common_state_root),
        )

    @property
    def tools_dir(self) -> Path:
        return self.project_root / "TOOLS"

    @property
    def run_dir(self) -> Path:
        return self.project_root / "RUN"

    @property
    def mql5_profiles_dir(self) -> Path:
        return self.project_root / "MQL5" / "Include" / "Profiles"

    @property
    def config_dir(self) -> Path:
        return self.project_root / "CONFIG"

    @property
    def evidence_ops_dir(self) -> Path:
        return self.project_root / "EVIDENCE" / "OPS"

    @property
    def datasets_dir(self) -> Path:
        return self.research_root / "datasets"

    @property
    def contracts_dir(self) -> Path:
        return self.research_root / "datasets" / "contracts"

    @property
    def reports_dir(self) -> Path:
        return self.research_root / "reports"

    @property
    def models_dir(self) -> Path:
        return self.research_root / "models"

    @property
    def global_model_dir(self) -> Path:
        return self.models_dir / "paper_gate_acceptor"

    @property
    def symbol_models_dir(self) -> Path:
        return self.models_dir / "paper_gate_acceptor_by_symbol"

    @property
    def candidate_signals_norm_latest(self) -> Path:
        return self.contracts_dir / "candidate_signals_norm_latest.parquet"

    @property
    def onnx_observations_norm_latest(self) -> Path:
        return self.contracts_dir / "onnx_observations_norm_latest.parquet"

    @property
    def learning_observations_v2_norm_latest(self) -> Path:
        return self.contracts_dir / "learning_observations_v2_norm_latest.parquet"

    @property
    def qdm_minute_bars_latest(self) -> Path:
        return self.datasets_dir / "qdm_minute_bars_latest.parquet"

    @property
    def research_contract_manifest_latest(self) -> Path:
        return self.reports_dir / "research_contract_manifest_latest.json"

    @property
    def execution_ping_contract_csv(self) -> Path:
        return self.common_state_root / "state" / "_global" / "execution_ping_contract.csv"

    @property
    def runtime_state_latest(self) -> Path:
        return self.common_state_root / "state" / "_global" / "runtime_state_latest.parquet"

    @property
    def paper_live_feedback_latest(self) -> Path:
        return self.common_state_root / "paper_live_feedback_latest.json"

    @property
    def broker_net_ledger_latest(self) -> Path:
        return self.contracts_dir / "broker_net_ledger_latest.parquet"

    @property
    def server_parity_tail_bridge_latest(self) -> Path:
        return self.contracts_dir / "server_parity_tail_bridge_latest.parquet"

    @property
    def onnx_symbol_registry_latest(self) -> Path:
        return self.models_dir / "onnx_symbol_registry_latest.json"

    @property
    def onnx_symbol_registry_latest_alt(self) -> Path:
        return self.symbol_models_dir / "onnx_symbol_registry_latest.json"
