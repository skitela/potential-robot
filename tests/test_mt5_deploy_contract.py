import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TestMt5DeployContract(unittest.TestCase):
    def test_deploy_script_copies_shadow_kernel_includes(self) -> None:
        script = (ROOT / "Aktualizuj_EA.bat").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            "KernelTypes_v1.mqh",
            "StateCache_v1.mqh",
            "InstrumentProfileCache_v2.mqh",
            "LiveConfigLoader_v2.mqh",
            "CircuitBreaker_v2.mqh",
            "DecisionKernel_v1.mqh",
            "HybridAgent.ex5",
            "copy_if_needed.ps1",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Deploy script missing token: {token}")

    def test_deploy_script_selects_active_terminal_dir_by_server_and_recency(self) -> None:
        script = (ROOT / "Aktualizuj_EA.bat").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            "Get-IniValue",
            "MetaQuotes\\Terminal",
            "Section 'Common' -Key 'Server'",
            "LastWriteTimeUtc.ToFileTimeUtc()",
            "$score += 1000",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Deploy script missing active-dir selector token: {token}")

    def test_deploy_script_allows_locked_but_identical_runtime_libs(self) -> None:
        script = (ROOT / "Aktualizuj_EA.bat").read_text(encoding="utf-8", errors="ignore")
        helper = (ROOT / "TOOLS" / "copy_if_needed.ps1").read_text(encoding="utf-8", errors="ignore")
        self.assertIn("copy_if_needed.ps1", script)
        required_tokens = (
            "Get-FileHash -Path $Path -Algorithm SHA256",
            "LOCKED_MATCH",
            "UNCHANGED",
            "Copy-Item -Force -LiteralPath $Source -Destination $Destination -ErrorAction Stop",
        )
        for token in required_tokens:
            self.assertIn(token, helper, f"Copy helper missing token: {token}")

    def test_deploy_script_resolves_python_with_metatrader5_for_mt5_tools(self) -> None:
        script = (ROOT / "Aktualizuj_EA.bat").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            ":resolve_mt5_python",
            ":run_mt5_python",
            ":python_can_import_mt5",
            "Python with MetaTrader5 package not found - symbol select skipped.",
            "C:\\Users\\skite\\AppData\\Local\\Programs\\Python\\Python312\\python.exe",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Deploy script missing MT5 Python resolver token: {token}")

    def test_deploy_script_normalizes_compile_and_diag_status(self) -> None:
        script = (ROOT / "Aktualizuj_EA.bat").read_text(encoding="utf-8", errors="ignore")
        required_tokens = (
            ":compile_hybrid_agent",
            "Compile failed and HybridAgent.ex5 is missing",
            "Compile not clean, but HybridAgent.ex5 exists and will be used.",
            "for /L %%N in (1,1,3) do",
            "Diagnostic not ready yet",
            "MT5_FULL_DIAG_*.txt",
            "Compile OK",
            "Result: 0 errors, 0 warnings",
            "WARN_TRADE_DISABLED_PAPER_MODE",
            "WARN_RECENT_TRADE_DISABLED_IN_LOGS",
            "Diagnostic accepted warning verdict",
            "[FINAL] Diag verdict :",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Deploy script missing compile/diag normalization token: {token}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
