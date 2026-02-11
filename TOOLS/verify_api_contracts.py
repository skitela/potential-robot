#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ast
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Tuple


@dataclass
class ApiSurface:
    functions: Dict[str, List[str]]
    classes: Dict[str, Dict[str, List[str]]]


def _signature_params(node: ast.FunctionDef | ast.AsyncFunctionDef) -> List[str]:
    args = node.args
    out: List[str] = []
    for item in args.posonlyargs:
        out.append(item.arg)
    for item in args.args:
        out.append(item.arg)
    if args.vararg is not None:
        out.append(f"*{args.vararg.arg}")
    if args.kwonlyargs:
        out.append("*")
    for item in args.kwonlyargs:
        out.append(item.arg)
    if args.kwarg is not None:
        out.append(f"**{args.kwarg.arg}")
    return out


def _parse_module(path: Path) -> ApiSurface:
    tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    functions: Dict[str, List[str]] = {}
    classes: Dict[str, Dict[str, List[str]]] = {}

    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions[node.name] = _signature_params(node)
        elif isinstance(node, ast.ClassDef):
            methods: Dict[str, List[str]] = {}
            for item in node.body:
                if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef)):
                    methods[item.name] = _signature_params(item)
            classes[node.name] = methods
    return ApiSurface(functions=functions, classes=classes)


def _check_expected(actual: Dict[str, List[str]], expected: List[Dict[str, Any]], label: str) -> List[str]:
    issues: List[str] = []
    for spec in expected:
        name = str(spec.get("name") or "")
        want = [str(x) for x in spec.get("params", [])]
        if name not in actual:
            issues.append(f"{label}: missing symbol '{name}'")
            continue
        got = actual[name]
        if got != want:
            issues.append(f"{label}: signature mismatch for '{name}' expected={want} got={got}")
    return issues


def verify_contracts(root: Path, schema_path: Path) -> Tuple[bool, List[str]]:
    schema = json.loads(schema_path.read_text(encoding="utf-8-sig"))
    modules = schema.get("modules", [])
    if not isinstance(modules, list):
        return False, ["schema: 'modules' must be a list"]

    issues: List[str] = []
    for mod in modules:
        rel = str(mod.get("path") or "").strip()
        if not rel:
            issues.append("schema: module path is empty")
            continue
        module_path = (root / rel).resolve()
        if not module_path.exists():
            issues.append(f"{rel}: module not found")
            continue
        try:
            surface = _parse_module(module_path)
        except Exception as exc:  # pragma: no cover
            issues.append(f"{rel}: parse failure: {type(exc).__name__}: {exc}")
            continue

        fn_specs = mod.get("functions", [])
        if isinstance(fn_specs, list):
            issues.extend(_check_expected(surface.functions, fn_specs, f"{rel}::function"))

        cls_specs = mod.get("classes", [])
        if isinstance(cls_specs, list):
            for cls in cls_specs:
                cls_name = str(cls.get("name") or "")
                methods = cls.get("methods", [])
                if cls_name not in surface.classes:
                    issues.append(f"{rel}: missing class '{cls_name}'")
                    continue
                if not isinstance(methods, list):
                    issues.append(f"{rel}:{cls_name}: methods must be list")
                    continue
                issues.extend(
                    _check_expected(
                        surface.classes[cls_name],
                        methods,
                        f"{rel}::{cls_name}::method",
                    )
                )

    return len(issues) == 0, issues


def parse_args(argv: List[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Verify API signatures against schema contract.")
    parser.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    parser.add_argument("--schema", default="SCHEMAS/api_contracts_v1.json")
    parser.add_argument("--evidence", default="")
    return parser.parse_args(argv)


def main(argv: List[str] | None = None) -> int:
    args = parse_args(argv)
    root = Path(args.root).resolve()
    schema_path = Path(args.schema)
    if not schema_path.is_absolute():
        schema_path = (root / schema_path).resolve()

    ok, issues = verify_contracts(root, schema_path)
    report = {
        "status": "PASS" if ok else "FAIL",
        "root": str(root),
        "schema": str(schema_path),
        "issues": issues,
    }
    if args.evidence:
        evidence_path = Path(args.evidence)
        if not evidence_path.is_absolute():
            evidence_path = (root / evidence_path).resolve()
        evidence_path.parent.mkdir(parents=True, exist_ok=True)
        evidence_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    if ok:
        print("API_CONTRACTS_OK")
        return 0

    print("API_CONTRACTS_FAIL")
    for issue in issues:
        print(f"- {issue}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
