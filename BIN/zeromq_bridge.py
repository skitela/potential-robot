# -*- coding: utf-8 -*-
"""
zeromq_bridge.py - Warstwa komunikacyjna (most) dla systemu hybrydowego Python <-> MQL5.

Ten moduł jest odpowiedzialny za ustanowienie dwukierunkowej komunikacji
pomiędzy procesem Pythona (mózgiem) a agentem działającym w MQL5 (częścią wykonawczą).

Architektura:
- Używa biblioteki ZeroMQ (pyzmq), która jest wysokowydajnym standardem.
- Komunikacja odbywa się na dwóch dedykowanych gniazdach (sockets):
  1. PULL Socket (Port 5555): Python nasłuchuje na tym porcie, aby odbierać dane
     (ceny, wartości wskaźników) wysyłane z MQL5.
  2. REQ Socket (Port 5556): Python wysyła komendy i czeka na odpowiedź REP z MQL5.
- Ten wzorzec (PULL + REQ/REP) rozdziela strumień danych i strumień egzekucji
  oraz zapewnia potwierdzoną, synchroniczną komunikację komend.
- Wszystkie wiadomości są serializowane do formatu JSON.
"""

from __future__ import annotations

import json
import logging
import uuid
import threading
import time
import queue
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

import zmq

PROTOCOL_VERSION = "1.0"


def _utc_now_iso_z() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _fnv1a32_hex(text: str) -> str:
    data = str(text or "").encode("utf-8", errors="ignore")
    h = 0x811C9DC5
    for b in data:
        h ^= int(b)
        h = (h * 0x01000193) & 0xFFFFFFFF
    return f"{h:08X}"


def _norm_float(value: Any) -> str:
    try:
        return f"{float(value):.8f}"
    except Exception:
        return "0.00000000"


def _norm_int(value: Any) -> str:
    try:
        return str(int(value))
    except Exception:
        return "0"


def build_request_hash(command: Dict[str, Any]) -> str:
    action = str(command.get("action") or "").strip().upper()
    msg_id = str(command.get("msg_id") or "").strip()
    payload = command.get("payload") if isinstance(command.get("payload"), dict) else {}
    if action == "TRADE":
        deviation_pts = payload.get("deviation_points")
        if deviation_pts is None:
            deviation_pts = payload.get("deviation")
        sig = "|".join(
            [
                action,
                msg_id,
                str(payload.get("signal") or "").strip().upper(),
                str(payload.get("symbol") or "").strip().upper(),
                _norm_float(payload.get("volume")),
                _norm_float(payload.get("sl_price")),
                _norm_float(payload.get("tp_price")),
                _norm_int(payload.get("magic")),
                str(payload.get("comment") or ""),
                _norm_int(deviation_pts),
            ]
        )
    else:
        sig = "|".join([action, msg_id])
    return _fnv1a32_hex(sig)


def build_response_hash(reply: Dict[str, Any]) -> str:
    status = str(reply.get("status") or "").strip().upper()
    correlation_id = str(reply.get("correlation_id") or "").strip()
    action = str(reply.get("action") or "").strip().upper()
    details = reply.get("details") if isinstance(reply.get("details"), dict) else {}
    sig = "|".join(
        [
            status,
            correlation_id,
            action,
            _norm_int(details.get("retcode")),
            str(details.get("retcode_str") or ""),
            _norm_int(details.get("order")),
            _norm_int(details.get("deal")),
            str(details.get("comment") or ""),
            str(details.get("symbol") or ""),
            str(reply.get("error") or ""),
            str(reply.get("request_hash") or ""),
        ]
    )
    return _fnv1a32_hex(sig)


