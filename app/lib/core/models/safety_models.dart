import 'dart:ui';

// unknown: 엣지 모델을 쓸 수 없거나 입력이 오래되어 판단하지 못한 상태.
// 정상(normal)으로도, 위험(danger)으로도 보여주지 않는다.
enum SafetyStatus { normal, out, still, danger, unknown }

SafetyStatus safetyStatusFrom(dynamic value) {
  final raw = value?.toString().toLowerCase().trim();
  return switch (raw) {
    'normal' => SafetyStatus.normal,
    'danger' || 'fall' || 'fallen' || 'lying' => SafetyStatus.danger,
    'out' || 'exit' || 'intrusion' || 'entrance' => SafetyStatus.out,
    'still' || 'inactive' || 'sitting' || 'no_motion' => SafetyStatus.still,
    // 'unknown', 'model_unavailable', 'stale', 누락·미지원 값은 모두 판단 불가로 본다.
    _ => SafetyStatus.unknown,
  };
}

String safetyStatusToServer(SafetyStatus status) {
  return switch (status) {
    SafetyStatus.normal => 'normal',
    SafetyStatus.out => 'out',
    SafetyStatus.still => 'still',
    SafetyStatus.danger => 'danger',
    SafetyStatus.unknown => 'unknown',
  };
}

class RoomResolver {
  const RoomResolver._();

  static const bedroom2 = '침실-2';
  static const kitchen = '주방';
  static const living = '거실';
  static const bathroom = '욕실';
  static const bedroom = '침실-1';
  static const entrance = '현관';
  static const unknown = '확인 필요';

  static const all = [bedroom2, kitchen, living, bathroom, bedroom, entrance];

  static String normalize(dynamic raw, double x, double y) {
    final value = raw?.toString().trim();
    if (value == null || looksBrokenText(value)) return fromPosition(x, y);
    if (all.contains(value)) return value;

    if (value.contains('거실')) return living;
    if (value.contains('주방')) return kitchen;
    if (value.contains('욕실') || value.contains('화장실')) return bathroom;
    if (value.contains('현관')) return entrance;
    if (value.contains('침실-2')) return bedroom2;
    if (value.contains('침실') || value.contains('방')) return bedroom;

    return fromPosition(x, y);
  }

  static String fromPosition(double x, double y) {
    // 기준 도면: 일반 가정집형 실내측위 도면.
    // ESP32-1을 좌상단 원점으로 보고, 앱은 0.0~1.0 정규화 좌표를 사용한다.
    if (x < 0.50 && y < 0.39) return bedroom2;
    if (x >= 0.50 && y < 0.255) return kitchen;
    if (x < 0.50 && y < 0.565) return living;
    if (x >= 0.50 && x < 0.72 && y < 0.565) return bathroom;
    if (x < 0.50 && y >= 0.565) return bedroom;
    return entrance;
  }
}

bool looksBrokenText(String? value) {
  if (value == null) return true;
  final text = value.trim();
  if (text.isEmpty) return true;
  const brokenFragments = [
    '�',
    '蹂',
    '媛',
    '곹',
    '꾩',
    '뚮',
    '섏',
    '쨌',
    '吏',
    '湲',
    '嫄',
    '鍮',
    '遺',
    '묎',
    '대Ⅴ',
    '???',
  ];
  return brokenFragments.any(text.contains);
}

String cleanText(dynamic value, String fallback) {
  final text = value?.toString().trim();
  if (looksBrokenText(text)) return fallback;
  return text!;
}

double boundedDouble(dynamic value, double fallback, {double min = 0.0, double max = 1.0}) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
  return (parsed ?? fallback).clamp(min, max).toDouble();
}

double normalizedDouble(dynamic value, double fallback) => boundedDouble(value, fallback);

double? optionalBoundedDouble(dynamic value, {double min = 0.0, double max = 1.0}) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
  final clamped = parsed?.clamp(min, max);
  return clamped?.toDouble();
}

/// 서버가 보낸 호흡수를 읽는다. 값이 없거나 `breathingEstimated: true`(측정값이 아님)이면
/// null을 돌려주고, 화면에서는 숫자 대신 '측정 대기'로 보여준다.
double? measuredBreathingRate(Map<String, dynamic> json) {
  if (json['breathingEstimated'] == true) return null;
  return optionalBoundedDouble(
    json['breathingRate'] ?? json['respirationRate'] ?? json['breathRate'],
    min: 6,
    max: 36,
  );
}

