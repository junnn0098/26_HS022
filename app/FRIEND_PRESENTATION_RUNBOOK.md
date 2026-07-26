# 한이음 발표용 로컬 실행 안내

발표자가 다른 PC에서 시연할 때 쓰는 안내서입니다.

친구 PC의 현재 Wi-Fi IPv4 주소는 아래로 잡습니다.

```text
172.20.10.2
```

중요:

- `192.168.56.1`은 가상 어댑터 주소라 발표용 앱 연결 주소로 쓰지 않습니다.
- Android 에뮬레이터에서 앱을 실행하면 서버 주소는 `http://10.0.2.2:8000`입니다.
- 실제 Android 폰에서 앱을 실행하면 서버 주소는 `http://172.20.10.2:8000`입니다.

## 1. 서버 실행

`Hanium_app` 폴더에서 아래 파일을 더블클릭합니다.

```text
run_friend_1_server.cmd
```

서버 창은 발표가 끝날 때까지 닫지 않습니다.

관리자 페이지:

```text
http://127.0.0.1:8000/admin
```

같은 네트워크의 다른 기기에서 관리자 페이지를 볼 때:

```text
http://172.20.10.2:8000/admin
```

## 2-A. 에뮬레이터로 앱 실행할 때

Android 에뮬레이터를 켠 뒤 아래 파일을 실행합니다.

```text
run_friend_2_app_emulator.cmd
```

이 방식에서는 앱 서버 주소가 자동으로 아래처럼 들어갑니다.

```text
http://10.0.2.2:8000
```

## 2-B. 실제 폰으로 앱 실행할 때

실제 Android 폰과 발표 PC가 같은 Wi-Fi 또는 핫스팟에 연결되어 있어야 합니다.

아래 파일을 실행합니다.

```text
run_friend_2_app_real_phone.cmd
```

이 방식에서는 앱 서버 주소가 자동으로 아래처럼 들어갑니다.

```text
http://172.20.10.2:8000
```

## 3. 실제폰용 release APK 만들기

실제폰에 APK를 설치해서 시연할 경우 아래 파일을 실행합니다.

```text
run_friend_4_build_release_apk_real_phone.cmd
```

이 APK에는 아래 서버 주소가 들어갑니다.

```text
http://172.20.10.2:8000
```

생성 위치:

```text
release_apk/hanium_guardian_realphone_172.20.10.2.apk
```

주의: 발표장 네트워크에서 친구 PC의 IPv4가 바뀌면 APK를 다시 빌드해야 합니다.

## 4. 서버 연결 확인

연결이 불안하면 아래 파일을 실행합니다.

```text
run_friend_3_check_server.cmd
```

정상이라면 `ok` 또는 서버 상태 정보가 나옵니다.

## 5. 발표 시연 순서

1. `run_friend_1_server.cmd` 실행
2. 관리자 페이지가 열리는지 확인
3. 에뮬레이터면 `run_friend_2_app_emulator.cmd` 실행
4. 실제폰이면 `run_friend_2_app_real_phone.cmd` 실행
5. 앱 하단에서 `집 안` 화면으로 이동
6. 관리자 페이지에서 시연 버튼 실행
   - 정상
   - 현관 접근
   - 장시간 무반응
   - 낙상 의심
7. 앱에서 미니어처 위치, 이동 잔상, 알림 화면이 바뀌는지 확인

## 6. 안 될 때 빠른 해결

### 관리자 페이지는 되는데 앱이 안 바뀜

- 에뮬레이터 실행이면 `run_friend_2_app_emulator.cmd`를 사용했는지 확인
- 실제폰 실행이면 `run_friend_2_app_real_phone.cmd`를 사용했는지 확인
- 앱을 완전히 종료한 뒤 다시 실행
- 관리자 페이지에서 `시연 시작` 또는 정상 시나리오를 한 번 누른 뒤 다시 테스트

### 실제폰에서 서버 연결이 안 됨

1. 폰과 PC가 같은 Wi-Fi/핫스팟인지 확인
2. PC IP가 여전히 `172.20.10.2`인지 `ipconfig`로 확인
3. IP가 바뀌었으면 `run_friend_2_app_real_phone.cmd` 안의 `SERVER_URL` 값을 새 IP로 변경
4. Windows 방화벽에서 Node.js 또는 포트 8000 허용

방화벽 문제일 때 관리자 권한 PowerShell에서 아래 명령을 실행하면 됩니다.

```powershell
New-NetFirewallRule -DisplayName "Hanium Demo Server 8000" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

## 7. 발표 전 최종 체크

- 서버 창이 켜져 있는가?
- 관리자 페이지가 열리는가?
- 앱이 켜지는가?
- 앱에서 `집 안` 화면이 보이는가?
- 관리자 페이지에서 낙상 의심을 눌렀을 때 앱 알림이 바뀌는가?
- 발표 중에는 서버 창을 닫지 않는가?
