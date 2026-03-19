# 146 MicroBot ML Offline First Model V1

## Cel
- wdrozyc pierwszy praktyczny model ML offline do naszego systemu
- nie ruszac runtime `MQL5`
- wytrenowac model pomocniczy dla `candidate -> paper gate`
- zapisac artefakt w `ONNX` pod przyszla integracje

## Zakres
- [TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py](C:\MAKRO_I_MIKRO_BOT\TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py)
- [TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1)
- [TRAIN_MICROBOT_ML_STACK.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_MICROBOT_ML_STACK.ps1)
- [REFRESH_AND_TRAIN_MICROBOT_ML.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\REFRESH_AND_TRAIN_MICROBOT_ML.ps1)
- [START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1](C:\MAKRO_I_MIKRO_BOT\RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1)

## Co robi model
- bierze dane z `candidate_signals`
- uczy sie dla etapu `EVALUATED`
- target:
  - `accepted=1` oznacza przejscie do `PAPER_SCORE_GATE`
  - `accepted=0` oznacza zatrzymanie glownie na `SCORE_BELOW_TRIGGER`

## Po co ten model
- to nie jest nowy silnik strategii
- to jest model pomocniczy do oceny jakosci kandydata
- daje nam:
  - ranking prawdopodobienstwa przejscia przez paper gate
  - material do dalszej analizy agentow strojenia
  - pierwszy artefakt `ONNX`, ktory potem mozna walidowac w `MT5`

## Artefakty
Domyslny katalog wynikow:
- `C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor`

Powstaja tam:
- `paper_gate_acceptor_latest.joblib`
- `paper_gate_acceptor_latest.onnx`
- `paper_gate_acceptor_metrics_latest.json`
- `paper_gate_acceptor_report_latest.md`

## Automatyzacja
- `TRAIN_MICROBOT_ML_STACK.ps1` trenuje caly aktualny stos modeli ML
- `REFRESH_AND_TRAIN_MICROBOT_ML.ps1` robi:
  - odswiezenie magazynu research z MT5
  - trening modelu pomocniczego
- `START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1` uruchamia ten sam tor w tle z logiem

## Granica architektoniczna
- model jest offline
- nie steruje live execution
- nie siedzi jeszcze w mikrobotach
- najpierw ma przejsc:
  - trening
  - raport
  - walidacje
  - dopiero potem ewentualna integracje z `MQL5`
