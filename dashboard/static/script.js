// --- Globalny Stan i Konfiguracja ---
const API_URL = '/api/data';
const REFRESH_INTERVAL_MS = 3000; // 3 sekundy

// Przechowuje poprzedni stan danych, aby wykrywać zmiany
let previousData = {};

// --- Główne Funkcje ---

/**
 * Pobiera najnowsze dane z API backendu.
 */
async function fetchData() {
    try {
        const response = await fetch(API_URL);
        if (!response.ok) {
            throw new Error(`Błąd sieci: ${response.statusText}`);
        }
        const data = await response.json();
        updateDashboard(data);
    } catch (error) {
        console.error("Nie można pobrać danych dashboardu:", error);
        // Można tutaj dodać logikę wyświetlania błędu na UI
    }
}

/**
 * Aktualizuje wszystkie elementy na dashboardzie na podstawie świeżych danych.
 * @param {object} data - Obiekt danych z API.
 */
function updateDashboard(data) {
    // Aktualizuj tylko jeśli dane istnieją
    if (!data) return;

    // Sekcja 1: Status Systemu
    if (data.system_health) {
        const health = data.system_health;
        updateElement('status-ogolny', health.status, { textClass: `status-badge ${health.status.replace(/\s+/g, '-')}` });
        updateDiode('comp-python-brain', health.components.python_brain);
        updateDiode('comp-mql5-reflex', health.components.mql5_reflex);
        updateDiode('comp-zeromq-bridge', health.components.zeromq_bridge);
        updateElement('active-window', health.active_window);
        
        // Czas ostatniej aktualizacji
        const lastHeartbeat = new Date(health.last_heartbeat_utc);
        const now = new Date();
        const secondsAgo = Math.round((now - lastHeartbeat) / 1000);
        const updateText = data.is_demo_data ? "dane demo" : `${secondsAgo}s temu`;
        updateElement('last-update', updateText);
    }
    
    // Sekcja 2: Wydajność Finansowa
    if (data.performance) {
        const perf = data.performance;
        updateElement('pnl-today', perf.pnl_today.toFixed(2), { numeric: true, parentId: 'pnl-today' });
        updateElement('pnl-today-pct', `(${perf.pnl_today_pct.toFixed(2)}%)`, { numeric: true, parentId: 'pnl-today-pct' });
        updateElement('profit-factor', perf.profit_factor.toFixed(2));
        updateElement('win-rate-pct', `${perf.win_rate_pct.toFixed(1)}%`);
        updateElement('trades-today', perf.trades_today);
    }

    // Sekcja 3: Charakterystyka Strategii
    if (data.strategy_dna) {
        const dna = data.strategy_dna;
        updateElement('avg-position-duration-sec', dna.avg_position_duration_sec.toFixed(1));
        updateElement('avg-win-avg-loss-ratio', dna.avg_win_avg_loss_ratio.toFixed(2));
        updateElement('avg-slippage-pips', dna.avg_slippage_pips.toFixed(3));
        updateElement('avg-entry-spread-pips', dna.avg_entry_spread_pips.toFixed(2));
    }

    // Sekcja 4: Wskaźniki Ryzyka i Limity
    if (data.risk_limits) {
        const risk = data.risk_limits;
        updateProgressBar('daily-loss-limit', risk.daily_loss_limit_progress_pct);
        updateProgressBar('broker-order-limit', risk.broker_order_limit_usage_pct);
        updateElement('current-drawdown-pct', `${risk.current_drawdown_pct.toFixed(2)}%`, { numeric: true, positiveIsBad: true, parentId: 'current-drawdown-pct'});
        updateElement('open-positions', risk.open_positions);
    }

    // Zapisz obecny stan do porównania w następnej iteracji
    previousData = data;
}


// --- Funkcje Pomocnicze ---

/**
 * Aktualizuje tekst i klasy elementu, z opcją animacji przy zmianie.
 * @param {string} id - ID elementu do aktualizacji.
 * @param {string|number} value - Nowa wartość do wstawienia.
 * @param {object} [options] - Dodatkowe opcje.
 * @param {boolean} [options.numeric=false] - Czy wartość jest numeryczna (do kolorowania).
 * @param {boolean} [options.positiveIsBad=false] - Czy wartość dodatnia jest zła (np. drawdown).
 * @param {string} [options.textClass] - Konkretna klasa do ustawienia.
 * @param {string} [options.parentId] - ID rodzica do animacji.
 */
function updateElement(id, value, options = {}) {
    const element = document.getElementById(id);
    if (!element) return;

    const previousValue = previousData[id] ?? element.textContent;
    
    // Ustaw nową wartość
    element.textContent = value;

    // Obsługa klas dla wartości numerycznych
    if (options.numeric) {
        element.classList.remove('positive', 'negative', 'neutral');
        const numValue = parseFloat(value);
        if (numValue > 0) {
            element.classList.add(options.positiveIsBad ? 'negative' : 'positive');
        } else if (numValue < 0) {
            element.classList.add(options.positiveIsBad ? 'positive' : 'negative');
        } else {
            element.classList.add('neutral');
        }
    }
    
    // Obsługa konkretnej klasy (np. dla statusu)
    if (options.textClass) {
        element.className = options.textClass;
    }

    // Animacja na elemencie-rodzicu, jeśli wartość się zmieniła
    if (value.toString() !== previousValue.toString()) {
        const parentId = options.parentId || id;
        const parentElement = document.getElementById(parentId);
        if (parentElement) {
            const isNegative = element.classList.contains('negative');
            flashElement(parentElement, isNegative);
        }
    }
}


/**
 * Aktualizuje status "diody".
 * @param {string} id - ID diody.
 * @param {string} status - 'OK' lub 'FAIL'.
 */
function updateDiode(id, status) {
    const element = document.getElementById(id);
    if (!element) return;
    element.classList.remove('green', 'red', 'grey');
    if (status === 'OK') {
        element.classList.add('green');
    } else if (status === 'FAIL') {
        element.classList.add('red');
    } else {
        element.classList.add('grey');
    }
}

/**
 * Aktualizuje pasek postępu.
 * @param {string} name - Nazwa paska (prefix ID).
 * @param {number} percentage - Wartość procentowa.
 */
function updateProgressBar(name, percentage) {
    const bar = document.getElementById(`${name}-progress`);
    const label = document.getElementById(`${name}-label`);
    if (!bar || !label) return;

    bar.style.width = `${percentage}%`;
    label.textContent = `${percentage.toFixed(1)}%`;
    
    bar.classList.remove('high-usage', 'critical-usage');
    if (percentage > 85) {
        bar.classList.add('critical-usage');
    } else if (percentage > 60) {
        bar.classList.add('high-usage');
    }
}

/**
 * Dodaje klasę animacji do elementu i usuwa ją po zakończeniu.
 * @param {HTMLElement} element - Element do animacji.
 * @param {boolean} isNegative - Czy animacja ma być negatywna (czerwona).
 */
function flashElement(element, isNegative = false) {
    const animationClass = isNegative ? 'value-flash negative-flash' : 'value-flash';
    element.classList.add(animationClass);
    setTimeout(() => {
        element.classList.remove(animationClass);
    }, 700);
}


// --- Inicjalizacja ---
document.addEventListener('DOMContentLoaded', () => {
    fetchData(); // Pobierz dane od razu po załadowaniu strony
    setInterval(fetchData, REFRESH_INTERVAL_MS); // Ustaw cykliczne odświeżanie
});
