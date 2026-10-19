# WiFi CSI / Jetson 센서 연동 규격

센서·엣지 장비가 로컬 서버(`local_server.js`)로 보내는 데이터 규격입니다. 앱은 이 API로 들어온 상태와 위치를 실시간 도면에 반영합니다.

## 서버 주소

개발 PC에서 직접 호출할 때:

```text
http://127.0.0.1:8000
```

Android 에뮬레이터 안의 앱에서 PC 서버로 붙을 때:

```text
http://10.0.2.2:8000
```

실제 Jetson/외부 장비에서 보낼 때는 PC의 같은 네트워크 IP를 사용합니다.

```text
http://<PC-IP>:8000/sensor/update
```

## 위치 업데이트 API

```http
POST /sensor/update
Content-Type: application/json
```

`Content-Type: application/json`이 아니면 415로 거절합니다. 서버를 `HANIUM_API_TOKEN`과 함께 실행했다면 `Authorization: Bearer <토큰>` 헤더도 필요합니다.

보낸 값은 저장과 동시에 WebSocket으로 연결된 앱과 관리자 화면에 전달됩니다. 엣지 추론 결과는 `jetson_edge_client.py live-status`가 이 형식으로 바꿔 보냅니다([변환 규칙](JETSON_EDGE_CLIENT.md#실시간-추론-결과-연결-live-status)).

권장 요청 본문:

```json
{
  "x": 0.76,
  "y": 0.68,
  "status": "out",
  "pose": "walking",
  "confidence": 0.88,
  "breathingRate": 18.4,
  "breathingConfidence": 0.84,
  "source": "jetson_orin",
  "holdMs": 60000
}
```

## 필드 설명

| 필드 | 타입 | 필수 | 설명 |
|---|---:|---:|---|
| `x` | number | 예 | 집 도면 기준 X 좌표, 0.0–1.0 |
| `y` | number | 예 | 집 도면 기준 Y 좌표, 0.0–1.0 |
| `status` | string | 예 | `normal`, `out`, `danger`, `still`, `unknown` |
| `pose` | string | 아니오 | `standing`, `walking`, `lying`, `sitting` |
| `confidence` | number | 아니오 | 추정 신뢰도, 0.0–1.0 |
| `breathingRate` | number | 아니오 | 호흡수 참고값, 분당 호흡 횟수. `respirationRate`, `breathRate`도 허용. 없으면 서버도 `null`로 전달 |
| `breathingConfidence` | number | 아니오 | 호흡 신호 판단 확실도, 0.0–1.0. `respirationConfidence`도 허용 |
| `source` | string | 아니오 | `jetson_orin`(실제 엣지 추론), `scripted_demo`(시연 스크립트), `admin`, `test` 등. 없으면 `unknown` |
| `holdMs` | number | 아니오 | 이 수동 위치를 유지할 시간(ms) |

`room`은 보내지 않는 것을 추천합니다. 서버가 `x`, `y` 좌표를 기준으로 자동 계산합니다.
PowerShell/터미널 인코딩 문제로 `현관` 같은 한글이 `??`로 깨질 수 있기 때문입니다.

## 상태값 의미

| status | 의미 | 앱 표시 |
|---|---|---|
| `normal` | 평소와 유사한 움직임 | 초록 '정상' |
| `out` | 현관/외출 가능성 | 주황 '주의', 알림 생성 |
| `still` | 장시간 무반응 | 주황 '주의', 알림 생성 |
| `danger` | 낙상 의심 | 빨강 '위험', 알림 생성 |
| `unknown` | 판단 불가 (모델 미설치, 품질 저하, 오래된 결과, 인식하지 못한 상태값) | 회색 '확인 필요'. 정상으로 바꾸지 않고 알림도 만들지 않음 |

## PowerShell 테스트

아래 명령은 미리 정한 예시값을 보내므로 `source`를 `scripted_demo`로 둡니다. 앱에는 '시연 입력' 칩이 붙습니다.

현관 접근:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.76,"y":0.68,"status":"out","pose":"walking","confidence":0.88,"breathingRate":18.4,"breathingConfidence":0.84,"source":"scripted_demo","holdMs":60000}'
```

낙상 의심:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.36,"y":0.45,"status":"danger","pose":"lying","confidence":0.91,"breathingRate":24.1,"breathingConfidence":0.84,"source":"scripted_demo","holdMs":60000}'
```

장시간 무반응:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.31,"y":0.68,"status":"still","pose":"sitting","confidence":0.83,"breathingRate":13.6,"breathingConfidence":0.78,"source":"scripted_demo","holdMs":60000}'
```

## Python 예시

`demo_sensor_client.py`(Python 3 표준 라이브러리만 사용)를 실행하면 정상 → 현관 → 낙상 → 장시간 무반응 시나리오를 `source: scripted_demo`로 순서대로 서버에 보냅니다. `HANIUM_API_TOKEN` 환경 변수가 있으면 같은 토큰을 함께 보냅니다.

```powershell
python demo_sensor_client.py
```
