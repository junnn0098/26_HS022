# 프로젝트 자료 안내

프로젝트 소개는 [최상위 README](../README.md), 구현 근거·실행·검증 자료는 아래에서 확인할 수 있습니다.

| 읽고 싶은 내용 | 자료 | 포함한 산출물 |
|---|---|---|
| 실제로 실행한 실험 | [실험 결과 보고서](../experiments/RESULTS.md) | 낙상 10개 시나리오, 호흡 60회, 패킷 누락 36회, 노드 마스크, 서버 관측 |
| 실험 재현 | [실험 안내](../experiments/README.md) | Python 코드, 입력 시나리오, CSV·JSON, 그래프 3개, 환경·파일 해시 |
| 공개 수집 기록의 구성 | [데이터 설명서](data_collection/DATASET_CARD.md) | 동작 분포·메타데이터 집계, 평가 전 보완 사항, 재현 코드 |
| 센서에서 앱까지의 형식 | [데이터 연결 규격](architecture/DATA_CONTRACTS.md) | 패킷 바이트, 특징 배열, 상태 JSON, 서버 입력 |
| 설계서와 구현의 관계 | [설계·구현 대조표](IMPLEMENTATION_STATUS.md) | 요구사항별 코드 근거와 보완 항목 |
| 직접 실행·시연 | [실행 안내](RUNBOOK.md) | 센서 없는 시연, 모델 연결, FCM·평가 실행 |
| 실제 환경의 다음 검증 | [평가 절차](validation/EVALUATION_PROTOCOL.md) | 모델·이벤트·호흡·단말 알림의 평가 단위와 증거 |
| 기술 선택의 참고 근거 | [관련 연구](research/RELATED_WORK.md) | 공식 기술 문서·논문 4건과 BibTeX |

기존 이미지: [전체 시스템](images/system_overview.png), [데이터 흐름](images/data_flow.png), [앱 화면](images/app_screens.png), [하드웨어](images/hardware.jpg).

자료의 수보다 확인 가능한 근거를 우선합니다. 이번 실험은 합성 입력 기반 소프트웨어 검사이며, 센서·학습 가중치·실제 사용자의 실환경 성능을 새로 측정한 결과는 아닙니다.
