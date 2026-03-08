import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TestHybridKernelShadowContract(unittest.TestCase):
    def test_hybrid_agent_contains_shadow_kernel_loader(self) -> None:
        mql = (ROOT / "MQL5" / "Experts" / "HybridAgent.mq5").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            "#include <KernelTypes_v1.mqh>",
            "#include <StateCache_v1.mqh>",
            "#include <InstrumentProfileCache_v2.mqh>",
            "#include <LiveConfigLoader_v2.mqh>",
            "#include <DecisionKernel_v1.mqh>",
            "InpKernelConfigRelativePath",
            "RefreshKernelConfigV2();",
            "EvaluateKernelShadowForCurrentSymbol(\"TICK\")",
            "CompareKernelShadowTradeParity(",
        )
        for token in required_tokens:
            self.assertIn(token, mql, f"Missing MQL5 shadow token: {token}")

    def test_new_loader_contract_files_exist(self) -> None:
        expected = (
            ROOT / "MQL5" / "Include" / "KernelTypes_v1.mqh",
            ROOT / "MQL5" / "Include" / "StateCache_v1.mqh",
            ROOT / "MQL5" / "Include" / "InstrumentProfileCache_v2.mqh",
            ROOT / "MQL5" / "Include" / "LiveConfigLoader_v2.mqh",
            ROOT / "MQL5" / "Include" / "CircuitBreaker_v2.mqh",
            ROOT / "MQL5" / "Include" / "DecisionKernel_v1.mqh",
        )
        for path in expected:
            self.assertTrue(path.exists(), f"Missing kernel include: {path}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
