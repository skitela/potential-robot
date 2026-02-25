# Dashboard Monitorujący dla Systemu OANDA MT5

Ten folder zawiera autonomiczną aplikację webową do monitorowania kluczowych metryk Twojego bota tradingowego w czasie rzeczywistym.

## Architektura

Aplikacja składa się z dwóch głównych części:
1.  **Backend (Python/Flask):** Prosty serwer, który działa jako subskrybent (słuchacz) danych publikowanych przez głównego bota przez most ZeroMQ. Następnie udostępnia te dane przez prosty endpoint API.
2.  **Frontend (HTML/CSS/JS):** Strona internetowa, która odpytuje endpoint API i dynamicznie aktualizuje wyświetlane wartości bez potrzeby przeładowywania strony.

**Ważne:** Ta aplikacja **nie modyfikuje** w żaden sposób Twojego istniejącego kodu bota. Jest całkowicie nieinwazyjna.

## Instalacja

Zaleca się uruchomienie aplikacji w dedykowanym środowisku wirtualnym.

1.  **Utwórz środowisko wirtualne (opcjonalne, ale zalecane):**
    ```sh
    python -m venv .venv
    # Aktywuj środowisko
    # Windows:
    .venv\Scripts\activate
    # macOS/Linux:
    source .venv/bin/activate
    ```

2.  **Zainstaluj wymagane zależności:**
    Upewnij się, że jesteś w głównym katalogu projektu (`OANDA_MT5_SYSTEM`), a następnie uruchom:
    ```sh
    pip install -r dashboard/requirements.txt
    ```

## Uruchomienie

1.  Upewnij się, że Twój główny bot tradingowy jest uruchomiony i publikuje dane przez ZeroMQ.

2.  Uruchom aplikację dashboardu:
    ```sh
    python dashboard/app.py
    ```

3.  Otwórz przeglądarkę internetową i przejdź pod adres, który wyświetli się w konsoli (domyślnie `http://127.0.0.1:5001`).

## Konfiguracja

### Port ZeroMQ
Domyślnie aplikacja nasłuchuje na dane pod adresem `tcp://localhost:5556`. Jeśli Twój bot publikuje dane na innym porcie, zmień wartość zmiennej `ZMQ_ADDRESS` na początku pliku `dashboard/app.py`.

### Port Serwera WWW
Dashboard uruchamia się na porcie `5001`, aby uniknąć konfliktu z domyślnym portem Flaska (5000). Możesz to zmienić w ostatniej linijce pliku `dashboard/app.py`.

### Logo
Aby dodać swoje logo, znajdź w pliku `dashboard/templates/index.html` poniższy fragment i zastąp go swoim tagiem `<img>`:
```html
<div class="logo-placeholder">
    <!-- Zastąp ten div swoim tagiem <img> z logo -->
    LOGO
</div>
```
Na przykład:
```html
<img src="/static/moje-logo.png" alt="Moje Logo" class="logo-image">
```
Pamiętaj, aby umieścić plik z logo w katalogu `dashboard/static/`.

### Dane Demonstracyjne
Jeśli aplikacja dashboardu nie może połączyć się z botem (lub dane są starsze niż 10 sekund), automatycznie przełączy się w tryb demonstracyjny i będzie wyświetlać losowo generowane dane. Status systemu zmieni się wtedy na `OCZEKIWANIE`.
