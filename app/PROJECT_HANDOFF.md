# Hanium App 프로젝트 인수인계 문서

처음 프로젝트를 이어받는 사람이나 ChatGPT / Gemini / Codex 같은 AI에게 설명할 때는 먼저 `AI_ONBOARDING_HANDOFF.md`를 읽히는 것을 추천한다.  
`PROJECT_HANDOFF.md`는 현재 작업 상태를 더 자세히 정리한 개발 메모에 가깝고, `AI_ONBOARDING_HANDOFF.md`는 프로젝트를 처음 보는 사람도 바로 이해할 수 있게 만든 시작 문서다.

작성일: 2026-07-12  
목적: 다른 PC, 다른 Codex 세션, 발표 준비 환경에서도 현재 작업을 그대로 이어가기 위한 최신 정리 문서

---

## 1. 프로젝트 한 줄 요약

WiFi CSI 기반으로 실내 움직임과 낙상 징후를 감지하고, Flutter 앱에서 보호자/피보호자 역할에 따라 상태 확인, 위치 확인, 알림, 대응 흐름을 제공하는 스마트 주거 안전망 앱이다.

핵심 흐름:

```text
ESP32-S3 / WiFi CSI 수집
→ Jetson Orin Nano 추론
→ Node.js 로컬 서버
→ WebSocket / REST API
→ Flutter 앱
→ 보호자 확인 및 대응
```

---

## 2. 현재 앱에서 중요한 기능

### 2.1 역할 기반 앱 구조

하나의 앱에서 `보호자`와 `피보호자` 모드를 선택할 수 있다.

- 보호자 모드
  - 홈 요약
  - 집 안 상태
  - 안전 알림
  - 위험 대응
  - 설정
  - 보호자 화면에서 `피보호자 모드`로 바로 전환 가능

- 피보호자 모드
  - 내 상태 확인
  - 위치 공유 ON/OFF
  - 생활 리듬 / 생활 기록 확인
  - 피보호자 화면에서 보호자 모드로 바로 전환 가능

관련 파일:

```text
lib/app/hanium_app.dart
lib/core/models/app_role.dart
lib/features/auth/login_screen.dart
lib/features/shell/main_shell.dart
lib/features/care_recipient/care_recipient_screen.dart
```

최근 수정:

- 보호자 모드에도 `피보호자 모드` 전환 버튼 추가
- 피보호자 모드의 전환 버튼은 로그인으로 돌아가지 않고 바로 보호자 모드로 전환되도록 수정

---

## 3. 집 안 상태 / 3D 도면 관련

집 안 상태 화면은 `FloorPlanView`를 사용한다.

최근 수정:

- `집 안` 탭에서 3D/아이소메트릭 도면이 보이도록 기본 호출을 변경했다.

변경 위치:

```text
lib/features/home_map/home_map_screen.dart
```

현재 호출:

```dart
FloorPlanView(snapshot: snapshot, perspective3d: true)
```

도면 구현 파일:

```text
lib/features/home_map/floor_plan_view.dart
```

중요 포인트:

- 2D 도면과 3D/아이소메트릭 도면이 모두 코드에 있음
- `perspective3d: true`이면 3D 도면
- `perspective3d: false`이면 2D 도면
- 피보호자 모드의 작은 상세 지도는 아직 2D로 유지 중

---

## 4. 서버 실행 방법

서버는 앱 폴더 안의 `server` 폴더에서 실행한다.

1번 PowerShell 창:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
.\server\run_mock_server_node.cmd
```

관리자 페이지:

```text
http://127.0.0.1:8000/admin
```

주요 API:

```text
GET  /health
GET  /state
GET  /location/latest
POST /sensor/update
POST /sensor/reset
POST /scenario
WS   /ws/location
```

주의:

- `.\run_mock_server_node.cmd`는 앱 루트에는 없다.
- 정확한 실행 경로는 `.\server\run_mock_server_node.cmd`이다.

---

## 5. 앱 실행 방법

2번 PowerShell 창:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
flutter run -d emulator-5554
```

실행 중 단축키:

```text
r  Hot reload
R  Hot restart
q  종료
```

앱이 정상 실행되면 터미널에 아래 형태가 나온다.

```text
Built build\app\outputs\flutter-apk\app-debug.apk
Installing ...
Syncing files to device ...
A Dart VM Service ... is available
```

---

## 6. 에뮬레이터 문제 해결 기록

### 6.1 저장공간 부족

