import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hanium_app/app/hanium_app.dart';
import 'package:hanium_app/core/models/app_role.dart';
import 'package:hanium_app/core/models/safety_models.dart';
import 'package:hanium_app/core/services/local_safety_cache.dart';
import 'package:hanium_app/core/services/notification_service.dart';
import 'package:hanium_app/core/services/safety_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// 서버 없이 앱을 띄우기 위한 가짜 구현. 네트워크·Firebase·파일 캐시를 쓰지 않아서
// 테스트가 끝난 뒤 남는 타이머가 없다.
class _OfflineRepository extends SafetyRepository {
  _OfflineRepository()
    : super(client: MockClient((_) async => http.Response('{}', 503)));

  @override
  Future<Map<String, dynamic>?> getJson(String path) async => null;

  @override
  Future<Map<String, dynamic>?> postJson(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async => null;

  @override
  WebSocketChannel openLocationSocket() {
    throw UnsupportedError('테스트에서는 실시간 연결을 열지 않습니다.');
  }
}

class _NoopCache extends LocalSafetyCache {
  const _NoopCache();

  @override
  Future<SafetySnapshot?> load() async => null;

  @override
  Future<void> save(SafetySnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}

class _NoopNotificationService extends NotificationService {
  _NoopNotificationService(super.repository);

  @override
  Future<void> start({required AppRole role}) async {}

  @override
  Future<void> registerRole(AppRole role) async {}

  @override
  Future<void> dispose() async {}
}

Widget _buildApp() {
  final repository = _OfflineRepository();
  return HaniumApp(
    repository: repository,
    cache: const _NoopCache(),
    notificationService: _NoopNotificationService(repository),
  );
}

void main() {
  testWidgets('role selection screen is shown without credentials', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump();

    expect(find.text('한이음 어플'), findsOneWidget);
    expect(find.text('사용할 역할을 선택하세요'), findsOneWidget);
    expect(find.text('보호자'), findsOneWidget);
    expect(find.text('피보호자'), findsOneWidget);
    expect(find.text('역할 선택'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('guardian view shows a neutral state before any server data', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pump();

    // 역할 선택 화면은 ListView라서 시작 버튼이 화면 밖에 있으면 아직 만들어지지 않는다.
    final start = find.text('보호자로 시작하기');
    await tester.scrollUntilVisible(start, 200);
    await tester.tap(start);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('사용할 역할을 선택하세요'), findsNothing);
    expect(find.text('확인 필요'), findsWidgets);
    expect(find.text('정상'), findsNothing);
  });
}
