# hanium_fall_v1 — 개발보고서의 1D-CNN 낙상 감지 모델

개발보고서 4.2절의 `CSI1DCNN`(134채널 × 500패킷 입력, 낙상/비낙상 2분류)을 그대로 옮기고, 팀이 학습한 가중치·학습 데이터·평가 코드를 함께 공개합니다. 실시간 서비스용으로 다시 설계한 다중 노드 모델은 [`../hanium_fall_v2`](../hanium_fall_v2)입니다.

| 파일 | 역할 |
|---|---|
| [`model.py`](model.py) | `CSI1DCNN` — Conv1d 3단(32→64→128채널, 커널 7→5→3) + 평균 풀링 + Linear, 파라미터 65,762개 |
| [`data.py`](data.py) | [데이터셋](../../dataset) NPZ·메타데이터 읽기, 윈도우 단위 z-score, 채널 묶음 선택 |
| [`train.py`](train.py) | 가중 교차 엔트로피 학습, 분할 방식 3가지(윈도우 무작위·녹화 단위·날짜 단위) |
| [`evaluate.py`](evaluate.py) | 저장된 가중치를 수집일별·동작별로 평가 |
| [`realtime_inference.py`](realtime_inference.py) | UDP 5005로 받은 RuView 패킷을 학습과 같은 방식으로 변환해 실시간 추론 |
| [`replay_recording.py`](replay_recording.py) | 공개한 원본 녹화를 원래 시간 간격대로 UDP로 다시 보내는 센서 없는 시연 도구 |
| [`weights/`](weights) | 팀 학습 가중치 2개 (각 273KB) |

## 가중치

| 파일 | 만든 날짜 | SHA-256 앞 16자리 | 비고 |
|---|---|---|---|
| `team_v1_0717.pth` | 2026-07-17 | `13e202c4d35781f7` | 팀 실시간 추론 스크립트가 쓰던 가중치. 07-24·07-28 데이터보다 먼저 만들어짐 |
| `team_v1_0803.pth` | 2026-08-03 | `a71881cdafa1abde` | 이후 추가 수집 데이터로 다시 학습한 가중치 |

출력 `softmax[:, 0]`이 낙상 확률입니다(`model.FALL_INDEX`). 입력은 윈도우 전체 134×500 값의 평균·표준편차로 정규화합니다.

## 실행

```bash
pip install -r requirements.txt torch             # edge_ai/ 에서
# 내려받기 없이 저장소의 샘플 15개로 바로 확인
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all     --npz-dir ../dataset/sample --metadata ../dataset/sample/sample_windows.csv

python ../dataset/tools/download.py               # 학습 윈도우 NPZ 4개 (189MB)
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all
python -m hanium_fall_v1.train --protocol recording --channels all --out ../experiments/results/v1/recording_all
python ../experiments/run_v1_experiments.py      # 공개한 v1 결과 전체 재현 (CPU 약 15분)
```

실시간 추론(센서 노드가 이 PC로 UDP를 보내는 경우):

```bash
python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all
```

센서 없이 같은 경로를 확인하려면 원본 녹화(`python ../dataset/tools/download.py --raw`)를 다른 터미널에서 재생합니다. 07-08 낙상 녹화를 8배속으로 40초 재생했을 때 패킷 폭 134를 자동으로 고르고 0.5초마다 낙상 확률을 계산해 경보를 냈습니다.

```bash
python -m hanium_fall_v1.replay_recording ../dataset/raw/recordings/csi-1783443615.csi.jsonl --speed 8 --seconds 40
```

## 검증 결과 요약

전체 표와 해석은 [실측 데이터 검증 결과](../../experiments/MEASURED_RESULTS.md)에 있습니다.

| 평가 | 낙상 재현율 | AUROC |
|---|---:|---:|
| 보고서 방식: 1,019개 윈도우 무작위 80/20 분할, 5회 | 0.997 | 1.000 |
| 2,217개 전체, 윈도우 무작위 분할, 5회 | 0.929 | 0.987 |
| 같은 분할에서 CSI가 아닌 헤더 5채널만 사용 | 0.970 | 0.992 |
| 녹화 단위 5겹 교차검증 (같은 녹화가 학습·시험에 동시에 들어가지 않음) | 0.552 | 0.542 |
| 날짜 분할: 07-08~07-15 학습 → 07-24·07-28 시험 | 0.053 | 0.712 |
| `team_v1_0717.pth`를 이후 수집일(07-24·07-28)에 적용 | 0.000 | 0.75 |

윈도우를 무작위로 나누면 보고서 수치가 재현되지만, 헤더 값만으로도 같은 성능이 나옵니다. 같은 녹화의 이웃 구간이 학습과 시험에 함께 들어가 녹화 자체를 알아보는 것으로 판단됩니다. 처음 보는 녹화나 다른 날의 데이터에서는 성능이 크게 떨어지므로, 이 모델은 보고서 결과의 재현과 비교 기준으로 공개합니다.

## 입력에 대해 알아 둘 점

- 134채널 중 0~4번은 패킷 헤더 값(주파수·패킷 순번·RSSI·잡음·플래그)입니다. `--channels csi`로 빼거나 `--channels lltf`로 첫 LLTF 블록만 쓸 수 있습니다([채널 구성](../../dataset/README.md#134채널의-실제-구성)).
- 4개 노드의 패킷이 도착 순서대로 섞여 한 시계열이 됩니다. 노드 구분은 학습 데이터에 남아 있지 않습니다.
- 07-24부터 노드가 보내는 패킷 폭이 바뀌어 69~133번 채널의 의미가 달라집니다.
- 개발보고서의 "약 8.7만 파라미터"는 같은 코드로 계산하면 65,762개입니다.

v2 파이프라인은 이 문제들을 노드별 분리, LLTF 블록 고정 선택, 32Hz 시간축 보간으로 다룹니다.
