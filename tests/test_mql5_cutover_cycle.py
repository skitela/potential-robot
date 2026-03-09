from __future__ import annotations

import json

from TOOLS.mql5_cutover_cycle import evaluate_cycle_status, main, should_ignore_probe_failure


def test_cycle_status_pass_when_readiness_pass() -> None:
    got = evaluate_cycle_status(
        probe_status="OK",
        readiness_status="PASS",
        parity_rows=500,
    )
    assert got == "PASS"


def test_cycle_status_review_required_when_no_active_peer() -> None:
    got = evaluate_cycle_status(
        probe_status="NO_ACTIVE_PEER",
        readiness_status="REVIEW_REQUIRED",
        parity_rows=0,
    )
    assert got == "REVIEW_REQUIRED"


def test_cycle_status_review_required_when_probe_runtime_missing() -> None:
    got = evaluate_cycle_status(
        probe_status="NO_ZMQ",
        readiness_status="REVIEW_REQUIRED",
        parity_rows=0,
    )
    assert got == "REVIEW_REQUIRED"


def test_ignore_probe_failure_only_for_no_active_peer() -> None:
    assert should_ignore_probe_failure("NO_ACTIVE_PEER", True) is True
    assert should_ignore_probe_failure("NO_ZMQ", True) is False
    assert should_ignore_probe_failure("FAILED", True) is False


def test_cycle_passes_window_cutover_thresholds_to_readiness(monkeypatch, tmp_path) -> None:
    root = tmp_path
    (root / "EVIDENCE" / "kernel_shadow").mkdir(parents=True, exist_ok=True)
    (root / "EVIDENCE" / "cutover").mkdir(parents=True, exist_ok=True)
    (root / "EVIDENCE" / "kernel_shadow" / "kernel_shadow_parity_report_latest.json").write_text(
        json.dumps({"summary": {"parity_rows": 10}}), encoding="utf-8"
    )
    (root / "EVIDENCE" / "cutover" / "mql5_cutover_readiness_latest.json").write_text(
        json.dumps({"status": "REVIEW_REQUIRED"}), encoding="utf-8"
    )
    calls = []

    def _fake_run_tool(args, _root):
        calls.append(list(args))
        return {"returncode": 0, "stdout": "", "stderr": "", "cmd": list(args)}

    monkeypatch.setattr("TOOLS.mql5_cutover_cycle._run_tool", _fake_run_tool)
    rc = main(
        [
            "--root",
            str(root),
            "--skip-probe",
            "--min-active-windows",
            "2",
            "--min-window-parity-rows",
            "30",
            "--max-window-mismatch-ratio",
            "0.07",
            "--out-json",
            str(root / "EVIDENCE" / "cutover" / "cycle_out.json"),
        ]
    )
    assert rc == 0
    readiness_cmd = next(cmd for cmd in calls if any("mql5_cutover_readiness.py" in part for part in cmd))
    assert "--min-active-windows" in readiness_cmd
    assert "2" in readiness_cmd
    assert "--min-window-parity-rows" in readiness_cmd
    assert "30" in readiness_cmd
    assert "--max-window-mismatch-ratio" in readiness_cmd
    assert "0.07" in readiness_cmd
