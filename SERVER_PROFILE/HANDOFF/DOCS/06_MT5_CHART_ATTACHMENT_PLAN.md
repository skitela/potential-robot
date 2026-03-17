# MT5 Chart Attachment Plan

Ten dokument jest generowany z `CONFIG/microbots_registry.json`.

Opisuje operacyjny plan przypięcia mikro-botów do wykresów `MT5`:

- `1 wykres = 1 symbol = 1 mikro-bot`
- `Core` nie jest przypinany jako osobny EA
- operator przeciąga tylko konkretne `MicroBot_*.ex5` na właściwe wykresy

Do odświeżenia planu użyj:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\MAKRO_I_MIKRO_BOT\TOOLS\GENERATE_MT5_CHART_PLAN.ps1
```
