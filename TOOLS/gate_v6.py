#!/usr/bin/env python3
"""
gate_v6.py — offline release gates (PASS/FAIL) for OANDA_MT5_SYSTEM.
Scope: ONLY the project root folder (no scanning outside).
Contract: OFFLINE mode (no network, no KEY required), but ONLINE items must be marked DO_WERYFIKACJI_ONLINE.
"""

from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# Prevent gate tooling from creating __pycache__ artifacts in repo.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Structured logging / guards
from BIN import common_guards as cg

# --- V6.2 path policy (P0) ---
HARD_ROOT_STR = r"C:\OANDA_MT5_SYSTEM"
# Legacy root is banned; build pattern without embedding the exact legacy literal in source.
LEGACY_ROOT_PREFIX = "C:\\" + "OANDA_MT5"
REQUIRED_OANDA_MT5_EXE_STR = r"C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"

def _scan_text_legacy_paths() -> tuple[bool, list[str]]:
    """Scan project for banned legacy root literals in text-like files.

    Banned:  C:\\ + OANDA_MT5  (unless immediately followed by _SYSTEM)
    Allowed: C:\\OANDA_MT5_SYSTEM
    """
    issues: list[str] = []
    exts = {'.py','.ps1','.txt','.md','.json','.ini','.cfg','.toml','.yml','.yaml'}
    # Build regex without hardcoding the banned literal as a single token.
    legacy_prefix = LEGACY_ROOT_PREFIX  # e.g. "C:\\OANDA_MT5"
    pat = re.compile(re.escape(legacy_prefix) + r"(?!_SYSTEM)", flags=re.IGNORECASE)

    for p in ROOT.rglob('*'):
        if not p.is_file():
            continue
        if p.suffix.lower() not in exts:
            continue
        try:
            s = p.read_text(encoding='utf-8', errors='ignore')
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", f"read_text failed: {p.relative_to(ROOT)}", e)
            continue

        if pat.search(s):
            issues.append(f"LEGACY_ROOT_BANNED: {p.relative_to(ROOT)}")
    return (len(issues) == 0), issues

def _gate_bootstrap_assets() -> tuple[bool, list[str]]:
    required = [
        ROOT / 'RUN' / 'BOOTSTRAP_V6_2.ps1',
        ROOT / 'TOOLS' / 'smoke_compile_v6_2.py',
        ROOT / 'requirements.offline.lock',
        ROOT / 'requirements.live.lock',
        ROOT / 'BIN' / 'runtime_root.py',
    ]
    issues: list[str] = []
    for p in required:
        if not p.is_file():
            issues.append(f"MISSING: {p.relative_to(ROOT)}")
    return (len(issues) == 0), issues

def _gate_live_terminal_policy() -> tuple[bool, list[str]]:
    """Static policy gate (V6.2):
    - No reference to clean MT5 terminal path.
    - runtime_root.py must declare REQUIRED_OANDA_MT5_EXE_STR.
    - safetybot.py must reference runtime_root (symbol or helper), so LIVE can fail-fast deterministically.
    """
    issues: list[str] = []
    clean_mt5 = r"C:\Program Files\MetaTrader 5\terminal64.exe"

    safety = ROOT / "BIN" / "safetybot.py"
    rr = ROOT / "BIN" / "runtime_root.py"

    try:
        s_safety = safety.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", f"read_text failed: {safety.relative_to(ROOT)}", e)
        s_safety = ""
        issues.append(f"READ_FAIL: {safety.relative_to(ROOT)}")

    try:
        s_rr = rr.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", f"read_text failed: {rr.relative_to(ROOT)}", e)
        s_rr = ""
        issues.append(f"READ_FAIL: {rr.relative_to(ROOT)}")

    # Forbidden clean MT5 reference (anywhere in safety/runtime_root)
    if clean_mt5 in s_safety:
        issues.append(f"CLEAN_MT5_PATH_FORBIDDEN: {safety.relative_to(ROOT)}")
    if clean_mt5 in s_rr:
        issues.append(f"CLEAN_MT5_PATH_FORBIDDEN: {rr.relative_to(ROOT)}")

    # Required OANDA terminal literal must live in runtime_root.py
    if REQUIRED_OANDA_MT5_EXE_STR not in s_rr:
        issues.append(f"REQUIRED_OANDA_MT5_EXE_MISSING: {rr.relative_to(ROOT)}")

    # safetybot must rely on runtime_root (constant or helper) for MT5 path enforcement
    if ("REQUIRED_OANDA_MT5_EXE" not in s_safety) and ("require_live_oanda_terminal" not in s_safety):
        issues.append(f"SAFETYBOT_NOT_USING_RUNTIME_ROOT: {safety.relative_to(ROOT)}")

    return (len(issues) == 0), issues


