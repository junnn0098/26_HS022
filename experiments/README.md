# 실험

이 폴더에는 성격이 다른 두 가지 검증이 있습니다. 모델 성능은 실측 데이터 평가에서만 인용합니다.

| 구분 | 입력 | 결과 보고서 | 확인하는 내용 |
|---|---|---|---|
| 실측 데이터 모델 평가 | 팀이 수집한 [CSI 데이터셋](../dataset/README.md)의 5초 윈도우 2,217개 | **[실측 데이터 검증 결과](MEASURED_RESULTS.md)** | 낙상 감지 모델(v1·v2)의 분할 방식별 성능, 신호 진단 |
| 합성 입력 기반 소프트웨어 검증 | 사람이 정한 확률, 합성 신호, 합성 JSON | [합성 입력 기반 소프트웨어 검증 결과](RESULTS.md) | 상태기계, 호흡 추정기, 패킷·노드 누락 처리, 서버 연동 |

## 실측 데이터 모델 평가

PyTorch와 데이터셋 파일이 필요합니다. 내려받기와 실행 순서는 [재현 절차](MEASURED_RESULTS.md#재현)에 있습니다.

| 스크립트 | 하는 일 | 결과 위치 |
|---|---|---|
| [`run_v1_experiments.py`](run_v1_experiments.py) | v1 모델(`CSI1DCNN`, 134채널 × 500)을 윈도우 무작위·녹화 단위·날짜 분할로 학습·평가하고 팀 가중치를 적용 | [`results/v1/`](results/v1) |
| [`v2_measured.py`](v2_measured.py) | v2 파이프라인을 같은 윈도우·라벨·분할로 학습·평가 | [`results/v2_measured/`](results/v2_measured) |
| [`signal_diagnostics.py`](signal_diagnostics.py) | 모델 없이 CSI 움직임 지표로 동작 구분 정도를 진단 | [`results/diagnostics/`](results/diagnostics) |
| [`make_results_table.py`](make_results_table.py) | 위 결과로 실측 결과 표를 출력 | 표준 출력 |
| [`plot_figures.py`](plot_figures.py) | 데이터셋 구성 그림과 평가 방식 비교 그림(v2 결과가 있을 때) | [`../dataset/figures/`](../dataset/figures), `results/figures/` |

## 합성 입력 기반 소프트웨어 검증

센서와 학습 가중치 없이 실행합니다. 입력이 모두 합성값이므로 결과는 낙상 감지 정확도나 사람의 호흡 측정 정확도가 아니라, 코드가 정한 대로 동작하는지에 대한 확인입니다.

| 실험 | 입력 | 결과 파일 | 확인하는 내용 |
|---|---|---|---|
| 낙상 상태기계 | [확률 시나리오 10개](fall_scenarios.json) | `fall_trace.csv`, `fall_summary.json`, `fall_timeline.svg` | 단발성 확률 상승, 회복, 시간 초과, 확정 후 빈 방·품질 저하 |
| 호흡 주파수 추정 | 5개 주파수 × 잡음 4수준 × 시드 3개 | `respiration_trials.csv`, `respiration_summary.json`, `respiration_sweep.svg` | 합성 주기 성분의 복원 오차와 추정값 반환 비율 |
| 비주기·불충분 입력 | 영 신호, 상수, 백색잡음, 짧은 기록, 오래된 입력 | `respiration_probes.json` | 단일 노드 추정기가 값을 반환하는 조건 |
| 패킷 누락 | 누락률 6수준 × 패턴 2개 × 시드 3개 | `packet_loss_trials.csv`, `packet_loss.svg` | 입력 품질 점수와 실제 최대 패킷 간격의 관계 |
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
| [`results/2026-10-18/`](results/2026-10-18) | `run_experiments.py` 결과(Linux, PyTorch 미설치)와 서버 수정 전 관측 기록 |
| [`results/2026-10-19/`](results/2026-10-19) | 현재 `local_server.js`·`jetson_edge_client.py` 기준 서버 연동 검사 |

### 결과를 읽을 때

- `environment.json`과 `server_bridge.json`은 입력·스크립트 파일의 SHA-256을 기록합니다. 해시는 줄바꿈을 LF로 맞춘 내용과 저장소 기준 POSIX 경로로 계산하므로 Windows와 Linux 체크아웃에서 같은 값이 나옵니다.
- 시드는 `7, 19, 42`로 고정합니다. 같은 패키지 버전과 입력에서 재실행해 CSV/JSON 수치를 비교할 수 있으며, 실행 시각·커밋·검사 소요 시간은 달라집니다.
- `run_experiments.py`의 종료 코드 0은 상태기계 시나리오 일치, 기존 검사 통과, 수치 유한성 확인을 뜻합니다. 호흡 정확도나 배포 기준을 통과했다는 뜻은 아닙니다.
- `check_server_bridge.py`의 종료 코드 0은 `server_bridge.json`의 `expected` 항목이 모두 관측값과 일치했다는 뜻입니다. Flutter 화면과 FCM 단말 수신은 포함하지 않습니다.
- 시나리오의 기대값은 현재 로직을 설명하기 위한 것이며, 임계값이 실환경에 적절하다는 근거는 아닙니다.
- 저장된 SVG는 CSV 결과로 그린 그래프입니다.
