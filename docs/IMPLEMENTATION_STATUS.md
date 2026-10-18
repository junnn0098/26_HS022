# 설계 요구사항과 현재 구현

제작설계서(32쪽)·개발보고서(23쪽)에 적은 설계와 현재 저장소 코드의 관계를 정리했습니다. 쪽수는 PDF 첫 페이지부터 셉니다. 각 항목에는 근거 파일과 테스트를 연결했습니다. 실측 데이터로 낸 모델 성능은 [실측 데이터 검증 결과](../experiments/MEASURED_RESULTS.md)에 따로 정리했습니다.

## 개발보고서 모델·데이터·평가

| 항목 | 저장소 위치 | 내용 |
|---|---|---|
| 1D-CNN 모델 | [`edge_ai/hanium_fall_v1/model.py`](../edge_ai/hanium_fall_v1/model.py) | `CSI1DCNN`, 134채널 × 500패킷 입력, 낙상/비낙상 2분류, 파라미터 65,762개 |
| 팀 학습 가중치 | [`edge_ai/hanium_fall_v1/weights/`](../edge_ai/hanium_fall_v1/weights) | `team_v1_0717.pth`, `team_v1_0803.pth`. SHA-256은 [v1 설명서](../edge_ai/hanium_fall_v1/README.md)에 기록 |
| 학습·평가·실시간 추론 | [`train.py`](../edge_ai/hanium_fall_v1/train.py), [`evaluate.py`](../edge_ai/hanium_fall_v1/evaluate.py), [`realtime_inference.py`](../edge_ai/hanium_fall_v1/realtime_inference.py) | 분할 방식 3가지(윈도우 무작위·녹화 단위·날짜 단위), 테스트 [`test_v1.py`](../edge_ai/tests/test_v1.py) |
| 학습 데이터 | [`dataset/`](../dataset/README.md) | 녹화 48건(5일), 5초 윈도우 2,217개(낙상 969개), 동작 15종. 대용량 파일은 GitHub Release `dataset-v1.0` |
| 평가 결과 | [`experiments/MEASURED_RESULTS.md`](../experiments/MEASURED_RESULTS.md) | 분할 방식별 재현율·AUROC, 재현 명령, 윈도우별 예측 CSV |

## 입력 규격의 기준

