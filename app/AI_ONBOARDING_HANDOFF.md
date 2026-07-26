# Hanium Safety 앱 AI 인수인계 문서

작성일: 2026-07-12  
최신 동기화: 2026-07-26  
대상: 이 프로젝트를 처음 보는 팀원, 그리고 그 팀원이 사용할 ChatGPT / Gemini / Codex / Claude 등 AI 도구  
목적: 프로젝트 맥락을 모르는 사람이 이 문서만 읽고 앱과 서버를 실행하고, 이후 개발을 이어갈 수 있게 만드는 것

---

## 0-1. 2026-07-26 기준 최신 확정 사항

다른 개발 환경에서 진행된 최신 대화 기록을 기준으로 아래 내용을 현재 프로젝트에 반영했다.

- 서버는 Node.js 로컬 서버를 기준으로 한다.
- 기본 포트는 `8000`이다.
- Android 에뮬레이터 앱 서버 주소는 `http://10.0.2.2:8000`이다.
- 실제 Android 휴대폰에서는 에뮬레이터 주소를 쓸 수 없으므로, 서버 노트북의 Wi-Fi IPv4 주소를 사용한다.
- Firebase FCM은 `server/firebase-service-account.json` 또는 `GOOGLE_APPLICATION_CREDENTIALS` 환경변수로 연결한다.
- 실제 Jetson/센서 연동 시에는 서버 실행 전에 `REAL_SENSOR_ONLY=true`를 지정해서 mock 위치가 실제 센서 값을 덮어쓰지 않게 한다.
- 피보호자 위치 공유 OFF는 단순 UI 상태가 아니라 서버 설정(`locationSharingEnabled`)으로 저장되며, 보호자 화면에서는 위치와 이동 동선이 비공개 처리된다.

대표 실행 명령:

```powershell
cd <작업폴더>\Hanium_app\server
$env:GOOGLE_APPLICATION_CREDENTIALS="<작업폴더>\Hanium_app\server\firebase-service-account.json"
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

에뮬레이터 앱 실행:

```powershell
cd <작업폴더>\Hanium_app
flutter run -d emulator-5554 --dart-define=SERVER_URL=http://10.0.2.2:8000 --dart-define=DEMO_MODE=false
```

실제 휴대폰 APK 빌드 예시:

```powershell
cd <작업폴더>\Hanium_app
flutter build apk --release --dart-define=SERVER_URL=http://<서버노트북IPv4>:8000 --dart-define=DEMO_MODE=false
```

주의: `firebase-service-account.json`, `google-services.json`, Wi-Fi 비밀번호 같은 민감 파일은 Git에 올리지 않는다.

---

## 0. AI에게 그대로 붙여넣을 시작 프롬프트

아래 문단을 새 AI 대화창에 그대로 붙여넣으면 된다.

```text
나는 Hanium Safety 앱 프로젝트를 이어받았다.
이 프로젝트는 WiFi CSI 기반 비접촉 낙상 감지 시스템의 보호자/피보호자용 Flutter 앱과 Node.js 로컬 시연 서버로 구성되어 있다.

내 목표는 기존 코드를 망가뜨리지 않고 앱 완성도를 높이는 것이다.
먼저 이 저장소의 AI_ONBOARDING_HANDOFF.md, PROJECT_HANDOFF.md, README.md, server/README.md를 읽고 현재 구조를 파악해줘.
그 다음 lib/app, lib/core, lib/features, lib/shared 구조를 기준으로 앱을 분석해줘.

중요한 규칙:
1. main.dart에 모든 코드를 다시 몰아넣지 말 것.
2. 기존 보호자/피보호자 모드 구조를 유지할 것.
3. 서버 연결은 기본적으로 http://10.0.2.2:8000 이며, 실제 휴대폰에서는 노트북 IP로 바꿔야 한다.
4. 서버는 Hanium_app/server/run_mock_server_node.cmd로 실행한다.
5. 집 안 상태 화면의 도면 UI는 Figma 시안과 최대한 비슷하게 개선하는 것이 핵심 작업이다.
6. 변경 전에는 관련 파일을 먼저 읽고, 변경 후에는 flutter analyze 또는 flutter run으로 오류를 확인해줘.
7. git reset --hard 같은 위험한 명령은 절대 먼저 실행하지 말고 사용자에게 물어봐줘.

