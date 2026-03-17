# 43 Tuning Agent Architecture V1

## Cel

Ten dokument porzadkuje docelowa architekture Agenta Strojenia dla `MAKRO_I_MIKRO_BOT`.

Budujemy warstwe, ktora:
- podnosi `zysk netto`
- chroni `kapital`
- nie pogarsza `latencji`
- nie narusza zasad brokera i runtime `MT5/OANDA`

## Poziom 1 - kapitan lokalny

Kazdy mikro-bot docelowo dostaje wlasnego kapitana strojenia.

Przyklad:
- `EURUSD` -> `MbTuningLocalAgent`
- pozniej analogicznie kolejne instrumenty

Kapitan lokalny:
- czyta lokalne buckety zwyciestw i porazek
- rozumie genotyp instrumentu
- zmienia tylko dozwolone parametry sterujace
- dziala sekwencyjnie: jedna mala zmiana, potem obserwacja
- nie przepisywuje kodu

Dozwolone lokalne decyzje:
- przyciecie `BREAKOUT`
- przyciecie `TREND`
- lekkie wzmocnienie `REJECTION`
- obnizenie `confidence_cap`
- obnizenie `risk_cap`
- wymog wsparcia `AUX`
- czasowe zamrozenie toksycznego zachowania
- rollback ostatniej lokalnej zmiany

## Poziom 1b - majtek techniczny

Majtek nie stroi strategii.
Majtek przygotowuje kapitanowi czyste dane.

Majtek:
- sprawdza swiezosc i spojnosc `learning_observations_v2.csv`
- wykrywa nadmiar `NONE/UNKNOWN`
- pilnuje zgodnosci obserwacji z bucketami
- odbudowuje `learning_bucket_summary_v1.csv`, gdy probka sie zmienila albo summary zniknelo
- oznacza poziom zaufania do danych

Majtek nie moze:
- zmieniac ryzyka sam z siebie
- interpretowac przewagi rynkowej
- modyfikowac strategii
- uruchamiac strojenia bez kapitana

## Poziom 2 - agent rodzinny

Docelowo kazda rodzina dostaje wlasnego agenta rodzinnego:
- `FX_MAIN`
- `FX_ASIA`
- `FX_CROSS`
- pozniej `METALS`
- pozniej `INDICES`

Agent rodzinny:
- szuka wzorcow wspolnych w rodzinie
- wykrywa rzeczy transferowalne miedzy instrumentami
- buduje rodzinne granice i sugestie
- nie nadpisuje lokalnego genotypu

Dozwolone rodzinne decyzje:
- ustawienie rodzinnych limitow dla toksycznych wzorcow
- lekkie rodzinne premie dla stabilnych bucketow
- rekomendacje dla agentow lokalnych
- wycofanie rodzinnej hipotezy, jesli przestaje dzialac

## Poziom 3 - koordynator strojenia

Koordynator nie handluje.
To mozg strojenia, nie mozg rynku.

Koordynator:
- pilnuje kolejnosci zmian
- pilnuje, zeby nie bylo zbyt wielu zmian naraz
- kontroluje rollback
- zatrzymuje strojenie, jesli rośnie ryzyko systemowe
- pilnuje zgodnosci z brokerem, hostem i polityka runtime

## Dane, z ktorych korzysta strojenie

Kapitan lokalny pracuje glownie na:
- `learning_observations_v2.csv`
- `learning_bucket_summary_v1.csv`
- `runtime_state.csv`
- `execution_summary.json`
- `informational_policy.json`
- `latency_profile.csv`
- `broker_profile.json`

W przyszlosci dokladamy:
- `tuning_actions.csv`
- `tuning_deckhand.csv`
- `tuning_evaluations.csv`
- `tuning_rollbacks.csv`

## Twarde zasady bezpieczenstwa

- zero przepisywania kodu w runtime
- zero strojenia w hot-path tickowym
- zero wielu zmian naraz
- zero strojenia bez minimalnej probki
- zero agresywnej eksploracji na `live`
- zawsze mozliwy rollback

## Dlaczego taka architektura

To nie jest przypadkowy pomysl.
Korzystamy z wnioskow z:
- praktyki strojenia `EURUSD` i kolejnych par w tym projekcie
- podejsc do bezpiecznego uczenia z ograniczeniami
- strojenia parametrow w czasie zamiast jednorazowego "idealnego zestawu"
- hierarchicznych ukladow agentowych

Najwazniejsze inspiracje z badan i dokumentacji:
- Population Based Training: https://arxiv.org/abs/1711.09846
- Ray Tune / PBT guide: https://docs.ray.io/en/latest/tune/examples/pbt_guide.html
- execution i komunikacja wieloagentowa w finansach: https://arxiv.org/abs/2307.03119

## Wdrozenie v1

Na teraz wdrazamy tylko warstwe lokalna dla `EURUSD`:
- kapitan lokalny
- majtek techniczny
- journale polityki i akcji

To daje nam wzorzec do przyszlego rozlania na kolejne mikro-boty bez niszczenia ich genotypu.
