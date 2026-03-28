from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from websocket import WebSocketBadStatusException, create_connection


@dataclass
class Config:
    chat_url: str
    chrome_exe: str
    chrome_profile_dir: str
    remote_debugging_host: str
    remote_debugging_port: int
    desktop_agent_dir: str
    mailbox_dir: str
    codex_workspace_root: str
    poll_interval_seconds: int
    response_stable_rounds: int
    response_poll_seconds: int
    response_timeout_seconds: int
    launch_managed_chrome: bool
    create_new_tab_if_missing: bool
    save_html_snapshot: bool


def load_config(path: Path) -> Config:
    raw = json.loads(path.read_text(encoding="utf-8"))
    return Config(**raw)


def ensure_mailbox(cfg: Config) -> dict[str, Path]:
    root = Path(cfg.mailbox_dir)
    paths = {
        "root": root,
        "requests_pending": root / "requests" / "pending",
        "requests_in_progress": root / "requests" / "in_progress",
        "requests_done": root / "requests" / "done",
        "requests_failed": root / "requests" / "failed",
        "ack_root": root / "ack",
        "ack_executor": root / "ack" / "executor",
        "ack_reviewer": root / "ack" / "reviewer",
        "responses_ready": root / "responses" / "ready",
        "responses_archive": root / "responses" / "archive",
        "responses_consumed": root / "responses" / "consumed",
        "responses_extracted": root / "responses" / "extracted",
        "status": root / "status",
        "logs": root / "logs",
    }
    for path in paths.values():
        path.mkdir(parents=True, exist_ok=True)
    return paths