우선 현재 프로젝트 구조와 실행 방법을 요약해주고, 다음으로 해야 할 작업 우선순위를 제안해줘.
```

---

## 1. 프로젝트 한 줄 설명

Hanium Safety는 카메라나 웨어러블 없이 WiFi CSI 신호로 실내 움직임과 낙상 징후를 감지하고, 보호자와 피보호자에게 필요한 정보를 앱으로 보여주는 스마트 주거 안전 앱이다.

앱은 단순히 “낙상 알림”만 보내는 것이 아니라 다음을 목표로 한다.

- 보호자가 현재 집 안 상태를 한눈에 확인한다.
- 집 도면 기반으로 사람이 어디에 있는지 이해한다.
- 정상 / 주의 / 즉각 조치 필요 상태를 구분한다.
- 위험 상황에서는 전화, 신고, 위치 확인으로 바로 이어지게 한다.
- 피보호자는 자신의 위치 공유 여부와 생활 상태 정보를 확인할 수 있다.

---

## 2. 전체 시스템 구조

현재 프로젝트는 크게 세 부분으로 보면 된다.

```text
WiFi CSI 센서 / Jetson 추론
        ↓
Node.js 로컬 시연 서버
        ↓
Flutter 모바일 앱
```

실제 최종 시스템에서는 ESP32-S3 수신 노드와 Jetson Orin Nano가 CSI 데이터를 처리한다.

하지만 현재 발표/시연 환경에서는 Node.js mock 서버가 센서와 Jetson 역할을 대신한다.  
즉, 지금 앱 개발과 시연은 실제 하드웨어 없이도 가능하다.

---

## 3. 저장소 위치와 기본 구조

프로젝트 루트:

```text
C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
```

중요한 폴더:

```text
Hanium_app
├─ lib
│  ├─ main.dart
│  ├─ app
│  ├─ core
│  ├─ features
│  └─ shared
├─ server
│  ├─ dev_mock_server.js
│  ├─ run_mock_server_node.cmd
│  └─ README.md
├─ docs
├─ README.md
├─ PROJECT_HANDOFF.md
└─ AI_ONBOARDING_HANDOFF.md
```

Flutter 앱 구조:

```text
lib/main.dart
lib/app/hanium_app.dart
lib/app/app_config.dart
lib/app/app_theme.dart

lib/core/models
lib/core/services
lib/core/state

lib/features/auth
lib/features/dashboard
lib/features/home_map
lib/features/alerts
lib/features/settings
lib/features/care_recipient
lib/features/shell

lib/shared/ui
```

주의:

- 예전처럼 `main.dart` 하나에 모든 코드를 넣는 구조가 아니다.
- 새 기능을 추가할 때는 되도록 `features`, `core`, `shared` 안에 나눠서 넣어야 한다.

---

## 4. 앱의 핵심 화면

현재 앱은 하나의 앱 안에서 역할을 나누는 구조다.

### 4.1 보호자 모드

보호자가 보는 화면이다.

주요 기능:

- 홈 요약
- 집 안 상태 확인
- 집 도면 기반 위치 확인
- 실시간 알림 확인
- 위험 대응 화면
- 119 신고 정보 확인
- 보호자 정보 관리
- 피보호자 모드로 전환

관련 파일:

```text
lib/features/dashboard/dashboard_screen.dart
lib/features/home_map/home_map_screen.dart
lib/features/home_map/floor_plan_view.dart
lib/features/alerts/alerts_screen.dart
lib/features/settings/settings_screen.dart
lib/features/shell/main_shell.dart
```

### 4.2 피보호자 모드

피보호자가 보는 화면이다.

주요 기능:

- 내 상태 확인
- 위치 공유 ON/OFF
- 보호자에게 공유되는 정보 확인
- 생활 리듬 / 감성형 정보 확인
- 보호자 모드로 전환

관련 파일:

```text
lib/features/care_recipient/care_recipient_screen.dart
lib/core/models/app_role.dart
lib/app/hanium_app.dart
```

---

## 5. 서버 실행 방법

서버는 앱보다 먼저 켜야 한다.

PowerShell을 하나 열고 아래를 실행한다.

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
.\server\run_mock_server_node.cmd
```

정상 실행 후 브라우저에서 관리자 페이지를 연다.

```text
http://127.0.0.1:8000/admin
```

관리자 페이지에서 할 수 있는 것:

- 현재 위치 변경
- 정상 / 주의 / 낙상 의심 시나리오 실행
- 최근 알림 확인
- 시연 상태 초기화

주의:

- `.\run_mock_server_node.cmd`가 아니다.
- 정확한 경로는 `.\server\run_mock_server_node.cmd`다.

---

## 6. 앱 실행 방법

