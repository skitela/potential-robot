from __future__ import annotations

from pathlib import Path

import pytest

from TOOLS import lab_guardrails as lg


def test_write_guard_allows_lab_and_external_root(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    lab_data_root = tmp_path / "lab_data"
    lab_data_root.mkdir(parents=True, exist_ok=True)

    allowed_repo_target = root / "LAB" / "EVIDENCE" / "daily" / "x.json"
    allowed_external_target = lab_data_root / "reports" / "daily" / "x.json"

    lg.ensure_allowed_write(allowed_repo_target, root=root, lab_data_root=lab_data_root)
    lg.ensure_allowed_write(allowed_external_target, root=root, lab_data_root=lab_data_root)


def test_write_guard_blocks_runtime_paths(tmp_path: Path) -> None:
    root = tmp_path / "repo"
    root.mkdir(parents=True, exist_ok=True)
    lab_data_root = tmp_path / "lab_data"
    lab_data_root.mkdir(parents=True, exist_ok=True)

    blocked = root / "RUN" / "some_runtime_state.json"
    with pytest.raises(PermissionError):
        lg.ensure_allowed_write(blocked, root=root, lab_data_root=lab_data_root)

