import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class TestRuntimeLatencyAuditContract(unittest.TestCase):
    def test_bridge_soak_runner_resolves_python_explicitly(self) -> None:
        script = (ROOT / "TOOLS" / "run_bridge_soak_audit.ps1").read_text(
            encoding="utf-8", errors="ignore"
        )
        required_tokens = (
            "function Find-AuditPythonExe",
            'Join-Path $RuntimeRoot ".venv\\\\Scripts\\\\python.exe"',
            '"C:\\OANDA_VENV\\.venv\\Scripts\\python.exe"',
            'Get-Command python -ErrorAction SilentlyContinue',
            '$pythonExe = Find-AuditPythonExe -RuntimeRoot $Root',
            'SOAK_PYTHON=$pythonExe',
            '& $pythonExe (Join-Path $Root "TOOLS\\latency_stage2_section_profile.py")',
            '& $pythonExe (Join-Path $Root "TOOLS\\bridge_soak_compare.py")',
        )
        for token in required_tokens:
            self.assertIn(token, script, f"Missing soak-python token: {token}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
