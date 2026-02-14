# -*- coding: utf-8 -*-
import unittest

from TOOLS.validate_audit_checklist_v1_2 import CHECKLIST_IDS, OPTIONAL_STAGE_IDS, STAGE_IDS, evaluate_report


def _build_good_report() -> str:
    lines = [
        "Audit zakonczony.",
        "Run ID: sample_001",
        r"Root: C:\OANDA_MT5_SYSTEM",
        "Data UTC: 2026-02-14T12:00:00Z",
        "",
        "Etapy wykonane:",
    ]
    for sid in STAGE_IDS:
        if sid in OPTIONAL_STAGE_IDS:
            lines.append(f"- {sid}: NIE_URUCHAMIANO | dowod: nie wymagano w tej iteracji")
        else:
            lines.append(f"- {sid}: PASS | dowod: EVIDENCE/{sid.lower()}.txt")

    lines.extend(
        [
            "",
            "Checklista kontrolna (wymagana):",
        ]
    )
    for cid in CHECKLIST_IDS:
        lines.append(f"- {cid}: PASS | dowod: EVIDENCE/{cid.lower()}.txt | uwaga: ok")

    lines.extend(
        [
            "",
            "Werdykt koncowy:",
            "- SYSTEM_STATUS: GOTOWY",
        ]
    )
    return "\n".join(lines) + "\n"


class TestValidateAuditChecklistV12(unittest.TestCase):
    def test_good_report_passes(self) -> None:
        report = _build_good_report()
        result = evaluate_report(report, report_path="sample_report.txt")
        self.assertTrue(result["gate"]["ok"])
        self.assertEqual(result["gate"]["exit_code"], 0)
        self.assertEqual(result["summary"]["computed_system_status"], "GOTOWY")
        self.assertEqual(len(result["findings"]), 0)

    def test_missing_evidence_for_pass_fails(self) -> None:
        report = _build_good_report().replace(
            "- C09_SECRETS_POLICY: PASS | dowod: EVIDENCE/c09_secrets_policy.txt | uwaga: ok",
            "- C09_SECRETS_POLICY: PASS | dowod: <...> | uwaga: ok",
        )
        result = evaluate_report(report, report_path="sample_report.txt")
        self.assertFalse(result["gate"]["ok"])
        finding_ids = {f["id"] for f in result["findings"]}
        self.assertIn("EVIDENCE_REQUIRED_CHECK", finding_ids)

    def test_system_status_mismatch_fails(self) -> None:
        report = _build_good_report().replace(
            "- C05_STRATEGY_UNCHANGED: PASS | dowod: EVIDENCE/c05_strategy_unchanged.txt | uwaga: ok",
            "- C05_STRATEGY_UNCHANGED: FAIL | dowod: EVIDENCE/c05_strategy_unchanged.txt | uwaga: wykryto odchylenie",
        )
        # Keep SYSTEM_STATUS as GOTOWY to trigger mismatch.
        result = evaluate_report(report, report_path="sample_report.txt")
        self.assertFalse(result["gate"]["ok"])
        self.assertEqual(result["summary"]["computed_system_status"], "NIEGOTOWY")
        finding_ids = {f["id"] for f in result["findings"]}
        self.assertIn("SYSTEM_STATUS_MISMATCH", finding_ids)


if __name__ == "__main__":
    raise SystemExit(unittest.main())
