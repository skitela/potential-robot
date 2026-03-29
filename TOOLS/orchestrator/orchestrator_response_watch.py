from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any


def load_config(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def ensure_dirs(mailbox_dir: Path) -> dict[str, Path]:
    paths = {
        "root": mailbox_dir,
        "responses_ready": mailbox_dir / "responses" / "ready",
        "status": mailbox_dir / "status",
        "logs": mailbox_dir / "logs",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def append_log(log_path: Path, message: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{stamp}] {message}\n")


def write_status(status_dir: Path, name: str, payload: dict[str, Any]) -> None:
    payload = dict(payload)
    payload["written_at_local"] = time.strftime("%Y-%m-%d %H:%M:%S")
    (status_dir / f"{name}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def newest_ready_response(responses_ready: Path) -> Path | None:
    candidates = sorted(
        responses_ready.glob("*_response.json"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def load_state(status_dir: Path) -> dict[str, Any]:
    path = status_dir / "response_watch_state.json"
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def read_markdown_excerpt(path: Path, limit: int = 1200) -> str:
    try:
        return path.read_text(encoding="utf-8")[:limit]
    except Exception:
        return ""


def process_once(paths: dict[str, Path], log_path: Path) -> bool:
    latest = newest_ready_response(paths["responses_ready"])
    state = load_state(paths["status"])
    last_seen = str(state.get("last_seen_response_json", ""))
    if latest is None:
        write_status(
            paths["status"],
            "gpt_inbox_latest",
            {"has_response": False, "mailbox_dir": str(paths["root"])},
        )
        return False
    if str(latest) == last_seen:
        payload = state.get("last_inbox_payload", {})
        if payload:
            write_status(paths["status"], "gpt_inbox_latest", payload)
        return False

    payload = json.loads(latest.read_text(encoding="utf-8"))
    response_path = Path(str(payload.get("response_path", "")))
    request_meta = payload.get("request_meta", {}) or {}
    inbox_payload = {
        "has_response": True,
        "request_id": payload.get("request_id", ""),
        "title": request_meta.get("title", ""),
        "source_path": request_meta.get("source_path", ""),
        "response_json": str(latest),
        "response_markdown": str(response_path),
        "extracted_root": payload.get("extracted_root", ""),
        "extracted_files_count": len(payload.get("extracted_files", []) or []),
        "published_notes_count": len(payload.get("published_notes", []) or []),
        "html_snapshot_saved": bool(payload.get("html_snapshot_saved", False)),
        "assistant_excerpt": read_markdown_excerpt(response_path),
    }
    write_status(paths["status"], "gpt_inbox_latest", inbox_payload)
    write_status(
        paths["status"],
        "response_watch_state",
        {
            "last_seen_response_json": str(latest),
            "last_inbox_payload": inbox_payload,
        },
    )
    append_log(log_path, f"new GPT response detected: {payload.get('request_id', '')}")
    return True


def command_status(paths: dict[str, Path]) -> int:
    latest = newest_ready_response(paths["responses_ready"])
    state = load_state(paths["status"])
    payload = {
        "ready_response_json": str(latest) if latest else "",
        "last_seen_response_json": state.get("last_seen_response_json", ""),
        "mailbox_dir": str(paths["root"]),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def command_process_once(paths: dict[str, Path]) -> int:
    log_path = paths["logs"] / f"response_watch_{time.strftime('%Y%m%d')}.log"
    append_log(log_path, "response watch process-once started")
    process_once(paths, log_path)
    return 0


def command_run(paths: dict[str, Path], poll_interval_seconds: int) -> int:
    log_path = paths["logs"] / f"response_watch_{time.strftime('%Y%m%d')}.log"
    append_log(log_path, "response watch started")
    while True:
        process_once(paths, log_path)
        time.sleep(poll_interval_seconds)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["run", "status", "process-once"])
    parser.add_argument("--config", default="C:\\MAKRO_I_MIKRO_BOT\\TOOLS\\orchestrator\\orchestrator_config.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(Path(args.config))
    paths = ensure_dirs(Path(config["mailbox_dir"]))
    poll_interval_seconds = int(config.get("poll_interval_seconds", 5))
    if args.mode == "status":
        return command_status(paths)
    if args.mode == "process-once":
        return command_process_once(paths)
    return command_run(paths, poll_interval_seconds)


if __name__ == "__main__":
    raise SystemExit(main())
