@echo off
setlocal
if "%NODE%"=="" set NODE=node
if "%PORT%"=="" set PORT=8000
cd /d "%~dp0"
echo.
echo Hanium mock server starting...
echo Admin page: http://127.0.0.1:%PORT%/admin
echo Android emulator app URL: http://10.0.2.2:%PORT%
echo.
"%NODE%" "%~dp0dev_mock_server.js"
if errorlevel 1 (
  echo.
  echo Hanium mock server failed. Please check the error above.
  pause
)
