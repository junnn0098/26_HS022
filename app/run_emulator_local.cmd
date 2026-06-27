@echo off
setlocal
cd /d "%~dp0"
echo.
echo [Hanium] 에뮬레이터용 발표 모드 앱을 실행합니다.
echo [Hanium] 서버 주소: http://10.0.2.2:8000
echo [Hanium] 발표 모드: 켜짐
echo.
flutter run -d emulator-5554 --dart-define=SERVER_URL=http://10.0.2.2:8000 --dart-define=DEMO_MODE=true
if errorlevel 1 pause
