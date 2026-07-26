@echo off
setlocal
cd /d "%~dp0"

set PORT=8000
set FRIEND_PC_IP=172.20.10.2

echo.
echo ==================================================
echo  Hanium presentation server
echo ==================================================
echo.
echo 1. This starts the local mock server.
echo 2. Keep this window open during the presentation.
echo.
echo Admin page on this PC:
echo   http://127.0.0.1:%PORT%/admin
echo.
echo Admin page from another device on the same network:
echo   http://%FRIEND_PC_IP%:%PORT%/admin
echo.

start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Sleep -Seconds 3; Start-Process 'http://127.0.0.1:%PORT%/admin'"
call "%~dp0server\run_mock_server_node.cmd"