class Guardian {
  const Guardian({required this.id, required this.name, required this.phone, required this.role});

  factory Guardian.fromJson(Map<String, dynamic> json) {
    final id = switch (json['id']) {
      num number => number.toInt(),
      String text => int.tryParse(text) ?? 0,
      _ => 0,
    };

    return Guardian(
      id: id,
      name: cleanText(json['name'], id == 1 ? '김영희 어르신' : '홍길동 보호자'),
      phone: cleanText(json['phone'], id == 1 ? '010-0000-0000' : '010-1234-5678'),
      role: cleanText(json['role'], id == 1 ? '피보호자' : '1순위 보호자'),
    );
  }

  final int id;
  final String name;
  final String phone;
  final String role;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone, 'role': role};
}

class EmergencyInfo {
  const EmergencyInfo({
    required this.address,
    required this.accessNote,
    required this.medicalNote,
    required this.hospital,
  });

  factory EmergencyInfo.fromJson(Map<String, dynamic> json) {
    return EmergencyInfo(
      address: cleanText(json['address'], defaultInfo.address),
      accessNote: cleanText(json['accessNote'], defaultInfo.accessNote),
      medicalNote: cleanText(json['medicalNote'], defaultInfo.medicalNote),
      hospital: cleanText(json['hospital'], defaultInfo.hospital),
    );
  }

  static const defaultInfo = EmergencyInfo(
    address: '우리집',
    accessNote: '공동현관 호출 후 보호자에게 연락해 주세요.',
    medicalNote: '고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.',
    hospital: '가까운 응급실: ○○병원 응급실',
  );

  final String address;
  final String accessNote;
  final String medicalNote;
  final String hospital;

  Map<String, dynamic> toJson() => {
    'address': address,
    'accessNote': accessNote,
    'medicalNote': medicalNote,
    'hospital': hospital,
  };
}

class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.status,
    required this.title,
    required this.message,
    required this.time,
    required this.room,
    required this.urgent,
    required this.resolved,
  });

  factory AlertEvent.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString().toLowerCase();
    final status = switch (rawType) {
      'danger' || 'fall' => SafetyStatus.danger,
      'warning' || 'out' => SafetyStatus.out,
      'still' => SafetyStatus.still,
      'unknown' => SafetyStatus.unknown,
      _ => SafetyStatus.normal,
    };
    final rawRoom = cleanText(json['room'], RoomResolver.unknown);
    final room = RoomResolver.all.contains(rawRoom) ? rawRoom : RoomResolver.unknown;
    final fallback = AlertEvent.fromStatus(status, room: room);

    return AlertEvent(
      id: switch (json['id']) {
        num number => number.toInt(),
        String text => int.tryParse(text) ?? fallback.id,
        _ => fallback.id,
      },
      status: status,
      title: cleanText(json['title'], fallback.title),
      message: cleanText(json['message'], fallback.message),
      time: cleanText(json['time'], fallback.time),
      room: room,
      urgent: json['urgent'] == true || status == SafetyStatus.danger,
      resolved: json['resolved'] == true,
    );
  }

  factory AlertEvent.fromStatus(SafetyStatus status, {required String room, DateTime? at}) {
    final time = formatKoreanTime(at ?? DateTime.now());
    return switch (status) {
      SafetyStatus.danger => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '낙상 의심 움직임',
        message: '$room에서 급격히 쓰러진 듯한 패턴이 감지되었어요.',
        time: time,
        room: room,
        urgent: true,
        resolved: false,
      ),
      SafetyStatus.out => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '현관 접근 감지',
        message: '$room 근처에서 외출 가능성이 있는 이동이 감지되었어요.',
        time: time,
        room: room,
        urgent: false,
        resolved: false,
      ),
      SafetyStatus.still => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '장시간 움직임 적음',
        message: '$room에서 움직임이 거의 감지되지 않았어요.',
        time: time,
        room: room,
        urgent: false,
        resolved: false,
      ),
      SafetyStatus.normal => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '정상 재확인',
        message: '$room에서 평소와 비슷한 생활 움직임이 확인되었어요.',
        time: time,
        room: room,
        urgent: false,
        resolved: true,
      ),
      SafetyStatus.unknown => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '상태 확인 필요',
        message: '판단에 쓸 센서·모델 입력이 없어 상태를 확인하지 못했어요.',
        time: time,
        room: room,
        urgent: false,
        resolved: false,
      ),
    };
  }

  final int id;
  final SafetyStatus status;
  final String title;
  final String message;
  final String time;
  final String room;
  final bool urgent;
  final bool resolved;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': safetyStatusToServer(status),
    'title': title,
    'message': message,
    'time': time,
    'room': room,
    'urgent': urgent,
    'resolved': resolved,
  };
}

