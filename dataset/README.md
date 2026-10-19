# 실측 WiFi CSI 낙상 데이터셋

팀이 직접 구축한 센서 환경(ipTIME 공유기 1대 + XIAO ESP32-S3 수신 노드 4대)에서 수집한 WiFi CSI와, 같은 시간에 웹캠으로 기록한 사람 관절 좌표입니다. 모델 학습·검증에 사용한 윈도우 전부와 그 원본 녹화를 공개합니다.

| 항목 | 내용 |
|---|---|
| 센서 구성 | ipTIME A2004SR 공유기 1대(2.4GHz 6번 채널 고정) + XIAO ESP32-S3 수신 노드 4대 + 관절 좌표용 웹캠 |
| 원본 녹화 | 48건 (CSI 패킷과 같은 시간의 웹캠 관절 좌표) |
| 학습 윈도우 | **2,217개** (134채널 × 500패킷, 시간 길이 중앙값 5.0초), 이 중 낙상 **969개**·혼동 동작 351개·일상 동작 897개 |
| 동작 | 15종 = 낙상 1종 + 낙상과 헷갈리기 쉬운 동작 6종 + 일상 동작 8종 |
| 라벨 | 녹화 단위 동작 라벨. 같은 시간의 웹캠 관절 좌표를 CSI와 시각으로 맞춰 함께 제공 |
| 학습·평가 묶음 | **기본 동작 세트(11종) 1,019개**(낙상 302개)와 **전체 동작 세트(15종) 2,217개**(낙상 969개). 학습 결과는 [실측 데이터 학습 결과](../experiments/MEASURED_RESULTS.md) |

<p align="center"><img src="figures/composition.png" alt="동작별 학습 윈도우 구성" width="720"></p>

## 파일 구성과 내려받기

