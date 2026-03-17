# 119 Strategy Tester Human In Loop Contract V1

## Zasada nadrzedna

Tester strategii jest laboratorium i dostawca dowodow.
Nie jest autonomicznym stroicielem kodu.

## Co robi automat

- uruchamia test,
- resetuje sandbox,
- zbiera logi i artefakty,
- przygotowuje podsumowanie,
- porownuje dwa przebiegi,
- oznacza poprawy, pogorszenia i wyniki niejednoznaczne.

## Czego automat nie robi

- nie przepisuje kodu strategii,
- nie zmienia architektury,
- nie wdraza sam zmian do botow,
- nie podejmuje sam decyzji o akceptacji logiki.

## Co robi operator / inzynier

- analizuje wynik testu,
- odroznia prawdziwa poprawe od zludzenia,
- wprowadza zmiany w kodzie,
- usuwa negatywne zmiany,
- zostawia tylko zmiany z jasnym dowodem.

## Kontrakt pracy

1. test
2. raport
3. interpretacja czlowieka
4. zmiana kodu
5. kolejny test

## Cel

Zachowac czyste srodowisko rozwojowe i korzystac z testera jako narzedzia wspierajacego, a nie zrodla samodzielnych zmian.