서버를 먼저 켠 다음, 다른 PowerShell에서 앱을 실행한다.

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
flutter run -d emulator-5554
```

에뮬레이터가 여러 개 잡히면 먼저 확인한다.

```powershell
flutter devices
```

그 다음 원하는 디바이스 ID로 실행한다.

```powershell
flutter run -d 디바이스ID
```

---

## 7. 서버 주소 규칙

현재 앱의 기본 서버 주소는 아래 파일에서 관리한다.

```text
lib/app/app_config.dart
```

기본값:

```dart
http://10.0.2.2:8000
```

이 주소는 Android 에뮬레이터에서 PC의 localhost 서버에 접속할 때 쓰는 특수 주소다.

상황별 주소:

| 실행 환경 | 서버 주소 |
|---|---|
| Android 에뮬레이터 | `http://10.0.2.2:8000` |
| PC 브라우저 | `http://127.0.0.1:8000` |
| 실제 휴대폰 | `http://노트북_IP:8000` |

실제 휴대폰으로 실행할 때 예시:

```powershell
flutter run -d 디바이스ID --dart-define=SERVER_URL=http://172.20.10.2:8000
```

발표장 Wi-Fi나 핫스팟 IP가 바뀌면 `172.20.10.2` 부분도 바뀔 수 있다.

---

## 8. 서버와 앱 연결 확인 방법

### 8.1 서버 상태 확인

브라우저에서:

```text
http://127.0.0.1:8000/health
```

또는 PowerShell:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
```

### 8.2 관리자 페이지 확인

```text
http://127.0.0.1:8000/admin
```

관리자 페이지가 뜨면 서버는 켜진 것이다.

### 8.3 앱에서 확인

앱의 `집 안 상태` 화면에서 위치나 상태가 바뀌면 연결이 된 것이다.

연결이 안 된 것처럼 보이면 아래를 확인한다.

- 서버가 먼저 켜져 있는가?
- 앱이 에뮬레이터에서 실행 중인가?
- 앱 서버 주소가 `10.0.2.2:8000`인가?
- 실제 휴대폰이면 노트북 IP 주소를 넣었는가?
- 방화벽이 8000 포트를 막고 있지 않은가?

---

## 9. 서버 API 요약

자세한 내용은 `server/README.md`를 본다.

중요 API:

```text
GET  /health
GET  /admin
GET  /state
GET  /location/latest
POST /sensor/update
POST /sensor/reset
GET  /alerts
POST /alerts/resolve
POST /demo/reset
GET  /settings
POST /settings
GET  /emergency-info
POST /emergency-info
GET  /guardians
POST /guardians
POST /guardians/update
POST /guardians/delete
POST /scenario
WS   /ws/location
```

수동 센서 입력 예시:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.76,"y":0.68,"status":"out","pose":"walking","confidence":0.88,"source":"test","holdMs":60000}'
```