def write_status(status_dir: Path, name: str, payload: dict[str, Any]) -> None:
    payload = dict(payload)
    payload["written_at_local"] = time.strftime("%Y-%m-%d %H:%M:%S")
    (status_dir / f"{name}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def append_log(log_path: Path, message: str) -> None:
    stamp = time.strftime("%Y-%m-%d %H:%M:%S")
    with log_path.open("a", encoding="utf-8") as handle:
        handle.write(f"[{stamp}] {message}\n")


def devtools_url(cfg: Config, suffix: str) -> str:
    return f"http://{cfg.remote_debugging_host}:{cfg.remote_debugging_port}{suffix}"


def resolved_chat_url(cfg: Config) -> str:
    return os.environ.get("ORCH_CHAT_URL", cfg.chat_url)


def resolved_chrome_profile_dir(cfg: Config) -> str:
    return os.environ.get("ORCH_CHROME_PROFILE_DIR", cfg.chrome_profile_dir)


def resolve_chrome_exe(cfg: Config) -> str:
    candidates = [
        os.environ.get("ORCH_CHROME_EXE", "").strip(),
        cfg.chrome_exe,
        os.path.join(os.environ.get("ProgramFiles", ""), "Google", "Chrome", "Application", "chrome.exe"),
        os.path.join(os.environ.get("ProgramFiles(x86)", ""), "Google", "Chrome", "Application", "chrome.exe"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).exists():
            return candidate
    raise FileNotFoundError("Chrome executable not found in config, env, Program Files or Program Files (x86).")


def chrome_launch_args(cfg: Config, chrome_exe: str) -> list[str]:
    remote_host = cfg.remote_debugging_host
    remote_port = cfg.remote_debugging_port
    profile_dir = resolved_chrome_profile_dir(cfg)
    chat_url = resolved_chat_url(cfg)
    return [
        chrome_exe,
        f"--remote-debugging-port={remote_port}",
        f"--remote-debugging-address={remote_host}",
        f"--remote-allow-origins=http://127.0.0.1:{remote_port},http://localhost:{remote_port}",
        f"--user-data-dir={profile_dir}",
        "--no-first-run",
        "--disable-session-crashed-bubble",
        "--new-window",
        chat_url,
    ]


def build_operator_hint(error_text: str) -> str:
    lowered = error_text.lower()
    if "403" in lowered or "forbidden" in lowered:
        return (
            "Chrome DevTools odrzucil WebSocket. Sprawdz flagi "
            "--remote-allow-origins oraz czy uruchomiono dedykowany profil z launcherem."
        )
    if "composer_not_found_or_not_logged_in" in lowered:
        return "ChatGPT nie widzi pola wpisu. Zaloguj sie recznie w dedykowanym profilu Chrome."
    if "response_timeout" in lowered:
        return "ChatGPT nie oddal stabilnej odpowiedzi w limicie czasu. Sprobuj ponownie lub skróc prompt."
    return "Sprawdz status Orchestratora, log operatorski i czy Chrome DevTools odpowiada na porcie debugowym."


def sanitize_error_text(text: str) -> str:
    return text.replace("\r", " ").replace("\n", " ").strip()


def create_devtools_page(websocket_url: str, timeout_seconds: int = 30, retries: int = 3) -> tuple["DevToolsPage", dict[str, Any]]:
    last_error: Exception | None = None
    attempts: list[dict[str, Any]] = []
    for attempt in range(1, retries + 1):
        try:
            page = DevToolsPage(websocket_url, timeout_seconds=timeout_seconds)
            return page, {"attempts": attempts}
        except WebSocketBadStatusException as exc:
            last_error = exc
            attempts.append(
                {
                    "attempt": attempt,
                    "error_type": type(exc).__name__,
                    "error": sanitize_error_text(str(exc)),
                }
            )
            if exc.status_code == 403:
                raise RuntimeError(
                    "Chrome DevTools WebSocket handshake 403 Forbidden. "
                    "Uzyj launchera z flagami --remote-allow-origins=http://127.0.0.1:9222,http://localhost:9222 "
                    "albo otworz dedykowany profil orchestratora."
                ) from exc
        except Exception as exc:
            last_error = exc
            attempts.append(
                {
                    "attempt": attempt,
                    "error_type": type(exc).__name__,
                    "error": sanitize_error_text(str(exc)),
                }
            )
        time.sleep(min(2 * attempt, 5))
    assert last_error is not None
    raise RuntimeError(
        f"Nie udalo sie nawiazac polaczenia WebSocket z Chrome DevTools po {retries} probach: "
        f"{sanitize_error_text(str(last_error))}"
    ) from last_error


def devtools_get(cfg: Config, suffix: str) -> Any:
    with urllib.request.urlopen(devtools_url(cfg, suffix), timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def wait_for_devtools(cfg: Config, timeout: int = 30) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            devtools_get(cfg, "/json/version")
            return True
        except Exception:
            time.sleep(1)
    return False


def launch_chrome(cfg: Config) -> None:
    if not cfg.launch_managed_chrome:
        return
    chrome = Path(resolve_chrome_exe(cfg))
    profile_dir = Path(resolved_chrome_profile_dir(cfg))
    profile_dir.mkdir(parents=True, exist_ok=True)
    if wait_for_devtools(cfg, timeout=2):
        return
    args = chrome_launch_args(cfg, str(chrome))
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not wait_for_devtools(cfg, timeout=30):
        raise RuntimeError("Chrome DevTools did not start in time.")


def get_or_create_chat_tab(cfg: Config) -> dict[str, Any]:
    tabs = devtools_get(cfg, "/json/list")
    for tab in tabs:
        if tab.get("type") == "page" and str(tab.get("url", "")).startswith(cfg.chat_url):
            return tab
    if not cfg.create_new_tab_if_missing:
        raise RuntimeError("ChatGPT tab not found and auto-create is disabled.")
    encoded = urllib.parse.quote(cfg.chat_url, safe="")
    return devtools_get(cfg, f"/json/new?{encoded}")


class DevToolsPage:
    def __init__(self, websocket_url: str, timeout_seconds: int = 30):
        self.websocket_url = websocket_url
        kwargs: dict[str, Any] = {"timeout": timeout_seconds}
        try:
            self.ws = create_connection(websocket_url, suppress_origin=True, **kwargs)
        except TypeError:
            self.ws = create_connection(websocket_url, **kwargs)
        self.msg_id = 0

    def call(self, method: str, params: dict[str, Any] | None = None) -> Any:
        self.msg_id += 1
        payload = {"id": self.msg_id, "method": method, "params": params or {}}
        self.ws.send(json.dumps(payload))
        while True:
            raw = self.ws.recv()
            message = json.loads(raw)
            if message.get("id") == self.msg_id:
                if "error" in message:
                    raise RuntimeError(f"{method} failed: {message['error']}")
                return message.get("result", {})

    def evaluate(self, expression: str, await_promise: bool = True) -> Any:
        result = self.call(
            "Runtime.evaluate",
            {
                "expression": expression,
                "awaitPromise": await_promise,
                "returnByValue": True,
            },
        )
        return result.get("result", {}).get("value")

    def bring_to_front(self) -> None:
        self.call("Page.bringToFront")

    def close(self) -> None:
        try:
            self.ws.close()
        except Exception:
            pass


def js_string(value: str) -> str:
    return json.dumps(value)


JS_STATUS = r"""
(() => {
  const pick = (...selectors) => {
    for (const selector of selectors) {
      const node = document.querySelector(selector);
      if (node) return node;
    }
    return null;
  };
  const assistantNodes = Array.from(document.querySelectorAll(
    '[data-message-author-role="assistant"], article [data-message-author-role="assistant"], main article'
  ));
  const assistantTexts = assistantNodes
    .map(node => (node.innerText || '').trim())
    .filter(Boolean);
  const composer = pick(
    '#prompt-textarea',
    'textarea',
    'div[contenteditable="true"][data-testid]',
    'div.ProseMirror[contenteditable="true"]',
    'div[contenteditable="true"]'
  );
  const sendButton = pick(
    'button[data-testid="send-button"]',
    'button[aria-label*="Send"]',
    'button[aria-label*="Wyślij"]'
  );
  const stopButton = pick(
    'button[data-testid="stop-button"]',
    'button[aria-label*="Stop"]'
  );
  return {
    title: document.title,
    url: location.href,
    assistant_count: assistantTexts.length,
    last_assistant: assistantTexts.length ? assistantTexts[assistantTexts.length - 1] : '',
    composer_present: !!composer,
    send_present: !!sendButton,
    stop_present: !!stopButton
  };
})()
"""


def build_send_js(prompt_text: str) -> str:
    return f"""
((async () => {{
  const text = {js_string(prompt_text)};
  const pick = (...selectors) => {{
    for (const selector of selectors) {{
      const node = document.querySelector(selector);
      if (node) return node;
    }}
    return null;
  }};
  const composer = pick(
    '#prompt-textarea',
    'textarea',
    'div[contenteditable="true"][data-testid]',
    'div.ProseMirror[contenteditable="true"]',
    'div[contenteditable="true"]'
  );
  if (!composer) {{
    return {{ ok: false, error: 'composer_not_found_or_not_logged_in' }};
  }}
  const form = composer.closest('form');
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  const findSendButton = () => {{
    const scopedPick = (root, selectors) => {{
      if (!root) return null;
      for (const selector of selectors) {{
        const node = root.querySelector(selector);
        if (node) return node;
      }}
      return null;
    }};
    const selectors = [
      '#composer-submit-button',
      'button[data-testid="send-button"]',
      'button[aria-label*="Send"]',
      'button[aria-label*="Wyślij"]',
      'button[aria-label*="Wyślij polecenie"]',
      'button[type="submit"]'
    ];
    return scopedPick(form, selectors) || pick(...selectors);
  }};
  composer.focus();
  if (composer.tagName && composer.tagName.toLowerCase() === 'textarea') {{
    const setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
    setter.call(composer, text);
    composer.dispatchEvent(new Event('input', {{ bubbles: true }}));
  }} else {{
    composer.textContent = '';
    composer.dispatchEvent(new Event('input', {{ bubbles: true }}));
    composer.textContent = text;
    composer.dispatchEvent(new InputEvent('input', {{
      bubbles: true,
      data: text,
      inputType: 'insertText'
    }}));
  }}
  await wait(200);
  let sendButton = findSendButton();
  if (sendButton && sendButton.disabled) {{
    await wait(300);
    sendButton = findSendButton();
  }}
  if (sendButton && !sendButton.disabled) {{
    sendButton.click();
    return {{ ok: true, method: 'send_button_click' }};
  }}
  composer.dispatchEvent(new KeyboardEvent('keydown', {{ key: 'Enter', code: 'Enter', bubbles: true }}));
  composer.dispatchEvent(new KeyboardEvent('keypress', {{ key: 'Enter', code: 'Enter', bubbles: true }}));
  composer.dispatchEvent(new KeyboardEvent('keyup', {{ key: 'Enter', code: 'Enter', bubbles: true }}));
  await wait(150);
  return {{ ok: true, method: 'keyboard_enter_fallback' }};
}})())
"""


def build_html_js() -> str:
    return r"""
(() => {
  const assistantNodes = Array.from(document.querySelectorAll(
    '[data-message-author-role="assistant"], article [data-message-author-role="assistant"], main article'
  ));
  const node = assistantNodes.length ? assistantNodes[assistantNodes.length - 1] : null;
  return node ? node.outerHTML : '';
})()
"""


def wait_for_response(page: DevToolsPage, cfg: Config, initial_assistant_count: int) -> dict[str, Any]:
    deadline = time.time() + cfg.response_timeout_seconds
    last_text = ""
    stable_rounds = 0
    while time.time() < deadline:
        status = page.evaluate(JS_STATUS)
        assistant_count = int(status.get("assistant_count", 0))
        current_text = str(status.get("last_assistant", "")).strip()
        stop_present = bool(status.get("stop_present"))
        if assistant_count > initial_assistant_count and current_text:
            if current_text == last_text and not stop_present:
                stable_rounds += 1
            else:
                stable_rounds = 0
                last_text = current_text
            if stable_rounds >= cfg.response_stable_rounds:
                return {
                    "ok": True,
                    "assistant_count": assistant_count,
                    "text": current_text,
                    "html": page.evaluate(build_html_js()) if cfg.save_html_snapshot else "",
                    "status": status,
                }
        time.sleep(cfg.response_poll_seconds)
    return {
        "ok": False,
        "error": "response_timeout",
        "status": page.evaluate(JS_STATUS),
    }


FILE_BLOCK_RE = re.compile(
    r"(?ms)^FILE:\s*(?P<path>[^\r\n]+)\r?\n```[^\n]*\n(?P<content>.*?)\n```"
)


def extract_file_blocks(text: str, target_root: Path) -> list[dict[str, Any]]:
    extracted: list[dict[str, Any]] = []
    for match in FILE_BLOCK_RE.finditer(text):
        relative = match.group("path").strip().replace("/", os.sep)
        content = match.group("content")
        safe_relative = Path(relative)
        full_path = (target_root / safe_relative).resolve()
        if target_root.resolve() not in full_path.parents and full_path != target_root.resolve():
            continue
        full_path.parent.mkdir(parents=True, exist_ok=True)
        full_path.write_text(content, encoding="utf-8")
        extracted.append({"path": str(full_path), "relative_path": str(safe_relative)})
    return extracted


def next_request(requests_pending: Path) -> Path | None:
    files = sorted(requests_pending.glob("*.md"))
    return files[0] if files else None


def sidecar_path(path: Path) -> Path:
    return path.with_suffix(".json")


def move_with_sidecar(source: Path, destination: Path) -> None:
    shutil.move(str(source), str(destination))
    source_sidecar = sidecar_path(source)
    destination_sidecar = sidecar_path(destination)
    if source_sidecar.exists():
        shutil.move(str(source_sidecar), str(destination_sidecar))


def process_request(cfg: Config, paths: dict[str, Path], request_path: Path, log_path: Path) -> None:
    request_id = request_path.stem
    in_progress = paths["requests_in_progress"] / request_path.name
    move_with_sidecar(request_path, in_progress)
    request_meta: dict[str, Any] = {}
    in_progress_sidecar = sidecar_path(in_progress)
    if in_progress_sidecar.exists():
        request_meta = json.loads(in_progress_sidecar.read_text(encoding="utf-8"))
    write_status(
        paths["status"],
        "codex_last_request",
        {"request_id": request_id, "path": str(in_progress), "request_meta": request_meta},
    )

    append_log(log_path, f"processing request {request_id}")
    launch_chrome(cfg)
    tab = get_or_create_chat_tab(cfg)
    websocket_url = str(tab["webSocketDebuggerUrl"])
    page: DevToolsPage | None = None
    try:
        page, ws_meta = create_devtools_page(
            websocket_url, timeout_seconds=max(cfg.response_poll_seconds * 2, 30), retries=3
        )
        write_status(
            paths["status"],
            "orchestrator_transport",
            {
                "request_id": request_id,
                "chat_url": resolved_chat_url(cfg),
                "chrome_profile_dir": resolved_chrome_profile_dir(cfg),
                "websocket_url": websocket_url,
                "attempts": ws_meta.get("attempts", []),
            },
        )
        page.bring_to_front()
        before = page.evaluate(JS_STATUS)
        initial_assistant_count = int(before.get("assistant_count", 0))
        prompt_text = in_progress.read_text(encoding="utf-8")
        send_result = page.evaluate(build_send_js(prompt_text))
        if not send_result.get("ok"):
            raise RuntimeError(send_result.get("error", "unknown_send_error"))
        response = wait_for_response(page, cfg, initial_assistant_count)
        if not response.get("ok"):
            raise RuntimeError(response.get("error", "response_error"))

        response_md = paths["responses_ready"] / f"{request_id}_response.md"
        response_json = paths["responses_ready"] / f"{request_id}_response.json"
        extracted_root = paths["responses_extracted"] / request_id
        extracted = extract_file_blocks(str(response["text"]), extracted_root)

        response_md.write_text(str(response["text"]), encoding="utf-8")
        response_payload = {
            "request_id": request_id,
            "request_path": str(in_progress),
            "request_meta": request_meta,
            "response_path": str(response_md),
            "extracted_root": str(extracted_root),
            "extracted_files": extracted,
            "status": response.get("status", {}),
            "html_snapshot_saved": cfg.save_html_snapshot,
        }
        if cfg.save_html_snapshot and response.get("html"):
            html_path = paths["responses_ready"] / f"{request_id}_response.html"
            html_path.write_text(str(response["html"]), encoding="utf-8")
            response_payload["html_path"] = str(html_path)
        response_json.write_text(json.dumps(response_payload, ensure_ascii=False, indent=2), encoding="utf-8")

        done_path = paths["requests_done"] / request_path.name
        move_with_sidecar(in_progress, done_path)
        write_status(
            paths["status"],
            "gpt_last_response",
            {"request_id": request_id, "response_path": str(response_md), "request_meta": request_meta},
        )
        append_log(log_path, f"request {request_id} completed")
    except Exception as exc:
        failed_path = paths["requests_failed"] / request_path.name
        if in_progress.exists():
            move_with_sidecar(in_progress, failed_path)
        error_text = sanitize_error_text(str(exc))
        write_status(
            paths["status"],
            "orchestrator_error",
            {
                "request_id": request_id,
                "error": error_text,
                "chat_url": resolved_chat_url(cfg),
                "chrome_profile_dir": resolved_chrome_profile_dir(cfg),
                "websocket_url": websocket_url,
                "operator_hint": build_operator_hint(error_text),
                "request_path": str(failed_path),
                "request_meta": request_meta,
            },
        )
        append_log(log_path, f"request {request_id} failed: {error_text}")
    finally:
        if page is not None:
            page.close()


def command_open_chat(cfg: Config) -> int:
    ensure_mailbox(cfg)
    launch_chrome(cfg)
    print("Chrome ready with remote debugging.")
    print(f"Chat URL: {cfg.chat_url}")
    return 0


def command_status(cfg: Config) -> int:
    paths = ensure_mailbox(cfg)
    devtools_ok = wait_for_devtools(cfg, timeout=2)
    pending = len(list(paths["requests_pending"].glob("*.md")))
    in_progress = len(list(paths["requests_in_progress"].glob("*.md")))
    ready = len(list(paths["responses_ready"].glob("*.md")))
    failed = len(list(paths["requests_failed"].glob("*.md")))
    consumed = len(list(paths["responses_consumed"].glob("*")))

    def load_status_file(name: str) -> dict[str, Any]:
        path = paths["status"] / f"{name}.json"
        if not path.exists():
            return {}
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return {}

    last_request = load_status_file("codex_last_request")
    last_response = load_status_file("gpt_last_response")
    last_error = load_status_file("orchestrator_error")
    payload = {
        "devtools_ok": devtools_ok,
        "pending_requests": pending,
        "in_progress_requests": in_progress,
        "ready_responses": ready,
        "failed_requests": failed,
        "consumed_responses": consumed,
        "last_request_file": last_request.get("path", ""),
        "last_response_file": last_response.get("response_path", ""),
        "chrome_debug_port": cfg.remote_debugging_port,
        "chat_url": resolved_chat_url(cfg),
        "last_error_summary": last_error.get("error", ""),
        "mailbox_dir": str(paths["root"]),
    }
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


def command_run(cfg: Config) -> int:
    paths = ensure_mailbox(cfg)
    log_path = paths["logs"] / f"orchestrator_{time.strftime('%Y%m%d')}.log"
    append_log(log_path, "orchestrator started")
    launch_chrome(cfg)
    while True:
        request = next_request(paths["requests_pending"])
        if request is not None:
            process_request(cfg, paths, request, log_path)
        else:
            write_status(
                paths["status"],
                "orchestrator_heartbeat",
                {
                    "devtools_ok": wait_for_devtools(cfg, timeout=1),
                    "pending_requests": len(list(paths["requests_pending"].glob("*.md"))),
                },
            )
            time.sleep(cfg.poll_interval_seconds)


def command_process_once(cfg: Config) -> int:
    paths = ensure_mailbox(cfg)
    log_path = paths["logs"] / f"orchestrator_{time.strftime('%Y%m%d')}.log"
    append_log(log_path, "orchestrator process-once started")
    launch_chrome(cfg)
    request = next_request(paths["requests_pending"])
    if request is None:
        write_status(
            paths["status"],
            "orchestrator_heartbeat",
            {
                "devtools_ok": wait_for_devtools(cfg, timeout=1),
                "pending_requests": 0,
                "mode": "process-once",
            },
        )
        print("No pending requests.")
        return 0
    process_request(cfg, paths, request, log_path)
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["open-chat", "run", "status", "process-once"])
    parser.add_argument("--config", default="C:\\MAKRO_I_MIKRO_BOT\\TOOLS\\orchestrator\\orchestrator_config.json")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    cfg = load_config(Path(args.config))
    if args.mode == "open-chat":
        return command_open_chat(cfg)
    if args.mode == "status":
        return command_status(cfg)
    if args.mode == "process-once":
        return command_process_once(cfg)
    return command_run(cfg)


if __name__ == "__main__":
    raise SystemExit(main())
