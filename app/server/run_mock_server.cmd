@echo off
if "%PY%"=="" set PY=python
cd /d "%~dp0"
"%PY%" "%~dp0dev_mock_server.py" > "%~dp0server.out.log" 2> "%~dp0server.err.log"