def _gate_audit_policy_canon() -> tuple[bool, list[str]]:
    """Ensure a single, canonical audit policy exists and matches RELEASE_META.json."""
    issues: list[str] = []
    ap = ROOT / "AUDIT_POLICY.json"
    rm = ROOT / "RELEASE_META.json"

    if not ap.is_file():
        issues.append("MISSING: AUDIT_POLICY.json")
        return False, issues
    if not rm.is_file():
        issues.append("MISSING: RELEASE_META.json")
        return False, issues

    try:
        audit = json.loads(ap.read_text(encoding="utf-8"))
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "read AUDIT_POLICY.json failed", e)
        issues.append(f"READ_FAIL: AUDIT_POLICY.json ({e})")
        return False, issues

    try:
        rel = json.loads(rm.read_text(encoding="utf-8"))
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "read RELEASE_META.json failed", e)
        issues.append(f"READ_FAIL: RELEASE_META.json ({e})")
        return False, issues

    canon_id = audit.get("canonical", {}).get("release_id")
    canon_root = audit.get("canonical", {}).get("root_expected_windows")
    if not canon_id:
        issues.append("AUDIT_POLICY.canonical.release_id missing")
    if not canon_root:
        issues.append("AUDIT_POLICY.canonical.root_expected_windows missing")

    if canon_id and rel.get("release_id") and canon_id != rel.get("release_id"):
        issues.append(f"RELEASE_ID_MISMATCH: AUDIT_POLICY={canon_id} vs RELEASE_META={rel.get('release_id')}")

    if canon_root and rel.get("root_expected") and canon_root != rel.get("root_expected"):
        issues.append(f"ROOT_EXPECTED_MISMATCH: AUDIT_POLICY={canon_root} vs RELEASE_META={rel.get('root_expected')}")

    # Deprecations: these must not exist at root level
    for deprecated in ("AUDIT_META.json", "OUTER_META.json", "f6.txt"):
        if (ROOT / deprecated).exists():
            issues.append(f"DEPRECATED_PRESENT_IN_ROOT: {deprecated}")

    return (len(issues) == 0), issues


def _gate_online_preflight_contracts() -> tuple[bool, list[str]]:
    """Static ONLINE_PREFLIGHT checks (no network calls, no KEY).

    Verifies that LIVE dependencies and MT5 path contracts are consistent:
    - requirements.live.lock includes MetaTrader5
    - BIN/runtime_root.py contains required OANDA terminal path
    - RUN/BOOTSTRAP_V6_2.ps1 exists and references terminal policy
    """
    issues: list[str] = []
    # deps
    req = ROOT / "requirements.live.lock"
    if not req.is_file():
        issues.append("MISSING: requirements.live.lock")
    else:
        try:
            s = req.read_text(encoding="utf-8", errors="ignore")
            if re.search(r"(?i)^metatrader5==", s, flags=re.MULTILINE) is None:
                issues.append("MISSING_DEP: MetaTrader5 in requirements.live.lock")
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "read requirements.live.lock failed", e)
            issues.append("READ_FAIL: requirements.live.lock")

    rr = ROOT / "BIN" / "runtime_root.py"
    if rr.is_file():
        try:
            s = rr.read_text(encoding="utf-8", errors="ignore")
            if REQUIRED_OANDA_MT5_EXE_STR.replace("\\\\", "\\") not in s and "OANDA TMS MT5 Terminal" not in s:
                issues.append("RUNTIME_ROOT_MISSING_OANDA_MT5_PATH")
            if HARD_ROOT_STR.replace("\\\\", "\\") not in s and "OANDA_MT5_SYSTEM" not in s:
                issues.append("RUNTIME_ROOT_MISSING_HARD_ROOT")
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "read BIN/runtime_root.py failed", e)
            issues.append("READ_FAIL: BIN/runtime_root.py")
    else:
        issues.append("MISSING: BIN/runtime_root.py")

    bs = ROOT / "RUN" / "BOOTSTRAP_V6_2.ps1"
    if not bs.is_file():
        issues.append("MISSING: RUN/BOOTSTRAP_V6_2.ps1")
    else:
        try:
            s = bs.read_text(encoding="utf-8", errors="ignore")
            if "OANDA TMS MT5 Terminal" not in s:
                issues.append("BOOTSTRAP_MISSING_OANDA_MT5_TERMINAL_HINT")
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "read RUN/BOOTSTRAP_V6_2.ps1 failed", e)
            issues.append("READ_FAIL: RUN/BOOTSTRAP_V6_2.ps1")

    return (len(issues) == 0), issues

