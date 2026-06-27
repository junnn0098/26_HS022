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

class AlertItem {
  const AlertItem({
    this.id = 0,
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    required this.room,
    this.urgent = false,
    this.resolved = false,
  });

  factory AlertItem.fromJson(Map<String, dynamic> json) {
    final id = switch (json['id']) {
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

    return AlertItem(
      id: id,
      type: (json['type'] as String?) ?? 'system',
      title: (json['title'] as String?) ?? '알림',
      message: (json['message'] as String?) ?? '새로운 상태가 확인됐어요.',
      time: (json['time'] as String?) ?? _formatTime(DateTime.now()),
      room: (json['room'] as String?) ?? AppState.room,
      urgent: json['urgent'] == true,
      resolved: json['resolved'] == true,
    );
  }

  final int id;
  final String type;
  final String title;
  final String message;
  final String time;
  final String room;
  final bool urgent;
  final bool resolved;
}

class Guardian {
  const Guardian({
    this.id = 0,
    required this.name,
    required this.phone,
    required this.role,
  });

  factory Guardian.fromJson(Map<String, dynamic> json) {
    final id = switch (json['id']) {
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };

    return Guardian(
      id: id,
      name: (json['name'] as String?) ?? '보호자',
      phone: (json['phone'] as String?) ?? '010-0000-0000',
      role: (json['role'] as String?) ?? '보호자',
    );
  }

  final int id;
  final String name;
  final String phone;
  final String role;
}

class EmergencyInfo {
  const EmergencyInfo({
    required this.address,
    required this.accessNote,
    required this.doorPassword,
    required this.medicalNote,
    required this.hospital,
  });

  factory EmergencyInfo.fromJson(Map<String, dynamic> json) {
    return EmergencyInfo(
      address:
          (json['address'] as String?) ??
          '경기도 수원시 ○○구 ○○로 123, 101동 1001호',
      accessNote:
          (json['accessNote'] as String?) ?? '공동현관 호출 후 보호자에게 연락해 주세요.',
      doorPassword: (json['doorPassword'] as String?) ?? '',
      medicalNote:
          (json['medicalNote'] as String?) ??
          '고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.',
      hospital: (json['hospital'] as String?) ?? '가까운 응급실: 아주대학교병원',
    );
  }

  final String address;
  final String accessNote;
  final String doorPassword;
  final String medicalNote;
  final String hospital;

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'accessNote': accessNote,
      'doorPassword': doorPassword,
      'medicalNote': medicalNote,
      'hospital': hospital,
    };
  }
}

class StatusInfo {
  const StatusInfo({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.color,
    required this.lightColor,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final String action;
  final Color color;
  final Color lightColor;
  final IconData icon;
}

class AppState {
  static String status = 'normal';
  static String room = '거실';
  static String pose = 'standing';
  static double personX = 0.34;
  static double personY = 0.45;
  static double confidence = 0.86;
  static DateTime lastUpdated = DateTime.now();
  static bool serverConnected = false;
  static String signedInGuardianName = '김주환 보호자';
  static String connectionMessage = '상태 확인 준비 중';
  static EmergencyInfo emergencyInfo = const EmergencyInfo(
    address: '경기도 수원시 ○○구 ○○로 123, 101동 1001호',
    accessNote: '공동현관 호출 후 보호자에게 연락해 주세요.',
    doorPassword: '',
    medicalNote: '고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.',
    hospital: '가까운 응급실: 아주대학교병원',
  );
  static final List<Offset> movementPath = [
    const Offset(0.26, 0.42),
    const Offset(0.35, 0.55),
    const Offset(0.55, 0.72),
    const Offset(0.76, 0.85),
  ];

  static final Map<String, dynamic> settings = {
    'fallDetection': true,
    'stillnessDetection': true,
    'stillnessMinutes': 30,
    'intrusionDetection': true,
    'showPath': true,
    'showSensors': true,
    'miniatureSize': 'medium',
    'alertRetentionDays': 30,
    'allowClipboardCopy': true,
    'showDoorPasswordInEmergency': true,
    'shareMedicalInfoInEmergency': true,
    'guardianOnlySensitiveInfo': true,
    'roomLabels': {
      '거실': '거실',
      '주방': '주방',
      '침실': '침실',
      '욕실': '욕실',
      '현관': '현관',
    },
  };

  static final List<Guardian> guardians = [
    const Guardian(name: '김영희 어르신', phone: '010-0000-0000', role: '보호 대상'),
    const Guardian(name: '김주환 보호자', phone: '010-1234-5678', role: '1순위 보호자'),
  ];

  static final List<AlertItem> alerts = [
    const AlertItem(
      type: 'danger',
      title: '낙상 의심 움직임 감지',
      message: '거실에서 급격한 쓰러짐 패턴이 감지됐어요.',
      time: '방금 전',
      room: '거실',
      urgent: true,
    ),
    const AlertItem(
      type: 'warning',
      title: '현관 접근이 감지됐어요',
      message: '현관 위험 구역에 접근했어요.',
      time: '오후 1:42',
      room: '현관',
    ),
    const AlertItem(
      type: 'normal',
      title: '정상 재실이 확인됐어요',
      message: '침실에서 평소와 비슷한 움직임이 감지됐어요.',
      time: '오전 11:05',
      room: '침실',
    ),
    const AlertItem(
      type: 'system',
      title: '안심 감지 상태가 정상으로 돌아왔어요',
      message: '거실의 생활 상태 확인이 다시 정상적으로 작동하고 있어요.',
      time: '어제',
      room: '거실',
    ),
  ];

  static bool settingBool(String key, bool fallback) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  static int settingInt(String key, int fallback) {
    final value = settings[key];
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  static void applySettings(Map<String, dynamic> nextSettings) {
    settings.addAll(nextSettings);
  }

  static void replaceGuardiansFromServer(List<dynamic> items) {
    final next = items
        .whereType<Map>()
        .map((item) => Guardian.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    if (next.isEmpty) return;
    guardians
      ..clear()
      ..addAll(next);
  }

  static void replaceAlertsFromServer(List<dynamic> items) {
    final next = items
        .whereType<Map>()
        .map((item) => AlertItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    if (next.isEmpty) return;
    alerts
      ..clear()
      ..addAll(next);
  }

  static void applyEmergencyInfo(Map<String, dynamic> nextInfo) {
    emergencyInfo = EmergencyInfo.fromJson(nextInfo);
  }

  static void recordPosition(double x, double y) {
    final next = Offset(
      x.clamp(0.0, 1.0).toDouble(),
      y.clamp(0.0, 1.0).toDouble(),
    );
    if (movementPath.isEmpty || (movementPath.last - next).distance > 0.018) {
      movementPath.add(next);
    }

    while (movementPath.length > 28) {
      movementPath.removeAt(0);
    }
  }
}

class WsService {
  WsService._();
  static final WsService instance = WsService._();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  bool _connected = false;
  bool _pollingLocation = false;
  Timer? _locationPollTimer;
  Timer? _healthPollTimer;
  Timer? _reconnectTimer;
  DateTime _lastAlertSync = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastServerSeen = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastLocationSignature = '';
  int _reconnectDelaySeconds = 2;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  void notify() => _notifyConnection();

  void connect() {
    _startHealthPolling();
    _startLocationPolling();
    if (_connected) return;
    _connected = true;
    if (!AppState.serverConnected) {
      AppState.connectionMessage = '집 안 상태를 확인하는 중';
      _notifyConnection();
    }

    try {
      final uri = _serverWsUri('/ws/location');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        _onData,
        onError: (_) => _reconnect('상태 확인이 잠시 끊겼어요'),
        onDone: () => _reconnect('상태 확인이 잠시 중단됐어요'),
        cancelOnError: true,
      );
    } catch (_) {
      _reconnect('집 안 상태를 불러올 수 없어요');
    }
  }

  void markHttpSuccess() {
    _lastServerSeen = DateTime.now();
    _reconnectDelaySeconds = 2;

    if (!AppState.serverConnected) {
      AppState.serverConnected = true;
      AppState.connectionMessage = '최근 상태 확인 완료';
      _notifyConnection();
    }
  }

  void _onData(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      final nextStatus = (map['status'] as String?) ?? AppState.status;
      final wasDisconnected = !AppState.serverConnected;
      final signature = _locationSignature(map);
      final changed = signature != _lastLocationSignature || wasDisconnected;

      _lastLocationSignature = signature;
      _lastServerSeen = DateTime.now();
      _reconnectDelaySeconds = 2;
      _applyLocationFromServer(map);
      AppState.serverConnected = true;
      AppState.connectionMessage = '새 상태를 바로 받는 중';

      if (wasDisconnected) {
        unawaited(_syncInitialStateFromServer());
      }

      _recordLiveAlert(nextStatus);

      final now = DateTime.now();
      if (now.difference(_lastAlertSync).inSeconds > 4) {
        _lastAlertSync = now;
        unawaited(_syncAlertsFromServer());
      }

      if (changed) {
        _controller.add(map);
      }
    } catch (_) {
      // 잘못된 임시 데이터가 들어와도 화면 전체가 멈추지 않게 한다.
    }
  }

  void _startHealthPolling() {
    _healthPollTimer ??= Timer.periodic(_kHealthPollInterval, (_) {
      unawaited(_pollHealth());
    });
    unawaited(_pollHealth());
  }

  Future<void> _pollHealth() async {
    final result = await ApiService.get('/health', updateConnection: false);
    if (result == null) {
      _markDisconnectedIfStale('최근 상태를 다시 확인하는 중');
      return;
    }

    markHttpSuccess();
  }

  void _startLocationPolling() {
    _locationPollTimer ??= Timer.periodic(_kLocationPollInterval, (_) {
      unawaited(_pollLatestLocation());
    });
    unawaited(_pollLatestLocation());
  }

  Future<void> _pollLatestLocation() async {
    if (_pollingLocation) return;
    _pollingLocation = true;

    try {
      final result = await ApiService.get(
        '/location/latest',
        updateConnection: false,
      );
      if (result == null) {
        _markDisconnectedIfStale('집 안 상태를 다시 불러오는 중');
        return;
      }

      markHttpSuccess();
      final location = result['location'];
      if (location is Map) {
        final nextLocation = Map<String, dynamic>.from(location);
        final signature = _locationSignature(nextLocation);
        final wasDisconnected = !AppState.serverConnected;
        final changed = signature != _lastLocationSignature || wasDisconnected;

        _lastLocationSignature = signature;
        _applyLocationFromServer(nextLocation);
        AppState.serverConnected = true;
        AppState.connectionMessage = '새 상태를 빠르게 확인 중';

        final status = (location['status'] as String?) ?? AppState.status;
        _recordLiveAlert(status);

        final now = DateTime.now();
        if (now.difference(_lastAlertSync).inSeconds > 4) {
          _lastAlertSync = now;
          unawaited(_syncAlertsFromServer());
        }

        if (changed && !_controller.isClosed) {
          _controller.add({'event': 'location_poll'});
        }
      }
    } finally {
      _pollingLocation = false;
    }
  }

  void _reconnect([String message = '상태 확인을 다시 시도 중']) {
    _connected = false;
    try {
      _channel?.sink.close();
    } catch (_) {
      // 이미 닫힌 소켓이면 무시한다.
    }
    _channel = null;

    final delay = _reconnectDelaySeconds;
    _reconnectDelaySeconds = min(_reconnectDelaySeconds * 2, 8).toInt();
    _markDisconnectedIfStale('$message · ${delay}초 후 다시 시도');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), connect);
  }

  void _markDisconnectedIfStale(String message) {
    final recentlyReachedServer =
        DateTime.now().difference(_lastServerSeen) < const Duration(seconds: 8);
    if (recentlyReachedServer) return;

    AppState.serverConnected = false;
    AppState.connectionMessage = message;
    _notifyConnection();
  }

  void _notifyConnection() {
    if (!_controller.isClosed) {
      _controller.add({'event': 'connection'});
    }
  }

  String _locationSignature(Map<String, dynamic> map) {
    final x = _normalizedDouble(map['x'], AppState.personX).toStringAsFixed(3);
    final y = _normalizedDouble(map['y'], AppState.personY).toStringAsFixed(3);
    final status = (map['status'] as String?) ?? AppState.status;
    final room = (map['room'] as String?) ?? '';
    final pose = (map['pose'] as String?) ?? '';
    final confidence = _normalizedDouble(
      map['confidence'],
      AppState.confidence,
    ).toStringAsFixed(2);
    return '$x|$y|$status|$room|$pose|$confidence';
  }
}

class ApiService {
  const ApiService._();

