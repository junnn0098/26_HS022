@echo off
setlocal

set PORT=8000
set FRIEND_PC_IP=172.20.10.2

echo.
echo ==================================================
echo  Hanium server connection check
echo ==================================================
echo.
echo Checking local server...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-RestMethod http://127.0.0.1:%PORT%/health | ConvertTo-Json -Depth 5 } catch { Write-Host 'FAILED: local server is not reachable'; exit 1 }"
if errorlevel 1 (
  pause
  exit /b 1
)

echo.
echo Checking LAN address...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-RestMethod http://%FRIEND_PC_IP%:%PORT%/health | ConvertTo-Json -Depth 5 } catch { Write-Host 'WARNING: LAN address is not reachable. Real phone may fail. Emulator can still use 10.0.2.2.' }"

echo.
echo Done.
pause
