# 실측 WiFi CSI 낙상 데이터셋

팀이 직접 구축한 센서 환경(ipTIME 공유기 1대 + XIAO ESP32-S3 수신 노드 4대)에서 수집한 WiFi CSI와, 같은 시간에 웹캠으로 기록한 사람 관절 좌표입니다. 모델 학습·검증에 사용한 윈도우 전부와 그 원본 녹화를 공개합니다.

| 항목 | 내용 |
|---|---|
| 수집 기간 | 2026-07-08–2026-07-28, 3주 동안 5회 |
| 원본 녹화 | 48건 × 5분 = 4시간 (CSI 패킷 약 260만 개, 관절 좌표 프레임 약 31만 개) |
| 학습 윈도우 | **2,217개** (134채널 × 500패킷, 시간 길이 중앙값 5.0초·범위 4–42초), 이 중 낙상 **969개** |
| 동작 | 15종 = 낙상 1종 + 낙상과 헷갈리기 쉬운 동작 6종 + 일상 동작 8종 |
| 참여자 | 익명 ID `S1`, `S2` (07-24·07-28 기록). 그 이전 녹화는 참여자 미기록(`unrecorded`) |
| 1·2차 수집 | 07-08·07-09 녹화 17건의 윈도우 1,019개(낙상 302개, 11종). 학습 결과는 [실측 데이터 학습 결과](../experiments/MEASURED_RESULTS.md) |

<p align="center"><img src="figures/composition.png" alt="수집일별 학습 윈도우 구성" width="720"></p>

## 파일 구성과 내려받기

