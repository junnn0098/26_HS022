import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../app/app_config.dart';
import '../models/safety_models.dart';
import '../services/safety_repository.dart';

class SafetyController extends ChangeNotifier {
  SafetyController(this.repository);

  final SafetyRepository repository;

  SafetySnapshot _snapshot = SafetySnapshot.initial();
  SafetySnapshot get snapshot => _snapshot;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _locationPollTimer;
  Timer? _healthPollTimer;
  Timer? _reconnectTimer;

  bool _started = false;
  bool _pollingLocation = false;
  bool _socketConnected = false;
  String _lastLocationSignature = '';
  int _reconnectSeconds = 1;
  DateTime _lastServerSeen = DateTime.fromMillisecondsSinceEpoch(0);

  void start() {
    if (_started) return;
    _started = true;
    unawaited(refreshAll());
    _connectSocket();
    _startHealthPolling();
    _startLocationPolling();
  }

  Future<void> refreshAll() async {
    final data = await repository.state();
    if (data == null) {
      _setConnection(false, '최근 상태를 다시 확인 중');
      return;
    }

    _markServerSeen('방금 상태를 확인했어요');
    _applyState(data);
  }

  Future<void> refreshAlerts() async {
    final data = await repository.alerts();
    if (data == null) return;
    _applyState(data);
  }

