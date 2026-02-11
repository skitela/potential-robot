#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Set


REQUIREMENT_FILES_DEFAULT = [
    "requirements.txt",
    "requirements-dev.txt",
    "requirements.offline.lock",
    "requirements.live.lock",
]

IMPORT_MAP = {
    "python-dateutil": "dateutil",
    "pyyaml": "yaml",
    "scikit-learn": "sklearn",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _normalize_req_name(name: str) -> str:
    return re.sub(r"[-_.]+", "-", name.strip().lower())


def parse_requirements(paths: Iterable[Path]) -> Set[str]:
    out: Set[str] = set()
    for path in paths:
        if not path.exists():
            continue
        for raw in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("-r "):
                continue
            if ";" in line:
                line = line.split(";", 1)[0].strip()
            name = re.split(r"[<>=!~\[\]]", line, maxsplit=1)[0].strip()
            if name:
                out.add(_normalize_req_name(name))
    return out


def parse_imports(root: Path) -> Set[str]:
    imports: Set[str] = set()
    for path in root.rglob("*.py"):
        rel = path.relative_to(root).as_posix()
        if rel.startswith("EVIDENCE/"):
            continue
        if rel.startswith("DIAG/"):
            continue
        if "__pycache__" in rel:
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="ignore"), filename=str(path))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports.add(alias.name.split(".")[0])
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports.add(node.module.split(".")[0])
    return imports


def detect_hygiene(root: Path, requirement_files: List[str]) -> Dict[str, object]:
    req_paths = [(root / item).resolve() for item in requirement_files]
    reqs = parse_requirements(req_paths)
    imports = parse_imports(root)
    stdlib = set(sys.stdlib_module_names)

    local_roots = {
        "BIN",
        "TOOLS",
        "RUN",
        "tests",
        "SCHEMAS",
        "CORE",
        "DOCS",
        "DATA",
        "DB",
        "META",
        "LOGS",
        "EVIDENCE",
    }

    req_to_import = {name: IMPORT_MAP.get(name, name.replace("-", "_")) for name in reqs}
    used_requirements = sorted(name for name, imp in req_to_import.items() if imp in imports)
    unused_requirements = sorted(name for name, imp in req_to_import.items() if imp not in imports)

    third_party_imports = sorted(
        name
        for name in imports
        if name not in stdlib and name not in local_roots and not name.startswith("_")
    )
    missing_requirements = sorted(
        name
        for name in third_party_imports
        if _normalize_req_name(name) not in reqs and _normalize_req_name(name.replace("_", "-")) not in reqs
    )

    return {
        "status": "PASS",
        "ts_utc": utc_now_iso(),
        "root": str(root),
        "requirements_files": [str(p) for p in req_paths if p.exists()],
        "requirements_total": len(reqs),
        "imports_total": len(imports),
        "used_requirements": used_requirements,
        "unused_requirements": unused_requirements,
        "third_party_imports": third_party_imports,
        "missing_requirements": missing_requirements,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Offline dependency hygiene report.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--out", default="")
    parser.add_argument("--requirements", nargs="*", default=REQUIREMENT_FILES_DEFAULT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = detect_hygiene(root, [str(x) for x in args.requirements])
    if args.out:
        out = Path(args.out)
        if not out.is_absolute():
            out = (root / out).resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(
        "DEPENDENCY_HYGIENE_OK "
        f"unused={len(report['unused_requirements'])} "
        f"missing={len(report['missing_requirements'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