낙상 의심 시나리오 예시:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/scenario -ContentType 'application/json' -Body '{"status":"danger","seconds":18}'
```

---

## 10. 현재 앱에서 가장 중요한 개발 포인트

### 10.1 도면 UI

현재 가장 중요한 작업은 `집 안 상태` 화면의 도면 UI를 Figma 시안과 최대한 비슷하게 만드는 것이다.

관련 파일:

```text
lib/features/home_map/floor_plan_view.dart
lib/features/home_map/home_map_screen.dart
```

현재 목표:

- Figma 3번째 페이지의 집 도면처럼 보여야 한다.
- 방 구분이 명확해야 한다.
- 사람 미니어처가 더 잘 보여야 한다.
- 이동 경로가 잔상처럼 보여야 한다.
- 센서 위치와 현재 위치가 직관적으로 보여야 한다.
- 눌리는 요소는 그림자나 음영으로 구분되어야 한다.

### 10.2 보호자 UX

보호자는 개발자가 아니다.

따라서 보호자 화면에는 아래 정보가 과하게 보이면 안 된다.

- 서버 연결 중
- WebSocket
- confidence
- API
- source
- debug

대신 보호자가 이해할 문장으로 보여줘야 한다.

예:

```text
안심 시스템 정상 작동 중
거실에서 서 있는 상태
확인이 필요한 움직임이 감지되었어요
즉각적인 조치가 필요해요
```

### 10.3 상태 표현

보고서와 앱에서 상태 표현은 다음처럼 정리한다.

| 상태 | 의미 | 사용자 표현 |
|---|---|---|
| 정상 | 평소와 비슷한 생활 패턴 | 이상 징후가 없어요 |
| 주의 | 확인이 필요한 움직임 | 확인이 필요해요 |
| 위험 | 낙상 의심 등 즉각 대응 필요 | 즉각적인 조치가 필요해요 |

가능하면 `위험` 단어만 크게 쓰기보다 `즉각적인 조치가 필요`라는 표현을 함께 사용한다.

---

## 11. 발표 / 보고서에서 앱 파트 설명

앱 파트는 아래 세 가지를 중심으로 설명하면 된다.

### 11.1 역할 기반 앱 화면 구성

보호자와 피보호자가 하나의 앱을 사용하되, 각 역할에 필요한 정보만 볼 수 있도록 화면을 분리하였다. 보호자는 집 안 상태, 알림, 위험 대응을 중심으로 확인하고, 피보호자는 위치 공유 여부와 자신의 생활 상태를 확인하도록 구성하였다.

### 11.2 집 도면 기반 상태 시각화

단순 텍스트 알림만 제공하지 않고, 집 도면 위에 현재 위치와 이동 흐름을 표시하여 보호자가 상황을 직관적으로 이해할 수 있도록 하였다. 이를 통해 “어디에서 어떤 움직임이 발생했는지”를 빠르게 파악할 수 있다.

### 11.3 WebSocket 기반 실시간 알림

서버와 앱을 WebSocket으로 연결하여 위치와 상태 변화가 앱에 빠르게 반영되도록 구성하였다. 낙상 의심과 같은 위험 상황에서는 보호자 앱에서 즉시 확인하고 전화 또는 신고로 이어질 수 있도록 하였다.

---

## 12. 보고서에서 피해야 할 표현

현재 프로젝트 방향에서는 아래 표현을 조심한다.

| 피할 표현 | 바꿀 표현 |
|---|---|
| 부저 작동 | 보호자 앱 실시간 알림 |
| 위험 | 즉각적인 조치 필요 |
| 서버 연결 중 | 안심 시스템 정상 작동 중 |
| confidence 88% | 신뢰도 높은 상태 감지 |
| 관리자 웹이 핵심 기능 | 시연 및 설정용 관리자 콘솔 |

관리자 웹은 발표 시연에는 유용하지만, 보고서의 “주요 사용자 기능”으로 너무 강조하지 않는 것이 좋다.

---

## 13. 보고서용 생성 이미지

보고서에 사용할 수 있는 이미지 파일:

```text
C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\outputs\hanium_project_app_flow_roles.png
C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\outputs\hanium_project_app_flow_roles.svg
```

이 이미지는 `프로젝트 S/W 어플 흐름도` 용도로 만들었다.

이미지 내용:

- 시작 모드 선택
- 보호자 모드 흐름
- 피보호자 모드 흐름
- 센서 결과를 역할별로 다르게 보여주는 구조

본문 설명 예시:

```text
본 앱은 하나의 애플리케이션 안에서 보호자 모드와 피보호자 모드를 분리하여 제공한다. 보호자 모드는 집 안 상태, 실시간 도면, 안전 알림, 위험 대응을 중심으로 구성하고, 피보호자 모드는 위치 공유 여부와 생활 상태 확인을 중심으로 구성하였다. 동일한 센서 분석 결과라도 사용자 역할에 따라 필요한 정보가 다르므로, 앱 내부에서 역할별 화면 흐름을 분리하여 사용성을 높였다.
```

---

## 14. 흔한 오류와 해결법

### 14.1 앱 설치 실패: 저장공간 부족

오류 예시:

```text
INSTALL_FAILED_INSUFFICIENT_STORAGE
Requested internal only, but not enough space
```

해결:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 uninstall com.example.hanium_app
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" -s emulator-5554 shell pm trim-caches 4G
flutter run -d emulator-5554
```

그래도 안 되면 에뮬레이터 데이터를 초기화해야 한다.

### 14.2 서버는 켜졌는데 앱 반영이 느림

확인할 것:

- 앱이 WebSocket을 제대로 연결했는가?
- 서버 주소가 맞는가?
- 관리자 페이지에서 수동 입력이 유지 시간 `holdMs`와 함께 들어갔는가?
- 앱에서 polling 간격이 너무 긴가?

관련 파일:

```text
lib/app/app_config.dart
lib/core/services/safety_repository.dart
lib/core/state/safety_controller.dart
server/dev_mock_server.js
```

### 14.3 PowerShell에서 한글이 깨져 보임

파일이 실제로 깨진 것이 아니라 PowerShell 표시 인코딩 문제일 수 있다.  
VS Code에서 UTF-8로 열어 확인하는 것이 좋다.

### 14.4 서버 실행 파일을 못 찾음

잘못된 명령:

