@echo off
setlocal
set SCRIPT=%~dp0RUN\OPEN_GPT54_PRO_BRIDGE_PANEL.ps1

if not exist "%SCRIPT%" (
  echo Missing panel script: %SCRIPT%
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%SCRIPT%"
endlocal