# hanium_fall_v1 — 1D-CNN 낙상 감지 모델

134채널 × 500패킷 입력, 낙상/비낙상 2분류 1D-CNN(`CSI1DCNN`)과 팀 학습 가중치·학습 데이터([`dataset/`](../../dataset))·평가 코드를 공개합니다. 실시간 서비스용 다중 노드 파이프라인은 [`../hanium_fall_v2`](../hanium_fall_v2)입니다.

| 파일 | 역할 |
|---|---|
| [`model.py`](model.py) | `CSI1DCNN` — Conv1d 3단(32→64→128채널, 커널 7→5→3) + 평균 풀링 + Linear |
| [`data.py`](data.py) | [데이터셋](../../dataset) NPZ·메타데이터 읽기, 윈도우 단위 z-score, 채널 묶음 선택 |
| [`train.py`](train.py) | 가중 교차 엔트로피 학습, 분할 방식 3가지(윈도우 무작위·녹화 단위·날짜 단위) |
| [`evaluate.py`](evaluate.py) | 저장된 가중치를 수집일별·동작별로 평가 |
| [`realtime_inference.py`](realtime_inference.py) | UDP 5005로 받은 RuView 패킷을 학습과 같은 방식으로 변환해 실시간 추론 |
| [`replay_recording.py`](replay_recording.py) | 공개한 원본 녹화를 원래 시간 간격대로 UDP로 다시 보내는 센서 없는 시연 도구 |
| [`weights/`](weights) | 팀 학습 가중치 2개 (각 273KB) |

## 가중치

| 파일 | 만든 날짜 | SHA-256 앞 16자리 | 비고 |
|---|---|---|---|
| `team_v1_0717.pth` | 2026-07-17 | `13e202c4d35781f7` | 실시간 추론 예시의 기본 가중치 |
| `team_v1_0803.pth` | 2026-08-03 | `a71881cdafa1abde` | 이후 다시 학습한 가중치 |

출력 `softmax[:, 0]`이 낙상 확률입니다(`model.FALL_INDEX`). 입력은 윈도우 전체 134×500 값의 평균·표준편차로 정규화합니다.

## 실행

```bash
pip install -r requirements.txt torch             # edge_ai/ 에서
# 내려받기 없이 저장소의 샘플 15개로 실행 확인
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all     --npz-dir ../dataset/sample --metadata ../dataset/sample/sample_windows.csv

python ../dataset/tools/download.py               # 학습 윈도우 NPZ 4개 (189MB)
python -m hanium_fall_v1.train --protocol random --channels all --seeds 0 1 2 3 4 --threads 2 --out ../experiments/results/v1/random_all
python -m hanium_fall_v1.train --protocol random --channels all --seeds 0 1 2 3 4 --threads 2 --batches b1_0708_0709 --out ../experiments/results/v1/b1_random
python ../experiments/run_v1_experiments.py      # 위 두 결과를 한 번에 재현 (CPU 약 7분)
```

실시간 추론(센서 노드가 이 PC로 UDP를 보내는 경우):

```bash
python -m hanium_fall_v1.realtime_inference --weights hanium_fall_v1/weights/team_v1_0717.pth --channels all
```

센서 없이 같은 경로를 확인하려면 다른 터미널에서 녹화를 재생합니다. 저장소에 07-08 낙상 녹화 12초(`dataset/sample/raw`)가 들어 있어 내려받기 없이 바로 확인할 수 있습니다. 재생하면 패킷 폭 134를 자동으로 고르고 버퍼가 500패킷 찬 뒤부터 0.5초마다 낙상 확률을 계산합니다.

```bash
python -m hanium_fall_v1.replay_recording ../dataset/sample/raw/csi-1783443615.fall-12s.csi.jsonl.gz
python -m hanium_fall_v1.replay_recording ../dataset/raw/recordings/csi-1783443615.csi.jsonl --speed 4   # 전체 녹화 (--raw로 내려받은 경우)
```

## 학습 결과 요약

v1 `CSI1DCNN`을 라벨별 층화 윈도우 단위 무작위 80/20 분할로 5개 시드(0–4) 학습·평가했습니다. 낙상 판정 임계값은 0.5이고, 수치는 5회 평균 ± 표준편차, TP·FP·TN·FN은 5회 시험 세트 합계입니다. 전체 표는 [실측 데이터 학습 결과](../../experiments/MEASURED_RESULTS.md)에 있습니다.

| 데이터 | 낙상 재현율 | 정밀도 | F1 | AUROC | TP / FP / TN / FN | 비틀거리기 오탐 |
|---|---:|---:|---:|---:|---:|---:|
| 1·2차 수집(07-08·07-09) 1,019개 윈도우 | 0.997 ± 0.007 | 0.990 ± 0.008 | 0.993 ± 0.006 | 1.000 ± 0.000 | 299 / 3 / 712 / 1 | 0 |
| 전체 2,217개 윈도우(07-08–07-28) | 0.922 ± 0.014 | 0.953 ± 0.021 | 0.937 ± 0.016 | 0.986 ± 0.004 | 894 / 44 / 1,196 / 76 | 0 |

전체 2,217개 윈도우에서 특이도는 0.965, 정확도는 0.946입니다. 두 데이터 모두 낙상과 헷갈리기 쉬운 비틀거리기(`stumble_no_fall`)를 낙상으로 판정한 경우가 없었습니다.

## 입력 형식

- 134채널 = 패킷 헤더 필드 5채널(0–4번) + LLTF 64채널(5–68번) + 두 번째 64값 블록(69–132번) + 1채널(133번)입니다([134채널 구성](../../dataset/README.md#134채널-구성)).
- `--channels`로 입력 채널 묶음을 고를 수 있습니다: `all`(134채널 전체), `csi`(5–133번), `lltf`(5–68번).
- 4개 노드의 패킷을 도착 순서대로 이어 하나의 500패킷 시계열로 씁니다.
- 69–133번 채널의 구성은 노드가 보내는 패킷 폭(134·198)에 따라 정해집니다.

v2 파이프라인은 노드별 분리, LLTF 블록 고정 선택, 32Hz 시간축 보간을 적용한 193채널 × 160프레임 입력을 씁니다.
