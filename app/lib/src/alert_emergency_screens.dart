part of '../main.dart';

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