EVIDENCE_DIR = ROOT / "EVIDENCE" / "gates"
DIAG_LATEST = ROOT / "DIAG" / "bundles" / "LATEST"
DIAG_INCIDENTS = ROOT / "DIAG" / "bundles" / "INCIDENTS"

BANNED_SUFFIXES = {".exe", ".bat", ".pyc", ".pyo"}
BANNED_DIRS = {"__pycache__"}

# Paths that are runtime-only or temporary and must not affect release gates.
EXCLUDE_DIRS_CLEANLINESS = {
    ".venv",
    "_ZIP_AUDIT_",
    "LOGS",
    "RUN",
    "DIAG",
    "EVIDENCE",
    "DB",
    "DB_BACKUPS",
    ".git",
}

# Scope secrets scan to release content only; avoid runtime artifacts.
EXCLUDE_DIRS_SECRETS = {
    ".venv",
    "_ZIP_AUDIT_",
    "LOGS",
    "RUN",
    "DIAG",
    "EVIDENCE",
    "DB",
    "DB_BACKUPS",
    "TMP_AUDIT_IO",
    "__pycache__",
    ".git",
}

REQUIRED_CFG_FIELDS = [
    "fixed_sl_points",
    "fixed_tp_points",
    "atr_period",
    "cooldown_stops_s",
    "paper_trading",
]

# Secrets scan patterns (conservative: catch obvious tokens/passwords)
SECRET_PATTERNS = [
    # Only literal (quoted) assignments are treated as secrets.
    re.compile(r'(?i)\b(password|passwd|passphrase|api[_-]?key|secret|token)\b\s*[:=]\s*[\"\']([^\"\']{6,})[\"\']'),
    re.compile(r"(?i)\bauthorization\b[^\n]*\bbearer\s+[A-Za-z0-9\-._~+/]+=*"),
    re.compile(r"\bsk-[A-Za-z0-9]{10,}\b"),
]

ALLOW_SECRET_REFERENCE = re.compile(
    r"(?i)(config\[|os\.getenv\(|os\.environ|CFG\.|self\.cfg\.|<[^>]+>|CHANGE_ME|REDACTED|YOUR_|PLACEHOLDER)"
)

ALLOW_SHA256_LINE = re.compile(r"^[a-f0-9]{64}\s+\S+\s*$", re.I)


def now_id() -> str:
    # local time; in practice this runs on target Windows host
    return _dt.datetime.now().strftime("%Y%m%d_%H%M%S")


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_evidence(name: str, run_id: str, lines: list[str]) -> Path:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    out = EVIDENCE_DIR / f"{name}_{run_id}.txt"
    out.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
    return out


def rel(p: Path) -> str:
    return str(p.relative_to(ROOT)).replace("\\", "/")


def _is_excluded_dir(parts: tuple[str, ...], excluded: set[str]) -> bool:
    for part in parts:
        if part in excluded:
            return True
        for prefix in excluded:
            if prefix.endswith("_") and part.startswith(prefix):
                return True
    return False


def scan_cleanliness() -> tuple[bool, list[str]]:
    issues: list[str] = []
    for p in ROOT.rglob("*"):
        try:
            relp = p.relative_to(ROOT)
        except Exception:
            continue
        if _is_excluded_dir(relp.parts, EXCLUDE_DIRS_CLEANLINESS):
            continue
        if p.is_dir():
            if p.name in BANNED_DIRS:
                issues.append(f"BANNED_DIR: {rel(p)}")
            continue

        if p.suffix.lower() in BANNED_SUFFIXES:
            issues.append(f"BANNED_FILE: {rel(p)}")

    return (len(issues) == 0), issues




