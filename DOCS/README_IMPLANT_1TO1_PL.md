# Patch 1:1 dla `C:\MAKRO_I_MIKRO_BOT`

To nie jest nowy, równoległy projekt ML.  
To jest **repo-overlay**, który ma zostać wklejony do istniejącego repo i używać tych samych nazw, ścieżek, raportów i artefaktów, które już żyją w systemie.

## Co ta paczka robi

1. Buduje **adapter zgodności danych** zamiast wymyślać nowy kontrakt.
2. Buduje **ledger broker-net PLN** z istniejących źródeł.
3. Trenuje:
   - globalny `paper_gate_acceptor`,
   - lokalne `paper_gate_acceptor_by_symbol\<SYMBOL>`,
   - lokalne modele `edge/fill/slippage`.
4. Zostawia artefakty i raporty w nazwach zgodnych z obecnym systemem.
5. Uzupełnia audyty w `EVIDENCE\OPS\...`.

## Najważniejsze ścieżki, które są zachowane

### Repo
- `C:\MAKRO_I_MIKRO_BOT\TOOLS`
- `C:\MAKRO_I_MIKRO_BOT\RUN`
- `C:\MAKRO_I_MIKRO_BOT\MQL5`

### Dane research
- `C:\TRADING_DATA\RESEARCH\datasets\contracts\candidate_signals_norm_latest.parquet`
- `C:\TRADING_DATA\RESEARCH\datasets\contracts\onnx_observations_norm_latest.parquet`
- `C:\TRADING_DATA\RESEARCH\datasets\contracts\learning_observations_v2_norm_latest.parquet`
- `C:\TRADING_DATA\RESEARCH\datasets\qdm_minute_bars_latest.parquet`

### Stan MT5 / Common Files
- `...\MAKRO_I_MIKRO_BOT\state\<SYMBOL>\broker_profile.json`
- `...\MAKRO_I_MIKRO_BOT\state\_global\execution_ping_contract.csv`
- opcjonalnie: `paper_live_feedback_latest.json`

### Modele
- `C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_latest.joblib`
- `C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_latest.onnx`
- `C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor_by_symbol\<SYMBOL>\...`

## Co wkleić do repo

- cały katalog `TOOLS\mb_ml_core\`
- pliki:
  - `TOOLS\BUILD_SERVER_PARITY_TAIL_BRIDGE.py`
  - `TOOLS\BUILD_BROKER_NET_LEDGER.py`
  - `TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py`
  - `TOOLS\EXPORT_MT5_RESEARCH_DATA.py`
- wrappery:
  - `RUN\BUILD_SERVER_PARITY_TAIL_BRIDGE.ps1`
  - `RUN\BUILD_BROKER_NET_LEDGER.ps1`
  - `RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1`
  - `RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODELS_PER_SYMBOL.ps1`
- nagłówki:
  - `MQL5\Include\Core\MbExecutionSnapshot.mqh`
  - `MQL5\Include\Core\MbBrokerNetLedger.mqh`
  - `MQL5\Include\Core\MbStudentDecisionGate.mqh`
  - `MQL5\Include\Core\MbMlFeatureContract.mqh`

## Kolejność uruchomienia

### 1. Zbuduj most ogona serwerowego
```powershell
pwsh .\RUN\BUILD_SERVER_PARITY_TAIL_BRIDGE.ps1
```

### 2. Zbuduj ledger broker-net
```powershell
pwsh .\RUN\BUILD_BROKER_NET_LEDGER.ps1
```

### 3. Trening globalny
```powershell
pwsh .\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1 -ExportOnnx
```

### 4. Trening globalny + lokalni uczniowie
```powershell
pwsh .\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1 -WithLocalStudents -ExportOnnx
```

### 5. Tylko lokalne modele per symbol
```powershell
pwsh .\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODELS_PER_SYMBOL.ps1 -ExportOnnx
```

## Co jest ważne operacyjnie

- **nie oczekujemy `outcomes.parquet`**
- **nie utrzymujemy ręcznej listy 7 symboli**
- **symbole aktywne są czytane z `CONFIG\microbots_registry.json`**
- **teacher_global_score** jest liczony **OOF** na walk-forward splitach
- lokalne modele nie uczą się z `net_pln` jako cechy
- promotion gate jest formalny, a nie uznaniowy

## Czego ta paczka świadomie nie robi

- nie tworzy nowego świata danych obok repo
- nie podmienia istniejących supervisorów
- nie wprowadza DeepLOB / RL tylko po to, żeby wyglądało nowocześnie

## Uczciwa uwaga

Patch jest gotowy do **wklejenia 1:1 do repo** i do uruchomienia na prawdziwych danych, ale:
- nie zna Twoich prywatnych niestandardowych kolumn spoza opisanych kontraktów,
- nie zmienia istniejących Expert Advisorów za Ciebie,
- nie gwarantuje eksportu ONNX, jeżeli w środowisku nie ma `skl2onnx` i konwerterów.
