# 재현 가능한 소프트웨어 실험

센서와 학습 가중치 없이 실행할 수 있는 후처리·신호 추정·연동 실험입니다. 합성 입력을 사용한 결과와 실행 코드를 함께 제공합니다. 낙상 모델의 실환경 정확도나 사람의 호흡 측정 정확도를 평가한 자료는 아닙니다.

**[실험 결과 보고서](RESULTS.md)** · [원시 결과 폴더](results/2026-10-18) · [향후 실환경 평가 절차](../docs/validation/EVALUATION_PROTOCOL.md)

## 포함한 실험

| 실험 | 입력 | 결과 파일 | 확인하는 내용 |
|---|---|---|---|
| 낙상 후처리 | [확률 시나리오 10개](fall_scenarios.json) | `fall_trace.csv`, `fall_summary.json`, `fall_timeline.svg` | 단발성 확률 상승, 회복, 시간 초과, 확정 후 빈 방·품질 저하 |
| 호흡 주파수 추정 | 5개 주파수 × 잡음 4수준 × 시드 3개 | `respiration_trials.csv`, `respiration_summary.json`, `respiration_sweep.svg` | 합성 주기 성분의 복원 오차와 추정값 반환 비율 |
| 비주기·불충분 입력 | 영 신호, 상수, 백색잡음, 짧은 기록, 오래된 입력 | `respiration_probes.json` | 단일 노드 추정기가 값을 반환하는 조건 |
| 패킷 누락 | 누락률 6수준 × 패턴 2개 × 시드 3개 | `packet_loss_trials.csv`, `packet_loss.svg` | 입력 품질 점수와 실제 최대 패킷 간격의 관계 |
| 노드 누락 | 노드 0·1·2·4개 | `node_mask_results.json` | 고정 텐서 크기와 노드 마스크 |
| 서버 연결 | 합성 `live-status`와 임시 Node.js 서버 | `server_bridge.json` | 경보 전달과 누락값·오래된 상태 처리 |
| 기존 검사 | 저장소 단위 테스트와 자체 점검 | `unit_tests.txt`, `test_summary.json`, `selftest.txt` | 검사 결과 및 건너뛴 항목 공개 |

## 실행

Python 3.10 이상에서 저장소 루트를 기준으로 실행합니다. 서버 연결 실험에는 Node.js가 추가로 필요합니다. `requirements.txt`는 엣지 서비스의 의존성을 바꾸지 않는 실험용 목록입니다.

```bash
python -m pip install -r experiments/requirements.txt
python experiments/run_experiments.py --output experiments/results/local
python experiments/check_server_bridge.py --output experiments/results/local
```

Node.js가 PATH에 없다면 `--node /실제/경로/node`를 지정합니다. 가상환경 사용을 권장하며, 게시된 환경의 패키지 버전은 [environment.json](results/2026-10-18/environment.json)에 있습니다. PyTorch가 없으면 관련 검사를 건너뛰고 그 목록을 저장합니다. 이번 실행은 PyTorch 미설치 환경입니다.

서버 실험은 임시 폴더에 서버 코드만 복사하고 수신 주소만 `127.0.0.1`로 바꿉니다. 서비스 계정·기존 상태 파일을 복사하지 않으며, 사용 후 서버를 종료합니다. 서버에 보내는 낙상·호흡 입력은 모두 시연용으로 생성합니다.

## 결과를 읽을 때

- `environment.json`은 실행 시각·체크아웃 커밋·설정·시드와 입력 파일의 SHA-256을 기록합니다. 실험 스크립트는 실행 당시 새 파일일 수 있으므로 스크립트 해시도 함께 확인합니다.
- 시드는 `7, 19, 42`로 고정합니다. 같은 패키지 버전과 입력에서 재실행해 CSV/JSON 수치를 비교할 수 있습니다. 실행 시각·체크아웃 커밋·검사 소요 시간은 달라질 수 있습니다.
- `run_experiments.py`의 종료 코드 0은 지정한 상태 시나리오·기존 검사·수치 유한성 확인에 해당합니다. 호흡 정확도·서비스 배포 기준을 통과했다는 의미가 아닙니다.
- `check_server_bridge.py`의 종료 코드 0은 확정 경보와 제공 호흡값의 전달 확인에 해당합니다. 나머지 관측값은 해결되지 않은 동작을 기록합니다.
- 시나리오의 기대값은 현재 로직을 설명하기 위한 것입니다. 모든 기대값과 일치해도 임계값의 실환경 적절성이 입증되지는 않습니다.
- 저장된 SVG는 CSV 결과로 그린 그래프이며, 사진이나 학습 데이터가 아닙니다.
