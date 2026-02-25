# Checklist Klik-Po-Kliku: odblokowanie `trade_allowed` i `Algo Trading` (MT5)

Cel: usunąć stan, w którym zlecenia są odrzucane (`retcode=10017`, `trade_allowed=False`), a potem uruchomić automatyczny test wejść.

## 1) Logowanie właściwym hasłem (MASTER)
1. W MT5 kliknij `Plik` -> `Zaloguj się do rachunku handlowego`.
2. Wpisz:
   - Login: numer konta.
   - Hasło: **hasło główne (MASTER)**, nie inwestorskie.
   - Serwer: `OANDATMS-MT5` (lub dokładnie ten, który podał broker).
3. Kliknij `OK`.

## 2) Globalne ustawienia algo i DLL
1. Kliknij `Narzędzia` -> `Opcje` -> zakładka `Strategie`.
2. Zaznacz:
   - `Zezwalaj na handel algorytmiczny`.
   - `Zezwalaj na import DLL`.
3. Odznacz:
   - `Wyłącz handel algorytmiczny po zmianie rachunku`.
   - `Wyłącz handel algorytmiczny po zmianie profilu`.
   - `Wyłącz handel algorytmiczny po zmianie symbolu lub okresu wykresów`.
4. Kliknij `OK`.

## 3) Przycisk Algo Trading na pasku głównym
1. Na górnym pasku MT5 włącz `Algo Trading` (ma być aktywny/na zielono).

## 4) Ustawienia EA na wykresie
Powtórz dla każdego wykresu z `HybridAgent`:
1. Kliknij prawym na wykresie -> `Eksperci` -> `Właściwości`.
2. Zakładka `Ogólne`:
   - `Zezwalaj na handel algorytmiczny` = zaznaczone.
   - `Zezwalaj na import DLL` = zaznaczone.
3. Kliknij `OK`.

## 5) Okno ryzyka (jeśli wyskoczy)
1. Jeśli pojawi się okno ostrzeżenia o ryzyku, kliknij akceptację (`OK`/`Accept`).
2. To musi zostać zaakceptowane, inaczej broker/terminal może blokować wysyłkę zleceń.

## 6) Automatyczny retest po odblokowaniu
1. Uruchom w repo:
   - `RUN_POST_UNLOCK_ENTRY_TEST.bat`
2. Skrypt:
   - ustawi i sprawdzi MT5,
   - uruchomi diagnostykę,
   - odpali test wejść i zapisze raport.
3. Raport końcowy będzie w:
   - `RUN/DIAG_REPORTS/POST_UNLOCK_ENTRY_TEST_*.txt`
   - `RUN/DIAG_REPORTS/POST_UNLOCK_ENTRY_TEST_*.json`

## 7) Kryterium sukcesu
- Sukces techniczny odblokowania:
  - diagnostyka nie pokazuje `trade_allowed=False`.
- Sukces tradingowy:
  - w raporcie testu pojawia się co najmniej jedna skuteczna realizacja (`order_success > 0`).