용량이 큰 파일은 저장소의 [GitHub Release `dataset-v1.0`](https://github.com/junnn0098/26_HS022/releases/tag/dataset-v1.0)에 올려 두었습니다. 내려받기 도구가 [SHA-256](SHA256SUMS)을 확인합니다.

```bash
python dataset/tools/download.py            # 학습 윈도우 NPZ 4개 (189MB) -> dataset/data/
python dataset/tools/download.py --v2       # v2 형식 세션 48개 (156MB) -> dataset/v2_sessions/
python dataset/tools/download.py --raw      # 원본 CSI·관절 좌표 녹화 (788MB) -> dataset/raw/
```

| 파일 | 위치 | 내용 |
|---|---|---|
| [`metadata/recordings.csv`](metadata/recordings.csv) | 저장소 | 녹화 48건: 동작 라벨, 참여자 익명 ID, 노드별 패킷 수·수신 세기(RSSI), 패킷 폭 분포, 웹캠 프레임 수·검출 신뢰도 |
| [`metadata/windows.csv`](metadata/windows.csv) | 저장소 | 윈도우 2,217개: 출처 녹화, 녹화 안의 순번, 시작·끝 시각(UTC), 라벨, 몸통 하강 지표 |
| [`sample/`](sample) | 저장소 | 라벨마다 윈도우 1개(15개), 낙상 녹화 2초 분량의 원본 CSI·관절 좌표, 실시간 추론 재생 시연용 낙상 녹화 12초(`.csi.jsonl.gz`) |
| 학습 윈도우 NPZ 4개 (`csi134_*.npz`) | Release | 팀 학습 윈도우. `X` float32 `(N, 500, 134)`, `window_id`. 기본 동작 세트는 `csi134_b1_*.npz` 파일(`windows.csv`의 `batch`가 `b1_`로 시작), 전체 동작 세트는 4개 파일 전부 |
| `v2_sessions.zip` | Release | 원본에서 첫 LLTF 블록(64 서브캐리어)만 뽑아 v2 파이프라인 세션 형식으로 바꾼 48개 파일 |
| 원본 녹화 압축 파일 5개 (`raw_*.tar.xz`) | Release | 원본 녹화: `recordings/csi-<epoch>.csi.jsonl`, `ground-truth/keypoints_<KST 시각>.jsonl` |

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

1. **센서 설정**: 공유기를 2.4GHz 6번 채널에 고정하고 센서 전용 SSID를 씁니다. 수신 노드 4대가 공유기 패킷의 CSI를 UDP로 수집 PC에 보내고, RuView 녹화기가 패킷을 1줄씩 저장합니다. 노드당 초당 약 26–50개(녹화별 중앙값 약 48개) 패킷을 받았습니다.
2. **동작 수행**: 한 녹화에서는 한 가지 동작을 연속으로 반복합니다. 낙상 녹화에서는 넘어짐 → 누운 상태 → 일어남이 약 8초 간격으로 되풀이됩니다. 수행한 동작은 [동작 라벨](#동작-라벨)의 15종입니다.
3. **관절 좌표 기록**: 녹화하는 동안 웹캠으로 사람 관절 좌표를 함께 기록합니다. 학습용 웹캠은 프레임을 저장하지 않고 관절 좌표만 기록했으므로, 공개 데이터에도 관절 좌표만 있습니다. 관절 좌표는 CSI 패킷과 시각으로 맞춰 묶고([학습 윈도우를 만든 과정](#학습-윈도우를-만든-과정)), 검출 신뢰도는 녹화 품질을 확인하는 데 씁니다.
4. **라벨 기록**: 녹화 파일마다 수행한 동작 라벨을 기록하고, 참여자 이름은 공개 전에 익명 ID로 바꿉니다.
5. **품질 확인**: 웹캠 관절 검출 신뢰도가 평균 0.21–0.31로 낮은 녹화 3건(걷기, 누웠다 일어나기, 앉아 있기)은 학습 윈도우에서 뺐습니다. 원본 녹화에는 들어 있으므로 원본은 48건, 학습 윈도우를 만든 녹화는 45건입니다.

README의 수집 장면 영상은 수집 과정을 보여 주려고 따로 촬영한 것으로, 데이터셋과 연결되지 않습니다.

## 동작 라벨

| 분류 | 라벨 | 동작 | 윈도우 |
|---|---|---|---:|
| 낙상 | `fall` | 낙상 | 969 |
| 혼동 동작 | `lie_stand` | 누웠다 일어나기 | 91 |
| | `sit_lie` | 앉았다가 눕기(반복) | 61 |
| | `stumble_no_fall` | 비틀거리기(넘어지지 않음) | 56 |
| | `walk_pickup` | 걸어다니며 물건 줍기 | 56 |
| | `bend_pickup` | 허리 숙여 물건 줍기 | 51 |
| | `squat_stand` | 쪼그려 앉았다 일어나기 | 36 |
| 일상 동작 | `sit_stand` | 앉았다 일어나기 | 319 |
| | `sitting` | 가만히 앉아 있기 | 161 |
| | `walking` | 걷기 | 147 |
| | `standing` | 가만히 서 있기 | 64 |
| | `lying` | 누워 있기 | 64 |
| | `arm_wave` | 팔 흔들기 | 63 |
| | `sit_down` | 앉기 | 47 |
| | `chair_workout` | 의자에서 움직이기 | 32 |

기본 동작 세트(11종)에는 위 15종 중 `squat_stand`, `lying`, `sit_down`, `chair_workout`을 뺀 11종이 들어 있습니다.

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
| 69–132 | 두 번째 64개 블록. 패킷 폭(134/198)에 따라 담기는 값이 다름 (녹화별 주된 폭은 `recordings.csv`의 `modal_width`) |
| 133 | 134폭 패킷에서는 0, 198폭 패킷에서는 세 번째 블록의 첫 값 |

[`edge_ai/hanium_fall_v1/data.py`](../edge_ai/hanium_fall_v1/data.py)의 `CHANNEL_SETS`로 학습에 쓸 채널 묶음을 고를 수 있으며, 기본값(`all`)은 134채널 전체입니다. 실시간 경로([`realtime_inference.py`](../edge_ai/hanium_fall_v1/realtime_inference.py))는 학습 때와 같은 방식으로 값을 추출하며, 원본 녹화에서 추출한 값이 학습 윈도우와 일치함을 확인했습니다.

## 사용할 때 주의할 점

- **라벨은 녹화 단위입니다.** 낙상 녹화의 윈도우는 모두 `fall`이며, 넘어지는 순간·누워 있는 시간·일어나는 동작이 함께 들어 있습니다. 구간별 몸통 하강 정도는 `windows.csv`의 `pose_max_drop_1s`로 확인할 수 있습니다.
- **`windows.csv`의 `recording` 열로 같은 녹화의 윈도우를 묶을 수 있습니다.** 녹화 단위로 데이터를 나눌 때 씁니다.
- **윈도우 길이는 패킷 수(500개) 기준입니다.** 시간 길이는 노드의 패킷 수신량에 따라 달라지며 중앙값 5.0초, 범위 4.0–41.6초입니다(`windows.csv`의 `duration_s`).
- 녹화마다 주된 패킷 폭(134/198)과 노드별 수신량이 다를 수 있습니다(`recordings.csv`의 `modal_width`, `nodes`).
- 노드별 평균 RSSI(`recordings.csv`의 `rssi_mean_dbm`)는 노드 배치 변화를 구분할 때 참고할 수 있습니다.
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
- 참여자는 익명 ID로만 표기하며, 참여자를 따로 기록하지 않은 녹화는 `unrecorded`로 표기합니다. 이름 대응표는 공개 저장소에 두지 않습니다.
- 수집 PC의 IP·계정 정보는 원본 파일에 없습니다.
