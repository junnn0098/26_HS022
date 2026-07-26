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
        return ScreenScaffold(
          title: '설정',
          subtitle: '가족과 알림, 집 안 화면을 관리해요',
          trailing: StatusBadge(
            status: snapshot.serverConnected
                ? SafetyStatus.normal
                : SafetyStatus.out,
            label: snapshot.serverConnected ? '상태 확인 중' : '재확인 중',
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _CareTargetCard(snapshot: snapshot),
              const SectionTitle('알림 기준'),
              _SettingGroup(
                children: [
                  _SwitchSetting(
                    title: '낙상 의심',
                    subtitle: '급격한 쓰러짐 패턴을 감지해요',
                    value: snapshot.settingBool('fallDetection', true),
                    onChanged: (value) =>
                        controller.updateSetting('fallDetection', value),
                  ),
                  _SwitchSetting(
                    title: '장시간 무반응',
                    subtitle:
                        '${snapshot.settingInt('stillnessMinutes', 30)}분 이상 움직임이 적으면 알려줘요',
                    value: snapshot.settingBool('stillnessDetection', true),
                    onChanged: (value) =>
                        controller.updateSetting('stillnessDetection', value),
                  ),
                  _SwitchSetting(
                    title: '현관 접근',
                    subtitle: '외출 가능성이 있는 이동을 확인해요',
                    value: snapshot.settingBool('intrusionDetection', true),
                    onChanged: (value) =>
                        controller.updateSetting('intrusionDetection', value),
                  ),
                ],
              ),
              const SectionTitle('집 안 화면 표시'),
              _SettingGroup(
                children: [
                  _SwitchSetting(
                    title: '최근 이동 경로',
                    subtitle: '상황 재연을 위해 점선 잔상을 표시해요',
                    value: snapshot.settingBool('showPath', true),
                    onChanged: (value) =>
                        controller.updateSetting('showPath', value),
                  ),
                ],
              ),
              const SectionTitle('119 신고 정보'),
              _EmergencyInfoCard(snapshot: snapshot),
              const SectionTitle('상황 재연'),
              _DemoTools(controller: controller),
              const SizedBox(height: 12),
              _DiagnosticCard(snapshot: snapshot),
            ],
          ),
        );
      },
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
            title: target?.name ?? '김영희 어르신',
            subtitle: '보호 대상 · ${target?.phone ?? '010-0000-0000'}',
            color: AppColors.primary,
          ),
          const Divider(height: 26, color: AppColors.border),
          _InfoRow(
            icon: Icons.admin_panel_settings_rounded,
            title: guardian?.name ?? '김주환 보호자',
            subtitle:
                '${guardian?.role ?? '1순위 보호자'} · ${guardian?.phone ?? '010-1234-5678'}',
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
            subtitle: info.address,
            color: AppColors.primary,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.key_rounded,
            title: '출입 안내',
            subtitle: info.accessNote,
            color: AppColors.warning,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.medical_information_rounded,
            title: '의료 참고사항',
            subtitle: info.medicalNote,
            color: AppColors.danger,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoRow(
            icon: Icons.local_hospital_rounded,
            title: '가까운 병원',
            subtitle: info.hospital,
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
            style: TextStyle(
              color: AppColors.muted,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
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
          const Text(
            '앱 상태',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '알림과 집 안 상태 확인이 정상적으로 준비되어 있는지 보여줘요.',
            style: TextStyle(
              color: AppColors.muted.withValues(alpha: 0.9),
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _MiniLine(label: '최근 확인', value: snapshot.lastUpdatedText),
          _MiniLine(
            label: '알림 연결',
            value: snapshot.serverConnected ? '준비됨' : '다시 확인 중',
          ),
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
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              const Divider(height: 1, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
      activeThumbColor: AppColors.primary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
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
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w900,
                ),
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
  const _ScenarioButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
      child: Text(label),
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
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
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
