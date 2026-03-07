from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile
import zipfile

UTC = dt.timezone.utc


def iso_utc_now() -> str:
    return dt.datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def copy_tree(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    shutil.copytree(src, dst, dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__", ".pytest_cache", "*.tmp", "*.lock"))


def sqlite_backup(src: Path, dst: Path) -> None:
    ensure_dir(dst.parent)
    with sqlite3.connect(f"file:{src}?mode=ro", uri=True, timeout=20) as src_conn:
        with sqlite3.connect(str(dst), timeout=20) as dst_conn:
            src_conn.backup(dst_conn)


def build_zip_from_dir(source_dir: Path, zip_path: Path) -> None:
    ensure_dir(zip_path.parent)
    with zipfile.ZipFile(zip_path, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in {"__pycache__", ".pytest_cache"}]
            root_path = Path(root)
            for file_name in files:
                src = root_path / file_name
                rel = src.relative_to(source_dir)
                zf.write(src, arcname=str(rel).replace("\\", "/"))


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Build VPS data/state bundle with safe SQLite backups.")
    ap.add_argument("--root", default=r"C:\OANDA_MT5_SYSTEM")
    ap.add_argument("--lab-data-root", default=r"C:\OANDA_MT5_LAB_DATA")
    ap.add_argument("--out-dir", default=r"C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_prep")
    ap.add_argument("--bundle-name", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve()
    out_dir = ensure_dir(Path(args.out_dir).resolve())

    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    bundle_name = args.bundle_name.strip() or f"oanda_mt5_data_bundle_{stamp}.zip"
    bundle_path = out_dir / bundle_name

    stage = Path(tempfile.mkdtemp(prefix="oanda_vps_data_bundle_"))
    try:
        meta_src = root / "META"
        meta_dst = stage / "META"
        copy_tree(meta_src, meta_dst)

        db_src = root / "DB"
        db_dst = stage / "DB"
        ensure_dir(db_dst)
        db_files = []
        for src in sorted(db_src.glob("*.sqlite")):
            if src.name.startswith("_tmp_probe"):
                continue
            dst = db_dst / src.name
            sqlite_backup(src, dst)
            db_files.append(src.name)

        lab_dst = stage / "LAB_DATA"
        copy_tree(lab_data_root, lab_dst)

        manifest = {
            "schema": "oanda.mt5.vps.data_bundle.v1",
            "generated_at_utc": iso_utc_now(),
            "root": str(root),
            "lab_data_root": str(lab_data_root),
            "db_files": db_files,
            "includes_meta": meta_src.exists(),
            "includes_lab_data": lab_data_root.exists(),
            "bundle_path": str(bundle_path),
        }
        (stage / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        if bundle_path.exists():
            bundle_path.unlink()
        build_zip_from_dir(stage, bundle_path)

        latest_json = out_dir / "vps_data_bundle_latest.json"
        latest_txt = out_dir / "vps_data_bundle_latest.txt"
        latest_json.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        latest_txt.write_text(
            "\n".join(
                [
                    "VPS_DATA_BUNDLE_LATEST",
                    f"generated_at_utc={manifest['generated_at_utc']}",
                    f"bundle_path={bundle_path}",
                    f"db_files={','.join(db_files)}",
                    f"includes_meta={manifest['includes_meta']}",
                    f"includes_lab_data={manifest['includes_lab_data']}",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        print(f"VPS_DATA_BUNDLE_DONE path={bundle_path}")
        return 0
    finally:
        shutil.rmtree(stage, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
