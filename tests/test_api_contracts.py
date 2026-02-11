import unittest
from pathlib import Path

from TOOLS.verify_api_contracts import verify_contracts


class TestApiContracts(unittest.TestCase):
    def test_contracts_v1_pass(self) -> None:
        root = Path(__file__).resolve().parents[1]
        schema = root / "SCHEMAS" / "api_contracts_v1.json"
        ok, issues = verify_contracts(root, schema)
        self.assertTrue(ok, f"API contracts failed: {issues}")


if __name__ == "__main__":
    raise SystemExit(unittest.main())
