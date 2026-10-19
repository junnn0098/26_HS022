# 실행 및 시연 안내

모든 명령은 저장소 루트(`26_HS022`)에서 시작합니다. 서버, 엣지 추론, 연결 클라이언트, Flutter 앱은 각각 별도 터미널에서 실행합니다. 명령의 `python`은 Python 3이며, `python`이 없는 Linux·Jetson에서는 `python3`를 씁니다.

## 준비할 것

| 경로 | 필요 조건 |
|---|---|
| 내려받기 없는 확인 | Python 3.10 이상, NumPy, PyTorch(PC는 CPU용으로 충분), Node.js, Flutter |
| 화면·통신 시연 | Node.js, Python 3.10 이상, Flutter/Dart 개발 환경. 앱의 Dart SDK 제약은 `^3.9.2` |
| 실측 데이터 학습·재현 | 위 Python 환경과 [실측 데이터셋](../dataset/README.md) 내려받기(학습 윈도우 189MB부터), 그림에는 matplotlib |
| 센서 기반 낙상 추론 | 센서 전용망, ESP32-S3 노드, Jetson, JetPack과 호환되는 PyTorch, v2 학습 체크포인트 |
| 보호자 푸시 | Firebase 앱 설정, 서버 서비스 계정, 보호자 기기 토큰·알림 권한, 인터넷 연결 |

서버는 Node.js 기본 모듈만 사용하므로 `npm install`이 필요 없습니다. 기기 설정·서비스 계정 키는 담당자가 따로 준비합니다.

## 0. 내려받기 없이 확인

저장소에 들어 있는 샘플·가중치와 단위 테스트로 코드가 끝까지 실행되는지 확인합니다.

```bash
cd edge_ai
python -m pip install -r requirements.txt torch
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all --npz-dir ../dataset/sample --metadata ../dataset/sample/sample_windows.csv
python -m unittest discover -s tests
cd ..
python -m unittest discover -s app/server/tests
cd app
flutter test
```

- 평가 명령은 [`dataset/sample`](../dataset/sample)의 윈도우 15개(라벨마다 1개)에 팀 학습 가중치를 적용해 전체·수집 배치별·동작별 지표를 JSON으로 출력합니다. 샘플이 15개뿐이므로 출력 수치는 실행 확인용입니다. 학습 결과는 [실측 데이터 학습 결과](../experiments/MEASURED_RESULTS.md)에 있습니다.
- `edge_ai` 단위 테스트는 PyTorch가 없으면 모델·실시간·분할 테스트를 건너뜁니다.
- Windows에서 `flutter test`를 처음 실행할 때 개발자 모드(심볼릭 링크 허용)를 요구할 수 있습니다. 확인한 환경은 Flutter 3.47.2입니다.
- 서버 테스트는 Node.js가 필요하며, 서버를 임시 폴더에 복사해 띄우고 끝나면 종료하므로 `app/server/dev_state.json`을 건드리지 않습니다.

### 녹화 재생으로 v1 실시간 추론 확인

센서 노드 대신 저장소의 낙상 녹화 12초를 UDP로 재생해, 실시간 경로가 패킷을 받아 0.5초마다 낙상 확률을 계산하는지 봅니다. 두 터미널에서 `edge_ai/` 기준으로 실행합니다.

```bash
python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --host 127.0.0.1
python -m hanium_fall_v1.replay_recording ../dataset/sample/raw/csi-1783443615.fall-12s.csi.jsonl.gz
```

v1 실시간 스크립트는 0.5초마다 낙상 확률을 콘솔에 표시하고, 경보 조건(0.9 이상 즉시, 0.5 이상 2회 연속)을 넘으면 `FALL` 줄을 출력합니다. 녹화 재생은 실시간 경로의 동작 확인용입니다.

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
REAL_SENSOR_ONLY=true node app/server/local_server.js
```

`REAL_SENSOR_ONLY=true`로 자동 모의 이동을 멈춘 뒤 시연 입력을 직접 넣습니다. 시작 로그의 `Mode:` 줄에서 모의 이동 ON/OFF를 확인합니다. 관리자 화면은 `http://127.0.0.1:8000/admin`입니다.

