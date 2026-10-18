# Hanium 로컬 서버

WiFi CSI 기반 보호자 앱에 상태·알림을 전달하는 Node.js 시연 서버입니다.

## 실행

현재 시연 경로는 **Node.js 서버 `local_server.js`**입니다. 아래 명령은 저장소 루트에서 실행합니다.

```powershell
cd app\server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

Linux/macOS:

```bash
REAL_SENSOR_ONLY=true node app/server/local_server.js
```

서버는 Node.js 기본 모듈만 사용하므로 이 경로에 `npm install`이나 FastAPI 설치는 필요하지 않습니다(`package.json`은 CommonJS 모드 고정용이며 의존성이 없습니다). `/admin`은 시연 관리자 화면, `/health`는 서버 상태입니다. 전체 순서는 [실행 안내](../../docs/RUNBOOK.md)를 참고하세요.

`REAL_SENSOR_ONLY=true`는 자동 모의 이동을 멈춥니다. 설정하지 않으면 자동 모의 이동과 약 45초마다 모의 낙상(source `mock`)이 생성되며, 서버 시작 로그의 `Mode:` 줄에 현재 모드가 표시됩니다. 호흡값이 없으면 서버는 값을 채우지 않고 `breathingRate: null`로 전달합니다(앱 '측정 대기'). 입력이 끊기면 서버는 마지막 상태를 유지합니다. 실행 중인 `jetson_edge_client.py live-status`는 10초 넘게 갱신되지 않은 추론 결과를 `status: unknown`으로 알리지만, 클라이언트 자체가 멈추면 마지막 상태가 그대로 남습니다. 현재 동작과 개선 항목은 [구현 대조표](../../docs/IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)에 기록했습니다.

[`legacy_fastapi_prototype/`](legacy_fastapi_prototype/)(FastAPI `main.py`·`routers/`·`services/`·`models/`, `dev_mock_server.py`)는 초기 프로토타입으로 현재 사용하지 않습니다.

설정·보호자·알림은 `dev_state.json`(Git 제외)에 저장됩니다. 로그인은 역할 선택용이며, 서버 API 보호는 아래 설정으로 켭니다.

## 보안·네트워크 설정

| 환경 변수 | 기본값 | 의미 |
|---|---|---|
| `HOST` | `0.0.0.0` | 실제 휴대폰·Jetson 시연을 위해 모든 인터페이스에서 받으며 시작 시 경고를 출력합니다. 같은 PC(에뮬레이터 포함)만 쓸 때는 `127.0.0.1` |
| `HANIUM_API_TOKEN` | 없음 | 설정하면 모든 POST와 상태 조회 GET(`/state`, `/emergency-info`, `/guardians`, `/alerts`, `/settings`, `/location/latest`)에 `Authorization: Bearer <토큰>`이 필요합니다. `jetson_edge_client.py`·`demo_sensor_client.py`는 같은 환경 변수가 있으면 토큰을 보내고, 관리자 화면은 처음 한 번 토큰을 묻습니다. Flutter 앱은 `--dart-define=API_TOKEN=<같은 토큰>`으로 실행하면 같은 헤더를 보냅니다. `/`, `/health`, `/push/status`, `/sensor/schema`, `/sensor/test-command`, `/admin` 화면 자체와 `WS /ws/location`은 토큰 없이 열려 있습니다(WebSocket 위치도 위치 공유 OFF 필터는 적용) |
| `HANIUM_CORS_ORIGIN` | 없음 | 기본은 같은 출처(관리자 화면)만 허용합니다. 다른 출처의 브라우저 앱을 쓸 때 쉼표로 구분해 지정합니다(예: `http://localhost:5000`) |
| `REAL_SENSOR_ONLY` | `false` | `true`이면 자동 모의 이동을 끕니다 |

JSON 본문을 받는 POST는 `Content-Type: application/json`이 아니면 415로 거절합니다. 응급 정보에는 출입 비밀번호를 저장하지 않으며, `/health`·`/push/status`는 서비스 계정 파일 경로를 노출하지 않습니다.

회귀 테스트(Node.js 필요, 임시 폴더에서 서버를 띄우므로 `dev_state.json`을 건드리지 않음):

```bash
python -m unittest discover -s app/server/tests -v
```

추가 문서:

- [센서 입력 형식](SENSOR_INTEGRATION.md)
- [발표 시연 절차](DEMO_SCRIPT.md)
- [Jetson 결과 연결](JETSON_EDGE_CLIENT.md)

## API

