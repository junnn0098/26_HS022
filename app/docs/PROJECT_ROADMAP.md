# 앱 로드맵

보호자가 기술 정보를 해석하지 않아도 "지금 안전한지", "어디에서 어떤 일이 있었는지", "위험하면 무엇을 해야 하는지"를 바로 알 수 있게 하는 것이 앱의 목표입니다.

## 구현한 것

| 영역 | 내용 |
|---|---|
| 실행 | 서버·센서·Firebase가 없어도 첫 화면까지 실행(`test/widget_test.dart`). 로컬 서버는 `run_mock_server_node.cmd` 한 명령으로 실행 |
| 상태 표시 | 정상·주의·위험·확인 필요 4단계. 입력이 없거나 판단 불가(`unknown`)면 정상으로 표시하지 않음. 호흡값이 없으면 '측정 대기' |
| 집 안 화면 | 집 도면 위 위치와 최근 이동 경로(WebSocket) |
| 알림·대응 | 알림 목록, 위험 시 어르신·119 전화 앱 연결과 119 전달 내용 복사, 확인 완료 처리 |
| 설정 | 알림 기준·도면 표시·위치 공유를 서버에 저장(`/settings`), 보호 대상·보호자·119 신고 정보 표시 |
| 엣지 연결 | `jetson_edge_client.py live-status`로 Jetson 추론 결과 전달(source `jetson_orin`), 10초 넘은 결과는 `unknown` |
| 시연 구분 | 시연 스크립트 입력에 '시연 입력' 칩, 관리자 페이지 '발표 리모컨', 앱 시연 버튼은 `DEMO_MODE=true`일 때만 표시 |
| 개인정보·보안 | 위치 공유 OFF를 REST·WebSocket·알림에 적용, 출입 비밀번호 미저장, 선택적 API 토큰(`HANIUM_API_TOKEN` / `API_TOKEN`) |

서버는 Node.js `local_server.js` 하나로 정리했습니다. 초기 FastAPI 서버는 `server/legacy_fastapi_prototype/`로 옮겼으며 더 개발하지 않습니다.

## 향후 계획

1. 다양한 사용자·공간에서 CSI 데이터를 추가로 수집해 새로운 환경에서의 낙상 감지 성능을 고도화합니다([실측 데이터 학습 결과](../../experiments/MEASURED_RESULTS.md)).
2. 엣지 결과 전달 범위를 '현관 접근'·'장시간 무반응' 상태까지 확대합니다.
3. Firebase 프로젝트 설정(`google-services.json`)을 적용한 Android 단말 기준으로 FCM 푸시와 전화 연결 흐름을 고도화합니다.
4. 응급 정보 접근 권한과 API 토큰 관리 방식을 고도화합니다.
