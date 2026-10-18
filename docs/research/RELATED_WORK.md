# 관련 연구와 설계에 반영할 점

2026-10-18 확인. 공식 기술 문서, 저자의 소속 기관 연구 목록, 저자 공개 논문, NIST 원문을 참고했습니다. 아래의 ‘프로젝트에 적용할 점’은 이 저장소를 검토해 정리한 제안이며 해당 논문이 우리 구현을 검증했다는 의미는 아닙니다. 외부 논문 PDF·그림을 복제하지 않고 원문 링크와 서지정보를 제공합니다.

## 1. ESP32-S3 CSI 버퍼 규격

- 원문: [Espressif ESP-IDF v5.2.1 Wi-Fi Driver — Wi-Fi Channel State Information](https://docs.espressif.com/projects/esp-idf/en/v5.2.1/esp32s3/api-guides/wifi.html#wi-fi-channel-state-information)
- 확인 내용: LTF 종류와 패킷 조건에 따라 버퍼 길이가 달라지며, `first_word_invalid`일 때 첫 4바이트가 유효하지 않을 수 있습니다. 원본 버퍼는 복소 값의 허수→실수 순서를 설명합니다.
- 프로젝트에 적용할 점: 64개 선택·앞 2개 마스킹의 근거를 남기고, 실제 펌웨어의 LTF 설정·대역폭·직렬화 순서를 고정해야 합니다. 현재 사용한 펌웨어 버전이 이 문서 버전과 같다는 확인은 아직 없습니다.
- 연결 자료: [패킷 규격](../architecture/DATA_CONTRACTS.md), `test_adr018.py`.

## 2. WiFall

- Yuxi Wang, Kaishun Wu, Lionel M. Ni. **WiFall: Device-Free Fall Detection by Wireless Networks.** IEEE Transactions on Mobile Computing, 16(2), 581–594, 2017.
- 원문 정보: [HKUST 연구 목록](https://researchportal.hkust.edu.hk/en/publications/wifall-device-free-fall-detection-by-wireless-networks-3/), [DOI 10.1109/TMC.2016.2557792](https://doi.org/10.1109/TMC.2016.2557792).
- 확인 내용: 일반 802.11n NIC의 CSI를 이용한 비착용 낙상 감지로, 여러 실내 환경과 송수신 배치에서 평가했습니다. SVM·Random Forest 기반 결과를 제시합니다.
- 프로젝트에 적용할 점: 실내 공간과 송수신 배치가 달라질 때 평가를 분리하고 혼동 동작을 포함해야 합니다. ESP32-S3와 다중 노드 CNN을 사용하는 본 프로젝트와 장비·모델·데이터 분할이 달라 논문의 정확도를 우리 성능으로 가져올 수 없습니다.

## 3. Anti-Fall

- Daqing Zhang, Hao Wang, Yasha Wang, Junyi Ma. **Anti-Fall: A Non-intrusive and Real-time Fall Detector Leveraging CSI from Commodity WiFi Devices.** 2015.
- 원문: [저자 공개본 arXiv:1507.01057](https://arxiv.org/abs/1507.01057), [DOI 10.1007/978-3-319-19312-0_15](https://doi.org/10.1007/978-3-319-19312-0_15).
- 확인 내용: 두 수신 안테나의 CSI 위상차로 낙상 및 유사 동작의 구간을 나누고 진폭·위상을 함께 활용합니다.
- 프로젝트에 적용할 점: 낙상과 유사한 큰 움직임을 별도로 검증하는 근거로 참고합니다. 본 코드의 단일 안테나 시간축 위상차나 호흡용 인접 서브캐리어 위상차와 동일한 특징으로 설명하지 않습니다.

## 4. BreatheSmart

- Susanna Mosleh 외. **Monitoring Respiratory Motion With Wi-Fi CSI: Characterizing Performance and the BreatheSmart Algorithm.** IEEE Access, 2022.
- 원문: [NIST 공개 PDF](https://tsapps.nist.gov/publication/get_pdf.cfm?pub_id=935107), [DOI 10.1109/ACCESS.2022.3230003](https://doi.org/10.1109/ACCESS.2022.3230003).
- 확인 내용: CSI 진폭·위상과 학습 모델을 이용해 호흡 패턴·빈도를 분석하고, 측정 길이·프레임률·채널 조건 등 평가 조건을 구체화합니다.
- 프로젝트에 적용할 점: 단순 사인파 복원 성공만 제시하지 않고 실제 기준값, 조건별 오차, 값이 제공된 비율, 실패 조건을 함께 기록합니다. 본 프로젝트의 스펙트럼 기반 추정기와 논문의 모델은 다르므로 결과를 직접 비교하지 않습니다.

## 이번 자료에 반영한 범위

선행연구의 정확도 수치를 차용하는 대신 [실험 입력·출력·시드 공개](../../experiments/README.md), [실환경 평가 절차](../validation/EVALUATION_PROTOCOL.md)를 보완했습니다. 논문을 구현했거나 그 데이터로 모델을 재학습한 것은 아닙니다.

인용 관리용 파일: [references.bib](references.bib).
