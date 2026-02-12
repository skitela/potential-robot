from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict

DEFAULT_ROTATION_DAYS = 60
PROVIDERS = ("openai", "gemini")


def _local_appdata() -> Path:
    raw = os.environ.get("LOCALAPPDATA")
    if raw:
        return Path(raw)
    return Path.home() / "AppData" / "Local"


def secret_root(root_override: str | None = None) -> Path:
    if root_override:
        return Path(root_override)
    env_root = os.environ.get("LLM_SECRET_ROOT")
    if env_root:
        return Path(env_root)
    return _local_appdata() / "OANDA_MT5_SYSTEM" / "LLM_SECRETS_DPAPI"


def secret_paths(provider: str, root_override: str | None = None) -> Dict[str, Path]:
    if provider not in PROVIDERS:
        raise ValueError(f"Unsupported provider: {provider}")
    root = secret_root(root_override)
    pdir = root / provider
    return {
        "provider": provider,
        "secret_root": root,
        "secret_dir": pdir,
        "cipher_path": pdir / "api_key.dpapi",
        "meta_path": pdir / "metadata.json",
    }


def _safe_parse_iso(ts: str | None) -> datetime | None:
    raw = str(ts or "").strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(timezone.utc)
    except Exception:
        return None


def load_metadata(provider: str, root_override: str | None = None) -> Dict[str, Any]:
    paths = secret_paths(provider, root_override)
    meta_path = paths["meta_path"]
    if not meta_path.exists():
        return {}
    try:
        data = json.loads(meta_path.read_text(encoding="utf-8-sig"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def rotation_status(
    provider: str,
    rotation_days: int = DEFAULT_ROTATION_DAYS,
    root_override: str | None = None,
) -> Dict[str, Any]:
    paths = secret_paths(provider, root_override)
    meta = load_metadata(provider, root_override)
    cipher_exists = paths["cipher_path"].exists()

    created_at = str(meta.get("created_at") or "")
    last_rotated_at = str(meta.get("last_rotated_at") or created_at or "")
    ref_dt = _safe_parse_iso(last_rotated_at) or _safe_parse_iso(created_at)

    age_days: int | None = None
    if ref_dt is not None:
        age_days = max(0, int((datetime.now(timezone.utc) - ref_dt).days))

    rotation_due = bool(cipher_exists and age_days is not None and age_days >= int(rotation_days))
    status = "missing"
    if cipher_exists:
        status = "rotation_due" if rotation_due else "present"

    return {
        "provider": provider,
        "status": status,
        "present": bool(cipher_exists),
        "rotation_due": bool(rotation_due),
        "age_days": age_days,
        "created_at": created_at,
        "last_rotated_at": last_rotated_at,
        "ciphertext_path": str(paths["cipher_path"]),
        "metadata_path": str(paths["meta_path"]),
    }


def all_rotation_status(
    rotation_days: int = DEFAULT_ROTATION_DAYS,
    root_override: str | None = None,
) -> Dict[str, Dict[str, Any]]:
    return {p: rotation_status(p, rotation_days=rotation_days, root_override=root_override) for p in PROVIDERS}

