# app — Flutter 보호자/피보호자 앱 + 로컬 서버

WiFi CSI 엣지 추론 결과를 받아 보호자에게 실시간 상태·위치·위험 알림을 보여주는 Flutter 앱과, Jetson과 앱 사이를 잇는 로컬 서버입니다. (구 `Hanium_app` 저장소)

## 구성

| 경로 | 역할 |
|---|---|
| `lib/features/dashboard` | 보호자 홈 요약 (정상 / 주의 / 즉각 조치 필요) |
| `lib/features/home_map` | 집 도면 기반 위치·이동 경로 표시 |
| `lib/features/alerts` | 안전 알림 목록, 상황 재연, 위험 대응 |
| `lib/features/care_recipient` | 피보호자 모드 (내 상태, 위치 공유 ON/OFF, 호흡 리듬) |
| `lib/features/settings` | 알림 기준, 도면 표시, 보호자·응급 정보 관리 |
| `lib/core` | 상태 모델, WebSocket·REST 저장소, FCM 알림 서비스 |
| `server/dev_mock_server.js` | Node.js 로컬 서버 (REST + `WS /ws/location` + FCM + 관리자 웹 `/admin`) |
| `server/jetson_edge_client.py` | 엣지 추론 결과를 서버로 전달 (`live-status`), 발표용 시나리오 재현 (`sequence`, `once`) |
| `server/main.py`, `routers/`, `services/` | 초기 FastAPI 프로토타입 (현재 미사용) |

## 실행

```powershell
# 1) 서버
cd server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd          # http://127.0.0.1:8000/admin

# 2) 앱
cd ..
flutter pub get
flutter run --dart-define=SERVER_URL=http://<서버 IP>:8000 --dart-define=DEMO_MODE=false
```

자세한 API와 시연 절차는 [`server/README.md`](server/README.md), [`server/DEMO_SCRIPT.md`](server/DEMO_SCRIPT.md), [`server/JETSON_EDGE_CLIENT.md`](server/JETSON_EDGE_CLIENT.md)를 참고하세요.

> 로그인 화면은 역할 선택용이며 인증은 구현되어 있지 않습니다. 로컬 서버도 같은 네트워크 안의 시연을 전제로 하여 API 인증이 없습니다.
