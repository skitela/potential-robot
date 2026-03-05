from __future__ import annotations

import argparse
import datetime as dt
import fnmatch
import json
import os
from pathlib import Path
import zipfile

UTC = dt.timezone.utc

WEEKDAY_MAP = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

SKIP_DIR_NAMES = {
    "__pycache__",
    ".pytest_cache",
}

SKIP_FILE_PATTERNS = [
    "*.pyc",
    "*.pyo",
    "*.lock",
    "*.pid",
    "*.tmp.*",
]


def _now_utc() -> dt.datetime:
    return dt.datetime.now(tz=UTC)


def _read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return dict(json.loads(path.read_text(encoding="utf-8")))
    except Exception:
        return {}


def _write_json_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def _parse_ts(value: str) -> dt.datetime | None:
    raw = str(value or "").strip()
    if not raw:
        return None
    try:
        if raw.endswith("Z"):
            raw = raw[:-1] + "+00:00"
        out = dt.datetime.fromisoformat(raw)
        if out.tzinfo is None:
            out = out.replace(tzinfo=UTC)
        return out.astimezone(UTC)
    except Exception:
        return None


def _should_run(
    now_utc: dt.datetime,
    last_success_utc: dt.datetime | None,
    preferred_weekday: int,
    max_days_without_backup: int,
    force: bool,
) -> tuple[bool, str]:
    if force:
        return True, "FORCE"
    if last_success_utc is None:
        return True, "FIRST_RUN"

    days_since = (now_utc - last_success_utc).total_seconds() / 86400.0
    is_preferred_weekday = now_utc.weekday() == int(preferred_weekday)
    if is_preferred_weekday and now_utc.date() != last_success_utc.date():
        return True, f"PREFERRED_WEEKDAY:{now_utc.strftime('%A').upper()}"
    if days_since >= float(max(1, max_days_without_backup)):
        return True, f"CATCHUP_OVERDUE:{days_since:.2f}d"
    return False, f"NOT_DUE:{days_since:.2f}d"


