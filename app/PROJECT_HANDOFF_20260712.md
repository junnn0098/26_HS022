# Hanium App 프로젝트 인수인계 문서

이 파일은 `PROJECT_HANDOFF.md`와 같은 내용의 날짜 고정 백업본이다.  
최신 내용은 같은 폴더의 `PROJECT_HANDOFF.md`를 우선 확인한다.

작성일: 2026-07-12

주요 확인 파일:

```text
PROJECT_HANDOFF.md
lib/app/hanium_app.dart
lib/features/shell/main_shell.dart
lib/features/home_map/home_map_screen.dart
lib/features/home_map/floor_plan_view.dart
server/run_mock_server_node.cmd
```

빠른 실행:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
.\server\run_mock_server_node.cmd
```

다른 PowerShell:

```powershell
cd C:\Users\juhwan\Documents\Codex\2026-06-23\new-chat\Hanium_app
flutter run -d emulator-5554
```

핵심 최신 변경:

```text
- 보호자 모드에서 피보호자 모드로 전환 버튼 추가
- 피보호자 모드에서 보호자 모드로 바로 전환
- 집 안 탭에서 FloorPlanView를 perspective3d: true로 호출
- 보고서용 프로젝트 S/W 어플 흐름도 생성
- 보고서 앱 파트 문장 정리 완료
```

자세한 내용은 `PROJECT_HANDOFF.md` 참고.
