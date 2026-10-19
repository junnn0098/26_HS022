# 기능별 구현 현황

기능마다 구현 내용, 코드 위치, 테스트를 연결했습니다. 실측 데이터로 학습한 모델 결과는 [실측 데이터 학습 결과](../experiments/MEASURED_RESULTS.md)에 있습니다.

## 모델·데이터·평가

| 항목 | 저장소 위치 | 내용 |
|---|---|---|
| 1D-CNN 모델 | [`edge_ai/hanium_fall_v1/model.py`](../edge_ai/hanium_fall_v1/model.py) | `CSI1DCNN`, 134채널 × 500패킷 입력, 낙상/비낙상 2분류 |
| 팀 학습 가중치 | [`edge_ai/hanium_fall_v1/weights/`](../edge_ai/hanium_fall_v1/weights) | 팀 학습 가중치 2개(`team_v1_0717.pth`, `team_v1_0803.pth`). SHA-256은 [v1 설명서](../edge_ai/hanium_fall_v1/README.md)에 기록 |
| 학습·평가·실시간 추론 | [`train.py`](../edge_ai/hanium_fall_v1/train.py), [`evaluate.py`](../edge_ai/hanium_fall_v1/evaluate.py), [`realtime_inference.py`](../edge_ai/hanium_fall_v1/realtime_inference.py) | 라벨별 층화 윈도우 무작위 분할, 녹화 단위·날짜 단위 분할 옵션. 테스트 [`test_v1.py`](../edge_ai/tests/test_v1.py) |
| 학습 데이터 | [`dataset/`](../dataset/README.md) | 녹화 48건(3주간 5회), 500패킷 윈도우 2,217개(낙상 969개), 동작 15종. 대용량 파일은 GitHub Release `dataset-v1.0` |
| 학습 결과 | [`experiments/MEASURED_RESULTS.md`](../experiments/MEASURED_RESULTS.md) | 윈도우 무작위 80/20 5회 반복 결과(1·2차 수집 1,019개, 전체 2,217개), 윈도우별 예측 CSV, 재현 명령 |
| v2 실시간 모델 | [`edge_ai/hanium_fall_v2/`](../edge_ai/hanium_fall_v2) | 다중 노드 모델 구조, 학습·평가 코드, 체크포인트 호환 검사 |

## 입력 규격

