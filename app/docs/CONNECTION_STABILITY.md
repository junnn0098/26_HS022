# Hanium 발표용 앱-서버 연결 체크리스트

이 문서는 발표 전에 앱과 서버 연결을 안정적으로 확인하기 위한 순서입니다.

## 1. 서버 켜기

PowerShell에서 실행:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_fastApi
.\run_mock_server_node.cmd
```

서버 창에 아래 주소가 보이면 정상입니다.

- 관리자 페이지: `http://127.0.0.1:8000/admin`
- 에뮬레이터 앱 주소: `http://10.0.2.2:8000`

## 2. 서버 상태 확인

브라우저 또는 PowerShell에서 확인:

```powershell
Invoke-RestMethod http://127.0.0.1:8000/health
Invoke-RestMethod http://127.0.0.1:8000/location/latest
```

`ok : True` 또는 `location` 값이 나오면 서버는 정상입니다.

## 3. 에뮬레이터 앱 실행

PowerShell에서 실행:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
.\run_emulator_local.cmd
```

직접 실행하고 싶으면 아래 명령어를 써도 됩니다.

```powershell
flutter run -d emulator-5554 --dart-define=SERVER_URL=http://10.0.2.2:8000
```

## 4. 앱에서 봐야 하는 정상 표시

앱의 `집 안 상태` 화면에서 아래 중 하나가 보이면 정상입니다.

- `실시간 서버 연결 중`
- `서버 응답 확인 완료`
- 초록색 서버 연결 카드

서버를 잠깐 껐다 켜도 앱은 멈추지 않고, 서버가 다시 켜지면 자동으로 다시 연결됩니다.

## 5. 관리자 페이지로 연결 확인

브라우저에서 열기:

```powershell
start http://127.0.0.1:8000/admin
```

확인 순서:

1. `시연 상태 초기화` 클릭
2. 앱에서 정상 위치 표시 확인
3. 관리자 도면을 클릭하거나 `현관`, `낙상 의심 발생`, `장시간 무반응` 버튼 클릭
4. 앱 도면의 미니어처와 알림이 바뀌는지 확인

## 6. 실제 안드로이드 폰으로 연결할 때

에뮬레이터는 `10.0.2.2`를 쓰지만, 실제폰은 노트북의 Wi-Fi IPv4 주소를 써야 합니다.

노트북 IP 확인:

```powershell
ipconfig
```

예를 들어 IPv4가 `192.168.0.15`라면:

```powershell
flutter run --dart-define=SERVER_URL=http://192.168.0.15:8000
```

실제폰과 노트북은 반드시 같은 Wi-Fi에 있어야 합니다.

## 7. 문제가 생겼을 때

### 앱에 서버 대기 중이 계속 뜸

1. 서버 창이 켜져 있는지 확인
2. `http://127.0.0.1:8000/health`가 열리는지 확인
3. 에뮬레이터는 `SERVER_URL=http://10.0.2.2:8000`인지 확인
4. 실제폰은 `SERVER_URL=http://노트북IP:8000`인지 확인

### 관리자 페이지는 움직이는데 앱이 안 바뀜

1. 앱을 완전히 종료 후 다시 실행
2. 서버 창에서 오류가 없는지 확인
3. 앱 화면의 연결 카드가 초록색인지 확인
4. 관리자 페이지에서 `시연 상태 초기화` 클릭

### 포트 8000이 이미 사용 중이라고 나옴

기존 서버가 이미 켜져 있을 수 있습니다. 기존 서버 창을 닫고 다시 실행하세요.