class SafetySnapshot {
  const SafetySnapshot({
    required this.status,
    required this.room,
    required this.pose,
    required this.x,
    required this.y,
    required this.confidence,
    required this.breathingRate,
    required this.breathingConfidence,
    required this.locationSharingEnabled,
    required this.serverConnected,
    required this.connectionNote,
    required this.dataSource,
    required this.lastUpdated,
    required this.movementPath,
    required this.alerts,
    required this.guardians,
    required this.emergencyInfo,
    required this.settings,
  });

  factory SafetySnapshot.initial() {
    final now = DateTime.now();
    return SafetySnapshot(
      // 서버 값을 받기 전에는 정상으로 단정하지 않는다.
      status: SafetyStatus.unknown,
      room: RoomResolver.living,
      pose: 'unknown',
      x: 0.34,
      y: 0.45,
      confidence: 0.86,
      breathingRate: null,
      breathingConfidence: 0.72,
      locationSharingEnabled: true,
      serverConnected: false,
      connectionNote: '상태를 확인하는 중',
      // 아직 받은 데이터가 없으므로 시연 데이터로도 표시하지 않는다.
      dataSource: 'unknown',
      lastUpdated: now,
      movementPath: const [
        Offset(0.26, 0.42),
        Offset(0.35, 0.55),
        Offset(0.55, 0.72),
        Offset(0.76, 0.85),
      ],
      alerts: const [],
      guardians: const [
        Guardian(id: 1, name: '김영희 어르신', phone: '010-0000-0000', role: '피보호자'),
        Guardian(id: 2, name: '홍길동 보호자', phone: '010-1234-5678', role: '1순위 보호자'),
      ],
      emergencyInfo: EmergencyInfo.defaultInfo,
      settings: const {
        'fallDetection': true,
        'stillnessDetection': true,
        'stillnessMinutes': 30,
        'intrusionDetection': true,
        'showPath': true,
        'locationSharingEnabled': true,
        'largeTextMode': false,
        'miniatureSize': 'medium',
      },
    );
  }

  final SafetyStatus status;
  final String room;
  final String pose;
  final double x;
  final double y;
  final double confidence;
  // null이면 측정된 호흡수가 없다는 뜻이다. 화면에는 '측정 대기'로 표시한다.
  final double? breathingRate;
  final double breathingConfidence;
  final bool locationSharingEnabled;
  final bool serverConnected;
  final String connectionNote;
  final String dataSource;
  final DateTime lastUpdated;
  final List<Offset> movementPath;
  final List<AlertEvent> alerts;
  final List<Guardian> guardians;
  final EmergencyInfo emergencyInfo;
  final Map<String, dynamic> settings;

