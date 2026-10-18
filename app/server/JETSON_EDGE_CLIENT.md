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
cd app
.\server\run_mock_server_node.cmd
```

관리자 페이지:

```text
http://127.0.0.1:8000/admin
```

## 현재 권장 연결

현재 추론기는 `latest_status.json`의 낙상 상태기계 결과를 전달하는 `live-status` 모드를 사용합니다. 낙상 확률 하나로 위험/정상을 전환하는 예전 연결 설명과 구분합니다.

USB-C 연결에서 사용했던 `192.168.55.1`(Jetson), `192.168.55.100`(PC)은 예시입니다. 실행 장치에서 실제 IP를 확인하고 [실행 안내](../../docs/RUNBOOK.md)의 주소·작업 폴더를 적용합니다.

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
cd app/server
python3 jetson_edge_client.py health --server-url http://172.20.10.2:8000
```

## mock 시나리오 실행

Jetson에서:

```bash
cd app/server
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
./edge_ai/jetson/run_live.sh | python3 app/server/jetson_edge_client.py stdin-json --server-url http://192.168.55.100:8000
```

변환 규칙:

| edge_ai 출력 | 서버로 보내는 값 |
|---|---|
| `fall.alarm == true` (상태기계 CONFIRMED) | `status: danger`, `pose: lying` |
| 그 외 | 현재는 `status: normal`로 전달. `unknown`·`model_unavailable` 구분이 앱까지 유지되지 않는 보완 과제 있음 |
| `health.respiratory.breathing_rate_bpm` | 연결 클라이언트는 값이 없으면 생략. 서버는 누락값을 예시값으로 보충하므로 화면 실측 여부를 별도 확인 |
| 위치 | 모델은 방 이름·좌표를 출력하지 않음. 운영자가 지정한 설치 위치(`--room-x`, `--room-y`)를 사용 |

현재 `live-status`는 `unix_time` 변경 여부를 확인하지만 오래된 레코드의 나이를 검사하지 않습니다. 모델 미설치, 센서 단절, 예시 호흡값 처리에 관한 [확인 사항](../../docs/IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)을 함께 확인하세요.

## 그 밖의 AI 출력 연결 (단순 JSON)

다른 추론 스크립트가 아래처럼 JSON을 출력하면 `stdin-json`으로도 연결할 수 있습니다.

```json
{"label":"fall","confidence":0.92,"x":0.36,"y":0.45}
```

```bash
python3 ai_inference.py | python3 jetson_edge_client.py stdin-json --server-url http://172.20.10.2:8000
```

이 단순 JSON 경로는 `lying`을 `danger`로 매핑합니다. 현재 낙상 상태기계와 동일한 판정 규칙이 아니므로 실제 추론 연결에는 `live-status`를 사용합니다.

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
