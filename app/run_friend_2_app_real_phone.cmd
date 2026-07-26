@echo off
setlocal
cd /d "%~dp0"

set SERVER_URL=http://172.20.10.2:8000

echo.
echo ==================================================
echo  Hanium app - real Android phone mode
echo ==================================================
echo.
echo Use this when the app runs on a real Android phone.
echo The phone and this PC must be on the same Wi-Fi/hotspot network.
echo Server URL:
echo   %SERVER_URL%
echo.
echo Make sure run_friend_1_server.cmd is already running.
echo.

flutter run --dart-define=SERVER_URL=%SERVER_URL% --dart-define=DEMO_MODE=false
if errorlevel 1 pause
