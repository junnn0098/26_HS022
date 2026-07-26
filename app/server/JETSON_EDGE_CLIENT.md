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
SSH 계정 예시: junwon@192.168.55.1
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
python3 ~/jetson_edge_client.py --server-url http://192.168.55.100:8000 health
```

Jetson에서 단일 이벤트 전송 확인:

```bash
python3 ~/jetson_edge_client.py --server-url http://192.168.55.100:8000 once --event danger
python3 ~/jetson_edge_client.py --server-url http://192.168.55.100:8000 once --event normal
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

## AI 모델 출력과 연결

나중에 AI 모델이 아래처럼 JSON을 출력하게 만들면:

```json
{"label":"fall","confidence":0.92,"x":0.36,"y":0.45}
```

아래처럼 연결할 수 있습니다.

```bash
python3 ai_inference.py | python3 jetson_edge_client.py stdin-json --server-url http://172.20.10.2:8000
```

`stdin-json` 모드는 한 줄에 JSON 하나씩 읽어서 서버로 전송합니다.

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
| `source` | 데이터 출처. 기본값 `jetson_orin` |
| `holdMs` | 서버가 해당 상태를 유지할 시간 |

## 발표/개발 설명

> Jetson Orin에는 센서/AI 결과를 서버로 보내는 edge client를 구성했습니다. 현재는 mock 시나리오로 정상, 현관 접근, 장시간 무반응, 낙상 의심을 서버에 전송할 수 있고, 이후 실제 WiFi CSI 1D-CNN 모델 출력값을 같은 JSON 형식으로 연결하면 앱 화면과 보호자 알림에 반영되는 구조입니다.
