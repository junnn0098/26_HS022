import 'dart:ui';

enum SafetyStatus { normal, out, still, danger }

SafetyStatus safetyStatusFrom(dynamic value) {
  final raw = value?.toString().toLowerCase().trim();
  return switch (raw) {
    'danger' || 'fall' => SafetyStatus.danger,
    'out' || 'exit' || 'intrusion' => SafetyStatus.out,
    'still' || 'inactive' => SafetyStatus.still,
    _ => SafetyStatus.normal,
  };
}

String safetyStatusToServer(SafetyStatus status) {
  return switch (status) {
    SafetyStatus.normal => 'normal',
    SafetyStatus.out => 'out',
    SafetyStatus.still => 'still',
    SafetyStatus.danger => 'danger',
  };
}

class RoomResolver {
  const RoomResolver._();

  static const living = '거실';
  static const kitchen = '주방';
  static const bedroom = '침실';
  static const bathroom = '욕실';
  static const entrance = '현관';
  static const unknown = '확인 필요';

  static const all = [living, kitchen, bedroom, bathroom, entrance];

  static String normalize(dynamic raw, double x, double y) {
    final value = raw?.toString().trim();
    if (value != null && all.contains(value)) return value;
    return fromPosition(x, y);
  }

  static String fromPosition(double x, double y) {
    // 앱 도면 기준: 10 x 18 타일 투룸형 실험 공간.
    if (x >= 0.50 && y < 0.28) return kitchen;
    if (x < 0.50 && y < 0.28) return bedroom;
    if (x >= 0.67 && y >= 0.28 && y < 0.56) return bathroom;
    if (x >= 0.60 && y >= 0.56) return entrance;
    if (x < 0.60 && y >= 0.56) return bedroom;
    return living;
  }
}

bool looksBrokenText(String? value) {
  if (value == null) return true;
  final text = value.trim();
  if (text.isEmpty) return true;
  return text.contains('�') ||
      text.contains('?') ||
      text.contains('??') ||
      text.contains('嫄') ||
      text.contains('蹂') ||
      text.contains('源') ||
      text.contains('移') ||
      text.contains('怨') ||
      text.contains('諛');
}

String cleanText(dynamic value, String fallback) {
  final text = value?.toString().trim();
  if (looksBrokenText(text)) return fallback;
  return text!;
}

double normalizedDouble(dynamic value, double fallback) {
  final parsed = switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
  return (parsed ?? fallback).clamp(0.0, 1.0).toDouble();
}

class Guardian {
  const Guardian({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
  });

  factory Guardian.fromJson(Map<String, dynamic> json) {
    final id = switch (json['id']) {
      num number => number.toInt(),
      String text => int.tryParse(text) ?? 0,
      _ => 0,
    };

    return Guardian(
      id: id,
      name: cleanText(json['name'], id == 1 ? '김영희 어르신' : '김주환 보호자'),
      phone: cleanText(json['phone'], '010-0000-0000'),
      role: cleanText(json['role'], id == 1 ? '보호 대상' : '1순위 보호자'),
    );
  }

