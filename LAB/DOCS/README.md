# OANDA MT5 LAB (Offline)

Ten katalog to odseparowane laboratorium analityczne dla OANDA_MT5_SYSTEM.

## Cel
- Maksymalizacja wyniku netto po kosztach (`net after costs`) dla scalpingu.
- Uczenie na danych historycznych i persisted runtime.
- Zero ingerencji w live execution path.

## Zasady
- LAB nie wysyla zlecen i nie modyfikuje `CONFIG/strategy.json`.
- Parametry ryzyka kapitalowego sa nienaruszalne bez decyzji operatora.
- Wynik LAB to rekomendacje (ranking + bramka LAB->SHADOW), nie automatyczna aktywacja.

## Start (FX phase)
1. Uruchom pipeline:
   - `python -B TOOLS/lab_daily_pipeline.py --root C:\OANDA_MT5_SYSTEM --focus-group FX --lookback-days 30 --daily-guard`
2. Odczytaj raport:
   - `LAB/EVIDENCE/daily/lab_daily_report_latest.json`
   - `LAB/EVIDENCE/daily/lab_daily_report_latest.txt`

## Konfiguracja
- `LAB/CONFIG/lab_config.json`
  - cel i wagi rankingu,
  - progi promocji LAB->SHADOW,
  - statusy connectorow zewnetrznych (domyslnie OFF/PLANNED).

## Uwaga operacyjna
- Pipeline korzysta z raportu bazowego strict/explore (`TOOLS/shadow_policy_daily_report.py`).
- Obciazenie runtime jest niskie, ale zalecane uruchamianie poza najbardziej aktywnym oknem.
