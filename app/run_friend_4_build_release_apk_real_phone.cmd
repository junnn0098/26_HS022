@echo off
setlocal
cd /d "%~dp0"

set SERVER_URL=http://172.20.10.2:8000
set OUT_DIR=%~dp0release_apk
set OUT_APK=%OUT_DIR%\hanium_guardian_realphone_172.20.10.2.apk

echo.
echo ==================================================
echo  Hanium release APK build - real phone
echo ==================================================
echo.
echo This builds a release APK for the friend's presentation network.
echo Server URL embedded in APK:
echo   %SERVER_URL%
echo.
echo If the friend's Wi-Fi IPv4 changes, edit SERVER_URL in this file first.
echo.

flutter clean
if errorlevel 1 (
  pause
  exit /b 1
)

flutter pub get
if errorlevel 1 (
  pause
  exit /b 1
)

flutter build apk --release --dart-define=SERVER_URL=%SERVER_URL% --dart-define=DEMO_MODE=false
if errorlevel 1 (
  pause
  exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
copy /Y "%~dp0build\app\outputs\flutter-apk\app-release.apk" "%OUT_APK%"

echo.
echo Release APK created:
echo   %OUT_APK%
echo.
pause
