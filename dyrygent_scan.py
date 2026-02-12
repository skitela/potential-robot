import ast
import os
import sys
import json
from pathlib import Path

def scan_repo_map(root, denylist=None):
    """
    Skanuje repozytorium i generuje mapę plików z metadanymi:
    - rel_path, group, symbols, imports, entrypoint, risk_flags, notes
    """
    if denylist is None:
        denylist = [
            "EVIDENCE/", "DIAG/", "TOKEN/", "DPAPI/", ".venv/", "venv/", "__pycache__/"
        ]
    repo_map = []
    for dirpath, dirs, files in os.walk(root):
        rel_dir = os.path.relpath(dirpath, root)
        # Twardy denylist na katalogi
        for d in list(dirs):
            d_rel = os.path.join(rel_dir, d)
            if any(d_rel.replace("\\", "/").startswith(p) for p in denylist):
                dirs.remove(d)
        for f in files:
            rel_path = os.path.normpath(os.path.join(rel_dir, f))
            if any(rel_path.replace("\\", "/").startswith(p) for p in denylist):
                continue
            abs_path = os.path.join(dirpath, f)
            group = classify_group(rel_path)
            symbols, imports, entrypoint = [], [], False
            risk_flags = set()
            notes = ""
            if f.endswith(".py"):
                try:
                    with open(abs_path, encoding="utf-8", errors="replace") as fin:
                        src = fin.read()
                    tree = ast.parse(src, filename=rel_path)
                    symbols = [n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.ClassDef))]
                    imports = [n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module] + \
                              [n.names[0].name for n in ast.walk(tree) if isinstance(n, ast.Import)]
                    entrypoint = "if __name__ == '__main__'" in src or "if __name__ == \"__main__\"" in src
                    if any(x in src for x in ["api_key", "token", "password"]):
                        risk_flags.add("may_contain_secrets")
                    if any(x in src.lower() for x in ["bid", "ask", "ohlc", "price", "rate", "quote", "tick", "spread"]):
                        risk_flags.add("may_contain_price_like")
                except Exception as e:
                    notes = f"PARSE_ERROR: {e}"
            repo_map.append({
                "rel_path": rel_path.replace("\\", "/"),
                "group": group,
                "symbols": sorted(symbols),
                "imports": sorted(set(imports)),
                "entrypoint": entrypoint,
                "risk_flags": sorted(risk_flags),
                "notes": notes
            })
    repo_map = sorted(repo_map, key=lambda x: x["rel_path"])
    return repo_map

def classify_group(rel_path):
    if rel_path.startswith("BIN/"):
        return "guards"
    if rel_path.startswith("TOOLS/"):
        return "tooling"
    if rel_path.startswith("CORE/"):
        return "core_trading"
    if rel_path.startswith("DOCS/"):
        return "docs"
    if rel_path.startswith("TESTS/"):
        return "tests"
    if rel_path.startswith("RUN/"):
        return "runtime"
    if rel_path.startswith("DYRYGENT_EXTERNAL"):
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
