# Jetson Orin edge client

Jetson Orin에서 센서/AI 결과를 로컬 서버로 보내기 위한 클라이언트입니다.

전체 흐름:

```text
Jetson Orin
  -> POST /sensor/update
  -> Node.js local server
  -> WebSocket
  -> Flutter app / admin web
```

## 파일

```text
server/jetson_edge_client.py
server/run_jetson_edge_mock.sh   # Jetson/Linux
server/run_jetson_edge_mock.cmd  # Windows test
```

## 서버 먼저 실행

개발 PC 또는 발표 PC에서 서버를 먼저 켭니다.

```powershell
cd Hanium_app
.\server\run_mock_server_node.cmd
```

관리자 페이지:

```text
http://127.0.0.1:8000/admin
```

## 2026-07-26 기준 실제 Jetson 연동 확인값

노트북과 Jetson을 USB-C 네트워크로 연결했을 때 확인된 기준값입니다.

```text
Jetson IP: 192.168.55.1
노트북 USB-C IP: 192.168.55.100
SSH 계정 예시: <사용자>@192.168.55.1
```

노트북 서버는 실제 센서값만 받도록 아래처럼 실행하는 것을 권장합니다.

```powershell
cd <작업폴더>\Hanium_app\server
$env:GOOGLE_APPLICATION_CREDENTIALS="<작업폴더>\Hanium_app\server\firebase-service-account.json"
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

Jetson에서 서버 연결 확인:

```bash
python3 ~/jetson_edge_client.py health --server-url http://192.168.55.100:8000
```

Jetson에서 단일 이벤트 전송 확인:

```bash
python3 ~/jetson_edge_client.py once --event danger --server-url http://192.168.55.100:8000
python3 ~/jetson_edge_client.py once --event normal --server-url http://192.168.55.100:8000
```

Jetson AI 추론 실행 전 CUDA 라이브러리 경로가 필요한 경우:

```bash
export LD_LIBRARY_PATH="$HOME/.local/lib/python3.10/site-packages/nvidia/cu12/lib:$LD_LIBRARY_PATH"
```

실시간 추론 스크립트는 낙상 확률이 임계값 이상이면 `danger`, 이후 확률이 낮아지면 `normal`을 다시 서버로 보내야 한다. 그래야 앱 화면이 낙상 이후 정상 상태로 복귀한다.

## Jetson에서 서버 주소 정하기

Jetson과 서버가 같은 장치에서 실행되면:

```text
http://127.0.0.1:8000
```

Jetson이 서버 PC와 다른 장치라면:

```text
http://<서버_PC_IP>:8000
```

예:

```text
http://172.20.10.2:8000
```

## 서버 연결 확인

Jetson에서:

```bash
cd Hanium_app/server
python3 jetson_edge_client.py health --server-url http://172.20.10.2:8000
```

## mock 시나리오 실행

Jetson에서:

```bash
cd Hanium_app/server
SERVER_URL=http://172.20.10.2:8000 ./run_jetson_edge_mock.sh
```

또는 직접:

```bash
python3 jetson_edge_client.py sequence --server-url http://172.20.10.2:8000 --loop
```

전송 흐름:

```text
정상 -> 이동 중 -> 현관 접근 -> 장시간 무반응 -> 낙상 의심 -> 정상 복귀
```

앱의 `집 안` 화면과 관리자 웹에서 위치/상태가 바뀌는지 확인하면 됩니다.

## 단일 이벤트 전송

낙상 의심:

```bash
python3 jetson_edge_client.py once \
  --server-url http://172.20.10.2:8000 \
  --event danger
```

현관 접근:

```bash
python3 jetson_edge_client.py once \
  --server-url http://172.20.10.2:8000 \
  --event out
```

장시간 무반응:

```bash
python3 jetson_edge_client.py once \
  --server-url http://172.20.10.2:8000 \
  --event still
```

## 실시간 AI 추론 결과 연결 (edge_ai → 서버)

`edge_ai/jetson/run_live.sh`가 실행 중이면 추론 결과가 `edge_ai/runtime/latest_status.json`에 계속 갱신됩니다(형식: `hanium.ruview.live-status.v2`). `live-status` 모드가 이 결과를 읽어 서버의 `/sensor/update` 형식으로 바꿔 보냅니다.

```bash
# Jetson 안에서: 결과 파일을 1초마다 읽어 전송
python3 jetson_edge_client.py live-status \
  --status-file ~/26_HS022/edge_ai/runtime/latest_status.json \
  --server-url http://192.168.55.100:8000

# 노트북에서: Jetson의 상태 API(status_api.py, 기본 :8080)를 읽어 전송
python3 jetson_edge_client.py live-status \
  --status-url http://192.168.55.1:8080/status \
  --server-url http://127.0.0.1:8000

# 파이프로 바로 연결 (run_live.sh 로그 중 LIVE_STATUS= 줄만 골라 전송)
./edge_ai/jetson/run_live.sh | python3 jetson_edge_client.py stdin-json --server-url http://192.168.55.100:8000
```

변환 규칙:

| edge_ai 출력 | 서버로 보내는 값 |
|---|---|
| `fall.alarm == true` (상태기계 CONFIRMED) | `status: danger`, `pose: lying` |
| 그 외 | `status: normal`, `activity`에 따라 `pose`(walking / sitting / lying / standing) |
| `health.respiratory.breathing_rate_bpm` (신뢰 가능할 때만 값 존재) | `breathingRate`, `breathingConfidence` — 값이 없으면 보내지 않음 |
| 위치 | 모델은 방 단위로 판단하고 좌표를 추정하지 않으므로, 센서가 설치된 방의 도면 좌표(`--room-x`, `--room-y`)를 사용 |

## 그 밖의 AI 출력 연결 (단순 JSON)

다른 추론 스크립트가 아래처럼 JSON을 출력하면 `stdin-json`으로도 연결할 수 있습니다.

```json
{"label":"fall","confidence":0.92,"x":0.36,"y":0.45}
```

```bash
python3 ai_inference.py | python3 jetson_edge_client.py stdin-json --server-url http://172.20.10.2:8000
```

지원 label:

```text
normal, safe, standing -> normal
walking, out, entrance -> out
still, sitting, no_motion -> still
fall, fallen, lying, danger -> danger
```

## 서버로 보내는 데이터 형식

```json
{
  "x": 0.36,
  "y": 0.45,
  "status": "danger",
  "pose": "lying",
  "confidence": 0.91,
  "breathingRate": 24.1,
  "breathingConfidence": 0.84,
  "source": "jetson_orin",
  "holdMs": 60000
}
```

| 필드 | 의미 |
|---|---|
| `x`, `y` | 집 도면 기준 좌표, 0.0~1.0 |
| `status` | `normal`, `out`, `still`, `danger` |
| `pose` | `standing`, `walking`, `sitting`, `lying` |
| `confidence` | AI/센서 판단 신뢰도 |
| `breathingRate` | 호흡수 참고값, 분당 호흡 횟수 |
| `breathingConfidence` | 호흡 신호 판단 확실도, 0.0~1.0 |
| `source` | 데이터 출처. 기본값 `jetson_orin` |
| `holdMs` | 서버가 해당 상태를 유지할 시간 |

## 발표/개발 설명

> Jetson Orin에는 센서/AI 결과를 서버로 보내는 edge client를 구성했습니다. `live-status` 모드는 실제 WiFi CSI 추론 결과(낙상 상태기계, 호흡 추정)를 서버로 전달하고, `sequence`·`once` 모드는 센서 없이 발표·테스트할 때 정상, 현관 접근, 장시간 무반응, 낙상 의심 시나리오를 재현합니다.
