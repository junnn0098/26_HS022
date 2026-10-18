# WiFi CSI 기반 주거 취약계층을 위한 스마트 주거 안전망

> 2026년 한이음 드림업 공모전 · 프로젝트 번호 26_HS022<br>
> 카메라도, 웨어러블도 없이 **WiFi 신호만으로** 집 안 낙상을 감지하고 보호자의 확인·대응을 돕는 비접촉 주거 안전망

<p align="center">
  <img src="docs/images/system_overview.png" alt="전체 시스템 구성도 - 공유기, ESP32-S3 4대, Jetson Orin Nano, 보호자 알림" width="900">
</p>

| 한눈에 보기 | |
|---|---|
| **무엇을** | ESP32-S3 4대가 수신한 WiFi CSI로 Jetson Orin Nano가 낙상을 판정하고, 보호자 앱에 실시간 알림과 대응 화면을 제공 |
| **핵심 기술** | 4노드 attention 융합 multi-node 1D-CNN + 오탐을 줄이는 낙상 확정 상태기계 |
| **코드** | `edge_ai/` 엣지 AI 파이프라인 · `app/` Flutter 앱과 로컬 서버 |
| **현재 상태** | 센서·AI·서버·앱 연결 코드 및 시연 경로 구성. 이번 점검: 단위 테스트 25개 통과·6개 건너뜀. 수집 기록 36건 공개 (구현 범위는 아래 6장) |

---

처음 보는 분은 **프로젝트 개요 → 구현 범위(6장) → 검증 결과(10장)** 순서로 확인하면 됩니다.

- [설계 요구사항과 현재 구현 대조](docs/IMPLEMENTATION_STATUS.md): 설계서·개발보고서의 수치 차이와 코드 근거
- [실행 및 시연 안내](docs/RUNBOOK.md): 센서 없는 화면 시연과 실제 추론 연결을 구분한 실행 순서

> 공개 저장소에는 학습된 가중치와 원본 CSI 데이터가 없습니다. 코드를 내려받는 것만으로 학습된 낙상 감지가 시작되지는 않습니다. 아래의 보고서 성능 수치, 코드 테스트, 화면 시연은 각각 검증 범위가 다릅니다.

## **1. 프로젝트 개요**

**1-1. 프로젝트 소개**

- 프로젝트 명 : WiFi CSI 기반 주거 취약계층을 위한 스마트 주거 안전망
- 프로젝트 정의 : WiFi 신호의 채널 상태 정보(CSI, Channel State Information)를 분석해 카메라·웨어러블 없이 실내 낙상을 실시간으로 감지하고, 보호자 앱으로 위험 상황을 즉시 확인·대응할 수 있게 하는 비접촉 스마트 주거 안전망
- 동작 개요
  - **센싱** : ipTIME 공유기가 센서 전용 독립망에서 신호를 송출하고, ESP32-S3 수신 노드 4대가 CSI를 실시간 추출해 UDP로 전송
  - **엣지 AI** : Jetson Orin Nano가 4개 노드의 CSI를 통합해 multi-node 1D-CNN으로 행동·인원·신호 품질을 추론하고, 낙상 상태기계로 오탐을 걸러 낙상을 확정
  - **알림·대응** : 로컬 서버가 WebSocket으로 앱에 상태를 실시간 동기화하고, 위급 시 FCM 푸시를 발송. 보호자는 집 도면에서 위치를 확인하고 전화·119 신고로 대응

**1-2. 개발 배경 및 필요성**

- **돌봄 공백** : 혼자 생활하는 고령자가 낙상 후 직접 도움을 요청하기 어려울 때, 위험 발견과 보호자 확인이 늦어질 수 있습니다. 본 프로젝트는 주거 공간에서 위험 신호를 감지하고 보호자의 대응으로 연결하는 데 초점을 둡니다.
- **주거 공간의 안전 확인** : 보호자가 항상 현장에 머무르기 어려운 상황을 고려해, 평소 상태 확인과 위험 시 알림을 하나의 흐름으로 구성했습니다. 배경과 요구사항은 제작설계서 p.3~5 및 개발보고서 p.3~4를 참고했습니다.
- **기존 방식의 한계** : 카메라는 상시 촬영에 따른 사생활 침해로 설치 거부감이 크고, 웨어러블은 착용 거부·충전 누락 시 감지가 불가능합니다.
- **비접촉 WiFi 센싱의 가능성** : WiFi 신호의 변화를 활용해 착용·촬영 없이 움직임을 감지하는 방식입니다. 본 구현에는 센서용 공유기, CSI 수신 노드와 Jetson을 별도로 설치합니다.

