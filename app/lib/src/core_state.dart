part of '../main.dart';

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
