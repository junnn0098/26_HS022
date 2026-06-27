part of '../main.dart';

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
