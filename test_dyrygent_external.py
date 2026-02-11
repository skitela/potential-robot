import shutil
import time
from pathlib import Path

from DYRYGENT_EXTERNAL import DyrygentExternal


def run_smoke() -> int:
    repo_root = Path(__file__).resolve().parent
    evidence_dir = repo_root / "EVIDENCE" / "dyrygent_smoke" / f"test_smoke_{int(time.time())}"
    if evidence_dir.exists():
        shutil.rmtree(evidence_dir)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    dyrygent = DyrygentExternal(
        system_root=repo_root,
        evidence_dir=evidence_dir,
        mode="OFFLINE",
        dry_run=True,
    )
    dyrygent.register_ai_agent("LocalStub")
    ai_reply = dyrygent.query_external_ai("health-check", ai="LocalStub")
    verdict = dyrygent.run_full_validation()

    assert verdict["mode"] == "OFFLINE"
    assert verdict["status"] in {"PASS", "FAIL"}
    assert "OFFLINE_STUB" in ai_reply
    assert (evidence_dir / "verdict.json").exists()
    assert (evidence_dir / "evidence_bundle.zip").exists()
    assert (evidence_dir / "evidence_bundle.zip.sha256").exists()
    assert verdict["evidence"]["evidence_zip_sha256"]
    assert verdict["evidence"]["bundle_file_count"] > 0
    assert dyrygent.status_report()["ai_agents"][0]["mode"] == "OFFLINE_STUB"

    print("SMOKE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(run_smoke())