  factory SafetySnapshot.fromCacheJson(Map<String, dynamic> json) {
    final fallback = SafetySnapshot.initial();
    final movementPath = json['movementPath'] is List
        ? (json['movementPath'] as List)
              .whereType<Map>()
              .map(
                (item) => Offset(
                  normalizedDouble(item['x'], fallback.x),
                  normalizedDouble(item['y'], fallback.y),
                ),
              )
              .toList()
        : fallback.movementPath;

    final alerts = json['alerts'] is List
        ? (json['alerts'] as List)
              .whereType<Map>()
              .map((item) => AlertEvent.fromJson(Map<String, dynamic>.from(item)))
              .take(40)
              .toList()
        : fallback.alerts;

    final guardians = json['guardians'] is List
        ? (json['guardians'] as List)
              .whereType<Map>()
              .map((item) => Guardian.fromJson(Map<String, dynamic>.from(item)))
              .toList()
        : fallback.guardians;

    final emergencyInfo = json['emergencyInfo'] is Map
        ? EmergencyInfo.fromJson(Map<String, dynamic>.from(json['emergencyInfo'] as Map))
        : fallback.emergencyInfo;

    final settings = json['settings'] is Map
        ? Map<String, dynamic>.from(json['settings'] as Map)
        : fallback.settings;

    final cachedTime = DateTime.tryParse(json['lastUpdated']?.toString() ?? '');

    final status = safetyStatusFrom(json['status']);
    return fallback.copyWith(
      status: status,
      room: cleanText(json['room'], fallback.room),
      pose: cleanText(json['pose'], fallback.pose),
      x: normalizedDouble(json['x'], fallback.x),
      y: normalizedDouble(json['y'], fallback.y),
      confidence: normalizedDouble(json['confidence'], fallback.confidence),
      breathingRate: measuredBreathingRate(json),
      breathingConfidence: normalizedDouble(
        json['breathingConfidence'] ?? json['respirationConfidence'],
        fallback.breathingConfidence,
      ),
      locationSharingEnabled: json['locationSharingEnabled'] is bool
          ? json['locationSharingEnabled'] as bool
          : fallback.locationSharingEnabled,
      serverConnected: false,
      connectionNote: '저장된 마지막 상태를 보여주는 중이에요',
      // 저장된 값은 실시간 추론이 아니므로 원래 출처(jetson_orin 등) 대신 캐시로 표시한다.
      dataSource: 'cache',
      lastUpdated: cachedTime ?? fallback.lastUpdated,
      movementPath: movementPath.isEmpty ? fallback.movementPath : movementPath,
      alerts: alerts,
      guardians: guardians.isEmpty ? fallback.guardians : guardians,
      emergencyInfo: emergencyInfo,
      settings: settings,
    );
  }

  Map<String, dynamic> toCacheJson() => {
    'status': safetyStatusToServer(status),
    'room': room,
    'pose': pose,
    'x': x,
    'y': y,
    'confidence': confidence,
    'breathingRate': breathingRate,
    'breathingConfidence': breathingConfidence,
    'locationSharingEnabled': locationSharingEnabled,
    'dataSource': dataSource,
    'lastUpdated': lastUpdated.toIso8601String(),
    'movementPath': [
      for (final point in movementPath) {'x': point.dx, 'y': point.dy},
    ],
    'alerts': alerts.map((alert) => alert.toJson()).toList(),
    'guardians': guardians.map((guardian) => guardian.toJson()).toList(),
    'emergencyInfo': emergencyInfo.toJson(),
    'settings': settings,
  };

  // 판단 불가(unknown)는 위험 대응 화면을 띄우지 않으므로 여기서 제외한다.
  bool get needsAttention =>
      status != SafetyStatus.normal && status != SafetyStatus.unknown;
  bool get isDanger => status == SafetyStatus.danger;
  bool get isUnknown => status == SafetyStatus.unknown;
  bool get isLocationHidden => !locationSharingEnabled;

  // 출처 값은 부분 문자열이 아니라 정확히 일치할 때만 인정한다.
  // 'jetson_orin' = 실제 엣지 추론, 'scripted_demo' = 스크립트 시연 입력.
  bool get isLiveSensorSource => dataSource == 'jetson_orin';
  bool get isScriptedDemoSource =>
      dataSource == 'scripted_demo' || dataSource == 'demo_sensor';

  String get levelLabel {
    return switch (status) {
      SafetyStatus.normal => '정상',
      SafetyStatus.out => '주의',
      SafetyStatus.still => '주의',
      SafetyStatus.danger => '위험',
      SafetyStatus.unknown => '확인 필요',
    };
  }

  String get levelSummary {
    return switch (status) {
      SafetyStatus.normal => '평소 패턴',
      SafetyStatus.out => '현관 접근 확인 필요',
      SafetyStatus.still => '장시간 움직임 부족',
      SafetyStatus.danger => '즉각 조치 필요',
      SafetyStatus.unknown => '판단 입력 없음',
    };
  }

  String get recommendedAction {
    return switch (status) {
      SafetyStatus.normal => '추가 조치 없이 생활 상태만 확인하면 돼요.',
      SafetyStatus.out => '현관 위치와 외출 여부를 먼저 확인해 주세요.',
      SafetyStatus.still => '전화나 메시지로 안부를 확인해 주세요.',
      SafetyStatus.danger => '즉시 연락하고, 응답이 없으면 119 신고 정보를 확인해 주세요.',
      SafetyStatus.unknown => '센서·엣지 연결을 확인하고, 필요하면 직접 안부를 확인해 주세요.',
    };
  }

