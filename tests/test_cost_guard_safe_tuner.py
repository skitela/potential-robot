import json
from pathlib import Path

from TOOLS.cost_guard_safe_tuner import apply_profile, rollback_last, tuner_status


def _write_strategy(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def test_apply_profile_updates_config_and_records_state(tmp_path: Path) -> None:
    root = tmp_path
    _write_strategy(root / "CONFIG" / "strategy.json", {"cost_guard_auto_relax_min_total_decisions": 220})

    out = apply_profile(root=root, profile="fast_relax_stable", daily_limit=2, note="unit")
    assert out["status"] == "PASS"

    cfg = json.loads((root / "CONFIG" / "strategy.json").read_text(encoding="utf-8"))
    assert cfg["cost_guard_auto_relax_min_total_decisions"] == 120
    assert cfg["cost_guard_auto_relax_hysteresis_enabled"] is True

    state = json.loads((root / "RUN" / "cost_guard_safe_tuner_state.json").read_text(encoding="utf-8"))
    assert len(state.get("changes", [])) == 1
    assert state["changes"][0]["action"] == "apply"


def test_apply_profile_respects_daily_limit(tmp_path: Path) -> None:
    root = tmp_path
    _write_strategy(root / "CONFIG" / "strategy.json", {"cost_guard_auto_relax_min_total_decisions": 220})

    first = apply_profile(root=root, profile="fast_relax_stable", daily_limit=1, note="first")
    second = apply_profile(root=root, profile="fast_relax_stable", daily_limit=1, note="second")

    assert first["status"] == "PASS"
    assert second["status"] == "SKIP_DAILY_LIMIT"


def test_rollback_last_restores_previous_strategy(tmp_path: Path) -> None:
    root = tmp_path
    _write_strategy(root / "CONFIG" / "strategy.json", {"cost_guard_auto_relax_min_total_decisions": 220})

    apply = apply_profile(root=root, profile="fast_relax_stable", daily_limit=2, note="apply")
    assert apply["status"] == "PASS"

    rb = rollback_last(root=root, note="rollback")
    assert rb["status"] == "PASS"

    cfg = json.loads((root / "CONFIG" / "strategy.json").read_text(encoding="utf-8"))
    assert cfg["cost_guard_auto_relax_min_total_decisions"] == 220

    st = tuner_status(root=root)
    assert st["status"] == "PASS"
    assert st["changes_total"] >= 2
