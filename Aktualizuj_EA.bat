@echo off
setlocal

:: Gemini Agent Codename: AUTONOMOUS_METATRADER_MAESTRO
:: Operation: HYBRID_SCALPING_UPGRADE (MQL5 Hot-Swap)
:: Version: 2.1
:: Change ID: 29d8b4b7

echo [INFO] Inicjalizacja procesu aktualizacji Agenta Eksperckiego (EA) w MT5...
echo [INFO] Wersja skryptu: 2.1 (Build: 2026-02-21)

:: === Konfiguracja ===
:: Sciezka zrodlowa plikow .mq5 i .mqh w repozytorium projektu
set "SOURCE_DIR=%~dp0MQL5"

:: Sciezka docelowa do folderu MQL5 w terminalu MetaTrader 5
:: Uzytkownik podal te sciezke - jest ona specyficzna dla jego instalacji.
set "TARGET_DIR=C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856\MQL5"

echo [INFO] Katalog zrodlowy (repozytorium): %SOURCE_DIR%
echo [INFO] Katalog docelowy (MetaTrader 5): %TARGET_DIR%
echo.

:: === Walidacja ===
if not exist "%SOURCE_DIR%\Experts\HybridAgent.mq5" (
    echo [ERROR] Krytyczny blad: Nie znaleziono pliku zrodlowego HybridAgent.mq5!
    echo [ERROR] Sciezka: %SOURCE_DIR%\Experts\
    echo [ERROR] Proces przerwany. Sprawdz strukture repozytorium.
    pause
    exit /b 1
)

if not exist "%TARGET_DIR%" (
    echo [ERROR] Krytyczny blad: Sciezka docelowa dla MetaTrader 5 nie istnieje!
    echo [ERROR] Sciezka: %TARGET_DIR%
    echo [ERROR] Czy MetaTrader 5 jest zainstalowany i czy sciezka jest poprawna?
    echo [ERROR] Proces przerwany.
    pause
    exit /b 2
)

echo [SUCCESS] Walidacja wstepna zakonczona pomyslnie. Pliki zrodlowe i katalog docelowy sa dostepne.
echo.

:: === Proces Kopiowania ===
echo [EXEC] Rozpoczynanie kopiowania plikow EA...

:: Kopiowanie glownego pliku eksperta
echo [COPY] Kopiowanie: MQL5\Experts\HybridAgent.mq5
xcopy "%SOURCE_DIR%\Experts\HybridAgent.mq5" "%TARGET_DIR%\Experts\" /Y /Q /F
if %errorlevel% neq 0 (
    echo [ERROR] Nie udalo sie skopiowac HybridAgent.mq5.
) else (
    echo [SUCCESS] Skopiowano HybridAgent.mq5.
)

:: Kopiowanie plikow includowanych (np. kontrakty, helpery)
echo [COPY] Kopiowanie: MQL5\Include\*.mqh
xcopy "%SOURCE_DIR%\Include\*.mqh" "%TARGET_DIR%\Include\" /Y /Q /F
if %errorlevel% neq 0 (
    echo [ERROR] Nie udalo sie skopiowac plikow z folderu Include.
) else (
    echo [SUCCESS] Skopiowano wszystkie pliki .mqh z folderu Include.
)

echo.
echo [FINAL] === Proces aktualizacji zakonczony ===
echo [INFO] Pliki Agenta Eksperckiego zostaly zaktualizowane w katalogu MetaTrader 5.
echo [ACTION] Nastepny krok:
echo [ACTION] 1. Otworz MetaEditor w MT5.
echo [ACTION] 2. Otworz plik HybridAgent.mq5.
echo [ACTION] 3. Kliknij 'Kompiluj' (F7), aby zastosowac zmiany.
echo [ACTION] 4. Jesli EA jest juz na wykresie, przeladuj go, aby uzyc nowej wersji.
echo.

endlocal
pause
