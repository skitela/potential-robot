from flask import Flask, jsonify, render_template
import zmq
import threading
import json
import time
import random

# --- Konfiguracja ---
ZMQ_ADDRESS = "tcp://localhost:5556"
# Zmień powyższy adres, jeśli Twój bot publikuje dane na innym porcie lub maszynie.

# --- Globalny, współdzielony stan dashboardu ---
# Zamykamy dane w słowniku, aby zapewnić bezpieczny dostęp z różnych wątków.
shared_data_lock = threading.Lock()
dashboard_data = {
    "data": None,
    "last_update_timestamp": 0
}

# --- Przykładowe dane, na wypadek gdyby bot nie był uruchomiony ---
def get_dummy_data():
    """Generuje losowe, ale spójne dane do celów demonstracyjnych."""
    statuses = ["AKTYWNY", "TRYB ECO", "KONSERWACJA", "BŁĄD KRYTYCZNY"]
    components_status = ["OK", "OK", "OK", "FAIL"]
    
    # Symulacja zmiany statusu
    current_status = random.choice(statuses)
    is_error = current_status == "BŁĄD KRYTYCZNY"
    
    return {
        "system_health": {
            "status": current_status, 
            "components": { 
                "python_brain": "OK" if not is_error else "FAIL", 
                "mql5_reflex": "OK" if not is_error else "OK", 
                "zeromq_bridge": random.choice(components_status) if not is_error else "FAIL"
            },
            "last_heartbeat_utc": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            "active_window": "FX (09:00-12:00)" if current_status == "AKTYWNY" else "N/A"
        },
        "performance": {
            "pnl_today": round(random.uniform(-150, 350), 2),
            "pnl_today_pct": round(random.uniform(-0.5, 1.5), 2),
            "profit_factor": round(random.uniform(0.8, 2.5), 2),
            "win_rate_pct": round(random.uniform(55, 80), 1),
            "trades_today": random.randint(5, 100)
        },
        "strategy_dna": {
            "avg_position_duration_sec": round(random.uniform(30, 120), 1),
            "avg_win_avg_loss_ratio": round(random.uniform(0.7, 1.5), 2),
            "avg_slippage_pips": round(random.uniform(0.01, 0.15), 3),
            "avg_entry_spread_pips": round(random.uniform(0.8, 2.0), 2)
        },
        "risk_limits": {
            "daily_loss_limit_progress_pct": round(random.uniform(0, 100), 1),
            "current_drawdown_pct": round(random.uniform(-5, 0), 2),
            "broker_order_limit_usage_pct": round(random.uniform(5, 50), 1),
            "open_positions": random.randint(0, 5)
        }
    }

# --- Wątek Odbiornika ZeroMQ ---
def zmq_subscriber_thread():
    """
    Wątek, który łączy się z publikerem ZeroMQ bota, odbiera dane
    i aktualizuje globalny stan dashboardu.
    """
    context = zmq.Context()
    socket = context.socket(zmq.SUB)
    socket.connect(ZMQ_ADDRESS)
    socket.setsockopt_string(zmq.SUBSCRIBE, "") # Subskrybuj wszystkie wiadomości

    print(f"INFO: Nasłuchiwanie na dane z ZeroMQ pod adresem: {ZMQ_ADDRESS}")

    while True:
        try:
            message = socket.recv_string()
            data = json.loads(message)
            
            with shared_data_lock:
                dashboard_data["data"] = data
                dashboard_data["last_update_timestamp"] = time.time()

        except json.JSONDecodeError:
            print("BŁĄD: Otrzymano nieprawidłowy format JSON z ZeroMQ.")
        except Exception as e:
            print(f"Krytyczny błąd w wątku ZeroMQ: {e}")
            # W przypadku poważnego błędu, poczekaj chwilę przed ponowną próbą
            time.sleep(5)

# --- Aplikacja Flask ---
app = Flask(__name__)

@app.route('/')
def index():
    """Serwuje główną stronę dashboardu."""
    return render_template('index.html')

@app.route('/api/data')
def get_data():
    """Endpoint API, który dostarcza dane do frontendu."""
    with shared_data_lock:
        # Sprawdź, czy mamy świeże dane z ZMQ. Jeśli nie (np. bot wyłączony),
        # użyj danych demonstracyjnych. Dane starsze niż 10 sekund uznajemy za nieaktualne.
        is_stale = (time.time() - dashboard_data["last_update_timestamp"]) > 10
        
        if dashboard_data["data"] is None or is_stale:
            # Zwróć dane demonstracyjne, jeśli prawdziwe dane są niedostępne lub stare
            response_data = get_dummy_data()
            # Dodaj flagę, aby frontend wiedział, że to dane demo
            response_data["system_health"]["status"] = "OCZEKIWANIE"
            response_data["is_demo_data"] = True
        else:
            response_data = dashboard_data["data"]
            response_data["is_demo_data"] = False

    return jsonify(response_data)


if __name__ == '__main__':
    # Uruchom wątek subskrybenta ZeroMQ w tle
    subscriber = threading.Thread(target=zmq_subscriber_thread, daemon=True)
    subscriber.start()
    
    # Uruchom aplikację Flask
    # Użyj portu innego niż domyślny 5000, aby uniknąć konfliktów
    print("INFO: Uruchamianie serwera dashboardu pod adresem: http://127.0.0.1:5001")
    app.run(host='0.0.0.0', port=5001)

