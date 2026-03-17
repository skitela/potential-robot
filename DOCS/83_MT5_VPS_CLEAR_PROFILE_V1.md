# MT5 VPS Clear Profile V1

## Cel

Ten profil sluzy do bezpiecznego nadpisania starego snapshotu `MetaTrader VPS` profilem bez ekspertow.

## Zasada

- profil ma `1` wykres
- profil ma `0` ekspertow
- profil nie uruchamia zadnego mikro-bota
- po jego otwarciu lokalnie i wykonaniu synchronizacji do `MetaTrader VPS` zdalny snapshot przestaje nosic stare EA

## Co to rozwiazuje

- usuwa zdalny, starszy zestaw botow z `MetaTrader VPS`
- usuwa rozjazd miedzy lokalnym terminalem a starym snapshotem VPS
- zmniejsza ryzyko, ze stare paperowe EA beda dalej biegly na VPS bez potrzeby

## Ograniczenie

`MetaTrader VPS` od `MetaQuotes` nie jest zwyklym dyskiem sieciowym. Samo utworzenie profilu lokalnie nie czyści zdalnego snapshotu, dopoki operator nie wykona synchronizacji z `MT5` do `VPS`.

## Profil

- nazwa domyslna: `MAKRO_I_MIKRO_BOT_VPS_CLEAR`
- symbol bazowy: `EURUSD.pro`

## Narzedzia

- generator profilu:
  - `TOOLS/setup_mt5_safe_empty_profile.py`
- uruchomienie `MT5` z tym profilem:
  - `RUN/OPEN_OANDA_MT5_WITH_VPS_CLEAR_PROFILE.ps1`

## Oczekiwany efekt po synchronizacji do VPS

W panelu `MetaTrader VPS` dziennik powinien pokazac stan odpowiadajacy pustemu lub prawie pustemu profilowi, a nie staremu zestawowi `11 charts, 11 EAs`.
