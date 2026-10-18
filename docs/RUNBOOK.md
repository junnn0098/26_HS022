# 실행 및 시연 안내

모든 시작 경로는 이 저장소의 루트(`26_HS022`)입니다. 서버, 엣지 추론, 연결 클라이언트, Flutter 앱은 각각 별도 터미널에서 실행합니다.

## 준비할 것

| 경로 | 필요 조건 |
|---|---|
| 화면·통신 시연 | Node.js, Python 3.10 이상, Flutter/Dart 개발 환경. 앱의 Dart SDK 제약은 `^3.9.2` |
| 엣지 코드 점검 | Python과 `edge_ai/requirements.txt`의 NumPy |
| 실제 낙상 추론 | 센서 전용망, ESP32-S3 노드, Jetson, JetPack과 호환되는 PyTorch, 학습 가중치 |
| 보호자 푸시 | Firebase 앱 설정, 서버 서비스 계정, 보호자 기기 토큰·알림 권한, 인터넷 연결 |

서버는 Node.js 기본 모듈을 사용합니다. 현재 경로를 실행하기 위해 FastAPI나 `npm install`을 먼저 할 필요는 없습니다. 기기 설정·서비스 계정 키는 담당자가 별도로 준비합니다.

## 1. 센서 없이 화면과 통신 흐름 확인

### 터미널 A: 서버

Windows PowerShell:

```powershell
cd app\server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

Linux/macOS:

```bash
REAL_SENSOR_ONLY=true node app/server/dev_mock_server.js
```

`REAL_SENSOR_ONLY=true`로 자동 모의 이동을 멈춘 뒤 명시적으로 시연 이벤트를 넣습니다. 관리자 화면은 `http://127.0.0.1:8000/admin`입니다.

### 터미널 B: 서버 확인과 예시 입력

```bash
python3 app/server/jetson_edge_client.py health --server-url http://127.0.0.1:8000
python3 app/server/jetson_edge_client.py once --event danger --server-url http://127.0.0.1:8000
python3 app/server/jetson_edge_client.py once --event normal --server-url http://127.0.0.1:8000
```

여기서 `once`가 만드는 위치·확률·호흡수는 예시값입니다. 센서 기반 낙상 감지 성공을 입증하는 명령이 아닙니다. 여러 상태를 순서대로 보여주려면 `sequence` 모드를 사용할 수 있습니다.

### 터미널 C: 앱

```bash
cd app
flutter pub get
flutter run --dart-define=SERVER_URL=http://10.0.2.2:8000 --dart-define=DEMO_MODE=false
```

위 주소는 같은 PC의 Android 에뮬레이터 기준입니다. `DEMO_MODE=false`여도 서버에서 시연 입력을 보내면 시연값이 표시됩니다.

| 접속 장치 | 서버 주소 |
|---|---|
| 서버와 같은 PC의 브라우저·클라이언트 | `http://127.0.0.1:8000` |
| 같은 PC의 Android 에뮬레이터 | `http://10.0.2.2:8000` |
| 실제 휴대폰 또는 별도 Jetson | `http://서버_PC의_실제_IP:8000` |

실제 휴대폰의 `127.0.0.1`은 휴대폰 자신을 가리킵니다. 같은 망인지, 서버가 실행 중인지, 포트 8000 연결이 가능한지 순서대로 확인합니다.

## 2. 센서·학습 모델 연결

### 터미널 D: 엣지 환경과 가중치 확인

```bash
cd edge_ai
python3 -m pip install -r requirements.txt
python3 -m hanium_fall_v2.selftest
python3 -m unittest discover -s tests -v
```

이 의존성 파일에는 PyTorch가 없습니다. JetPack에 호환되는 PyTorch를 별도로 설치한 환경에서 다음을 진행합니다. 가중치는 저장소에 없으므로 팀이 사용하는 모델 파일을 `models/production/best_model.pt`에 준비합니다.

```bash
python3 -m hanium_fall_v2.validate_fall_checkpoint models/production/best_model.pt
```

`PASS_FALL_CHECKPOINT_LIVE_READY`와 `live_ready: true`를 확인합니다. 이는 형식·입력·모델 호환 검사이며 성능 검증 통과를 뜻하지 않습니다.

```bash
RUVIEW_NODES=1,2,3,4 RUVIEW_CHECKPOINT="$PWD/models/production/best_model.pt" ./jetson/run_live.sh
```

