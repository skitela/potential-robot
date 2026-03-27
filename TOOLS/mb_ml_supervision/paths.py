from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os


def _default_common_state_root() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    return Path(r"C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files")


@dataclass(frozen=True)
class OverlayPaths:
    project_root: Path
    research_root: Path
    common_state_root: Path

    @classmethod
    def create(
        cls,
        project_root: str | Path = r"C:\MAKRO_I_MIKRO_BOT",
        research_root: str | Path = r"C:\TRADING_DATA\RESEARCH",
        common_state_root: str | Path | None = None,
    ) -> "OverlayPaths":
        return cls(
            project_root=Path(project_root),
            research_root=Path(research_root),
            common_state_root=Path(common_state_root) if common_state_root else _default_common_state_root(),
        )

    @property
    def config_dir(self) -> Path:
        return self.project_root / "CONFIG"

    @property
    def evidence_ops_dir(self) -> Path:
        return self.project_root / "EVIDENCE" / "OPS"

    @property
    def models_dir(self) -> Path:
        return self.research_root / "models"

    @property
    def datasets_dir(self) -> Path:
        return self.research_root / "datasets"

    @property
    def contracts_dir(self) -> Path:
        return self.datasets_dir / "contracts"

    @property
    def candidate_contract_path(self) -> Path:
        return self.contracts_dir / "candidate_signals_norm_latest.parquet"

    @property
    def onnx_observations_contract_path(self) -> Path:
        return self.contracts_dir / "onnx_observations_norm_latest.parquet"

    @property
    def learning_contract_path(self) -> Path:
        return self.contracts_dir / "learning_observations_v2_norm_latest.parquet"

    @property
    def tail_bridge_path(self) -> Path:
        return self.contracts_dir / "server_parity_tail_bridge_latest.parquet"

    @property
    def broker_net_ledger_path(self) -> Path:
        return self.contracts_dir / "broker_net_ledger_latest.parquet"

    @property
    def qdm_minute_bars_path(self) -> Path:
        return self.datasets_dir / "qdm_minute_bars_latest.parquet"

    @property
    def package_json_path(self) -> Path:
        return self.models_dir / "paper_gate_acceptor_mt5_package_latest.json"

    @property
    def global_model_dir(self) -> Path:
        return self.models_dir / "paper_gate_acceptor"

    @property
    def global_model_joblib_path(self) -> Path:
        return self.global_model_dir / "paper_gate_acceptor_latest.joblib"

    @property
    def global_model_onnx_path(self) -> Path:
        return self.global_model_dir / "paper_gate_acceptor_latest.onnx"

    @property
    def global_metrics_path(self) -> Path:
        return self.global_model_dir / "paper_gate_acceptor_latest_metrics.json"

    @property
    def symbol_models_dir(self) -> Path:
        return self.models_dir / "paper_gate_acceptor_by_symbol"

    @property
    def onnx_symbol_registry_candidates(self) -> list[Path]:
        return [
            self.models_dir / "onnx_symbol_registry_latest.json",
            self.symbol_models_dir / "onnx_symbol_registry_latest.json",
            self.research_root / "onnx_symbol_registry_latest.json",
        ]

    @property
    def microbots_registry_path(self) -> Path:
        return self.config_dir / "microbots_registry.json"

    @property
    def family_policy_registry_path(self) -> Path:
        return self.config_dir / "family_policy_registry.json"

    @property
    def family_reference_registry_path(self) -> Path:
        return self.config_dir / "family_reference_registry.json"

    @property
    def runtime_symbol_state_root(self) -> Path:
        return self.common_state_root / "MAKRO_I_MIKRO_BOT" / "state"

    @property
    def runtime_global_state_dir(self) -> Path:
        return self.runtime_symbol_state_root / "_global"

    @property
    def runtime_logs_root(self) -> Path:
        return self.common_state_root / "MAKRO_I_MIKRO_BOT" / "logs"

    @property
    def runtime_root(self) -> Path:
        return self.common_state_root / "MAKRO_I_MIKRO_BOT"

    @property
    def sync_runtime_registry_path(self) -> Path:
        return self.runtime_global_state_dir / "student_gate_registry_latest.json"

    @property
    def overlay_audit_path(self) -> Path:
        return self.evidence_ops_dir / "ml_overlay_supervision_latest.json"

    @property
    def overlay_rollout_guard_path(self) -> Path:
        return self.evidence_ops_dir / "ml_overlay_rollout_guard_latest.json"

    @property
    def overlay_runtime_audit_path(self) -> Path:
        return self.evidence_ops_dir / "ml_runtime_bridge_audit_latest.json"

    @property
    def learning_wellbeing_path(self) -> Path:
        return self.evidence_ops_dir / "learning_wellbeing_latest.json"

    @property
    def instrument_training_readiness_path(self) -> Path:
        return self.evidence_ops_dir / "instrument_training_readiness_latest.json"

    @property
    def learning_source_audit_path(self) -> Path:
        return self.evidence_ops_dir / "learning_source_audit_latest.json"

    @property
    def ml_scalping_fit_audit_path(self) -> Path:
        return self.evidence_ops_dir / "ml_scalping_fit_audit_latest.json"

    @property
    def trade_transition_audit_path(self) -> Path:
        return self.evidence_ops_dir / "trade_transition_audit_latest.json"

    @property
    def paper_live_action_gap_audit_path(self) -> Path:
        return self.evidence_ops_dir / "paper_live_action_gap_audit_latest.json"

    @property
    def possible_mql5_microbot_dirs(self) -> list[Path]:
        return [
            self.project_root / "MQL5" / "Experts" / "MicroBots",
            self.project_root / "MQL5" / "Experts",
            self.project_root,
        ]

    def resolve_microbots_dir(self) -> Path:
        for candidate in self.possible_mql5_microbot_dirs:
            if candidate.exists():
                if list(candidate.glob("MicroBot_*.mq5")):
                    return candidate
        return self.project_root / "MQL5" / "Experts" / "MicroBots"

    @property
    def possible_profile_dirs(self) -> list[Path]:
        return [
            self.project_root / "MQL5" / "Include" / "Profiles",
            self.project_root / "MQL5" / "Include",
            self.project_root / "Include" / "Profiles",
        ]

    def resolve_profiles_dir(self) -> Path:
        for candidate in self.possible_profile_dirs:
            if candidate.exists():
                if list(candidate.glob("Profile_*.mqh")):
                    return candidate
        return self.project_root / "MQL5" / "Include" / "Profiles"