| 항목 | v1 ([`hanium_fall_v1`](../edge_ai/hanium_fall_v1/README.md)) | v2 ([`hanium_fall_v2`](../edge_ai/hanium_fall_v2)) |
|---|---|---|
| 입력 크기 | 134채널 × 500패킷 | 노드별 193채널 × 160프레임, 최대 4노드 |
| 시간축 | 4개 노드의 패킷을 도착 순서대로 이어 붙인 500패킷 | 5초 창을 노드별 수신 시각 기준 32Hz로 보간 |
| 채널 | 패킷 오프셋 10부터 2바이트씩 묶은 크기 134개: 헤더 5 + 첫 LLTF 블록 64 + 두 번째 64값 블록 + 1([134채널 구성](../dataset/README.md#134채널-구성)). `--channels csi`·`lltf`로 채널 선택 | `adr018.py::extract_lltf_iq`가 첫 LLTF 64개 선택(앞 2개 복소 값 마스킹, 20MHz·PPDU 검사) → 로그 진폭 64 + 동적 진폭 64 + 위상차 64 + RSSI 1 |
| 노드 융합 | 한 시계열로 연결 | 노드별 공유 1D-CNN 인코딩 후 attention 가중 융합 |
| 출력 | 낙상/비낙상 2분류 | 행동 10종·인원·품질 |
| 낙상 판정 | `realtime_inference.py::AlertGate`: 0.9 이상 즉시, 0.5 이상 2회 연속 시 경보(콘솔 출력) | `fall_state.py` 상태기계(아래 표)를 거쳐 서버로 전달 |

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

## 요구사항별 구현

| 요구사항 | 구현 | 코드 | 테스트 |
|---|---|---|---|
| HW_01_F01 독립 센서망 | ipTIME A2004SR, 2.4GHz 6번 채널(2437MHz) 고정, 센서 전용 SSID. 녹화 48건 모두 2437MHz | [`recordings.csv`](../dataset/metadata/recordings.csv)의 `frequency_mhz` | — |
| HW_01_F02 CSI 추출 | ESP32-S3 ×4(오픈소스 RuView 펌웨어, 저장소 미포함) → ADR-018 UDP 패킷 | [파서](../edge_ai/hanium_fall_v2/adr018.py), [v2 실시간 수신](../edge_ai/hanium_fall_v2/live_inference.py), [v1 실시간 추론](../edge_ai/hanium_fall_v1/realtime_inference.py) | [`test_adr018.py`](../edge_ai/tests/test_adr018.py) |
| HW_01_F03 UDP 전달 | 포트 5005 수신, 패킷 형식·순번 검사. v2는 노드별 품질·마스크로 누락 반영 | [`adr018.py`](../edge_ai/hanium_fall_v2/adr018.py), [`features.py`](../edge_ai/hanium_fall_v2/features.py) | `test_adr018.py`, [`test_features.py`](../edge_ai/tests/test_features.py) |
| AI_01_F01 전처리 | v1: 윈도우 단위 z-score. v2: 32Hz 보간, 로그 진폭·동적 진폭·위상차·RSSI 193채널 | [v1 `data.py`](../edge_ai/hanium_fall_v1/data.py), [v2 `features.py`](../edge_ai/hanium_fall_v2/features.py) | `test_v1.py`, `test_features.py` |
| AI_01_F02 추론 | v1 1D-CNN + 팀 학습 가중치 2개. v2 다중 노드 1D-CNN(행동 10종·인원·품질 출력), 체크포인트 호환 검사 | [v1 `model.py`](../edge_ai/hanium_fall_v1/model.py), [v2 `model.py`](../edge_ai/hanium_fall_v2/model.py), [`fall_checkpoint.py`](../edge_ai/hanium_fall_v2/fall_checkpoint.py) | `test_v1.py`, [`test_model.py`](../edge_ai/tests/test_model.py), [`test_fall_checkpoint.py`](../edge_ai/tests/test_fall_checkpoint.py) |
| AI_01_F03 후처리 | v1 `AlertGate`, v2 낙상 상태기계 | [`realtime_inference.py`](../edge_ai/hanium_fall_v1/realtime_inference.py), [`fall_state.py`](../edge_ai/hanium_fall_v2/fall_state.py) | `test_v1.py::test_alert_gate`, [`test_fall_state.py`](../edge_ai/tests/test_fall_state.py) |
| AI_02_F01 호흡 분석 | 움직임·신호 품질 게이트, 기본 6–30회/분 분석 범위. 값이 없으면 서버는 `null`로 전달하고 앱은 '측정 대기'로 표시. 호흡수는 참고 정보이며 의료용 측정값이 아님 | [`respiratory.py`](../edge_ai/hanium_fall_v2/respiratory.py) | [`test_respiratory.py`](../edge_ai/tests/test_respiratory.py) |
| APP_01_F01 푸시 | 서버 FCM 전송, 앱 토큰 등록·수신. Firebase 서비스 계정을 설정하면 동작 | [`local_server.js`](../app/server/local_server.js)의 `sendPushForAlert`, [`notification_service.dart`](../app/lib/core/services/notification_service.dart) | 단말 수신 절차는 [실행 안내](RUNBOOK.md#3-fcm-확인) |
| APP_01_F02 전화 연결 | 보호자 화면에서 어르신·119, 피보호자 화면에서 보호자·119 번호로 전화 앱 열기(Android `ACTION_DIAL`). 알림 화면에서 119 전달 정보 표시·복사 | [`emergency_actions.dart`](../app/lib/core/services/emergency_actions.dart), [`alerts_screen.dart`](../app/lib/features/alerts/alerts_screen.dart), [`care_recipient_screen.dart`](../app/lib/features/care_recipient/care_recipient_screen.dart) | — |
| APP_01_F03 위치·동선 | 앱 도면·최근 이동 경로(최대 32개 점) | [`home_map/`](../app/lib/features/home_map), [`safety_controller.dart`](../app/lib/core/state/safety_controller.dart) | — |
| APP_02_F01 위치 공유 | 서버 `publicLocation()`을 REST와 `WS /ws/location`에 모두 적용, 새 알림·푸시는 '위치 비공개' | `local_server.js` | `test_local_server.py::test_websocket_respects_location_sharing_off` |
| APP_02_F02 상태 문구 | 정상·주의·즉각 조치 필요 + 판단 불가 '확인 필요', 호흡 '측정 대기', 시연 입력 '시연 입력' 칩 | [`safety_models.dart`](../app/lib/core/models/safety_models.dart) | [`safety_models_test.dart`](../app/test/safety_models_test.dart), [`widget_test.dart`](../app/test/widget_test.dart) |

서버는 설정·보호자·알림을 `dev_state.json` 파일에 저장합니다. 호흡·기침 연구 코드는 의료 진단 기능이 아닙니다.

## 서버·앱 연동

| 기능 | 동작 | 코드 | 테스트 |
|---|---|---|---|
| 판단 불가 상태 | 모델 미설치(`model_unavailable`)·`unknown`·미인식 상태를 `unknown`으로 전달합니다. `unknown`은 알림·푸시를 만들지 않고 앱에서 '확인 필요'로 표시됩니다. 서버 시작·초기화 직후와 서버 데이터를 받기 전 앱 화면도 '확인 필요'입니다 | `jetson_edge_client.py::payload_from_live_status`, `local_server.js::normalizeStatus` | `test_unavailable_or_unrecognized_states_are_unknown`, `test_unknown_status_and_missing_source`, `test_boot_and_reset_start_unknown`, `safety_models_test.dart`, `widget_test.dart` |
| 호흡값 누락 | 연결 클라이언트는 없는 호흡값을 보내지 않고, 서버도 채우지 않고 `breathingRate: null`로 전달합니다. 앱은 `breathingRate`가 없거나 `breathingEstimated: true`이면 '측정 대기'로 표시합니다 | `jetson_edge_client.py`, `local_server.js::normalizeLocation` | `test_missing_breathing_is_omitted`, `test_missing_breathing_stays_null`, `safety_models_test.dart` |
| 오래된 추론 결과 | `live-status`는 `unix_time`이 없거나 `--max-age`(기본 10초)보다 오래된 결과를 전달하지 않고 `status: unknown`을 보냅니다 | `jetson_edge_client.py::command_live_status` | `test_age_limit`, `test_cli_rejects_old_record` |
| 입력 출처 구분 | `once`·`sequence`는 `source: scripted_demo`, `live-status`는 `jetson_orin`으로 보내고, 서버는 `source`가 없으면 `unknown`으로 저장합니다. 앱은 `scripted_demo`에 '시연 입력' 칩을 붙이고, 시연 도구는 `--dart-define=DEMO_MODE=true`일 때만 보여 줍니다 | `jetson_edge_client.py`, `local_server.js`, `safety_models.dart` | `test_default_sources`, `safety_models_test.dart` |
| 역할 선택 | 첫 화면 '역할 선택'에서 보호자·피보호자 화면을 고릅니다 | [`login_screen.dart`](../app/lib/features/auth/login_screen.dart) | `widget_test.dart` |
| 서버 API 보호(선택 설정) | `HANIUM_API_TOKEN`을 설정하면 POST·상태 조회에 Bearer 토큰이 필요하고, JSON POST는 `Content-Type: application/json`이 아니면 415로 거절합니다. CORS 허용 목록, `HOST` 바인딩, `WS /ws/location`의 `?token=` 확인과 다른 출처 연결 거절. 앱은 `--dart-define=API_TOKEN`으로 토큰을 보냅니다([서버 설정](../app/server/README.md#보안네트워크-설정)) | `local_server.js` | `test_token_required_only_on_protected_routes`, `test_post_json_route_requires_json_content_type`, `test_cors_allowlist`, `test_websocket_requires_token_and_known_origin` |

서버 테스트는 [`test_local_server.py`](../app/server/tests/test_local_server.py)와 [`test_jetson_edge_client.py`](../app/server/tests/test_jetson_edge_client.py)에 있습니다.

## 향후 계획

- 다양한 사용자·공간에서 데이터를 추가 수집해 새로운 환경에서의 낙상 감지 성능을 강화합니다.
- 웹캠 관절 좌표로 넘어지는 순간을 표시하는 사건 단위 라벨로 학습 데이터를 고도화합니다.
- 추가 수집 데이터로 v2 실시간 모델을 학습해 실시간 경로에 적용합니다.
- 기준 장치와 함께 측정해 호흡 추정의 비교 평가를 확대합니다.

## 확인 기록

2026-10-19:

| 점검 | 결과 |
|---|---|
| `python -m unittest discover -s tests` (`edge_ai/`, PyTorch 2.14 CPU) | 40개 모두 통과(v1 테스트 9개 포함) |
| `python -m hanium_fall_v2.selftest` (`edge_ai/`) | `RESULT=PASS_COMPLETE_SELFTEST`, `TORCH_MODELS=PASS`, `fall_parameters=359697` |
| `python -m unittest discover -s app/server/tests` (저장소 루트, Node.js 24) | 18개 모두 통과 |
| `flutter test` (`app/`) | 11개 모두 통과 |

합성 입력 시스템 점검(낙상 상태기계 시나리오 10개 모두 기대대로 동작, 엣지→서버 연동 13개 항목 일치)은 [합성 입력 기반 소프트웨어 검증 결과](../experiments/RESULTS.md), 실행 절차는 [실행 및 시연 안내](RUNBOOK.md)에 있습니다.
