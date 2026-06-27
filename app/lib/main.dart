import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'firebase_options.dart';

part 'src/core_state.dart';
part 'src/login_screen.dart';
part 'src/home_screens.dart';
part 'src/alert_emergency_screens.dart';
part 'src/settings_screens.dart';
part 'src/app_actions.dart';


const _kServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'http://10.0.2.2:8000',
);
const _kDemoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);
final _navigatorKey = GlobalKey<NavigatorState>();

String get _serverBaseUrl => _kServerUrl.replaceFirst(RegExp(r'/+$'), '');

Uri _serverUri(String path) => Uri.parse('$_serverBaseUrl$path');

Uri _serverWsUri(String path) {
  final base = _serverBaseUrl;
  final wsBase = base.startsWith('https://')
      ? base.replaceFirst('https://', 'wss://')
      : base.replaceFirst('http://', 'ws://');
  return Uri.parse('$wsBase$path');
}

const _primary = Color(0xFF5B6CF6);
const _primaryDark = Color(0xFF1B2A4A);
const _primaryLight = Color(0xFFEFF2FF);
const _bg = Color(0xFFF5F7FB);
const _card = Colors.white;
const _textPrimary = Color(0xFF121A2F);
const _textMuted = Color(0xFF7A8397);
const _border = Color(0xFFE8ECF4);
const _success = Color(0xFF28BE82);
const _successLight = Color(0xFFE9FFF5);
const _warning = Color(0xFFF4A62A);
const _warningLight = Color(0xFFFFF6E4);
const _danger = Color(0xFFFF5B73);
const _dangerLight = Color(0xFFFFEEF2);
const _emergencyChannel = MethodChannel('hanium_app/emergency_actions');
const _kLocationPollInterval = Duration(milliseconds: 150);
const _kHealthPollInterval = Duration(seconds: 2);
const _kApiTimeout = Duration(milliseconds: 900);
const _roomOrder = ['거실', '주방', '침실', '욕실', '현관'];

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _setupFcm() async {
  final messaging = FirebaseMessaging.instance;
  await messaging
      .requestPermission(alert: true, badge: true, sound: true)
      .timeout(const Duration(seconds: 4));
  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  final token = await messaging.getToken().timeout(const Duration(seconds: 6));
  if (token != null) {
    await _registerDeviceToken(token);
  }

  messaging.onTokenRefresh.listen(_registerDeviceToken);
  FirebaseMessaging.onMessage.listen((message) {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message.notification?.body ?? '새 안전 알림이 도착했어요.'),
        backgroundColor: _danger,
        duration: const Duration(seconds: 5),
      ),
    );
  });
}

Future<void> _registerDeviceToken(String token) async {
  try {
    await http.post(
      _serverUri('/device/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token}),
    ).timeout(const Duration(seconds: 3));
  } catch (_) {
    // 네트워크가 막힌 시연 환경에서도 앱 화면은 열리도록 둔다.
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HaniumApp());

  unawaited(_startBackgroundServices());
}

Future<void> _startBackgroundServices() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 5));
    await _setupFcm();
  } catch (_) {
    // Firebase 설정 파일이 없는 개발 PC에서도 UI 확인이 가능하도록 한다.
  }

  unawaited(_syncInitialStateFromServer());
  WsService.instance.connect();
}

class HaniumApp extends StatelessWidget {
  const HaniumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Hanium Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: _bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _primary,
          brightness: Brightness.light,
          surface: _card,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: _textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