- `GET /health` : 서버 실행 상태 확인
- `GET /admin` : 시연용 관리자 콘솔
- `GET /state` : 보호자, 설정, 알림 전체 상태 확인
- `GET /location/latest` : 최근 위치/방/자세/위험 상태 조회
- `POST /sensor/update` : 외부 센서 또는 관리자 콘솔에서 위치/상태 입력
- `POST /sensor/reset` : 수동 센서 입력 해제. 자동 모의 이동 여부는 `REAL_SENSOR_ONLY` 설정에 따름
- `GET /alerts` : 알림 목록 조회
- `POST /alerts/resolve` : 위험 알림 확인 완료 처리
- `POST /alerts/delete` : 특정 알림 1개 삭제
- `POST /alerts/clear` : 알림 기록 전체 삭제
- `POST /demo/reset` : 발표/시연 상태 초기화
- `GET /settings` : 설정 조회
- `POST /settings` : 설정 저장
- `POST /settings`의 `locationSharingEnabled` : 피보호자 위치 공유 ON/OFF 저장. OFF일 때 REST 응답과 `WS /ws/location` 스트림 모두 위치가 비공개 처리되고, 알림·푸시에도 방 이름 대신 `위치 비공개`가 기록됨
- `GET /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 조회
- `POST /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 저장
- `GET /guardians` : 보호자 목록 조회
- `POST /guardians` : 보호자 추가
- `POST /guardians/update` : 보호자 정보 수정
- `POST /guardians/delete` : 보호자 삭제
- `POST /device/register` : 앱 알림 토큰 등록
- `POST /alarm/test` : 테스트 알림 요청
- `POST /care-recipient/safe` : 피보호자가 괜찮다고 알린 경우 보호자에게 알림 전송
- `POST /scenario` : 시연용 상황 발생. `source`를 지정하지 않으면 `scenario`(앱 표시 '앱 시연 데이터')
- `WS /ws/location` : 실시간 위치/방/자세/위험 상태 스트림

시연용 위험 상황 발생 예시:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/scenario -ContentType 'application/json' -Body '{"status":"danger","seconds":18}'
```

외부 WiFi CSI/Jetson 쪽에서 좌표를 넣을 때는 아래 형식으로 보내면 됩니다. 손으로 보내는 시험 입력은 `source`를 `scripted_demo`로 두어 실제 엣지 추론(`jetson_orin`)과 구분합니다. `source`가 없으면 `unknown`, 인식하지 못한 `status`(`model_unavailable` 포함)는 `normal`이 아니라 `unknown`(판단 불가)으로 저장됩니다.

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.36,"y":0.45,"status":"danger","pose":"lying","confidence":0.91,"source":"scripted_demo"}'
```

`HANIUM_API_TOKEN`을 설정했다면 `-Headers @{ Authorization = 'Bearer <토큰>' }`을 추가합니다.

PowerShell에서 한글 JSON이 깨질 수 있으므로 테스트 명령에서는 `room`을 생략하는 것을 추천합니다.
서버가 `x`, `y` 좌표를 기준으로 거실/주방/침실-1/침실-2/욕실/현관을 자동 계산합니다.

## FCM 설정과 단말 수신 확인

앱은 Firebase Messaging 토큰을 `POST /device/register`로 서버에 등록합니다. 이때 `role` 값으로 `guardian` 또는 `careRecipient`를 함께 보내며, Node.js 로컬 서버는 역할별 토큰을 저장합니다. 위험 상황, 테스트 알림, 피보호자의 안전 확인 알림은 기본적으로 보호자 토큰을 대상으로 Firebase Cloud Messaging 푸시 알림을 보냅니다.

실제 FCM 전송은 Firebase 서비스 계정 키가 있어야 동작합니다. 키가 없으면 서버는 FCM 전송을 건너뛰고, 앱이 켜져 있는 동안의 WebSocket/REST 갱신만 동작합니다.

서비스 계정 JSON 파일을 받은 뒤 서버 실행 전에 PowerShell에서 아래처럼 지정합니다.

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\firebase-service-account.json"
.\run_mock_server_node.cmd
```

또는 프로젝트 ID를 별도로 지정해야 하는 환경에서는 아래처럼 실행합니다.

```powershell
$env:FIREBASE_PROJECT_ID="firebase-project-id"
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\path\to\firebase-service-account.json"
.\run_mock_server_node.cmd
```

테스트 알림 전송:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/alarm/test
```

응답에서 `status`가 `stored_only`이면 서버 알림 목록에는 저장됐지만 실제 FCM 푸시는 보내지 못한 상태입니다. `push.reason`이 `no_registered_tokens`이면 보호자 앱이 아직 토큰을 등록하지 않은 것이고, `fcm_not_configured`이면 서비스 계정 JSON 경로를 실제 파일 경로로 다시 지정해야 합니다.

FCM 설정 상태 확인:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/push/status
```

설정 확인 시 `push.configured`와 `credentialPathExists`를 확인합니다. 설정·전송 응답 성공만으로 기기 수신이 증명되지는 않으므로 보호자 단말에서 알림 도착까지 확인합니다.

피보호자가 “괜찮다고 알리기”를 누른 상황 테스트:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/care-recipient/safe -ContentType 'application/json' -Body '{"room":"거실"}'
```

보호자 기기가 한 번이라도 보호자 모드로 실행되어 토큰을 등록해야 보호자 대상 푸시가 정상 전송됩니다.