  String get mapStatusLabel {
    return switch (status) {
      SafetyStatus.normal => '안정적인 생활 패턴',
      SafetyStatus.out => '주의: 현관 접근',
      SafetyStatus.still => '주의: 장시간 무반응',
      SafetyStatus.danger => '위험: 낙상 의심',
      SafetyStatus.unknown => '확인 필요: 판단 입력 없음',
    };
  }

  String get title {
    return switch (status) {
      SafetyStatus.normal => '이상 징후가 없어요',
      SafetyStatus.out => '현관 쪽 움직임이 있었어요',
      SafetyStatus.still => '오래 움직임이 적어요',
      SafetyStatus.danger => '즉각적인 조치가 필요해요',
      SafetyStatus.unknown => '지금 상태를 판단할 수 없어요',
    };
  }

  String get subtitle {
    return switch (status) {
      SafetyStatus.normal => '$room에서 평소와 비슷한 생활 움직임이 확인되었어요.',
      SafetyStatus.out => '$room 쪽 이동이 감지되었어요. 외출 여부를 확인해 주세요.',
      SafetyStatus.still => '$room에서 움직임이 적게 감지되었어요. 안부 확인이 필요해요.',
      SafetyStatus.danger => '$room에서 낙상 의심 움직임이 감지되었어요.',
      SafetyStatus.unknown => '엣지 모델 결과가 없거나 오래되어 상태를 확인하는 중이에요.',
    };
  }

  String get actionLabel {
    return switch (status) {
      SafetyStatus.normal => '집 안 상태 보기',
      SafetyStatus.out => '위치 확인하기',
      SafetyStatus.still => '어르신께 연락하기',
      SafetyStatus.danger => '긴급 확인하기',
      SafetyStatus.unknown => '연결 상태 확인하기',
    };
  }

  String get poseLabel {
    return switch (pose) {
      'lying' || 'fallen' => '누워 있는',
      'sitting' => '앉아 있는',
      'walking' => '이동 중인',
      'unknown' => '확인 필요',
      _ => '서 있는',
    };
  }

  String get confidenceLabel {
    if (confidence >= 0.85) return '높음';
    if (confidence >= 0.65) return '보통';
    return '확인 필요';
  }

  bool get breathingNeedsAttention {
    if (status == SafetyStatus.danger) return true;
    final rate = breathingRate;
    if (rate == null) return false;
    return rate < 12 || rate > 22 || breathingConfidence < 0.55;
  }

  String get breathingRateLabel {
    final rate = breathingRate;
    return rate == null ? '측정 대기' : '${rate.toStringAsFixed(1)}회/분';
  }

  String get breathingStatusLabel {
    if (status == SafetyStatus.danger) return '호흡 확인 필요';
    final rate = breathingRate;
    if (rate == null) return '호흡 측정 대기';
    if (rate < 12) return '일반 범위보다 느림';
    if (rate > 22) return '일반 범위보다 빠름';
    if (breathingConfidence < 0.55) return '신호 확인 중';
    return '안정적인 리듬';
  }

  String get breathingSummary {
    if (status == SafetyStatus.danger) {
      return '움직임 변화가 커서 호흡 리듬도 함께 확인하는 중이에요.';
    }
    final rate = breathingRate;
    if (rate == null) {
      return '아직 측정된 호흡 신호가 없어요. 측정값이 들어오면 여기에 보여드려요.';
    }
    if (rate < 12) {
      return '호흡이 일반적인 범위보다 느리게 보일 수 있어요. 몸 상태를 천천히 확인해 주세요.';
    }
    if (rate > 22) {
      return '호흡이 일반적인 범위보다 빠르게 보일 수 있어요. 잠시 앉아서 쉬어 주세요.';
    }
    if (breathingConfidence < 0.55) {
      return '신호가 약해 호흡 리듬을 다시 확인하고 있어요.';
    }
    return '비접촉 센싱 기준으로 호흡 리듬이 안정적으로 보이고 있어요.';
  }

