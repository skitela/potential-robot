# Counterfactual Tuning Analyzer

## Cel

To narzedzie robi offline analize kontrfaktyczna na danych `learning_observations_v2.csv`.

Nie probuje udawac, ze mozna zamienic kazda strate w wygrana.
Szuka zamiast tego:

- ktore klasy wejsc byly najbardziej toksyczne,
- jakie filtry blokujace dalyby najwieksza poprawe,
- gdzie lepiej blokowac, a gdzie raczej sciskac ryzyko.

## Zakres V1

V1 czyta dane lokalne dla rodziny i buduje kandydatow na reguly typu:

- blokuj `setup`,
- blokuj `setup` w `market_regime`,
- podnies confidence gate,
- wymagaj wsparcia kierunkowego,
- nie wpuszczaj przy slabym `candle` albo `Renko`,
- rozpatrz polowe ryzyka zamiast twardego bloku.

## Uczciwe ograniczenie

To jest analiza weekendowa i retrospektywna:

- nie dowodzi przyszlej przewagi,
- nie zastępuje forward paper,
- nie daje prawa do wdrozenia wielu zmian naraz.

## Uzycie

Przyklad:

```powershell
python C:\MAKRO_I_MIKRO_BOT\TOOLS\ANALYZE_COUNTERFACTUAL_TUNING.py --family FX_MAIN
```

## Wynik

Narzędzie zapisuje:

- raport `json` w `EVIDENCE`
- raport `md` w `EVIDENCE`

Raport ma sluzyc jako baza pod:

- weekendowe przygotowanie hipotez,
- kolejnosc zmian po otwarciu rynku,
- oddzielenie filtrow twardych od filtrow typu `risk squeeze`.
