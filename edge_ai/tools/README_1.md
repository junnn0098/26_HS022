# tools — 실시간 CSI 파형 시각화 · 시연 로그 도구

ESP32-S3 수신 노드가 보내는 CSI를 **실시간으로 눈으로 확인**하고, **시연 영상을 녹화**하기 위한 보조 도구 모음입니다. 낙상 추론은 하지 않고, 검증된 파서(`hanium_fall_v2.adr018`)로 받은 "날 것"의 진폭만 다룹니다. 모델 학습 전에도 센서→젯슨 데이터 흐름을 바로 확인할 수 있습니다.

> ⚠️ 아직 임시(초안) 버전입니다. 데모·디버깅용으로 먼저 올려두고, 이후 완성본으로 교체할 예정입니다.

| 파일 | 역할 |
|---|---|
| `csi_ws_bridge.py` | 젯슨에서 ESP 4대 UDP(ADR-018, 5005) 수신 → 노드별 LLTF 64 진폭 계산 → WebSocket(8765)로 브로드캐스트 |
| `csi_dashboard.html` | 4개 노드의 CSI 진폭 파형을 실시간으로 그리는 웹 대시보드 (브리지의 WebSocket에 연결) |
| `demo_log.py` | 시연 영상용 — 노드별 pps·평균 진폭·움직임 강도를 0.5초마다 터미널에 출력하고 `logs/`에 저장 |
| `play_log.py` | 저장된 로그를 실시간처럼 한 줄씩 재생 (영상 녹화용, 색상 표시) |

## 실행 위치

스크립트들은 저장소의 `hanium_fall_v2` 파서를 import 하므로, **`edge_ai/` 폴더에서** 실행합니다.

```bash
cd edge_ai
pip install --break-system-packages websockets numpy   # 최초 1회
```

## 1) 실시간 파형 보기

젯슨에서 브리지 실행:

```bash
python3 tools/csi_ws_bridge.py --udp-port 5005 --ws-port 8765 --nodes 1,2,3,4
```

`tools/csi_dashboard.html` 상단의 `JETSON_WS_URL`을 젯슨 IP로 맞춘 뒤 브라우저로 엽니다:

```js
const JETSON_WS_URL = "ws://<젯슨_IP>:8765";
```

노드가 일정 시간(`--stale-seconds`, 기본 1.5초) 동안 프레임을 안 주면 대시보드에서 "끊김"으로 표시됩니다.

## 2) 시연 로그 녹화 / 재생

```bash
# 평상시 녹화
python3 tools/demo_log.py --label normal

# 낙상 재연하며 녹화 (안전 매트 위)
python3 tools/demo_log.py --label fall --alert 40 --nodes 1,2,3,4

# 저장된 로그를 영상용으로 재생
python3 tools/play_log.py logs/demo_fall_YYYYMMDD_HHMMSS.log --delay 0.5
```

`demo_log.py`의 '상태'는 AI 낙상 판정이 아니라 **움직임 강도 임계값** 기반 표시입니다(모델 학습 전 시연용). 평상시엔 낮고, 낙상처럼 급격한 움직임이 있으면 수치가 확 튑니다.
