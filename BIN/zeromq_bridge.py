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
        self._audit_log_file: Optional[Path] = Path(self.audit_log_path) if self.audit_log_path else None

        logging.info(
            f"ZMQBridge zainicjalizowany. Odbiór danych na porcie {pull_port}, komunikacja REQ/REP na porcie {req_port}."
        )
        if self.audit_log_path:
            logging.info(f"Dziennik audytu będzie zapisywany w: {self.audit_log_path}")

    def _write_audit_log(self, event_type: str, message_id: str, data: Dict[str, Any]):
        """Zapisuje zdarzenie do pliku dziennika audytu w sposób bezpieczny wątkowo."""
        if not self._audit_log_file:
            return
        
        log_entry = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "event_type": event_type,
            "message_id": message_id,
            "data": data
        }
        
        try:
            with self._audit_log_lock:
                self._audit_log_file.parent.mkdir(parents=True, exist_ok=True)
                with open(self._audit_log_file, "a", encoding="utf-8") as f:
                    f.write(json.dumps(log_entry, separators=(",", ":")) + "\n")
        except Exception as e:
            logging.error(f"Nie udało się zapisać do dziennika audytu: {e}")

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
            self.req_socket.bind(f"tcp://127.0.0.1:{self.req_port}")
            self.req_socket.setsockopt(zmq.LINGER, 0)
            logging.info(f"ZMQ REQ socket gotowy do wysyłania na tcp://127.0.0.1:{self.req_port}")

        except zmq.ZMQError as e:
            logging.error(f"Nie udało się powiązać gniazd ZMQ: {e}")
            logging.error(f"Sprawdź, czy inny proces nie używa portów {self.pull_port}/{self.req_port}.")
            raise

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

    def send_command(self, command: Dict[str, Any]) -> Optional[Dict[str, Any]]:
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

        original_command = dict(command)
        original_command.setdefault("__v", PROTOCOL_VERSION)
        original_command.setdefault("schema_version", PROTOCOL_VERSION)
        if "msg_id" not in original_command:
            original_command["msg_id"] = str(uuid.uuid4())
        msg_id = str(original_command["msg_id"])
        original_command["request_hash"] = str(build_request_hash(original_command))
        original_command.setdefault("request_ts_utc", datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"))

        for attempt in range(self.req_retries):
            try:
                logging.debug(f"Wysyłanie komendy (próba {attempt + 1}/{self.req_retries}): {original_command}")
                self._write_audit_log("COMMAND_SENT", msg_id, original_command)
                message = json.dumps(original_command, separators=(",", ":"))
                t0 = time.perf_counter()
                self.req_socket.send_string(message)

                if self.req_socket.poll(self.req_timeout_ms):
                    reply_message = self.req_socket.recv_string()
                    logging.debug(f"Odebrano odpowiedź: {reply_message}")
                    try:
                        reply_data = json.loads(reply_message)
                        correlation_id = reply_data.get('correlation_id')
                        self._write_audit_log("REPLY_RECEIVED", correlation_id or "unknown", reply_data)
                         
                        if correlation_id == msg_id:
                            req_hash_reply = str(reply_data.get("request_hash") or "")
                            req_hash_sent = str(original_command.get("request_hash") or "")
                            if req_hash_reply and req_hash_reply != req_hash_sent:
                                logging.warning(
                                    "Hash request mismatch in reply. expected=%s got=%s",
                                    req_hash_sent,
                                    req_hash_reply,
                                )
                                self._write_audit_log(
                                    "REPLY_REQUEST_HASH_MISMATCH",
                                    msg_id,
                                    {"expected": req_hash_sent, "got": req_hash_reply},
                                )
                                continue

                            got_resp_hash = str(reply_data.get("response_hash") or "")
                            if got_resp_hash:
                                exp_resp_hash = str(build_response_hash(reply_data))
                                if got_resp_hash != exp_resp_hash:
                                    logging.warning(
                                        "Response hash mismatch. expected=%s got=%s",
                                        exp_resp_hash,
                                        got_resp_hash,
                                    )
                                    self._write_audit_log(
                                        "REPLY_RESPONSE_HASH_MISMATCH",
                                        msg_id,
                                        {"expected": exp_resp_hash, "got": got_resp_hash},
                                    )
                                    continue
                            else:
                                logging.warning("Reply missing response_hash for msg_id=%s", msg_id)

                            rtt_ms = int((time.perf_counter() - t0) * 1000.0)
                            logging.info("ZMQ_RTT msg_id=%s rtt_ms=%s action=%s", msg_id, rtt_ms, str(original_command.get("action") or ""))
                            return reply_data
                        else:
                            logging.warning(f"Odebrano odpowiedź z nieprawidłowym correlation_id. Oczekiwano {msg_id}, otrzymano {correlation_id}.")
                    except json.JSONDecodeError:
                        logging.error(f"Nie udało się zdeserializować odpowiedzi od MQL5: {reply_message}")
                        self._write_audit_log("REPLY_INVALID_JSON", msg_id, {"raw_reply": reply_message})
                        return None 
                else:
                    logging.warning(f"Timeout (próba {attempt + 1}). Brak odpowiedzi od MQL5 dla msg_id: {msg_id}.")
                    self._write_audit_log("COMMAND_TIMEOUT", msg_id, {"attempt": attempt + 1, "timeout_ms": self.req_timeout_ms})
                    self._reconnect_req_socket()

            except (TypeError, json.JSONDecodeError) as e:
                logging.error(f"Błąd serializacji komendy do JSON: {e}")
                self._write_audit_log("COMMAND_SERIALIZATION_ERROR", msg_id, {"error": str(e)})
                return None
            except zmq.ZMQError as e:
                logging.error(f"Błąd gniazda ZMQ podczas wysyłania komendy: {e}")
                self._reconnect_req_socket()
        
        logging.error(f"Nie udało się wysłać komendy i otrzymać odpowiedzi po {self.req_retries} próbach dla msg_id: {msg_id}.")
        self._write_audit_log("COMMAND_FAILED", msg_id, {"retries": self.req_retries})
        return None

    def _reconnect_req_socket(self):
        """Prywatna metoda do resetowania gniazda REQ w przypadku timeoutu lub błędu."""
        logging.info("Resetowanie gniazda REQ...")
        if self.req_socket:
            self.req_socket.close()
        
        self.req_socket = self.context.socket(zmq.REQ)
        self.req_socket.setsockopt(zmq.LINGER, 0)
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