**1-3. 프로젝트 특장점**

- **비접촉 감지** : 운영 시 카메라·웨어러블 없이 WiFi CSI로 감지하여 영상 촬영과 착용 부담을 줄임
- **저비용 하드웨어** : WiFi 센싱 전용 NIC 대신 XIAO ESP32-S3 + 오픈소스 [RuView](https://github.com/ruvnet/RuView) 펌웨어로 CSI 추출 노드 구성
- **다중 노드 attention 융합** : 4개 수신 노드의 CSI를 노드별 신호 품질과 함께 attention으로 가중 통합하여, 일부 노드가 끊겼을 때 해당 입력을 제외하도록(node mask) 설계. 결측 상황의 정확도는 별도 평가 필요
- **오탐을 줄이는 낙상 상태기계** : 한 번의 확률 튐으로는 알림을 보내지 않고 `낙상 후보 → 사후 눕기 확인 → 확정 / 회복` 단계를 거쳐야만 경보 전송
- **엣지 로컬 처리** : 운영 중 원시 CSI는 Jetson에서 분석하고 판정 결과를 서버에 전달. 학습 데이터 라벨링에는 별도 웹캠 기록을 활용
- **보호자 친화 UI** : 확률·좌표 같은 기술 수치 대신 `정상 / 주의 / 즉각 조치 필요` 3단계 상태와 집 도면 기반 위치로 표현
- **웰니스 범위 준수** : 호흡 리듬 등 생활 데이터는 의료 진단이 아닌 참고 정보로만 제공 (심박 추정은 의도적으로 제외)

**1-4. 주요 기능**

| 구분 | 기능 | 설명 |
|---|---|---|
| H/W | CSI 동시 수신 클러스터 | ipTIME A2004SR 센서 전용 독립망(2.4GHz 고정 채널) + ESP32-S3 수신 노드 4대 + 5dBi 외장 안테나 |
| H/W | 실시간 CSI 전달 | 각 노드가 RuView ADR-018 형식 CSI 패킷을 UDP(5005)로 Jetson에 스트리밍 |
| AI | CSI 특징 추출 | LLTF 64 서브캐리어 선택 → 32Hz 보간 → 로그 진폭·동적 진폭·위상차·RSSI 193채널 × 160프레임(5초) |
| AI | multi-node 1D-CNN | 노드별 1D-CNN 인코더 + attention 융합으로 행동 10종·인원 4분류·신호 품질 동시 추론 |
| AI | 낙상 상태기계 | 반복된 낙상 확률 → 사후 눕기 확인 → 낙상 확정(최소 30초 유지 후 회복 조건 확인) / 확정 전 회복 시 경보 취소 |
| AI | 호흡 리듬 모니터링 | 정지 상태에서 CSI 진폭 스펙트럼(6~30회/분 대역)으로 분당 호흡수 추정 (참고용) |
| Server | 엣지 → 서버 연동 | `jetson_edge_client.py live-status`가 엣지 추론 결과를 서버 형식으로 변환해 `POST /sensor/update`로 전달 |
| Server | 실시간 동기화 · 긴급 푸시 | WebSocket 상태 전달과 FCM 전송 코드. 백그라운드 수신은 Firebase 설정·기기 토큰·권한 및 실제 단말 검증 필요 |
| App | 역할 기반 화면 | 하나의 앱에서 보호자 모드(위험 대응 중심) / 피보호자 모드(생활 상태·위치 공유 관리) 선택 |
| App | 집 도면 위치 표시 | 도면 위에 위치·사람 미니어처·최근 이동 경로 표시(센서 설치 방 기준), 위치 공유 OFF 시 동선 비공개 |
| App | 위험 대응 | 즉각 조치 알림 → 발생 위치·자세 확인 → 어르신 전화 / 119 신고 정보 / 5단계 상황 대응 절차 |

**1-5. 기대 효과 및 향후 활용 분야**

- 기대 효과
  - 공유기·ESP32-S3·Jetson으로 구성한 비접촉 감지 방식을 독거노인 돌봄에 적용하는 것이 목표이며, 가정별 배치와 성능 검증이 필요
  - 비접촉·비촬영으로 사생활을 보호하면서 보호자의 원격 확인과 즉시 대응을 지원해 낙상 발견 지연 위험 감소
  - 착용·조작이 필요 없어 스마트 기기 사용이 어려운 고령자도 부담 없이 이용 가능
- 활용 분야
  - 독거노인·취약계층 돌봄 : 가정 내 상시 낙상 감지 및 보호자·복지기관 알림
  - 요양시설·병원 : 다인 환경 평가 후 돌봄 인력 보조로 확장 검토
  - 스마트홈 보안 : 외출·침입 감지로 확장 검토. 현재 앱 시나리오 재현과 실제 침입 판별을 구분
  - 생활 기록 : 활동·호흡 리듬을 누적한 일일·주간 요약 리포트 제공 검토. 현재 구현 완료 기능은 아님

**1-6. 기술 스택**

- 센서 / H/W : XIAO ESP32-S3 (RuView 펌웨어, 2.4GHz CSI), 2.4GHz 5dBi 다이폴 외장 안테나, ipTIME A2004SR(802.11ac, MU-MIMO), NVIDIA Jetson Orin Nano Super 8GB (JetPack 6.2.1, NVMe SSD)
- 엣지 AI : Python, PyTorch(CUDA), NumPy, UDP 소켓, systemd 서비스
- 서버 : Node.js(HTTP + WebSocket 로컬 서버), Firebase Cloud Messaging
- 모바일 앱 : Flutter(Dart), web_socket_channel, firebase_messaging
- 협업 / 관리 : GitHub, Notion, Figma(UI/UX 설계), 카카오톡

---

## **2. 팀원 소개(이름 기재X)**

| **멘티1** | **멘티2** | **멘티3** | **멘티4** | **멘토** |
|:---:|:---:|:---:|:---:|:---:|
| • 프로젝트 총괄<br>• H/W 센서망 구축 | • AI 모델 설계·학습<br>• CSI 데이터 수집·라벨링 | • 엣지 추론 파이프라인<br>• Jetson 서버 구축 | • Flutter 앱 UI/UX<br>• 로컬 서버·알림 연동 | • 프로젝트 멘토<br>• 기술 자문 |

---

## **3. 시스템 구성도**

**3-1. 데이터 흐름 (저장소 코드 기준)**

각 단계 카드에 해당 코드가 있는 폴더를 표시했습니다.

<p align="center"><img src="docs/images/data_flow.png" alt="데이터 흐름 - 센서 네트워크, 엣지 AI, 로컬 서버, 보호자 앱" width="820"></p>

도면 좌표는 연결 클라이언트에 지정한 설치 위치입니다. 현재 모델은 행동·인원·품질을 출력하며, 방 이름이나 사람의 연속 좌표를 추정하는 출력은 없습니다. 그림의 ‘즉시 알림’은 처리 흐름을 뜻하며 전체 지연 시간의 실측값은 아닙니다.

**3-2. 낙상 감지 추론 흐름 · 상태기계**

낙상 여부는 특정 순간의 확률값 하나로 판단하지 않고, 기본 0.5초 간격의 추론 결과를 상태기계에 전달해 순차적으로 확인합니다.

<p align="center"><img src="docs/images/fall_state_machine.png" alt="낙상 감지 추론 흐름과 상태기계" width="900"></p>

| 단계 | 조건 (`edge_ai/config/default_config.json`) | 결과 |
|---|---|---|
| ① 낙상 후보 | fall 확률 ≥ 0.70 이 2회 누적 | `NORMAL → FALL_CANDIDATE → POST_FALL_CHECK` |
| ② 사후 확인 | 사후 확인 구간에서 lying(누워 있음) 확률 ≥ 0.55 누적 3회 | `CONFIRMED` · 최소 30초 유지 후 회복 조건 충족 시 해제 |
| ③ 회복 체크 | 서기·걷기·일어서기 확률 ≥ 0.65 가 2회 | `RECOVERED` · 단순히 앉거나 누웠다 일어난 것으로 보고 경보 취소 |
| ④ 시간 초과 | 8초 안에 확정·회복 모두 없음 | `NORMAL` 복귀 |
| 예외 | 신호 품질 < 0.55 / 방에 사람 없음(인원 0) 예측 | `UNKNOWN`으로 판단 유보 / `NORMAL` — 단, 사후 확인·확정 중에는 두 경우 모두 상태 유지 |

**3-3. H/W 구성 (실물)**

<p align="center"><img src="docs/images/hardware.jpg" alt="하드웨어 실물 - 공유기, 센서 노드, 엣지 서버, 설치 모습" width="900"></p>

| 구성 | 부품 | 역할 |
|---|---|---|
| ① 네트워크·송신 | ipTIME A2004SR | 2.4GHz 고정 채널·전용 SSID·노드별 고정 IP로 센서 전용 독립망 구성, 타 기기 트래픽 간섭 차단 |
| ② 센서 노드 ×4 | XIAO ESP32-S3 + 5dBi 외장 안테나(U.FL→SMA) | RuView 펌웨어로 CSI 추출, 내장 안테나 수신 한계를 외장 다이폴로 개선(개발보고서 기재) |
| ③ 엣지 서버 | Jetson Orin Nano Super 8GB | JetPack 6.2.1 + NVMe SSD, GPU 가속 실시간 추론, 원시 CSI 로컬 처리 |
| ④ 설치 환경 | 연구실 · 생활 주거 공간 | 감지 영역 네 모서리에 노드를 분산 배치해 다중 관점(multi-view) CSI 확보 |

**3-4. 앱 메뉴 구성도 및 화면**

<p align="center"><img src="docs/images/app_menu.png" alt="앱 메뉴 구성도" width="700"></p>

<p align="center"><img src="docs/images/app_screens.png" alt="보호자 앱 화면 - 홈 요약, 집 안 상태, 안전 알림, 설정" width="640"></p>

**3-5. 엔티티 관계도 (서비스 확장용 설계안)**

<p align="center"><img src="docs/images/erd.png" alt="엔티티 관계도" width="700"></p>

> 현재 로컬 서버는 보호자·설정·알림 이력을 JSON 상태 파일(`app/server/dev_state.json`)에 저장합니다. 위 ERD는 다중 사용자 서비스로 확장할 때의 DB 설계안입니다.

<details>
<summary>유즈케이스 다이어그램 보기 (설계 단계)</summary>
<p align="center"><img src="docs/images/usecase.png" alt="유즈케이스 다이어그램" width="900"></p>
</details>

---

## **4. 시연 영상**

아래 링크는 실환경 데이터 수집 과정입니다. 센서 입력부터 앱 알림까지 한 화면에서 확인하는 전체 연동 영상은 별도로 등록할 예정입니다.

**동작 시연 (실환경 데이터 수집 과정)**

| 앉는 동작 | 눕는 동작 | 넘어지는 동작 |
|:---:|:---:|:---:|
| [![앉는 동작](https://img.youtube.com/vi/iZQwqRPPQ_E/hqdefault.jpg)](https://www.youtube.com/shorts/iZQwqRPPQ_E) | [![눕는 동작](https://img.youtube.com/vi/-Sp3iTWWZpE/hqdefault.jpg)](https://www.youtube.com/shorts/-Sp3iTWWZpE) | [![넘어지는 동작](https://img.youtube.com/vi/3AxhnGbnZMk/hqdefault.jpg)](https://www.youtube.com/shorts/3AxhnGbnZMk) |

---

## **5. 핵심 소스코드**

**5-1. multi-node 1D-CNN 낙상 감지 모델** — [`edge_ai/hanium_fall_v2/model.py`](edge_ai/hanium_fall_v2/model.py)

- 소스코드 설명 : 4개 노드의 CSI `(batch, 4, 193, 160)`를 노드 공유 1D-CNN 인코더로 각각 임베딩한 뒤, 노드별 신호 품질을 함께 넣은 attention으로 가중 합산합니다. 끊긴 노드는 `node_mask`로 제외되므로 모델 구조를 바꾸지 않고도 수신 노드 수 변화에 대응합니다. 하나의 융합 벡터에서 행동(10종)·인원(0/1/2/3+)·신호 품질을 동시에 출력하며, 전체 약 36만 파라미터의 경량 구조입니다.

```python
class MultiNodeFallModel(nn.Module):
    """Shared node encoder plus activity, person count, and quality heads."""

    def forward(self, features, node_mask, node_quality):
        batch, nodes, channels, frames = features.shape            # (B, 4, 193, 160)
        encoded = self.node_encoder(features.reshape(batch * nodes, channels, frames))
        encoded = encoded.reshape(batch, nodes, self.embedding_dim)

        # 노드 임베딩 + 신호 품질 → attention 점수, 끊긴 노드는 mask로 제외
        quality_column = node_quality.unsqueeze(-1)
        attention_logits = self.attention(torch.cat([encoded, quality_column], dim=-1)).squeeze(-1)
        attention_logits = attention_logits.masked_fill(~node_mask.bool(), -1e4)
        attention_weights = torch.softmax(attention_logits, dim=1)

        fused_embedding = torch.sum(encoded * attention_weights.unsqueeze(-1), dim=1)
        fused_quality = torch.sum(node_quality * attention_weights, dim=1, keepdim=True)
        fused = torch.cat([fused_embedding, fused_quality], dim=1)
        return {
            "activity_logits": self.activity_head(fused),   # 행동 10종
            "count_logits": self.count_head(fused),         # 인원 4분류
            "quality": self.quality_head(fused).squeeze(-1),
            "node_attention": attention_weights,
        }
```

**5-2. 낙상 확정 상태기계** — [`edge_ai/hanium_fall_v2/fall_state.py`](edge_ai/hanium_fall_v2/fall_state.py)

- 소스코드 설명 : 낙상 후보로 등록된 뒤에도 바로 알림을 보내지 않고, 이후 계속 누워 있는지(눕기 확률 누적)와 다시 일어났는지(서기·걷기 확률 누적)를 비교합니다. 회복이 먼저 확인되면 경보를 취소하고, 눕기 확률 누적 조건이 충족되면 `CONFIRMED`로 전이해 보호자 알림을 보냅니다. 눕기 3회는 연속 횟수가 아니며, 임계값은 검증 조건에 맞춰 평가해야 합니다.

```python
elif self.state == FallState.NORMAL:
    if fall_probability >= self.config.fall_candidate_probability:      # 0.70
        self.candidate_hits += 1
    else:
        self.candidate_hits = max(0, self.candidate_hits - 1)
    if self.candidate_hits >= self.config.fall_candidate_hits:          # 2회
        self._transition(FallState.FALL_CANDIDATE, now)
        reason = "repeated_fall_probability"
elif self.state == FallState.FALL_CANDIDATE:
    self._transition(FallState.POST_FALL_CHECK, now)
    reason = "checking_post_fall_posture"
elif self.state == FallState.POST_FALL_CHECK:
    if lying_probability >= self.config.post_fall_lying_probability:    # 0.55
        self.lying_hits += 1
    if recovery_probability >= self.config.recovery_probability:        # 0.65
        self.recovery_hits += 1
    else:
        self.recovery_hits = max(0, self.recovery_hits - 1)
    if self.recovery_hits >= self.config.recovery_hits:                 # 일어남 → 경보 취소
        self._transition(FallState.RECOVERED, now)
        reason = "person_recovered"
    elif self.lying_hits >= self.config.post_fall_lying_hits:           # 계속 누움 → 확정
        self._transition(FallState.CONFIRMED, now)
        reason = "fall_then_lying_confirmed"
    elif now - self.state_started >= self.config.post_fall_timeout_seconds:
        self._transition(FallState.NORMAL, now)
        reason = "post_fall_not_confirmed"
```

**5-3. CSI 특징 추출 파이프라인** — [`edge_ai/hanium_fall_v2/features.py`](edge_ai/hanium_fall_v2/features.py)

- 소스코드 설명 : 노드마다 불규칙하게 들어오는 CSI 패킷(약 33pps)을 32Hz 고정 격자로 보간한 뒤, 64개 서브캐리어에서 ① 절대 로그 진폭 ② 중앙값·MAD 기준 동적 진폭 ③ 프레임 간 위상차 ④ RSSI를 뽑아 193채널을 만듭니다. 학습과 실시간 추론이 이 함수 하나를 공유해 두 환경의 입력이 어긋나지 않도록 했습니다.

```python
log_amplitude = np.log1p(np.abs(complex_csi)).astype(np.float32)
absolute_amplitude = np.clip((log_amplitude - 3.0) / 1.5, -3.0, 3.0)

# 환경마다 다른 기본 신호 세기를 지우고 '움직임에 의한 변화'만 남김
median = np.median(log_amplitude, axis=0, keepdims=True)
mad = np.median(np.abs(log_amplitude - median), axis=0, keepdims=True)
dynamic_amplitude = np.clip((log_amplitude - median) / (1.4826 * mad + 0.05), -5.0, 5.0)

# 인접 프레임 간 위상 변화 (낙상처럼 빠른 반사 경로 변화에 민감)
phase_delta = np.zeros_like(log_amplitude, dtype=np.float32)
phase_delta[1:] = np.angle(complex_csi[1:] * np.conj(complex_csi[:-1])) / np.pi

features = np.concatenate(
    [absolute_amplitude.T, dynamic_amplitude.T, phase_delta.T, rssi.T], axis=0
)  # (64 + 64 + 64 + 1 = 193, 160 frames)
```

**5-4. 엣지 → 서버 연동** — [`app/server/jetson_edge_client.py`](app/server/jetson_edge_client.py)

- 소스코드 설명 : 엣지 AI의 실시간 결과(`latest_status.json`)를 읽어 서버 입력 형식으로 바꿉니다. 상태기계의 경보 플래그가 참이거나 상태가 `confirmed`이면 `danger`로 보냅니다. 호흡수는 엣지가 신뢰할 수 있다고 판단한 값만 전달하며, 연결 클라이언트는 값이 없으면 해당 필드를 생략합니다. 다만 현재 Node.js 서버에는 누락 호흡값을 시연값으로 보충하는 동작이 있어, 앱 표시까지 실측값만 전달된다고 보장할 수 없습니다. [보완 항목](docs/IMPLEMENTATION_STATUS.md#우선-보완할-구현-항목)을 참고하세요.

```python
def payload_from_live_status(record, args):
    fall = record.get("fall") or {}
    alarm = bool(fall.get("alarm")) or fall.get("state") == "confirmed"
    activity = str(record.get("activity") or "unknown")
    probabilities = record.get("activity_probabilities") or {}
    if alarm:
        status, pose = "danger", "lying"
        confidence = probabilities.get("fall", record.get("activity_confidence"))
    else:
        status = "normal"
        pose = LIVE_ACTIVITY_TO_POSE.get(activity, "standing")
    ...
    breathing_rate = respiratory.get("breathing_rate_bpm")   # 신뢰 가능할 때만 값이 있음
    if breathing_rate is not None:
        payload["breathingRate"] = round(clamp(float(breathing_rate), 6.0, 36.0), 1)
    return payload
```

---

## **6. 구현 범위와 한계**

심사·재현 시 혼동이 없도록, 저장소에 실제로 구현된 범위를 구분해 밝힙니다.

| 구분 | 현재 확인되는 범위 |
|---|---|
| 코드 구현 | CSI 수신·검증, 193채널 특징 추출, 다중 노드 학습·평가·추론, 낙상 상태기계, 호흡 추정, 상태 API, 서버·앱 연결 |
| 조건부 동작 | 실제 낙상 추론은 호환 가중치·센서가 필요. FCM은 설정·토큰·단말 권한이 필요 |
| 화면·시연 기능 | 역할 선택, 집 도면 표시, 전화 앱 연결, `once`·`sequence` 입력, 상황 재연 화면. 자동 위치 추정이나 자동 신고를 뜻하지 않음 |
| 확장 설계 | 일일·주간 생활 리포트, ERD 기반 DB, 공간 위험도 필터, 다중 사용자 서비스 및 원격 접근 인증 |
| 현재 보완 필요 | 호흡 예시값 구분, 모델 미설치·품질 부족 상태 전달, 입력 중단 시 마지막 상태의 최신성 표시 |

**제작설계서·개발보고서와 현재 코드의 관계**

제작설계서 p.21에는 현재 입력 규격이 있지만 다른 페이지에는 이전 규격이 섞여 있습니다. 문서 전체를 일괄적으로 ‘V1’, 저장소를 ‘검증 완료 V2’로 해석하지 않습니다.

| 항목 | 제출 문서에 기재된 내용 | 현재 코드 기준 |
|---|---|---|
| 수집·입력 | 100Hz·134×500, 설계서 p.22의 52×500, p.21의 약 33pps·193×160이 혼재 | 노드별 32Hz 보간·193×160·5초. 약 33pps는 수집 조건이며 고정 보장값이 아님 |
| LTF 선택 | 설계서 p.21 그림은 LLTF, 본문은 HT-LTF로 불일치 | `extract_lltf_iq()`가 첫 LLTF 64개 선택, 앞 2개 복소수 위치를 0으로 마스킹 |
| 모델 | 2종 분류와 10종 행동·인원·품질 설명이 혼재 | 공유 1D-CNN 인코더 이후 attention 융합, 행동 10종·인원·품질 출력 |
| 후처리 | 시간·공간 필터 설명 | 낙상 상태기계 구현. 공간 위험도 필터는 현재 경로에서 확인되지 않음 |
| 추론 방식·시간 | TensorRT·0.01초 기재 | PyTorch 경로. TensorRT 실행 및 전체 감지·알림 지연 산출물 미포함 |

요구사항별 파일 위치와 남은 검증은 [설계·구현 대조표](docs/IMPLEMENTATION_STATUS.md)에 정리했습니다.

---

## **7. 오픈소스 활용 및 팀 기여**

| 오픈소스 | 라이선스 | 사용 범위 |
|---|---|---|
| [RuView](https://github.com/ruvnet/RuView) | [MIT](https://github.com/ruvnet/RuView/blob/main/LICENSE) | ESP32-S3 CSI 추출 펌웨어, CSI 패킷 형식(ADR-018) |

RuView에는 자체 낙상·호흡 감지 기능도 있지만, 본 프로젝트는 **CSI를 뽑아 보내는 펌웨어로** 활용합니다. 이 저장소는 Jetson의 특징 추출·모델·상태기계와 서버·앱 연결 코드를 관리합니다. 실제 보드에 사용한 펌웨어 커밋·빌드 설정은 추가 기록이 필요합니다.

- CSI 패킷 수신·검증과 LLTF 블록 선택 — `edge_ai/hanium_fall_v2/adr018.py`, `edge_ai/ruview_adr018_receiver.py`
- 특징 추출, multi-node 1D-CNN, 데이터셋 분할·학습·평가 — `features.py`, `model.py`, `build_manifest.py`, `train.py`, `evaluate.py`
- 낙상 확정 상태기계, 호흡·기침 후보 모니터링 — `fall_state.py`, `respiratory.py`, `cough.py`
- Jetson 배포(systemd), 상태 API, 엣지 → 서버 연동, 로컬 서버, Flutter 앱 — `edge_ai/jetson/`, `status_api.py`, `app/`

---

## **8. 저장소 구조**

엣지 코드(`Hanium_jetson`)와 앱·서버 코드(`Hanium_app`)를 한 저장소에서 관리합니다.

```text
.
├── README.md
├── docs/
│   ├── IMPLEMENTATION_STATUS.md # 설계 요구사항·현재 코드·검증 범위
│   ├── RUNBOOK.md               # 화면 시연·실제 센서 연결·평가 실행
│   ├── images/                  # README 구성도·화면·실물 사진
│   └── data_collection/         # 실환경 CSI 녹화 세션 기록 (36건, 익명화)
├── edge_ai/                     # (구 Hanium_jetson) Jetson 엣지 AI 파이프라인
│   ├── hanium_fall_v2/          #   패킷 파서 · 특징 추출 · 모델 · 학습/평가 · 상태기계 · 호흡/기침 · 상태 API
│   ├── config/default_config.json
│   ├── jetson/                  #   실행 스크립트 · systemd 서비스
│   └── tests/                   #   단위 테스트
└── app/                         # (구 Hanium_app) 모바일 앱 + 로컬 서버
    ├── lib/                     #   Flutter 앱 (보호자/피보호자 모드, 도면, 알림)
    ├── server/                  #   Node.js 로컬 서버(dev_mock_server.js), 엣지 연동 클라이언트
    └── docs/
```

> `app/server/main.py`, `routers/`, `services/`는 초기 FastAPI 프로토타입으로, 현재 시연은 Node.js 서버를 사용합니다.

---

## **9. 실행 방법**

전체 명령은 [실행 및 시연 안내](docs/RUNBOOK.md)를 기준으로 사용합니다. 각 단계는 별도 터미널에서 실행합니다.

| 목적 | 실행 경로 | 확인할 결과 |
|---|---|---|
| 센서 없는 화면·통신 시연 | Node.js 서버 → Flutter 앱 → `jetson_edge_client.py once` 또는 `sequence` | 입력한 예시 상태가 앱까지 전달되는지 확인 |
| 실제 CSI 추론 연결 | 호환 가중치 확인 → 센서·엣지 추론 → `live-status` → 서버·앱 | 새 CSI 입력, 갱신 시각, 낙상 상태와 앱 반영을 함께 확인 |
| 코드 점검 | `edge_ai`에서 `selftest`, `unittest` | 파서·특징·상태기계 등의 로직 확인. 모델 실환경 성능 평가와 구분 |

`REAL_SENSOR_ONLY=true`는 서버의 자동 모의 이동을 멈추는 옵션입니다. 호흡 예시값 보충이나 마지막 상태 유지를 모두 제거하는 옵션은 아닙니다.

---

## **10. 검증 결과**

검증 결과는 출처와 범위를 나누어 제시합니다.

| 구분 | 확인 내용 | 해석 범위 |
|---|---|---|
| 이번 코드 점검 (2026-10-18) | 31개 발견, **25개 통과·6개 건너뜀**. `selftest` 통과, Torch 모델 점검은 건너뜀 | Python·NumPy 환경의 단위 테스트. PyTorch·센서·Jetson·앱 실기기 검증 아님 |
| 데이터 수집 기록 | [CSV](docs/data_collection/collection_log.csv) 36건: 낙상 14·혼동 동작 7·일상 15 | 녹화 목록. 보고서의 1,019개 평가 클립과 일대일 대응표는 미포함 |
| 개발보고서 p.19 초기 검증 | 502개 클립, 재현율 1.0·오탐 0건 | 보고서 기재 결과이며 현재 저장소에서 재계산한 값이 아님 |
| 개발보고서 p.15·19 확장 검증 | 1,019개 클립 중 낙상 302건, 11종 동작, **재현율 0.933** | 현재 가중치·평가 분할·예측 로그가 없어 현재 코드의 성능 수치로 단정하지 않음 |
| 개발보고서의 휘청임 오탐 | 해당 동작에서 0건 | 모든 동작·장시간 운영의 오탐 0건을 의미하지 않음 |

현재 코드에는 피험자 단위 분할, 평가, 배포 기준 점검 도구가 있습니다. 검증 결과를 재현하려면 가중치 식별값, 평가 manifest, 예측·정답, confusion matrix와 지표 파일이 함께 필요합니다. 전체 알림 지연은 입력 창·상태기계·통신을 포함해 별도로 측정합니다.

---

## **11. 개발 과정의 문제와 개선**

| 문제 | 해결 |
|---|---|
| 노드마다 CSI 패킷의 서브캐리어 수가 64/128/192로 섞여 들어와 학습 데이터와 실시간 입력의 형태가 달라짐 | 64/128/192 길이 패킷이 LLTF·HT-LTF·STBC-HT-LTF 블록 순서로 이어져 있음을 확인하고, 첫 번째 LLTF 블록(64 서브캐리어)만 고정 선택·20MHz 외 프레임은 거부하도록 파서를 표준화 |
| 하드웨어·AI 담당 간 CSI 데이터 형식(채널 수·프레임 길이·라벨)이 통일되지 않음 | 데이터 규격을 명문화하고, 학습·실시간 추론이 하나의 특징 추출 함수를 공유하도록 구조화 |
| 내장 PCB 안테나의 낮은 수신 감도(RSSI -80dBm 수준)로 패킷 유실 발생 | 5dBi 외장 다이폴 안테나 결선으로 수신 상태 개선(개발보고서 p.16~17) |
| 일반 가정망 트래픽이 CSI에 잡음으로 유입 | 고정 채널·전용 SSID·고정 IP의 센서 전용 독립망 구성 |
| 엣지 추론 결과 형식과 서버 입력 형식이 달라 실제 판정이 앱까지 전달되지 않음 | `jetson_edge_client.py live-status`로 상태기계 결과를 서버 형식으로 변환해 전달, 연결 클라이언트는 유효 호흡값만 전송. 서버·앱에서 예시값을 분리하는 개선은 남아 있음 |
| 낙상 확정 후 '방에 사람 없음' 예측 한 번에 경보가 해제됨 (움직이지 않는 사람은 빈 방처럼 보일 수 있음) | 사후 확인·확정 중에는 빈 방 예측을 무시하도록 상태기계를 수정하고 회귀 테스트 추가 |
| 앱 화면에 서버·센서 상태 등 개발자 중심 정보가 과도하게 노출 | 보호자(위험 대응)·피보호자(생활 상태·위치 공유)로 화면 목적을 재정의 |
| 좌표 기반 위치 표시는 보호자가 이해하기 어려움 | 거실·침실·욕실·현관 등 생활 공간 단위의 집 도면으로 표현 |

---

> **사용 범위** : 본 서비스는 의료기기가 아니며 질병의 진단·치료를 대체하지 않습니다. 호흡 리듬 등 생활 데이터는 건강 관리 참고용 정보로만 제공됩니다.