class ZMQBridge:
    """
    Zarządza połączeniem ZeroMQ do komunikacji z agentem MQL5.
    Używa PULL do odbierania danych i REQ/REP do niezawodnego wysyłania komend.
    Loguje wszystkie transakcje do pliku audytu.
    """

    def __init__(
        self,
        pull_port: int = 5555,
        req_port: int = 5556,
        req_timeout_ms: int = 5000,
        req_retries: int = 3,
        audit_log_path: Optional[str] = "LOGS/audit_trail.jsonl",
        heartbeat_trade_priority_window_ms: int = 300,
        audit_async: bool = True,
        audit_queue_maxsize: int = 8192,
        audit_queue_put_timeout_ms: int = 2,
        audit_batch_size: int = 64,
        audit_flush_interval_ms: int = 200,
    ):
        """
        Inicjalizuje kontekst ZMQ i definiuje porty.

        :param pull_port: Port do odbierania danych z MQL5 (MQL5 będzie tu wysyłał PUSH).
        :param req_port: Port do wysyłania komend do MQL5 i odbierania odpowiedzi (REQ/REP).
        :param req_timeout_ms: Czas oczekiwania na odpowiedź od MQL5 w milisekundach.
        :param req_retries: Liczba prób ponowienia wysłania komendy w przypadku braku odpowiedzi.
        :param audit_log_path: Ścieżka do pliku dziennika audytu. Jeśli None, logowanie jest wyłączone.
        """
        self.pull_port = pull_port
        self.req_port = req_port
        self.req_timeout_ms = req_timeout_ms
        self.req_retries = req_retries
        self.audit_log_path = audit_log_path
        
        self.context = zmq.Context()
        self.pull_socket: Optional[zmq.Socket] = None
        self.req_socket: Optional[zmq.Socket] = None
        self._audit_log_lock = threading.Lock()
        self._command_lock = threading.Lock()
        self._diag_lock = threading.Lock()
        self._audit_log_file: Optional[Path] = Path(self.audit_log_path) if self.audit_log_path else None
        self._last_command_diag: Dict[str, Any] = {}
        self._audit_async_enabled = bool(audit_async and self._audit_log_file is not None)
        self._audit_queue_maxsize = int(max(128, int(audit_queue_maxsize or 8192)))
        self._audit_queue_put_timeout_s = max(0.0, float(audit_queue_put_timeout_ms or 0) / 1000.0)
        self._audit_batch_size = int(max(1, int(audit_batch_size or 64)))
        self._audit_flush_interval_s = max(0.01, float(audit_flush_interval_ms or 200) / 1000.0)
        self._audit_queue: Optional[queue.Queue[str]] = (
            queue.Queue(maxsize=self._audit_queue_maxsize) if self._audit_async_enabled else None
        )
        self._audit_stop = threading.Event()
        self._audit_thread: Optional[threading.Thread] = None
        self._audit_queue_full_count = 0
        self._heartbeat_trade_priority_window_ms = int(
            max(0, int(heartbeat_trade_priority_window_ms or 0))
        )
        self._trade_priority_lock = threading.Lock()
        self._trade_waiting_count = 0
        self._trade_inflight_count = 0
        self._last_trade_activity_monotonic = 0.0

        logging.info(
            f"ZMQBridge zainicjalizowany. Odbiór danych na porcie {pull_port}, komunikacja REQ/REP na porcie {req_port}."
        )
        if self.audit_log_path:
            logging.info(f"Dziennik audytu będzie zapisywany w: {self.audit_log_path}")
        if self._audit_async_enabled:
            self._start_audit_worker()
            logging.info(
                "AUDIT_LOG_MODE=ASYNC queue_maxsize=%s batch_size=%s flush_interval_ms=%s",
                int(self._audit_queue_maxsize),
                int(self._audit_batch_size),
                int(max(10, int(self._audit_flush_interval_s * 1000.0))),
            )
        elif self.audit_log_path:
            logging.info("AUDIT_LOG_MODE=SYNC")

    def _set_last_command_diag(self, diag: Dict[str, Any]) -> None:
        with self._diag_lock:
            self._last_command_diag = dict(diag or {})

    def get_last_command_diag(self) -> Dict[str, Any]:
        with self._diag_lock:
            return dict(self._last_command_diag)

    def _trade_mark_waiting(self, delta: int) -> None:
        now_mono = float(time.perf_counter())
        with self._trade_priority_lock:
            self._trade_waiting_count = int(max(0, int(self._trade_waiting_count) + int(delta)))
            self._last_trade_activity_monotonic = now_mono

    def _trade_mark_inflight_start(self) -> None:
        now_mono = float(time.perf_counter())
        with self._trade_priority_lock:
            self._trade_inflight_count = int(max(0, int(self._trade_inflight_count) + 1))
            self._last_trade_activity_monotonic = now_mono

    def _trade_mark_done(self) -> None:
        now_mono = float(time.perf_counter())
        with self._trade_priority_lock:
            self._trade_inflight_count = int(max(0, int(self._trade_inflight_count) - 1))
            self._last_trade_activity_monotonic = now_mono

    def _is_trade_priority_active(self, window_ms: int) -> bool:
        eff_window_ms = int(max(0, int(window_ms)))
        now_mono = float(time.perf_counter())
        with self._trade_priority_lock:
            waiting = int(self._trade_waiting_count)
            inflight = int(self._trade_inflight_count)
            last_ts = float(self._last_trade_activity_monotonic or 0.0)
        if waiting > 0 or inflight > 0:
            return True
        if eff_window_ms <= 0 or last_ts <= 0.0:
            return False
        elapsed_ms = int(max(0.0, (now_mono - last_ts) * 1000.0))
        return bool(elapsed_ms <= eff_window_ms)

    @staticmethod
    def _command_type(action: Any) -> str:
        act = str(action or "").strip().upper()
        if act == "HEARTBEAT":
            return "HEARTBEAT"
        if act == "TRADE":
            return "TRADE"
        return "OTHER"

    @staticmethod
    def _timeout_budget_bucket(timeout_budget_ms: int) -> str:
        v = int(max(1, int(timeout_budget_ms or 1)))
        if v <= 300:
            return "LE_300MS"
        if v <= 600:
            return "301_600MS"
        if v <= 900:
            return "601_900MS"
        if v <= 1200:
            return "901_1200MS"
        return "GT_1200MS"

    def _write_audit_log(self, event_type: str, message_id: str, data: Dict[str, Any]) -> int:
        """Zapisuje zdarzenie do pliku dziennika audytu w sposób bezpieczny wątkowo."""
        if not self._audit_log_file:
            return 0
        event_type_norm = str(event_type or "").strip().upper()
        log_entry = {
            "timestamp_utc": _utc_now_iso_z(),
            "timestamp_semantics": "UTC",
            "event_type": event_type,
            "event_type_norm": event_type_norm,
            "source_provenance": "python.zmq_bridge",
            "message_id": message_id,
            "data": data
        }

        line = json.dumps(log_entry, separators=(",", ":")) + "\n"
        if self._audit_async_enabled:
            return self._enqueue_audit_line(line)

        return self._append_audit_lines_sync([line])

    def _append_audit_lines_sync(self, lines: list[str]) -> int:
        if not self._audit_log_file or not lines:
            return 0
        lock_wait_ms = 0
        try:
            lock_t0 = time.perf_counter()
            with self._audit_log_lock:
                lock_wait_ms = int((time.perf_counter() - lock_t0) * 1000.0)
                self._audit_log_file.parent.mkdir(parents=True, exist_ok=True)
                with open(self._audit_log_file, "a", encoding="utf-8") as f:
                    f.writelines(lines)
        except Exception as e:
            logging.error(f"Nie udało się zapisać do dziennika audytu: {e}")
        return int(lock_wait_ms)

    def _enqueue_audit_line(self, line: str) -> int:
        q = self._audit_queue
        if q is None:
            return self._append_audit_lines_sync([line])
        queue_wait_t0 = time.perf_counter()
        try:
            q.put(line, timeout=self._audit_queue_put_timeout_s)
            return int((time.perf_counter() - queue_wait_t0) * 1000.0)
        except queue.Full:
            self._audit_queue_full_count += 1
            if self._audit_queue_full_count <= 3 or (self._audit_queue_full_count % 100) == 0:
                logging.warning(
                    "AUDIT_QUEUE_FULL fallback=SYNC count=%s queue_maxsize=%s",
                    int(self._audit_queue_full_count),
                    int(self._audit_queue_maxsize),
                )
            # Fallback sync: no audit-data loss, only rare contention spike.
            sync_wait = self._append_audit_lines_sync([line])
            queue_wait = int((time.perf_counter() - queue_wait_t0) * 1000.0)
            return int(max(sync_wait, queue_wait))

    def _start_audit_worker(self) -> None:
        if not self._audit_async_enabled:
            return
        if self._audit_thread is not None:
            return
        self._audit_stop.clear()
        t = threading.Thread(target=self._audit_worker_loop, name="zmq-audit-writer", daemon=True)
        self._audit_thread = t
        t.start()

    def _audit_worker_loop(self) -> None:
        q = self._audit_queue
        if q is None:
            return
        while (not self._audit_stop.is_set()) or (not q.empty()):
            try:
                first = q.get(timeout=self._audit_flush_interval_s)
            except queue.Empty:
                continue
            batch: list[str] = [first]
            while len(batch) < self._audit_batch_size:
                try:
                    batch.append(q.get_nowait())
                except queue.Empty:
                    break
            self._append_audit_lines_sync(batch)
            for _ in batch:
                try:
                    q.task_done()
                except Exception:
                    break

    def _flush_audit_queue_sync(self) -> None:
        q = self._audit_queue
        if q is None:
            return
        batch: list[str] = []
        while True:
            try:
                batch.append(q.get_nowait())
            except queue.Empty:
                break
        if batch:
            self._append_audit_lines_sync(batch)
            for _ in batch:
                try:
                    q.task_done()
                except Exception:
                    break

    def setup_sockets(self) -> None:
        """
        Tworzy i wiąże gniazda ZMQ.
        Musi być wywołane przed próbą wysłania lub odbioru.
        """
        try:
            # Gniazdo do odbierania danych od MQL5 - bez zmian
            self.pull_socket = self.context.socket(zmq.PULL)
            self.pull_socket.bind(f"tcp://127.0.0.1:{self.pull_port}")
            logging.info(f"ZMQ PULL socket nasłuchuje na tcp://127.0.0.1:{self.pull_port}")

            # Gniazdo REQ do wysyłania komend i odbierania potwierdzeń
            self.req_socket = self.context.socket(zmq.REQ)
            self._configure_req_socket(self.req_socket)
            self.req_socket.bind(f"tcp://127.0.0.1:{self.req_port}")
            logging.info(f"ZMQ REQ socket gotowy do wysyłania na tcp://127.0.0.1:{self.req_port}")

        except zmq.ZMQError as e:
            logging.error(f"Nie udało się powiązać gniazd ZMQ: {e}")
            logging.error(f"Sprawdź, czy inny proces nie używa portów {self.pull_port}/{self.req_port}.")
            raise

    def _configure_req_socket(self, sock: zmq.Socket) -> None:
        """
        Konfiguracja REQ pod odporno?? na brak po??czenia z EA:
        - ograniczone timeouty send/recv (brak zawieszania),
        - IMMEDIATE=1 (nie blokuj wysy?ki bez peera),
        - LINGER=0 (szybkie zamykanie przy reconnect).
        """
        sock.setsockopt(zmq.LINGER, 0)
        sock.setsockopt(zmq.SNDTIMEO, int(max(1, self.req_timeout_ms)))
        sock.setsockopt(zmq.RCVTIMEO, int(max(1, self.req_timeout_ms)))
        sock.setsockopt(zmq.IMMEDIATE, 1)

    def receive_data(self, timeout: Optional[int] = None) -> Optional[Dict[str, Any]]:
        """
        Odbiera dane z Agenta MQL5 (kanał PULL). Może działać w trybie blokującym lub z timeoutem.
        """
        if not self.pull_socket:
            logging.error("Próba odbioru na niezainicjalizowanym gnieździe PULL.")
            return None

        try:
            if timeout is not None:
                if not self.pull_socket.poll(timeout):
                    return None

            message = self.pull_socket.recv_string(flags=zmq.NOBLOCK if timeout is not None else 0)
            return json.loads(message)
        except zmq.Again:
            return None
        except (json.JSONDecodeError, TypeError) as e:
            logging.warning(f"Błąd deserializacji wiadomości JSON z MQL5: {e}")
            return None
        except Exception as e:
            logging.error(f"Niespodziewany błąd podczas odbierania danych ZMQ: {e}")
            return None

    def send_command(
        self,
        command: Dict[str, Any],
        *,
        timeout_ms: Optional[int] = None,
        max_retries: Optional[int] = None,
        loop_id: Optional[str] = None,
        queue_lock_timeout_ms: Optional[int] = None,
        reconnect_on_timeout: bool = True,
    ) -> Optional[Dict[str, Any]]:
        """
        Wysyła komendę do Agenta MQL5 z mechanizmem ponowień i oczekiwaniem na odpowiedź.
        Loguje operacje do dziennika audytu.
        """
        if not self.req_socket:
            logging.error("Próba wysłania na niezainicjalizowanym gnieździe REQ.")
            return None

        if not isinstance(command, dict):
            logging.error("Nieprawidłowy typ komendy - oczekiwano obiektu JSON.")
            return None

        effective_timeout_ms = int(max(1, timeout_ms if timeout_ms is not None else self.req_timeout_ms))
        effective_retries = int(max(1, max_retries if max_retries is not None else self.req_retries))

        pre_action = str(command.get("action") or "").strip().upper()
        pre_command_type = self._command_type(pre_action)
        pre_timeout_bucket = self._timeout_budget_bucket(effective_timeout_ms)
        pre_msg_id = str(command.get("msg_id") or str(uuid.uuid4()))
        pre_loop_id = str(loop_id if loop_id is not None else (command.get("loop_id") or "none"))
        trade_priority_window_ms = int(max(0, self._heartbeat_trade_priority_window_ms))
        is_trade_command = bool(pre_command_type == "TRADE")
        endpoint = f"tcp://127.0.0.1:{self.req_port}"

        if is_trade_command:
            self._trade_mark_waiting(+1)
        elif pre_command_type == "HEARTBEAT":
            if self._is_trade_priority_active(trade_priority_window_ms):
                diag = {
                    "loop_id": pre_loop_id,
                    "command_id": pre_msg_id,
                    "action": pre_action,
                    "command_type": pre_command_type,
                    "timeout_budget_ms": int(effective_timeout_ms),
                    "timeout_budget_bucket": pre_timeout_bucket,
                    "max_retries": int(effective_retries),
                    "attempts": 0,
                    "bridge_send_ms": 0,
                    "bridge_wait_ms": 0,
                    "bridge_parse_ms": 0,
                    "bridge_total_ms": 0,
                    "bridge_timeout_reason": "QUEUE_LOCK_TIMEOUT",
                    "bridge_timeout_subreason": "TRADE_PRIORITY_WINDOW",
                    "status": "SKIPPED",
                    "fallback_used": True,
                    "channel": "REQ_REP",
                    "endpoint": endpoint,
                    "command_queue_wait_ms": 0,
                    "audit_log_lock_wait_max_ms": 0,
                    "heartbeat_trade_priority_window_ms": int(trade_priority_window_ms),
                }
                self._set_last_command_diag(diag)
                self._write_audit_log(
                    "COMMAND_SKIPPED",
                    pre_msg_id,
                    {
                        "phase": "trade_priority_window",
                        "action": pre_action,
                        "command_type": pre_command_type,
                        "bridge_timeout_reason": "QUEUE_LOCK_TIMEOUT",
                        "bridge_timeout_subreason": "TRADE_PRIORITY_WINDOW",
                        "timeout_budget_ms": int(effective_timeout_ms),
                        "timeout_budget_bucket": pre_timeout_bucket,
                        "heartbeat_trade_priority_window_ms": int(trade_priority_window_ms),
                    },
                )
                return None

        queue_wait_t0 = time.perf_counter()
        if queue_lock_timeout_ms is None:
            acquired = bool(self._command_lock.acquire())
        else:
            acquired = bool(
                self._command_lock.acquire(
                    timeout=max(0.0, float(max(0, int(queue_lock_timeout_ms))) / 1000.0)
                )
            )
        command_queue_wait_ms = int((time.perf_counter() - queue_wait_t0) * 1000.0)
        if not acquired:
            if is_trade_command:
                self._trade_mark_waiting(-1)
            diag = {
                "loop_id": pre_loop_id,
                "command_id": pre_msg_id,
                "action": pre_action,
                "command_type": pre_command_type,
                "timeout_budget_ms": int(effective_timeout_ms),
                "timeout_budget_bucket": pre_timeout_bucket,
                "max_retries": int(effective_retries),
                "attempts": 0,
                "bridge_send_ms": 0,
                "bridge_wait_ms": 0,
                "bridge_parse_ms": 0,
                "bridge_total_ms": 0,
                "bridge_timeout_reason": "QUEUE_LOCK_TIMEOUT",
                "bridge_timeout_subreason": "LOCK_BUSY",
                    "status": "SKIPPED",
                    "fallback_used": True,
                    "channel": "REQ_REP",
                    "endpoint": endpoint,
                    "command_queue_wait_ms": int(command_queue_wait_ms),
                    "audit_log_lock_wait_max_ms": 0,
                }
            self._set_last_command_diag(diag)
            self._write_audit_log(
                "COMMAND_SKIPPED",
                pre_msg_id,
                {
                    "phase": "queue_lock_timeout",
                    "action": pre_action,
                    "command_type": pre_command_type,
                    "queue_lock_timeout_ms": (
                        None if queue_lock_timeout_ms is None else int(max(0, int(queue_lock_timeout_ms)))
                    ),
                    "command_queue_wait_ms": int(command_queue_wait_ms),
                    "bridge_timeout_reason": "QUEUE_LOCK_TIMEOUT",
                    "bridge_timeout_subreason": "LOCK_BUSY",
                    "timeout_budget_ms": int(effective_timeout_ms),
                    "timeout_budget_bucket": pre_timeout_bucket,
                },
            )
            return None

        try:
            original_command = dict(command)
            original_command.setdefault("__v", PROTOCOL_VERSION)
            original_command.setdefault("schema_version", PROTOCOL_VERSION)
            if "msg_id" not in original_command:
                original_command["msg_id"] = str(uuid.uuid4())
            msg_id = str(original_command["msg_id"])
            original_command.setdefault("command_id", msg_id)
            original_command.setdefault("request_id", msg_id)
            original_command["request_hash"] = str(build_request_hash(original_command))
            original_command.setdefault("request_ts_utc", _utc_now_iso_z())
            original_command.setdefault("request_ts_semantics", "UTC")
            if loop_id is None:
                loop_id = original_command.get("loop_id")
            if loop_id is not None:
                original_command["loop_id"] = str(loop_id)

            action_norm = str(original_command.get("action") or "").strip().upper()
            command_type = self._command_type(action_norm)
            budget_bucket = self._timeout_budget_bucket(effective_timeout_ms)
            hb_loop_lag_ms = 0
            hb_market_data_stale_ms = -1
            trade_started = False
            if is_trade_command:
                self._trade_mark_waiting(-1)
                self._trade_mark_inflight_start()
                trade_started = True
            try:
                hb_loop_lag_ms = int(max(0, int(original_command.get("hb_loop_lag_ms", 0) or 0)))
            except Exception:
                hb_loop_lag_ms = 0
            try:
                hb_market_data_stale_ms = int(original_command.get("hb_market_data_stale_ms", -1) or -1)
            except Exception:
                hb_market_data_stale_ms = -1

            diag: Dict[str, Any] = {
                "loop_id": str(original_command.get("loop_id") or "none"),
                "command_id": msg_id,
                "action": action_norm,
                "command_type": command_type,
                "timeout_budget_ms": int(effective_timeout_ms),
                "timeout_budget_bucket": budget_bucket,
                "max_retries": int(effective_retries),
                "attempts": 0,
                "bridge_send_ms": 0,
                "bridge_wait_ms": 0,
                "bridge_parse_ms": 0,
                "bridge_total_ms": 0,
                "bridge_timeout_reason": "NONE",
                "bridge_timeout_subreason": "NONE",
                "status": "PENDING",
                "fallback_used": False,
                "channel": "REQ_REP",
                "endpoint": endpoint,
                "command_queue_wait_ms": int(command_queue_wait_ms),
                "audit_log_lock_wait_max_ms": 0,
            }

            self._set_last_command_diag(diag)
            cmd_start_t0 = time.perf_counter()
            last_reason = "UNKNOWN"
            last_subreason = "UNKNOWN"
            max_audit_lock_wait_ms = 0
            encoded_message = json.dumps(original_command, separators=(",", ":"))

            for attempt in range(effective_retries):
                send_ms = 0
                wait_ms = 0
                parse_ms = 0
                elapsed_ms = 0
                diag["attempts"] = int(attempt + 1)
                try:
                    lock_wait_ms = self._write_audit_log(
                        "COMMAND_SENT",
                        msg_id,
                        {
                            **original_command,
                            "phase": "command_send",
                            "channel": "REQ_REP",
                            "endpoint": endpoint,
                            "attempt": int(attempt + 1),
                            "retry_count": int(attempt),
                            "timeout_budget_ms": int(effective_timeout_ms),
                            "timeout_budget_bucket": budget_bucket,
                            "command_type": command_type,
                            "command_queue_wait_ms": int(command_queue_wait_ms),
                            "hb_loop_lag_ms": int(hb_loop_lag_ms),
                            "hb_market_data_stale_ms": int(hb_market_data_stale_ms),
                        },
                    )
                    max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))

                    send_t0 = time.perf_counter()
                    self.req_socket.send_string(encoded_message)
                    send_ms = int((time.perf_counter() - send_t0) * 1000.0)
                    wait_t0 = time.perf_counter()

                    if self.req_socket.poll(effective_timeout_ms):
                        wait_ms = int((time.perf_counter() - wait_t0) * 1000.0)
                        reply_message = self.req_socket.recv_string()
                        parse_t0 = time.perf_counter()
                        try:
                            reply_data = json.loads(reply_message)
                            correlation_id = reply_data.get("correlation_id")
                            parse_ms = int((time.perf_counter() - parse_t0) * 1000.0)
                            elapsed_ms = int((time.perf_counter() - cmd_start_t0) * 1000.0)
                            response_budget_state = "OVER_BUDGET" if int(elapsed_ms) > int(effective_timeout_ms) else "ON_BUDGET"
                            lock_wait_ms = self._write_audit_log(
                                "REPLY_RECEIVED",
                                correlation_id or "unknown",
                                {
                                    **reply_data,
                                    "phase": "reply_receive",
                                    "channel": "REQ_REP",
                                    "endpoint": endpoint,
                                    "attempt": int(attempt + 1),
                                    "retry_count": int(attempt),
                                    "send_ms": int(send_ms),
                                    "wait_ms": int(wait_ms),
                                    "parse_ms": int(parse_ms),
                                    "elapsed_ms": int(elapsed_ms),
                                    "timeout_budget_ms": int(effective_timeout_ms),
                                    "timeout_budget_bucket": budget_bucket,
                                    "command_action": action_norm,
                                    "command_type": command_type,
                                    "command_queue_wait_ms": int(command_queue_wait_ms),
                                    "hb_loop_lag_ms": int(hb_loop_lag_ms),
                                    "hb_market_data_stale_ms": int(hb_market_data_stale_ms),
                                    "response_budget_state": response_budget_state,
                                    "response_over_budget": bool(response_budget_state == "OVER_BUDGET"),
                                },
                            )
                            max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))

                            if correlation_id == msg_id:
                                req_hash_reply = str(reply_data.get("request_hash") or "")
                                req_hash_sent = str(original_command.get("request_hash") or "")
                                if req_hash_reply and req_hash_reply != req_hash_sent:
                                    self._write_audit_log(
                                        "REPLY_REQUEST_HASH_MISMATCH",
                                        msg_id,
                                        {"expected": req_hash_sent, "got": req_hash_reply},
                                    )
                                    last_reason = "REQUEST_HASH_MISMATCH"
                                    last_subreason = "HASH_MISMATCH"
                                    continue

                                got_resp_hash = str(reply_data.get("response_hash") or "")
                                if got_resp_hash:
                                    exp_resp_hash = str(build_response_hash(reply_data))
                                    if got_resp_hash != exp_resp_hash:
                                        self._write_audit_log(
                                            "REPLY_RESPONSE_HASH_MISMATCH",
                                            msg_id,
                                            {"expected": exp_resp_hash, "got": got_resp_hash},
                                        )
                                        last_reason = "RESPONSE_HASH_MISMATCH"
                                        last_subreason = "HASH_MISMATCH"
                                        continue
                                else:
                                    last_reason = "RESPONSE_HASH_MISSING"
                                    last_subreason = "HASH_MISSING"

                                rtt_ms = int((time.perf_counter() - cmd_start_t0) * 1000.0)
                                diag.update(
                                    {
                                        "bridge_send_ms": int(send_ms),
                                        "bridge_wait_ms": int(wait_ms),
                                        "bridge_parse_ms": int(parse_ms),
                                        "bridge_total_ms": int(rtt_ms),
                                        "bridge_timeout_reason": "NONE",
                                        "bridge_timeout_subreason": "NONE",
                                        "status": "OK",
                                        "fallback_used": False,
                                        "audit_log_lock_wait_max_ms": int(max_audit_lock_wait_ms),
                                        "response_budget_state": response_budget_state,
                                    }
                                )
                                self._set_last_command_diag(diag)
                                reply_data["__bridge_diag"] = dict(diag)
                                logging.info(
                                    "ZMQ_RTT msg_id=%s loop_id=%s send_ms=%s wait_ms=%s parse_ms=%s rtt_ms=%s action=%s",
                                    msg_id,
                                    str(diag.get("loop_id") or "none"),
                                    int(send_ms),
                                    int(wait_ms),
                                    int(parse_ms),
                                    int(rtt_ms),
                                    str(original_command.get("action") or ""),
                                )
                                return reply_data
                            last_reason = "CORRELATION_MISMATCH"
                            last_subreason = "CORRELATION_MISMATCH"
                        except json.JSONDecodeError:
                            self._write_audit_log("REPLY_INVALID_JSON", msg_id, {"raw_reply": reply_message})
                            diag.update(
                                {
                                    "bridge_send_ms": int(send_ms),
                                    "bridge_wait_ms": int(wait_ms),
                                    "bridge_parse_ms": int(parse_ms),
                                    "bridge_total_ms": int((time.perf_counter() - cmd_start_t0) * 1000.0),
                                    "bridge_timeout_reason": "PARSE_ERROR",
                                    "bridge_timeout_subreason": "INVALID_JSON",
                                    "status": "FAILED",
                                    "fallback_used": True,
                                    "audit_log_lock_wait_max_ms": int(max_audit_lock_wait_ms),
                                }
                            )
                            self._set_last_command_diag(diag)
                            return None
                    else:
                        last_reason = "TIMEOUT_NO_RESPONSE"
                        if command_type == "HEARTBEAT":
                            if int(hb_loop_lag_ms) >= 1000:
                                timeout_subreason = "HB_LOOP_BUSY"
                            elif int(command_queue_wait_ms) >= 200:
                                timeout_subreason = "HB_LOOP_BUSY"
                            elif int(command_queue_wait_ms) >= 50:
                                timeout_subreason = "HB_QUEUE_DELAY"
                            elif int(max_audit_lock_wait_ms) >= 25:
                                timeout_subreason = "HB_LOCK_CONTENTION"
                            elif int(hb_market_data_stale_ms) >= 0 and int(hb_market_data_stale_ms) >= 120000:
                                timeout_subreason = "HB_NO_WORKER_RESPONSE"
                            else:
                                timeout_subreason = "HB_NO_WORKER_RESPONSE"
                        else:
                            timeout_subreason = "NO_RESPONSE"
                            if int(command_queue_wait_ms) >= 50:
                                timeout_subreason = "QUEUE"
                            elif int(max_audit_lock_wait_ms) >= 25:
                                timeout_subreason = "LOCK"
                        last_subreason = timeout_subreason
                        wait_ms = int((time.perf_counter() - wait_t0) * 1000.0)
                        lock_wait_ms = self._write_audit_log(
                            "COMMAND_TIMEOUT",
                            msg_id,
                            {
                                "phase": "recv_timeout",
                                "channel": "REQ_REP",
                                "endpoint": f"tcp://127.0.0.1:{self.req_port}",
                                "attempt": int(attempt + 1),
                                "retry_count": int(attempt),
                                "action": action_norm,
                                "command_type": command_type,
                                "timeout_budget_bucket": budget_bucket,
                                "send_ms": int(send_ms),
                                "wait_ms": int(wait_ms),
                                "timeout_budget_ms": int(effective_timeout_ms),
                                "bridge_timeout_reason": "TIMEOUT_NO_RESPONSE",
                                "bridge_timeout_subreason": timeout_subreason,
                                "command_queue_wait_ms": int(command_queue_wait_ms),
                                "audit_log_lock_wait_ms": int(max_audit_lock_wait_ms),
                                "hb_loop_lag_ms": int(hb_loop_lag_ms),
                                "hb_market_data_stale_ms": int(hb_market_data_stale_ms),
                                "wait_over_budget": bool(int(wait_ms) >= int(effective_timeout_ms)),
                                "fail_safe_decision_tag": "retry",
                            },
                        )
                        max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))
                        if bool(reconnect_on_timeout):
                            self._reconnect_req_socket()

                except (TypeError, json.JSONDecodeError) as e:
                    self._write_audit_log("COMMAND_SERIALIZATION_ERROR", msg_id, {"error": str(e)})
                    diag.update(
                        {
                            "bridge_send_ms": int(send_ms),
                            "bridge_wait_ms": int(wait_ms),
                            "bridge_parse_ms": int(parse_ms),
                            "bridge_total_ms": int((time.perf_counter() - cmd_start_t0) * 1000.0),
                            "bridge_timeout_reason": "SERIALIZATION_ERROR",
                            "bridge_timeout_subreason": "SERIALIZATION",
                            "status": "FAILED",
                            "fallback_used": True,
                            "audit_log_lock_wait_max_ms": int(max_audit_lock_wait_ms),
                        }
                    )
                    self._set_last_command_diag(diag)
                    return None
                except zmq.Again:
                    last_reason = "SEND_TIMEOUT"
                    last_subreason = "NO_ACTIVE_PEER"
                    lock_wait_ms = self._write_audit_log(
                        "COMMAND_SEND_TIMEOUT",
                        msg_id,
                        {
                            "phase": "send_timeout",
                            "channel": "REQ_REP",
                            "endpoint": f"tcp://127.0.0.1:{self.req_port}",
                            "attempt": int(attempt + 1),
                            "retry_count": int(attempt),
                            "action": action_norm,
                            "command_type": command_type,
                            "timeout_budget_bucket": budget_bucket,
                            "send_ms": int(send_ms),
                            "timeout_budget_ms": int(effective_timeout_ms),
                            "bridge_timeout_reason": "SEND_TIMEOUT",
                            "bridge_timeout_subreason": "NO_ACTIVE_PEER",
                            "command_queue_wait_ms": int(command_queue_wait_ms),
                            "audit_log_lock_wait_ms": int(max_audit_lock_wait_ms),
                            "hb_loop_lag_ms": int(hb_loop_lag_ms),
                            "hb_market_data_stale_ms": int(hb_market_data_stale_ms),
                            "fail_safe_decision_tag": "retry",
                        },
                    )
                    max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))
                    self._reconnect_req_socket()
                except zmq.ZMQError:
                    last_reason = "ZMQ_ERROR"
                    last_subreason = "SOCKET_ERROR"
                    self._reconnect_req_socket()

            final_reason = str(last_reason or "COMMAND_FAILED")
            final_subreason = str(last_subreason or "UNKNOWN")
            if final_reason == "TIMEOUT_NO_RESPONSE":
                if command_type == "HEARTBEAT":
                    final_subreason = "HB_REPLY_MISSED_WINDOW"
                else:
                    final_subreason = "RETRY_CEILING"

            self._write_audit_log(
                "COMMAND_FAILED",
                msg_id,
                {
                    "phase": "command_fail",
                    "channel": "REQ_REP",
                    "endpoint": f"tcp://127.0.0.1:{self.req_port}",
                    "retries": int(effective_retries),
                    "action": action_norm,
                    "command_type": command_type,
                    "timeout_budget_bucket": budget_bucket,
                    "timeout_budget_ms": int(effective_timeout_ms),
                    "bridge_timeout_reason": final_reason,
                    "bridge_timeout_subreason": final_subreason,
                    "command_queue_wait_ms": int(command_queue_wait_ms),
                    "audit_log_lock_wait_ms": int(max_audit_lock_wait_ms),
                    "hb_loop_lag_ms": int(hb_loop_lag_ms),
                    "hb_market_data_stale_ms": int(hb_market_data_stale_ms),
                    "fail_safe_decision_tag": "no_trade",
                },
            )
            diag.update(
                {
                    "bridge_total_ms": int((time.perf_counter() - cmd_start_t0) * 1000.0),
                    "bridge_timeout_reason": final_reason,
                    "bridge_timeout_subreason": final_subreason,
                    "status": "FAILED",
                    "fallback_used": True,
                    "audit_log_lock_wait_max_ms": int(max_audit_lock_wait_ms),
                }
            )
            self._set_last_command_diag(diag)
            return None
        finally:
            if is_trade_command:
                try:
                    self._trade_mark_done()
                except Exception as exc:
                    _ = exc
            self._command_lock.release()

    def _reconnect_req_socket(self):
        """Prywatna metoda do resetowania gniazda REQ w przypadku timeoutu lub błędu."""
        logging.info("Resetowanie gniazda REQ...")
        if self.req_socket:
            self.req_socket.close()
        
        self.req_socket = self.context.socket(zmq.REQ)
        self._configure_req_socket(self.req_socket)
        self.req_socket.bind(f"tcp://127.0.0.1:{self.req_port}")
        logging.info("Gniazdo REQ zostało zresetowane i ponownie powiązane.")


    def close(self) -> None:
        """
        Zamyka gniazda i kontekst ZMQ w sposób bezpieczny.
        """
        logging.info("Zamykanie mostu ZMQ...")
        if self._audit_async_enabled:
            self._audit_stop.set()
            if self._audit_thread and self._audit_thread.is_alive():
                self._audit_thread.join(timeout=max(0.5, 2.0 * self._audit_flush_interval_s))
            self._flush_audit_queue_sync()
        if self.pull_socket:
            self.pull_socket.close()
        if self.req_socket:
            self.req_socket.close()
        if self.context:
            self.context.term()
        logging.info("Most ZMQ zamknięty.")

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    
    print("Testowanie inicjalizacji mostu ZMQ z logiką REQ/REP i audytem...")
    bridge = None
    try:
        # Używamy tymczasowego pliku audytu do testu
        test_audit_file = "test_audit_trail.jsonl"
        bridge = ZMQBridge(audit_log_path=test_audit_file)
        bridge.setup_sockets()
        print(f"Gniazda PULL i REQ utworzone. Dziennik audytu w '{test_audit_file}'.")

        test_cmd = {"action": "TEST", "symbol": "EURUSD", "payload": "Hello from Python REQ"}
        print(f"\nWysyłanie testowej komendy i oczekiwanie na odpowiedź: {test_cmd}")
        
        print("\nUruchom klienta testowego MQL5 (REP) na porcie 5556, aby odpowiedział na komendę.")
        reply = bridge.send_command(test_cmd)
        
        if reply:
            print(f"\nOdebrano pomyślną odpowiedź: {reply}")
        else:
            print("\nNie udało się otrzymać odpowiedzi po wszystkich próbach (to jest oczekiwane bez klienta).")

        print(f"\nZawartość pliku audytu ('{test_audit_file}'):")
        try:
            with open(test_audit_file, "r") as f:
                for line in f:
                    print(line.strip())
            import os
            os.remove(test_audit_file)
            print(f"\nPlik '{test_audit_file}' został usunięty.")
        except FileNotFoundError:
            print("Plik audytu nie został utworzony (co może być błędem).")

    except zmq.ZMQError as e:
        print(f"BŁĄD KRYTYCZNY: {e}")
    except Exception as e:
        print(f"Wystąpił niespodziewany błąd: {e}")
    finally:
        if bridge:
            bridge.close()
            print("Zasoby ZMQ zwolnione.")
