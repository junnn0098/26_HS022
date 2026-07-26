@echo off
setlocal
cd /d "%~dp0"

if "%SERVER_URL%"=="" set SERVER_URL=http://127.0.0.1:8000

echo.
echo ==================================================
echo  Hanium Jetson edge mock client
echo ==================================================
echo.
echo Server URL:
echo   %SERVER_URL%
echo.
echo This sends a demo sequence to /sensor/update:
echo normal - moving - entrance - stillness - fall suspicion
echo.

python jetson_edge_client.py sequence --server-url %SERVER_URL% --loop
if errorlevel 1 pause

