# DEV Environment Setup (VS Code, Windows 11)

## Scope
- Developer tooling only.
- No strategy/risk/entry/exit logic changes.
- No secrets in repo settings files.

## Files configured
- `.vscode/extensions.json`
- `.vscode/settings.json`
- `.vscode/tasks.json`
- `pyproject.toml` (Ruff format section)
- `TOOLS/DEV_SETUP_VSCODE.ps1`

## VS Code tasks
- `dev:py_compile`
- `dev:smoke_import`
- `dev:gate_placeholder`
- `dev:diag_placeholder`

## Manual steps (if needed)
1. Install PowerShell 7 (optional but recommended):
```powershell
winget install --id Microsoft.PowerShell --exact --source winget
```
2. Install VS Code CLI integration (if `code` not in PATH):
- VS Code -> Command Palette -> `Shell Command: Install 'code' command in PATH`

3. Install recommended extensions automatically:
```powershell
powershell -ExecutionPolicy Bypass -File TOOLS\DEV_SETUP_VSCODE.ps1 -Root C:\OANDA_MT5_SYSTEM -InstallExtensions
```

## Quick validation
```powershell
python -m py_compile BIN/safetybot.py TOOLS/gate.py TOOLS/no_live_drift_check.py
python -m unittest tests.test_symbol_aliases_oanda_mt5_pl -v
python TOOLS/gate.py --mode dev
cmd /c RUN_MT5_FULL_DIAGNOSTIC.bat
```
