# WiFi CSI / Jetson 센서 연동 규격

이 문서는 실제 센서 장비가 서버로 어떤 데이터를 보내야 하는지 정리한 규격입니다.
현재 앱은 아래 API로 들어온 위치를 실시간 도면에 반영합니다.

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

이 API로 새 위치를 보내면 저장만 하는 것이 아니라, WebSocket으로 연결된 앱 화면에도 즉시 전달됩니다. 그래서 실제 Jetson/CSI 분석 결과가 들어오면 보호자 앱의 도면과 알림이 바로 갱신되는 흐름으로 시연할 수 있습니다.

권장 요청 본문:

```json
{
  "x": 0.76,
  "y": 0.68,
  "status": "out",
  "pose": "walking",
  "confidence": 0.88,
  "source": "jetson",
  "holdMs": 60000
}
```

## 필드 설명

| 필드 | 타입 | 필수 | 설명 |
|---|---:|---:|---|
| `x` | number | 예 | 집 도면 기준 X 좌표, 0.0~1.0 |
| `y` | number | 예 | 집 도면 기준 Y 좌표, 0.0~1.0 |
| `status` | string | 예 | `normal`, `out`, `danger`, `still` |
| `pose` | string | 아니오 | `standing`, `walking`, `lying`, `sitting` |
| `confidence` | number | 아니오 | 추정 신뢰도, 0.0~1.0 |
| `source` | string | 아니오 | `jetson`, `admin`, `test` 등 |
| `holdMs` | number | 아니오 | 이 수동 위치를 유지할 시간(ms) |

`room`은 보내지 않는 것을 추천합니다. 서버가 `x`, `y` 좌표를 기준으로 자동 계산합니다.
PowerShell/터미널 인코딩 문제로 `현관` 같은 한글이 `??`로 깨질 수 있기 때문입니다.

## 상태값 의미

| status | 의미 | 앱 표시 |
|---|---|---|
| `normal` | 평소와 유사한 움직임 | 초록, 이상 징후 없음 |
| `out` | 현관/외출 가능성 | 노랑, 확인 필요 |
| `danger` | 낙상 의심 | 빨강, 긴급 확인 |
| `still` | 장시간 무반응 | 노랑, 주의 확인 |

## PowerShell 테스트

현관 접근:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.76,"y":0.68,"status":"out","pose":"walking","confidence":0.88,"source":"test","holdMs":60000}'
```

낙상 의심:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.36,"y":0.45,"status":"danger","pose":"lying","confidence":0.91,"source":"test","holdMs":60000}'
```

장시간 무반응:

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:8000/sensor/update -ContentType 'application/json' -Body '{"x":0.31,"y":0.68,"status":"still","pose":"sitting","confidence":0.83,"source":"test","holdMs":60000}'
```

## Python 예시

`demo_sensor_client.py`를 실행하면 정상 → 현관 → 낙상 → 장시간 무반응 시나리오를 순서대로 서버에 보냅니다.

```powershell
python demo_sensor_client.py
```

Python 명령이 없다면 Codex 번들 Python을 사용할 수 있습니다.

```powershell
C:\Users\juhwan\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe demo_sensor_client.py
```
