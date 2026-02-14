#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

PATTERNS = (
    (
        "authorization_bearer",
        re.compile(r"(?i)\bauthorization\b\s*[:=]\s*bearer\s+[A-Za-z0-9._-]{10,}"),
    ),
    (
        "named_secret_assignment",
        re.compile(
            r"(?i)\b(api[_-]?key|token|password)\b\s*[:=]\s*[\"']?[A-Za-z0-9_\-]{10,}[\"']?"
        ),
    ),
    (
        "openai_sk_token",
        re.compile(r"\bsk-[A-Za-z0-9]{10,}\b"),
    ),
)

ALLOWLIST_MARKERS = (
    "<REDACTED>",
    "<PLACEHOLDER>",
    '"[REDACTED]"',
)

SHA256_LINE_RE = re.compile(r"^[a-f0-9]{64}\s+\S+$", re.IGNORECASE)

SKIP_DIRS = {
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tmp",
    ".tmp_py",
    "TMP_AUDIT_IO",
    "EVIDENCE",
    "DIAG",
    "DB",
    "DATA",
}

TEXT_EXTS = {
    ".py",
    ".ps1",
    ".cmd",
    ".bat",
    ".json",
    ".yaml",
    ".yml",
    ".txt",
    ".md",
    ".ini",
    ".cfg",
    ".csv",
    ".toml",
    ".env",
    ".log",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _is_probably_text(path: Path) -> bool:
    if path.suffix.lower() in TEXT_EXTS:
        return True
    try:
        head = path.read_bytes()[:2048]
    except OSError:
        return False
    return b"\x00" not in head


def _iter_files(root: Path) -> Iterable[Path]:
    for path in root.rglob("*"):
        if path.is_dir():
            continue
        rel_parts = path.relative_to(root).parts
        if any(part in SKIP_DIRS for part in rel_parts):
            continue
        if not _is_probably_text(path):
            continue
        yield path


def _line_is_allowlisted(line: str) -> bool:
    if any(marker in line for marker in ALLOWLIST_MARKERS):
        return True
    if SHA256_LINE_RE.match(line.strip()):
        return True
    return False


def scan_roots(
    roots: Sequence[Path],
    *,
    max_findings: int = 1000,
) -> Dict[str, object]:
    findings: List[Dict[str, object]] = []
    files_scanned = 0
    lines_scanned = 0

    unique_files = set()
    for root in roots:
        if not root.exists():
            continue
        for fpath in _iter_files(root):
            unique_files.add(fpath.resolve())

    for path in sorted(unique_files):
        files_scanned += 1
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for ln, line in enumerate(text.splitlines(), start=1):
            lines_scanned += 1
            if _line_is_allowlisted(line):
                continue
            for p_name, p_re in PATTERNS:
                if p_re.search(line):
                    findings.append(
                        {
                            "file": str(path).replace("\\", "/"),
                            "line": ln,
                            "pattern": p_name,
                        }
                    )
                    break
            if len(findings) >= int(max_findings):
                break
        if len(findings) >= int(max_findings):
            break

    return {
        "status": "FAIL" if findings else "PASS",
        "ts_utc": utc_now_iso(),
        "totals": {
            "files_scanned": files_scanned,
            "lines_scanned": lines_scanned,
            "findings": len(findings),
            "max_findings": int(max_findings),
        },
        "findings": findings,
    }


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Secret scanner for repo and evidence.")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--scan-evidence", action="store_true")
    ap.add_argument("--evidence-root", default="")
    ap.add_argument("--report", default="")
    ap.add_argument("--max-findings", type=int, default=1000)
    return ap.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    roots = [root]
    if args.scan_evidence:
        ev_root = Path(args.evidence_root).resolve() if args.evidence_root else (root / "EVIDENCE").resolve()
        roots.append(ev_root)

    report = scan_roots(roots, max_findings=max(1, int(args.max_findings)))
    report["root"] = str(root)
    report["scan_evidence"] = bool(args.scan_evidence)
    report["evidence_root"] = str(roots[1]) if args.scan_evidence and len(roots) > 1 else ""

    if args.report:
        rep = Path(args.report)
        if not rep.is_absolute():
            rep = (root / rep).resolve()
        rep.parent.mkdir(parents=True, exist_ok=True)
        rep.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if report["status"] == "PASS":
        print("SECRETS_SCAN_PASS")
        return 0
    print("SECRETS_SCAN_FAIL")
    for f in report["findings"]:
        print(f"- {f['file']}:{f['line']} [{f['pattern']}]")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