오류:

```text
INSTALL_FAILED_INSUFFICIENT_STORAGE
Requested internal only, but not enough space
```

원인:

```text
에뮬레이터 내부 저장공간 부족
```

1차 해결:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 uninstall com.example.hanium_app
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 shell pm trim-caches 4G
flutter run -d emulator-5554
```

반복되면 에뮬레이터 초기화가 필요하다.

Android Studio가 없는 경우:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 emu kill
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd AVD이름 -wipe-data
```

### 6.2 검은 화면

증상:

```text
Flutter는 실행됐는데 에뮬레이터 화면이 검은색
```

해결 순서:

```text
1. Flutter 터미널에서 q
2. 에뮬레이터 종료
3. 에뮬레이터 재시작
4. flutter run -d emulator-5554
```

그래도 안 되면:

```powershell
flutter run -d emulator-5554 --enable-software-rendering
```

---

## 7. 현재 코드 구조

현재는 과거 `lib/src/*` 중심 구조에서 기능별 폴더 구조로 분리된 상태다.

중요 구조:

```text
lib/
  app/
    hanium_app.dart
    app_theme.dart
  core/
    models/
      app_role.dart
      safety_models.dart
    services/
      notification_service.dart
      safety_repository.dart
    state/
      safety_controller.dart
  features/
    auth/
      login_screen.dart
    shell/
      main_shell.dart
    dashboard/
      dashboard_screen.dart
    home_map/
      home_map_screen.dart
      floor_plan_view.dart
    alerts/
      alerts_screen.dart
    care_recipient/
      care_recipient_screen.dart
    settings/
      settings_screen.dart
  shared/
    ui/
      app_ui.dart
```

Git 상태 기준으로는 기존 `lib/src/*` 파일들이 삭제되고, `lib/app`, `lib/core`, `lib/features`, `lib/shared`가 새로 추가된 상태일 수 있다. 새 환경에서 이어받을 때는 `git status`로 변경 상태를 먼저 확인할 것.

---

## 8. 현재 Git 상태 주의

2026-07-12 기준 작업 트리는 아직 완전히 커밋된 상태가 아닐 수 있다.

주요 변경/추가 가능 항목:

```text
.gitignore
lib/main.dart
lib/app/
lib/core/
lib/features/
lib/shared/
server/jetson_edge_client.py
server/JETSON_EDGE_CLIENT.md
run_friend_*.cmd
FRIEND_PRESENTATION_RUNBOOK.md
PRESENTATION_QUICK_START_172.20.10.2.md
PROJECT_HANDOFF.md
```

새 환경에서 작업 전 확인:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
git status --short
```

---

## 9. 보고서에 넣은 앱 파트 핵심 문장

### 9.1 주요 기능 3개

표에 넣을 앱 관련 주요 기능:

```text
보호자·피보호자 역할 기반 앱 UI/UX
하나의 앱에서 보호자 모드와 피보호자 모드를 선택할 수 있도록 구성하였다. 보호자는 상태 확인과 위험 대응 중심 화면을, 피보호자는 생활 상태와 위치 공유 관리 중심 화면을 제공받는다.
```

```text
집 도면 기반 디지털 트윈 및 이동 흐름 시각화
집 도면 위에 감지 위치, 사람 미니어처, 최근 이동 경로를 표시하여 현재 위치와 이동 흐름을 직관적으로 확인할 수 있도록 구현하였다.
```

```text
WebSocket 기반 실시간 알림 연동
서버와 앱을 WebSocket으로 연결하여 낙상 의심 등 상태 변화를 실시간 반영하고, 위험 발생 시 전화 연결 및 119 신고 정보로 이어지도록 구성하였다.
```

### 9.2 주요 적용 기술

압축 버전:

```text
3.1.6 역할 기반 모바일 앱 UI/UX 및 디지털 트윈

Flutter 기반 모바일 앱을 구현하여 하나의 앱에서 보호자 모드와 피보호자 모드를 선택할 수 있도록 구성하였다. 보호자 모드는 위험 상태 확인과 대응 중심으로, 피보호자 모드는 생활 상태 확인과 위치 공유 관리 중심으로 화면 흐름을 분리하였다. 또한 집 도면 기반 디지털 트윈 화면을 통해 감지 위치, 사람 미니어처, 최근 이동 경로를 시각화하여 보호자가 위험 발생 위치와 이동 흐름을 직관적으로 파악할 수 있도록 하였다.