def _zip_directory(
    source_dir: Path,
    target_zip: Path,
    skip_dir_names: set[str],
    skip_file_patterns: list[str],
) -> dict:
    source_dir = source_dir.resolve()
    target_zip.parent.mkdir(parents=True, exist_ok=True)
    files_added = 0
    bytes_added = 0
    errors: list[str] = []

    with zipfile.ZipFile(target_zip, mode="w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, dirs, files in os.walk(source_dir):
            dirs[:] = [d for d in dirs if d not in skip_dir_names]
            root_path = Path(root)
            for name in files:
                skip = False
                for pat in skip_file_patterns:
                    if fnmatch.fnmatch(name, pat):
                        skip = True
                        break
                if skip:
                    continue
                src = root_path / name
                try:
                    rel = src.relative_to(source_dir)
                    arcname = str(Path(source_dir.name) / rel).replace("\\", "/")
                    zf.write(src, arcname)
                    files_added += 1
                    try:
                        bytes_added += int(src.stat().st_size)
                    except Exception as exc:
                        _ = exc
                except Exception as exc:
                    errors.append(f"{src}: {type(exc).__name__}: {exc}")

    return {
        "source_dir": str(source_dir),
        "target_zip": str(target_zip),
        "files_added": int(files_added),
        "bytes_added": int(bytes_added),
        "errors": errors,
    }


def _resolve_token_env_path(token_env_path: str, usb_label: str) -> Path | None:
    if token_env_path:
        p = Path(token_env_path).expanduser().resolve()
        return p if p.exists() else None
    label = str(usb_label or "").strip().upper()
    if not label:
        return None
    for dl in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        p = Path(f"{dl}:\\TOKEN\\BotKey.env")
        if p.exists():
            try:
                import subprocess

                cmd = [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    f"(Get-Volume -DriveLetter {dl} -ErrorAction SilentlyContinue).FileSystemLabel",
                ]
                out = subprocess.check_output(cmd, text=True, timeout=5).strip().upper()
                if out == label:
                    return p
            except Exception:
                continue
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Weekly full-system backup with catch-up policy.")
    ap.add_argument("--root", default="C:\\OANDA_MT5_SYSTEM")
    ap.add_argument("--lab-data-root", default="C:\\OANDA_MT5_LAB_DATA")
    ap.add_argument("--backup-root", default="C:\\OANDA_MT5_BACKUPS")
    ap.add_argument("--preferred-weekday", default="sunday", choices=sorted(WEEKDAY_MAP.keys()))
    ap.add_argument("--max-days-without-backup", type=int, default=7)
    ap.add_argument("--state-file", default="RUN/weekly_backup_state.json")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--include-usb-token", action="store_true")
    ap.add_argument("--token-env-path", default="")
    ap.add_argument("--usb-label", default="OANDAKEY")
    args = ap.parse_args()

    now = _now_utc()
    stamp = now.strftime("%Y%m%dT%H%M%SZ")
    root = Path(args.root).resolve()
    lab_data_root = Path(args.lab_data_root).resolve()
    backup_root = Path(args.backup_root).resolve()
    state_path = (root / str(args.state_file)).resolve()
    report_dir = (root / "EVIDENCE" / "backups").resolve()
    report_path = report_dir / f"weekly_backup_{stamp}.json"
    report_latest = report_dir / "weekly_backup_latest.json"

    state = _read_json(state_path)
    last_success_utc = _parse_ts(str(state.get("last_success_utc", "")))
    should_run, reason = _should_run(
        now_utc=now,
        last_success_utc=last_success_utc,
        preferred_weekday=int(WEEKDAY_MAP[str(args.preferred_weekday).lower()]),
        max_days_without_backup=int(max(1, args.max_days_without_backup)),
        force=bool(args.force),
    )

    base_report: dict = {
        "schema": "oanda_mt5.weekly_system_backup.v1",
        "ts_utc": now.isoformat(),
        "root": str(root),
        "lab_data_root": str(lab_data_root),
        "backup_root": str(backup_root),
        "preferred_weekday": str(args.preferred_weekday).lower(),
        "max_days_without_backup": int(max(1, args.max_days_without_backup)),
        "decision": {"should_run": bool(should_run), "reason": str(reason)},
        "artifacts": [],
        "status": "SKIP",
    }

    if not should_run:
        _write_json_atomic(report_path, base_report)
        _write_json_atomic(report_latest, base_report)
        state_out = {
            "schema": "oanda_mt5.weekly_backup_state.v1",
            "last_run_utc": now.isoformat(),
            "last_status": "SKIP",
            "last_reason": str(reason),
            "last_success_utc": state.get("last_success_utc", ""),
            "last_backup_dir": state.get("last_backup_dir", ""),
            "last_report_path": str(report_path),
        }
        _write_json_atomic(state_path, state_out)
        print("WEEKLY_BACKUP_SKIP", reason)
        return 0

    run_dir = backup_root / f"weekly_backup_{stamp}"
    run_dir.mkdir(parents=True, exist_ok=True)

    errors: list[str] = []

    system_zip = run_dir / "oanda_mt5_system.zip"
    res_system = _zip_directory(
        source_dir=root,
        target_zip=system_zip,
        skip_dir_names=set(SKIP_DIR_NAMES),
        skip_file_patterns=list(SKIP_FILE_PATTERNS),
    )
    base_report["artifacts"].append({"type": "system_zip", **res_system})
    errors.extend(res_system.get("errors", []))

    if lab_data_root.exists():
        lab_zip = run_dir / "oanda_mt5_lab_data.zip"
        res_lab = _zip_directory(
            source_dir=lab_data_root,
            target_zip=lab_zip,
            skip_dir_names=set(SKIP_DIR_NAMES),
            skip_file_patterns=list(SKIP_FILE_PATTERNS),
        )
        base_report["artifacts"].append({"type": "lab_data_zip", **res_lab})
        errors.extend(res_lab.get("errors", []))
    else:
        base_report["artifacts"].append(
            {
                "type": "lab_data_zip",
                "source_dir": str(lab_data_root),
                "status": "MISSING_SOURCE",
            }
        )

    if bool(args.include_usb_token):
        token_env = _resolve_token_env_path(args.token_env_path, args.usb_label)
        if token_env and token_env.exists():
            dst = run_dir / "token_BotKey.env"
            dst.write_bytes(token_env.read_bytes())
            base_report["artifacts"].append(
                {
                    "type": "usb_token_env_copy",
                    "source": str(token_env),
                    "target": str(dst),
                    "bytes": int(dst.stat().st_size),
                }
            )
        else:
            base_report["artifacts"].append(
                {
                    "type": "usb_token_env_copy",
                    "status": "MISSING_SOURCE",
                    "usb_label": str(args.usb_label),
                }
            )

    total_files = sum(int((a.get("files_added") or 0)) for a in base_report["artifacts"] if isinstance(a, dict))
    total_bytes = sum(int((a.get("bytes_added") or 0)) for a in base_report["artifacts"] if isinstance(a, dict))
    if total_files <= 0:
        errors.append("NO_FILES_ADDED")

    base_report["summary"] = {
        "artifacts_n": len(base_report["artifacts"]),
        "total_files_added": int(total_files),
        "total_bytes_added": int(total_bytes),
        "error_n": len(errors),
    }
    if errors:
        base_report["status"] = "FAIL"
        base_report["errors"] = errors
    else:
        base_report["status"] = "PASS"
        base_report["backup_dir"] = str(run_dir)

    _write_json_atomic(report_path, base_report)
    _write_json_atomic(report_latest, base_report)

    state_out = {
        "schema": "oanda_mt5.weekly_backup_state.v1",
        "last_run_utc": now.isoformat(),
        "last_status": base_report["status"],
        "last_reason": str(reason),
        "last_report_path": str(report_path),
        "last_backup_dir": str(run_dir) if base_report["status"] == "PASS" else state.get("last_backup_dir", ""),
        "last_success_utc": now.isoformat() if base_report["status"] == "PASS" else state.get("last_success_utc", ""),
    }
    _write_json_atomic(state_path, state_out)

    print(
        "WEEKLY_BACKUP_RESULT",
        f"status={base_report['status']}",
        f"reason={reason}",
        f"files={total_files}",
        f"bytes={total_bytes}",
    )
    return 0 if base_report["status"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

