@echo off
set PY=C:\Users\juhwan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe
cd /d "%~dp0"
"%PY%" "%~dp0dev_mock_server.py" > "%~dp0server.out.log" 2> "%~dp0server.err.log"
