import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../firebase_options.dart';
import '../models/app_role.dart';
import 'safety_repository.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class NotificationService {
  NotificationService(this._repository);

  final SafetyRepository _repository;
  FirebaseMessaging? _messaging;
  StreamSubscription<String>? _tokenSubscription;
  AppRole _currentRole = AppRole.guardian;
  bool _ready = false;

  Future<void> start({required AppRole role}) async {
    try {
      _currentRole = role;
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 5));

      final messaging = FirebaseMessaging.instance;
      _messaging = messaging;
      await messaging
          .requestPermission(alert: true, badge: true, sound: true)
          .timeout(const Duration(seconds: 4));
      await messaging.setAutoInitEnabled(true);
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _ready = true;
      await _registerCurrentToken();
      _tokenSubscription ??= messaging.onTokenRefresh.listen((token) {
        unawaited(_repository.registerDeviceToken(token, role: _currentRole));
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) {});
      await messaging.getInitialMessage();
    } catch (_) {
      // 발표/개발 PC에 Firebase 설정이 없어도 앱 UI와 로컬 서버 시연은 계속 가능해야 한다.
    }
  }

  Future<void> registerRole(AppRole role) async {
    try {
      _currentRole = role;
      if (!_ready) {
        await start(role: role);
        return;
      }
      await _registerCurrentToken();
    } catch (_) {
      // Firebase 또는 네트워크가 준비되지 않아도 앱 화면 전환은 계속 가능해야 한다.
    }
  }

  Future<void> _registerCurrentToken() async {
    final messaging = _messaging;
    if (messaging == null) return;
    final token = await messaging.getToken().timeout(
      const Duration(seconds: 6),
    );
    if (token != null) {
      await _repository.registerDeviceToken(token, role: _currentRole);
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
  }
}
