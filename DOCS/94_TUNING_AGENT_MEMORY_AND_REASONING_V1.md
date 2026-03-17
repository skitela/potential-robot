# Pamiec i sciezka myslenia agentow strojenia

Data: 2026-03-16

## Problem
- agent strojenia umial juz regulowac polityke, ale jego pamiec byla zbyt plaska
- wiedzial:
  - jaki ma trust reason
  - jaka byla ostatnia akcja
  - jaki ma cooldown
- ale nie trzymal jeszcze wyraznie:
  - na czym teraz skupia uwage
  - jaka jest jego robocza hipoteza
  - co by sie stalo, gdyby nic nie zmienial
  - ile cykli z rzedu tkwil w tym samym blokadzie

## Co zostalo dodane
- do polityki lokalnej agenta dodano pamiec:
  - `reason_streak`
  - `action_streak`
  - `blocked_cycles`
  - `trusted_cycles`
  - `last_focus_setup_type`
  - `last_focus_market_regime`
  - `last_hypothesis_code`
  - `last_hypothesis_detail`
  - `last_counterfactual_code`
  - `last_counterfactual_detail`
- deckhand zaczal wypelniac te pola juz na etapie oceny czystosci danych
- lokalny agent strojenia zaczal dopisywac:
  - glowny obszar bolu
  - robocza hipoteze strojenia
  - kontrfaktyczna przestroge: co by bylo, gdyby zostawic wszystko bez zmian

## Co to daje
- agent nie tylko wie, czy ufa danym, ale tez pamieta dlaczego
- agent nie tylko reguluje podatki, ale wie na czym aktualnie pracuje
- mozna teraz odczytac jego tok rozumowania bez zgadywania z samych liczb
- przy uporczywej blokadzie papierowej agent nie wraca slepo do tego samego punktu, tylko niesie pamiec o:
  - ilu cyklach blokady
  - jaka byla hipoteza naprawcza
  - jaki byl spodziewany koszt braku zmiany

## Nowy slad operacyjny
- dodano osobny dziennik `tuning_reasoning.csv`
- ten dziennik ma zbierac dwa typy myslenia:
  - `DECKHAND`
  - `LOCAL_AGENT`

## Uczciwy stan po wdrozeniu
- architektura pamieci i logowania jest juz w kodzie
- cala flota kompiluje sie poprawnie
- lokalny MT5 zostal odswiezony
- runtime potrzebuje jeszcze kolejnego pelnego cyklu strojenia, aby zostawic pierwszy nowy slad w `tuning_reasoning.csv`
