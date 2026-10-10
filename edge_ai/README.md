# edge_ai — Jetson 엣지 AI 파이프라인

ESP32-S3 수신 노드 4대가 보내는 RuView ADR-018 CSI 패킷(UDP 5005)을 받아, 실시간으로 낙상·행동·인원·호흡을 추론하는 Jetson Orin Nano용 코드입니다. (구 `Hanium_jetson` 저장소)

| 파일 | 역할 |
|---|---|
| `hanium_fall_v2/adr018.py` | ADR-018 패킷 파싱, 첫 번째 LLTF 블록(64 서브캐리어) 추출 |
| `hanium_fall_v2/features.py` | 32Hz 보간 → 193채널 × 160프레임 특징, 노드 mask·품질 계산 |
| `hanium_fall_v2/model.py` | multi-node 1D-CNN (행동 10종 · 인원 4분류 · 품질) |
| `hanium_fall_v2/fall_state.py` | 낙상 후보 → 사후 눕기 확인 → 확정 / 회복 상태기계 |
| `hanium_fall_v2/respiratory.py` | CSI 기반 호흡수 추정, 보수적 무호흡 의심 게이트 (심박 미추정) |
| `hanium_fall_v2/live_inference.py` | 실시간 UDP 수신·추론, `runtime/latest_status.json` 기록 |
| `hanium_fall_v2/capture_labeled.py` | 라벨(행동·인원)을 붙인 CSI 수집 |
| `hanium_fall_v2/build_manifest.py`, `train.py`, `evaluate.py` | 데이터셋 구성·학습·평가 |
| `hanium_fall_v2/status_api.py` | 추론 결과 조회용 HTTP API (기본 8080) |
| `jetson/` | 실행 스크립트와 systemd 서비스 템플릿 |
| `config/default_config.json` | 특징·모델·상태기계·건강 모니터링 설정값 |

## 빠른 점검

```bash
pip install -r requirements.txt
python3 -m hanium_fall_v2.selftest      # torch 없이도 파서·특징·상태기계 점검
```

## 실시간 실행

```bash
export RUVIEW_APP_DIR=$(pwd)
./jetson/run_live.sh                     # 추론 (RUVIEW_NODES 기본 1,2,3,4)
./jetson/run_api.sh                      # 상태 API
./jetson/install_services.sh "$(pwd)"   # 부팅 시 자동 실행 등록
```

학습된 체크포인트(`models/`)와 수집 데이터(`captures/`)는 `.gitignore`로 제외되어 있습니다.
