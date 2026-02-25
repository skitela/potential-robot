#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set


REQUIREMENT_FILES_DEFAULT = [
    "requirements.txt",
    "requirements-dev.txt",
    "requirements.offline.lock",
    "requirements.live.lock",
    "dashboard/requirements.txt",
]

IMPORT_MAP = {
    "python-dateutil": "dateutil",
    "pyyaml": "yaml",
    "scikit-learn": "sklearn",
    "metatrader5": "MetaTrader5",
    "pypdf2": "PyPDF2",
    "pyzmq": "zmq",
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


def iter_python_files(root: Path) -> Iterable[Path]:
    excluded_prefixes = (
        "EVIDENCE/",
        "DIAG/",
        "TMP_AUDIT_IO/",
        ".tmp/",
        ".tmp_py/",
        ".tmp_pycache/",
    )
    for path in root.rglob("*.py"):
        rel = path.relative_to(root).as_posix()
        if rel.startswith(excluded_prefixes):
            continue
        if "__pycache__" in rel:
            continue
        yield path


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
    for path in iter_python_files(root):
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
    for path in iter_python_files(root):
        stem = path.stem.strip()
        if stem and stem != "__init__":
            mods.add(stem)
    for pkg in ("BIN", "TOOLS", "tests"):
        pkg_init = root / pkg / "__init__.py"
        if pkg_init.exists():
            mods.add(pkg)
    return mods


def module_name_from_path(root: Path, path: Path) -> str:
    rel = path.relative_to(root).as_posix()
    if rel.endswith("/__init__.py"):
        rel = rel[: -len("/__init__.py")]
    elif rel.endswith(".py"):
        rel = rel[:-3]
    return rel.replace("/", ".")


def build_module_index(root: Path) -> Set[str]:
    out: Set[str] = set()
    for path in iter_python_files(root):
        mod = module_name_from_path(root, path)
        if mod:
            out.add(mod)
    return out


def _resolve_relative_module(current_module: str, module: Optional[str], level: int) -> Optional[str]:
    if level <= 0:
        return module
    parts = current_module.split(".")
    # current_module is a module path (not package path), so strip leaf first.
    pkg = parts[:-1]
    if level > len(pkg):
        return None
    base = pkg[: len(pkg) - level + 1]
    mod_tail = (module or "").strip()
    if mod_tail:
        return ".".join(base + [mod_tail])
    return ".".join(base)


def _module_exists(target: str, module_index: Set[str]) -> bool:
    if not target:
        return False
    if target in module_index:
        return True
    # allow package imports (e.g. "BIN" if "BIN.safetybot" exists)
    pref = target + "."
    return any(mod.startswith(pref) for mod in module_index)


def analyze_local_links(root: Path) -> Dict[str, Any]:
    module_index = build_module_index(root)
    local_prefixes = ("BIN", "TOOLS", "tests")
    edges: List[Dict[str, str]] = []
    unresolved: List[Dict[str, Any]] = []

    for path in iter_python_files(root):
        current_module = module_name_from_path(root, path)
        try:
            tree = ast.parse(path.read_text(encoding="utf-8", errors="ignore"), filename=str(path))
        except SyntaxError:
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    target = str(alias.name or "").strip()
                    if not target.startswith(local_prefixes):
                        continue
                    if _module_exists(target, module_index):
                        edges.append({"src": current_module, "dst": target, "kind": "import"})
                    else:
                        unresolved.append(
                            {
                                "src": current_module,
                                "import": target,
                                "line": int(getattr(node, "lineno", 0) or 0),
                                "kind": "import",
                            }
                        )
            elif isinstance(node, ast.ImportFrom):
                resolved = _resolve_relative_module(current_module, node.module, int(getattr(node, "level", 0) or 0))
                if not resolved:
                    continue
                if not resolved.startswith(local_prefixes):
                    continue
                if _module_exists(resolved, module_index):
                    edges.append({"src": current_module, "dst": resolved, "kind": "from"})
                else:
                    unresolved.append(
                        {
                            "src": current_module,
                            "import": resolved,
                            "line": int(getattr(node, "lineno", 0) or 0),
                            "kind": "from",
                        }
                    )

    # Deduplicate while preserving deterministic order.
    dedup_edges: List[Dict[str, str]] = []
    seen_edges: Set[str] = set()
    for row in sorted(edges, key=lambda x: (x["src"], x["dst"], x["kind"])):
        key = f"{row['src']}|{row['dst']}|{row['kind']}"
        if key in seen_edges:
            continue
        seen_edges.add(key)
        dedup_edges.append(row)

    dedup_unresolved: List[Dict[str, Any]] = []
    seen_unresolved: Set[str] = set()
    for row in sorted(unresolved, key=lambda x: (x["src"], x["import"], int(x["line"]), x["kind"])):
        key = f"{row['src']}|{row['import']}|{row['line']}|{row['kind']}"
        if key in seen_unresolved:
            continue
        seen_unresolved.add(key)
        dedup_unresolved.append(row)

    return {
        "module_index_total": len(module_index),
        "local_prefixes": list(local_prefixes),
        "edges_total": len(dedup_edges),
        "unresolved_total": len(dedup_unresolved),
        "edges": dedup_edges,
        "unresolved": dedup_unresolved,
    }


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
    provided_imports_norm = {_normalize_req_name(imp) for imp in req_to_import.values() if imp}
    missing_requirements = sorted(
        name
        for name in third_party_imports
        if _normalize_req_name(name) not in reqs
        and _normalize_req_name(name.replace("_", "-")) not in reqs
        and _normalize_req_name(name) not in normalized_locals
        and _normalize_req_name(name) not in provided_imports_norm
    )

    local_links = analyze_local_links(root)

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
        "local_module_index_total": int(local_links.get("module_index_total", 0)),
        "local_link_edges_total": int(local_links.get("edges_total", 0)),
        "local_unresolved_total": int(local_links.get("unresolved_total", 0)),
        "local_unresolved": list(local_links.get("unresolved", [])),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Offline dependency hygiene report.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--out", default="")
    parser.add_argument("--requirements", nargs="*", default=REQUIREMENT_FILES_DEFAULT)
    parser.add_argument("--include-tooling", action="store_true")
    parser.add_argument("--fail-on-missing-requirements", action="store_true")
    parser.add_argument("--fail-on-local-unresolved", action="store_true")
    return parser.parse_args()


def evaluate_failures(
    report: Dict[str, object],
    *,
    fail_on_missing_requirements: bool,
    fail_on_local_unresolved: bool,
) -> List[str]:
    failures: List[str] = []
    missing = list(report.get("missing_requirements") or [])
    unresolved = int(report.get("local_unresolved_total") or 0)
    if fail_on_missing_requirements and missing:
        failures.append(f"MISSING_REQUIREMENTS:{len(missing)}")
    if fail_on_local_unresolved and unresolved > 0:
        failures.append(f"LOCAL_UNRESOLVED:{unresolved}")
    return failures


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

    failures = evaluate_failures(
        report,
        fail_on_missing_requirements=bool(args.fail_on_missing_requirements),
        fail_on_local_unresolved=bool(args.fail_on_local_unresolved),
    )

    print(
        "DEPENDENCY_HYGIENE_OK "
        f"unused={len(report['unused_requirements'])} "
        f"missing={len(report['missing_requirements'])} "
        f"tooling_unused={len(report['unused_tooling_requirements'])} "
        f"indirect_unused={len(report['unused_indirect_requirements'])}"
    )
    if failures:
        print("DEPENDENCY_HYGIENE_FAIL " + ",".join(failures))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