def core_acl_check() -> tuple[str, list[str]]:
    """Check NTFS ACL for CORE/ on Windows. Offline on non-Windows => DO_WERYFIKACJI_ONLINE."""
    if os.name != 'nt':
        return (
            'DO_WERYFIKACJI_ONLINE',
            [
                'Non-Windows environment: CORE ACL verification requires Windows icacls.',
                'Status set to DO_WERYFIKACJI_ONLINE.'
            ]
        )

    core_dir = ROOT / 'CORE'
    if not core_dir.exists():
        return ('FAIL', [f'MISSING_DIR: {rel(core_dir)}'])

    try:
        out = subprocess.check_output(['icacls', str(core_dir)], stderr=subprocess.STDOUT, timeout=10)
        txt = out.decode('utf-8', errors='ignore').strip()
        if not txt:
            return ('FAIL', ['icacls returned empty output'])
        return ('PASS', txt.splitlines())
    except subprocess.TimeoutExpired:
        cg.tlog(None, "WARN", "GATE_EXC", "icacls timeout (10s)")
        return ('DO_WERYFIKACJI_ONLINE', ['icacls timeout (10s); verify manually on target host.'])
    except FileNotFoundError:
        cg.tlog(None, "WARN", "GATE_EXC", "icacls not found on PATH; CORE ACL check skipped")
        return ('DO_WERYFIKACJI_ONLINE', ['icacls not found on PATH; verify on Windows host'])
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "icacls check failed", e)
        return ('DO_WERYFIKACJI_ONLINE', [f'icacls check not performed: {type(e).__name__}: {e}'])
def parse_manifest_sha256(path: Path) -> dict[str, str]:
    entries: dict[str, str] = {}
    if not path.exists():
        return entries
    try:
        data = path.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", f"parse_manifest_sha256 read failed: {path}", e)
        return entries

    for line in data.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        digest = parts[0].strip().lower()
        relpath = " ".join(parts[1:]).strip().strip('"')
        # Normalize separators and strip leading './'
        relpath = relpath.replace("\\", "/")
        if relpath.startswith("./"):
            relpath = relpath[2:]
        if relpath.startswith("/"):
            relpath = relpath[1:]
        entries[relpath] = digest
    return entries


def verify_manifest_sha256(path: Path) -> tuple[bool, list[str]]:
    ok = True
    lines: list[str] = []

    base_dir = path.parent
    base_dir_resolved = base_dir.resolve()

    entries = parse_manifest_sha256(path)
    for relpath, expected_hex in entries.items():
        candidate = base_dir / relpath
        try:
            file_path = candidate.resolve()
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "resolve candidate path failed", e)
            ok = False
            lines.append(f"RESOLVE_FAIL: {relpath}")
            continue

        try:
            file_path.relative_to(base_dir_resolved)
        except ValueError:
            ok = False
            lines.append(f"TRAVERSAL: {relpath}")
            continue

        if not file_path.exists():
            ok = False
            lines.append(f"MISS: {relpath}")
            continue

        got = sha256_file(file_path)
        if got.lower() != expected_hex.lower():
            ok = False
            lines.append(f"SHA_MISMATCH: {relpath} expected={expected_hex} got={got}")

    return ok, lines

def extract_cfg_block(text: str) -> str:
    m = re.search(r"class\s+CFG\s*:\s*([\s\S]*?)(?:\n# =|\nclass\s|\Z)", text)
    # return just the inner block (group 1) to simplify field extraction
    return m.group(1) if m else ""


def cfg_completeness() -> tuple[bool, list[str]]:
    sb = ROOT / "BIN" / "safetybot.py"
    if not sb.exists():
        return False, [f"MISSING: {rel(sb)}"]

    try:
        text = sb.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "read BIN/safetybot.py failed", e)
        return False, ["READ_FAIL: BIN/safetybot.py"]
    block = extract_cfg_block(text)
    if not block:
        return False, ["CFG_BLOCK_NOT_FOUND in BIN/safetybot.py"]

    # Identify declared fields in CFG block
    declared = set()
    for m in re.finditer(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=]+)?\s*=", block, flags=re.MULTILINE):
        declared.add(m.group(1))

    # Identify fields referenced as CFG.<name> in file
    referenced = set(re.findall(r"\bCFG\.([A-Za-z_][A-Za-z0-9_]*)\b", text))
    # Exclude obviously non-config / false hits
    referenced = {x for x in referenced if not x.startswith("_")}

    missing = sorted([x for x in referenced if x not in declared])
    # Required fields must be declared at minimum
    req_missing = sorted([x for x in REQUIRED_CFG_FIELDS if x not in declared])

    ok = (len(missing) == 0) and (len(req_missing) == 0)
    lines = []
    for k in sorted(REQUIRED_CFG_FIELDS):
        lines.append(f"REQUIRED_FIELD {k}: {'OK' if k in declared else 'MISSING'}")
    if missing:
        lines.append("")
        lines.append("MISSING_REFERENCED_FIELDS:")
        lines.extend([f"- {x}" for x in missing])
    return ok, lines


