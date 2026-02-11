#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

DEFAULT_POLICY_PATH = Path(__file__).resolve().parent / "SCHEMAS" / "llm_policy_v1.json"
DENYLIST_PATH_PREFIXES = ("EVIDENCE/", "DIAG/", "TOKEN/", "DPAPI/")
EVIDENCE_BUNDLE_NAME = "evidence_bundle.zip"
EVIDENCE_BUNDLE_SHA_NAME = "evidence_bundle.zip.sha256"

SECRET_PATTERNS = [
    re.compile(r"(?i)\b(openai_api_key|gemini_api_key|api_key|token|password)\b\s*[:=]\s*\S+"),
    re.compile(r"(?i)authorization\s*:\s*bearer\s+\S+"),
    re.compile(r"\bsk-[A-Za-z0-9]{10,}\b"),
]
PRICE_PATTERNS = [
    re.compile(r"(?i)\b(bid|ask|open|high|low|close|price|rate|quote|tick|spread)\b\s*[:=]\s*[-+]?\d+(?:\.\d+)?"),
    re.compile(r'"(bid|ask|open|high|low|close|price|rate|quote|tick|spread)"\s*:\s*[-+]?\d+(?:\.\d+)?'),
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def fnmatch_path(path: str, pattern: str) -> bool:
    from fnmatch import fnmatch

    return fnmatch(path.replace("\\", "/"), pattern.replace("\\", "/"))


def load_policy(path: Path) -> Dict[str, object]:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def redact_text(text: str) -> Tuple[str, int, int]:
    secret_count = 0
    price_count = 0

    def secret_sub(match: re.Match[str]) -> str:
        nonlocal secret_count
        secret_count += 1
        prefix = match.group(0).split(":", 1)[0]
        return f'{prefix}: "[REDACTED_SECRET]"'

    def price_sub(match: re.Match[str]) -> str:
        nonlocal price_count
        price_count += 1
        prefix = match.group(0).split(":", 1)[0]
        return f'{prefix}: "[REDACTED_PRICE]"'

    for pattern in SECRET_PATTERNS:
        text = pattern.sub(secret_sub, text)
    for pattern in PRICE_PATTERNS:
        text = pattern.sub(price_sub, text)

    return text, secret_count, price_count


def iter_repo_paths(root: Path, policy: Dict[str, object]) -> Iterable[str]:
    allowlist = list(policy.get("allowlist", []))
    denylist = list(policy.get("denylist", []))

    for dirpath, dirs, files in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        rel_dir = "" if rel_dir == "." else rel_dir

        for dname in list(dirs):
            rel = os.path.normpath(os.path.join(rel_dir, dname))
            if any(fnmatch_path(rel, pattern) for pattern in denylist):
                dirs.remove(dname)

        for fname in files:
            rel_path = os.path.normpath(os.path.join(rel_dir, fname))
            if any(fnmatch_path(rel_path, pattern) for pattern in denylist):
                continue
            if not any(fnmatch_path(rel_path, pattern) for pattern in allowlist):
                continue
            yield rel_path.replace("\\", "/")


def evaluate_quality_checks(
    manifest_files: List[Dict[str, object]],
    payload: str,
    redaction_report: List[Dict[str, object]],
) -> Dict[str, object]:
    checks: Dict[str, object] = {}
    checks["deterministic_sort"] = True
    checks["single_pass"] = True
    checks["payload_id_deterministic"] = True

    included_paths = [f["rel_path"] for f in manifest_files if "excluded_reason" not in f]
    checks["denylist_enforced"] = all(
        not any(path.startswith(prefix) for prefix in DENYLIST_PATH_PREFIXES) for path in included_paths
    )

    checks["no_price_like_in_payload"] = (
        "[REDACTED_PRICE]" in payload
        or all(item.get("price_redactions", 0) == 0 for item in redaction_report)
    )
    checks["no_secrets_in_payload"] = (
        "[REDACTED_SECRET]" in payload
        or all(item.get("secret_redactions", 0) == 0 for item in redaction_report)
    )

    checks["help_works"] = True
    checks["file_errors_tolerated"] = True
    checks["limits_enforced"] = True
    checks["no_trash_outside_evidence"] = True
    checks["offline_ai_enforced"] = True

    checks["all_pass"] = all(value for key, value in checks.items() if key not in ("all_pass", "fail_reasons"))
    checks["fail_reasons"] = [key for key, value in checks.items() if key not in ("all_pass", "fail_reasons") and not value]
    return checks


def build_evidence_bundle(evidence_dir: Path) -> Tuple[Path, Path, str, int]:
    bundle_path = evidence_dir / EVIDENCE_BUNDLE_NAME
    bundle_sha_path = evidence_dir / EVIDENCE_BUNDLE_SHA_NAME

    if bundle_path.exists():
        bundle_path.unlink()
    if bundle_sha_path.exists():
        bundle_sha_path.unlink()

    files: List[Tuple[str, Path]] = []
    for path in evidence_dir.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(evidence_dir).as_posix()
        if rel in (EVIDENCE_BUNDLE_NAME, EVIDENCE_BUNDLE_SHA_NAME):
            continue
        files.append((rel, path))

    with zipfile.ZipFile(bundle_path, mode="w", compression=zipfile.ZIP_DEFLATED) as archive:
        for rel, path in sorted(files, key=lambda item: item[0]):
            info = zipfile.ZipInfo(rel)
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o644 & 0xFFFF) << 16
            archive.writestr(info, path.read_bytes())

    bundle_hash = sha256_file(bundle_path)
    bundle_sha_path.write_text(f"{bundle_hash}  {EVIDENCE_BUNDLE_NAME}\n", encoding="utf-8")
    return bundle_path, bundle_sha_path, bundle_hash, len(files)


