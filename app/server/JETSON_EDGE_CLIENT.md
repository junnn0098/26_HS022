# Jetson 엣지 클라이언트

`jetson_edge_client.py`는 Jetson의 낙상 추론 결과를 로컬 서버로 전달하고, 센서 없이 발표할 때는 미리 정한 시나리오를 보냅니다.

```text
Jetson (edge_ai 추론) -> jetson_edge_client.py -> POST /sensor/update -> local_server.js -> WebSocket -> Flutter 앱 / 관리자 웹
```

| 파일 | 용도 |
|---|---|
| `jetson_edge_client.py` | `health`, `live-status`, `stdin-json`, `once`, `sequence`, `heartbeat` 모드 |
| `run_jetson_edge_mock.sh` / `.cmd` | `sequence --loop` 시연 실행 (Jetson·Linux / Windows) |

| 모드 | 보내는 값 | `source` |
|---|---|---|
| `live-status`, `stdin-json` | 실제 엣지 추론 결과 | `jetson_orin` (앱 'Jetson 실시간 추론') |
| `once`, `sequence`, `heartbeat` | 미리 정한 예시값 | `scripted_demo` (앱 '시연 입력' 칩) |

## 서버 먼저 실행

개발 PC 또는 발표 PC에서 서버를 켭니다(`app` 폴더 기준). 관리자 페이지는 `http://127.0.0.1:8000/admin`입니다.

```powershell
cd app
$env:REAL_SENSOR_ONLY="true"
.\server\run_mock_server_node.cmd
```

서버를 `HANIUM_API_TOKEN`과 함께 실행했다면 클라이언트에도 같은 환경 변수(또는 `--server-token`)를 지정합니다. `live-status`의 `--token`은 Jetson 상태 API(`RUVIEW_API_TOKEN`)용으로 별개입니다.

## 서버 주소와 연결 확인

Jetson과 서버가 같은 장치면 `http://127.0.0.1:8000`, 다른 장치면 `http://<서버_PC_IP>:8000`을 씁니다. USB-C 연결에서 사용한 `192.168.55.1`(Jetson), `192.168.55.100`(PC)과 아래의 `172.20.10.2`는 예시이므로 실행 장치의 실제 IP로 바꿉니다([실행 안내](../../docs/RUNBOOK.md)).

```bash
cd app/server
python3 jetson_edge_client.py health --server-url http://172.20.10.2:8000
```

## 실시간 추론 결과 연결 (live-status)

`edge_ai/jetson/run_live.sh`가 실행 중이면 추론 결과가 `edge_ai/runtime/latest_status.json`에 계속 갱신됩니다(형식: `hanium.ruview.live-status.v2`). `live-status` 모드는 이 낙상 상태기계 결과를 읽어 `/sensor/update` 형식으로 보냅니다.

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
| `fall.state`가 `normal`·`fall_candidate`·`post_fall_check`·`recovered` | `status: normal` |
| `fall.state`가 `model_unavailable`·`unknown`·그 밖의 값이거나 없음 | `status: unknown`(판단 불가). 정상으로 전달하지 않음 |
| `health.respiratory.breathing_rate_bpm` | 값이 없으면 생략. 서버도 채우지 않고 `breathingRate: null`로 전달(앱 '측정 대기') |
| 위치 | 모델은 방 이름·좌표를 출력하지 않음. 운영자가 지정한 설치 위치(`--room-x`, `--room-y`)를 사용 |
| `source` | `jetson_orin` |

`live-status`는 `unix_time`이 `--max-age`(기본 10초)보다 오래되었거나 없는 레코드를 전달하지 않고, 대신 `status: unknown`을 한 번 보내 `[stale]` 경고를 출력합니다(`--once`에서는 종료 코드 1). Jetson과 PC의 시계가 다르면 시계를 맞추거나 `--max-age 0`으로 검사를 끕니다. 모델 미설치와 센서 단절에 관한 [확인 사항](../../docs/IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)을 함께 확인하세요.

v2 낙상 가중치는 다음 데이터 수집 후 학습할 예정이라 저장소에 없습니다. 가중치 없이 `run_live.sh`를 실행하면 `fall.state`가 `model_unavailable`이므로 서버·앱에는 `unknown`('확인 필요')으로 전달됩니다. 이 경로는 연결 방식이며, 모델의 실측 성능은 [실측 데이터 검증 결과](../../experiments/MEASURED_RESULTS.md)를 기준으로 설명합니다.

## 그 밖의 AI 출력 연결 (단순 JSON)

다른 추론 스크립트가 아래처럼 JSON을 출력하면 `stdin-json`으로도 연결할 수 있습니다.

```json
{"label":"fall","confidence":0.92,"x":0.36,"y":0.45}
```

```bash
python3 ai_inference.py | python3 jetson_edge_client.py stdin-json --server-url http://172.20.10.2:8000
```

이 단순 JSON 경로는 `lying`을 `danger`로 매핑합니다. 낙상 상태기계와 같은 판정 규칙이 아니므로 실제 추론 연결에는 `live-status`를 사용합니다. 아래 목록에 없는 label은 `unknown`으로, 호흡값이 없으면 생략해 전달합니다.

```text
normal, safe, standing -> normal
walk, walking, out, entrance -> out
still, sitting, no_motion -> still
fall, fallen, lying, danger -> danger
```

## 센서 없이 시나리오 보내기

`sequence`·`once`·`heartbeat`는 위치·신뢰도·호흡수 모두 미리 정한 예시값을 보냅니다. 센서 기반 낙상 감지를 보여주는 명령이 아닙니다.

```bash
cd app/server
SERVER_URL=http://172.20.10.2:8000 ./run_jetson_edge_mock.sh
# 또는
python3 jetson_edge_client.py sequence --server-url http://172.20.10.2:8000 --loop
```

`sequence` 순서: 정상 -> 이동 중 -> 현관 접근 -> 장시간 무반응 -> 낙상 의심 -> 정상 복귀

단일 이벤트는 `once --event <normal|out|still|danger>`로 보냅니다.

```bash
python3 jetson_edge_client.py once --server-url http://172.20.10.2:8000 --event danger   # 낙상 의심
python3 jetson_edge_client.py once --server-url http://172.20.10.2:8000 --event out      # 현관 접근
python3 jetson_edge_client.py once --server-url http://172.20.10.2:8000 --event still    # 장시간 무반응
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

필드 설명은 [센서 입력 형식](SENSOR_INTEGRATION.md)에 있습니다.
