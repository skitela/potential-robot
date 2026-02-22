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
  2. PUSH Socket (Port 5556): Python używa tego portu do wysyłania komend
     (sygnałów transakcyjnych, poleceń modyfikacji) do MQL5.
- Ten wzorzec (PUSH/PULL) jest idealny do rozdzielenia strumieni danych i komend
  i zapewnia, że wiadomości są kolejkowane i dostarczane niezawodnie.
- Wszystkie wiadomości są serializowane do formatu JSON.
"""

from __future__ import annotations

import json
import logging
from typing import Any, Dict, Optional

import zmq


class ZMQBridge:
    """
    Zarządza połączeniem ZeroMQ do komunikacji z agentem MQL5.
    """

    def __init__(self, pull_port: int = 5555, push_port: int = 5556):
        """
        Inicjalizuje kontekst ZMQ i definiuje porty.

        :param pull_port: Port do odbierania danych z MQL5 (MQL5 będzie tu wysyłał).
        :param push_port: Port do wysyłania komend do MQL5 (MQL5 będzie tu nasłuchiwał).
        """
        self.pull_port = pull_port
        self.push_port = push_port
        self.context = zmq.Context()
        self.pull_socket: Optional[zmq.Socket] = None
        self.push_socket: Optional[zmq.Socket] = None
        logging.info(
            f"ZMQBridge zainicjalizowany. Odbiór danych na porcie {pull_port}, wysyłanie komend na porcie {push_port}."
        )

    def setup_sockets(self) -> None:
        """
        Tworzy i wiąże gniazda ZMQ.
        Musi być wywołane przed próbą wysłania lub odbioru.
        """
        try:
            # Gniazdo do odbierania danych od MQL5 - ograniczony do localhost (P0 Security)
            self.pull_socket = self.context.socket(zmq.PULL)
            self.pull_socket.bind(f"tcp://127.0.0.1:{self.pull_port}")
            logging.info(f"ZMQ PULL socket nasłuchuje na tcp://127.0.0.1:{self.pull_port}")

            # Gniazdo do wysyłania komend do MQL5 - ograniczony do localhost (P0 Security)
            self.push_socket = self.context.socket(zmq.PUSH)
            self.push_socket.bind(f"tcp://127.0.0.1:{self.push_port}")
            logging.info(f"ZMQ PUSH socket gotowy do wysyłania na tcp://127.0.0.1:{self.push_port}")

        except zmq.ZMQError as e:
            logging.error(f"Nie udało się powiązać gniazd ZMQ: {e}")
            logging.error("Sprawdź, czy inny proces (lub poprzednia instancja bota) nie używa portów 5555/5556.")
            raise

    def receive_data(self, timeout: Optional[int] = None) -> Optional[Dict[str, Any]]:
        """
        Odbiera dane z Agenta MQL5. Może działać w trybie blokującym lub z timeoutem.

        :param timeout: Czas oczekiwania na wiadomość w milisekundach.
                        Jeśli None, czeka w nieskończoność (blokuje).
        :return: Zdeserializowany słownik (wiadomość JSON) lub None, jeśli upłynął timeout.
        """
        if not self.pull_socket:
            logging.error("Próba odbioru na niezainicjalizowanym gnieździe PULL.")
            return None

        try:
            if timeout is not None:
                # Sprawdź, czy są dane do odebrania, z zadanym timeoutem
                if not self.pull_socket.poll(timeout):
                    return None  # Timeout

            # Odbierz wiadomość (w tym momencie powinna już być dostępna)
            message = self.pull_socket.recv_string(flags=zmq.NOBLOCK if timeout is not None else 0)
            return json.loads(message)
        except zmq.Again:
            # Oczekiwany wyjątek przy NOBLOCK, gdy nie ma wiadomości
            return None
        except (json.JSONDecodeError, TypeError) as e:
            logging.warning(f"Błąd deserializacji wiadomości JSON z MQL5: {e}")
            return None
        except Exception as e:
            logging.error(f"Niespodziewany błąd podczas odbierania danych ZMQ: {e}")
            return None


    def send_command(self, command: Dict[str, Any]) -> bool:
        """
        Wysyła komendę do Agenta MQL5.

        :param command: Słownik Pythona reprezentujący komendę.
        :return: True, jeśli wysłano pomyślnie, False w przeciwnym razie.
        """
        if not self.push_socket:
            logging.error("Próba wysłania na niezainicjalizowanym gnieździe PUSH.")
            return False
        try:
            message = json.dumps(command, separators=(",", ":"))
            self.push_socket.send_string(message)
            return True
        except (TypeError, json.JSONDecodeError) as e:
            logging.error(f"Błąd serializacji komendy do JSON: {e}")
            return False
        except Exception as e:
            logging.error(f"Niespodziewany błąd podczas wysyłania komendy ZMQ: {e}")
            return False

    def close(self) -> None:
        """
        Zamyka gniazda i kontekst ZMQ w sposób bezpieczny.
        """
        logging.info("Zamykanie mostu ZMQ...")
        if self.pull_socket:
            self.pull_socket.close()
        if self.push_socket:
            self.push_socket.close()
        if self.context:
            self.context.term()
        logging.info("Most ZMQ zamknięty.")

if __name__ == '__main__':
    # Prosty przykład użycia i test, który można uruchomić, aby zweryfikować,
    # czy gniazda są poprawnie tworzone.
    print("Testowanie inicjalizacji mostu ZMQ...")
    bridge = None
    try:
        bridge = ZMQBridge()
        bridge.setup_sockets()
        print("Gniazda PULL i PUSH zostały pomyślnie utworzone i powiązane.")

        # Test wysyłania
        test_cmd = {"action": "TEST", "symbol": "EURUSD", "payload": "Hello from Python"}
        print(f"Wysyłanie testowej komendy: {test_cmd}")
        success = bridge.send_command(test_cmd)
        print(f"Wysłano pomyślnie: {success}")

        print("\nOczekiwanie na testowa wiadomosc od klienta MQL5 (timeout 10s)...")
        print("Aby przetestować, uruchom klienta MQL5, który wyśle wiadomość na port 5555.")
        data = bridge.receive_data(timeout=10000)
        if data:
            print(f"Odebrano dane: {data}")
        else:
            print("Nie odebrano danych (timeout).")

    except zmq.ZMQError as e:
        print(f"BŁĄD KRYTYCZNY: {e}")
        print("Upewnij się, że porty 5555 i 5556 nie są zablokowane.")
    except Exception as e:
        print(f"Wystąpił niespodziewany błąd: {e}")
    finally:
        if bridge:
            bridge.close()
            print("Zasoby ZMQ zwolnione.")
