# Audyt Python/OANDA MT5 - 2026-02-18

## Zakres
- Zgodnosc Python 3.12 vs 3.14 z OANDA TMS MT5 (serwer zewnetrzny, test online attach).
- Zgodnosc instrumentow docelowych systemu z serwerem OANDA TMS.
- Regresja lokalnych kontraktow instrumentow i limitow.

## Testy wykonane

### Test 1A - Python 3.12 -> online_smoke_mt5 (LIVE)
- Komenda:
  - `py -3.12 -B TOOLS/online_smoke_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"`
- Wynik: PASS
- Dowod:
  - `EVIDENCE/broker_compat_3tests/manual_20260218T090842Z/test1_py312_online_smoke.json`
- Kluczowe pola:
  - `company`: `OANDA TMS Brokers S.A.`
  - `connected`: `true`
  - `trade_allowed`: `true`
  - terminal build: `5577` (`5 Feb 2026`)

### Test 1B - Python 3.14 -> online_smoke_mt5 (LIVE)
- Komenda:
  - `py -3.14 -B TOOLS/online_smoke_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"`
- Wynik: FAIL
- Dowod:
  - `EVIDENCE/broker_compat_3tests/manual_20260218T090842Z/test1_py314_online_smoke.json`
- Przyczyna:
  - `Import MetaTrader5 failed: No module named 'MetaTrader5'`

Wniosek techniczny:
- Srodowisko online OANDA MT5 dziala u Ciebie poprawnie na Python 3.12.
- Python 3.14 nie jest gotowy do online tradingu w tym setupie (brak pakietu `MetaTrader5`).

### Test 2 - Instrumenty docelowe vs serwer OANDA (STRICT)
- Komenda:
  - `py -3.12 -B TOOLS/audit_symbols_get_mt5.py --mt5-path "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe" --strict`
- Wynik: PASS
- Dowod:
  - `EVIDENCE/broker_compat_3tests/manual_20260218T090842Z/test2_symbols_get_audit.json`
- Liczba symboli: `1765`
- Instrumenty docelowe i trafienia:
  - EURUSD -> `EURUSD`, `EURUSD.PRO`
  - GBPUSD -> `GBPUSD`, `GBPUSD.PRO`
  - XAUUSD -> `GOLD.PRO`
  - DAX40 -> `DE30.PRO`
  - US500 -> `US500.PRO`
- `target_missing`: puste (brak brakujacych)

### Test 3 - Regresja kontraktow (3.12)
- Komenda:
  - `py -3.12 -m unittest tests.test_symbol_aliases_oanda_mt5_pl tests.test_oanda_limits_integration tests.test_contract_run_v2 -v`
- Wynik: PASS
- Dowod:
  - `EVIDENCE/broker_compat_3tests/manual_20260218T090842Z/test3_cmd_err.log`
- Podsumowanie:
  - `Ran 24 tests in 0.143s`
  - `OK`

## Co zostalo poprawione technicznie

1. Dodany wariant push przez PAT (bez promptu i bez stalego zapisu tokena):
- `TOOLS/GIT_PUSH_WITH_PAT.ps1`
- usuwa wadliwe proxy (`127.0.0.1:9`) z sesji i wymusza `openssl` backend dla git.

2. Dodany pakiet 3 audytow brokerskich:
- `TOOLS/BROKER_COMPAT_3TESTS.ps1`
- testuje 3.12/3.14 + instrumenty serwerowe + lokalna regresje kontraktow.

3. Naprawiony blad uruchamiania przy sciezkach i argumentach:
- wyeliminowane wywolania oparte o parsowanie `-Command` dla dlugich polecen,
- usuniety konflikt z automatyczna zmienna PowerShell `$args`.

## Dlaczego wygladalo to jak "zawieszanie"

To nie bylo faktyczne zawieszenie procesu tradingowego, tylko problem warstwy uruchamiania:

1) Bledne przekazywanie argumentow (szczegolnie sciezek ze spacjami)
- Objaw: `unrecognized arguments: Files\OANDA ...`
- Efekt: test odpalal sie zlym argumentem, czasem czekal na zakonczenie procesu bez sensownego postepu.

2) Uruchamianie dlugiego kroku jako jedna komenda bez etapowego polling
- Efekt: terminal narzedzia zwraca wynik dopiero po zakonczeniu kroku.
- Dla operatora wyglada to jak brak odpowiedzi.

3) Wczesniej aktywne lokalne proxy 127.0.0.1:9
- Efekt: bledy sieci git (nie broker), co dodatkowo mylilo diagnoze.

## Stan koncowy audytu wersji
- Rekomendacja runtime ONLINE dla OANDA MT5: **Python 3.12**
- Python 3.14: tylko pomocniczo/offline, dopoki nie bedzie pelnej kompatybilnosci pakietu `MetaTrader5` w tym srodowisku.

## Zrodla zewnetrzne (kontrola wersji)
- MetaTrader5 na PyPI: https://pypi.org/project/MetaTrader5/
- Dokumentacja API Python MT5 (MQL5): https://www.mql5.com/en/docs/python_metatrader5
- OANDA REST V20 API docs (referencja brokerska): https://developer.oanda.com/rest-live-v20/introduction/