  final int id;
  final String name;
  final String phone;
  final String role;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'role': role,
  };
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
      address: cleanText(json['address'], defaultInfo.address),
      accessNote: cleanText(json['accessNote'], defaultInfo.accessNote),
      doorPassword: cleanText(json['doorPassword'], defaultInfo.doorPassword),
      medicalNote: cleanText(json['medicalNote'], defaultInfo.medicalNote),
      hospital: cleanText(json['hospital'], defaultInfo.hospital),
    );
  }

  static const defaultInfo = EmergencyInfo(
    address: '우리집',
    accessNote: '공동현관 호출 후 보호자에게 연락해 주세요.',
    doorPassword: '',
    medicalNote: '고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.',
    hospital: '가까운 응급실: 아주대학교병원',
  );

  final String address;
  final String accessNote;
  final String doorPassword;
  final String medicalNote;
  final String hospital;

  Map<String, dynamic> toJson() => {
    'address': address,
    'accessNote': accessNote,
    'doorPassword': doorPassword,
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
      'danger' => SafetyStatus.danger,
      'warning' => SafetyStatus.out,
      'still' => SafetyStatus.still,
      _ => SafetyStatus.normal,
    };
    final rawRoom = cleanText(json['room'], RoomResolver.unknown);
    final room = RoomResolver.all.contains(rawRoom)
        ? rawRoom
        : RoomResolver.unknown;
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

  factory AlertEvent.fromStatus(
    SafetyStatus status, {
    required String room,
    DateTime? at,
  }) {
    final time = formatKoreanTime(at ?? DateTime.now());
    return switch (status) {
      SafetyStatus.danger => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '낙상 의심 움직임',
        message: '$room에서 급격한 쓰러짐 패턴이 감지됐어요.',
        time: time,
        room: room,
        urgent: true,
        resolved: false,
      ),
      SafetyStatus.out => AlertEvent(
        id: DateTime.now().millisecondsSinceEpoch,
        status: status,
        title: '현관 접근 감지',
        message: '$room 근처에서 외출 가능성이 있는 이동이 감지됐어요.',
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
        message: '$room에서 평소와 비슷한 움직임이 확인됐어요.',
        time: time,
        room: room,
        urgent: false,
        resolved: true,
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
}

class SafetySnapshot {
  const SafetySnapshot({
    required this.status,
    required this.room,
    required this.pose,
    required this.x,
    required this.y,
    required this.confidence,
    required this.locationSharingEnabled,
    required this.serverConnected,
    required this.connectionNote,
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
      status: SafetyStatus.normal,
      room: RoomResolver.living,
      pose: 'standing',
      x: 0.34,
      y: 0.45,
      confidence: 0.86,
      locationSharingEnabled: true,
      serverConnected: false,
      connectionNote: '상태를 확인하는 중',
      lastUpdated: now,
      movementPath: const [
        Offset(0.26, 0.42),
        Offset(0.35, 0.55),
        Offset(0.55, 0.72),
        Offset(0.76, 0.85),
      ],
      alerts: [
        AlertEvent.fromStatus(SafetyStatus.normal, room: RoomResolver.living),
      ],
      guardians: const [
        Guardian(id: 1, name: '김영희 어르신', phone: '010-0000-0000', role: '보호 대상'),
        Guardian(
          id: 2,
          name: '김주환 보호자',
          phone: '010-1234-5678',
          role: '1순위 보호자',
        ),
      ],
      emergencyInfo: EmergencyInfo.defaultInfo,
      settings: const {
        'fallDetection': true,
        'stillnessDetection': true,
        'stillnessMinutes': 30,
        'intrusionDetection': true,
        'showPath': true,
        'locationSharingEnabled': true,
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
  final bool locationSharingEnabled;
  final bool serverConnected;
  final String connectionNote;
  final DateTime lastUpdated;
  final List<Offset> movementPath;
  final List<AlertEvent> alerts;
  final List<Guardian> guardians;
  final EmergencyInfo emergencyInfo;
  final Map<String, dynamic> settings;

  bool get needsAttention => status != SafetyStatus.normal;
  bool get isDanger => status == SafetyStatus.danger;
  bool get isLocationHidden => !locationSharingEnabled;

  String get levelLabel {
    return switch (status) {
      SafetyStatus.normal => '정상',
      SafetyStatus.out => '주의',
      SafetyStatus.still => '주의',
      SafetyStatus.danger => '위험',
    };
  }

  String get levelSummary {
    return switch (status) {
      SafetyStatus.normal => '평소와 유사한 움직임',
      SafetyStatus.out => '현관·외출 가능성 확인 필요',
      SafetyStatus.still => '장시간 움직임 부족',
      SafetyStatus.danger => '즉각적인 조치 필요',
    };
  }

  String get recommendedAction {
    return switch (status) {
      SafetyStatus.normal => '추가 조치 없이 생활 상태만 확인하면 돼요.',
      SafetyStatus.out => '현관 위치와 외출 여부를 먼저 확인해 주세요.',
      SafetyStatus.still => '전화나 메시지로 안부를 확인해 주세요.',
      SafetyStatus.danger => '즉시 연락하고, 응답이 없으면 119 신고 정보를 확인해 주세요.',
    };
  }

  String get mapStatusLabel {
    return switch (status) {
      SafetyStatus.normal => '안정적인 생활 패턴',
      SafetyStatus.out => '주의: 현관 접근',
      SafetyStatus.still => '주의: 장시간 무반응',
      SafetyStatus.danger => '위험: 낙상 의심',
    };
  }

  String get title {
    return switch (status) {
      SafetyStatus.normal => '이상 징후가 없어요',
      SafetyStatus.out => '현관 접근을 확인해 주세요',
      SafetyStatus.still => '오래 움직임이 적어요',
      SafetyStatus.danger => '즉각적인 조치가 필요해요',
    };
  }

  String get subtitle {
    return switch (status) {
      SafetyStatus.normal => '$room에서 평소와 비슷한 생활 움직임이 확인됐어요.',
      SafetyStatus.out => '$room 쪽 이동이 감지됐어요. 외출 여부를 확인해 주세요.',
      SafetyStatus.still => '$room에서 움직임이 적게 감지됐어요. 안부 확인이 필요해요.',
      SafetyStatus.danger => '$room에서 낙상 의심 움직임이 감지됐어요.',
    };
  }

  String get actionLabel {
    return switch (status) {
      SafetyStatus.normal => '집 안 상태 보기',
      SafetyStatus.out => '위치 확인하기',
      SafetyStatus.still => '어르신께 연락하기',
      SafetyStatus.danger => '긴급 확인하기',
    };
  }

  String get poseLabel {
    return switch (pose) {
      'lying' => '누워 있는',
      'sitting' => '앉아 있는',
      'walking' => '이동 중인',
      _ => '서 있는',
    };
  }

  String get confidenceLabel {
    if (confidence >= 0.85) return '높음';
    if (confidence >= 0.65) return '보통';
    return '재확인 필요';
  }

  String get lastUpdatedText {
    if (!serverConnected) return '최근 상태를 다시 확인 중';
    final diff = DateTime.now().difference(lastUpdated);
    if (diff.inSeconds < 5) return '방금 확인됨';
    if (diff.inMinutes < 1) return '${diff.inSeconds}초 전 확인';
    return '${diff.inMinutes}분 전 확인';
  }

  Guardian? get careTarget {
    for (final guardian in guardians) {
      if (guardian.role.contains('대상') || guardian.name.contains('어르신')) {
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
    bool? locationSharingEnabled,
    bool? serverConnected,
    String? connectionNote,
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
      locationSharingEnabled:
          locationSharingEnabled ?? this.locationSharingEnabled,
      serverConnected: serverConnected ?? this.serverConnected,
      connectionNote: connectionNote ?? this.connectionNote,
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
  };
}

String formatKoreanTime(DateTime time) {
  final prefix = time.hour < 12 ? '오전' : '오후';
  final hour = time.hour == 0
      ? 12
      : (time.hour > 12 ? time.hour - 12 : time.hour);
  final minute = time.minute.toString().padLeft(2, '0');
  return '$prefix $hour:$minute';
}
