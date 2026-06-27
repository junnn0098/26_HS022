@echo off
setlocal
cd /d "%~dp0"

REM 실제 안드로이드 폰으로 테스트할 때만 사용하세요.
REM 아래 IP를 발표 노트북의 Wi-Fi IPv4 주소로 바꿔야 합니다.
REM 예: set SERVER_URL=http://192.168.0.15:8000
set SERVER_URL=http://YOUR_PC_WIFI_IP:8000

echo.
echo [Hanium] 실제폰용 앱 실행 예시입니다.
echo [Hanium] 먼저 이 파일의 YOUR_PC_WIFI_IP를 노트북 IPv4 주소로 바꿔 주세요.
echo [Hanium] 현재 설정된 서버 주소: %SERVER_URL%
echo [Hanium] 발표 모드: 꺼짐
echo.
flutter run --dart-define=SERVER_URL=%SERVER_URL% --dart-define=DEMO_MODE=false
if errorlevel 1 pause
