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

    def test_live_config_loader_verifies_kernel_hash_contract(self) -> None:
        loader = (ROOT / "MQL5" / "Include" / "LiveConfigLoader_v2.mqh").read_text(
            encoding="utf-8", errors="ignore"
        )
        required_tokens = (
            "hash_method",
            "hash_scope",
            "sha256_sig_v1",
            "kernel_core_v1",
            "KERNEL_CONFIG_HASH_INVALID_FORMAT",
            "KERNEL_CONFIG_HASH_MISMATCH",
            "CryptEncode(CRYPT_HASH_SHA256",
        )
        for token in required_tokens:
            self.assertIn(token, loader, f"Missing loader hash-verification token: {token}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