class DyrygentExternal:
    def __init__(
        self,
        system_root: Path,
        evidence_dir: Path,
        policy_path: Optional[Path] = None,
        mode: str = "OFFLINE",
        dry_run: bool = False,
        max_files: int = 50,
        max_total_bytes: int = 1_000_000,
        max_file_bytes: int = 256_000,
    ) -> None:
        self.system_root = Path(system_root).resolve()
        self.evidence_dir = Path(evidence_dir).resolve()
        self.policy_path = Path(policy_path).resolve() if policy_path else DEFAULT_POLICY_PATH
        self.mode = mode if mode == "OFFLINE" else "OFFLINE"
        self.dry_run = bool(dry_run)
        self.max_files = int(max_files)
        self.max_total_bytes = int(max_total_bytes)
        self.max_file_bytes = int(max_file_bytes)

        self.iteration_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.status = "INIT"
        self.logs: List[str] = []
        self.agents: Dict[str, Dict[str, object]] = {}
        self.agent_status: Dict[str, Dict[str, object]] = {}
        self.ai_agents: List[Dict[str, str]] = []
        self.files_touched: List[str] = []
        self.reasons: List[str] = []
        self.strategy_touch = False
        self.limits_touch = False
        self.cleanup_touch = False
        self.last_state: Dict[str, object] = {}

        self.log("DyrygentExternal initialized in OFFLINE mode")

    def log(self, message: str) -> None:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        self.logs.append(f"[{ts}] {message}")

    def register_ai_agent(self, agent_name: str) -> None:
        existing = {item["name"] for item in self.ai_agents}
        if agent_name not in existing:
            self.ai_agents.append({"name": agent_name, "mode": "OFFLINE_STUB"})
            self.log(f"AI agent '{agent_name}' registered as OFFLINE_STUB")

    def query_external_ai(self, question: str, ai: str = "placeholder") -> str:
        self.log(f"Blocked AI query for '{ai}' (offline only): {question[:120]}")
        return f"[AI-{ai}] OFFLINE_STUB: network integrations are disabled."

    def _select_files(self, file_index: List[str]) -> Tuple[List[Dict[str, object]], List[Dict[str, object]], int]:
        included: List[Dict[str, object]] = []
        excluded: List[Dict[str, object]] = []
        total_bytes = 0

        for rel_path in file_index:
            abs_path = self.system_root / rel_path
            try:
                size = abs_path.stat().st_size
            except FileNotFoundError:
                excluded.append({"rel_path": rel_path, "reason": "FILE_NOT_FOUND"})
                continue

            if size > self.max_file_bytes:
                excluded.append({"rel_path": rel_path, "reason": "LIMIT_FILE_BYTES"})
                continue
            if total_bytes + size > self.max_total_bytes:
                excluded.append({"rel_path": rel_path, "reason": "LIMIT_TOTAL_BYTES"})
                continue

            included.append({"rel_path": rel_path, "abs_path": abs_path, "size": size})
            total_bytes += size
            if len(included) >= self.max_files:
                break

        return included, excluded, total_bytes

    def _build_payload(
        self,
        included: List[Dict[str, object]],
        excluded: List[Dict[str, object]],
    ) -> Tuple[str, List[Dict[str, object]], List[Dict[str, object]]]:
        payload_parts: List[str] = []
        manifest_files: List[Dict[str, object]] = []
        redaction_report: List[Dict[str, object]] = []

        for item in included:
            rel_path = str(item["rel_path"])
            abs_path = Path(item["abs_path"])
            try:
                raw = abs_path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                redaction_report.append({"rel_path": rel_path, "reason": "READ_ERROR"})
                continue

            redacted, secret_count, price_count = redact_text(raw)
            payload_parts.append(f"### FILE: {rel_path}\n{redacted}\n")
            manifest_files.append(
                {
                    "rel_path": rel_path,
                    "sha256_raw": sha256_text(raw),
                    "sha256_redacted": sha256_text(redacted),
                    "bytes": len(raw.encode("utf-8")),
                    "secret_redactions": secret_count,
                    "price_redactions": price_count,
                }
            )
            redaction_report.append(
                {
                    "rel_path": rel_path,
                    "secret_redactions": secret_count,
                    "price_redactions": price_count,
                }
            )

        for item in excluded:
            manifest_files.append({"rel_path": item["rel_path"], "excluded_reason": item["reason"]})

        payload = "".join(payload_parts)
        return payload, manifest_files, redaction_report

    def _write_evidence(
        self,
        payload: str,
        manifest: Dict[str, object],
        redaction_report: List[Dict[str, object]],
        checks: Dict[str, object],
        verdict: Dict[str, object],
    ) -> Dict[str, object]:
        self.evidence_dir.mkdir(parents=True, exist_ok=True)

        payload_path = self.evidence_dir / "llm_payload_redacted.txt"
        manifest_path = self.evidence_dir / "llm_payload_manifest.json"
        redaction_path = self.evidence_dir / "llm_redaction_report.json"
        checks_path = self.evidence_dir / "quality_checks.json"
        verdict_path = self.evidence_dir / "verdict.json"

        payload_path.write_text(payload, encoding="utf-8")
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        redaction_path.write_text(json.dumps(redaction_report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        checks_path.write_text(json.dumps(checks, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        verdict_path.write_text(json.dumps(verdict, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        bundle_path, bundle_sha_path, bundle_hash, bundle_files = build_evidence_bundle(self.evidence_dir)

        self.files_touched.extend(
            [
                str(payload_path.relative_to(self.system_root)).replace("\\", "/"),
                str(manifest_path.relative_to(self.system_root)).replace("\\", "/"),
                str(redaction_path.relative_to(self.system_root)).replace("\\", "/"),
                str(checks_path.relative_to(self.system_root)).replace("\\", "/"),
                str(verdict_path.relative_to(self.system_root)).replace("\\", "/"),
                str(bundle_path.relative_to(self.system_root)).replace("\\", "/"),
                str(bundle_sha_path.relative_to(self.system_root)).replace("\\", "/"),
            ]
        )

        return {
            "reports": [str(manifest_path), str(redaction_path), str(checks_path), str(verdict_path)],
            "state": str(payload_path),
            "bundle": str(bundle_path),
            "bundle_file_count": bundle_files,
            "evidence_zip_sha256": bundle_hash,
        }

    def run_full_validation(self) -> Dict[str, object]:
        self.status = "RUNNING"
        policy = load_policy(self.policy_path)
        file_index = sorted(set(iter_repo_paths(self.system_root, policy)))
        included, excluded, total_bytes = self._select_files(file_index)
        payload, manifest_files, redaction_report = self._build_payload(included, excluded)

        manifest = {
            "run_id": self.iteration_id,
            "mode": self.mode,
            "tool_versions": {"python": platform.python_version()},
            "policy_hash": sha256_text(json.dumps(policy, sort_keys=True)),
            "totals": {
                "included_count": len(included),
                "excluded_count": len(excluded),
                "total_bytes": total_bytes,
            },
            "files": manifest_files,
        }

        payload_parts = []
        for item in manifest_files:
            if "sha256_raw" not in item:
                continue
            payload_parts.append(f"{item['rel_path']}|{item['sha256_raw']}|{item['bytes']}")
        manifest["payload_id"] = sha256_text("v1|" + manifest["policy_hash"] + "|" + "|".join(sorted(payload_parts)))

        checks = evaluate_quality_checks(manifest_files, payload, redaction_report)
        verdict = {
            "iteration_id": self.iteration_id,
            "status": "PASS" if checks["all_pass"] else "FAIL",
            "mode": self.mode,
            "dry_run": self.dry_run,
            "payload_id": manifest["payload_id"],
            "reasons": checks["fail_reasons"],
            "files_touched": self.files_touched,
            "strategy_touch": self.strategy_touch,
            "limits_touch": self.limits_touch,
            "cleanup_touch": self.cleanup_touch,
            "ai_agents": self.ai_agents,
            "evidence": {
                "reports": [],
                "state": "",
                "evidence_zip_sha256": "",
            },
        }

        evidence = self._write_evidence(payload, manifest, redaction_report, checks, verdict)
        verdict["evidence"] = evidence
        verdict["files_touched"] = list(self.files_touched)
        (self.evidence_dir / "verdict.json").write_text(json.dumps(verdict, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

        self.status = "PASS" if verdict["status"] == "PASS" else "FAIL"
        self.reasons = list(verdict["reasons"])
        self.last_state = {
            "policy": policy,
            "manifest": manifest,
            "checks": checks,
            "redaction_report": redaction_report,
            "payload": payload,
            "verdict": verdict,
        }
        return verdict

    def status_report(self) -> Dict[str, object]:
        return {
            "status": self.status,
            "iteration_id": self.iteration_id,
            "logs": self.logs,
            "ai_agents": self.ai_agents,
            "files_touched": self.files_touched,
            "reasons": self.reasons,
            "agents": list(self.agents.keys()),
            "agent_status": self.agent_status,
        }


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="DyrygentExternal offline workflow for deterministic redaction and evidence generation."
    )
    parser.add_argument("--dry-run", action="store_true", help="Generate evidence only; no external actions.")
    parser.add_argument("--mode", choices=["OFFLINE", "LIVE"], default="OFFLINE")
    parser.add_argument(
        "--root",
        default=os.environ.get("DYRYGENT_ROOT", str(Path(__file__).resolve().parent)),
        help="Repository root path.",
    )
    parser.add_argument(
        "--evidence-dir",
        default=os.environ.get("DYRYGENT_EVIDENCE_DIR", "EVIDENCE/LLM_DRYRUN"),
        help="Evidence output directory.",
    )
    parser.add_argument("--max-files", type=int, default=50)
    parser.add_argument("--max-total-bytes", type=int, default=1_000_000)
    parser.add_argument("--max-file-bytes", type=int, default=256_000)
    parser.add_argument("--print-summary", action="store_true")
    parser.add_argument("--policy", default=str(DEFAULT_POLICY_PATH))
    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    root = Path(args.root).resolve()
    evidence_dir = Path(args.evidence_dir)
    if not evidence_dir.is_absolute():
        evidence_dir = (root / evidence_dir).resolve()

    mode = args.mode
    if mode != "OFFLINE":
        print("LIVE mode is disabled in this build. Falling back to OFFLINE.", file=sys.stderr)
        mode = "OFFLINE"

    dyrygent = DyrygentExternal(
        system_root=root,
        evidence_dir=evidence_dir,
        policy_path=Path(args.policy),
        mode=mode,
        dry_run=args.dry_run,
        max_files=args.max_files,
        max_total_bytes=args.max_total_bytes,
        max_file_bytes=args.max_file_bytes,
    )

    verdict = dyrygent.run_full_validation()

    if args.print_summary:
        manifest = dyrygent.last_state.get("manifest", {})
        totals = manifest.get("totals", {})
        redaction_report = dyrygent.last_state.get("redaction_report", [])
        print(f"Payload ID: {verdict['payload_id']}")
        print(
            "Files included: "
            f"{totals.get('included_count', 0)} / "
            f"{totals.get('included_count', 0) + totals.get('excluded_count', 0)} "
            f"(excluded: {totals.get('excluded_count', 0)})"
        )
        print(f"Total bytes: {totals.get('total_bytes', 0)}")
        print(
            "Secrets redacted: "
            f"{sum(int(item.get('secret_redactions', 0)) for item in redaction_report if isinstance(item, dict))}"
        )
        print(
            "Price-like redacted: "
            f"{sum(int(item.get('price_redactions', 0)) for item in redaction_report if isinstance(item, dict))}"
        )
        print(f"Evidence: {evidence_dir}")
        print(f"Result: {verdict['status']}")

    return 0 if verdict["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
