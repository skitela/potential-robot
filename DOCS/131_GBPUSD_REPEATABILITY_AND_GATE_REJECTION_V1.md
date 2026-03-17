# GBPUSD Repeatability And Gate Rejection V1

## Co sprawdziliśmy
- pierwszy batch baseline dla `GBPUSD`
- wąską blokadę `BREAKOUT / CHAOS / LOW / BAD spread / candle != GOOD`
- repeatability między baseline i kolejnym runem

## Wynik eksperymentu
- samo `netto` wyglądało lepiej
- ale próbka spadła zbyt mocno
- `pnl per sample` praktycznie się nie poprawił
- repeatability check oznaczył parę jako `UNSTABLE`

## Decyzja
- nie akceptować tej blokady jako trwałej poprawki kodu
- nie stroić dalej `GBPUSD` tak, jakby baseline był już stabilny
- najpierw pilnować powtarzalności runów

## Znaczenie
- to nie jest porażka
- to jest ważny bezpiecznik jakości
- system ma teraz lepszą ochronę przed fałszywą poprawą wynikającą tylko z obcięcia aktywności
