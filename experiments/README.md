# 실험

이 폴더에는 두 가지 검증이 있습니다.

| 구분 | 입력 | 결과 문서 | 확인하는 내용 |
|---|---|---|---|
| 실측 데이터 학습 | 팀이 수집한 [CSI 데이터셋](../dataset/README.md)의 5초 윈도우 | **[실측 데이터 학습 결과](MEASURED_RESULTS.md)** | v1 1D-CNN 낙상 감지 모델의 재현율·정밀도·F1·AUROC, 동작별 오탐 |
| 합성 입력 기반 소프트웨어 검증 | 정해 둔 확률, 합성 신호, 합성 JSON | [합성 입력 기반 소프트웨어 검증 결과](RESULTS.md) | 상태기계, 호흡 추정기, 패킷·노드 누락 처리, 서버 연동 |

## 실측 데이터 학습

PyTorch와 데이터셋 파일이 필요합니다. 내려받기와 실행 순서는 [재현 절차](MEASURED_RESULTS.md#재현)에 있습니다.

| 스크립트 | 하는 일 | 결과 위치 |
|---|---|---|
| [`run_v1_experiments.py`](run_v1_experiments.py) | v1 모델(`CSI1DCNN`, 134채널 × 500)을 기본 동작 세트(11종) 1,019개(`b1_random`)와 전체 동작 세트(15종) 2,217개(`random_all`)에서 윈도우 무작위 80/20, 시드 5회로 학습·평가 | [`results/v1/`](results/v1) |
| [`make_results_table.py`](make_results_table.py) | 결과 표와 동작별 오탐 표를 출력 | 표준 출력 |
| [`plot_figures.py`](plot_figures.py) | 데이터셋 구성 그림과 v1 결과 그림 | [`../dataset/figures/`](../dataset/figures), [`results/figures/`](results/figures) |

## 합성 입력 기반 소프트웨어 검증

센서와 학습 가중치 없이 실행합니다. 입력이 모두 합성값이므로 결과는 낙상 감지 정확도나 호흡 측정 정확도가 아니라, 코드가 설계대로 동작하는지에 대한 확인입니다.

| 실험 | 입력 | 결과 파일 | 확인하는 내용 |
|---|---|---|---|
| 낙상 상태기계 | [확률 시나리오 10개](fall_scenarios.json) | `fall_trace.csv`, `fall_summary.json`, `fall_timeline.svg` | 단발성 확률 상승, 회복, 시간 초과, 확정 후 빈 방·품질 저하 |
| 호흡 주파수 추정 | 5개 주파수 × 잡음 4수준 × 시드 3개 | `respiration_trials.csv`, `respiration_summary.json`, `respiration_sweep.svg` | 합성 주기 성분의 복원 오차와 추정값 반환 비율 |
| 비주기·불충분 입력 | 영 신호, 상수, 백색잡음, 짧은 기록, 오래된 입력 | `respiration_probes.json` | 단일 노드 추정기의 반환 조건과 신뢰도 |
| 패킷 누락 | 누락률 6수준 × 패턴 2개 × 시드 3개 | `packet_loss_trials.csv`, `packet_loss.svg` | 입력 품질 점수와 최대 패킷 간격의 관계 |
| 노드 누락 | 노드 0·1·2·4개 | `node_mask_results.json` | 고정 텐서 크기와 노드 마스크 |
| 서버 연동 | 합성 `live-status`와 임시 로컬 서버 | `server_bridge.json` | 초기 상태, 경보 전달, 판단 불가·누락 호흡값·오래된 결과 처리 |
| 기존 검사 | `edge_ai/tests` 단위 테스트와 자체 점검 | `unit_tests.txt`, `test_summary.json`, `selftest.txt` | 검사 결과와 건너뛴 항목 |

### 실행

Python 3.10 이상에서 저장소 루트를 기준으로 실행합니다. 서버 연동 검사에는 Node.js가 필요하며, PATH에 없으면 `--node <node 경로>`를 지정합니다. `requirements.txt`는 엣지 서비스의 의존성과 별개인 실험용 목록입니다.

```bash
python -m pip install -r experiments/requirements.txt
python experiments/run_experiments.py --output experiments/results/local
python experiments/check_server_bridge.py --output experiments/results/local
```

서버 연동 검사는 `app/server/local_server.js`와 `package.json`을 임시 폴더에 그대로 복사하고 환경 변수 `HOST=127.0.0.1`, 빈 포트, `REAL_SENSOR_ONLY=true`로 실행합니다. 서비스 계정·상태 파일·API 토큰은 복사하거나 전달하지 않으며, 검사가 끝나면 서버를 종료합니다.

### 결과 폴더

| 폴더 | 내용 |
|---|---|
| [`results/2026-10-18/`](results/2026-10-18) | `run_experiments.py` 결과(Linux, PyTorch 미설치) |
| [`results/2026-10-19/`](results/2026-10-19) | `local_server.js`·`jetson_edge_client.py` 서버 연동 검사 |

### 결과 파일 읽는 법

- `environment.json`과 `server_bridge.json`은 입력·스크립트 파일의 SHA-256을 기록합니다. 해시는 줄바꿈을 LF로 맞춘 내용과 저장소 기준 POSIX 경로로 계산하므로 Windows와 Linux 체크아웃에서 같은 값이 나옵니다.
- 시드는 `7, 19, 42`로 고정합니다. 같은 패키지 버전과 입력에서 재실행해 CSV/JSON 수치를 비교할 수 있으며, 실행 시각·커밋·검사 소요 시간은 달라집니다.
- `run_experiments.py`의 종료 코드 0은 상태기계 시나리오 일치, 기존 검사 통과, 수치 유한성 확인을 뜻합니다.
- `check_server_bridge.py`의 종료 코드 0은 `server_bridge.json`의 `expected` 항목이 모두 관측값과 일치했다는 뜻입니다. Flutter 화면과 FCM 단말 수신은 포함하지 않습니다.
- 시나리오의 기대값은 현재 상태기계 로직을 기준으로 정했습니다.
- 저장된 SVG는 CSV 결과로 그린 그래프입니다.