가중치가 없으면 `run_live.sh`가 수신·건강 모니터링 경로만 시작할 수 있습니다. `fall.state=model_unavailable`을 낙상 감지 준비 완료로 해석하지 않습니다. 실제 보드의 노드 ID와 `RUVIEW_NODES`가 일치해야 합니다.

### 터미널 E: 추론 결과 전달

저장소 루트에서 실행합니다. 아래 주소는 서버가 같은 장치일 때이며 별도 PC라면 실제 IP로 바꿉니다.

```bash
python3 app/server/jetson_edge_client.py live-status \
  --status-file edge_ai/runtime/latest_status.json \
  --server-url http://127.0.0.1:8000 \
  --room-x 0.35 --room-y 0.45
```

`--room-x`, `--room-y`는 운영자가 지정한 설치 위치입니다. 모델이 추정한 사람 좌표가 아닙니다. 실제 시연에서는 새 CSI 입력, `latest_status.json`의 `unix_time`, `fall.state`, 서버 반영, 앱 표시를 같은 시간대에 확인합니다.

연결 전 전송 내용을 한 번만 확인하려면:

```bash
python3 app/server/jetson_edge_client.py live-status \
  --status-file edge_ai/runtime/latest_status.json --once --dry-run
```

파일을 직접 읽기 어려우면 별도 터미널에서 `edge_ai/jetson/run_api.sh`로 상태 API(기본 8080)를 실행하고 `--status-url http://Jetson_IP:8080/status`를 사용합니다. API 토큰을 설정했다면 클라이언트에도 동일한 `--token`이 필요합니다.

## 3. FCM 확인

서버 시작 전에 서비스 계정 경로를 지정합니다. 아래 명령의 경로는 실제 파일 위치로 바꿉니다.

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\credentials\firebase-service-account.json"
$env:REAL_SENSOR_ONLY="true"
node app/server/dev_mock_server.js
```

1. 보호자 단말에서 알림 권한을 허용하고 보호자 역할로 실행해 토큰을 등록합니다.
2. `GET /push/status`로 설정 상태를 확인합니다.
3. 관리자 화면 또는 `POST /alarm/test`로 테스트 알림을 보내고 실제 단말 도착까지 확인합니다.
4. `stored_only`, `fcm_not_configured`, 수신 토큰 부재를 전송 성공으로 처리하지 않습니다. 앱 전경·백그라운드 조건을 따로 기록합니다.

## 4. 시연 결과에 함께 기록할 것

| 구분 | 확인할 내용 |
|---|---|
| 입력 출처 | 실제 CSI인지 `once`·`sequence` 예시 입력인지 |
| 위치 출처 | 지정한 설치 좌표인지 별도 위치 추정 결과인지 |
| 호흡 | 현재 서버의 누락값 보충 및 앱 표시 문제를 확인했는지 |
| 모델·신호 상태 | 모델 미설치·품질 부족·센서 중단을 정상으로 오인하지 않는지 |
| 지연 | 낙상 동작 시작·판정·서버 수신·앱 표시 시각을 구분했는지 |
| 긴급 대응 | 실제 신고 대신 전화 앱 연결까지만 확인했는지 |

현재 코드에서 호흡 예시값, 판단 불가 상태, 오래된 데이터 처리에는 보완점이 있습니다. [구현 대조표의 확인 사항](IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)을 해결하기 전에는 단순 시연 성공을 상시 돌봄 서비스 검증 완료로 표현하지 않습니다.

## 5. 평가 재현에 필요한 자료

모델 가중치, 분할 manifest, 해당 CSI 파일을 준비한 후 `edge_ai`에서 실행합니다. 아래 파일 경로는 실제 자료 위치에 맞춥니다.

```bash
python3 -m hanium_fall_v2.evaluate \
  --checkpoint models/production/best_model.pt \
  --manifest data/manifest.json --split test \
  --output reports/test_metrics.json
python3 -m hanium_fall_v2.acceptance_check reports/test_metrics.json
```

실행 결과는 모델 해시와 데이터 분할 정보를 묶어 보관합니다. `acceptance_check`의 기본 기준을 그대로 통과했다고 주장하기 전에 출력의 각 항목을 확인합니다. 장기 오탐은 실제 비낙상 관찰 시간과 경보 건수를 확보한 뒤 추가 입력합니다.
