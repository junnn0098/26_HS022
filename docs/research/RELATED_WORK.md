# 관련 연구와 설계에 반영할 점

공식 기술 문서, 저자 소속 기관의 연구 목록, 저자 공개 논문, NIST 원문을 2026-10-18에 확인했습니다. 각 자료에서 우리 설계와 평가에 반영할 점을 ‘프로젝트에 적용할 점’으로 정리했습니다. 논문 PDF·그림은 저장소에 옮기지 않고 원문 링크와 서지정보만 남깁니다.

## 1. ESP32-S3 CSI 버퍼 규격

- 원문: [Espressif ESP-IDF v5.2.1 Wi-Fi Driver — Wi-Fi Channel State Information](https://docs.espressif.com/projects/esp-idf/en/v5.2.1/esp32s3/api-guides/wifi.html#wi-fi-channel-state-information)
- 확인 내용: LTF 종류와 패킷 조건에 따라 버퍼 길이가 달라지며, `first_word_invalid`일 때 첫 4바이트가 유효하지 않을 수 있습니다. 원본 버퍼는 복소 값의 허수→실수 순서를 설명합니다.
- 프로젝트에 적용할 점: v2 파서의 64개 선택·앞 2개 마스킹이 이 규격에 근거합니다. 노드 펌웨어(RuView)의 LTF 설정·대역폭·직렬화 순서와 ESP-IDF 버전을 기록하고 고정합니다. 실측 녹화에서 노드가 보낸 패킷 폭이 수집일마다 달랐으므로([데이터셋 설명서](../../dataset/README.md#사용할-때-주의할-점)), 다음 수집은 한 가지 형식으로 고정합니다.
- 연결 자료: [패킷 규격](../architecture/DATA_CONTRACTS.md#1-adr-018-패킷), [`test_adr018.py`](../../edge_ai/tests/test_adr018.py).

## 2. WiFall

- Yuxi Wang, Kaishun Wu, Lionel M. Ni. **WiFall: Device-Free Fall Detection by Wireless Networks.** IEEE Transactions on Mobile Computing, 16(2), 581–594, 2017.
- 원문 정보: [HKUST 연구 목록](https://researchportal.hkust.edu.hk/en/publications/wifall-device-free-fall-detection-by-wireless-networks-3/), [DOI 10.1109/TMC.2016.2557792](https://doi.org/10.1109/TMC.2016.2557792).
- 확인 내용: 일반 802.11n NIC의 CSI를 이용한 비착용 낙상 감지로, 여러 실내 환경과 송수신 배치에서 평가했습니다. SVM·Random Forest 기반 결과를 제시합니다.
- 프로젝트에 적용할 점: 공간·송수신 배치가 달라지는 조건을 나누어 평가하고 혼동 동작을 포함합니다. 지금까지는 녹화 단위·날짜 단위 분할과 낙상 혼동 동작 6종으로 평가했고([실측 데이터 검증 결과](../../experiments/MEASURED_RESULTS.md)), 설치 공간을 기록하지 않아 공간별 평가는 다음 수집(`--room`)부터 합니다. 장비·모델·데이터 분할이 다르므로 논문의 정확도를 우리 성능과 직접 비교하지 않습니다.

## 3. Anti-Fall

- Daqing Zhang, Hao Wang, Yasha Wang, Junyi Ma. **Anti-Fall: A Non-intrusive and Real-time Fall Detector Leveraging CSI from Commodity WiFi Devices.** 2015.
- 원문: [저자 공개본 arXiv:1507.01057](https://arxiv.org/abs/1507.01057), [DOI 10.1007/978-3-319-19312-0_15](https://doi.org/10.1007/978-3-319-19312-0_15).
- 확인 내용: 두 수신 안테나의 CSI 위상차로 낙상 및 유사 동작의 구간을 나누고 진폭·위상을 함께 활용합니다.
- 프로젝트에 적용할 점: 낙상과 비슷한 큰 움직임을 따로 검증하는 근거로 참고합니다. 우리 v2 특징은 단일 안테나의 시간축 위상차, 호흡 추정은 인접 서브캐리어 위상차를 쓰므로 논문의 안테나 간 위상차와는 다른 특징입니다.

## 4. BreatheSmart

- Susanna Mosleh 외. **Monitoring Respiratory Motion With Wi-Fi CSI: Characterizing Performance and the BreatheSmart Algorithm.** IEEE Access, 2022.
- 원문: [NIST 공개 PDF](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=935107), [DOI 10.1109/ACCESS.2022.3230003](https://doi.org/10.1109/ACCESS.2022.3230003).
- 확인 내용: CSI 진폭·위상과 학습 모델을 이용해 호흡 패턴·빈도를 분석하고, 측정 길이·프레임률·채널 조건 등 평가 조건을 구체화합니다.
- 프로젝트에 적용할 점: 사인파 복원 결과만 제시하지 않고 실제 기준값, 조건별 오차, 값이 제공된 비율, 실패 조건을 함께 기록합니다([평가 절차](../validation/EVALUATION_PROTOCOL.md#호흡-비교)). 우리 스펙트럼 기반 추정기와 논문의 모델은 다르므로 결과를 직접 비교하지 않습니다.

## 저장소에 반영한 내용

선행연구의 정확도를 인용하는 대신 우리 데이터로 직접 평가했습니다. 실측 데이터 평가는 [실측 데이터 검증 결과](../../experiments/MEASURED_RESULTS.md), 합성 입력 검사는 [소프트웨어 실험](../../experiments/README.md), 앞으로의 평가 방법은 [평가 절차](../validation/EVALUATION_PROTOCOL.md)에 있습니다. 위 논문의 방법을 구현하거나 논문 데이터로 학습하지는 않았습니다.

인용 관리용 파일: [references.bib](references.bib).
