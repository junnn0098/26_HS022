# Hanium FastAPI Server

WiFi CSI 기반 어르신 안전 모니터링 앱의 개발용 FastAPI 서버입니다.

## 실행

FastAPI 패키지를 설치할 수 있으면 아래 방식으로 실행합니다.

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_fastApi
python -m venv .venv
.\.venv\Scripts\activate
pip install -r requirements.txt
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

현재 Codex 환경처럼 pip 설치가 막힌 경우에는 외부 패키지 없는 개발용 서버를 사용합니다.

```powershell
C:\Users\juhwan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe dev_mock_server.py
```

Node.js 개발용 서버도 제공합니다. Python/FastAPI 설치 없이 실행할 수 있습니다.

```powershell
.\run_mock_server_node.cmd
```

지금 앱 개발 단계에서는 위 Node.js mock 서버를 먼저 추천합니다. 설정값, 보호자, 알림은
`dev_state.json`에 저장되므로 서버를 껐다 켜도 유지됩니다.

Android 에뮬레이터에서 PC 서버로 붙을 때는 앱의 서버 주소를 `http://10.0.2.2:8000`으로 사용합니다.

브라우저에서 시연용 관리자 콘솔을 열 수 있습니다.

```powershell
start http://127.0.0.1:8000/admin
```

추가 문서:

- `SENSOR_INTEGRATION.md` : 실제 WiFi CSI/Jetson 센서 연동 요청 형식
- `DEMO_SCRIPT.md` : 발표 시연 순서와 장애 대응 체크리스트
- `demo_sensor_client.py` : 센서 입력을 흉내 내는 Python 예제

## 현재 앱과 연결된 개발용 API

- `GET /health` : 서버 실행 상태 확인
- `GET /admin` : 시연용 관리자 콘솔
- `GET /state` : 보호자, 설정, 알림 전체 상태 확인
- `GET /location/latest` : 최근 위치/방/자세/위험 상태 조회
- `POST /sensor/update` : 외부 센서 또는 관리자 콘솔에서 위치/상태 입력
- `POST /sensor/reset` : 수동 센서 입력 해제 후 mock 위치로 복귀
- `GET /alerts` : 알림 목록 조회
- `POST /alerts/resolve` : 위험 알림 확인 완료 처리
- `POST /demo/reset` : 발표/시연 상태 초기화
- `GET /settings` : 설정 조회
- `POST /settings` : 설정 저장
- `GET /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 조회
- `POST /emergency-info` : 119 신고용 집 주소/출입/의료 참고 정보 저장
- `GET /guardians` : 보호자 목록 조회
- `POST /guardians` : 보호자 추가
- `POST /guardians/update` : 보호자 정보 수정
- `POST /guardians/delete` : 보호자 삭제
- `POST /device/register` : 앱 알림 토큰 등록
- `POST /alarm/test` : 테스트 알림 요청
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
서버가 `x`, `y` 좌표를 기준으로 거실/주방/침실/욕실/현관을 자동 계산합니다.