- 보호자/피보호자 역할 기반 앱 화면 구조 적용
- 정상/주의/즉각 조치 필요 3단계 상태 표시
- 집 도면 기반 위치·이동 경로 시각화
- 전화 연결 및 119 신고 정보 제공
```

```text
3.1.7 WebSocket 기반 실시간 앱 연동

서버에서 발생한 상태 변화를 보호자 앱에 빠르게 반영하기 위해 WebSocket 기반 실시간 통신 구조를 적용하였다. 낙상 의심, 현관 접근, 장시간 무반응 등 이벤트 발생 시 앱 화면에 즉시 반영되며, 보호자가 상황을 확인하고 대응할 수 있도록 안전 알림 및 위험 대응 화면과 연결하였다.

- 로컬 서버와 앱 간 WebSocket 실시간 연결
- 상태 변화 발생 시 앱 화면 즉시 갱신
- 위험 이벤트를 보호자 중심 문구로 변환하여 표시
- 알림 이후 전화 연결 및 신고 정보 확인 흐름 제공
```

### 9.3 개발 환경

앱/서버 관련 추가 내용:

```text
개발환경(IDE): VS Code(Flutter 앱·Node.js 서버 개발), Anaconda Jupyter Notebook(모델 학습·실험)

개발도구: Flutter(모바일 앱 구현), Firebase FCM(푸시 알림), Node.js(WebSocket 서버), PyTorch, NVIDIA TensorRT, NumPy·SciPy·h5py, RuView, OpenCV

개발언어: Dart, JavaScript, Python

기타사항: Android Emulator 기반 앱 테스트, UDP 소켓(실시간 CSI 수신), WebSocket(앱 실시간 연동), FCM(백그라운드 알림)
```

### 9.4 기타 사항 / 제작 노력

```text
5) 사용성 및 제작 노력

- 보호자와 피보호자가 하나의 앱을 사용하되, 역할에 따라 필요한 정보가 다르다는 점을 고려하여 보호자 모드와 피보호자 모드를 분리하였다. 보호자에게는 위험 확인과 대응 중심 화면을 제공하고, 피보호자에게는 생활 상태 확인과 위치 공유 관리 중심 화면을 제공하도록 설계하였다.

- 서버와 앱 간 WebSocket 기반 실시간 연결을 적용하여 낙상 의심, 현관 접근, 장시간 무반응 등 상태 변화가 앱 화면에 빠르게 반영되도록 구현하였다. 이를 통해 보호자는 위험 발생 여부뿐 아니라 발생 위치와 대응 필요 여부를 즉시 확인할 수 있다.

