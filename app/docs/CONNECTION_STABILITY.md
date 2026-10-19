# 앱-서버 연결 체크리스트

발표 전에 앱과 로컬 서버(`local_server.js`) 연결을 확인하는 순서입니다. 전체 실행 순서는 [실행 안내](../../docs/RUNBOOK.md), 발표 진행은 [시연 스크립트](../server/DEMO_SCRIPT.md)에 있습니다.

## 1. 서버 켜기

```powershell
cd <작업폴더>\app\server
$env:REAL_SENSOR_ONLY="true"
.\run_mock_server_node.cmd
```

서버 창에서 다음을 확인합니다.

- 관리자 페이지 `http://127.0.0.1:8000/admin`, 에뮬레이터 앱 주소 `http://10.0.2.2:8000`
- `Mode: REAL_SENSOR_ONLY=true -> mock motion OFF` (모의 이동·모의 낙상 꺼짐)
- 기본 바인딩 `0.0.0.0` 경고. 같은 PC와 에뮬레이터만 쓰면 `$env:HOST="127.0.0.1"`로 실행합니다. 실제 휴대폰·Jetson을 연결할 때는 `HOST`를 지정하지 않습니다

## 2. 서버 상태 확인

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:8000/location/latest
```

`ok : True`와 `location` 값이 나오면 서버는 정상입니다. 서버에 `HANIUM_API_TOKEN`을 설정했다면 `/location/latest`에는 `-Headers @{ Authorization = 'Bearer <토큰>' }`이 필요합니다.

## 3. 앱 실행

```powershell
cd <작업폴더>\app
.\run_emulator_user_mode.cmd      # 또는 직접:
flutter run -d emulator-5554 --dart-define=SERVER_URL=http://10.0.2.2:8000 --dart-define=DEMO_MODE=false
```

설정 화면의 '상황 재연' 시연 버튼이 필요하면 `.\run_emulator_local.cmd`(DEMO_MODE=true)를 씁니다. 토큰을 설정한 서버라면 `--dart-define=API_TOKEN=<같은 토큰>`을 추가합니다.

## 4. 앱에서 확인할 표시

- 설정 화면 '앱 연결 상태' 카드의 서버 연결이 '준비됨'
- 홈에 '마지막 상태를 보여주는 중이에요' 카드가 없음 (연결이 끊기면 이 카드가 나타남)
- 서버 데이터를 받기 전이나 초기화 직후에는 회색 '확인 필요'가 정상 동작입니다

서버를 잠깐 껐다 켜도 앱은 멈추지 않고, 서버가 다시 켜지면 자동으로 다시 연결합니다.

## 5. 관리자 페이지로 연결 확인

1. 관리자 페이지에서 `시연 상태 초기화` 클릭
2. 도면을 클릭하거나 '시연 버튼'의 `현관`, `장시간 무반응`, `낙상 의심 발생` 클릭
3. 앱 도면의 위치와 알림이 바뀌는지 확인 (출처 표시: '관리자 수동 입력')

## 6. 실제 Android 휴대폰

에뮬레이터는 `10.0.2.2`를 쓰지만, 실제 휴대폰은 노트북의 Wi-Fi IPv4 주소(`ipconfig`로 확인)를 씁니다. 휴대폰과 노트북은 같은 Wi-Fi에 있어야 합니다.

```powershell
flutter run --dart-define=SERVER_URL=http://192.168.0.15:8000 --dart-define=DEMO_MODE=false
```

`run_real_phone_example.cmd`의 `YOUR_PC_WIFI_IP`를 바꿔 실행해도 됩니다.

## 7. 문제가 생겼을 때

| 증상 | 확인 |
|---|---|
| 앱이 계속 '마지막 상태를 보여주는 중이에요' | 서버 창이 켜져 있는지, `/health`가 열리는지, `SERVER_URL`(에뮬레이터 `10.0.2.2`, 휴대폰 노트북 IP), 서버를 `HOST=127.0.0.1`로 띄워 휴대폰 접속을 막지 않았는지 |
| 연결은 되는데 상태·알림을 못 읽음 | 서버의 `HANIUM_API_TOKEN`과 앱의 `API_TOKEN`이 같은지 |
| 관리자 페이지는 바뀌는데 앱은 그대로 | 앱 완전 종료 후 재실행, 서버 창 오류 확인, `시연 상태 초기화` |
| 갑자기 낙상 알림이 생김 | `REAL_SENSOR_ONLY=true` 없이 서버를 띄워 모의 낙상이 생성된 경우. 서버를 다시 실행 |
| 포트 8000 사용 중 | 이미 켜진 서버 창을 닫고 다시 실행 |