필요할 때만 쓰는 설정입니다. 자세한 동작은 [서버 안내](../app/server/README.md#보안네트워크-설정)에 있습니다.

| 환경 변수 | 쓰는 경우 |
|---|---|
| `HOST=127.0.0.1` | 같은 PC의 브라우저·에뮬레이터만 접속할 때. 기본값 `0.0.0.0`은 같은 망의 모든 기기에서 접속할 수 있으며 시작 시 경고를 출력합니다 |
| `HANIUM_API_TOKEN=<토큰>` | POST와 상태 조회 API에 `Authorization: Bearer <토큰>`을 요구할 때. 연결 클라이언트와 앱에도 같은 토큰을 지정합니다 |
| `HANIUM_CORS_ORIGIN=<출처>` | 다른 출처의 브라우저 앱에서 접속할 때(기본은 같은 출처만 허용) |

### 터미널 B: 서버 확인과 예시 입력

```bash
python app/server/jetson_edge_client.py health --server-url http://127.0.0.1:8000
python app/server/jetson_edge_client.py once --event danger --server-url http://127.0.0.1:8000
python app/server/jetson_edge_client.py once --event normal --server-url http://127.0.0.1:8000
```

`once`·`sequence`는 미리 정한 위치·확률·호흡수를 `source: scripted_demo`로 보냅니다. 앱은 이 입력에 '시연 입력' 칩을 붙여 실제 엣지 추론(`jetson_orin`)과 구분합니다. 센서로 낙상을 감지한 결과가 아닙니다. 서버에 토큰을 설정했다면 같은 `HANIUM_API_TOKEN` 환경 변수를 두거나 `--server-token <토큰>`을 붙입니다.

### 터미널 C: 앱

```bash
cd app
flutter pub get
flutter run --dart-define=SERVER_URL=http://10.0.2.2:8000 --dart-define=DEMO_MODE=false
```

- 위 주소는 같은 PC의 Android 에뮬레이터 기준입니다.
- 첫 화면 '역할 선택'에서 보호자·피보호자 화면을 고릅니다.
- 설정 화면의 '상황 재연' 버튼은 `--dart-define=DEMO_MODE=true`(예: `app/run_emulator_local.cmd`)일 때만 보입니다.
- 서버에 `HANIUM_API_TOKEN`을 설정했다면 앱도 `--dart-define=API_TOKEN=<같은 토큰>`으로 실행합니다. 토큰이 앱 빌드에 들어가므로 시연용으로만 씁니다.
- 서버 데이터를 받기 전과 `status: unknown`은 '확인 필요', 호흡값이 없으면 '측정 대기'로 표시됩니다.

| 접속 장치 | 서버 주소 |
|---|---|
| 서버와 같은 PC의 브라우저·클라이언트 | `http://127.0.0.1:8000` |
| 같은 PC의 Android 에뮬레이터 | `http://10.0.2.2:8000` |
| 실제 휴대폰 또는 별도 Jetson | `http://서버_PC의_실제_IP:8000` (서버를 `HOST=127.0.0.1`로 띄우면 접속 불가) |

실제 휴대폰의 `127.0.0.1`은 휴대폰 자신을 가리킵니다. 같은 망인지, 서버가 실행 중인지, 포트 8000 연결이 가능한지 순서대로 확인합니다.

## 2. 센서·학습 모델 연결

### 터미널 D: 엣지 환경과 가중치 확인

`requirements.txt`에는 PyTorch가 없으므로 Jetson에서는 JetPack과 호환되는 PyTorch를 먼저 따로 설치합니다.

```bash
cd edge_ai
python3 -m pip install -r requirements.txt
python3 -m hanium_fall_v2.selftest
python3 -m unittest discover -s tests -v
```

실시간 경로(`run_live.sh`)는 v2 모델(`hanium_fall_v2`)을 씁니다. v2는 모델 구조와 학습 코드(`hanium_fall_v2.train`)를 제공하며, 학습한 체크포인트를 `models/production/best_model.pt`에 두고 확인합니다.

```bash
python3 -m hanium_fall_v2.validate_fall_checkpoint models/production/best_model.pt
```

`PASS_FALL_CHECKPOINT_LIVE_READY`와 `live_ready: true`를 확인합니다. 형식·입력·모델 호환 검사이며 성능 검증이 아닙니다.

```bash
RUVIEW_NODES=1,2,3,4 RUVIEW_CHECKPOINT="$PWD/models/production/best_model.pt" ./jetson/run_live.sh
```

가중치가 없으면 `run_live.sh`는 수신·건강 모니터링 경로만 시작하고 `fall.state=model_unavailable`을 기록합니다. 이 상태는 앱에 '확인 필요'로 전달됩니다. 실제 보드의 노드 ID와 `RUVIEW_NODES`가 일치해야 합니다.

- v1 모델은 `python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all`로 UDP 5005 패킷을 받아 낙상 확률을 콘솔에 출력합니다.
- 센서 수신만 눈으로 확인하려면 [CSI 파형 도구](../edge_ai/tools/README.md)를 씁니다(`python3 -m pip install -r tools/requirements.txt` 후 `python3 -m tools.csi_ws_bridge`).
- v1 실시간 추론과 CSI 파형 도구는 `run_live.sh`와 같은 UDP 5005를 받으므로 하나씩 실행합니다.

### 터미널 E: 추론 결과 전달

저장소 루트에서 실행합니다. 아래 주소는 서버가 같은 장치일 때이며 별도 PC라면 실제 IP로 바꿉니다.

```bash
python3 app/server/jetson_edge_client.py live-status \
  --status-file edge_ai/runtime/latest_status.json \
  --server-url http://127.0.0.1:8000 \
  --room-x 0.35 --room-y 0.45
```

- `--room-x`, `--room-y`는 도면에 표시할 감시 방의 설치 위치(0–1 정규화 좌표)입니다.
- `live-status`는 `source: jetson_orin`으로 보냅니다. `unix_time`이 없거나 `--max-age`(기본 10초)보다 오래된 결과는 전달하지 않고, `[stale]` 경고를 출력한 뒤 `status: unknown`을 한 번 보냅니다. Jetson과 PC 시계가 다르면 시계를 맞추거나 `--max-age 0`을 씁니다.
- 로컬 서버를 `HANIUM_API_TOKEN`으로 실행했다면 같은 환경 변수(또는 `--server-token`)를 지정합니다.
- 실제 시연에서는 새 CSI 입력, `latest_status.json`의 `unix_time`, `fall.state`, 서버 반영, 앱 표시를 같은 시간대에 확인합니다.

연결 전 전송 내용을 한 번만 확인하려면:

```bash
python3 app/server/jetson_edge_client.py live-status \
  --status-file edge_ai/runtime/latest_status.json --once --dry-run
```

`latest_status.json`이 10초보다 오래되었으면 이 명령은 `[stale]`을 출력하고 종료 코드 1로 끝납니다.

파일을 직접 읽기 어려우면 별도 터미널에서 `edge_ai/jetson/run_api.sh`로 상태 API(기본 8080)를 실행하고 `--status-url http://Jetson_IP:8080/status`를 사용합니다. 상태 API에 토큰(`RUVIEW_API_TOKEN`)을 설정했다면 클라이언트에 같은 `--token`을 지정합니다. 이 토큰은 로컬 서버 토큰과 별개입니다.

## 3. FCM 확인

서버 시작 전에 서비스 계정 경로를 지정합니다. 아래 경로는 실제 파일 위치로 바꿉니다.

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\credentials\firebase-service-account.json"
$env:REAL_SENSOR_ONLY="true"
node app/server/local_server.js
```

1. 보호자 단말에서 알림 권한을 허용하고 보호자 역할로 실행해 토큰을 등록합니다.
2. `GET /push/status`로 설정 상태를 확인합니다.
3. 관리자 화면 또는 `POST /alarm/test`로 테스트 알림을 보내고 실제 단말 도착까지 확인합니다.
4. `stored_only`, `fcm_not_configured`, 수신 토큰 부재는 전송 실패로 기록합니다. 앱 전경·백그라운드 조건을 따로 기록합니다.

## 4. 실측 데이터셋과 결과 재현

### 데이터셋 내려받기

```bash
python dataset/tools/download.py --list     # 받을 파일 목록만 출력
python dataset/tools/download.py            # 학습 윈도우 NPZ 4개 (189MB) -> dataset/data/
python dataset/tools/download.py --v2       # NPZ + v2 형식 세션 -> dataset/v2_sessions/
python dataset/tools/download.py --raw      # NPZ + 원본 CSI·관절 좌표 녹화 -> dataset/raw/
```

GitHub Release `dataset-v1.0`에서 받아 [`SHA256SUMS`](../dataset/SHA256SUMS)로 확인하고, 이미 받은 파일은 다시 받지 않습니다. 압축 파일은 받은 폴더에 풉니다. 압축 해제는 Python 3.10 이상에서 동작하며, 파일 경로가 받은 폴더 밖을 가리키는 항목은 거부합니다. 파일 구성과 용량은 [데이터셋 설명](../dataset/README.md#파일-구성과-내려받기)에 있습니다.

### 결과 재현

```bash
python dataset/tools/download.py                        # 학습 윈도우 NPZ (189MB)
python experiments/run_v1_experiments.py                # v1 학습·평가 (CPU 약 7분)
python -m pip install -r experiments/requirements.txt   # 그림용 matplotlib
python experiments/plot_figures.py                      # 데이터셋·결과 그림
```

- `run_v1_experiments.py`는 v1 1D-CNN 모델을 라벨별 층화 윈도우 무작위 80/20 분할로 5회 반복 학습·평가합니다. 기본 동작 세트(11종) 1,019개 윈도우 결과는 `experiments/results/v1/b1_random/`, 전체 동작 세트(15종) 2,217개 윈도우 결과는 `experiments/results/v1/random_all/`에 덮어씁니다. 하나만 돌리려면 `--only b1_random`처럼 실행 이름을 지정합니다.
- 결과 폴더마다 `summary.json`(평균·표준편차·실행 환경), `runs.json`(반복별 지표), `predictions.csv`(윈도우별 낙상 확률)가 있습니다. 공개한 결과는 기본값 `--threads 2`로 만들었으며, 스레드 수를 바꾸면 소수 셋째 자리에서 차이가 날 수 있습니다.
- `plot_figures.py`는 데이터셋 구성 그림과 결과 그림(`experiments/results/figures/v1_results.png`)을 그립니다.
- 결과 표와 설명은 [실측 데이터 학습 결과](../experiments/MEASURED_RESULTS.md)에 있습니다.

### v2 체크포인트 평가

v2 가중치, 분할 manifest, 해당 CSI 세션을 준비한 뒤 `edge_ai`에서 실행합니다. 파일 경로는 실제 자료 위치에 맞춥니다.

```bash
python3 -m hanium_fall_v2.evaluate \
  --checkpoint models/production/best_model.pt \
  --manifest data/manifest.json --split test \
  --output reports/test_metrics.json
python3 -m hanium_fall_v2.acceptance_check reports/test_metrics.json
```

결과는 모델 해시와 데이터 분할 정보와 함께 보관합니다. `acceptance_check`의 기본 기준은 코드에 둔 목표값이므로 출력의 항목별 결과를 함께 기록합니다. 장기 오탐은 실제 비낙상 관찰 시간과 경보 건수를 `--reviewed-negative-hours`, `--observed-false-alarms`로 넣습니다.

## 5. 시연 결과에 함께 기록할 것

| 구분 | 확인할 내용 |
|---|---|
| 입력 출처 | 실제 CSI 추론(`jetson_orin`)인지 `once`·`sequence` 예시 입력(`scripted_demo`, 앱의 '시연 입력' 칩)인지 |
| 호흡 | 측정값이 없을 때 '측정 대기'로 표시되는지 |
| 모델·신호 상태 | 모델 미설치·판단 불가가 '확인 필요'로 표시되는지, `live-status`의 `[stale]` 경고가 있었는지 |
| 지연 | 낙상 동작 시작·판정·서버 수신·앱 표시 시각을 구분했는지 |
| 긴급 대응 | 실제 신고 대신 전화 앱 연결까지만 확인했는지 |

입력이 끊기면 서버는 마지막 상태를 유지하며, 오래된 추론 결과는 `live-status`만 걸러 `unknown`으로 알립니다. 기능별 구현 내용은 [기능별 구현 현황](IMPLEMENTATION_STATUS.md), 실환경 평가 방법은 [평가 절차](validation/EVALUATION_PROTOCOL.md)에 있습니다.
