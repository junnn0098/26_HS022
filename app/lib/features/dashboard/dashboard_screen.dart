import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/emergency_actions.dart';
import '../../core/state/safety_controller.dart';
import '../../shared/ui/app_ui.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.controller,
    required this.onOpenMap,
    required this.onOpenAlerts,
    required this.onOpenSettings,
    super.key,
  });

  final SafetyController controller;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return ScreenScaffold(
          title: '지금 상태를\n확인했어요',
          subtitle: '${snapshot.careTarget?.name ?? '어르신'} · 보호자용 안심 요약',
          trailing: _ProfileBadge(snapshot: snapshot, onTap: onOpenSettings),
          child: Column(
            children: [
              const SizedBox(height: 12),
              _HeroStatusCard(
                snapshot: snapshot,
                onPrimary: snapshot.isDanger ? onOpenAlerts : onOpenMap,
              ),
              const SectionTitle('상태 기준'),
              _GuardianLevelGuide(
                status: snapshot.status,
                onOpenAlerts: onOpenAlerts,
              ),
              const SectionTitle('오늘의 안심 요약'),
              _DailySummary(snapshot: snapshot, onOpenMap: onOpenMap),
              const SectionTitle('빠른 연락'),
              _QuickContactCard(snapshot: snapshot, onOpenAlerts: onOpenAlerts),
              const SectionTitle('최근 알림'),
              _RecentAlert(snapshot: snapshot, onOpenAlerts: onOpenAlerts),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({required this.snapshot, required this.onTap});

  final SafetySnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '설정 보기',
      child: PressableScale(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: AppColors.primary,
              ),
            ),
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: statusColor(snapshot.status),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({required this.snapshot, required this.onPrimary});

  final SafetySnapshot snapshot;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    final gradient = snapshot.isDanger
        ? const [AppColors.danger, Color(0xFFFF7D90)]
        : snapshot.needsAttention
        ? const [AppColors.warning, Color(0xFFFFC46B)]
        : const [Color(0xFF43D39E), Color(0xFF20B983)];

    return PressableScale(
      onTap: onPrimary,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
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
                    color: Colors.white.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    statusIcon(snapshot.status),
                    color: Colors.white,
                    size: 34,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    snapshot.lastUpdatedText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              snapshot.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                height: 1.15,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              snapshot.subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                height: 1.45,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _HeroDecisionStrip(snapshot: snapshot),
            const SizedBox(height: 22),
            Row(
              children: [
                _WhitePill(
                  icon: Icons.place_rounded,
                  label: '${snapshot.room} · ${snapshot.poseLabel} 상태',
                ),
                const SizedBox(width: 8),
                _WhitePill(
                  icon: Icons.verified_rounded,
                  label: '확인 수준 ${snapshot.confidenceLabel}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onPrimary,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: color,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Text(
                snapshot.actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroDecisionStrip extends StatelessWidget {
  const _HeroDecisionStrip({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon(snapshot.status), color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${snapshot.levelLabel} · ${snapshot.levelSummary}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot.recommendedAction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
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

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardianLevelGuide extends StatelessWidget {
  const _GuardianLevelGuide({
    required this.status,
    required this.onOpenAlerts,
  });

  final SafetyStatus status;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LevelGuideChip(
            active: status == SafetyStatus.normal,
            color: AppColors.success,
            icon: Icons.check_rounded,
            title: '정상',
            body: '평소 패턴',
            onTap: onOpenAlerts,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LevelGuideChip(
            active: status == SafetyStatus.out || status == SafetyStatus.still,
            color: AppColors.warning,
            icon: Icons.visibility_rounded,
            title: '주의',
            body: '확인 필요',
            onTap: onOpenAlerts,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LevelGuideChip(
            active: status == SafetyStatus.danger,
            color: AppColors.danger,
            icon: Icons.priority_high_rounded,
            title: '위험',
            body: '즉시 조치',
            onTap: onOpenAlerts,
          ),
        ),
      ],
    );
  }
}

class _LevelGuideChip extends StatelessWidget {
  const _LevelGuideChip({
    required this.active,
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool active;
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.36) : AppColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: active ? 0.18 : 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailySummary extends StatelessWidget {
  const _DailySummary({required this.snapshot, required this.onOpenMap});

  final SafetySnapshot snapshot;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    return AppCard(
      onTap: onOpenMap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: statusSoftColor(snapshot.status),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon(snapshot.status), color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.needsAttention ? '확인이 필요한 변화가 있어요' : '평소와 비슷한 하루예요',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.needsAttention
                      ? '어디에서 어떤 변화가 있었는지 먼저 확인해 주세요.'
                      : '확인이 필요한 위험 알림 없이 생활 흐름이 안정적이에요.',
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '최근 확인  ${snapshot.room} · ${snapshot.lastUpdatedText}',
                  style: const TextStyle(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}

class _QuickContactCard extends StatelessWidget {
  const _QuickContactCard({required this.snapshot, required this.onOpenAlerts});

  final SafetySnapshot snapshot;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final target = snapshot.careTarget;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.phone_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '어르신께 연락이 필요한가요?',
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '등록된 번호로 바로 연결해요.',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GhostButton(
                  label: '전화하기',
                  icon: Icons.call_rounded,
                  onPressed: () => _dial(context, target?.phone ?? ''),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PrimaryButton(
                  label: '알림 보기',
                  icon: Icons.notifications_rounded,
                  color: statusColor(snapshot.status),
                  onPressed: onOpenAlerts,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _dial(BuildContext context, String phone) async {
    final ok = await EmergencyActions.dial(phone);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '전화 앱을 열었어요.' : '전화 앱을 열 수 없어요. 연락처를 확인해 주세요.'),
      ),
    );
  }
}

class _RecentAlert extends StatelessWidget {
  const _RecentAlert({required this.snapshot, required this.onOpenAlerts});

  final SafetySnapshot snapshot;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final alert = snapshot.alerts.isEmpty ? null : snapshot.alerts.first;
    if (alert == null) {
      return AppCard(
        child: Text(
          '아직 알림이 없어요.',
          style: TextStyle(color: AppColors.muted.withValues(alpha: 0.9)),
        ),
      );
    }

    final color = statusColor(alert.status);
    return AppCard(
      onTap: onOpenAlerts,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusSoftColor(alert.status),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon(alert.status), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${alert.room} · ${alert.time}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    );
  }
}
