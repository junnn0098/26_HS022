import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../core/state/safety_controller.dart';
import '../../shared/ui/app_ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final SafetyController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final connected = snapshot.serverConnected;

        return ScreenScaffold(
          title: '설정',
          subtitle: '보호 대상, 알림, 집 안 화면을 관리해요',
          trailing: StatusBadge(
            status: connected ? SafetyStatus.normal : SafetyStatus.out,
            label: connected ? '준비됨' : '확인 중',
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              _SettingsOverviewCard(snapshot: snapshot),
              const SectionTitle('보호 대상'),
              _CareTargetCard(snapshot: snapshot),
              const SectionTitle(
                '화면 보기',
                trailing: TapHintLabel(icon: Icons.touch_app_rounded, label: '바로 적용'),
              ),
              _SettingGroup(
                children: [
                  _SwitchSetting(
                    icon: Icons.format_size_rounded,
                    color: AppColors.primary,
                    title: '큰 글자 모드',
                    subtitle: '고령층도 쉽게 읽을 수 있도록 주요 글자를 크게 보여줘요.',
                    value: snapshot.settingBool('largeTextMode', false),
                    onChanged: (value) => _updateSetting(context, 'largeTextMode', value),
                  ),
                ],
              ),
              const SectionTitle(
                '알림 기준',
                trailing: TapHintLabel(icon: Icons.notifications_active_rounded, label: '위험 감지'),
              ),
              _SettingGroup(
                children: [
                  _SwitchSetting(
                    icon: Icons.personal_injury_rounded,
                    color: AppColors.danger,
                    title: '낙상 의심',
                    subtitle: '급격히 쓰러지는 듯한 움직임이 보이면 보호자에게 알려줘요.',
                    value: snapshot.settingBool('fallDetection', true),
                    onChanged: (value) => _updateSetting(context, 'fallDetection', value),
                  ),
                  _SwitchSetting(
                    icon: Icons.event_busy_rounded,
                    color: AppColors.warning,
                    title: '장시간 무반응',
                    subtitle: '${snapshot.settingInt('stillnessMinutes', 30)}분 이상 움직임이 적으면 확인 알림을 띄워요.',
                    value: snapshot.settingBool('stillnessDetection', true),
                    onChanged: (value) => _updateSetting(context, 'stillnessDetection', value),
                  ),
                  _SwitchSetting(
                    icon: Icons.door_front_door_rounded,
                    color: AppColors.warning,
                    title: '현관 접근',
                    subtitle: '현관 쪽 이동이 반복되면 외출 가능성으로 표시해요.',
                    value: snapshot.settingBool('intrusionDetection', true),
                    onChanged: (value) => _updateSetting(context, 'intrusionDetection', value),
                  ),
                ],
              ),
              const SectionTitle(
                '집 안 도면 표시',
                trailing: TapHintLabel(icon: Icons.map_rounded, label: '위치 화면'),
              ),
              _SettingGroup(
                children: [
                  _SwitchSetting(
                    icon: Icons.route_rounded,
                    color: AppColors.primary,
                    title: '최근 이동 잔상',
                    subtitle: '도면에서 최근 움직임을 사람 잔상으로 보여줘 상황을 더 빨리 이해하게 해요.',
                    value: snapshot.settingBool('showPath', true),
                    onChanged: (value) => _updateSetting(context, 'showPath', value),
                  ),
                  _SwitchSetting(
                    icon: Icons.my_location_rounded,
                    color: AppColors.success,
                    title: '위치 공유',
                    subtitle: '보호자가 피보호자의 현재 위치를 확인할 수 있게 해요.',
                    value: snapshot.locationSharingEnabled,
                    onChanged: (value) =>
                        _updateSetting(context, 'locationSharingEnabled', value),
                  ),
                ],
              ),
              const SectionTitle('119 신고 정보'),
              _EmergencyInfoCard(snapshot: snapshot),
              const SectionTitle(
                '상황 재연',
                trailing: TapHintLabel(icon: Icons.play_circle_rounded, label: '발표용'),
              ),
              _DemoTools(controller: controller),
              const SizedBox(height: 12),
              _DiagnosticCard(snapshot: snapshot),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateSetting(BuildContext context, String key, Object? value) async {
    final saved = await controller.updateSetting(key, value);
    if (saved || !context.mounted) return;
    showAppSnackBar(
      context,
      message: '화면에는 적용했지만 서버 저장은 다시 확인 중이에요.',
      icon: Icons.cloud_sync_rounded,
      color: AppColors.warning,
    );
  }
}

class _SettingsOverviewCard extends StatelessWidget {
  const _SettingsOverviewCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final enabledAlerts = [
      snapshot.settingBool('fallDetection', true),
      snapshot.settingBool('stillnessDetection', true),
      snapshot.settingBool('intrusionDetection', true),
    ].where((enabled) => enabled).length;

    return AppCard(
      color: const Color(0xFFF8FAFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '설정 요약',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '보호자가 자주 확인할 항목만 모았어요.',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OverviewPill(
                icon: Icons.format_size_rounded,
                label: '큰 글자',
                activeText: snapshot.settingBool('largeTextMode', false) ? '켜짐' : '기본',
                active: snapshot.settingBool('largeTextMode', false),
                color: AppColors.primary,
              ),
              _OverviewPill(
                icon: Icons.notifications_active_rounded,
                label: '알림',
                activeText: '$enabledAlerts개 감지',
                active: enabledAlerts > 0,
                color: AppColors.danger,
              ),
              _OverviewPill(
                icon: Icons.location_on_rounded,
                label: '위치 공유',
                activeText: snapshot.locationSharingEnabled ? '켜짐' : '꺼짐',
                active: snapshot.locationSharingEnabled,
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  const _OverviewPill({
    required this.icon,
    required this.label,
    required this.activeText,
    required this.active,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String activeText;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? color : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.11) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: active ? color.withValues(alpha: 0.18) : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 17),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: foreground, fontSize: 12, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 5),
          Text(
            activeText,
            style: TextStyle(
              color: active ? AppColors.text : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CareTargetCard extends StatelessWidget {
  const _CareTargetCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final target = snapshot.careTarget;
    final guardian = snapshot.primaryGuardian;
    return AppCard(
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.elderly_rounded,
            title: _safeText(target?.name, '김영희 어르신'),
            subtitle: '보호 대상 · ${_safeText(target?.phone, '010-0000-0000')}',
            color: AppColors.primary,
          ),
          const Divider(height: 26, color: AppColors.border),
          _InfoRow(
            icon: Icons.admin_panel_settings_rounded,
            title: _safeText(guardian?.name, '김주환 보호자'),
            subtitle: '${_safeText(guardian?.role, '1순위 보호자')} · ${_safeText(guardian?.phone, '010-1234-5678')}',
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _EmergencyInfoCard extends StatelessWidget {
  const _EmergencyInfoCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final info = snapshot.emergencyInfo;
    return AppCard(
      child: Column(
        children: [
          _InfoRow(
            icon: Icons.home_work_rounded,
            title: '집 주소',
            subtitle: _safeText(info.address, '우리집'),
            color: AppColors.primary,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.key_rounded,
            title: '출입 안내',
            subtitle: _safeText(info.accessNote, '공동현관 호출 후 보호자에게 연락해 주세요.'),
            color: AppColors.warning,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.medical_information_rounded,
            title: '의료 참고사항',
            subtitle: _safeText(info.medicalNote, '고혈압 약 복용 중. 낙상 의심 시 무리하게 일으키지 말아 주세요.'),
            color: AppColors.danger,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.local_hospital_rounded,
            title: '가까운 병원',
            subtitle: _safeText(info.hospital, '가까운 응급실: 아주대학교병원'),
            color: AppColors.success,
          ),
        ],
      ),
    );
  }
}

class _DemoTools extends StatelessWidget {
  const _DemoTools({required this.controller});

  final SafetyController controller;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _ScenarioButton(
                  label: '정상',
                  color: AppColors.success,
                  onTap: () => controller.triggerScenario(SafetyStatus.normal),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ScenarioButton(
                  label: '현관 접근',
                  color: AppColors.warning,
                  onTap: () => controller.triggerScenario(SafetyStatus.out),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ScenarioButton(
                  label: '무반응',
                  color: AppColors.warning,
                  onTap: () => controller.triggerScenario(SafetyStatus.still),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ScenarioButton(
                  label: '낙상 의심',
                  color: AppColors.danger,
                  onTap: () => controller.triggerScenario(SafetyStatus.danger),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '테스트나 발표 상황에서 정상·주의·위험 상태를 빠르게 재연할 수 있어요.',
            style: TextStyle(color: AppColors.muted, height: 1.45, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: const Color(0xFFF8FAFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: snapshot.serverConnected ? AppColors.successSoft : AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  snapshot.serverConnected ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                  color: snapshot.serverConnected ? AppColors.success : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '앱 연결 상태',
                  style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '알림과 위치 화면이 정상적으로 준비되어 있는지 확인할 수 있어요.',
            style: TextStyle(
              color: AppColors.muted.withValues(alpha: 0.9),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _MiniLine(label: '최근 확인', value: _safeText(snapshot.lastUpdatedText, '방금 확인')),
          _MiniLine(label: '서버 연결', value: snapshot.serverConnected ? '준비됨' : '다시 확인 중'),
          _MiniLine(label: '데이터 출처', value: snapshot.dataSourceLabel),
          _MiniLine(label: '현재 위치', value: _safeText(snapshot.room, '거실')),
        ],
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i != children.length - 1) const Divider(height: 1, color: AppColors.border),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: value ? color.withValues(alpha: 0.13) : const Color(0xFFF3F5FA),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Icon(icon, color: value ? color : AppColors.muted),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatePill(active: value),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              IgnorePointer(
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: color,
                  activeTrackColor: color.withValues(alpha: 0.24),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: const Color(0xFFE1E6F0),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.success : AppColors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: active ? AppColors.successSoft : const Color(0xFFF3F5FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? '켜짐' : '꺼짐',
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScenarioButton extends StatelessWidget {
  const _ScenarioButton({required this.label, required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.24),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _MiniLine extends StatelessWidget {
  const _MiniLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _safeText(dynamic value, String fallback) => cleanText(value, fallback);
