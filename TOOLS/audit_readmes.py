#!/usr/bin/env python3
"""
TOOLS/audit_readmes.py

Cel: reprodukowalnie wyciągnąć i porównać Readme*.txt z dwóch paczek ZIP.
Uwaga: narzędzie nie modyfikuje ZIP-ów ani plików runtime. Tylko odczyt.
"""
import argparse
import hashlib
import re
import zipfile
from pathlib import Path
import difflib
from BIN import common_guards as cg  # type: ignore

README_RE = re.compile(r"(^|/)(readme[^/]*\.txt)$", re.IGNORECASE)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def read_text(z: zipfile.ZipFile, member: str) -> str:
    data = z.read(member)
    for enc in ("utf-8", "utf-8-sig", "cp1250", "latin-1"):
        try:
            return data.decode(enc)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")

def find_readmes(names):
    return [n for n in names if README_RE.search(n)]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--zip-a", required=True, help="Pierwszy ZIP (np. demo1)")
    ap.add_argument("--zip-b", required=True, help="Drugi ZIP (np. baseline)")
    ap.add_argument("--out", required=True, help="Katalog wyjściowy (wyniki audytu)")
    args = ap.parse_args()

    zip_a = Path(args.zip_a)
    zip_b = Path(args.zip_b)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    (out / "HASHES_SHA256.txt").write_text(
        f"A  {zip_a}  {sha256_file(zip_a)}\nB  {zip_b}  {sha256_file(zip_b)}\n",
        encoding="utf-8"
    )

    with zipfile.ZipFile(zip_a, "r") as za, zipfile.ZipFile(zip_b, "r") as zb:
        ra = find_readmes(za.namelist())
        rb = find_readmes(zb.namelist())
        (out / "README_LIST.txt").write_text(
            "ZIP-A READMEs:\n" + "\n".join(ra) + "\n\nZIP-B READMEs:\n" + "\n".join(rb) + "\n",
            encoding="utf-8"
        )

        common = sorted(set(ra) & set(rb))
        extract = out / "README_EXTRACT"
        diffs = out / "DIFFS"
        extract.mkdir(exist_ok=True)
        diffs.mkdir(exist_ok=True)

        for rel in common:
            a_txt = read_text(za, rel)
            b_txt = read_text(zb, rel)

            (extract / f"A__{rel.replace('/', '__')}").write_text(a_txt, encoding="utf-8")
            (extract / f"B__{rel.replace('/', '__')}").write_text(b_txt, encoding="utf-8")

            diff = difflib.unified_diff(
                b_txt.splitlines(),
                a_txt.splitlines(),
                fromfile=f"B/{rel}",
                tofile=f"A/{rel}",
                lineterm=""
            )
            (diffs / f"{rel.replace('/', '__')}.diff.txt").write_text("\n".join(diff) + "\n", encoding="utf-8")

    cg.tlog(None, "INFO", "AUDIT_READMES_OK", f"OK. Wyniki: {out}")

if __name__ == "__main__":
    main()
