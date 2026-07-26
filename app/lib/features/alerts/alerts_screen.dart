import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/emergency_actions.dart';
import '../../core/state/safety_controller.dart';
import '../../shared/ui/app_ui.dart';
import '../home_map/floor_plan_view.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({required this.controller, super.key});

  final SafetyController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return ScreenScaffold(
          title: snapshot.isDanger ? '긴급 확인이\n필요해요' : '안전 알림',
          subtitle: snapshot.isDanger
              ? '확인 → 연락 → 신고 → 기록 순서로 안내해요'
              : '생활 변화와 위험 알림을 모아봤어요',
          trailing: StatusBadge(
            status: snapshot.status,
            label: snapshot.isDanger ? '즉각 조치' : '알림 정리',
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              if (snapshot.needsAttention) ...[
                _EmergencySummary(controller: controller, snapshot: snapshot),
                const SectionTitle('도면으로 위치 확인'),
                _LocationCheckMapCard(snapshot: snapshot),
                const SectionTitle('상황 대응 절차'),
                _ActionSteps(snapshot: snapshot),
                const SectionTitle('119 전달 정보'),
                _EmergencyInfoForCall(snapshot: snapshot),
              ],
              SectionTitle(snapshot.needsAttention ? '알림 기록' : '오늘 알림'),
              if (snapshot.alerts.isEmpty)
                const AppCard(
                  child: Text(
                    '아직 확인할 알림이 없어요.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else
                ...snapshot.alerts.map(
                  (alert) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AlertTile(alert: alert),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmergencySummary extends StatelessWidget {
  const _EmergencySummary({required this.controller, required this.snapshot});

  final SafetyController controller;
  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    final target = snapshot.careTarget;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  statusIcon(snapshot.status),
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  snapshot.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            snapshot.subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              height: 1.45,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                _Meta(label: '발생 위치', value: snapshot.room),
                const SizedBox(height: 10),
                _Meta(label: '현재 자세', value: snapshot.poseLabel),
                const SizedBox(height: 10),
                _Meta(label: '확인 시각', value: snapshot.lastUpdatedText),
                const SizedBox(height: 10),
                _Meta(
                  label: '필요 조치',
                  value: snapshot.isDanger ? '연락 후 119 판단' : '안부 확인',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _dialTarget(context, target?.phone ?? ''),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('어르신께 전화'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: color,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _dialTarget(context, '119'),
                  icon: const Icon(Icons.local_hospital_rounded),
                  label: const Text('119'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GhostButton(
            label: '괜찮음을 확인했어요',
            icon: Icons.check_circle_rounded,
            onPressed: controller.markSafe,
          ),
        ],
      ),
    );
  }

  Future<void> _dialTarget(BuildContext context, String phone) async {
    final ok = await EmergencyActions.dial(phone);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '전화 앱을 열었어요.' : '전화 앱을 열 수 없어요.')),
    );
  }
}

class _ActionSteps extends StatelessWidget {
  const _ActionSteps({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final steps = snapshot.isDanger
        ? const [
            _StepData('1', '전화 확인', '어르신께 전화해 의식, 통증, 움직일 수 있는지 확인해요.'),
            _StepData('2', '추가 확인', '응답이 애매하면 가까운 가족이나 이웃에게 확인을 요청해요.'),
            _StepData('3', '119 신고 판단', '응답이 없거나 통증이 크면 119 신고 단계로 넘어가요.'),
            _StepData('4', '정보 전달', '주소, 출입 안내, 의료 참고사항을 구조대에게 전달해요.'),
            _StepData('5', '상황 기록', '확인 결과를 알림 기록에 남겨 이후 재연/보고에 사용해요.'),
          ]
        : const [
            _StepData('1', '위치 확인', '현재 위치와 최근 이동 동선을 확인해요.'),
            _StepData('2', '안부 연락', '필요하면 어르신께 전화로 상태를 확인해요.'),
            _StepData('3', '정상 처리', '문제가 없으면 괜찮음을 확인해 알림을 정리해요.'),
          ];

    return AppCard(
      child: Column(
        children: [
          for (final step in steps) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: snapshot.isDanger
                        ? AppColors.dangerSoft
                        : AppColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      step.number,
                      style: TextStyle(
                        color: snapshot.isDanger
                            ? AppColors.danger
                            : AppColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.body,
                        style: const TextStyle(
                          color: AppColors.muted,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (step != steps.last)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: AppColors.border),
              ),
          ],
        ],
      ),
    );
  }
}

class _LocationCheckMapCard extends StatelessWidget {
  const _LocationCheckMapCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    final hidden = snapshot.isLocationHidden;
    final title = hidden ? '위치 공유가 꺼져 있어요' : '${snapshot.room} 위치를 확인해 주세요';
    final body = hidden
        ? '피보호자가 위치 공유를 꺼둔 상태라 정확한 방 위치와 이동 동선은 숨겨져요.'
        : '도면 위 사람 아이콘은 현재 위치, 점선은 최근 이동 흐름이에요.';

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  hidden ? Icons.location_off_rounded : Icons.map_rounded,
                  color: color,
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
                        color: AppColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FloorPlanView(
            snapshot: snapshot,
            compact: true,
            showPath: !hidden,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LocationChip(
                icon: hidden
                    ? Icons.visibility_off_rounded
                    : Icons.place_rounded,
                label: hidden ? '위치 비공개' : snapshot.room,
                color: color,
              ),
              _LocationChip(
                icon: Icons.accessibility_new_rounded,
                label: snapshot.poseLabel,
                color: color,
              ),
              _LocationChip(
                icon: Icons.schedule_rounded,
                label: snapshot.lastUpdatedText,
                color: color,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LocationChip extends StatelessWidget {
  const _LocationChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmergencyInfoForCall extends StatelessWidget {
  const _EmergencyInfoForCall({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final info = snapshot.emergencyInfo;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoLine(icon: Icons.home_rounded, label: '주소', value: info.address),
          const Divider(height: 24, color: AppColors.border),
          _InfoLine(
            icon: Icons.key_rounded,
            label: '출입',
            value: info.accessNote,
          ),
          const Divider(height: 24, color: AppColors.border),
          _InfoLine(
            icon: Icons.medical_information_rounded,
            label: '의료',
            value: info.medicalNote,
          ),
          const SizedBox(height: 16),
          PrimaryButton(
            label: '119 전달 내용 복사',
            icon: Icons.copy_rounded,
            color: AppColors.primaryDark,
            onPressed: () => _copyEmergencyInfo(context, snapshot),
          ),
        ],
      ),
    );
  }

  Future<void> _copyEmergencyInfo(
    BuildContext context,
    SafetySnapshot snapshot,
  ) async {
    final info = snapshot.emergencyInfo;
    await Clipboard.setData(
      ClipboardData(
        text:
            '한이음 안전 알림\n'
            '상황: ${snapshot.title}\n'
            '위치: ${snapshot.room}\n'
            '자세: ${snapshot.poseLabel}\n'
            '주소: ${info.address}\n'
            '출입 안내: ${info.accessNote}\n'
            '의료 참고: ${info.medicalNote}\n'
            '가까운 병원: ${info.hospital}',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('119 전달 내용을 복사했어요.')));
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final AlertEvent alert;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(alert.status);
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusSoftColor(alert.status),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon(alert.status), color: color),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (alert.urgent)
                      Text(
                        '즉시 확인',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  alert.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.35,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${alert.room} · ${alert.time}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _copyAlert(context),
            icon: const Icon(Icons.copy_rounded, color: AppColors.muted),
          ),
        ],
      ),
    );
  }

  Future<void> _copyAlert(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(
        text:
            '${alert.title}\n위치: ${alert.room}\n시간: ${alert.time}\n내용: ${alert.message}',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('알림 내용을 복사했어요.')));
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(width: 12),
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.text,
              height: 1.4,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _StepData {
  const _StepData(this.number, this.title, this.body);

  final String number;
  final String title;
  final String body;
}
