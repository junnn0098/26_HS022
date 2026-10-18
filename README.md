# WiFi CSI 기반 주거 취약계층을 위한 스마트 주거 안전망

> 2026년 한이음 드림업 공모전 · 프로젝트 번호 26_HS022<br>
> 카메라도 웨어러블도 없이 **WiFi 신호(CSI)만으로** 집 안 낙상을 감지하는 것을 목표로, 센서망·엣지 AI·로컬 서버·보호자 앱을 직접 구축하고 실측 데이터셋과 검증 결과까지 공개한 비접촉 주거 안전망

| 한눈에 보기 | |
|---|---|
| **작품 소개영상** | [YouTube에서 보기](https://www.youtube.com/watch?v=05OW0u8NRQg) (4장) |
| **무엇을** | ESP32-S3 4대가 받은 WiFi CSI를 Jetson Orin Nano가 분석해 낙상을 판정하고, 보호자 앱에 실시간 알림·위치·대응 화면을 제공 |
| **공개 자료** | 직접 수집한 [실측 CSI 데이터셋](dataset) (윈도우 2,217개·원본 녹화 4시간) · v1 팀 학습 가중치 2개 · 학습/평가 코드 · Flutter 앱 · 로컬 서버 |
| **코드** | [`edge_ai/`](edge_ai) 엣지 AI(개발보고서 모델 v1, 실시간 파이프라인 v2) · [`app/`](app) 보호자 앱과 로컬 서버 · [`dataset/`](dataset) 데이터 도구 |
| **검증 결과** | 개발보고서 조건(윈도우 무작위 분할)에서 낙상 재현율 0.997로 다시 확인했습니다. 동시에 헤더 값만으로도 0.970이 나오는 데이터 누수를 직접 찾아냈고, 처음 보는 녹화에서는 아직 일반화되지 않음(AUROC 0.544)를 함께 공개합니다. 원인과 재수집 설계는 7·11장 |
| **문서** | [문서 안내](docs/INDEX.md) · [실행 안내](docs/RUNBOOK.md) · [설계·구현 대조](docs/IMPLEMENTATION_STATUS.md) |

---

## **💡1. 프로젝트 개요**

**1-1. 프로젝트 소개**

- 프로젝트 명 : WiFi CSI 기반 주거 취약계층을 위한 스마트 주거 안전망
- 프로젝트 정의 : WiFi 신호의 채널 상태 정보(CSI, Channel State Information)를 분석해 카메라·웨어러블 없이 실내 낙상을 감지하고, 보호자 앱으로 위험 상황을 즉시 확인·대응할 수 있게 하는 비접촉 스마트 주거 안전망
- 동작 개요
  - **센싱** : 센서 전용 공유기가 2.4GHz 고정 채널로 신호를 내보내고, ESP32-S3 수신 노드 4대가 패킷마다 CSI를 뽑아 UDP로 전송
  - **엣지 AI** : Jetson Orin Nano가 4개 노드의 CSI를 분석해 낙상 확률을 계산하고, 낙상 상태기계로 순간적인 오판을 걸러 낙상을 확정. 개발보고서의 1D-CNN(v1)은 학습 가중치와 함께, 실시간 서비스용 다중 노드 모델(v2)은 구조·학습 코드로 공개
  - **알림·대응** : 로컬 서버가 WebSocket으로 앱 화면을 실시간 갱신하고 위급 시 FCM 푸시를 발송. 보호자는 집 도면에서 위치를 확인하고 전화·119 신고로 대응

**1-2. 개발 배경 및 필요성**

- **늘어나는 돌봄 공백** : 65세 이상 1인 가구는 2022년 192.3만 가구에서 2052년 496.1만 가구로 늘 것으로 전망됩니다(통계청 장래가구추계). 혼자 사는 고령자가 넘어지면 스스로 도움을 요청하기 어려워 발견이 늦어집니다.
- **기존 방식의 한계** : 카메라는 상시 촬영에 따른 사생활 침해로 설치 거부감이 크고, 웨어러블은 착용 거부·충전 누락 시 감지할 수 없습니다.
- **비접촉 WiFi 센싱** : 사람이 움직이면 실내에서 반사되는 WiFi 신호가 달라지고, 그 변화가 CSI에 남습니다. 착용·촬영 없이 생활을 방해하지 않는 상시 감지가 가능하며, 저가 모듈로 구성할 수 있습니다.

**1-3. 프로젝트 특장점**

- **비접촉·비촬영** : 운영 중에는 카메라·웨어러블 없이 WiFi CSI만 사용합니다. 웹캠은 학습 데이터의 정답 기록에만 썼고, 영상은 저장하지 않았습니다.
- **저비용 하드웨어** : WiFi 센싱 전용 NIC 대신 XIAO ESP32-S3와 오픈소스 [RuView](https://github.com/ruvnet/RuView) 펌웨어로 CSI 수신 노드를 만들었습니다.
- **직접 구축한 실측 데이터셋 공개** : 3주(07-08~07-28)에 걸쳐 5회 수집한 녹화 48건(4시간)의 원본 CSI·관절 좌표와, 그중 45건에서 만든 학습 윈도우 2,217개를 공개합니다. 원본 녹화에서 윈도우를 다시 만들어 팀 학습 파일과 모든 값이 같은지 확인하고, 윈도우마다 출처(녹화·순번·시각)를 기록했습니다.
- **스스로 찾아낸 데이터 누수와 재현 가능한 검증** : 개발보고서 결과를 같은 조건에서 다시 얻는 코드와, 처음 보는 녹화·다른 날 데이터로 평가하는 코드를 함께 제공합니다. CSI가 아닌 헤더 5채널만으로도 재현율 0.970이 나오는 누수를 정량적으로 밝히고 원인을 분석했습니다.
- **오탐을 줄이는 낙상 상태기계** : 확률이 한 번 튀었다고 알리지 않고 `낙상 후보 → 사후 눕기 확인 → 확정 / 회복` 단계를 거칩니다.
- **보호자 친화 UI** : 확률·좌표 대신 `정상 / 주의 / 위험(즉각 조치 필요)` 상태와 집 도면 위치로 보여 주고, 판단할 수 없을 때는 정상으로 꾸미지 않고 `확인 필요`로 표시합니다.
- **웰니스 범위 준수** : 호흡 리듬은 의료 진단이 아닌 참고 정보로만 제공하며, 심박 추정은 의도적으로 넣지 않았습니다.

**1-4. 주요 기능**

| 구분 | 기능 | 설명 |
|---|---|---|
| H/W | CSI 동시 수신 클러스터 | ipTIME A2004SR 센서 전용망(2.4GHz 6번 채널 고정) + ESP32-S3 노드 4대 + 5dBi 외장 안테나 |
| H/W | 실시간 CSI 전달 | 각 노드가 RuView ADR-018 형식 CSI 패킷을 UDP 5005로 전송 (노드당 초당 약 37~50개) |
| Data | 실측 데이터 수집 | CSI와 웹캠 관절 좌표를 함께 기록하고 시각으로 맞춰 500패킷(약 5초) 학습 윈도우 생성 |
| AI | v1 1D-CNN (개발보고서 모델) | 134채널 × 500패킷을 1D-CNN(65,762 파라미터)으로 낙상/비낙상 분류. 팀 가중치·실시간 추론·녹화 재생 시연 포함 |
| AI | v2 다중 노드 모델 (실시간 서비스용) | 노드별 첫 LLTF 64개 서브캐리어 → 32Hz 보간 → 193채널 × 160프레임, 노드 attention 융합으로 행동 10종·인원·신호 품질 추론. 구조·학습 코드 공개, 운영용 가중치는 재수집 데이터로 학습 예정 |
| AI | 낙상 상태기계 | 반복된 낙상 확률 → 사후 눕기 확인 → 확정(최소 30초 유지) / 확정 전 회복 시 경보 취소 |
| AI | 호흡 리듬 (참고용) | 정지 상태에서 CSI 로그 진폭과 인접 서브캐리어 위상차의 스펙트럼(분당 6~30회 대역)으로 호흡수 추정 |
| Server | 엣지 → 서버 연동 | `jetson_edge_client.py live-status`가 엣지 판정을 서버 형식으로 바꿔 `POST /sensor/update`로 전달 |
| Server | 실시간 동기화 · 긴급 푸시 | WebSocket 상태 전달, Firebase 설정 시 FCM 푸시, 선택적 API 토큰 |
| App | 역할 기반 화면 | 한 앱에서 보호자 모드(위험 대응) / 피보호자 모드(생활 상태·위치 공유 관리) 선택 |
| App | 집 도면 위치 표시 | 감시 중인 방의 위치·상태를 도면에 표시, 위치 공유 OFF 시 비공개. 이동 경로·현관 접근 알림은 시연 입력 기능이며 방 안 위치 추정은 향후 과제 |
| App | 위험 대응 | 즉각 조치 알림 → 발생 위치·자세 확인 → 어르신 전화 / 119 신고 정보 / 5단계 대응 절차 |

**1-5. 기대 효과 및 활용 분야**

- 기대 효과
  - 카메라 없이 상시 감지해 독거노인의 사생활을 지키면서 낙상 발견 지연을 줄임
  - 착용·조작이 필요 없어 스마트 기기 사용이 어려운 고령자도 부담 없이 이용
  - 공유기·저가 노드 기반으로 설치 비용 절감
- 활용 분야
  - 독거노인·취약계층 돌봄 : 가정 내 낙상 감지 및 보호자·복지기관 알림
  - 요양시설·병원 : 다인 환경 평가 후 돌봄 인력 보조로 확장
  - 스마트홈 : 외출·침입 감지, 생활 리듬 기록으로 확장

**1-6. 기술 스택**

- 센서 / H/W : XIAO ESP32-S3 (RuView 펌웨어), 2.4GHz 5dBi 다이폴 안테나, ipTIME A2004SR, NVIDIA Jetson Orin Nano Super 8GB (JetPack 6.2.1, NVMe SSD)
- 엣지 AI : Python, PyTorch, NumPy, UDP 소켓, systemd
- 서버 : Node.js (HTTP + WebSocket), Firebase Cloud Messaging
- 모바일 앱 : Flutter (Dart), web_socket_channel, firebase_messaging
- 협업 : GitHub, Notion, Figma, 카카오톡

---

## **💡2. 팀원 소개(이름 기재X)**

| **멘티1** | **멘티2** | **멘티3** | **멘티4** | **멘토** |
|:---:|:---:|:---:|:---:|:---:|
| • 프로젝트 총괄<br>• H/W 센서망 구축 | • AI 모델 설계·학습<br>• CSI 데이터 수집·라벨링 | • 엣지 추론 파이프라인<br>• Jetson 서버 구축 | • Flutter 앱 UI/UX<br>• 로컬 서버·알림 연동 | • 프로젝트 멘토<br>• 기술 자문 |

---

## **💡3. 시스템 구성도**

**3-1. 전체 시스템 구성도**

<p align="center"><img src="docs/images/system_overview.png" alt="전체 시스템 구성도 - 공유기, ESP32-S3 4대, Jetson Orin Nano, 보호자 알림" width="900"></p>

그림은 실시간 서비스용 v2 파이프라인 기준입니다. v2의 구조·학습 코드는 저장소에 있고, 운영용 가중치는 재수집 데이터로 학습할 예정입니다(7·11장). 현재 공개한 학습 가중치는 개발보고서 모델(v1)입니다.

**3-2. 데이터 흐름 (코드 기준)**

각 단계에 해당 코드 폴더를 표시했습니다.

<p align="center"><img src="docs/images/data_flow.png" alt="데이터 흐름 - 센서 네트워크, 엣지 AI, 로컬 서버, 보호자 앱" width="760"></p>

도면 위치는 센서를 설치한 방을 기준으로 표시하며, 방 안의 좌표를 추정하는 모델은 아직 없습니다. FCM 푸시는 Firebase 프로젝트 설정과 기기 토큰이 있을 때 동작합니다.

**3-3. 낙상 판정 흐름 (상태기계)**

낙상은 한 번의 확률값으로 판단하지 않습니다. 0.5초마다 나오는 추론 결과를 상태기계가 순서대로 확인합니다. 단발성 확률 상승·회복·빈 방 예측 등 10개 시나리오를 합성 입력으로 검사해 모두 의도대로 동작함을 확인했습니다([검증 결과](experiments/RESULTS.md)).

<p align="center"><img src="docs/images/fall_state_machine.png" alt="낙상 감지 추론 흐름과 상태기계" width="860"></p>

| 단계 | 조건 ([`default_config.json`](edge_ai/config/default_config.json)) | 결과 |
|---|---|---|
| ① 낙상 후보 | 낙상 확률 ≥ 0.70이 2회 누적 | `NORMAL → FALL_CANDIDATE → POST_FALL_CHECK` |
| ② 사후 확인 | 누워 있음 확률 ≥ 0.55가 3회 누적 | `CONFIRMED` (최소 30초 유지 후 회복 조건 확인) |
| ③ 회복 확인 | 서기·걷기·일어서기 확률 ≥ 0.65가 2회 | `RECOVERED` — 앉거나 누웠다 일어난 것으로 보고 경보 취소 |
| ④ 시간 초과 | 8초 안에 확정·회복 모두 없음 | `NORMAL` 복귀 |
| 예외 | 신호 품질 < 0.55 / 방에 사람 없음 예측 | 판단 보류 / `NORMAL` — 단, 사후 확인·확정 중에는 상태 유지 |

**3-4. H/W 구성 (실물)**

<p align="center"><img src="docs/images/hardware.jpg" alt="하드웨어 실물 - 공유기, 센서 노드, 엣지 서버, 설치 모습" width="900"></p>

| 구성 | 부품 | 역할 |
|---|---|---|
| ① 네트워크·송신 | ipTIME A2004SR | 2.4GHz 고정 채널·전용 SSID·노드별 고정 IP로 센서 전용망 구성, 다른 기기 트래픽 간섭 차단 |
| ② 센서 노드 ×4 | XIAO ESP32-S3 + 5dBi 외장 안테나(U.FL→SMA) | RuView 펌웨어로 CSI 추출. 내장 안테나의 낮은 수신 감도(RSSI 약 -80dBm)를 외장 다이폴로 개선 |
| ③ 엣지 서버 | Jetson Orin Nano Super 8GB | JetPack 6.2.1 + NVMe SSD, GPU 추론, 원시 CSI는 기기 안에서만 처리 |
| ④ 설치 | 감지 영역 네 모서리 | 서로 다른 위치의 노드 4대가 같은 신호를 동시에 받아 여러 방향의 CSI 확보 |

**3-5. 앱 메뉴 구성도 및 화면**

<p align="center"><img src="docs/images/app_menu.png" alt="앱 메뉴 구성도" width="700"></p>

<p align="center"><img src="docs/images/app_screens.png" alt="보호자 앱 화면 - 홈 요약, 집 안 상태, 안전 알림, 설정" width="640"></p>

아래 화면은 센서 없이 시연 입력으로 띄운 화면입니다. 이동 경로·현관 접근 알림은 시연 입력에서만 나타나며, 실제 센서를 연결하면 감시 중인 방 1곳의 상태를 표시합니다. 현재 버전은 시연 입력에 `시연 입력` 표시를 붙이고, 판단할 수 없는 상태는 `확인 필요`, 호흡값이 없으면 `측정 대기`로 보여 줍니다.

<details>
<summary>엔티티 관계도·유즈케이스 다이어그램 보기 (서비스 확장 설계)</summary>

현재 로컬 서버는 보호자·설정·알림 이력을 JSON 상태 파일에 저장합니다. 아래 ERD는 다중 사용자 서비스로 확장할 때의 DB 설계입니다.

<p align="center"><img src="docs/images/erd.png" alt="엔티티 관계도" width="700"></p>
<p align="center"><img src="docs/images/usecase.png" alt="유즈케이스 다이어그램" width="900"></p>
</details>

---

## **💡4. 작품 소개영상**

**4-1. 작품 소개영상**

[![2026 한이음 드림업 공모전 - WiFi CSI 기반 주거 취약계층을 위한 스마트 주거 안전망](https://img.youtube.com/vi/05OW0u8NRQg/hqdefault.jpg)](https://www.youtube.com/watch?v=05OW0u8NRQg)

1분 32초 분량의 공식 작품 소개영상입니다.

**4-2. 실환경 데이터 수집 장면**

| 앉는 동작 | 눕는 동작 | 넘어지는 동작 |
|:---:|:---:|:---:|
| [![앉는 동작](https://img.youtube.com/vi/iZQwqRPPQ_E/hqdefault.jpg)](https://www.youtube.com/shorts/iZQwqRPPQ_E) | [![눕는 동작](https://img.youtube.com/vi/-Sp3iTWWZpE/hqdefault.jpg)](https://www.youtube.com/shorts/-Sp3iTWWZpE) | [![넘어지는 동작](https://img.youtube.com/vi/3AxhnGbnZMk/hqdefault.jpg)](https://www.youtube.com/shorts/3AxhnGbnZMk) |

수집 과정을 보여 주려고 따로 촬영한 참고 영상입니다. 데이터셋에는 영상이 없고, 학습용 웹캠은 프레임을 저장하지 않고 관절 좌표만 기록했습니다.

---

## **💡5. 핵심 소스코드**

**5-1. 개발보고서 모델(v1): 1D-CNN 낙상 분류기** — [`edge_ai/hanium_fall_v1/model.py`](edge_ai/hanium_fall_v1/model.py), [`train.py`](edge_ai/hanium_fall_v1/train.py)

- 소스코드 설명 : 134채널 × 500패킷(약 5초) CSI를 3단 1D 합성곱(채널 32→64→128, 커널 7→5→3)으로 요약해 낙상/비낙상을 분류합니다. 파라미터는 65,762개로 엣지 장비에서 가볍게 돌아갑니다. 낙상을 놓치는 비용이 크므로 학습에서 클래스 빈도의 역수로 가중한 교차 엔트로피를 씁니다. 팀이 학습한 가중치 2개를 [`weights/`](edge_ai/hanium_fall_v1/weights)에 함께 공개했습니다.

```python
class CSI1DCNN(nn.Module):
    """Input (batch, 134, 500) -> logits (batch, 2). About 66k parameters."""

    def __init__(self, in_channels: int = IN_CHANNELS, num_classes: int = 2, width: int = 32):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv1d(in_channels, width, 7, padding=3),
            nn.BatchNorm1d(width), nn.ReLU(), nn.MaxPool1d(2),
            nn.Conv1d(width, width * 2, 5, padding=2),
            nn.BatchNorm1d(width * 2), nn.ReLU(), nn.MaxPool1d(2),
            nn.Conv1d(width * 2, width * 4, 3, padding=1),
            nn.BatchNorm1d(width * 4), nn.ReLU(), nn.AdaptiveAvgPool1d(1),
        )
        self.head = nn.Linear(width * 4, num_classes)

    def forward(self, x):
        return self.head(self.features(x).squeeze(-1))

# train.py — 낙상(소수 클래스)을 놓칠 때 더 큰 손실을 주는 가중 교차 엔트로피
counts = np.bincount(y, minlength=2).astype(np.float64)
weights = torch.tensor(counts.sum() / (2 * np.maximum(counts, 1)), dtype=torch.float32)
criterion = torch.nn.CrossEntropyLoss(weight=weights)
```

**5-2. 실시간 입력 처리: 노드별 LLTF 선택과 특징 추출** — [`edge_ai/hanium_fall_v2/adr018.py`](edge_ai/hanium_fall_v2/adr018.py), [`features.py`](edge_ai/hanium_fall_v2/features.py)

- 소스코드 설명 : LLTF는 모든 WiFi 패킷 앞부분에 공통으로 들어 있는 64개 기준 신호 구간입니다. 노드가 보내는 패킷은 64·128·192개 값이 LLTF → HT-LTF → STBC-HT-LTF 순으로 이어진 형태라, 길이가 다른 패킷을 그대로 쓰면 같은 위치의 값이 다른 의미를 갖습니다. v2는 모든 패킷에서 **첫 LLTF 블록 64개만** 고르고, 노드마다 따로 32Hz 시간축으로 보간한 뒤 ① 로그 진폭 ② 중앙값·MAD 기준 동적 진폭 ③ 인접 프레임 위상차 ④ RSSI로 193채널을 만듭니다. 학습과 실시간 추론이 이 함수 하나를 함께 씁니다.

```python
def extract_lltf_iq(frame: CsiFrame, target_subcarriers: int = CANONICAL_SUBCARRIERS, *,
                    mask_first_word: bool = True, require_20mhz: bool = True) -> np.ndarray:
    if require_20mhz and frame.bandwidth_code != ADR110_BANDWIDTH_20MHZ:
        raise ValueError(f"non-20MHz frame: bandwidth code {frame.bandwidth_code}")
    if frame.ppdu not in SUPPORTED_LLTF_PPDU:
        raise ValueError(f"unsupported PPDU for S3 LLTF: {frame.ppdu}")
    return _extract_first_lltf_block(frame.iq, mask_first_word=mask_first_word)

# features.py — 노드 하나의 5초 구간 -> (193, 160)
log_amplitude = np.log1p(np.abs(complex_csi)).astype(np.float32)
absolute_amplitude = np.clip((log_amplitude - 3.0) / 1.5, -3.0, 3.0)
median = np.median(log_amplitude, axis=0, keepdims=True)
mad = np.median(np.abs(log_amplitude - median), axis=0, keepdims=True)
dynamic_amplitude = np.clip((log_amplitude - median) / (1.4826 * mad + 0.05), -5.0, 5.0)
phase_delta = np.zeros_like(log_amplitude, dtype=np.float32)
phase_delta[1:] = np.angle(complex_csi[1:] * np.conj(complex_csi[:-1])) / np.pi
features = np.concatenate([absolute_amplitude.T, dynamic_amplitude.T, phase_delta.T, rssi.T], axis=0)
```

**5-3. 다중 노드 attention 융합 모델** — [`edge_ai/hanium_fall_v2/model.py`](edge_ai/hanium_fall_v2/model.py)

- 소스코드 설명 : 4개 노드의 특징 `(batch, 4, 193, 160)`을 노드 공용 1D-CNN 인코더로 각각 요약한 뒤, 노드별 신호 품질과 함께 attention으로 가중 합산합니다. 끊긴 노드는 `node_mask`로 빼므로 수신 노드 수가 바뀌어도 구조를 바꿀 필요가 없습니다. 융합 벡터 하나에서 행동 10종·인원(0/1/2/3+)·신호 품질을 함께 출력합니다.

```python
def forward(self, features, node_mask, node_quality):
    batch, nodes, channels, frames = features.shape            # (B, 4, 193, 160)
    encoded = self.node_encoder(features.reshape(batch * nodes, channels, frames))
    encoded = encoded.reshape(batch, nodes, self.embedding_dim)

    quality_column = node_quality.unsqueeze(-1)                 # 노드 임베딩 + 신호 품질 -> attention
    attention_logits = self.attention(torch.cat([encoded, quality_column], dim=-1)).squeeze(-1)
    attention_logits = attention_logits.masked_fill(~node_mask.bool(), -1e4)   # 끊긴 노드 제외
    attention_weights = torch.softmax(attention_logits, dim=1)

    fused_embedding = torch.sum(encoded * attention_weights.unsqueeze(-1), dim=1)
    fused_quality = torch.sum(node_quality * attention_weights, dim=1, keepdim=True)
    fused = torch.cat([fused_embedding, fused_quality], dim=1)
    return {"activity_logits": self.activity_head(fused), "count_logits": self.count_head(fused),
            "quality": self.quality_head(fused).squeeze(-1), "node_attention": attention_weights}
```

**5-4. 낙상 확정 상태기계** — [`edge_ai/hanium_fall_v2/fall_state.py`](edge_ai/hanium_fall_v2/fall_state.py)

- 소스코드 설명 : 신호 품질이 낮으면 판단을 미루고, 낙상 후보가 된 뒤에도 바로 알리지 않습니다. 이후 계속 누워 있는지(눕기 확률 누적)와 다시 일어났는지(서기·걷기 확률 누적)를 비교해, 회복이 먼저 확인되면 경보를 취소하고 눕기가 이어지면 `CONFIRMED`로 바꿔 보호자에게 알립니다.

```python
if quality < self.config.min_quality:                                   # 신호 품질 부족 -> 판단 보류
    if self.state not in (FallState.CONFIRMED, FallState.POST_FALL_CHECK):
        self._transition(FallState.UNKNOWN, now)
    reason = "low_quality"
elif people_count_label == "0" and self.state not in (FallState.CONFIRMED, FallState.POST_FALL_CHECK):
    # A person lying still after a fall can look like an empty room, so an
    # "empty" prediction must never cancel a confirmed or pending alarm.
    self._transition(FallState.NORMAL, now)
    reason = "room_empty"
...
elif self.state == FallState.NORMAL:
    if fall_probability >= self.config.fall_candidate_probability:      # 0.70
        self.candidate_hits += 1
    else:
        self.candidate_hits = max(0, self.candidate_hits - 1)
    if self.candidate_hits >= self.config.fall_candidate_hits:          # 2회
        self._transition(FallState.FALL_CANDIDATE, now)
...
elif self.state == FallState.POST_FALL_CHECK:
    if lying_probability >= self.config.post_fall_lying_probability:    # 0.55
        self.lying_hits += 1
    if recovery_probability >= self.config.recovery_probability:        # 0.65
        self.recovery_hits += 1
    else:
        self.recovery_hits = max(0, self.recovery_hits - 1)
    if self.recovery_hits >= self.config.recovery_hits:                 # 일어남 -> 경보 취소
        self._transition(FallState.RECOVERED, now)
    elif self.lying_hits >= self.config.post_fall_lying_hits:           # 계속 누움 -> 확정
        self._transition(FallState.CONFIRMED, now)
    elif now - self.state_started >= self.config.post_fall_timeout_seconds:
        self._transition(FallState.NORMAL, now)                         # 8초 안에 결론 없음
```

---

## **💡6. 실측 데이터셋**

팀이 설치한 센서 환경에서 3주(07-08~07-28)에 걸쳐 5회 직접 수집한 데이터입니다. 자세한 설명은 [데이터셋 안내](dataset/README.md)에 있습니다.

<p align="center"><img src="dataset/figures/composition.png" alt="수집일별 학습 윈도우 구성" width="680"></p>

| 항목 | 내용 |
|---|---|
| 원본 녹화 | 48건 × 5분 (CSI 패킷 약 260만 개 + 웹캠 관절 좌표 약 31만 프레임, 영상은 저장하지 않음) |
| 학습 윈도우 | 500패킷(중앙값 5.0초) 윈도우 2,217개 (낙상 969개), 동작 15종 — 낙상 / 혼동 동작 6종(비틀거리기·물건 줍기·눕기 등) / 일상 동작 8종 |
| 출처 기록 | 윈도우마다 원본 녹화·구간 순번·시각을 [`windows.csv`](dataset/metadata/windows.csv)에 기록하고, 팀 학습 파일과 값이 모두 일치함을 확인 |
| 내려받기 | `python dataset/tools/download.py` (학습 윈도우) · `--v2` (v2 형식) · `--raw` (원본 녹화), [Release `dataset-v1.0`](https://github.com/junnn0098/26_HS022/releases/tag/dataset-v1.0) |

---

## **💡7. 학습·검증 결과**

공개 데이터셋으로 개발보고서 모델(v1)을 다시 학습하고, 같은 데이터를 세 가지 방식으로 나누어 평가했습니다. 전체 표·해석·재현 명령은 [실측 데이터 검증 결과](experiments/MEASURED_RESULTS.md)에 있습니다.

<p align="center"><img src="experiments/results/figures/protocol_comparison.png" alt="평가 방식별 낙상 재현율과 AUROC" width="900"></p>

| 평가 (낙상 확률 ≥ 0.5) | 낙상 재현율 | AUROC |
|---|---:|---:|
| **개발보고서 조건 추정** — 1,019개 윈도우 무작위 80/20, 5회 (보고서 기재 0.933, 비틀거리기 오탐 0건) | **0.997** | 1.000 |
| 2,217개 전체, 윈도우 무작위 80/20, 5회 | 0.922 | 0.986 |
| 같은 분할에서 CSI가 아닌 헤더 5채널만 입력 (누수 점검) | 0.970 | 0.992 |
| 녹화 단위 5겹 교차검증 (처음 보는 녹화) | 0.553 | 0.544 |
| 날짜 분할 평가 (07-08~07-15 학습 → 07-24·07-28 시험, 3회) | 0.033 | 0.708 |
| 실시간용 v2 파이프라인, 녹화 단위 5겹 | 0.461 | 0.500 |
| 실시간용 v2 파이프라인, 날짜 분할 평가 | 0.343 | 0.517 |

- **개발보고서 수치는 같은 조건에서 다시 얻어집니다.** 보고서와 같은 1,019개 윈도우를 무작위 80/20으로 나누면(보고서에 분할 방식이 적혀 있지 않아 추정) 재현율 0.997로 보고서(0.933)와 같은 수준이 나오고, 비틀거리기 오탐 0건도 같습니다. 이 재실험은 전이 학습 없이 처음부터 학습했습니다.
- **그 점수는 모델이 낙상 동작보다 "어느 녹화인지"를 알아맞혀 얻은 것으로 보입니다.** 패킷 순번·RSSI 같은 헤더 값만으로도 재현율 0.970이 나옵니다. 처음 보는 녹화로 시험하면 AUROC가 0.544로 무작위 추측 수준(0.5)에 가깝고, 날짜를 나누면 재현율이 0.033으로 떨어집니다. 07-17 팀 가중치는 이후 수집일의 낙상 359개를 하나도 찾지 못했습니다.
- **원인을 데이터에서 확인했습니다.** ① 라벨이 5분 녹화 단위로 붙어 있고 ② 노드마다 패킷 형식(64·128·192값)이 섞이며 ③ 동작에 따른 CSI 변화가 패킷 형식·노드 배치 변화로 생기는 변동보다 작습니다. v2는 ②를 노드별 분리·LLTF 고정 선택으로 정리했지만 처음 보는 녹화에서는 나아지지 않아(녹화 단위 AUROC 0.500, 학습 데이터 AUROC 0.890), 병목을 ①·③으로 판단하고 다음 수집을 설계했습니다(11장).

**개발보고서 대비 정정 사항**

| 항목 | 개발보고서 | 저장소에서 확인한 내용 |
|---|---|---|
| 낙상 재현율 | 0.933 (1,019개 클립) | 같은 데이터·무작위 분할 재실험 0.997. 녹화 단위 평가에서는 일반화되지 않음 |
| 파라미터 수 | 약 8.7만 | 같은 코드로 계산하면 65,762개 |
| 입력 134채널 | 서브캐리어 진폭 | 앞 5채널은 패킷 헤더 값, 나머지는 LLTF 64개와 두 번째 64값 블록 ([채널 구성](dataset/README.md#134채널의-실제-구성)) |
| 수신 속도 | 100Hz | 노드당 초당 약 37~50개 패킷(4노드 합계 약 100~200개) |
| 학습 방식 | 공개 데이터 선행 학습 후 실환경 미세조정 | 선행 학습 코드·체크포인트는 남아 있지 않아, 재실험은 실측 데이터만으로 학습 |
| 추론 가속 | TensorRT 0.01초 | TensorRT 변환은 포함하지 않음. 현재 PyTorch 추론 |
| 오탐 필터 | 시간·공간 필터 | 시간 조건은 낙상 상태기계로 구현, 공간(위험 구역) 필터는 미구현 |

**시스템 동작 검증 (합성 입력)** — 센서 없이 낙상 상태기계 10개 시나리오가 모두 기대대로 동작하고, 엣지 → 서버 연동 13개 항목이 기대값과 일치함을 확인했습니다. 호흡 추정·패킷 누락 검사에서 드러난 한계(백색잡음에도 낮은 신뢰도의 호흡값 반환, 품질 점수가 긴 공백을 반영하지 않음)도 함께 기록했습니다([결과](experiments/RESULTS.md)).

---

## **💡8. 개발 과정의 문제와 개선**

| 문제 | 대응 |
|---|---|
| 하드웨어·AI 담당 간 CSI 데이터 형식(채널 수·길이·라벨)이 통일되지 않아 수집 데이터를 바로 학습에 쓰지 못함 | 데이터 규격(134채널 × 500, z-score)을 문서로 정하고 웹캠 동기화 정답 기록 방식을 합의 |
| 내장 PCB 안테나의 낮은 수신 감도(RSSI 약 -80dBm)로 패킷 유실 | 5dBi 외장 다이폴 안테나로 교체 |
| 일반 가정망 트래픽이 CSI에 잡음으로 섞임 | 고정 채널·전용 SSID·고정 IP의 센서 전용망 구성 |
| 무작위 분할에서는 높은 성능이 나왔지만 새로 수집한 날의 데이터에서는 낙상을 거의 찾지 못함 | 데이터 출처를 복원해 녹화·날짜 단위로 다시 평가하고 원인(헤더 값 혼입, 녹화 단위 라벨, 패킷 형식 혼재)을 찾음. 입력 쪽 원인은 v2에 반영했고, 라벨·신호 쪽 원인은 재수집으로 해결 예정 (7·11장) |
| 노드마다 CSI 패킷 길이가 64/128/192로 섞여 들어와 같은 채널 번호의 의미가 달라짐 | 패킷이 LLTF·HT-LTF·STBC-HT-LTF 블록 순서임을 확인하고 첫 LLTF 블록(64개)만 고정 선택, 20MHz 외 프레임 거부 |
| 엣지 판정 형식과 서버 입력 형식이 달라 실제 판정이 앱까지 전달되지 않음 | `jetson_edge_client.py live-status`가 상태기계 결과를 서버 형식으로 바꿔 전달. 모델 미설치·오래된 입력은 `unknown`으로 구분 |
| 낙상 확정 뒤 '방에 사람 없음' 예측 한 번에 경보가 풀림 (움직이지 않는 사람은 빈 방처럼 보일 수 있음) | 사후 확인·확정 중에는 빈 방 예측을 무시하도록 상태기계를 고치고 회귀 테스트 추가 |
| 앱 화면에 서버·센서 상태 등 개발자용 정보가 많이 노출됨 | 보호자(위험 대응)·피보호자(생활 상태·위치 공유)로 화면 목적을 다시 정의 |
| 좌표 기반 위치 표시는 보호자가 이해하기 어려움 | 거실·침실·욕실·현관 등 생활 공간 단위의 집 도면으로 표현 |

---

## **💡9. 저장소 구조**

```text
.
├── README.md
├── dataset/                     # 실측 CSI 데이터셋 (설명서·메타데이터·샘플·도구, 대용량 파일은 Release)
│   ├── metadata/                #   recordings.csv(녹화 48건) · windows.csv(윈도우 2,217개)
│   ├── sample/                  #   라벨별 윈도우 15개 + 원본 2초 발췌
│   └── tools/                   #   내려받기 · 출처 대조 · 원본→v2 변환 · 관절 좌표 지표
├── edge_ai/                     # Jetson 엣지 AI
│   ├── hanium_fall_v1/          #   보고서 1D-CNN: 모델·학습·평가·실시간 추론 + 팀 가중치
│   ├── hanium_fall_v2/          #   실시간 파이프라인: 패킷 파서·특징·다중 노드 모델·상태기계·호흡·상태 API
│   ├── jetson/                  #   실행 스크립트 · systemd 서비스
│   ├── tools/                   #   CSI 실시간 대시보드
│   └── tests/                   #   단위 테스트
├── app/                         # 보호자 앱(Flutter) + 로컬 서버(app/server, Node.js)
├── experiments/                 # 실측 데이터 검증(run_v1_experiments.py, v2_measured.py) + 합성 입력 검증
└── docs/                        # 실행 안내 · 데이터 규격 · 설계·구현 대조 · 구성도 이미지
```

---

## **💡10. 실행 방법**

전체 명령은 [실행 및 시연 안내](docs/RUNBOOK.md)에 있습니다.

```bash
# 1) 내려받기 없이 실행 확인 (Python 3.10+). 샘플 15개 중 대부분이 이 가중치의 학습 날짜라 출력 수치는 성능이 아닙니다 (성능은 7장)
cd edge_ai
python -m pip install -r requirements.txt torch
python -m hanium_fall_v1.evaluate --weights hanium_fall_v1/weights/team_v1_0717.pth --npz-dir ../dataset/sample --metadata ../dataset/sample/sample_windows.csv

# 2) 전체 데이터로 7장의 v1 결과 재현 (v2·그림은 experiments/MEASURED_RESULTS.md의 재현 절)
python ../dataset/tools/download.py && python ../experiments/run_v1_experiments.py

# 3) 단위 테스트
python -m unittest discover -s tests
```

| 목적 | 실행 경로 |
|---|---|
| 센서 없는 화면·통신 시연 | `REAL_SENSOR_ONLY=true node app/server/local_server.js` → Flutter 앱 → `jetson_edge_client.py once` / `sequence` (시연 입력) |
| 센서 없는 실시간 추론 시연 | `hanium_fall_v1.realtime_inference` + 원본 녹화 재생 `hanium_fall_v1.replay_recording` ([방법](edge_ai/hanium_fall_v1/README.md#실행)) |
| 실제 CSI 추론 연결 (v2) | 센서 노드 → `edge_ai/jetson/run_live.sh` → `jetson_edge_client.py live-status` → 서버·앱. v2 가중치가 없으면 앱에 `확인 필요`로 표시 |

---

## **💡11. 한계 및 향후 과제**

- **일반화** : 현재 데이터와 모델은 처음 보는 녹화·다른 날의 데이터에서 낙상을 안정적으로 찾지 못합니다(7장). 낙상 순간 단위의 라벨(웹캠 관절 좌표 활용), 패킷 형식을 고정한 펌웨어 설정, 더 많은 참여자·공간, 빈 방 기록을 갖춘 데이터로 v2를 다시 학습하는 것이 다음 과제입니다.
- **실시간 판정 가중치** : 실시간 서비스용 v2의 운영 가중치는 아직 없습니다. v1은 실시간 추론 코드와 녹화 재생 시연을 제공하지만 앱 서버로 결과를 보내는 연결은 v2 경로에만 있습니다. 저장소에서 앱까지 이어지는 흐름은 시연 입력과 합성 입력으로 검증했습니다.
- **추론 가속** : 보고서의 TensorRT 변환은 저장소에 포함되지 않았으며, 현재 코드는 PyTorch로 추론합니다.
- **위치** : 집 도면 위치는 센서를 설치한 방 기준이며, 방 안 좌표 추정과 위험 구역(공간) 필터는 구현하지 않았습니다.
- **서비스 범위** : 일일·주간 생활 리포트, 다중 사용자 DB, 원격 접속 인증은 설계 단계입니다. 로컬 서버는 같은 공유기 안에서의 시연을 전제로 합니다.
- **호흡** : 호흡수는 참고 정보이며 의료용 측정값이 아닙니다.
- **보안** : 로컬 서버는 시연용 네트워크를 전제로 합니다. `HANIUM_API_TOKEN`을 설정하면 상태 조회·입력 API와 WebSocket 위치 스트림에 토큰이 필요하고, 위치 공유 OFF는 REST·WebSocket·알림 모두에 적용됩니다([서버 설정](app/server/README.md)).

---

## **💡12. 오픈소스**

| 오픈소스 | 라이선스 | 사용 범위 |
|---|---|---|
| [RuView](https://github.com/ruvnet/RuView) | [MIT](https://github.com/ruvnet/RuView/blob/main/LICENSE) | ESP32-S3 CSI 추출 펌웨어, CSI 패킷 형식(ADR-018), 수집 단계의 CSI·관절 좌표 시간 맞춤 도구 |

RuView 자체의 낙상·호흡 기능은 쓰지 않고 CSI를 뽑아 보내는 펌웨어와 수집 도구로만 사용했습니다. 패킷 수신·검증, 특징 추출, 두 모델, 상태기계, 데이터셋 도구, 서버·앱은 팀이 작성했습니다.

---

> **사용 범위** : 본 서비스는 의료기기가 아니며 질병의 진단·치료를 대체하지 않습니다. 호흡 리듬 등 생활 데이터는 건강 관리 참고용 정보로만 제공됩니다.