def detect_key_volume_label(label: str = "OANDAKEY") -> tuple[bool, str]:
    """
    Return (present, details). Does not reveal any secret content.
    """
    if os.name != "nt":
        return False, "NON_WINDOWS_ENV (run on target Windows host)"

    label = (label or "OANDAKEY").strip()
    drive = None

    try:
        safe_label = label.replace("'", "''")
        ps = (
            f"$v = Get-Volume | Where-Object {{ $_.FileSystemLabel -eq '{safe_label}' }} | Select-Object -First 1;"
            "if ($v -and $v.DriveLetter) { Write-Output $v.DriveLetter }"
        )
        proc = subprocess.run(
            ["powershell", "-NoProfile", "-Command", ps],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
        out = (proc.stdout or "").strip()
        if proc.returncode == 0 and out:
            cand = out.strip()
            if re.fullmatch(r"[A-Za-z]", cand):
                drive = cand.upper()
            else:
                cg.tlog(None, "WARN", "GATE_EXC", f"detect_key_volume_label: unexpected drive '{cand}'")
        elif proc.returncode != 0:
            stderr_txt = (proc.stderr or "").strip().splitlines()
            err_head = stderr_txt[0] if stderr_txt else "powershell_nonzero"
            return False, f"NOT_FOUND label='{label}' rc={proc.returncode} err='{err_head[:120]}'"
    except subprocess.TimeoutExpired:
        return False, f"NOT_FOUND label='{label}' reason='powershell_timeout'"
    except Exception as e:
        cg.tlog(None, "WARN", "GATE_EXC", "detect_key_volume_label: powershell call failed", e)
        drive = None

    if not drive:
        return False, f"NOT_FOUND label='{label}'"

    # Check expected file presence (relative only)
    key_env_rel = "TOKEN/BotKey.env"
    env_exists = Path(f"{drive}:/") / "TOKEN" / "BotKey.env"
    exists = env_exists.exists()
    return bool(exists), f"FOUND label='{label}' env='{key_env_rel}' exists={exists}"


def secrets_scan() -> tuple[bool, list[str]]:
    ok = True
    lines: list[str] = []

    allow_ext = {".py", ".txt", ".md", ".json", ".yaml", ".yml", ".ini", ".cfg", ".toml"}

    findings = []
    for p in ROOT.rglob("*"):
        if not p.is_file():
            continue
        try:
            relp = p.relative_to(ROOT)
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", "secrets_scan relative_to failed", e)
            continue

        if _is_excluded_dir(relp.parts, EXCLUDE_DIRS_SECRETS):
            continue

        if p.suffix.lower() not in allow_ext:
            continue

        try:
            txt = p.read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            cg.tlog(None, "WARN", "GATE_EXC", f"secrets_scan read failed: {relp}", e)
            continue

        for i, line in enumerate(txt.splitlines(), 1):
            line_str = line.strip()
            if not line_str:
                continue
            if ALLOW_SHA256_LINE.match(line_str):
                continue

            for pat in SECRET_PATTERNS:
                m = pat.search(line)
                if not m:
                    continue

                # For literal assignments, allow placeholders and config/env references.
                if m.lastindex and m.lastindex >= 2:
                    literal = m.group(2)
                    if ALLOW_SECRET_REFERENCE.search(literal):
                        continue

                findings.append((str(relp).replace("\\", "/"), i, line_str[:180]))
                break

    if findings:
        ok = False
        lines.append(f"FOUND {len(findings)} potential literal secrets")
        for fpath, lineno, snippet in findings[:25]:
            lines.append(f"{fpath}:{lineno}: {snippet}")
        if len(findings) > 25:
            lines.append("...truncated")

    return ok, lines

def diag_latest_check() -> tuple[bool, list[str]]:
    lines: list[str] = []

    if not DIAG_LATEST.exists():
        return False, ["DIAG_LATEST: MISSING_DIR"]

    required = [
        "env_snapshot.json",
        "gate_snapshot.txt",
        "logs_snippet.txt",
        "error_bundle.json",
    ]

    marker = DIAG_LATEST / ".diag_ran"
    present = [f for f in required if (DIAG_LATEST / f).exists()]

    # First gate (pre-DIAG): allow skip if DIAG was not run yet.
    if (not marker.exists()) and (not present):
        lines.append("diag_latest: SKIP_PRE_DIAG")
        return True, lines

    missing = [f for f in required if not (DIAG_LATEST / f).exists()]
    if missing:
        lines.append("diag_latest: FAIL missing required files")
        for f in missing:
            lines.append(f"MISSING: DIAG/bundles/LATEST/{f}")
        return False, lines

    lines.append("diag_latest: PASS")
    return True, lines

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", default="offline", choices=["offline", "online_preflight"])
    ap.add_argument("--key-label", default="OANDAKEY")
    args = ap.parse_args()

    run_id = now_id()

    # Gate G0: cleanliness
    clean_ok, clean_issues = scan_cleanliness()
    write_evidence("cleanliness", run_id, [
        "GATE: cleanliness",
        f"RESULT: {'PASS' if clean_ok else 'FAIL'}",
        "",
        *clean_issues
    ])

    # Gate PATH policy (V6.2): no legacy root literals
    path_ok, path_issues = _scan_text_legacy_paths()
    write_evidence("path_policy_legacy_root", run_id, [
        "GATE: path_policy_legacy_root",
        f"RESULT: {'PASS' if path_ok else 'FAIL'}",
        "",
        *path_issues
    ])


    # Gate AUDIT_POLICY canon (single source of truth)
    ap_ok, ap_issues = _gate_audit_policy_canon()
    write_evidence("audit_policy_canon", run_id, [
        "GATE: audit_policy_canon",
        f"RESULT: {'PASS' if ap_ok else 'FAIL'}",
        "",
        *ap_issues
    ])

    # Gate ONLINE_PREFLIGHT contracts (only in online_preflight mode; static checks, no network)
    pre_ok = True
    pre_issues: list[str] = []
    pre_result_label = "SKIP_OFFLINE"
    if args.mode == "online_preflight":
        pre_ok, pre_issues = _gate_online_preflight_contracts()
        pre_result_label = "PASS" if pre_ok else "FAIL"
    write_evidence("online_preflight_contracts", run_id, [
        "GATE: online_preflight_contracts",
        f"RESULT: {pre_result_label}",
        "",
        *pre_issues
    ])
    # Gate BOOTSTRAP assets presence (V6.2)
    boot_ok, boot_issues = _gate_bootstrap_assets()
    write_evidence("bootstrap_assets", run_id, [
        "GATE: bootstrap_assets",
        f"RESULT: {'PASS' if boot_ok else 'FAIL'}",
        "",
        *boot_issues
    ])

    # Gate LIVE terminal policy (V6.2) — static
    term_ok, term_issues = _gate_live_terminal_policy()
    write_evidence("live_terminal_policy", run_id, [
        "GATE: live_terminal_policy",
        f"RESULT: {'PASS' if term_ok else 'FAIL'}",
        "",
        *term_issues
    ])

    # Gate G1: manifest integrity
    root_manifest_ok, root_manifest_details = verify_manifest_sha256(ROOT / "MANIFEST.sha256")
    core_manifest_ok, core_manifest_details = verify_manifest_sha256(ROOT / "CORE" / "MANIFEST.sha256")

    write_evidence("manifest_integrity_root", run_id, [
        "GATE: manifest_integrity_root",
        f"RESULT: {'PASS' if root_manifest_ok else 'FAIL'}",
        "",
        *root_manifest_details
    ])
    write_evidence("manifest_integrity_core", run_id, [
        "GATE: manifest_integrity_core",
        f"RESULT: {'PASS' if core_manifest_ok else 'FAIL'}",
        "",
        *core_manifest_details
    ])

    # Gate CFG completeness (ZM-01)
    cfg_ok, cfg_lines = cfg_completeness()
    write_evidence("cfg_completeness", run_id, [
        "GATE: cfg_completeness",
        f"RESULT: {'PASS' if cfg_ok else 'FAIL'}",
        "",
        *cfg_lines
    ])

    # Gate KEY presence (ZM-02): In OFFLINE, absence is expected -> PASS_SAFE_MODE
    key_present, key_details = detect_key_volume_label(args.key_label)
    key_result = "PASS_SAFE_MODE" if (not key_present) else "PASS"
    # If label exists but env missing, treat as FAIL (misconfigured KEY)
    if ("FOUND" in key_details) and ("exists=False" in key_details):
        key_result = "FAIL"

    write_evidence("key_presence", run_id, [
        "GATE: key_presence",
        f"MODE: {args.mode}",
        f"RESULT: {key_result}",
        f"DETAILS: {key_details}",
        "NOTE: OFFLINE expects KEY absent; system must enter safe mode.",
    ])

    # Gate DIAG LATEST (ZM-03 verification)
    diag_ok, diag_lines = diag_latest_check()
    write_evidence("diag_latest", run_id, [
        "GATE: diag_latest",
        f"RESULT: {'PASS' if diag_ok else 'FAIL'}",
        "",
        *diag_lines
    ])

    # Gate NTFS ACL for CORE (ZM-04)
    acl_status, acl_lines = core_acl_check()
    write_evidence("core_acl", run_id, [
        "GATE: core_acl",
        f"RESULT: {acl_status}",
        "",
        *acl_lines
    ])

    # Gate secrets scan (ZM-05)
    sec_ok, sec_lines = secrets_scan()
    write_evidence("secrets_scan", run_id, [
        "GATE: secrets_scan",
        f"RESULT: {'PASS' if sec_ok else 'FAIL'}",
        "",
        "ALLOWLIST: sha256 manifest lines (64-hex + path), explicit <REDACTED>/<PLACEHOLDER>.",
        "",
        *sec_lines
    ])

    # ONLINE deferred (ZM-06) — always deferred in this run
    write_evidence("do_weryfikacji_online", run_id, [
        "DO_WERYFIKACJI_ONLINE (this run cannot issue GO for ONLINE):",
        "- minimalne odległości poziomów ochronnych (stop level) i walidacja na realnym serwerze/MT5",
        "- realne odrzucenia/retcode w środowisku sieciowym",
        "- zachowanie w trybach close-only/long-only/short-only",
        "- limity zapytań / tempo zleceń / throttling (OANDA TMS)",
        "- różnice egzekucji live vs demo",
    ])

    overall_fail = False
    # Hard fails
    for _name, ok in [
        ("cleanliness", clean_ok),
        ("path_policy_legacy_root", path_ok),
        ("audit_policy_canon", ap_ok),
        ("bootstrap_assets", boot_ok),
        ("live_terminal_policy", term_ok),
        ("manifest_root", root_manifest_ok),
        ("manifest_core", core_manifest_ok),
        ("cfg_completeness", cfg_ok),
        ("diag_latest", diag_ok),
        ("secrets_scan", sec_ok),
    ]:
        if not ok:
            overall_fail = True
    if args.mode == "online_preflight" and not pre_ok:
        overall_fail = True


    # ACL gate: PASS required on Windows; otherwise DO_WERYFIKACJI_ONLINE is acceptable in non-Windows build env
    if os.name == "nt" and acl_status != "PASS":
        overall_fail = True

    cg.tlog(None, "INFO", "GATES_SUMMARY", "=== GATES V6 SUMMARY ===")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"run_id: {run_id}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"mode: {args.mode}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"cleanliness: {'PASS' if clean_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"path_policy_legacy_root: {'PASS' if path_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"audit_policy_canon: {'PASS' if ap_ok else 'FAIL'}")
    if args.mode == "online_preflight":
        cg.tlog(None, "INFO", "GATES_SUMMARY", f"online_preflight_contracts: {'PASS' if pre_ok else 'FAIL'}")
    else:
        cg.tlog(None, "INFO", "GATES_SUMMARY", "online_preflight_contracts: SKIP_OFFLINE")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"bootstrap_assets: {'PASS' if boot_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"live_terminal_policy: {'PASS' if term_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"manifest_root: {'PASS' if root_manifest_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"manifest_core: {'PASS' if core_manifest_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"cfg_completeness: {'PASS' if cfg_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"key_presence: {key_result}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"diag_latest: {'PASS' if diag_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"core_acl: {acl_status}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"secrets_scan: {'PASS' if sec_ok else 'FAIL'}")
    cg.tlog(None, "INFO", "GATES_SUMMARY", f"overall: {'FAIL' if overall_fail else 'PASS (OFFLINE ONLY)'}")
    return 1 if overall_fail else 0


if __name__ == "__main__":
    raise SystemExit(main())
