import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "TOOLS" / "post_unlock_entry_test.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("post_unlock_entry_test", MODULE_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_post_unlock_entry_test_downgrades_trade_disabled_in_paper_mode(tmp_path: Path) -> None:
    module = _load_module()
    config_dir = tmp_path / "CONFIG"
    config_dir.mkdir(parents=True, exist_ok=True)
    (config_dir / "strategy.json").write_text('{"paper_trading": true}', encoding="utf-8")

    strategy_mode = module._load_strategy_mode(tmp_path)
    verdict, reason, hints = module._decide_verdict(
        counts={
            "entry_ready": 0,
            "entry_signal": 0,
            "dispatch": 0,
            "dispatch_reject": 0,
            "order_success": 0,
            "order_failed": 0,
        },
        retcodes={"10017": 1},
        paper_trading=bool(strategy_mode["paper_trading"]),
    )

    assert strategy_mode["strategy_loaded"] is True
    assert verdict == "WARN_TRADE_DISABLED_PAPER_MODE"
    assert "paper_trading mode" in reason
    assert any("CONFIG\\strategy.json" in hint for hint in hints)


def test_post_unlock_entry_test_keeps_hard_fail_outside_paper_mode() -> None:
    module = _load_module()
    verdict, reason, hints = module._decide_verdict(
        counts={
            "entry_ready": 0,
            "entry_signal": 0,
            "dispatch": 0,
            "dispatch_reject": 0,
            "order_success": 0,
            "order_failed": 0,
        },
        retcodes={"10017": 2},
        paper_trading=False,
    )

    assert verdict == "FAIL_TRADE_DISABLED"
    assert "retcode=10017" in reason
    assert any("MASTER" in hint for hint in hints)
