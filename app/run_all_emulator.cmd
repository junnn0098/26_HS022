@echo off
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_all_emulator.ps1"
if errorlevel 1 (
  echo.
  echo Hanium app launcher failed. Please check the message above.
  pause
)
