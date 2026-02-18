import ast
import json
import os
import re
import sys
from pathlib import Path

SECRETS_ASSIGN_RE = re.compile(r"\b(api[_-]?key|token|password)\b\s*[:=]", re.IGNORECASE)
PRICE_ASSIGN_RE = re.compile(r"\b(bid|ask|ohlc|price|rate|quote|tick|spread)\b\s*[:=]", re.IGNORECASE)


def _norm_rel(path: str) -> str:
    return str(path or "").replace("\\", "/")


def scan_repo_map(root, denylist=None):
    """
    Skanuje repozytorium i generuje mapę plików z metadanymi:
    - rel_path, group, symbols, imports, entrypoint, risk_flags, notes
    """
    if denylist is None:
        denylist = [
            "EVIDENCE/", "DIAG/", "TOKEN/", "DPAPI/", ".venv/", "venv/", "__pycache__/"
        ]
    denylist_norm = [x.lower() for x in denylist]

    repo_map = []
    for dirpath, dirs, files in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        # Twardy denylist na katalogi
        for d in list(dirs):
            d_rel = _norm_rel(os.path.join(rel_dir, d)).lower()
            if any(d_rel.startswith(p) for p in denylist_norm):
                dirs.remove(d)

        for f in files:
            rel_path = os.path.normpath(os.path.join(rel_dir, f))
            rel_norm = _norm_rel(rel_path)
            if any(rel_norm.lower().startswith(p) for p in denylist_norm):
                continue

            abs_path = os.path.join(dirpath, f)
            group = classify_group(rel_norm)
            symbols, imports, entrypoint = [], [], False
            risk_flags = set()
            notes = ""
            if f.endswith(".py"):
                try:
                    with open(abs_path, encoding="utf-8", errors="replace") as fin:
                        src = fin.read()
                    tree = ast.parse(src, filename=rel_norm)
                    symbols = [n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.ClassDef))]
                    imports = [n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module]
                    for node in ast.walk(tree):
                        if isinstance(node, ast.Import):
                            for alias in node.names:
                                imports.append(alias.name)
                    entrypoint = "if __name__ == '__main__'" in src or "if __name__ == \"__main__\"" in src
                    if SECRETS_ASSIGN_RE.search(src):
                        risk_flags.add("may_contain_secrets")
                    if PRICE_ASSIGN_RE.search(src):
                        risk_flags.add("may_contain_price_like")
                except Exception as e:
                    notes = f"PARSE_ERROR: {e}"

            repo_map.append({
                "rel_path": rel_norm,
                "group": group,
                "symbols": sorted(symbols),
                "imports": sorted(set(imports)),
                "entrypoint": entrypoint,
                "risk_flags": sorted(risk_flags),
                "notes": notes,
            })

    repo_map = sorted(repo_map, key=lambda x: x["rel_path"])
    return repo_map


def classify_group(rel_path):
    rel = _norm_rel(rel_path).lower()
    if rel.startswith("bin/"):
        return "guards"
    if rel.startswith("tools/"):
        return "tooling"
    if rel.startswith("core/"):
        return "core_trading"
    if rel.startswith("docs/"):
        return "docs"
    if rel.startswith("tests/"):
        return "tests"
    if rel.startswith("run/"):
        return "runtime"
    if rel.startswith("dyrygent_external"):
        return "dyrygent"
    return "other"


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else str(Path(__file__).parent)
    repo_map = scan_repo_map(root)
    out_path = Path(root) / "EVIDENCE" / "repo_map.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(repo_map, f, indent=2, ensure_ascii=False)
    print(f"Repo map written to {out_path}")