| 항목 | 설계서·보고서 표현 | 현재 코드와 실측값 |
|---|---|---|
| 수신률 | 설계서 p.5·10은 100Hz, p.21은 약 33pps | 실측 노드당 초당 약 37~50개(수집일별 중앙값, 모든 패킷 형식 포함). [`recordings.csv`](../dataset/metadata/recordings.csv)의 노드별 패킷 수(`nodes`) ÷ 녹화 시간, [수집 방법](../dataset/README.md#수집-방법). v2 `features.py`는 실제 수신 시각을 32Hz로 보간 |
| 입력 크기 | 설계서 p.22는 52×500, p.26 및 보고서는 134×500, 설계서 p.21은 193×160 | v1: 134×500. v2: 노드별 193×160, 최대 4노드, 5초 창(`FeatureConfig`, `default_config.json`) |
| 134채널 구성 | 보고서는 서브캐리어 진폭으로 설명 | 헤더 5바이트 + 첫 LLTF 블록 64 + 두 번째 64값 블록 + 1([채널 구성](../dataset/README.md#134채널의-실제-구성)). `--channels csi`·`lltf`로 헤더를 뺀 학습 가능 |
| LTF 선택 | 설계서 p.21의 그림은 LLTF, 본문은 HT-LTF | v1: LTF를 구분하지 않고 패킷 오프셋 10부터 134값을 읽음(위 행). v2: `adr018.py::extract_lltf_iq`가 첫 LLTF 64개 선택, 앞 2개 복소수 마스킹, 20MHz·PPDU 검사 |
| 노드 융합 순서 | 설계서 p.21은 입력을 attention으로 먼저 합치는 것으로 읽힘 | v1: 4개 노드의 패킷을 도착 순서대로 한 시계열로 이어 붙임(노드 구분 없음). v2: 노드별 공유 1D-CNN 인코딩 후 attention 가중 융합 |
| 모델 크기 | 보고서 약 8.7만 파라미터 | 같은 코드로 계산하면 v1 65,762개. v2는 359,697개(`python -m hanium_fall_v2.selftest`) |
| 낙상 판정 | 설계서 p.13은 P≥0.9, 다른 곳은 시간·공간 필터 | v1: `realtime_inference.py::AlertGate`(0.9 이상 즉시, 0.5 이상 2회 연속 시 경보, 콘솔 출력). v2: `fall_state.py` 상태기계(아래 표)를 거쳐 서버로 전달. 공간 필터는 미구현 |
| 배포·지연 | TensorRT·0.01초 | 저장소의 추론 코드는 PyTorch. TensorRT 변환·엔진·Jetson 지연 측정은 포함하지 않음 |

v2 기본값의 출처: [설정](../edge_ai/config/default_config.json), [특징 추출](../edge_ai/hanium_fall_v2/features.py), [패킷 파서](../edge_ai/hanium_fall_v2/adr018.py), [모델](../edge_ai/hanium_fall_v2/model.py), [상태기계](../edge_ai/hanium_fall_v2/fall_state.py).

| v2 상태기계 항목 | 기본값 | 해석 |
|---|---|---|
| 추론 주기 | 0.5초 | 입력 창 5초와 별개 |
| 최소 품질 | 0.55 | 낮은 품질의 판단을 유보. 사후 확인·확정 상태는 별도 유지 규칙 적용 |
| 낙상 후보 | fall≥0.70, 누적 2회 | 조건 미충족 시 후보 횟수 감소 |
| 사후 눕기 | lying≥0.55, 누적 3회 | 연속 3회 조건은 아님 |
| 회복 | 서기·걷기·일어서기 확률 중 최대값≥0.65, 누적 2회 | 확정 전 사후 확인에서 회복 여부 판단 |
| 사후 확인 제한 | 8초 | 확정·회복이 없으면 정상으로 복귀 |
| 확정 경보 유지 | 최소 30초 | 30초 경과만으로 해제하지 않고 이후 회복 조건도 확인 |

이 값은 설정값이며 검출 정확도나 전체 알림 지연을 뜻하지 않습니다.

## 요구사항 대조

요구사항 ID는 제작설계서 p.5를 따릅니다.

| 요구사항 | 구현과 근거 | 남은 일 |
|---|---|---|
| HW_01_F01 독립 센서망 | ipTIME A2004SR, 2.4GHz 6번 채널(2437MHz) 고정, 센서 전용 SSID. 녹화 48건 모두 2437MHz(`recordings.csv`의 `frequency_mhz`) | 채널은 수동 고정이며 자동 채널 변경은 없음 |
| HW_01_F02 CSI 추출 | ESP32-S3 ×4(오픈소스 RuView 펌웨어, 저장소에는 미포함) → ADR-018 UDP. [파서](../edge_ai/hanium_fall_v2/adr018.py), [v2 실시간 수신](../edge_ai/hanium_fall_v2/live_inference.py), [v1 실시간 추론](../edge_ai/hanium_fall_v1/realtime_inference.py) | 펌웨어 커밋·ESP-IDF 버전·빌드 설정 기록 |
| HW_01_F03 UDP 전달 | 포트 5005 수신, 패킷 형식·순번 검사. 실측 수신량은 위 표 | 07-24 일부 녹화에서 노드 1 수신량 감소(`recordings.csv`의 `nodes`). UDP 유실 패킷은 복구되지 않으며 v2는 노드별 품질·마스크로 반영 |
| AI_01_F01 전처리 | v1: 윈도우 단위 z-score([`data.py`](../edge_ai/hanium_fall_v1/data.py)). v2: 32Hz 보간, 로그 진폭·동적 진폭·위상차·RSSI 193채널 | — |
| AI_01_F02 추론 | v1 1D-CNN + 팀 가중치 2개. v2 다중 노드 1D-CNN(행동 10종·인원·품질 출력, 호환 가중치 검사) | v2 가중치는 새 데이터 수집 후 학습. 처음 보는 녹화·날짜에서의 일반화(아래 남은 과제) |
| AI_01_F03 후처리 | v1 `AlertGate`, v2 [낙상 상태기계](../edge_ai/hanium_fall_v2/fall_state.py) | 위험·안전 구역 공간 필터 |
| AI_02_F01 호흡 분석 | [호흡 추정](../edge_ai/hanium_fall_v2/respiratory.py), 움직임·신호 품질 게이트, 기본 6~30회/분 분석 범위. 값이 없으면 서버는 `null`로 전달하고 앱은 '측정 대기'로 표시 | 기준 장치와의 실측 비교. 호흡수는 참고 정보이며 의료용 측정값이 아님 |
| APP_01_F01 푸시 | 서버 FCM 전송, 앱 토큰 등록·수신 코드 | Firebase 서비스 계정 설정 시 동작. 전송 성공과 실제 단말 수신을 따로 확인 |
| APP_01_F02 전화 연결 | [Flutter 호출](../app/lib/core/services/emergency_actions.dart), Android `ACTION_DIAL` | 전화 앱을 여는 기능이며 자동 발신·119 자동 신고는 하지 않음. iOS 동작 확인 |
| APP_01_F03 위치·동선 | 앱 도면·최근 이동 경로(최대 32개 점), 연결 클라이언트의 설치 좌표(`--room-x`, `--room-y`) | 방 자동 분류·방 안 좌표 추정 |
| APP_02_F01 위치 공유 | 서버 `publicLocation()`을 REST와 `WS /ws/location`에 모두 적용, 새 알림·푸시는 '위치 비공개' | 계정 간 접근 제어(로그인은 역할 선택만). 공유를 끄기 전에 만든 알림은 방 이름 유지 |
| APP_02_F02 상태 문구 | 정상·주의·즉각 조치 필요 + 판단 불가 '확인 필요', 호흡 '측정 대기', 시연 입력 '시연 입력' 칩 | — |

제작설계서 p.19·24~25의 ERD는 확장 설계입니다. 현재 Node.js 서버는 설정·보호자·알림을 `dev_state.json` 파일에 저장합니다. 호흡·기침 연구 코드는 의료 진단 기능이 아닙니다.

## 보고서 성능 수치와 재현

| 보고서 | 대응하는 데이터 | 저장소에서 확인한 결과 |
|---|---|---|
| p.19 초기 502개 클립: 재현율 1.0, 오탐 0건 | 07-08 녹화의 윈도우 502개 | 따로 재현하지 않음(아래 1,019개에 포함) |
| p.15·19 1,019개 클립(낙상 302건, 11종 동작): 재현율 0.933, 비틀거림 오탐 0건 | 07-08·07-09 녹화의 윈도우 1,019개 | 같은 1,019개를 윈도우 무작위 80/20으로 나누면 재현율 0.997, 비틀거리기 오탐 0건 |

보고서 수치는 윈도우를 무작위로 나눈 조건에서 나온 것으로 판단합니다. 2,217개 전체를 무작위로 나누면 CSI가 아닌 헤더 5채널만 넣어도 재현율 0.970이 나오고, 녹화 단위로 나누면 AUROC가 약 0.54로 떨어지며, 날짜 단위로 나누면 낙상을 거의 찾지 못합니다. 전체 표·해석·재현 명령은 [실측 데이터 검증 결과](../experiments/MEASURED_RESULTS.md)에 있습니다. 앞으로의 성능은 녹화 단위 이상으로 나눈 결과로 보고합니다([평가 절차](validation/EVALUATION_PROTOCOL.md)).

## 우선 보완할 구현 항목

서버·앱 연동에서 찾은 문제와 현재 상태입니다.

| 항목 | 상태 | 현재 동작과 근거 |
|---|---|---|
| 없는 호흡값을 서버가 예시값으로 보충 | 해결 | 연결 클라이언트는 없는 호흡값을 보내지 않고, 서버 `app/server/local_server.js::normalizeLocation`도 채우지 않고 `breathingRate: null`로 전달합니다. 앱은 `breathingRate`가 없거나 `breathingEstimated: true`이면 '측정 대기'로 표시합니다. 테스트: `test_local_server.py::test_missing_breathing_stays_null`, `test_jetson_edge_client.py::test_missing_breathing_is_omitted`, `app/test/safety_models_test.dart` |
| 모델 미설치·판단 불가가 `normal`로 전달 | 해결 | `jetson_edge_client.py::payload_from_live_status`는 `model_unavailable`·`unknown`·미인식 상태를, 서버 `normalizeStatus`는 미인식 상태를 `unknown`으로 처리합니다. `unknown`은 알림·푸시를 만들지 않습니다. 앱은 '확인 필요'로 표시하고, 서버 데이터를 받기 전 초기 화면도 '확인 필요'·'출처 미지정'입니다. 테스트: `test_unavailable_or_unrecognized_states_are_unknown`, `test_unknown_status_and_missing_source`, `safety_models_test.dart`, `widget_test.dart` |
| 오래된 추론 결과 전달 | 일부 해결 | `command_live_status`는 `unix_time`이 `--max-age`(기본 10초)보다 오래되었거나 없는 레코드를 전달하지 않고 `status: unknown`을 보냅니다(`test_age_limit`, `test_cli_rejects_old_record`). 서버 시작·초기화 직후 상태도 `unknown`입니다(`test_boot_and_reset_start_unknown`). 남은 부분: 연결 클라이언트 자체가 멈추면 `REAL_SENSOR_ONLY=true` 서버(`local_server.js::currentLocation`)는 마지막 상태를 계속 보여 줍니다 |
| 시연 입력과 실제 추론의 구분 | 해결 | `once`·`sequence`는 `source: scripted_demo`, `live-status`는 `jetson_orin`으로 보내고(`test_default_sources`), 서버는 `source`가 없으면 `unknown`으로 저장합니다. 앱은 `scripted_demo`에 '시연 입력' 칩을 붙이고, 시연 도구는 `--dart-define=DEMO_MODE=true`일 때만 보여 줍니다 |
| 위치 공유 OFF가 WebSocket에 미적용 | 해결 | `publicLocation()`을 REST와 `WS /ws/location` 모두에 적용합니다(`test_websocket_respects_location_sharing_off`) |
| 로그인 화면의 고정 계정값 | 해결 | 로그인 화면을 '시연용 역할 선택 (계정 인증 미구현)'으로 바꿨습니다(`widget_test.dart`). 계정 인증은 구현하지 않았습니다 |
| 서버 API 보호 | 해결(선택 설정) | `HANIUM_API_TOKEN`을 설정하면 POST·상태 조회에 Bearer 토큰이 필요하고, JSON POST는 `Content-Type: application/json`이 아니면 415로 거절합니다. CORS 허용 목록, `HOST` 바인딩, 출입 비밀번호 저장 제거(`test_local_server.py`). 앱은 `--dart-define=API_TOKEN`으로 토큰을 보냅니다. `WS /ws/location`은 토큰 검사가 없습니다([서버 설정](../app/server/README.md)) |
| 도면 위치가 고정 설치 좌표 | 남음 | `--room-x`, `--room-y`로 지정한 방 위치입니다. 자동 위치 추정을 도입하면 위치 정답과 오차 평가를 추가합니다 |
| 단순 JSON 경로의 `lying` → 위험 매핑 | 남음 | `LABEL_TO_EVENT`, `payload_from_ai_record`는 `lying`을 곧바로 `danger`로 매핑합니다(인식하지 못한 라벨은 `unknown`). 실제 모델 연결은 상태기계를 거치는 `live-status`를 사용합니다 |

## 남은 과제

| 항목 | 현재 상태 |
|---|---|
| 일반화 | 처음 보는 녹화·다른 날의 데이터에서는 아직 낙상을 안정적으로 찾지 못합니다. 원인 분석과 다음 수집 계획(패킷 형식 고정, 관절 좌표 기반 사건 단위 라벨, 빈 방 기준선)은 [실측 데이터 검증 결과](../experiments/MEASURED_RESULTS.md#6-다음-단계)에 있습니다 |
| v2 학습 가중치 | 새 데이터를 수집한 뒤 학습해 공개합니다. 현재 저장소에는 v2 가중치가 없습니다 |
| 전이 학습 | 보고서에 적은 공개 데이터 사전학습·전이 학습 코드는 저장소에 없습니다 |
| 추론 가속 | TensorRT 변환·엔진·Jetson 지연 측정은 포함하지 않았습니다 |
| 공간 필터 | 위험·안전 구역 필터는 구현하지 않았습니다 |
| 생활 리포트·DB | 일일·주간 리포트와 SQLite DB는 구현하지 않았습니다 |
| 펌웨어 기록 | RuView 펌웨어 커밋·ESP-IDF 버전·sdkconfig를 기록하고, I/Q 바이트 순서를 패킷으로 확인합니다([데이터 연결 규격](architecture/DATA_CONTRACTS.md#1-adr-018-패킷)) |
| 호흡 실측 비교 | 기준 장치와 함께 측정한 비교 결과는 아직 없습니다 |

## 확인 기록

2026-10-19, 브랜치 `data/measured-dataset`:

| 점검 | 결과 |
|---|---|
| `python -m unittest discover -s tests` (`edge_ai/`, PyTorch 2.14 CPU) | 40개 모두 통과(v1 테스트 9개 포함) |
| `python -m hanium_fall_v2.selftest` (`edge_ai/`) | `RESULT=PASS_COMPLETE_SELFTEST`, `TORCH_MODELS=PASS`, `fall_parameters=359697` |
| `python -m unittest discover -s app/server/tests` (저장소 루트, Node.js 24) | 17개 모두 통과 |
| `flutter test` (`app/`) | 11개 모두 통과 |

위 점검은 실제 센서·앱 단말·FCM 수신을 포함하지 않습니다. 합성 입력으로 한 소프트웨어 검사는 [소프트웨어 실험 결과](../experiments/RESULTS.md), 실행 절차는 [실행 및 시연 안내](RUNBOOK.md)에 있습니다.