  static Future<Map<String, dynamic>?> get(
    String path, {
    bool updateConnection = true,
  }) async {
    try {
      final response = await http
          .get(_serverUri(path))
          .timeout(_kApiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      if (updateConnection) WsService.instance.markHttpSuccess();
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> post(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final response = await http
          .post(
            _serverUri(path),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_kApiTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      WsService.instance.markHttpSuccess();
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

Future<void> _syncInitialStateFromServer() async {
  final result = await ApiService.get('/state');
  if (result == null) return;
  _applyServerState(result);
  WsService.instance.notify();
}

Future<void> _syncAlertsFromServer() async {
  final result = await ApiService.get('/alerts');
  if (result == null) return;
  _applyServerState(result);
  WsService.instance.notify();
}

Future<void> _syncGuardiansFromServer() async {
  final result = await ApiService.get('/guardians');
  if (result == null) return;
  _applyServerState(result);
  WsService.instance.notify();
}

Future<void> _syncEmergencyInfoFromServer() async {
  final result = await ApiService.get('/emergency-info');
  if (result == null) return;
  _applyServerState(result);
  WsService.instance.notify();
}

void _applyServerState(Map<String, dynamic> data) {
  final settings = data['settings'];
  if (settings is Map) {
    AppState.applySettings(Map<String, dynamic>.from(settings));
  }

  final guardians = data['guardians'];
  if (guardians is List) {
    AppState.replaceGuardiansFromServer(guardians);
  }

  final alerts = data['alerts'];
  if (alerts is List) {
    AppState.replaceAlertsFromServer(alerts);
  }

  final emergencyInfo = data['emergencyInfo'];
  if (emergencyInfo is Map) {
    AppState.applyEmergencyInfo(Map<String, dynamic>.from(emergencyInfo));
  }

  final location = data['location'];
  if (location is Map) {
    _applyLocationFromServer(Map<String, dynamic>.from(location));
  }
}

void _applyLocationFromServer(Map<String, dynamic> map) {
  final nextStatus = (map['status'] as String?) ?? AppState.status;
  final serverRoom = map['room'] as String?;

  AppState.personX = _normalizedDouble(map['x'], AppState.personX);
  AppState.personY = _normalizedDouble(map['y'], AppState.personY);
  AppState.recordPosition(AppState.personX, AppState.personY);
  AppState.status = nextStatus;
  AppState.room = _validRoomName(serverRoom)
      ? serverRoom!
      : _roomFromPosition(AppState.personX, AppState.personY);
  AppState.pose = (map['pose'] as String?) ?? _poseFromStatus(nextStatus);
  AppState.confidence = _normalizedDouble(
    map['confidence'],
    AppState.confidence,
  );
  AppState.lastUpdated = DateTime.now();
}

bool _validRoomName(String? room) {
  return _roomOrder.contains(room);
}

Map<String, String> _roomLabelsForDisplay() {
  final labels = {for (final room in _roomOrder) room: room};
  final raw = AppState.settings['roomLabels'];

  if (raw is Map) {
    raw.forEach((key, value) {
      final room = key.toString();
      final label = value?.toString().trim() ?? '';
      if (_roomOrder.contains(room) && label.isNotEmpty) {
        labels[room] = label;
      }
    });
  }

  return labels;
}

String _roomDisplayName(String room) {
  return _roomLabelsForDisplay()[room] ?? room;
}

double _normalizedDouble(dynamic value, double fallback) {
  final number = switch (value) {
    num n => n.toDouble(),
    String s => double.tryParse(s),
    _ => null,
  };

  if (number == null) return fallback;
  return number.clamp(0.0, 1.0).toDouble();
}

AlertItem _alertFromStatus(String status) {
  final now = _formatTime(DateTime.now());
  switch (status) {
    case 'danger':
    case 'fall':
      return AlertItem(
        type: 'danger',
        title: '낙상 의심 움직임 감지',
        message: '${_roomDisplayName(AppState.room)}에서 급격한 쓰러짐 패턴이 감지됐어요.',
        time: now,
        room: AppState.room,
        urgent: true,
      );
    case 'out':
      return AlertItem(
        type: 'warning',
        title: '외출 또는 현관 접근 감지',
        message: '현관 근처에서 이동 패턴이 감지됐어요.',
        time: now,
        room: AppState.room,
      );
    case 'still':
      return AlertItem(
        type: 'warning',
        title: '장시간 움직임이 적어요',
        message: '${_roomDisplayName(AppState.room)}에서 움직임이 거의 감지되지 않았어요.',
        time: now,
        room: AppState.room,
      );
    default:
      return AlertItem(
        type: 'normal',
        title: '정상 재실이 확인됐어요',
        message: '${_roomDisplayName(AppState.room)}에서 평소와 비슷한 움직임이 감지됐어요.',
        time: now,
        room: AppState.room,
      );
  }
}

String _alertKindFromStatus(String status) {
  return switch (status) {
    'danger' || 'fall' => 'fall',
    'out' => 'out',
    'still' => 'still',
    _ => 'normal',
  };
}

String _alertKind(AlertItem alert) {
  if (alert.type == 'danger' || alert.urgent || alert.title.contains('낙상')) {
    return 'fall';
  }
  if (alert.title.contains('현관') || alert.title.contains('외출')) {
    return 'out';
  }
  if (alert.title.contains('무반응') || alert.title.contains('움직임이 적')) {
    return 'still';
  }
  if (alert.type == 'system') return 'system';
  return alert.type;
}

void _recordLiveAlert(String status) {
  if (status == 'normal') return;

  final next = _alertFromStatus(status);
  final nextKind = _alertKindFromStatus(status);
  final existingIndex = AppState.alerts.indexWhere(
    (alert) => !alert.resolved && _alertKind(alert) == nextKind,
  );

  if (existingIndex == 0) {
    AppState.alerts[0] = next;
    return;
  }

  if (existingIndex > 0) {
    AppState.alerts.removeAt(existingIndex);
  }

  AppState.alerts.insert(0, next);
}

String _formatTime(DateTime time) {
  final hour = time.hour;
  final minute = time.minute.toString().padLeft(2, '0');
  final prefix = hour < 12 ? '오전' : '오후';
  final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$prefix $displayHour:$minute';
}

String _lastUpdatedText() {
  final diff = DateTime.now().difference(AppState.lastUpdated);
  if (!AppState.serverConnected) return '최근 상태를 다시 확인하는 중';
  if (diff.inSeconds < 5) return '방금 확인했어요';
  if (diff.inMinutes < 1) return '${diff.inSeconds}초 전에 확인했어요';
  return '${diff.inMinutes}분 전에 확인했어요';
}

String _certaintyLabel([double? value]) {
  final confidence = (value ?? AppState.confidence).clamp(0, 1);
  if (confidence >= 0.85) return '높음';
  if (confidence >= 0.65) return '보통';
  return '확인 필요';
}

Color _connectionColor() {
  return AppState.serverConnected ? _success : _warning;
}

String _connectionTitle() {
  return AppState.serverConnected ? '안심 시스템 정상 작동 중' : '최근 상태를 다시 확인 중';
}

String _careStatusSubtitle() {
  if (!AppState.serverConnected) {
    return '마지막으로 받은 상태를 보여드리고 있어요.';
  }

  return '${_roomDisplayName(AppState.room)}에서 ${_poseLabel(AppState.pose)} 상태 · ${_lastUpdatedText()}';
}

String _careStatusDetail() {
  if (!AppState.serverConnected) {
    return '잠시 후 자동으로 다시 확인해요. 급하면 보호자 연락이나 119 신고 정보를 먼저 확인하세요.';
  }

  return '확인이 필요한 변화가 생기면 바로 알려드릴게요.';
}

String _summaryTitle(StatusInfo info) {
  if (info.color == _danger) return '빠른 확인이 필요한 상황이에요';
  if (info.color != _success) return '잠깐 확인이 필요한 상황이에요';
  return '평소와 비슷한 하루예요';
}

String _summarySubtitle(StatusInfo info) {
  if (info.color == _danger) return '전화 또는 신고 정보를 바로 확인해 주세요.';
  if (info.color != _success) return '위치와 움직임 변화를 한 번 살펴봐 주세요.';
  return '확인이 필요한 위험 알림이 없어요.';
}

String _alertReason(AlertItem alert) {
  if (alert.type == 'danger' || alert.urgent) {
    return '${_roomDisplayName(alert.room)}에서 평소와 다른 급격한 자세 변화가 감지됐어요.';
  }
  if (alert.type == 'warning' && alert.title.contains('현관')) {
    return '현관 가까운 구역에서 이동 흐름이 확인됐어요.';
  }
  if (alert.type == 'warning') {
    return '${_roomDisplayName(alert.room)}에서 움직임이 적은 시간이 길어지고 있어요.';
  }
  if (alert.type == 'system') {
    return '안심 시스템 상태가 바뀌어 보호자 확인이 필요해요.';
  }
  return '${_roomDisplayName(alert.room)}에서 평소와 비슷한 움직임이 확인됐어요.';
}

String _guardianMeaning(AlertItem alert) {
  if (alert.type == 'danger' || alert.urgent) {
    return '먼저 전화로 반응을 확인하고, 응답이 없으면 119 신고 정보를 확인하세요.';
  }
  if (alert.type == 'warning' && alert.title.contains('현관')) {
    return '외출 가능성이 있으니 현재 위치와 이동 방향을 한 번 확인하세요.';
  }
  if (alert.type == 'warning') {
    return '잠시 후에도 움직임이 없으면 전화로 상태를 확인하는 게 좋아요.';
  }
  if (alert.type == 'system') {
    return '안심 확인이 정상적으로 이어지는지 한 번 점검하세요.';
  }
  return '지금은 추가 조치 없이 상태만 확인하면 충분해요.';
}

String _emergencyEventTitle() {
  return switch (AppState.status) {
    'out' => '현관 접근 움직임',
    'still' => '장시간 무반응',
    'danger' || 'fall' => '낙상 의심 움직임',
    _ => '확인이 필요한 움직임',
  };
}

String _emergencyEventMessage() {
  return switch (AppState.status) {
    'out' => '${_roomDisplayName(AppState.room)} 가까이에서 외출 가능성이 있는 이동이 감지됐어요.',
    'still' => '${_roomDisplayName(AppState.room)}에서 평소보다 움직임이 적게 감지됐어요.',
    'danger' || 'fall' => '${_roomDisplayName(AppState.room)}에서 급격한 쓰러짐 패턴이 감지됐어요.',
    _ => '${_roomDisplayName(AppState.room)}에서 보호자 확인이 필요한 변화가 감지됐어요.',
  };
}

String _emergencyFirstStep() {
  return switch (AppState.status) {
    'out' => '현재 위치와 외출 여부 확인',
    'still' => '전화로 반응 여부 확인',
    _ => '어르신께 전화해 상태 확인',
  };
}

String _emergencyFirstStepSubtitle() {
  return switch (AppState.status) {
    'out' => '현관 근처 이동인지, 실제 외출 상황인지 먼저 확인하세요.',
    'still' => '응답이 없거나 이상하면 다음 단계로 진행하세요.',
    _ => '응답이 없으면 다음 단계로 진행하세요.',
  };
}

StatusInfo _statusInfo(String status) {
  switch (status) {
    case 'danger':
    case 'fall':
      return const StatusInfo(
        title: '빠른 확인이 필요해요',
        subtitle: '낙상 의심 움직임이 감지됐어요.',
        action: '보호자에게 즉시 알려드렸어요',
        color: _danger,
        lightColor: _dangerLight,
        icon: Icons.warning_rounded,
      );
    case 'out':
      return const StatusInfo(
        title: '현관 접근이 감지됐어요',
        subtitle: '외출 또는 현관 이동 가능성이 있어요.',
        action: '필요하면 바로 연락해 주세요',
        color: _warning,
        lightColor: _warningLight,
        icon: Icons.door_front_door_rounded,
      );
    case 'still':
      return const StatusInfo(
        title: '오래 움직임이 적어요',
        subtitle: '평소보다 움직임이 적게 감지됐어요.',
        action: '잠시 후 다시 확인할게요',
        color: _warning,
        lightColor: _warningLight,
        icon: Icons.access_time_filled_rounded,
      );
    default:
      return const StatusInfo(
        title: '이상 징후가 없어요',
        subtitle: '거실에서 평소와 비슷한 움직임이 감지됐어요.',
        action: '집 안 상태 보기',
        color: _success,
        lightColor: _successLight,
        icon: Icons.check_rounded,
      );
  }
}

String _poseFromStatus(String status) {
  return switch (status) {
    'danger' || 'fall' => 'lying',
    'still' => 'sitting',
    _ => 'standing',
  };
}

String _roomFromPosition(double x, double y) {
  if (x > 0.62 && y < 0.42) return '주방';
  if (x < 0.48 && y > 0.58) return '침실';
  if (x > 0.68 && y > 0.55) return '현관';
  if (x > 0.47 && x < 0.68 && y > 0.56) return '욕실';
  return '거실';
}

BoxDecoration _softCard({Color color = _card, double radius = 26}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    boxShadow: [
      BoxShadow(
        color: const Color(0xFF15213D).withOpacity(0.05),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ],
  );
}

class LiveBuilder extends StatefulWidget {
  const LiveBuilder({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  State<LiveBuilder> createState() => _LiveBuilderState();
}

class _LiveBuilderState extends State<LiveBuilder> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = WsService.instance.stream.listen((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController(text: 'guardian');
  final _pwCtrl = TextEditingController(text: '1234');
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await Future.delayed(const Duration(milliseconds: 450));

    final id = _idCtrl.text.trim().toLowerCase();
    final password = _pwCtrl.text;
    final validAccount =
        password == '1234' &&
        (id == 'guardian' || id == 'admin' || id == 'protector');

    if (validAccount) {
      AppState.signedInGuardianName = _primaryGuardian()?.name ?? '김주환 보호자';
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
      return;
    }

    setState(() {
      _loading = false;
      _error = '아이디 또는 비밀번호가 올바르지 않습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5C7CFF), Color(0xFF7659E8)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -28,
                      top: -42,
                      child: Container(
                        width: 136,
                        height: 136,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '카메라 없이,\n가족의 안전을 확인하세요',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '착용 기기 없이 집 안의 위험 징후를 감지해요.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFFFDF6E),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '낙상 · 장시간 무반응 · 외부인 침입\n위험할 때 보호자에게 바로 알려드려요.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '보호자 로그인',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '등록된 보호자 계정으로 시작하세요.',
                style: TextStyle(color: _textMuted),
              ),
              const SizedBox(height: 22),
              _LoginField(
                controller: _idCtrl,
                label: '아이디',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 14),
              _LoginField(
                controller: _pwCtrl,
                label: '비밀번호',
                icon: Icons.lock_rounded,
                obscureText: _obscure,
                trailing: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: _textMuted,
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _softCard(color: _primaryLight, radius: 18),
                child: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: _primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '사생활을 침해하지 않는 안전 확인\n카메라 없이 집 안 위험 신호를 살펴요.',
                        style: TextStyle(
                          color: _primaryDark,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_kDemoMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _softCard(
                    color: const Color(0xFFFFF7ED),
                    radius: 18,
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.key_rounded, color: _warning),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '발표용 계정  ID guardian · PW 1234\n실사용 모드에서는 보호자 계정만 보이게 숨겨져요.',
                          style: TextStyle(
                            color: _textPrimary,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
    this.trailing,
    this.obscureText = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Widget? trailing;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _primary),
        suffixIcon: trailing,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onOpenHomeStatus: () => setState(() => _index = 1)),
      const HomeStatusScreen(),
      const AlertScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          backgroundColor: Colors.white,
          indicatorColor: _primaryLight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: _primary),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded, color: _primary),
              label: '집 안',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded, color: _primary),
              label: '알림',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: _primary),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenHomeStatus});

  final VoidCallback onOpenHomeStatus;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final info = _statusInfo(AppState.status);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HomeHeader(info: info),
                const SizedBox(height: 20),
                _StatusHeroCard(info: info),
                const SizedBox(height: 14),
                _NextActionCard(
                  info: info,
                  onOpenHomeStatus: onOpenHomeStatus,
                  onEmergency: () => _openEmergency(context),
                ),
                const SizedBox(height: 24),
                const Text(
                  '오늘의 안심 요약',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _SummaryCard(info: info),
                const SizedBox(height: 24),
                const Text(
                  '빠른 연락',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _ContactCard(onEmergency: () => _openEmergency(context)),
                const SizedBox(height: 14),
                _InfoStrip(
                  icon: AppState.serverConnected
                      ? Icons.verified_user_rounded
                      : Icons.sync_problem_rounded,
                  title: _connectionTitle(),
                  subtitle: _careStatusDetail(),
                  color: _connectionColor(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '김영희 어르신',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info.title == '이상 징후가 없어요' ? '지금 상태를 확인했어요' : info.title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: _primary,
                size: 30,
              ),
            ),
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: info.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final isDanger = info.color == _danger;
    final isWarning = info.color == _warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDanger
              ? const [Color(0xFFFF6178), Color(0xFFFF4E67)]
              : isWarning
                  ? const [Color(0xFFFFBF5E), Color(0xFFF4A62A)]
                  : const [Color(0xFF45D298), Color(0xFF21B77D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -38,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(info.icon, color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '현재 상태',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          info.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                info.subtitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Divider(color: Colors.white.withOpacity(0.22)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _WhitePill(
                    icon: Icons.location_on_rounded,
                    text:
                        '${_roomDisplayName(AppState.room)} · ${_lastUpdatedText()}',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _openEmergency(context),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(isDanger ? '긴급 확인' : info.action),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _softCard(radius: 24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: info.lightColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(info.icon, color: info.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _summaryTitle(info),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _summarySubtitle(info),
                      style: const TextStyle(color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: _border),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '최근 활동',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_roomDisplayName(AppState.room)} → ${_roomDisplayName(AppState.room == '거실' ? '침실' : '거실')} · 12분 전',
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.onEmergency});

  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.phone_rounded, color: _primary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '어르신께 연락이 필요한가요?',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '등록된 전화번호로 바로 연결해요.',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEmergency, child: const Text('전화하기')),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: color.withOpacity(0.08), radius: 22),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeStatusScreen extends StatelessWidget {
  const HomeStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final info = _statusInfo(AppState.status);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '집 안 상태',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              color: _textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '김영희 어르신 · 생활 상태 확인',
                            style: TextStyle(color: _textMuted),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(info: info),
                  ],
                ),
                const SizedBox(height: 18),
                const FloorPlanCard(),
                const SizedBox(height: 18),
                const _ConnectionStatusCard(),
                const SizedBox(height: 14),
                _InfoStrip(
                  icon: Icons.check_circle_rounded,
                  title:
                      '${_roomDisplayName(AppState.room)}에서 ${_poseLabel(AppState.pose)} 상태',
                  subtitle: '안전 확인을 위한 추정 정보예요. 위험 변화가 생기면 바로 알려드려요.',
                  color: info.color,
                ),
                const SizedBox(height: 14),
                _CareGuideCard(info: info),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _poseLabel(String pose) {
  return switch (pose) {
    'lying' => '누워 있는',
    'sitting' => '앉아 있는',
    'walking' => '이동 중인',
    _ => '서 있는',
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final color = !AppState.serverConnected ? _warning : info.color;
    final text = !AppState.serverConnected
        ? '확인 중'
        : info.color == _success
            ? '안심 확인'
            : '확인 필요';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context) {
    final connected = AppState.serverConnected;
    final color = _connectionColor();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: color.withOpacity(0.08), radius: 22),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              connected
                  ? Icons.health_and_safety_rounded
                  : Icons.manage_search_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _connectionTitle(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected ? _careStatusSubtitle() : _careStatusDetail(),
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloorPlanCard extends StatelessWidget {
  const FloorPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(AppState.status);
    final movementPath = List<Offset>.of(AppState.movementPath);
    final showPath = AppState.settingBool('showPath', true);
    final showSensors = AppState.settingBool('showSensors', true);
    final roomLabels = _roomLabelsForDisplay();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_searching_rounded,
                        color: _primary,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '현재 위치 중심',
                        style: TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_rounded),
                style: IconButton.styleFrom(backgroundColor: _bg),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.menu_rounded),
                style: IconButton.styleFrom(backgroundColor: _bg),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 0.82,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFF),
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    final left = (AppState.personX.clamp(0.07, 0.93) * w - 18)
                        .toDouble();
                    final top = (AppState.personY.clamp(0.08, 0.90) * h - 32)
                        .toDouble();

                    return Stack(
                      children: [
                        CustomPaint(
                          painter: FloorPlanPainter(
                            statusColor: info.color,
                            movementPath: movementPath,
                            showPath: showPath,
                            showSensors: showSensors,
                            roomLabels: roomLabels,
                          ),
                          size: Size.infinite,
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          left: left,
                          top: top,
                          child: MiniPersonMarker(
                            color: info.color,
                            pose: AppState.pose,
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 14,
                          child: _MapLegend(color: info.color),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FloorPlanPainter extends CustomPainter {
  const FloorPlanPainter({
    required this.statusColor,
    required this.movementPath,
    required this.showPath,
    required this.showSensors,
    required this.roomLabels,
  });

  final Color statusColor;
  final List<Offset> movementPath;
  final bool showPath;
  final bool showSensors;
  final Map<String, String> roomLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Paint()
      ..color = const Color(0xFF3C465A)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final thinWall = Paint()
      ..color = const Color(0xFF3C465A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    Rect r(double l, double t, double rr, double b) {
      return Rect.fromLTRB(
        size.width * l,
        size.height * t,
        size.width * rr,
        size.height * b,
      );
    }

    void room(Rect rect, Color fill, String label) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = fill,
      );

      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF586176),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      text.paint(canvas, Offset(rect.left + 10, rect.top + 10));
    }

    final outer = r(0.07, 0.07, 0.93, 0.92);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(6)),
      Paint()..color = Colors.white,
    );

    final living = r(0.07, 0.07, 0.61, 0.56);
    final kitchen = r(0.61, 0.07, 0.93, 0.42);
    final bedroom = r(0.07, 0.56, 0.47, 0.92);
    final bath = r(0.47, 0.56, 0.67, 0.92);
    final entrance = r(0.67, 0.42, 0.93, 0.92);

    room(living, const Color(0xFFEAF3EF), roomLabels['거실'] ?? '거실');
    room(kitchen, const Color(0xFFF5E8C9), roomLabels['주방'] ?? '주방');
    room(bedroom, const Color(0xFFE8F0FF), roomLabels['침실'] ?? '침실');
    room(bath, const Color(0xFFEAF7FB), roomLabels['욕실'] ?? '욕실');
    room(entrance, const Color(0xFFF0E5F8), roomLabels['현관'] ?? '현관');

    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(6)),
      wall,
    );
    canvas.drawLine(
      Offset(size.width * 0.61, size.height * 0.07),
      Offset(size.width * 0.61, size.height * 0.92),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.07, size.height * 0.56),
      Offset(size.width * 0.67, size.height * 0.56),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.42),
      Offset(size.width * 0.93, size.height * 0.42),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.47, size.height * 0.56),
      Offset(size.width * 0.47, size.height * 0.92),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.42),
      Offset(size.width * 0.67, size.height * 0.92),
      thinWall,
    );

    _drawFurniture(canvas, size);
    if (showPath) _drawRecentPath(canvas, size);
    if (showSensors) _drawSensors(canvas, size);
  }

  void _drawFurniture(Canvas canvas, Size size) {
    RRect rr(
      double l,
      double t,
      double w,
      double h,
      Color color, {
      double radius = 8,
    }) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * l,
          size.height * t,
          size.width * w,
          size.height * h,
        ),
        Radius.circular(radius),
      );
    }

    final furniture = Paint()..color = const Color(0xFFB8C9BD);
    final wood = Paint()..color = const Color(0xFFD7C79F);
    final blue = Paint()..color = const Color(0xFFBFD1EF);
    final purple = Paint()..color = const Color(0xFFD6BEE5);
    final line = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 2;

    canvas.drawRRect(
      rr(0.12, 0.16, 0.25, 0.08, const Color(0xFFB8C9BD)),
      furniture,
    );
    canvas.drawRRect(rr(0.18, 0.36, 0.16, 0.10, const Color(0xFFD7C79F)), wood);
    canvas.drawCircle(
      Offset(size.width * 0.26, size.height * 0.41),
      8,
      Paint()..color = const Color(0xFFF6EECF),
    );
    canvas.drawCircle(
      Offset(size.width * 0.32, size.height * 0.41),
      8,
      Paint()..color = const Color(0xFFF6EECF),
    );

    canvas.drawRRect(rr(0.67, 0.14, 0.20, 0.10, const Color(0xFFD7C79F)), wood);
    canvas.drawRRect(rr(0.70, 0.26, 0.16, 0.08, const Color(0xFFF1E2BC)), wood);
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.30),
      9,
      Paint()..color = const Color(0xFFFFF7D7),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30),
      9,
      Paint()..color = const Color(0xFFFFF7D7),
    );

    canvas.drawRRect(rr(0.13, 0.66, 0.25, 0.16, const Color(0xFFBFD1EF)), blue);
    canvas.drawLine(
      Offset(size.width * 0.14, size.height * 0.71),
      Offset(size.width * 0.37, size.height * 0.71),
      line,
    );
    canvas.drawRRect(
      rr(0.52, 0.66, 0.08, 0.13, const Color(0xFFBED8E1)),
      Paint()..color = const Color(0xFFBED8E1),
    );
    canvas.drawCircle(
      Offset(size.width * 0.56, size.height * 0.73),
      9,
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      rr(0.73, 0.62, 0.13, 0.18, const Color(0xFFD6BEE5)),
      purple,
    );
  }

  void _drawRecentPath(Canvas canvas, Size size) {
    if (movementPath.length < 2) return;

    final path = movementPath
        .map(
          (point) => Offset(
            size.width * point.dx.clamp(0.07, 0.93).toDouble(),
            size.height * point.dy.clamp(0.07, 0.92).toDouble(),
          ),
        )
        .toList();

    final paint = Paint()
      ..color = _primary.withOpacity(0.45)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < path.length - 1; i++) {
      _drawDashedLine(canvas, path[i], path[i + 1], paint);
    }

    canvas.drawCircle(path.first, 4, Paint()..color = _primary.withOpacity(0.35));
    canvas.drawCircle(path.last, 5, Paint()..color = statusColor.withOpacity(0.7));
  }

  void _drawSensors(Canvas canvas, Size size) {
    final sensors = [
      Offset(size.width * 0.08, size.height * 0.08),
      Offset(size.width * 0.92, size.height * 0.08),
      Offset(size.width * 0.08, size.height * 0.91),
      Offset(size.width * 0.92, size.height * 0.91),
    ];

    for (final sensor in sensors) {
      canvas.drawCircle(
        sensor,
        10,
        Paint()..color = _success.withOpacity(0.16),
      );
      canvas.drawCircle(sensor, 5, Paint()..color = _success);

      final signal = Paint()
        ..color = _success.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawArc(
        Rect.fromCircle(center: sensor, radius: 13),
        -1.0,
        1.8,
        false,
        signal,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final distance = (b - a).distance;
    final direction = (b - a) / distance;
    const dash = 7.0;
    const gap = 7.0;
    var current = 0.0;

    while (current < distance) {
      final start = a + direction * current;
      final end = a + direction * min(current + dash, distance);
      canvas.drawLine(start, end, paint);
      current += dash + gap;
    }
  }

  @override
  bool shouldRepaint(FloorPlanPainter oldDelegate) {
    if (oldDelegate.statusColor != statusColor ||
        oldDelegate.showPath != showPath ||
        oldDelegate.showSensors != showSensors ||
        oldDelegate.roomLabels.toString() != roomLabels.toString() ||
        oldDelegate.movementPath.length != movementPath.length) {
      return true;
    }

    if (movementPath.isEmpty) return false;
    return oldDelegate.movementPath.isEmpty ||
        oldDelegate.movementPath.last != movementPath.last;
  }
}

class MiniPersonMarker extends StatelessWidget {
  const MiniPersonMarker({required this.color, required this.pose, super.key});

  final Color color;
  final String pose;

  @override
  Widget build(BuildContext context) {
    final lying = pose == 'lying';
    final scale = switch (AppState.settings['miniatureSize']) {
      'small' => 0.86,
      'large' => 1.18,
      _ => 1.0,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 8 * scale,
            vertical: 5 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            '${_poseLabel(pose)} 상태 · ${_roomDisplayName(AppState.room)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10 * scale,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: (lying ? 42 : 34) * scale,
          height: (lying ? 22 : 46) * scale,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Transform.rotate(
            angle: lying ? pi / 2 : 0,
            child: CustomPaint(painter: PersonPainter(color: color)),
          ),
        ),
      ],
    );
  }
}