  Future<void> markSafe() async {
    await repository.resolveAlerts();
    final safeRoom = _snapshot.room;
    final alerts = [
      AlertEvent.fromStatus(SafetyStatus.normal, room: safeRoom),
      ..._snapshot.alerts.where((alert) => alert.status != SafetyStatus.normal),
    ].take(20).toList();
    _snapshot = _snapshot.copyWith(
      status: SafetyStatus.normal,
      pose: 'standing',
      alerts: alerts,
      connectionNote: '보호자가 안전을 확인했어요',
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
    unawaited(refreshAll());
  }

  Future<void> notifyCareRecipientSafe() async {
    final safeRoom = _snapshot.room;
    await repository.notifyCareRecipientSafe(room: safeRoom);
    final alerts = [
      AlertEvent.fromStatus(SafetyStatus.normal, room: safeRoom),
      ..._snapshot.alerts.where((alert) => alert.status != SafetyStatus.normal),
    ].take(20).toList();
    _snapshot = _snapshot.copyWith(
      status: SafetyStatus.normal,
      pose: 'standing',
      alerts: alerts,
      connectionNote: '괜찮다고 보호자에게 알렸어요',
      lastUpdated: DateTime.now(),
    );
    notifyListeners();
    unawaited(refreshAll());
  }

  Future<void> triggerScenario(SafetyStatus status) async {
    final preset = _scenarioPreset(status);
    final result = await repository.triggerScenario(
      status: safetyStatusToServer(status),
      x: preset.$1,
      y: preset.$2,
      room: preset.$3,
      seconds: 30,
    );
    final location = result?['location'];
    if (location is Map) {
      _applyLocation(Map<String, dynamic>.from(location), notifyAlways: true);
    } else {
      _applyLocation({
        'status': safetyStatusToServer(status),
        'x': preset.$1,
        'y': preset.$2,
        'room': preset.$3,
      }, notifyAlways: true);
    }
  }

  Future<void> updateSetting(String key, Object? value) async {
    final nextSettings = Map<String, dynamic>.from(_snapshot.settings);
    nextSettings[key] = value;
    _snapshot = _snapshot.copyWith(
      settings: nextSettings,
      locationSharingEnabled: key == 'locationSharingEnabled' && value is bool
          ? value
          : _snapshot.locationSharingEnabled,
    );
    notifyListeners();
    await repository.updateSetting(key, value);
  }

  void _connectSocket() {
    if (_socketConnected) return;
    _socketConnected = true;

    try {
      _channel = repository.openLocationSocket();
      _wsSubscription = _channel!.stream.listen(
        _handleSocketData,
        onDone: () => _scheduleReconnect('실시간 확인이 잠시 멈췄어요'),
        onError: (_) => _scheduleReconnect('실시간 확인을 다시 연결하는 중'),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect('실시간 확인을 다시 연결하는 중');
    }
  }

  void _handleSocketData(dynamic raw) {
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      _markServerSeen('생활 상태를 바로 받고 있어요');
      _reconnectSeconds = 1;
      _applyLocation(map);
    } catch (_) {
      // 잘못 들어온 일시 데이터는 무시하고 다음 데이터를 기다린다.
    }
  }

  void _scheduleReconnect(String note) {
    _socketConnected = false;
    try {
      _wsSubscription?.cancel();
      _channel?.sink.close();
    } catch (_) {
      // 이미 닫힌 경우는 무시한다.
    }
    _wsSubscription = null;
    _channel = null;

    _setConnection(false, note);
    final delay = _reconnectSeconds;
    _reconnectSeconds = (_reconnectSeconds * 2).clamp(1, 8).toInt();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delay), _connectSocket);
  }

  void _startHealthPolling() {
    _healthPollTimer ??= Timer.periodic(AppConfig.healthPollInterval, (_) {
      unawaited(_pollHealth());
    });
    unawaited(_pollHealth());
  }

  Future<void> _pollHealth() async {
    final result = await repository.health();
    if (result == null) {
      _markDisconnectedIfStale();
      return;
    }
    _markServerSeen('방금 상태를 확인했어요');
  }

  void _startLocationPolling() {
    _locationPollTimer ??= Timer.periodic(AppConfig.locationPollInterval, (_) {
      unawaited(_pollLatestLocation());
    });
    unawaited(_pollLatestLocation());
  }

  Future<void> _pollLatestLocation() async {
    if (_pollingLocation) return;
    _pollingLocation = true;
    try {
      final result = await repository.latestLocation();
      final location = result?['location'];
      if (location is! Map) {
        _markDisconnectedIfStale();
        return;
      }

      _markServerSeen('방금 위치를 확인했어요');
      _applyLocation(Map<String, dynamic>.from(location));
    } finally {
      _pollingLocation = false;
    }
  }

  void _applyState(Map<String, dynamic> data) {
    var next = _snapshot;

    final settings = data['settings'];
    if (settings is Map) {
      final parsedSettings = Map<String, dynamic>.from(settings);
      next = next.copyWith(
        settings: parsedSettings,
        locationSharingEnabled:
            parsedSettings['locationSharingEnabled'] is bool
                ? parsedSettings['locationSharingEnabled'] as bool
                : next.locationSharingEnabled,
      );
    }

    final guardians = data['guardians'];
    if (guardians is List) {
      final parsed = guardians
          .whereType<Map>()
          .map((item) => Guardian.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      if (parsed.isNotEmpty) next = next.copyWith(guardians: parsed);
    }

    final emergencyInfo = data['emergencyInfo'];
    if (emergencyInfo is Map) {
      next = next.copyWith(
        emergencyInfo: EmergencyInfo.fromJson(
          Map<String, dynamic>.from(emergencyInfo),
        ),
      );
    }

    final alerts = data['alerts'];
    if (alerts is List) {
      final parsed = alerts
          .whereType<Map>()
          .map((item) => AlertEvent.fromJson(Map<String, dynamic>.from(item)))
          .take(40)
          .toList();
      if (parsed.isNotEmpty) next = next.copyWith(alerts: parsed);
    }

    _snapshot = next;
    final location = data['location'];
    if (location is Map) {
      _applyLocation(Map<String, dynamic>.from(location), notifyAlways: true);
    } else {
      notifyListeners();
    }
  }

  void _applyLocation(Map<String, dynamic> map, {bool notifyAlways = false}) {
    final locationSharingEnabled = map['locationSharingEnabled'] is bool
        ? map['locationSharingEnabled'] as bool
        : _snapshot.locationSharingEnabled;
    final x = normalizedDouble(map['x'], _snapshot.x);
    final y = normalizedDouble(map['y'], _snapshot.y);
    final status = safetyStatusFrom(map['status']);
    final room = locationSharingEnabled
        ? RoomResolver.normalize(map['room'], x, y)
        : cleanText(map['room'], '위치 공유 꺼짐');
    final pose = cleanText(map['pose'], poseFromStatus(status));
    final confidence = normalizedDouble(
      map['confidence'],
      _snapshot.confidence,
    );
    final signature =
        '${x.toStringAsFixed(3)}|${y.toStringAsFixed(3)}|$status|$room|$pose|${confidence.toStringAsFixed(2)}|$locationSharingEnabled';

    if (!notifyAlways && signature == _lastLocationSignature) return;
    _lastLocationSignature = signature;

    final path = [..._snapshot.movementPath];
    final nextPoint = Offset(x, y);
    if (path.isEmpty || (path.last - nextPoint).distance > 0.006) {
      path.add(nextPoint);
    }
    while (path.length > 32) {
      path.removeAt(0);
    }

    var alerts = _snapshot.alerts;
    if (status != SafetyStatus.normal) {
      final liveAlert = AlertEvent.fromStatus(status, room: room);
      alerts = [
        liveAlert,
        ...alerts.where((alert) => alert.status != status),
      ].take(40).toList();
    }

    _snapshot = _snapshot.copyWith(
      status: status,
      room: room,
      pose: pose,
      x: x,
      y: y,
      confidence: confidence,
      locationSharingEnabled: locationSharingEnabled,
      lastUpdated: DateTime.now(),
      movementPath: path,
      alerts: alerts,
      serverConnected: true,
    );
    notifyListeners();
  }

  void _markServerSeen(String note) {
    _lastServerSeen = DateTime.now();
    if (!_snapshot.serverConnected || _snapshot.connectionNote != note) {
      _snapshot = _snapshot.copyWith(
        serverConnected: true,
        connectionNote: note,
      );
      notifyListeners();
    }
  }

  void _markDisconnectedIfStale() {
    if (DateTime.now().difference(_lastServerSeen) <
        const Duration(seconds: 8)) {
      return;
    }
    _setConnection(false, '최근 상태를 다시 확인 중');
  }

  void _setConnection(bool connected, String note) {
    if (_snapshot.serverConnected == connected &&
        _snapshot.connectionNote == note) {
      return;
    }
    _snapshot = _snapshot.copyWith(
      serverConnected: connected,
      connectionNote: note,
    );
    notifyListeners();
  }

  (double, double, String) _scenarioPreset(SafetyStatus status) {
    return switch (status) {
      SafetyStatus.normal => (0.35, 0.45, RoomResolver.living),
      SafetyStatus.out => (0.76, 0.66, RoomResolver.entrance),
      SafetyStatus.still => (0.31, 0.68, RoomResolver.bedroom),
      SafetyStatus.danger => (0.78, 0.70, RoomResolver.entrance),
    };
  }

  @override
  void dispose() {
    _locationPollTimer?.cancel();
    _healthPollTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {
      // 이미 닫힌 경우는 무시한다.
    }
    repository.close();
    super.dispose();
  }
}
