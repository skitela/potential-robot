#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import platform
import socket
import subprocess
from pathlib import Path
from typing import Any, Dict, List

UTC = dt.timezone.utc


def iso_utc_now() -> str:
    return dt.datetime.now(tz=UTC).isoformat().replace("+00:00", "Z")


def tcp_check(host: str, port: int, timeout_s: float = 3.0) -> Dict[str, Any]:
    started = dt.datetime.now(tz=UTC)
    ok = False
    err = ""
    try:
        with socket.create_connection((host, int(port)), timeout=timeout_s):
            ok = True
    except Exception as exc:  # pragma: no cover
        err = f"{type(exc).__name__}:{exc}"
    elapsed_ms = int((dt.datetime.now(tz=UTC) - started).total_seconds() * 1000.0)
    return {
        "port": int(port),
        "open": bool(ok),
        "elapsed_ms": elapsed_ms,
        "error": err,
    }


def ping_check(host: str, count: int = 2) -> Dict[str, Any]:
    # Windows ping.
    cmd = ["ping", "-n", str(max(1, int(count))), host]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=20)
        return {
            "ok": bool(proc.returncode == 0),
            "returncode": int(proc.returncode),
            "stdout_tail": "\n".join((proc.stdout or "").splitlines()[-6:]),
            "stderr_tail": "\n".join((proc.stderr or "").splitlines()[-6:]),
        }
    except Exception as exc:  # pragma: no cover
        return {
            "ok": False,
            "returncode": -1,
            "stdout_tail": "",
            "stderr_tail": f"{type(exc).__name__}:{exc}",
        }


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Local preflight for Windows VPS connectivity.")
    ap.add_argument("--host", required=True, help="VPS public IPv4/hostname")
    ap.add_argument("--ports", default="3389,5985,5986,22,443", help="Comma-separated TCP ports")
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--out-json", default="")
    ap.add_argument("--out-txt", default="")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    root = Path(args.root).resolve()
    out_dir = (root / "EVIDENCE" / "vps_prep").resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(tz=UTC).strftime("%Y%m%dT%H%M%SZ")
    out_json = Path(args.out_json).resolve() if str(args.out_json).strip() else (out_dir / f"vps_preflight_{stamp}.json")
    out_txt = Path(args.out_txt).resolve() if str(args.out_txt).strip() else (out_dir / f"vps_preflight_{stamp}.txt")

    ports: List[int] = []
    for raw in str(args.ports).split(","):
        s = raw.strip()
        if not s:
            continue
        try:
            ports.append(int(s))
        except ValueError:
            pass
    if not ports:
        ports = [3389]

    report: Dict[str, Any] = {
        "schema": "oanda.mt5.vps_preflight.local.v1",
        "generated_at_utc": iso_utc_now(),
        "target_host": str(args.host).strip(),
        "ports_checked": ports,
        "local_host": {
            "node": platform.node(),
            "platform": platform.platform(),
            "python_version": platform.python_version(),
        },
        "checks": {
            "ping": ping_check(str(args.host).strip(), count=2),
            "tcp": [tcp_check(str(args.host).strip(), p, timeout_s=3.0) for p in ports],
        },
    }

    report["summary"] = {
        "rdp_open": any((r.get("port") == 3389 and bool(r.get("open"))) for r in report["checks"]["tcp"]),
        "winrm_open": any((r.get("port") in {5985, 5986} and bool(r.get("open"))) for r in report["checks"]["tcp"]),
        "any_open": any(bool(r.get("open")) for r in report["checks"]["tcp"]),
    }

    out_json.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    lines = [
        "VPS_PREFLIGHT_LOCAL",
        f"Generated: {report['generated_at_utc']}",
        f"Target: {report['target_host']}",
        f"Ping OK: {report['checks']['ping']['ok']}",
        f"RDP(3389) open: {report['summary']['rdp_open']}",
        f"WinRM(5985/5986) open: {report['summary']['winrm_open']}",
        "TCP results:",
    ]
    for row in report["checks"]["tcp"]:
        lines.append(f"  - port {row['port']}: open={row['open']} elapsed_ms={row['elapsed_ms']} err={row.get('error','')}")
    out_txt.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"VPS_PREFLIGHT_LOCAL_DONE json={out_json} txt={out_txt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