용량이 큰 파일은 저장소의 [GitHub Release `dataset-v1.0`](https://github.com/junnn0098/26_HS022/releases/tag/dataset-v1.0)에 올려 두었습니다. 내려받기 도구가 [SHA-256](SHA256SUMS)을 확인합니다.

```bash
python dataset/tools/download.py            # 학습 윈도우 NPZ 4개 (189MB) -> dataset/data/
python dataset/tools/download.py --v2       # v2 형식 세션 48개 (156MB) -> dataset/v2_sessions/
python dataset/tools/download.py --raw      # 원본 CSI·관절 좌표 녹화 (788MB) -> dataset/raw/
```

| 파일 | 위치 | 내용 |
|---|---|---|
| [`metadata/recordings.csv`](metadata/recordings.csv) | 저장소 | 녹화 48건: 날짜, 동작 라벨, 참여자 ID, 노드별 패킷 수·수신 세기(RSSI), 패킷 폭 분포, 웹캠 프레임 수·검출 신뢰도 |
| [`metadata/windows.csv`](metadata/windows.csv) | 저장소 | 윈도우 2,217개: 출처 녹화, 녹화 안의 순번, 시작·끝 시각(UTC), 라벨, 몸통 하강 지표 |
| [`sample/`](sample) | 저장소 | 라벨마다 윈도우 1개(15개), 낙상 녹화 2초 분량의 원본 CSI·관절 좌표, 실시간 추론 재생 시연용 낙상 녹화 12초(`.csi.jsonl.gz`) |
| `csi134_b1_0708_0709.npz` 외 3개 | Release | 팀 학습 윈도우. `X` float32 `(N, 500, 134)`, `window_id` |
| `v2_sessions.zip` | Release | 원본에서 첫 LLTF 블록(64 서브캐리어)만 뽑아 v2 파이프라인 세션 형식으로 바꾼 48개 파일 |
| `raw_2026-07-08.tar.xz` 외 4개 | Release | 원본 녹화: `recordings/csi-<epoch>.csi.jsonl`, `ground-truth/keypoints_<KST 시각>.jsonl` |

```python
import numpy as np, csv
x = np.load("dataset/sample/csi134_sample.npz")
print(x["X"].shape, x["window_id"][:3])          # (15, 500, 134)
rows = list(csv.DictReader(open("dataset/metadata/windows.csv", encoding="utf-8")))
```

학습 코드는 [`edge_ai/hanium_fall_v1/data.py`](../edge_ai/hanium_fall_v1/data.py)의 `load_windows()`로 NPZ와 `windows.csv`를 함께 읽고, 두 파일의 `window_id`가 일치하는지 확인합니다.

## 수집 방법

```text
ipTIME A2004SR ── 2.4GHz 6번 채널(2437MHz) 고정, 센서 전용 SSID
      │  WiFi 패킷
      ▼
ESP32-S3 ×4 (RuView 펌웨어) ──UDP 5005──▶ 수집 PC: RuView 녹화기 → recordings/csi-<epoch>.csi.jsonl
웹캠 ── 관절 좌표 추정(COCO 17점, 약 20–30fps) ─────▶ ground-truth/keypoints_<시각>.jsonl
```

- 한 녹화는 5분 동안 한 동작을 반복합니다. 낙상 녹화에서는 넘어짐 → 누운 상태 → 일어남이 약 8초 간격으로 되풀이됩니다.
- 학습용 웹캠은 프레임을 저장하지 않고 관절 좌표만 기록했습니다. 공개 데이터에는 관절 좌표만 있습니다. (README의 수집 장면 영상은 수집 과정을 보여 주려고 따로 촬영한 것으로, 데이터셋과 연결되지 않습니다.)
- 노드당 패킷 수신량은 초당 약 48–50개(07-08–07-15), 37–42개(07-24·07-28)입니다.

| 날짜 | 팀 차수 | 녹화 | 학습에 쓴 녹화 | 윈도우 | 낙상 윈도우 | 노드당 패킷/초 | 참여자 |
|---|---|---:|---:|---:|---:|---:|---|
| 2026-07-08 | 1차 | 8 | 8 | 502 | 127 | 49.8 | 미기록 |
| 2026-07-09 | 2차 | 9 | 9 | 517 | 175 | 48.2 | 미기록 |
| 2026-07-15 | 낙상 보강 | 12 | 9 | 434 | 308 | 48.7 | 미기록 |
| 2026-07-24 | 3차 | 13 | 13 | 446 | 203 | 37.5 | S1, S2 |
| 2026-07-28 | 4차 | 6 | 6 | 318 | 156 | 42.2 | S1 |
| **합계** | | **48** | **45** | **2,217** | **969** | | |

07-15의 3건(걷기, 누웠다 일어나기, 앉아 있기)은 웹캠 관절 검출 신뢰도가 평균 0.21–0.31로 낮아 팀이 학습에서 뺐습니다. 원본 녹화에는 들어 있습니다.

## 동작 라벨

| 분류 | 라벨 | 동작 | 윈도우 | 녹화 |
|---|---|---|---:|---:|
| 낙상 | `fall` | 낙상 | 969 | 20 |
| 혼동 동작 | `lie_stand` | 누웠다 일어나기 | 91 | 2 |
| | `sit_lie` | 앉았다가 눕기(반복) | 61 | 1 |
| | `stumble_no_fall` | 비틀거리기(넘어지지 않음) | 56 | 1 |
| | `walk_pickup` | 걸어다니며 물건 줍기 | 56 | 1 |
| | `bend_pickup` | 허리 숙여 물건 줍기 | 51 | 1 |
| | `squat_stand` | 쪼그려 앉았다 일어나기 | 36 | 1 |
| 일상 동작 | `sit_stand` | 앉았다 일어나기 | 319 | 6 |
| | `sitting` | 가만히 앉아 있기 | 161 | 3 |
| | `walking` | 걷기 | 147 | 3 |
| | `standing` | 가만히 서 있기 | 64 | 1 |
| | `lying` | 누워 있기 | 64 | 2 |
| | `arm_wave` | 팔 흔들기 | 63 | 1 |
| | `sit_down` | 앉기 | 47 | 1 |
| | `chair_workout` | 의자에서 움직이기 | 32 | 1 |

라벨 정의는 [`tools/labels.py`](tools/labels.py)에 있습니다. v2 모델의 10종 라벨로 바꾸는 규칙은 [`tools/raw_to_v2.py`](tools/raw_to_v2.py)의 `V2_ACTIVITY`입니다(여러 동작이 섞인 녹화는 `other_motion`).

## 학습 윈도우를 만든 과정

1. **시간 맞추기**: RuView의 `align-ground-truth.js`가 CSI 패킷과 관절 좌표를 시각으로 맞춰 20패킷 묶음을 만듭니다. 녹화에서 가장 흔한 패킷 폭(134 또는 198)의 패킷만 쓰고, 4개 노드의 패킷을 도착 순서대로 이어 붙입니다.
2. **500패킷 윈도우**: 20패킷 묶음 25개를 이어 500패킷 윈도우를 만들고, 폭을 134로 자르거나 0으로 채운 뒤 녹화 라벨을 붙입니다(팀 변환 스크립트 `convert_for_ai_team_134ch_v3.py`의 규칙).
3. **출처 복원**: [`tools/export_windows.py`](tools/export_windows.py)가 위 과정을 다시 수행해 팀 학습 파일의 2,217개 윈도우와 **모든 값이 일치함**을 확인한 뒤, 윈도우마다 출처 녹화·순번·시각을 기록하고 참여자 이름을 익명 ID로 바꿉니다.
4. **보조 지표**: [`tools/pose_events.py`](tools/pose_events.py)가 윈도우 안에서 1초 이내에 몸통(어깨·엉덩이)이 내려간 최대 거리(`pose_max_drop_1s`)를 계산합니다. 카메라 위치에 따라 값의 크기가 달라 단독 판정 기준으로는 쓰지 않습니다.

```bash
# RuView 작업 폴더(비공개 원본)에서 공개 파일을 다시 만드는 순서
python dataset/tools/export_windows.py     --ruview <RuView> --out <폴더> --subject-map <비공개 대응표.csv>
python dataset/tools/inventory_recordings.py --ruview <RuView> --subject-map <비공개 대응표.csv>
python dataset/tools/pose_events.py        --ruview <RuView>
python dataset/tools/raw_to_v2.py          --raw <RuView>/data/recordings --out <폴더>
```

## 134채널 구성

134개 값은 RuView 페이로드의 패킷 오프셋 10부터 2바이트씩 I/Q 쌍으로 읽어 계산한 크기 값입니다. 채널별 구성은 다음과 같습니다.

| 채널 | 내용 |
|---|---|
| 0–4 | 패킷 헤더 필드: 주파수 상위 바이트(항상 0), 패킷 순번, 순번 상위 바이트, RSSI·잡음 하한, PPDU·플래그 |
| 5–68 | 첫 번째 LLTF 블록 64개 서브캐리어 (5번은 펌웨어가 무효로 표시하는 첫 값이라 0) |
| 69–132 | 두 번째 64개 블록. 패킷 폭(134/198)에 따라 담기는 값이 다름 (07-24부터 198폭 패킷이 대부분) |
| 133 | 134폭 패킷에서는 0, 198폭 패킷에서는 세 번째 블록의 첫 값 |

[`edge_ai/hanium_fall_v1/data.py`](../edge_ai/hanium_fall_v1/data.py)의 `CHANNEL_SETS`로 학습에 쓸 채널 묶음을 고를 수 있으며, 기본값(`all`)은 134채널 전체입니다. 실시간 경로([`realtime_inference.py`](../edge_ai/hanium_fall_v1/realtime_inference.py))는 학습 때와 같은 방식으로 값을 추출하며, 원본 녹화에서 추출한 값이 학습 윈도우와 일치함을 확인했습니다.

## 사용할 때 주의할 점

- **라벨은 녹화 단위입니다.** 낙상 녹화의 윈도우는 모두 `fall`이며, 넘어지는 순간·누워 있는 시간·일어나는 동작이 함께 들어 있습니다. 구간별 몸통 하강 정도는 `windows.csv`의 `pose_max_drop_1s`로 확인할 수 있습니다.
- **`windows.csv`의 `recording` 열로 녹화 단위 분할을 할 수 있습니다.** 15종 중 9종은 녹화 1건으로 수집했으므로, 녹화 단위로 나누면 해당 동작은 학습·시험 중 한쪽에만 들어갑니다.
- **윈도우 길이는 패킷 수(500개) 기준입니다.** 시간 길이는 중앙값 5.0초, 범위 4.0–41.6초이며, 07-24 녹화는 중앙값 약 7.5초입니다(`windows.csv`의 `duration_s`).
- 07-24부터는 노드가 보낸 패킷 폭이 대부분 198이고, 노드 1의 수신량이 적은 녹화가 있습니다(`recordings.csv`의 `nodes`, `modal_width`).
- 노드별 RSSI는 07-09 오후, 07-15, 07-24에 각각 달라집니다(`recordings.csv`의 `rssi_mean_dbm`). 노드 배치 변화를 구분할 때 참고할 수 있습니다.
- RSSI는 원본 JSONL의 `rssi` 필드가 아니라 `iq_hex` 헤더의 9번째 바이트에서 읽습니다. 녹화기가 `rssi` 필드에 다른 바이트를 저장했기 때문이며, `recordings.csv`도 이 방식으로 계산했습니다.

## 원본 형식

**`recordings/csi-<epoch>.csi.jsonl`** (패킷 1개 = 1줄)

| 필드 | 설명 |
|---|---|
| `ts_ns` | 수집 PC 수신 시각 (Unix ns) |
| `node_id`, `subcarriers` | 보낸 노드(1–4), RuView 녹화기가 저장한 폭 = (패킷 길이 − 8) / 2. 폭 70/134/198 = 복소 값 64/128/192개(LLTF / +HT-LTF / +STBC-HT-LTF) + 헤더 6쌍 |
| `iq_hex` | RuView ADR-018 UDP 패킷의 9번째 바이트부터: 주파수(4) · 순번(4) · RSSI(1) · 잡음 하한(1) · PPDU(1) · 플래그(1) · I/Q int8 쌍 |
| `amplitudes` | 녹화기가 계산한 진폭(참고용) |

앞 8바이트(magic `0xC5110001`, node_id, 안테나 수, 서브캐리어 수)를 다시 붙이면 원래 패킷이 되므로 v2 파서 [`adr018.py`](../edge_ai/hanium_fall_v2/adr018.py)를 그대로 쓸 수 있습니다([`tools/raw_to_v2.py`](tools/raw_to_v2.py)).

**`ground-truth/keypoints_<YYYYMMDD_HHMMSS>.jsonl`** (웹캠 프레임 1개 = 1줄): `ts_ns`, `keypoints`(COCO 17점 `[x, y]`, 화면 크기로 정규화), `confidence`, `n_visible`, `n_persons`

**`v2_sessions/csi-<epoch>.npz`**: `iq` int8 `(N, 1, 64, 2)`, `received_unix_ns`, `node_id`, `sequence`, `rssi_dbm`, `noise_floor_dbm`, `ppdu`, `flags`, `source_subcarriers`, `meta_json`. [`edge_ai/hanium_fall_v2/capture_labeled.py`](../edge_ai/hanium_fall_v2/capture_labeled.py)가 만드는 세션 파일과 배열 이름이 같습니다.

## 개인정보

- 학습용 웹캠 프레임은 저장하지 않았고, 데이터셋에는 관절 좌표만 있습니다.
- 참여자는 `S1`, `S2`로만 표기합니다. 이름 대응표는 공개 저장소에 두지 않습니다.
- 수집 PC의 IP·계정 정보는 원본 파일에 없습니다.
