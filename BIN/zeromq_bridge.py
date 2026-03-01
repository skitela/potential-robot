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

    def __init__(self, pull_port: int = 5555, req_port: int = 5556, req_timeout_ms: int = 5000, req_retries: int = 3, audit_log_path: Optional[str] = "LOGS/audit_trail.jsonl"):
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

        logging.info(
            f"ZMQBridge zainicjalizowany. Odbiór danych na porcie {pull_port}, komunikacja REQ/REP na porcie {req_port}."
        )
        if self.audit_log_path:
            logging.info(f"Dziennik audytu będzie zapisywany w: {self.audit_log_path}")

    def _set_last_command_diag(self, diag: Dict[str, Any]) -> None:
        with self._diag_lock:
            self._last_command_diag = dict(diag or {})

    def get_last_command_diag(self) -> Dict[str, Any]:
        with self._diag_lock:
            return dict(self._last_command_diag)

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
        
        lock_wait_ms = 0
        try:
            lock_t0 = time.perf_counter()
            with self._audit_log_lock:
                lock_wait_ms = int((time.perf_counter() - lock_t0) * 1000.0)
                self._audit_log_file.parent.mkdir(parents=True, exist_ok=True)
                with open(self._audit_log_file, "a", encoding="utf-8") as f:
                    f.write(json.dumps(log_entry, separators=(",", ":")) + "\n")
        except Exception as e:
            logging.error(f"Nie udało się zapisać do dziennika audytu: {e}")
        return int(lock_wait_ms)

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

        queue_wait_t0 = time.perf_counter()
        self._command_lock.acquire()
        command_queue_wait_ms = int((time.perf_counter() - queue_wait_t0) * 1000.0)

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
                "endpoint": f"tcp://127.0.0.1:{self.req_port}",
                "command_queue_wait_ms": int(command_queue_wait_ms),
                "audit_log_lock_wait_max_ms": 0,
            }

            self._set_last_command_diag(diag)
            cmd_start_t0 = time.perf_counter()
            last_reason = "UNKNOWN"
            last_subreason = "UNKNOWN"
            max_audit_lock_wait_ms = 0

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
                            "endpoint": f"tcp://127.0.0.1:{self.req_port}",
                            "attempt": int(attempt + 1),
                            "retry_count": int(attempt),
                            "timeout_budget_ms": int(effective_timeout_ms),
                            "timeout_budget_bucket": budget_bucket,
                            "command_type": command_type,
                            "command_queue_wait_ms": int(command_queue_wait_ms),
                        },
                    )
                    max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))

                    send_t0 = time.perf_counter()
                    message = json.dumps(original_command, separators=(",", ":"))
                    self.req_socket.send_string(message)
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
                                    "endpoint": f"tcp://127.0.0.1:{self.req_port}",
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
                                "wait_over_budget": bool(int(wait_ms) >= int(effective_timeout_ms)),
                                "fail_safe_decision_tag": "retry",
                            },
                        )
                        max_audit_lock_wait_ms = max(int(max_audit_lock_wait_ms), int(lock_wait_ms))
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
