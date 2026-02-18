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
    "metatrader5": "MetaTrader5",
    "pypdf2": "PyPDF2",
}

TOOLING_REQUIREMENTS = {
    "bandit",
    "black",
    "isort",
    "mypy",
    "pip-audit",
    "pytest",
    "pytest-cov",
    "ruff",
}

# Runtime transitive dependency (imported by feedparser, not directly by this repo).
INDIRECT_RUNTIME_REQUIREMENTS = {"sgmllib3k"}


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


def parse_local_modules(root: Path) -> Set[str]:
    mods: Set[str] = set()
    for path in root.rglob("*.py"):
        rel = path.relative_to(root).as_posix()
        if rel.startswith("EVIDENCE/"):
            continue
        if rel.startswith("DIAG/"):
            continue
        if "__pycache__" in rel:
            continue
        stem = path.stem.strip()
        if stem and stem != "__init__":
            mods.add(stem)
    for pkg in ("BIN", "TOOLS", "tests"):
        pkg_init = root / pkg / "__init__.py"
        if pkg_init.exists():
            mods.add(pkg)
    return mods


def detect_hygiene(root: Path, requirement_files: List[str], *, include_tooling: bool = False) -> Dict[str, object]:
    req_paths = [(root / item).resolve() for item in requirement_files]
    reqs = parse_requirements(req_paths)
    imports = parse_imports(root)
    local_modules = parse_local_modules(root)
    stdlib = set(sys.stdlib_module_names)
    normalized_imports = {_normalize_req_name(name) for name in imports}
    normalized_locals = {_normalize_req_name(name) for name in local_modules}

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
    used_requirements: List[str] = []
    unused_requirements: List[str] = []
    unused_tooling_requirements: List[str] = []
    unused_indirect_requirements: List[str] = []
    for name, imp in req_to_import.items():
        imp_norm = _normalize_req_name(imp)
        is_used = (imp in imports) or (imp_norm in normalized_imports)
        if is_used:
            used_requirements.append(name)
            continue
        if not include_tooling and name in TOOLING_REQUIREMENTS:
            unused_tooling_requirements.append(name)
            continue
        if not include_tooling and name in INDIRECT_RUNTIME_REQUIREMENTS:
            unused_indirect_requirements.append(name)
            continue
        unused_requirements.append(name)
    used_requirements.sort()
    unused_requirements.sort()
    unused_tooling_requirements.sort()
    unused_indirect_requirements.sort()

    third_party_imports = sorted(
        name
        for name in imports
        if name not in stdlib
        and name not in local_roots
        and not name.startswith("_")
        and _normalize_req_name(name) not in normalized_locals
    )
    missing_requirements = sorted(
        name
        for name in third_party_imports
        if _normalize_req_name(name) not in reqs
        and _normalize_req_name(name.replace("_", "-")) not in reqs
        and _normalize_req_name(name) not in normalized_locals
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
        "unused_tooling_requirements": unused_tooling_requirements,
        "unused_indirect_requirements": unused_indirect_requirements,
        "third_party_imports": third_party_imports,
        "missing_requirements": missing_requirements,
        "local_modules_detected": sorted(local_modules),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Offline dependency hygiene report.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--out", default="")
    parser.add_argument("--requirements", nargs="*", default=REQUIREMENT_FILES_DEFAULT)
    parser.add_argument("--include-tooling", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    report = detect_hygiene(root, [str(x) for x in args.requirements], include_tooling=bool(args.include_tooling))
    if args.out:
        out = Path(args.out)
        if not out.is_absolute():
            out = (root / out).resolve()
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(
        "DEPENDENCY_HYGIENE_OK "
        f"unused={len(report['unused_requirements'])} "
        f"missing={len(report['missing_requirements'])} "
        f"tooling_unused={len(report['unused_tooling_requirements'])} "
        f"indirect_unused={len(report['unused_indirect_requirements'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
