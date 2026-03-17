# 44 Family Tuning Agent V1

## Cel

`v1` agenta rodzinnego porzadkuje wspolne wnioski dla calej rodziny symboli:
- `FX_MAIN`
- `FX_ASIA`
- `FX_CROSS`

To nie jest centralny dyktator rynku.
To warstwa, ktora:
- czyta stan lokalnych botow
- patrzy na ich wspolne problemy
- buduje rodzinne granice i sugestie

## Co czyta

Agent rodzinny korzysta z lokalnych danych symboli:
- `runtime_state.csv`
- `tuning_policy.csv`, jesli symbol ma juz lokalnego kapitana strojenia

## Co rozumie

Patrzy na:
- laczna liczbe probek w rodzinie
- serie strat
- dominujace reżimy typu `CHAOS`
- presje zlego spreadu
- dominacje toksycznych zachowan `BREAKOUT` albo `TREND`
- obecne ograniczenia ryzyka i confidence z agentow lokalnych

## Co wypluwa

Buduje polityke rodzinna:
- `dominant_confidence_cap`
- `dominant_risk_cap`
- `breakout_family_tax`
- `trend_family_tax`
- `rejection_range_boost`
- `freeze_new_changes`

## Czego nie robi

- nie zmienia kodu strategii
- nie handluje
- nie zastępuje lokalnego genotypu symbolu
- nie wymusza identycznych ustawien na wszystkich

## Rola wobec genotypu

Rodzina widzi tylko to, co wspolne.

Nie wolno jej:
- zrobic z `USDJPY` drugiego `EURUSD`
- zrobic z crossa AUD glownej pary dolarowej

Rodzina ma przekazywac tylko to, co jest naprawde rodzinne:
- wspolny stres spreadowy
- wspolna slabosc breakoutu
- wspolny problem chaosu
- wspolna potrzebe schlodzenia ryzyka

## Plik kodu

- [MbTuningFamilyAgent.mqh](C:\MAKRO_I_MIKRO_BOT\MQL5\Include\Core\MbTuningFamilyAgent.mqh)
