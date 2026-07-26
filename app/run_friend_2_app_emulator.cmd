@echo off
setlocal
cd /d "%~dp0"

set SERVER_URL=http://10.0.2.2:8000

echo.
echo ==================================================
echo  Hanium app - Android emulator mode
echo ==================================================
echo.
echo Use this when the app runs on the emulator on the same PC.
echo Server URL for Android emulator:
echo   %SERVER_URL%
echo.
echo Make sure run_friend_1_server.cmd is already running.
echo.

flutter run -d emulator-5554 --dart-define=SERVER_URL=%SERVER_URL% --dart-define=DEMO_MODE=false
if errorlevel 1 pause

