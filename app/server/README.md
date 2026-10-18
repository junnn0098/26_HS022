# Hanium 로컬 서버

WiFi CSI 기반 보호자 앱에 상태·알림을 전달하는 Node.js 시연 서버입니다.

## 실행

현재 시연 경로는 **Node.js 서버 `dev_mock_server.js`**입니다. 아래 명령은 저장소 루트에서 실행합니다.

```powershell
cd app\server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

Linux/macOS:

```bash
REAL_SENSOR_ONLY=true node app/server/dev_mock_server.js
```

서버는 Node.js 기본 모듈을 사용하므로 이 경로에 `npm install`이나 FastAPI 설치는 필요하지 않습니다. `/admin`은 시연 관리자 화면, `/health`는 서버 상태입니다. 전체 순서는 [실행 안내](../../docs/RUNBOOK.md)를 참고하세요.

`REAL_SENSOR_ONLY=true`는 자동 모의 이동을 멈춥니다. 호흡값이 없으면 예시값을 보충하고 입력이 끊기면 마지막 상태를 유지하는 동작은 남아 있습니다. 현재 동작과 개선 항목은 [구현 대조표](../../docs/IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)에 기록했습니다.

`main.py`·`routers/`·`services/`와 `dev_mock_server.py`는 이전 프로토타입입니다. 현재 Node.js 경로와 API 동작이 같다고 가정하지 않습니다.

설정·보호자·알림은 `dev_state.json`에 저장됩니다. 로그인·서버 API 인증은 구현되지 않았으므로 관리 가능한 시연 네트워크에서 사용합니다.

추가 문서:

- [센서 입력 형식](SENSOR_INTEGRATION.md)
- [발표 시연 절차](DEMO_SCRIPT.md)
- [Jetson 결과 연결](JETSON_EDGE_CLIENT.md)

## 현재 앱과 연결된 개발용 API

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
- `POST /settings`의 `locationSharingEnabled` : 피보호자 위치 공유 ON/OFF 저장. OFF일 때 보호자 앱에는 위치와 이동 동선이 비공개 처리됨
- `GET /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 조회
- `POST /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 저장
- `GET /guardians` : 보호자 목록 조회
- `POST /guardians` : 보호자 추가
- `POST /guardians/update` : 보호자 정보 수정
- `POST /guardians/delete` : 보호자 삭제
- `POST /device/register` : 앱 알림 토큰 등록
- `POST /alarm/test` : 테스트 알림 요청
- `POST /care-recipient/safe` : 피보호자가 괜찮다고 알린 경우 보호자에게 알림 전송
- `POST /scenario` : 시연용 상황 발생
- `WS /ws/location` : 실시간 위치/방/자세/위험 상태 스트림

시연용 위험 상황 발생 예시:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/scenario -ContentType 'application/json' -Body '{"status":"danger","seconds":18}'
```

외부 WiFi CSI/Jetson 쪽에서 좌표를 넣을 때는 아래 형식으로 보내면 됩니다.

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.36,"y":0.45,"status":"danger","pose":"lying","confidence":0.91,"source":"jetson"}'
```

PowerShell에서 한글 JSON이 깨질 수 있으므로 테스트 명령에서는 `room`을 생략하는 것을 추천합니다.
서버가 `x`, `y` 좌표를 기준으로 거실/주방/침실-1/침실-2/욕실/현관을 자동 계산합니다.

## FCM 설정과 단말 수신 확인

앱은 Firebase Messaging 토큰을 `POST /device/register`로 서버에 등록합니다. 이때 `role` 값으로 `guardian` 또는 `careRecipient`를 함께 보내며, Node.js mock 서버는 역할별 토큰을 저장합니다. 위험 상황, 테스트 알림, 피보호자의 안전 확인 알림은 기본적으로 보호자 토큰을 대상으로 Firebase Cloud Messaging 푸시 알림을 보냅니다.

단, 실제 FCM 전송은 Firebase 서비스 계정 키가 있어야 동작합니다. 키가 없으면 기존처럼 앱이 켜져 있을 때 WebSocket/REST 기반 시연만 동작하고, 서버는 FCM 전송을 조용히 건너뜁니다.

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

응답에서 `status`가 `stored_only`이고 `push.reason`이 `fcm_not_configured`이면 서버 알림 목록에는 저장됐지만 실제 FCM 푸시는 보내지 못한 상태입니다. 이 경우 서비스 계정 JSON 경로를 실제 파일 경로로 다시 지정해야 합니다.

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

낙상 의심 시나리오 전송:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/scenario -ContentType 'application/json' -Body '{"status":"danger","seconds":18}'
```