- 집 도면 기반 디지털 트윈 화면을 구현하여 감지 위치, 사람 미니어처, 최근 이동 경로를 시각화하였다. 좌표값이나 센서 수치를 직접 해석하지 않아도 생활 공간 단위로 상황을 파악할 수 있도록 하여 보호자 앱의 직관성과 사용성을 높였다.
```

### 9.5 문제점 및 해결방안

관리 측면:

```text
- (문제) 초기에는 센서·AI 중심으로 기능을 정의하다 보니, 보호자와 피보호자가 실제 앱에서 어떤 정보를 봐야 하는지에 대한 기준이 명확하지 않았다. 이로 인해 앱 화면에 서버 연결 상태, 센서 상태 등 개발자 중심 정보가 과도하게 노출되는 문제가 있었다.
- (해결) 사용자 역할을 보호자와 피보호자로 구분하고, 보호자는 위험 확인과 대응 중심, 피보호자는 생활 상태와 위치 공유 관리 중심으로 화면 목적을 재정의하였다. 이를 바탕으로 Figma 시안과 Flutter 화면을 수정하여 사용자 역할별 정보 구조를 정리하였다.
```

개발 측면:

```text
- (문제) 보호자 앱에서 위험 상태를 확인하려면 서버에서 발생한 상태 변화가 빠르게 반영되어야 하지만, 초기 구조에서는 앱과 서버의 연결 방식이 명확하지 않아 화면 반영이 느리거나 수동 갱신이 필요한 문제가 있었다.
- (해결) WebSocket 기반 실시간 연결 구조를 적용하여 서버의 상태 변화가 보호자 앱 화면에 즉시 반영되도록 개선하였다. 이를 통해 낙상 의심, 현관 접근, 장시간 무반응 등 이벤트가 발생했을 때 앱에서 상태 단계와 위치 정보를 빠르게 확인할 수 있도록 하였다.
```

```text
- (문제) 초기 집 안 상태 화면은 단순 좌표나 평면 도면 형태에 가까워 보호자가 위험 발생 위치와 이동 흐름을 직관적으로 이해하기 어려웠다.
- (해결) 집 도면 기반 디지털 트윈 화면을 구현하여 거실, 침실, 욕실, 현관 등 생활 공간 단위로 위치를 표현하고, 사람 미니어처와 최근 이동 경로를 함께 표시하도록 개선하였다. 이를 통해 보호자가 좌표값이 아닌 실제 생활 공간 기준으로 상황을 이해할 수 있도록 하였다.
```

느낀 점:

```text
- 앱과 서버를 연동하면서 코드 구현뿐 아니라 실행 환경 관리의 중요성을 느꼈다. 로컬 서버가 켜져 있어도 앱이 바라보는 IP 주소나 포트가 맞지 않으면 상태가 반영되지 않았고, 에뮬레이터 저장공간 부족이나 렌더링 문제로 앱 실행이 불안정해지는 경우도 있었다. 이를 해결하며 서버 실행 순서, WebSocket 연결 확인, 에뮬레이터 초기화 등 시연 환경을 안정적으로 관리하는 과정이 실제 서비스 개발에서 매우 중요하다는 점을 배웠다.
```

---

## 10. 보고서용 생성 이미지

생성된 주요 이미지:

```text
outputs/hanium_project_app_flow_roles.png
outputs/hanium_project_app_flow_roles.svg
outputs/hanium_app_internal_flow.png
outputs/hanium_app_internal_flow.svg
outputs/hanium_sw_architecture_guardian_app.png
outputs/hanium_sw_architecture_guardian_app.svg
```

추천 사용:

- `hanium_project_app_flow_roles.png`
  - 제목: 그림 X. 프로젝트 S/W 어플 흐름도
  - 보호자/피보호자 역할 분리 설명에 사용

- `hanium_sw_architecture_guardian_app.png`
  - 시스템/앱 연동 흐름 설명에 사용 가능
  - 단, 사용자가 원한 것은 앱 내부 흐름이므로 우선순위는 낮음

---

## 11. 앱 흐름도 설명 문장

보고서에 붙일 설명:

```text
프로젝트 S/W 어플은 하나의 앱에서 보호자 모드와 피보호자 모드를 선택할 수 있도록 구성하였다. 보호자 모드는 홈 요약, 집 안 상태, 안전 알림, 위험 대응 화면을 통해 현재 상태 확인부터 위치·이동 경로 파악, 전화 연결 및 119 신고 정보 확인까지 이어지는 대응 중심 흐름을 제공한다.

피보호자 모드는 간편 시작, 내 상태, 위치 공유, 생활 기록 화면으로 구성되어 복잡한 조작 없이 본인의 생활 상태와 위치 공유 여부를 확인할 수 있다. 이를 통해 동일한 센서 결과라도 보호자에게는 위험 대응에 필요한 정보를, 피보호자에게는 생활 상태와 위치 공유 관리 정보를 제공하도록 설계하였다.
```

---

## 12. 발표/보고서 표현 주의

사용하지 않는 것이 좋은 표현:

```text
부저 작동
위험
서버 연결 중
좌표값
센서값 그대로 표시
```

추천 표현:

```text
보호자 앱 실시간 알림
즉각 조치 필요
안심 시스템 정상 작동 중
집 도면 기반 위치
생활 공간 단위 상태 표시
```

`위험`은 보고서에서는 `즉각 조치 필요`로 쓰는 편이 좋다.

---

## 13. 다음 작업 추천

다른 환경에서 이어받으면 우선순위는 아래 순서가 좋다.

```text
1. 서버 실행 확인
2. 앱 실행 확인
3. 보호자 → 피보호자 전환 확인
4. 집 안 탭에서 3D 도면 표시 확인
5. WebSocket 상태 반영 확인
6. 보고서 이미지/문장 최종 삽입
7. Git commit / push 정리
```

---

## 14. 빠른 명령어 모음

서버:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
.\server\run_mock_server_node.cmd
```

앱:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
flutter run -d emulator-5554
```

에뮬레이터 앱 삭제:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 uninstall com.example.hanium_app
```

에뮬레이터 저장공간 정리:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 shell pm trim-caches 4G
```

에뮬레이터 초기화:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 emu kill
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -list-avds
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd AVD이름 -wipe-data
```