class PersonPainter extends CustomPainter {
  PersonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final head = Paint()..color = color;

    final cx = size.width / 2;
    canvas.drawCircle(Offset(cx, size.height * 0.22), 5, head);
    canvas.drawLine(
      Offset(cx, size.height * 0.34),
      Offset(cx, size.height * 0.62),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.43),
      Offset(cx - 8, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.43),
      Offset(cx + 8, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.62),
      Offset(cx - 8, size.height * 0.82),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.62),
      Offset(cx + 8, size.height * 0.82),
      paint,
    );
  }

  @override
  bool shouldRepaint(PersonPainter oldDelegate) => oldDelegate.color != color;
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: color, text: '사람'),
          const SizedBox(width: 12),
          const _LegendDot(color: _success, text: '확인 구역'),
          const SizedBox(width: 12),
          const _LegendDot(color: _primary, text: '최근 이동'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: _textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({
    required this.info,
    required this.onOpenHomeStatus,
    required this.onEmergency,
  });

  final StatusInfo info;
  final VoidCallback onOpenHomeStatus;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final isDanger = info.color == _danger;
    final hasConcern = info.color != _success;
    final title = isDanger
        ? '먼저 이렇게 확인해 주세요'
        : hasConcern
            ? '잠깐 확인해 주세요'
            : '오늘은 이렇게만 확인하면 돼요';
    final steps = isDanger
        ? const [
            '어르신께 전화 또는 문자로 반응을 확인',
            '집 도면에서 현재 위치와 상태 확인',
            '위험하면 119 신고 정보를 바로 확인',
          ]
        : hasConcern
            ? const [
                '집 도면에서 위치와 이동 흐름 확인',
                '몇 분 뒤 상태가 바뀌는지 다시 확인',
                '걱정되면 등록된 번호로 바로 연락',
              ]
            : const [
                '현재 위치와 최근 확인 시각만 확인',
                '위험 알림이 없는지 간단히 확인',
                '필요할 때만 전화하기 버튼 사용',
              ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: info.lightColor, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: info.color.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(info.icon, color: info.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.86),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: info.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: isDanger ? onEmergency : onOpenHomeStatus,
              style: FilledButton.styleFrom(
                backgroundColor: isDanger ? _primaryDark : Colors.white,
                foregroundColor: isDanger ? Colors.white : info.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(
                isDanger
                    ? Icons.emergency_share_rounded
                    : Icons.grid_view_rounded,
                size: 18,
              ),
              label: Text(isDanger ? '긴급 화면 열기' : '집 안 상태 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareGuideCard extends StatelessWidget {
  const _CareGuideCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final hasRisk = info.color != _success;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '보호자가 볼 내용',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          _SensorRow(
            icon: Icons.schedule_rounded,
            title: '최근 확인',
            status: _lastUpdatedText(),
            color: AppState.serverConnected ? _success : _warning,
          ),
          _SensorRow(
            icon: Icons.location_on_rounded,
            title: '현재 위치',
            status: _roomDisplayName(AppState.room),
            color: info.color,
          ),
          _SensorRow(
            icon: hasRisk
                ? Icons.notification_important_rounded
                : Icons.check_circle_rounded,
            title: hasRisk ? '필요한 행동' : '현재 알림',
            status: hasRisk ? info.action : '확인할 위험 알림 없음',
            color: hasRisk ? info.color : _success,
          ),
        ],
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
          ),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  String _filter = '전체';

  @override
  void initState() {
    super.initState();
    unawaited(_syncAlertsFromServer());
  }

  List<AlertItem> get _filtered {
    final retained = AppState.alerts.where(_keptByRetentionSetting).toList();
    if (_filter == '전체') return retained;
    if (_filter == '위험')
      return retained.where((e) => e.type == 'danger').toList();
    if (_filter == '외출')
      return retained.where((e) => e.type == 'warning').toList();
    return retained
        .where((e) => e.type == 'system' || e.type == 'normal')
        .toList();
  }

  bool _keptByRetentionSetting(AlertItem alert) {
    final retentionDays = AppState.settingInt('alertRetentionDays', 30);
    final daysAgo = _daysAgoFromLabel(alert.time);
    if (daysAgo == null) return true;
    return daysAgo < retentionDays;
  }

  int? _daysAgoFromLabel(String label) {
    if (label.contains('방금') ||
        label.contains('오전') ||
        label.contains('오후') ||
        label.contains('분 전') ||
        label.contains('시간 전')) {
      return 0;
    }
    if (label.contains('어제')) return 1;
    final match = RegExp(r'(\d+)\s*일\s*전').firstMatch(label);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String get _retentionLabel {
    final days = AppState.settingInt('alertRetentionDays', 30);
    return '최근 ${days}일 기준';
  }

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final info = _statusInfo(AppState.status);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '안전 알림',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        unawaited(_syncAlertsFromServer());
                        _showTodoSnack(context, '알림을 새로 확인했어요.');
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (info.color == _danger) ...[
                  _DangerNotice(onTap: () => _openEmergency(context)),
                  const SizedBox(height: 18),
                ],
                _FilterTabs(
                  value: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '알림 기록',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _primaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _retentionLabel,
                        style: const TextStyle(
                          color: _primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_filtered.isEmpty)
                  const _EmptyAlertState()
                else
                  ..._filtered.map(
                    (alert) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AlertTile(alert: alert),
                    ),
                  ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: () => _openEmergency(context),
                    icon: const Icon(Icons.phone_rounded),
                    label: const Text('긴급 연락하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryDark,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
                if (_kDemoMode) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _triggerDangerScenario(context),
                      icon: const Icon(Icons.play_circle_rounded),
                      label: const Text('발표용 위험 상황 실행'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _danger,
                        side: const BorderSide(color: _dangerLight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DangerNotice extends StatelessWidget {
  const _DangerNotice({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _danger,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_rounded, color: Colors.white),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '긴급 상황이 발생하면\n보호자에게 즉시 알려드려요',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '긴급 연락 관리',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = ['전체', '위험', '외출', '시스템'];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2F8),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: tabs
            .map(
              (tab) => Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(tab),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: value == tab ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Text(
                      tab,
                      style: TextStyle(
                        color: value == tab ? _primary : _textMuted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _EmptyAlertState extends StatelessWidget {
  const _EmptyAlertState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: _softCard(radius: 22),
      child: const Column(
        children: [
          Icon(Icons.notifications_none_rounded, color: _textMuted, size: 34),
          SizedBox(height: 10),
          Text(
            '표시할 알림이 없어요',
            style: TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '위험 상황이 생기면 이곳에 기록돼요.',
            style: TextStyle(color: _textMuted),
          ),
        ],
      ),
    );
  }
}

class AlertTile extends StatelessWidget {
  const AlertTile({required this.alert, super.key});

  final AlertItem alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.type) {
      'danger' => _danger,
      'warning' => _warning,
      'system' => _primary,
      _ => _success,
    };

    final icon = switch (alert.type) {
      'danger' => Icons.warning_rounded,
      'warning' => Icons.priority_high_rounded,
      'system' => Icons.wifi_rounded,
      _ => Icons.check_rounded,
    };
    final displayColor = alert.resolved ? _success : color;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => AlertDetailScreen(alert: alert)),
        );
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: _softCard(radius: 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: displayColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                alert.resolved ? Icons.check_rounded : icon,
                color: displayColor,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          alert.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _textPrimary,
                          ),
                        ),
                      ),
                      if (alert.resolved)
                        const Text(
                          '확인 완료',
                          style: TextStyle(
                            color: _success,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else if (alert.urgent)
                        Text(
                          '방금 전',
                          style: TextStyle(
                            color: displayColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      else
                        Text(
                          alert.time,
                          style: const TextStyle(
                            color: _textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    alert.message,
                    style: const TextStyle(color: _textMuted, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '자세히 보기',
                    style: TextStyle(
                      color: displayColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({required this.alert, super.key});

  final AlertItem alert;

  @override
  Widget build(BuildContext context) {
    final color = switch (alert.type) {
      'danger' => _danger,
      'warning' => _warning,
      'system' => _primary,
      _ => _success,
    };
    final urgent = alert.urgent && !alert.resolved;

    return LiveBuilder(
      builder: (context) {
        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubPageHeader(
                    title: '알림 상세',
                    subtitle: '감지된 상황과 보호자가 할 일을 한눈에 확인해요.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                alert.resolved
                                    ? Icons.check_rounded
                                    : Icons.warning_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                alert.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          alert.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Divider(color: Colors.white.withOpacity(0.24)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _EmergencyMeta(
                                label: '감지 위치',
                                value: _roomDisplayName(alert.room),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 42,
                              color: Colors.white.withOpacity(0.18),
                            ),
                            Expanded(
                              child: _EmergencyMeta(
                                label: '감지 시각',
                                value: alert.time,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _AlertReasonCard(alert: alert, color: color),
                  const SizedBox(height: 16),
                  _DetailInfoCard(
                    title: '현재 집 안 상태',
                    rows: [
                      _DetailRow('현재 위치', _roomDisplayName(AppState.room)),
                      _DetailRow('현재 자세', '${_poseLabel(AppState.pose)} 상태'),
                      _DetailRow(
                        '감지 확실성',
                        _certaintyLabel(),
                      ),
                      _DetailRow('최근 확인', _lastUpdatedText()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const FloorPlanCard(),
                  const SizedBox(height: 16),
                  Text(
                    urgent ? '보호자가 바로 할 일' : '처리 기록',
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ActionStep(
                    number: '1',
                    title: urgent ? '어르신 상태 확인' : '알림이 확인됐어요',
                    subtitle: urgent
                        ? '전화 또는 문자로 먼저 반응을 확인해 주세요.'
                        : '확인 완료 처리된 알림입니다.',
                  ),
                  _ActionStep(
                    number: '2',
                    title: urgent ? '위험하면 긴급 화면으로 이동' : '기록으로 보관',
                    subtitle: urgent
                        ? '주소, 출입 안내, 119 신고 정보를 바로 볼 수 있어요.'
                        : '추후 위험 패턴을 볼 때 참고할 수 있어요.',
                  ),
                  const SizedBox(height: 10),
                  if (urgent)
                    _EmergencyActionButton(
                      icon: Icons.phone_rounded,
                      label: '긴급 화면 열기',
                      description: '전화, 문자, 119 신고 정보 확인',
                      backgroundColor: _primaryDark,
                      foregroundColor: Colors.white,
                      onPressed: () => _openEmergency(context),
                    ),
                  const SizedBox(height: 10),
                  _EmergencyActionButton(
                    icon: Icons.copy_rounded,
                    label: '알림 내용 복사',
                    description: '보호자 공유용 문장으로 복사',
                    backgroundColor: Colors.white,
                    foregroundColor: _textPrimary,
                    borderColor: _border,
                    onPressed: () => _copyAlertSummary(context, alert),
                  ),
                  if (urgent) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => _confirmSafe(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _textPrimary,
                          side: const BorderSide(color: _border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('확인 완료로 처리'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;
}

class _DetailInfoCard extends StatelessWidget {
  const _DetailInfoCard({required this.title, required this.rows});

  final String title;
  final List<_DetailRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: Text(
                    row.label,
                    style: const TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (row != rows.last)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: _border),
              ),
          ],
        ],
      ),
    );
  }
}

class _AlertReasonCard extends StatelessWidget {
  const _AlertReasonCard({required this.alert, required this.color});

  final AlertItem alert;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.help_rounded, color: color),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '왜 알림이 떴나요?',
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _ReasonLine(label: '감지 근거', value: _alertReason(alert)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: _border),
          ),
          _ReasonLine(label: '해야 할 일', value: _guardianMeaning(alert)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: _border),
          ),
          _ReasonLine(label: '감지 확실성', value: _certaintyLabel()),
        ],
      ),
    );
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(
              color: _textMuted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final emergencyInfo = AppState.emergencyInfo;
        final info = _statusInfo(AppState.status);
        final eventColor = info.color == _success ? _warning : info.color;

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const Spacer(),
                      _StatusPill(info: info),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '김영희 어르신',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '빠른 확인이 필요해요',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: eventColor,
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.warning_rounded,
                                color: Colors.white,
                                size: 34,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                _emergencyEventTitle(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _emergencyEventMessage(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Divider(color: Colors.white.withOpacity(0.24)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _EmergencyMeta(
                                label: '발생 위치',
                                value: _roomDisplayName(AppState.room),
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 42,
                              color: Colors.white.withOpacity(0.18),
                            ),
                            Expanded(
                              child: _EmergencyMeta(
                                label: '발생 시각',
                                value: _lastUpdatedText(),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '먼저 이렇게 확인해 주세요',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionStep(
                    number: '1',
                    title: _emergencyFirstStep(),
                    subtitle: _emergencyFirstStepSubtitle(),
                  ),
                  const _ActionStep(
                    number: '2',
                    title: '구급 상황이면 119에 신고',
                    subtitle: '주소와 감지 위치를 바로 확인할 수 있어요.',
                  ),
                  const SizedBox(height: 8),
                  _EmergencyInfoCard(info: emergencyInfo),
                  const SizedBox(height: 18),
                  const Text(
                    '바로 할 수 있는 행동',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EmergencyActionButton(
                    icon: Icons.phone_rounded,
                    label: '어르신께 전화하기',
                    description: _careTarget()?.phone ?? '보호 대상 연락처가 필요해요',
                    backgroundColor: _primaryDark,
                    foregroundColor: Colors.white,
                    onPressed: () => _callCareTarget(context),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _EmergencyActionButton(
                          icon: Icons.local_hospital_rounded,
                          label: '119 전화 열기',
                          description: '전화 앱에서 바로 확인',
                          backgroundColor: _danger,
                          foregroundColor: Colors.white,
                          compact: true,
                          onPressed: () => _dial119(context),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _EmergencyActionButton(
                          icon: Icons.sms_rounded,
                          label: '상황 문자 작성',
                          description: _primaryGuardian()?.name ?? '보호자 선택',
                          backgroundColor: _primaryLight,
                          foregroundColor: _primary,
                          compact: true,
                          onPressed: () => _sendEmergencySms(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _EmergencyActionButton(
                    icon: Icons.copy_rounded,
                    label: '신고 문장 복사',
                    description: '주소와 출입 안내를 클립보드에 저장',
                    backgroundColor: Colors.white,
                    foregroundColor: _textPrimary,
                    borderColor: _border,
                    onPressed: () => _copyEmergencySummary(context),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () => _confirmSafe(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textPrimary,
                        side: const BorderSide(color: _border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: const Text('괜찮음을 확인했어요'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmergencyMeta extends StatelessWidget {
  const _EmergencyMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _EmergencyInfoCard extends StatelessWidget {
  const _EmergencyInfoCard({required this.info});

  final EmergencyInfo info;

  @override
  Widget build(BuildContext context) {
    final hasDoorPassword = info.doorPassword.trim().isNotEmpty;
    final showDoorPassword = AppState.settingBool(
      'showDoorPasswordInEmergency',
      true,
    );
    final showMedicalInfo = AppState.settingBool(
      'shareMedicalInfoInEmergency',
      true,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _primaryLight,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_hospital_rounded,
                  color: _primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '119 신고 정보',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      '위급할 때 바로 읽어줄 내용이에요.',
                      style: TextStyle(color: _textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmergencyInfoEditScreen(),
                    ),
                  );
                },
                child: const Text('수정'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _EmergencyInfoLine(
            icon: Icons.home_rounded,
            label: '집 주소',
            value: info.address,
          ),
          _EmergencyInfoLine(
            icon: Icons.door_front_door_rounded,
            label: '출입 안내',
            value: info.accessNote,
          ),
          if (hasDoorPassword)
            _EmergencyInfoLine(
              icon: Icons.lock_rounded,
              label: '도어락 참고',
              value: showDoorPassword ? info.doorPassword : '개인정보 설정으로 숨김',
            ),
          if (showMedicalInfo)
            _EmergencyInfoLine(
              icon: Icons.medical_information_rounded,
              label: '의료 참고사항',
              value: info.medicalNote,
            ),
          _EmergencyInfoLine(
            icon: Icons.local_hospital_outlined,
            label: '가까운 병원',
            value: info.hospital,
            bottomPadding: 0,
          ),
        ],
      ),
    );
  }
}

class _EmergencyInfoLine extends StatelessWidget {
  const _EmergencyInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.bottomPadding = 12,
  });

  final IconData icon;
  final String label;
  final String value;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final visibleValue = value.trim().isEmpty ? '아직 입력되지 않았어요' : value;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _textMuted, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  visibleValue,
                  style: TextStyle(
                    color: value.trim().isEmpty ? _textMuted : _textPrimary,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyActionButton extends StatelessWidget {
  const _EmergencyActionButton({
    required this.icon,
    required this.label,
    required this.description,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String description;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 88 : 66),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 14 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: borderColor == null ? null : Border.all(color: borderColor!),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: foregroundColor, size: 22),
                    const SizedBox(height: 9),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foregroundColor.withOpacity(0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Icon(icon, color: foregroundColor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: foregroundColor,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foregroundColor.withOpacity(0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: foregroundColor.withOpacity(0.72),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ActionStep extends StatelessWidget {
  const _ActionStep({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 18),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: _primaryLight,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final stillnessMinutes =
            (AppState.settings['stillnessMinutes'] as num?)?.round() ?? 30;

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '설정',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '가족과 알림, 집 안 화면을 관리해요.',
                  style: TextStyle(color: _textMuted),
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: _softCard(radius: 24),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: _primaryLight,
                        child: Icon(Icons.person_rounded, color: _primary),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '김영희 어르신',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: _textPrimary,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '집 정보 · 보호자 · 전화번호',
                              style: TextStyle(
                                color: _textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: _textMuted),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '집 안 화면',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _SettingGroup(
                  children: [
                    _SettingTile(
                      icon: Icons.home_rounded,
                      color: _primary,
                      title: '집 평면도 관리',
                      subtitle: '방 이름과 배치를 수정해요',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const FloorPlanManagementScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingTile(
                      icon: Icons.health_and_safety_rounded,
                      color: _success,
                      title: '안심 확인 상태',
                      subtitle: '집 안 상태가 잘 들어오는지 확인',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SensorStatusScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingTile(
                      icon: Icons.accessibility_new_rounded,
                      color: const Color(0xFFB569D6),
                      title: '미니어처 표시 방식',
                      subtitle: '색상 · 크기 · 이동 경로 표시',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MiniatureDisplayScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  '위험 알림',
                  style: TextStyle(
                    color: _textMuted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _SettingGroup(
                  children: [
                    _SwitchTile(
                      title: '낙상 의심',
                      subtitle: '급격한 쓰러짐 패턴',
                      settingKey: 'fallDetection',
                      value: AppState.settingBool('fallDetection', true),
                    ),
                    _SwitchTile(
                      title: '장시간 무반응',
                      subtitle: '움직임 없음 기준 시간 설정',
                      settingKey: 'stillnessDetection',
                      value: AppState.settingBool('stillnessDetection', true),
                      trailingText: '$stillnessMinutes분',
                    ),
                    _SwitchTile(
                      title: '외부인 침입',
                      subtitle: '위험 구역 움직임 감지',
                      settingKey: 'intrusionDetection',
                      value: AppState.settingBool('intrusionDetection', true),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SettingGroup(
                  children: [
                    _SettingTile(
                      icon: Icons.local_police_rounded,
                      color: _danger,
                      title: '보호자·119 신고 정보',
                      subtitle: '연락 순서 · 주소 · 출입 안내',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const GuardianManagementScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingTile(
                      icon: Icons.location_on_rounded,
                      color: _warning,
                      title: '집 주소와 출입 안내',
                      subtitle: '119 신고 때 필요한 정보를 저장해요',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const EmergencyInfoEditScreen(),
                          ),
                        );
                      },
                    ),
                    _SettingTile(
                      icon: Icons.privacy_tip_rounded,
                      color: _primary,
                      title: '개인정보 및 기록 보관',
                      subtitle: '저장 기간과 보호자 열람 권한',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PrivacyManagementScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FloorPlanManagementScreen extends StatelessWidget {
  const FloorPlanManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubPageHeader(
                    title: '집 평면도 관리',
                    subtitle: '보호자가 이해하기 쉬운 집 구조로 보여줘요.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  const FloorPlanCard(),
                  const SizedBox(height: 16),
                  const Text(
                    '방 이름',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingGroup(
                    children: [
                      _PlanRoomTile(
                        room: '거실',
                        description: '주 활동 공간 · 낙상 감지 우선 구역',
                        color: const Color(0xFFE8F4ED),
                        onTap: () => _editRoomLabel(context, '거실'),
                      ),
                      _PlanRoomTile(
                        room: '주방',
                        description: '화기/식사 공간 · 장시간 정지 확인',
                        color: const Color(0xFFFFF1CC),
                        onTap: () => _editRoomLabel(context, '주방'),
                      ),
                      _PlanRoomTile(
                        room: '침실',
                        description: '수면 공간 · 야간 움직임 확인',
                        color: const Color(0xFFD8E6FF),
                        onTap: () => _editRoomLabel(context, '침실'),
                      ),
                      _PlanRoomTile(
                        room: '욕실',
                        description: '낙상 위험 구역 · 짧은 체류도 중요',
                        color: const Color(0xFFD9EEF5),
                        onTap: () => _editRoomLabel(context, '욕실'),
                      ),
                      _PlanRoomTile(
                        room: '현관',
                        description: '외출/외부인 접근 확인 구역',
                        color: const Color(0xFFE9D7F1),
                        onTap: () => _editRoomLabel(context, '현관'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: () => _resetRoomLabels(context),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('기본 방 이름으로 되돌리기'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _textPrimary,
                        side: const BorderSide(color: _border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _softCard(color: _primaryLight, radius: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_rounded, color: _primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _kDemoMode
                                ? '현재는 발표용 기본 도면이에요. 방 이름을 바꾸면 도면, 알림 상세, 긴급 화면 문구에 같이 반영돼요.'
                                : '방 이름을 가족이 부르는 표현으로 바꿀 수 있어요. 예: 안방, 작은방, 거실 앞 현관',
                            style: const TextStyle(
                              color: _textMuted,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SensorStatusScreen extends StatelessWidget {
  const SensorStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final connected = AppState.serverConnected;
        final connectionColor = _connectionColor();

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubPageHeader(
                    title: '안심 확인 상태',
                    subtitle: '어르신의 집 안 상태가 잘 들어오는지 확인해요.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: _softCard(
                      color: connected ? _successLight : _warningLight,
                      radius: 24,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.white,
                          child: Icon(
                            connected
                                ? Icons.health_and_safety_rounded
                                : Icons.manage_search_rounded,
                            color: connectionColor,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _connectionTitle(),
                                style: const TextStyle(
                                  color: _textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppState.connectionMessage,
                                style: const TextStyle(
                                  color: _textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SensorMetricCard(
                          title: '감지 확실성',
                          value: _certaintyLabel(),
                          icon: Icons.verified_user_rounded,
                          color: _primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SensorMetricCard(
                          title: '마지막 확인',
                          value: _lastUpdatedText(),
                          icon: Icons.schedule_rounded,
                          color: _success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SensorStatusCard(
                    name: '거실 확인 구역',
                    location: '거실 중심 · 주 생활 공간',
                    strength: connected ? '잘 확인되고 있어요' : '다시 확인 중이에요',
                    online: connected,
                  ),
                  _SensorStatusCard(
                    name: '주방 확인 구역',
                    location: '주방 입구 · 이동 흐름 확인',
                    strength: connected ? '잘 확인되고 있어요' : '다시 확인 중이에요',
                    online: connected,
                  ),
                  _SensorStatusCard(
                    name: '현관 확인 구역',
                    location: '현관 위험 구역 · 출입 확인',
                    strength: connected ? '잘 확인되고 있어요' : '다시 확인 중이에요',
                    online: connected,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: () => _refreshServerHealth(context),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('상태 다시 확인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class MiniatureDisplayScreen extends StatelessWidget {
  const MiniatureDisplayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final size =
            (AppState.settings['miniatureSize'] as String?) ?? 'medium';

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubPageHeader(
                    title: '미니어처 표시 방식',
                    subtitle: '보호자가 보기 편한 방식으로 도면 표시를 조정해요.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  const FloorPlanCard(),
                  const SizedBox(height: 16),
                  _SettingGroup(
                    children: [
                      _SwitchTile(
                        title: '최근 이동 경로 표시',
                        subtitle: '점선으로 최근 이동 흐름을 보여줘요',
                        settingKey: 'showPath',
                        value: AppState.settingBool('showPath', true),
                      ),
                      _SwitchTile(
                        title: '확인 구역 표시',
                        subtitle: '도면 모서리의 확인 구역을 보여줘요',
                        settingKey: 'showSensors',
                        value: AppState.settingBool('showSensors', true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '미니어처 크기',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniatureSizeButton(
                          label: '작게',
                          selected: size == 'small',
                          onTap: () => _saveMiniatureSize(context, 'small'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniatureSizeButton(
                          label: '보통',
                          selected: size == 'medium',
                          onTap: () => _saveMiniatureSize(context, 'medium'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniatureSizeButton(
                          label: '크게',
                          selected: size == 'large',
                          onTap: () => _saveMiniatureSize(context, 'large'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubPageHeader extends StatelessWidget {
  const _SubPageHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          style: IconButton.styleFrom(backgroundColor: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _textMuted, height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlanRoomTile extends StatelessWidget {
  const _PlanRoomTile({
    required this.room,
    required this.description,
    required this.color,
    required this.onTap,
  });

  final String room;
  final String description;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayName = _roomDisplayName(room);
    final changed = displayName != room;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                displayName.substring(0, 1),
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    changed ? '$room · $description' : description,
                    style: const TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.edit_rounded, color: _textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _SensorMetricCard extends StatelessWidget {
  const _SensorMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            style: const TextStyle(color: _textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SensorStatusCard extends StatelessWidget {
  const _SensorStatusCard({
    required this.name,
    required this.location,
    required this.strength,
    required this.online,
  });

  final String name;
  final String location;
  final String strength;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = online ? _success : _warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.wifi_rounded, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  location,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                online ? '정상' : '대기',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                strength,
                style: const TextStyle(color: _textMuted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniatureSizeButton extends StatelessWidget {
  const _MiniatureSizeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? _primary : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class GuardianManagementScreen extends StatefulWidget {
  const GuardianManagementScreen({super.key});

  @override
  State<GuardianManagementScreen> createState() =>
      _GuardianManagementScreenState();
}

class _GuardianManagementScreenState extends State<GuardianManagementScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(_refreshGuardians());
  }

  Future<void> _refreshGuardians() async {
    await _syncGuardiansFromServer();
    if (mounted) setState(() {});
  }

  Future<void> _openGuardianEditor({
    Guardian? guardian,
    String defaultRole = '1순위 보호자',
  }) async {
    final changed = await _showGuardianEditor(
      context,
      guardian: guardian,
      defaultRole: defaultRole,
    );
    if (changed && mounted) setState(() {});
  }

  Future<void> _deleteGuardian(Guardian guardian) async {
    final changed = await _confirmDeleteGuardian(context, guardian);
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    Guardian? careTarget;
    for (final guardian in AppState.guardians) {
      if (guardian.role.contains('보호 대상') || guardian.role.contains('어르신')) {
        careTarget = guardian;
        break;
      }
    }

    final target = careTarget;
    final contacts = AppState.guardians
        .where((guardian) => guardian.id != target?.id)
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '보호자·신고 정보',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '위험 상황이 생겼을 때 누구에게 먼저 알릴지 관리해요.',
                style: TextStyle(color: _textMuted, height: 1.4),
              ),
              const SizedBox(height: 22),
              const Text(
                '보호 대상',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              if (target != null)
                _GuardianCard(
                  guardian: target,
                  color: _primary,
                  icon: Icons.person_rounded,
                  onEdit: () => _openGuardianEditor(guardian: target),
                  onDelete: null,
                )
              else
                _EmptyGuardianCard(
                  title: '보호 대상 정보가 없어요',
                  buttonText: '보호 대상 추가',
                  onPressed: () =>
                      _openGuardianEditor(defaultRole: '보호 대상'),
                ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '긴급 연락 순서',
                      style: TextStyle(
                        color: _textMuted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openGuardianEditor(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('추가'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (contacts.isEmpty)
                _EmptyGuardianCard(
                  title: '등록된 보호자가 없어요',
                  buttonText: '보호자 추가하기',
                  onPressed: () => _openGuardianEditor(),
                )
              else
                ...contacts.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _GuardianCard(
                          guardian: entry.value,
                          order: entry.key + 1,
                          color: _success,
                          icon: Icons.supervisor_account_rounded,
                          onEdit: () =>
                              _openGuardianEditor(guardian: entry.value),
                          onDelete: () => _deleteGuardian(entry.value),
                        ),
                      ),
                    ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: _softCard(color: _dangerLight, radius: 24),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.local_police_rounded, color: _danger),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '119 신고 정보도 연결됐어요',
                            style: TextStyle(
                              color: _textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            '주소, 출입 안내, 의료 참고사항은 설정의 “집 주소와 출입 안내”에서 수정할 수 있어요.',
                            style: TextStyle(
                              color: _textMuted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuardianCard extends StatelessWidget {
  const _GuardianCard({
    required this.guardian,
    required this.color,
    required this.icon,
    required this.onEdit,
    required this.onDelete,
    this.order,
  });

  final Guardian guardian;
  final int? order;
  final Color color;
  final IconData icon;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 22),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: order == null
                ? Icon(icon, color: color)
                : Text(
                    '$order',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  guardian.name,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${guardian.role} · ${guardian.phone}',
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '수정',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
            color: _textMuted,
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '삭제',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: _danger,
            ),
        ],
      ),
    );
  }
}

class _EmptyGuardianCard extends StatelessWidget {
  const _EmptyGuardianCard({
    required this.title,
    required this.buttonText,
    required this.onPressed,
  });

  final String title;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.add_rounded),
            label: Text(buttonText),
          ),
        ],
      ),
    );
  }
}

class GuardianEditScreen extends StatefulWidget {
  const GuardianEditScreen({
    required this.defaultRole,
    this.guardian,
    super.key,
  });

  final Guardian? guardian;
  final String defaultRole;

  @override
  State<GuardianEditScreen> createState() => _GuardianEditScreenState();
}

class _GuardianEditScreenState extends State<GuardianEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _roleController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.guardian?.name ?? '');
    _phoneController = TextEditingController(
      text: widget.guardian?.phone ?? '',
    );
    _roleController = TextEditingController(
      text: widget.guardian?.role ?? widget.defaultRole,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop({
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'role': _roleController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.guardian != null;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(backgroundColor: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        editing ? '보호자 정보 수정' : '보호자 추가',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '위험 상황에서 바로 연락할 수 있도록 정확히 입력해 주세요.',
                  style: TextStyle(color: _textMuted, height: 1.4),
                ),
                const SizedBox(height: 24),
                _GuardianTextField(
                  controller: _nameController,
                  label: '이름',
                  hint: '예: 김주환 보호자',
                  icon: Icons.person_rounded,
                  validatorMessage: '이름을 입력해 주세요',
                ),
                const SizedBox(height: 14),
                _GuardianTextField(
                  controller: _phoneController,
                  label: '전화번호',
                  hint: '예: 010-1234-5678',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                  validatorMessage: '전화번호를 입력해 주세요',
                ),
                const SizedBox(height: 14),
                _GuardianTextField(
                  controller: _roleController,
                  label: '역할',
                  hint: '예: 1순위 보호자, 보호 대상',
                  icon: Icons.badge_rounded,
                  validatorMessage: '역할을 입력해 주세요',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(editing ? '수정 완료' : '추가하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class EmergencyInfoEditScreen extends StatefulWidget {
  const EmergencyInfoEditScreen({super.key});

  @override
  State<EmergencyInfoEditScreen> createState() =>
      _EmergencyInfoEditScreenState();
}

class _EmergencyInfoEditScreenState extends State<EmergencyInfoEditScreen> {
  final _addressController = TextEditingController();
  final _accessController = TextEditingController();
  final _passwordController = TextEditingController();
  final _medicalController = TextEditingController();
  final _hospitalController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _fill(AppState.emergencyInfo);
  }

  Future<void> _load() async {
    await _syncEmergencyInfoFromServer();
    if (mounted) _fill(AppState.emergencyInfo);
  }

  void _fill(EmergencyInfo info) {
    _addressController.text = info.address;
    _accessController.text = info.accessNote;
    _passwordController.text = info.doorPassword;
    _medicalController.text = info.medicalNote;
    _hospitalController.text = info.hospital;
  }

  @override
  void dispose() {
    _addressController.dispose();
    _accessController.dispose();
    _passwordController.dispose();
    _medicalController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final info = EmergencyInfo(
      address: _addressController.text.trim(),
      accessNote: _accessController.text.trim(),
      doorPassword: _passwordController.text.trim(),
      medicalNote: _medicalController.text.trim(),
      hospital: _hospitalController.text.trim(),
    );

    final response = await ApiService.post('/emergency-info', info.toJson());

    if (!mounted) return;
    setState(() => _saving = false);
    if (response == null) {
      _showTodoSnack(context, '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
      return;
    }

    _applyServerState(response);
    _showTodoSnack(context, '119 신고 정보를 저장했어요.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '집 주소와 출입 안내',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '긴급 상황에서 보호자나 119가 바로 확인해야 하는 정보를 적어둬요.',
                style: TextStyle(color: _textMuted, height: 1.4),
              ),
              const SizedBox(height: 24),
              _GuardianTextField(
                controller: _addressController,
                label: '집 주소',
                hint: '예: 경기도 수원시 ○○구 ○○로 123',
                icon: Icons.home_rounded,
                validatorMessage: '주소를 입력해 주세요',
              ),
              const SizedBox(height: 14),
              _GuardianTextField(
                controller: _accessController,
                label: '출입 안내',
                hint: '예: 공동현관 호출 후 보호자에게 연락',
                icon: Icons.meeting_room_rounded,
                validatorMessage: '출입 안내를 입력해 주세요',
              ),
              const SizedBox(height: 14),
              _GuardianTextField(
                controller: _passwordController,
                label: '공동현관/도어락 참고',
                hint: '선택 입력 · 실제 비밀번호 저장은 주의',
                icon: Icons.lock_rounded,
                validatorMessage: '없으면 공란으로 둬도 돼요',
                requiredField: false,
              ),
              const SizedBox(height: 14),
              _GuardianTextField(
                controller: _medicalController,
                label: '의료 참고사항',
                hint: '예: 고혈압 약 복용 중',
                icon: Icons.medical_information_rounded,
                validatorMessage: '의료 참고사항을 입력해 주세요',
              ),
              const SizedBox(height: 14),
              _GuardianTextField(
                controller: _hospitalController,
                label: '가까운 병원/응급실',
                hint: '예: 아주대학교병원',
                icon: Icons.local_hospital_rounded,
                validatorMessage: '병원 정보를 입력해 주세요',
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _softCard(color: _warningLight, radius: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.privacy_tip_rounded, color: _warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _kDemoMode
                            ? '발표용 저장 정보입니다. 실제 서비스에서는 공동현관/도어락 정보를 암호화하고 보호자 권한을 분리해야 해요.'
                            : '공동현관/도어락 정보는 민감한 정보예요. 신뢰할 수 있는 보호자에게만 공유되도록 관리해 주세요.',
                        style: const TextStyle(
                          color: _textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(_saving ? '저장 중...' : '저장하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyManagementScreen extends StatelessWidget {
  const PrivacyManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final retentionDays = AppState.settingInt('alertRetentionDays', 30);

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SubPageHeader(
                    title: '개인정보 및 기록 보관',
                    subtitle: '민감한 신고 정보와 알림 기록을 보호자 기준으로 관리해요.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: _softCard(color: _primaryLight, radius: 24),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '보호자에게 필요한 만큼만 보여줘요',
                                style: TextStyle(
                                  color: _textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                '주소, 도어락, 의료 참고사항은 위급 상황에 도움이 되지만 민감한 정보라 표시 범위를 조절할 수 있어요.',
                                style: TextStyle(
                                  color: _textMuted,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '알림 기록 보관',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: _softCard(radius: 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '기록 보관 기간',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '위험 알림과 확인 기록을 어느 정도 기간 동안 참고할지 정해요.',
                          style: TextStyle(color: _textMuted, height: 1.35),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _RetentionChoiceButton(
                                label: '7일',
                                selected: retentionDays == 7,
                                onTap: () =>
                                    _saveRetentionDays(context, 7),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _RetentionChoiceButton(
                                label: '30일',
                                selected: retentionDays == 30,
                                onTap: () =>
                                    _saveRetentionDays(context, 30),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _RetentionChoiceButton(
                                label: '90일',
                                selected: retentionDays == 90,
                                onTap: () =>
                                    _saveRetentionDays(context, 90),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '민감정보 표시',
                    style: TextStyle(
                      color: _textMuted,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingGroup(
                    children: [
                      _SwitchTile(
                        title: '신고 문장 복사 허용',
                        subtitle: '주소와 출입 안내를 클립보드에 복사할 수 있어요',
                        settingKey: 'allowClipboardCopy',
                        value: AppState.settingBool('allowClipboardCopy', true),
                      ),
                      _SwitchTile(
                        title: '도어락 참고 표시',
                        subtitle: '긴급 화면과 신고 문장에 도어락 참고를 포함해요',
                        settingKey: 'showDoorPasswordInEmergency',
                        value: AppState.settingBool(
                          'showDoorPasswordInEmergency',
                          true,
                        ),
                      ),
                      _SwitchTile(
                        title: '의료 참고사항 표시',
                        subtitle: '119 신고 정보에 의료 참고사항을 함께 보여줘요',
                        settingKey: 'shareMedicalInfoInEmergency',
                        value: AppState.settingBool(
                          'shareMedicalInfoInEmergency',
                          true,
                        ),
                      ),
                      _SwitchTile(
                        title: '민감정보 보호자 전용',
                        subtitle: '실제 서비스에서 보호자 권한 확인이 필요한 항목이에요',
                        settingKey: 'guardianOnlySensitiveInfo',
                        value: AppState.settingBool(
                          'guardianOnlySensitiveInfo',
                          true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _softCard(color: _warningLight, radius: 20),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_rounded, color: _warning),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '현재는 발표용/개발용 저장 방식이에요. 실제 서비스에서는 암호화 저장, 보호자 권한 확인, 기록 자동 삭제 정책을 서버에서 강제해야 해요.',
                            style: TextStyle(color: _textMuted, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RetentionChoiceButton extends StatelessWidget {
  const _RetentionChoiceButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _primary : _bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? _primary : _border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : _textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _GuardianTextField extends StatelessWidget {
  const _GuardianTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validatorMessage,
    this.keyboardType,
    this.requiredField = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String validatorMessage;
  final TextInputType? keyboardType;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: _primary),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
      ),
      validator: (value) {
        if (!requiredField) return null;
        return value == null || value.trim().isEmpty ? validatorMessage : null;
      },
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _softCard(radius: 22),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, indent: 58, color: _border),
          ],
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _textMuted),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatefulWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.settingKey,
    required this.value,
    this.trailingText,
  });

  final String title;
  final String subtitle;
  final String settingKey;
  final bool value;
  final String? trailingText;

  @override
  State<_SwitchTile> createState() => _SwitchTileState();
}

class _SwitchTileState extends State<_SwitchTile> {
  late bool _value = widget.value;

  @override
  void didUpdateWidget(covariant _SwitchTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (widget.trailingText != null) ...[
            Text(
              widget.trailingText!,
              style: const TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Switch(
            value: _value,
            activeThumbColor: _primary,
            onChanged: (value) {
              setState(() => _value = value);
              AppState.settings[widget.settingKey] = value;
              WsService.instance.notify();
              unawaited(_saveSettingToServer(widget.settingKey, value, context));
            },
          ),
        ],
      ),
    );
  }
}

void _openEmergency(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
}

void _showTodoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _refreshServerHealth(BuildContext context) async {
  final result = await ApiService.get('/health');
  if (!context.mounted) return;

  if (result == null) {
    AppState.serverConnected = false;
    AppState.connectionMessage = '상태를 다시 확인하는 중이에요';
    WsService.instance.notify();
    _showTodoSnack(context, '지금은 상태 확인이 지연되고 있어요.');
    return;
  }

  AppState.serverConnected = true;
  AppState.connectionMessage = '최근 상태 확인 완료';
  WsService.instance.notify();
  _showTodoSnack(context, '안심 상태가 정상적으로 확인됐어요.');
}

Future<void> _saveMiniatureSize(BuildContext context, String size) async {
  AppState.settings['miniatureSize'] = size;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {'miniatureSize': size});
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '표시 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, '미니어처 크기를 저장했어요.');
}

Future<bool> _showGuardianEditor(
  BuildContext context, {
  Guardian? guardian,
  String defaultRole = '1순위 보호자',
}) async {
  final result = await Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => GuardianEditScreen(
        guardian: guardian,
        defaultRole: defaultRole,
      ),
    ),
  );

  if (result == null || !context.mounted) return false;

  final body = <String, dynamic>{
    'name': result['name'],
    'phone': result['phone'],
    'role': result['role'],
  };
  if (guardian != null) body['id'] = guardian.id;

  final response = await ApiService.post(
    guardian == null ? '/guardians' : '/guardians/update',
    body,
  );

  if (!context.mounted) return false;
  if (response == null) {
    _showTodoSnack(context, '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return false;
  }

  _applyServerState(response);
  _showTodoSnack(context, guardian == null ? '보호자를 추가했어요.' : '보호자 정보를 수정했어요.');
  return true;
}

Future<bool> _confirmDeleteGuardian(
  BuildContext context,
  Guardian guardian,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('보호자 삭제'),
        content: Text('${guardian.name} 정보를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('삭제'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return false;

  final response = await ApiService.post('/guardians/delete', {
    'id': guardian.id,
  });

  if (!context.mounted) return false;
  if (response == null) {
    _showTodoSnack(context, '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return false;
  }

  _applyServerState(response);
  WsService.instance.notify();
  _showTodoSnack(context, '보호자 정보를 삭제했어요.');
  return true;
}

Future<void> _triggerDangerScenario(BuildContext context) async {
  if (!_kDemoMode) {
    _showTodoSnack(context, '발표 모드에서만 사용할 수 있는 기능이에요.');
    return;
  }

  final result = await ApiService.post('/scenario', {
    'status': 'danger',
    'seconds': 18,
  });

  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '발표 상태를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  final location = result['location'];
  if (location is Map) {
    _applyLocationFromServer(Map<String, dynamic>.from(location));
  } else {
    AppState.status = 'danger';
    AppState.pose = 'lying';
    AppState.room = '거실';
  }
  AppState.alerts.insert(
    0,
    AlertItem(
      type: 'danger',
      title: '발표용 낙상 의심 상황',
      message: '발표용으로 위험 상황을 발생시켰어요.',
      time: _formatTime(DateTime.now()),
      room: AppState.room,
      urgent: true,
    ),
  );
  unawaited(_syncAlertsFromServer());
  WsService.instance.notify();

  _showTodoSnack(context, '발표용 위험 상황을 발생시켰어요.');
  _openEmergency(context);
}

Guardian? _careTarget() {
  for (final guardian in AppState.guardians) {
    if (guardian.role.contains('보호 대상') || guardian.name.contains('어르신')) {
      return guardian;
    }
  }
  return AppState.guardians.isEmpty ? null : AppState.guardians.first;
}

Guardian? _primaryGuardian() {
  for (final guardian in AppState.guardians) {
    final isCareTarget =
        guardian.role.contains('보호 대상') || guardian.name.contains('어르신');
    if (!isCareTarget && guardian.role.contains('보호자')) {
      return guardian;
    }
  }

  if (AppState.guardians.length > 1) return AppState.guardians[1];
  return AppState.guardians.isEmpty ? null : AppState.guardians.first;
}

String _phoneForDial(String phone) {
  return phone.replaceAll(RegExp(r'[^0-9+]'), '');
}

String _buildEmergencySummary() {
  final target = _careTarget()?.name ?? '보호 대상';
  final info = AppState.emergencyInfo;
  final status = _statusInfo(AppState.status);
  final includeDoorPassword = AppState.settingBool(
    'showDoorPasswordInEmergency',
    true,
  );
  final includeMedicalInfo = AppState.settingBool(
    'shareMedicalInfoInEmergency',
    true,
  );

  final lines = [
    '[한이음 안전 알림]',
    '$target에게 빠른 확인이 필요합니다.',
    '',
    '상태: ${status.title}',
    '감지 내용: ${_emergencyEventMessage()}',
    '감지 위치: ${_roomDisplayName(AppState.room)}',
    '현재 자세: ${_poseLabel(AppState.pose)} 상태',
    '감지 확실성: ${_certaintyLabel()}',
    '확인 시각: ${_formatTime(DateTime.now())}',
    '',
    '집 주소: ${info.address}',
    '출입 안내: ${info.accessNote}',
    if (includeDoorPassword && info.doorPassword.trim().isNotEmpty)
      '도어락 참고: ${info.doorPassword}',
    if (includeMedicalInfo) '의료 참고사항: ${info.medicalNote}',
    '가까운 병원: ${info.hospital}',
  ];

  return lines.join('\n');
}

Future<void> _openNativeAction(
  BuildContext context, {
  required String method,
  required Map<String, String> arguments,
  required String successMessage,
  required String fallbackMessage,
}) async {
  try {
    final opened = await _emergencyChannel.invokeMethod<bool>(
      method,
      arguments,
    );
    if (!context.mounted) return;

    if (opened == true) {
      _showTodoSnack(context, successMessage);
    } else {
      _showTodoSnack(context, fallbackMessage);
    }
  } on MissingPluginException {
    if (!context.mounted) return;
    _showTodoSnack(context, '현재 실행 환경에서는 전화/문자 앱을 직접 열 수 없어요.');
  } on PlatformException catch (error) {
    if (!context.mounted) return;
    _showTodoSnack(context, error.message ?? fallbackMessage);
  } catch (_) {
    if (!context.mounted) return;
    _showTodoSnack(context, fallbackMessage);
  }
}

Future<void> _callCareTarget(BuildContext context) async {
  final target = _careTarget();
  final phone = _phoneForDial(target?.phone ?? '');
  if (target == null || phone.isEmpty) {
    _showTodoSnack(context, '설정에서 보호 대상 연락처를 먼저 입력해 주세요.');
    return;
  }

  await _openNativeAction(
    context,
    method: 'dial',
    arguments: {'phone': phone},
    successMessage: '${target.name} 전화 화면을 열었어요.',
    fallbackMessage: '전화 앱을 열 수 없어요. 연락처: ${target.phone}',
  );
}

Future<void> _dial119(BuildContext context) async {
  await Clipboard.setData(ClipboardData(text: _buildEmergencySummary()));

  if (!context.mounted) return;
  await _openNativeAction(
    context,
    method: 'dial',
    arguments: {'phone': '119'},
    successMessage: '119 전화 화면을 열었어요. 신고 문장도 복사했어요.',
    fallbackMessage: '전화 앱을 열 수 없어요. 신고 문장은 복사해뒀어요.',
  );
}

Future<void> _sendEmergencySms(BuildContext context) async {
  final guardian = _primaryGuardian();
  final phone = _phoneForDial(guardian?.phone ?? '');
  if (guardian == null || phone.isEmpty) {
    _showTodoSnack(context, '설정에서 1순위 보호자 연락처를 먼저 입력해 주세요.');
    return;
  }

  await _openNativeAction(
    context,
    method: 'sms',
    arguments: {'phone': phone, 'message': _buildEmergencySummary()},
    successMessage: '${guardian.name}에게 보낼 문자 초안을 열었어요.',
    fallbackMessage: '문자 앱을 열 수 없어요. 보호자 연락처: ${guardian.phone}',
  );
}

Future<void> _copyEmergencySummary(BuildContext context) async {
  if (!AppState.settingBool('allowClipboardCopy', true)) {
    _showTodoSnack(context, '개인정보 보호 설정으로 문장 복사가 꺼져 있어요.');
    return;
  }

  await Clipboard.setData(ClipboardData(text: _buildEmergencySummary()));
  if (!context.mounted) return;
  _showTodoSnack(context, '119 신고 문장을 복사했어요.');
}

Future<void> _copyAlertSummary(BuildContext context, AlertItem alert) async {
  if (!AppState.settingBool('allowClipboardCopy', true)) {
    _showTodoSnack(context, '개인정보 보호 설정으로 알림 복사가 꺼져 있어요.');
    return;
  }

  final text = [
    '[한이음 안전 알림]',
    alert.title,
    '',
    '내용: ${alert.message}',
    '감지 근거: ${_alertReason(alert)}',
    '보호자 안내: ${_guardianMeaning(alert)}',
    '감지 위치: ${_roomDisplayName(alert.room)}',
    '감지 시각: ${alert.time}',
    '현재 위치: ${_roomDisplayName(AppState.room)}',
    '현재 자세: ${_poseLabel(AppState.pose)} 상태',
    '감지 확실성: ${_certaintyLabel()}',
    '',
    '집 주소: ${AppState.emergencyInfo.address}',
    '출입 안내: ${AppState.emergencyInfo.accessNote}',
  ].join('\n');

  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  _showTodoSnack(context, '알림 내용을 복사했어요.');
}

Future<void> _confirmSafe(BuildContext context) async {
  final result = await ApiService.post('/alerts/resolve');

  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '확인 완료 처리에 실패했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  AppState.status = 'normal';
  AppState.pose = 'standing';
  _applyServerState(result);
  WsService.instance.notify();

  Navigator.of(context).maybePop();
  _showTodoSnack(context, '위험 알림을 확인 완료로 처리했어요.');
}

Future<void> _editRoomLabel(BuildContext context, String room) async {
  final controller = TextEditingController(text: _roomDisplayName(room));
  final nextName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('$room 이름 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '예: 안방, 작은방, 현관 앞',
            helperText: '도면과 알림 문구에 표시될 이름이에요.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onSubmitted: (_) {
            Navigator.of(dialogContext).pop(controller.text.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('저장'),
          ),
        ],
      );
    },
  );
  controller.dispose();

  if (nextName == null || !context.mounted) return;

  final labels = _roomLabelsForDisplay();
  labels[room] = nextName.isEmpty ? room : nextName;
  await _saveRoomLabels(context, labels, successMessage: '$room 이름을 저장했어요.');
}

Future<void> _resetRoomLabels(BuildContext context) async {
  final labels = {for (final room in _roomOrder) room: room};
  await _saveRoomLabels(context, labels, successMessage: '기본 방 이름으로 되돌렸어요.');
}

Future<void> _saveRoomLabels(
  BuildContext context,
  Map<String, String> labels, {
  required String successMessage,
}) async {
  AppState.settings['roomLabels'] = labels;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {'roomLabels': labels});
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '방 이름을 서버에 저장하지 못했어요. 화면에는 임시 반영됐어요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, successMessage);
}

Future<void> _saveRetentionDays(BuildContext context, int days) async {
  AppState.settings['alertRetentionDays'] = days;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {
    'alertRetentionDays': days,
  });
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '보관 기간을 서버에 저장하지 못했어요. 화면에는 임시 반영됐어요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, '알림 기록 보관 기간을 ${days}일로 저장했어요.');
}

Future<void> _saveSettingToServer(
  String key,
  dynamic value,
  BuildContext context,
) async {
  final result = await ApiService.post('/settings', {key: value});
  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
}
