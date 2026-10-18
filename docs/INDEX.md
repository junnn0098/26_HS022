# 프로젝트 자료 안내

프로젝트 소개는 [최상위 README](../README.md)에 있습니다. 나머지 자료는 아래와 같습니다.

## 데이터와 모델 성능

| 자료 | 내용 |
|---|---|
| [실측 데이터셋](../dataset/README.md) | 녹화 48건, 5초 윈도우 2,217개(낙상 969개), 동작 라벨 15종, 내려받기, 134채널 구성 |
| [보고서 모델 v1](../edge_ai/hanium_fall_v1/README.md) | 개발보고서의 `CSI1DCNN`, 팀 가중치 2개, 학습·평가·실시간 추론 |
| [실측 데이터 검증 결과](../experiments/MEASURED_RESULTS.md) | 분할 방식별 v1·v2 결과, 신호 진단, 다음 수집 방향, 재현 명령 |
| [합성 입력 소프트웨어 검증](../experiments/RESULTS.md) | 상태기계·호흡 추정·패킷 누락·서버 연동을 합성 입력으로 점검한 결과. 모델 성능 자료가 아님 |
| [실험 폴더 안내](../experiments/README.md) | 실측 모델 평가 스크립트와 합성 입력 검증을 구분한 실행 방법 |
| [평가 절차](validation/EVALUATION_PROTOCOL.md) | 데이터 분할 기준, 다음 수집에서 고칠 점, 모델·낙상 이벤트·호흡·단말 알림의 평가 단위와 기록할 증거 |

## 시스템 구현

| 자료 | 내용 |
|---|---|
| [엣지 AI](../edge_ai/README.md) | v1·v2 패키지 구성, Jetson 실행 스크립트 |
| [CSI 파형 도구](../edge_ai/tools/README.md) | 노드별 CSI 실시간 대시보드, 시연 로그 녹화·재생 |
| [데이터 연결 규격](architecture/DATA_CONTRACTS.md) | 패킷 바이트, 모델 입력, 엣지 상태 JSON, 서버 입력과 앱 표시, 데이터셋 파일 형식 |
| [로컬 서버](../app/server/README.md) | Node.js 서버 API, 보안·네트워크 설정, FCM |
| [Flutter 앱](../app/README.md) | 보호자·피보호자 화면 구성, 상태·출처 표시 규칙, 실행과 테스트 |
| [설계·구현 대조표](IMPLEMENTATION_STATUS.md) | 설계서 요구사항별 코드 근거와 보완 항목 |
| [실행 안내](RUNBOOK.md) | 내려받기 없는 확인, 센서 없는 시연, 모델 연결, FCM, 실측 결과 재현 |
| [관련 연구](research/RELATED_WORK.md) | 공식 기술 문서·논문 4건과 [BibTeX](research/references.bib) |

그림: [전체 시스템](images/system_overview.png), [데이터 흐름](images/data_flow.png), [낙상 상태기계](images/fall_state_machine.png), [하드웨어](images/hardware.jpg), [앱 화면](images/app_screens.png)(역할 선택·'확인 필요' 표시 반영 전 캡처).