```powershell
.\run_mock_server_node.cmd
```

올바른 명령:

```powershell
.\server\run_mock_server_node.cmd
```

---

## 15. 개발할 때 지켜야 할 규칙

새로 이어받는 사람이나 AI가 꼭 지켜야 할 규칙이다.

1. 기존 코드를 삭제하고 처음부터 다시 만들지 않는다.
2. `main.dart`에 모든 코드를 몰아넣지 않는다.
3. 화면은 `features` 단위로 나눠서 수정한다.
4. 서버 주소는 `app_config.dart`에서 관리한다.
5. 보호자 화면에는 개발자용 정보를 노출하지 않는다.
6. 피보호자 모드는 별도 사용자 경험으로 유지한다.
7. 도면 UI는 `floor_plan_view.dart` 중심으로 수정한다.
8. 서버 API 변경 시 Flutter 쪽 모델과 repository도 같이 확인한다.
9. 변경 후에는 최소한 `flutter analyze`를 실행한다.
10. Git 작업 전에는 `git status`로 현재 변경 파일을 확인한다.

---

## 16. 다음 작업 우선순위

### 1순위: 도면 UI 완성도 개선

목표:

- Figma 3번째 페이지의 도면처럼 보이게 하기
- 방 경계, 바닥 질감, 가구, 센서, 사람, 경로를 더 명확하게 표현
- 미니어처 사람의 상태를 더 부각

### 2순위: 보호자용 문구 정리

목표:

- 개발자용 단어 제거
- 보호자가 이해하는 문장으로 변경
- 정상 / 주의 / 즉각 조치 필요 표현 통일

### 3순위: 실시간 반영 속도 개선

목표:

- 관리자 페이지에서 위치 변경 시 앱 반영 지연 최소화
- WebSocket 이벤트 수신 안정성 확인
- fallback polling 간격 조정

### 4순위: 이벤트 재현 기능

목표:

- 과거 이벤트를 선택하면 당시 위치와 이동 경로를 다시 보여주기
- 발표에서 “상황 재연” 기능으로 설명 가능

### 5순위: 역할 확장

목표:

- 보호자 / 피보호자 외에 관리자 또는 중간 관리자 역할 추가 가능성 검토
- 실제 서비스에서는 돌봄 담당자나 관제 담당자 역할로 확장 가능

---

## 17. 발표 시연 순서

발표자가 그대로 따라 하면 된다.

1. 서버 실행
2. 관리자 페이지 열기
3. 앱 실행
4. 앱에서 보호자 모드 선택
5. `집 안 상태` 화면 확인
6. 관리자 페이지에서 정상 상태 시연
7. 현관 접근 또는 이동 상태 시연
8. 낙상 의심 상태 시연
9. 앱에서 알림 화면과 위험 대응 화면 확인
10. 전화하기 / 신고 정보 / 괜찮음 확인 버튼 설명
11. 피보호자 모드로 전환
12. 위치 공유 ON/OFF와 내 상태 화면 설명

---

## 18. GitHub 작업 주의

다른 사람이 이어받으면 먼저 아래를 실행한다.

```powershell
git status
git branch
git remote -v
```

절대 바로 실행하지 말 것:

```powershell
git reset --hard
git checkout -- .
```

이 명령은 작업 내용을 날릴 수 있다.

커밋 전 확인:

```powershell
flutter analyze
git status
```

---

## 19. 이 프로젝트를 이해하는 가장 빠른 순서

처음 보는 사람은 아래 순서대로 읽으면 된다.

1. 이 문서 `AI_ONBOARDING_HANDOFF.md`
2. `PROJECT_HANDOFF.md`
3. `README.md`
4. `server/README.md`
5. `lib/app/hanium_app.dart`
6. `lib/app/app_config.dart`
7. `lib/features/home_map/home_map_screen.dart`
8. `lib/features/home_map/floor_plan_view.dart`
9. `lib/core/services/safety_repository.dart`
10. `lib/core/state/safety_controller.dart`

---

## 20. 마지막 요약

이 프로젝트는 단순 Flutter 앱이 아니다.  
WiFi CSI 기반 낙상 감지 결과를 사람이 이해할 수 있는 안전 서비스 화면으로 바꾸는 앱이다.

가장 중요한 방향은 다음과 같다.

```text
센서 데이터 → 서버 → 앱 → 보호자가 이해 가능한 상황 정보 → 즉각 대응
```

앞으로 개발할 때는 “기술적으로 연결되었는가?”보다 “보호자가 이 화면을 보고 바로 판단할 수 있는가?”를 더 중요하게 봐야 한다.
