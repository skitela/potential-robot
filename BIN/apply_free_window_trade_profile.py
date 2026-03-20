# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any, Dict

try:
    from .runtime_root import get_runtime_root
except Exception:  # pragma: no cover
    from runtime_root import get_runtime_root


def _safe_load_json(path: Path) -> Dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise SystemExit(f"CONFIG_FAIL: expected object in {path}")
    return payload


def _dump_json(path: Path, payload: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _resolve_season(raw: str) -> str:
    season = str(raw or "auto").strip().lower()
    if season in {"winter", "summer"}:
        return season
    # Europe/Warsaw DST starts at the end of March, so for this project
    # a lightweight profile split by month is enough for generated configs.
    import datetime as dt
    now = dt.datetime.now()
    return "summer" if now.month in {4, 5, 6, 7, 8, 9, 10} else "winter"


def build_profile(base_strategy: Dict[str, Any], runtime_profile: Dict[str, Any], *, season: str) -> Dict[str, Any]:
    out = copy.deepcopy(base_strategy)
    profiles = runtime_profile.get("profiles") if isinstance(runtime_profile.get("profiles"), dict) else {}
    profile = profiles.get(season) if isinstance(profiles.get(season), dict) else {}
    if not profile:
        raise SystemExit(f"PROFILE_FAIL: missing season profile {season}")

    shared = runtime_profile.get("shared_overrides") if isinstance(runtime_profile.get("shared_overrides"), dict) else {}
    for key, value in shared.items():
        out[key] = value

    out["symbols_to_trade"] = list(profile.get("symbols_to_trade") or [])
    out["trade_windows"] = dict(profile.get("trade_windows") or {})
    out["trade_window_symbol_intents"] = dict(profile.get("trade_window_symbol_intents") or {})
    out["free_window_training_profile_active"] = True
    out["free_window_training_profile_season"] = str(season)
    out["free_window_training_profile_schema"] = str(runtime_profile.get("schema") or "")
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Build seasonal free-window runtime strategy for OANDA_MT5_SYSTEM.")
    parser.add_argument("--root", default=str(get_runtime_root(enforce=True)))
    parser.add_argument("--season", default="auto", choices=["auto", "winter", "summer"])
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    base_path = root / "CONFIG" / "strategy.json"
    runtime_path = root / "CONFIG" / "free_window_trade_runtime_v1.json"
    if not base_path.exists():
        raise SystemExit(f"CONFIG_FAIL: missing {base_path}")
    if not runtime_path.exists():
        raise SystemExit(f"CONFIG_FAIL: missing {runtime_path}")

    season = _resolve_season(args.season)
    base_strategy = _safe_load_json(base_path)
    runtime_profile = _safe_load_json(runtime_path)
    payload = build_profile(base_strategy, runtime_profile, season=season)

    if args.out:
      out_path = Path(args.out).resolve()
    else:
      out_path = (root / "CONFIG" / f"strategy.free_window_training.{season}.json").resolve()
    _dump_json(out_path, payload)
    print(str(out_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