  String get breathingAction {
    if (status == SafetyStatus.danger) return '통증이나 숨참이 있으면 바로 도움을 요청하세요.';
    final rate = breathingRate;
    if (rate == null) return '측정값이 들어오기 전까지는 호흡 안내를 하지 않아요.';
    if (rate < 12 || rate > 22) return '불편함이 계속되면 보호자에게 알려 주세요.';
    if (breathingConfidence < 0.55) return '센서 주변에서 잠시 편하게 머물러 주세요.';
    return '편하게 호흡하면서 평소처럼 지내도 괜찮아요.';
  }

  String get breathingSourceLabel {
    if (breathingRate == null) return '호흡 신호 미수신';
    if (isLiveSensorSource) return 'CSI 호흡 신호 수신';
    if (isScriptedDemoSource) return '시연 입력값';
    return '실측 여부 확인 필요';
  }

  String get dataSourceLabel {
    return switch (dataSource) {
      'jetson_orin' => 'Jetson 실시간 추론',
      'scripted_demo' || 'demo_sensor' => '시연 입력',
      'unknown' => '출처 미지정',
      'sensor-waiting' => '센서 입력 대기',
      'admin' => '관리자 수동 입력',
      'app-demo' || 'scenario' => '앱 시연 데이터',
      'mock' => '시연용 mock 데이터',
      'boot' || 'reset' => '입력 대기',
      'care-recipient' => '피보호자 확인 응답',
      'cache' => '앱에 저장된 마지막 상태',
      _ => cleanText(dataSource, '데이터 출처 확인 중'),
    };
  }

  String get lastUpdatedText {
    if (!serverConnected) return '최근 상태 재확인 중';
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inSeconds < 5) return '방금 확인';
    if (diff.inMinutes < 1) return '${diff.inSeconds}초 전 확인';
    return '${diff.inMinutes}분 전 확인';
  }

  Guardian? get careTarget {
    for (final guardian in guardians) {
      if (guardian.role.contains('피보호자') || guardian.name.contains('어르신')) {
        return guardian;
      }
    }
    return guardians.isEmpty ? null : guardians.first;
  }

  Guardian? get primaryGuardian {
    for (final guardian in guardians) {
      if (guardian.role.contains('보호자')) return guardian;
    }
    if (guardians.length > 1) return guardians[1];
    return guardians.isEmpty ? null : guardians.first;
  }

  bool settingBool(String key, bool fallback) {
    final value = settings[key];
    return value is bool ? value : fallback;
  }

  int settingInt(String key, int fallback) {
    final value = settings[key];
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  SafetySnapshot copyWith({
    SafetyStatus? status,
    String? room,
    String? pose,
    double? x,
    double? y,
    double? confidence,
    double? breathingRate,
    bool clearBreathingRate = false,
    double? breathingConfidence,
    bool? locationSharingEnabled,
    bool? serverConnected,
    String? connectionNote,
    String? dataSource,
    DateTime? lastUpdated,
    List<Offset>? movementPath,
    List<AlertEvent>? alerts,
    List<Guardian>? guardians,
    EmergencyInfo? emergencyInfo,
    Map<String, dynamic>? settings,
  }) {
    return SafetySnapshot(
      status: status ?? this.status,
      room: room ?? this.room,
      pose: pose ?? this.pose,
      x: x ?? this.x,
      y: y ?? this.y,
      confidence: confidence ?? this.confidence,
      breathingRate: clearBreathingRate ? null : (breathingRate ?? this.breathingRate),
      breathingConfidence: breathingConfidence ?? this.breathingConfidence,
      locationSharingEnabled: locationSharingEnabled ?? this.locationSharingEnabled,
      serverConnected: serverConnected ?? this.serverConnected,
      connectionNote: connectionNote ?? this.connectionNote,
      dataSource: dataSource ?? this.dataSource,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      movementPath: movementPath ?? this.movementPath,
      alerts: alerts ?? this.alerts,
      guardians: guardians ?? this.guardians,
      emergencyInfo: emergencyInfo ?? this.emergencyInfo,
      settings: settings ?? this.settings,
    );
  }
}

String poseFromStatus(SafetyStatus status) {
  return switch (status) {
    SafetyStatus.danger => 'lying',
    SafetyStatus.out => 'walking',
    SafetyStatus.still => 'sitting',
    SafetyStatus.normal => 'standing',
    SafetyStatus.unknown => 'unknown',
  };
}

String formatKoreanTime(DateTime time) {
  final prefix = time.hour < 12 ? '오전' : '오후';
  final hour = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  return '$prefix $hour:$minute';
}
