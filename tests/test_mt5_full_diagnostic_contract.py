import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TestMt5FullDiagnosticContract(unittest.TestCase):
    def test_diagnostic_reads_strategy_mode_flags(self) -> None:
        script = (ROOT / "TOOLS" / "mt5_full_diagnostic.ps1").read_text(
            encoding="utf-8", errors="ignore"
        )
        required_tokens = (
            "function Get-StrategyModeFlags",
            'Join-Path $RepoRoot "CONFIG\\\\strategy.json"',
            "paper_trading = $true",
            "ConvertFrom-Json -ErrorAction Stop",
            "$strategyMode = Get-StrategyModeFlags -RepoRoot $repoRoot",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Missing strategy-mode token: {token}")

    def test_diagnostic_treats_trade_disabled_as_warning_in_paper_mode(self) -> None:
        script = (ROOT / "TOOLS" / "mt5_full_diagnostic.ps1").read_text(
            encoding="utf-8", errors="ignore"
        )
        required_tokens = (
            "WARN_TRADE_DISABLED_PAPER_MODE",
            "CONFIG\\\\strategy.json wskazuje paper_trading=true",
            "paper runtime",
            "live wymaga odblokowania flag trade_allowed/trade_expert",
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Missing paper-warning token: {token}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
