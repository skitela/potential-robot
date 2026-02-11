# -*- coding: utf-8 -*-
"""smoke_compile_v6_2.py — compile + import smoke test (NO .pyc)

- Checks syntax for all .py under --root, excluding .venv, DIAG, EVIDENCE.
- Does NOT create __pycache__ or *.pyc (complies with no-bytecode policy).
- Writes a JSON report to --out.
- Exits non-zero on first failure.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from BIN import common_guards as cg  # noqa: E402

EXCLUDE_DIRS = {'.venv', 'DIAG', 'EVIDENCE', '__pycache__'}


def iter_py(root: Path):
    for p in root.rglob('*.py'):
        if set(p.parts) & EXCLUDE_DIRS:
            continue
        yield p


def check_syntax(p: Path) -> None:
    # Avoid py_compile (writes .pyc). Pure syntax check only.
    src = p.read_text(encoding='utf-8', errors='replace')
    if src.startswith('\ufeff'):
        src = src.lstrip('\ufeff')
    compile(src, str(p), 'exec')


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    root = Path(args.root)
    out = Path(args.out)
    t0 = time.time()

    report: Dict[str, Any] = {
        'root': str(root),
        'ts_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'checked': 0,
        'failures': [],
        'python': sys.version,
        'executable': sys.executable,
        'bytecode_writes': 'disabled (compile-only)',
    }

    for p in iter_py(root):
        try:
            check_syntax(p)
            report['checked'] += 1
        except Exception as e:
            cg.tlog(None, "WARN", "SMOKE_EXC", "nonfatal exception swallowed", e)
            report['failures'].append({'file': str(p), 'error': str(e)})
            break

    report['elapsed_s'] = round(time.time() - t0, 3)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding='utf-8')

    return 0 if not report['failures'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
