# edge_ai — Jetson 엣지 AI

ESP32-S3 수신 노드 4대가 보내는 RuView ADR-018 CSI 패킷(UDP 5005)으로 낙상을 감지하는 코드입니다. (구 `Hanium_jetson` 저장소)

| 패키지 | 내용 | 가중치 |
|---|---|---|
| [`hanium_fall_v1/`](hanium_fall_v1) | 개발보고서의 1D-CNN(134채널 × 500패킷, 낙상/비낙상). 학습·평가·실시간 추론 | 팀 가중치 2개 포함 |
| `hanium_fall_v2/` | 실시간 서비스용 파이프라인. 노드별 LLTF 선택 → 193채널 × 160프레임 → 다중 노드 모델 → 낙상 상태기계, 호흡·상태 API | 다음 데이터 수집 후 학습 ([이유](../experiments/MEASURED_RESULTS.md)) |

| v2 파일 | 역할 |
|---|---|
| `hanium_fall_v2/adr018.py` | ADR-018 패킷 파싱, 첫 번째 LLTF 블록(64 서브캐리어) 추출 |
| `hanium_fall_v2/features.py` | 32Hz 보간 → 193채널 × 160프레임 특징, 노드 mask·품질 계산 |
| `hanium_fall_v2/model.py` | 다중 노드 1D-CNN + attention 융합 (행동 10종 · 인원 4분류 · 품질) |
| `hanium_fall_v2/fall_state.py` | 낙상 후보 → 사후 눕기 확인 → 확정 / 회복 상태기계 |
| `hanium_fall_v2/respiratory.py` | CSI 기반 호흡수 추정, 보수적 무호흡 의심 게이트 (심박 미추정) |
| `hanium_fall_v2/live_inference.py` | 실시간 UDP 수신·추론, `runtime/latest_status.json` 기록 |
| `hanium_fall_v2/capture_labeled.py` | 라벨(행동·인원·사건 시각)을 붙인 CSI 수집 |
| `hanium_fall_v2/build_manifest.py`, `train.py`, `evaluate.py` | 피험자 단위 데이터 분할·학습·평가 |
| `hanium_fall_v2/status_api.py` | 추론 결과 조회용 HTTP API (기본 8080) |
| `jetson/` | 실행 스크립트와 systemd 서비스 템플릿 |
| `tools/` | CSI 파형 실시간 대시보드·시연 로그 보조 도구, 추론 없음 ([사용법](tools/README.md)) |
| `config/default_config.json` | 특징·모델·상태기계·건강 모니터링 설정값 |

[전체 실행 순서](../docs/RUNBOOK.md) · [설계·구현 대조](../docs/IMPLEMENTATION_STATUS.md) · [실측 데이터 검증](../experiments/MEASURED_RESULTS.md)

## 점검

```bash
pip install -r requirements.txt torch
python -m hanium_fall_v2.selftest         # 파서·특징·상태기계 자체 점검
python -m unittest discover -s tests      # 단위 테스트 (torch가 없으면 모델 테스트는 건너뜀)
```

## v1 실행

```bash
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all \
    --npz-dir ../dataset/sample --metadata ../dataset/sample/sample_windows.csv
python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all
```

자세한 내용은 [hanium_fall_v1/README.md](hanium_fall_v1/README.md)에 있습니다.

## v2 실시간 실행

스크립트는 자기 위치를 기준으로 `edge_ai/` 폴더를 찾습니다. 다른 위치에 설치했다면 `RUVIEW_APP_DIR`로 지정하세요.

```bash
./jetson/run_live.sh                      # 추론 (RUVIEW_NODES 기본 1,2,3,4, RUVIEW_CHECKPOINT로 모델 지정)
./jetson/run_api.sh                       # 상태 API
./jetson/install_services.sh              # 부팅 시 자동 실행 등록
```

추론 결과를 앱 서버로 보내려면 `app/server/jetson_edge_client.py live-status`를 사용합니다([설명](../app/server/JETSON_EDGE_CLIENT.md)).

`run_live.sh`는 가중치가 없어도 수신·호흡 모니터링 경로를 시작합니다. 이때 `fall.state`는 `model_unavailable`이고 서버·앱에는 `unknown`(확인 필요)으로 표시됩니다. 실제 낙상 시연 전에 `python -m hanium_fall_v2.validate_fall_checkpoint`로 `live_ready`를 확인하세요. 학습한 체크포인트(`models/`)와 수집 데이터(`captures/`)는 `.gitignore`로 제외되어 있습니다.

공개 데이터셋의 원본 녹화는 [`dataset/tools/raw_to_v2.py`](../dataset/tools/raw_to_v2.py)로 v2 세션 형식으로 바꿀 수 있습니다.
