# RANKING BENCHMARK METODYKA V1

## Cel

Ten dokument utrwala stala metode porownywania:
- systemu OANDA_MT5_SYSTEM,
- 6 rozwiazan polprofesjonalnych,
- 6 rozwiazan profesjonalnych.

Metoda ma byc powtarzalna, z tymi samymi kryteriami i tymi samymi wagami.

## Skala i progi

- skala: 0-100
- segment TOP (gorny): >= 80
- segment SRODEK: 65-79.9
- segment NISKI: < 65

## 10 kryteriow i wagi

1. Ochrona kapitalu i kontrola ryzyka - 18%
2. Odpornosc operacyjna (awarie, recovery, watchdog) - 14%
3. Jakosc egzekucji i kontrola zlecen - 12%
4. Monitoring, logi, diagnostyka - 10%
5. Dane rynkowe (jakosc, realtime, pokrycie) - 10%
6. API i automatyzacja - 10%
7. Skalowalnosc i architektura - 8%
8. Compliance i audit trail - 8%
9. Trening, backtest, anty-przeuczenie - 6%
10. Gotowosc operacyjna (runbook, smoke, checklisty) - 4%

Suma wag = 100%.

## Wzor liczenia

Dla kazdego systemu:

score_100 = sum(ocena_kryterium_0_10 * waga_kryterium) / 10

Gdzie:
- ocena_kryterium_0_10 to punktacja 0..10 dla danego kryterium,
- waga_kryterium to procent (np. 18, 14, 12...),
- dzielenie przez 10 zamienia wynik na skale 0..100.

## Jak oceniac uczciwie

1. Dla naszego systemu:
- opierac sie na twardych artefaktach lokalnych (prelive, gate, smoke, stress, testy).

2. Dla systemow zewnetrznych:
- opierac sie na oficjalnej dokumentacji producenta i oficjalnych stronach produktu/API.

3. Nie mieszac marketingu z dowodem:
- jesli brak dowodu na dana funkcje, nie dawac maksymalnych punktow.

4. Przed kazdym kolejnym rankingiem:
- sprawdzic aktualne wersje i daty dokumentacji,
- odswiezyc tylko zrodla oficjalne.

## Stala lista porownawcza (12 rozwiazan)

Polprofesjonalne:
- MetaTrader 5
- cTrader Automate/Open API
- NinjaTrader 8
- TradeStation
- QuantConnect LEAN
- IBKR API

Profesjonalne:
- Bloomberg EMSX/Execution Management
- FlexTrade
- Fidessa (ION)
- Trading Technologies (TT)
- Saxo OpenAPI (PRO)
- LMAX Exchange API

## Artefakty wyjscia (za kazdym razem)

1. Raport opisowy `.md`:
- wynik naszego systemu,
- tabela 6 + 6,
- srednie i mediany grup,
- roznice (gap) do semi/pro,
- GO/NO-GO dla live.

2. Raport maszynowy `.json`:
- wagi,
- wyniki,
- statystyki grup,
- gapy.

## Aktualizacja metodologii

Jesli kiedys zmieniamy kryteria lub wagi:
- zwiekszyc wersje dokumentu (V2, V3...),
- trzymac porownania historyczne osobno,
- nie mieszac starych i nowych wag w jednej serii rankingow.

## Staly launcher (w obu repo)

Ta sama metodyka jest przypieta do:
- `SCHEMAS/ranking_benchmark_metodyka_v1.json`
- `TOOLS/ranking_benchmark_v1.py`
- `RUN/RANKING_BENCHMARK_V1.ps1`

Jednolita komenda:
- `python -B TOOLS/ranking_benchmark_v1.py`

Tryb uruchomienia:
- z OANDA_MT5_SYSTEM: domyslnie ocenia GH V1 (`C:\GLOBALNY HANDEL VER1`) jesli istnieje,
- z GH_V1: domyslnie ocenia biezacy root GH_V1.

Wymuszenie targetu:
- `python -B TOOLS/ranking_benchmark_v1.py --target-root "C:\GLOBALNY HANDEL VER1"`
