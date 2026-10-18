# app — Flutter 보호자/피보호자 앱 + 로컬 서버

WiFi CSI 엣지 추론 결과를 받아 보호자에게 실시간 상태·위치·위험 알림을 보여주는 Flutter 앱과, Jetson과 앱 사이를 잇는 로컬 서버입니다. (구 `Hanium_app` 저장소)

## 구성

| 경로 | 역할 |
|---|---|
| `lib/features/auth` | 시연용 역할 선택(보호자/피보호자). 계정 인증은 구현하지 않았습니다 |
| `lib/features/dashboard` | 보호자 홈 요약 (정상 / 주의 / 위험 / 확인 필요) |
| `lib/features/home_map` | 집 도면 기반 위치·이동 경로 표시 |
| `lib/features/alerts` | 안전 알림 목록, 위험 대응, 알림 1건으로 만든 예시 재구성 화면 |
| `lib/features/care_recipient` | 피보호자 모드 (내 상태, 위치 공유 ON/OFF, 호흡 리듬) |
| `lib/features/settings` | 알림 기준, 도면 표시, 위치 공유 설정, 보호자·119 신고 정보 확인 |
| `lib/core` | 상태 모델, WebSocket·REST 저장소, FCM 알림 서비스 |
| `server/local_server.js` | Node.js 로컬 서버 (REST + `WS /ws/location` + FCM + 관리자 웹 `/admin`) |
| `server/jetson_edge_client.py` | 엣지 추론 결과를 서버로 전달 (`live-status`, source `jetson_orin`), 발표용 시나리오 재현 (`sequence`, `once`, source `scripted_demo`) |
| `server/legacy_fastapi_prototype/` | 초기 FastAPI 프로토타입 (현재 미사용) |

[전체 실행 순서와 네트워크 주소](../docs/RUNBOOK.md) · [현재 구현의 확인 사항](../docs/IMPLEMENTATION_STATUS.md)

## 실행

```powershell
# 1) 서버 (별도 터미널, app 폴더 기준)
cd server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd          # http://127.0.0.1:8000/admin

# 2) 앱 (새 터미널에서 app 폴더로 이동)
flutter pub get
flutter run --dart-define=SERVER_URL=http://<서버 IP>:8000 --dart-define=DEMO_MODE=false
```

서버에 `HANIUM_API_TOKEN`을 설정한 경우에만 2)에 `--dart-define=API_TOKEN=<같은 토큰>`을 추가합니다. 값은 앱 빌드에 들어가므로 시연용으로만 사용합니다. `DEMO_MODE=true`(예: `run_emulator_local.cmd`)로 실행하면 설정 화면에 시연용 '상황 재연' 버튼이 나타납니다.

자세한 API와 시연 절차는 [`server/README.md`](server/README.md), [`server/DEMO_SCRIPT.md`](server/DEMO_SCRIPT.md), [`server/JETSON_EDGE_CLIENT.md`](server/JETSON_EDGE_CLIENT.md)를 참고하세요.

## 화면 표시 규칙

| 서버에서 받은 값 | 앱 표시 |
|---|---|
| 데이터 수신 전, 또는 `status: unknown`(모델 미설치·오래된 결과·판단 불가) | 회색 '확인 필요'. 정상으로 표시하지 않고 알림도 만들지 않습니다 |
| `breathingRate` 없음 | 숫자 대신 '측정 대기' |
| `source: jetson_orin` | 'Jetson 실시간 추론' |
| `source: scripted_demo` | '시연 입력' 칩 |
| `source: admin` | '관리자 수동 입력' |
| `source: app-demo`·`scenario` (앱 시연 버튼, `/scenario` 기본값) | '앱 시연 데이터' |
| `source: mock`·`boot`·`reset` (서버 모의 이동, 시작·초기화 직후) | '시연용 mock 데이터' |

## 테스트

```powershell
flutter analyze
flutter test
```

`test/safety_models_test.dart`는 위 표시 규칙(확인 필요, 측정 대기, 출처 구분)을, `test/widget_test.dart`는 서버 없이 역할 선택 화면과 보호자 첫 화면('확인 필요')이 뜨는지 확인합니다.

> 로그인 화면은 역할 선택용이며 인증은 구현되어 있지 않습니다. 로컬 서버는 기본적으로 같은 네트워크의 모든 기기에서 접속할 수 있으므로(시작 시 경고 출력) 관리 가능한 시연 네트워크에서만 사용합니다. `HOST`, `HANIUM_API_TOKEN`, `HANIUM_CORS_ORIGIN` 설정은 [`server/README.md`](server/README.md#보안네트워크-설정)를 참고하세요.
