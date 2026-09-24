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
          subtitle: '${snapshot.careTarget?.name ?? '어르신'} · 생활 상태 요약',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextScaleButton(
                enabled: snapshot.settingBool('largeTextMode', false),
                onTap: () {
                  controller.updateSetting(
                    'largeTextMode',
                    !snapshot.settingBool('largeTextMode', false),
                  );
                },
              ),
              const SizedBox(width: 8),
              _ProfileBadge(snapshot: snapshot, onTap: onOpenSettings),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              if (!snapshot.serverConnected) ...[
                _ConnectionNoticeCard(snapshot: snapshot),
                const SizedBox(height: 14),
              ],
              SectionTitle(
                '상태 기준',
                trailing: TapHintLabel(
                  icon: Icons.info_outline_rounded,
                  label: '상태 설명',
                  onTap: () => _showStatusGuide(context, snapshot.status),
                ),
              ),
              _GuardianLevelGuide(
                status: snapshot.status,
                onGuideTap: (guideStatus) =>
                    _showStatusGuide(context, guideStatus),
              ),
              const SectionTitle('오늘의 안심 요약'),
              _DailySummary(snapshot: snapshot, onOpenMap: onOpenMap),
              const SectionTitle('빠른 연락'),
              _QuickContactCard(snapshot: snapshot, onOpenAlerts: onOpenAlerts),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showStatusGuide(BuildContext context, SafetyStatus status) {
    final guide = _StatusGuideData.from(status);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.text.withValues(alpha: 0.28),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryDark.withValues(alpha: 0.18),
                    blurRadius: 30,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: guide.color.withValues(alpha: 0.13),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(guide.icon, color: guide.color, size: 34),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              guide.title,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 24,
                                height: 1.12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              guide.summary,
                              style: TextStyle(
                                color: guide.color,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    guide.description,
                    style: const TextStyle(
                      color: AppColors.muted,
                      height: 1.48,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: guide.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: guide.color.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          color: guide.color,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            guide.action,
                            style: TextStyle(
                              color: guide.color,
                              height: 1.38,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: '확인했어요',
                    icon: Icons.check_rounded,
                    color: guide.color,
                    onPressed: () => Navigator.of(sheetContext).pop(),
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

class _StatusGuideData {
  const _StatusGuideData({
    required this.title,
    required this.summary,
    required this.description,
    required this.action,
    required this.icon,
    required this.color,
  });

  factory _StatusGuideData.from(SafetyStatus status) {
    return switch (status) {
      SafetyStatus.normal => const _StatusGuideData(
        title: '정상 상태',
        summary: '평소 생활 패턴',
        description:
            '집 안에서 평소와 비슷한 움직임이 확인된 상태예요. 위험 알림이 없으므로 생활 상태만 가볍게 확인하면 돼요.',
        action: '추가 조치 없이 오늘의 안심 요약과 최근 위치만 확인하면 충분해요.',
        icon: Icons.check_rounded,
        color: AppColors.success,
      ),
      SafetyStatus.out => const _StatusGuideData(
        title: '주의 상태',
        summary: '현관 접근 또는 외출 가능성',
        description:
            '현관 쪽 이동처럼 보호자가 한 번 확인하면 좋은 변화가 감지된 상태예요. 위험은 아니지만 위치와 연락 가능 여부를 확인하는 것이 좋아요.',
        action: '집 안 도면에서 위치를 보고, 필요하면 어르신께 짧게 연락해 주세요.',
        icon: Icons.visibility_rounded,
        color: AppColors.warning,
      ),
      SafetyStatus.still => const _StatusGuideData(
        title: '주의 상태',
        summary: '장시간 무반응',
        description:
            '한 위치에서 움직임이 적게 감지된 상태예요. 수면이나 휴식일 수도 있지만, 평소와 다르면 안부 확인이 필요해요.',
        action: '최근 위치와 시간을 확인한 뒤 전화나 메시지로 상태를 확인해 주세요.',
        icon: Icons.event_busy_rounded,
        color: AppColors.warning,
      ),
      SafetyStatus.danger => const _StatusGuideData(
        title: '위험 상태',
        summary: '즉각적인 조치 필요',
        description:
            '낙상 의심처럼 빠른 대응이 필요한 움직임이 감지된 상태예요. 보호자가 먼저 연락하고, 응답이 없으면 신고 정보를 확인해야 해요.',
        action: '어르신께 즉시 연락하고, 응답이 없거나 통증이 있다면 119 신고 정보를 확인해 주세요.',
        icon: Icons.priority_high_rounded,
        color: AppColors.danger,
      ),
    };
  }

  final String title;
  final String summary;
  final String description;
  final String action;
  final IconData icon;
  final Color color;
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
              child: const Icon(Icons.person_rounded, color: AppColors.primary),
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

class _GuardianLevelGuide extends StatelessWidget {
  const _GuardianLevelGuide({required this.status, required this.onGuideTap});

  final SafetyStatus status;
  final ValueChanged<SafetyStatus> onGuideTap;

  @override
  Widget build(BuildContext context) {
    final displayStatus = status;
    final guide = _StatusGuideData.from(displayStatus);
    final title = switch (displayStatus) {
      SafetyStatus.normal => '정상',
      SafetyStatus.out || SafetyStatus.still => '주의',
      SafetyStatus.danger => '위험',
    };
    final body = switch (displayStatus) {
      SafetyStatus.normal => '평소 패턴',
      SafetyStatus.out => '현관 접근',
      SafetyStatus.still => '무반응',
      SafetyStatus.danger => '낙상 의심',
    };
    final action = switch (displayStatus) {
      SafetyStatus.normal => '생활 확인',
      SafetyStatus.out => '위치 확인',
      SafetyStatus.still => '안부 확인',
      SafetyStatus.danger => '즉시 조치',
    };

    return _LevelGuideChip(
      color: guide.color,
      icon: guide.icon,
      title: title,
      body: body,
      action: action,
      onTap: () => onGuideTap(displayStatus),
    );
  }
}

class _LevelGuideChip extends StatelessWidget {
  const _LevelGuideChip({
    required this.color,
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: double.infinity,
        constraints: BoxConstraints(minHeight: largeText ? 158 : 130),
        padding: EdgeInsets.fromLTRB(20, largeText ? 18 : 20, 18, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.18),
              color.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withValues(alpha: 0.34)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.13),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: largeText ? 58 : 62,
              height: largeText ? 58 : 62,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.72),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.13),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: largeText ? 32 : 34),
            ),
            SizedBox(width: largeText ? 14 : 18),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 30,
                          height: 1.02,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.76),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: color.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          '현재 단계',
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    maxLines: largeText ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 16,
                      height: 1.28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.82),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: color.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.info_outline_rounded, color: color, size: 15),
                        const SizedBox(width: 5),
                        Text(
                          largeText ? '설명 보기' : '$action · 설명 보기',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
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
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: color.withValues(alpha: 0.72),
              size: 30,
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
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    final title = snapshot.needsAttention
        ? (largeText ? '확인이 필요해요' : '확인이 필요한 변화가 있어요')
        : (largeText ? '평소와 비슷해요' : '평소와 비슷한 하루예요');
    final body = snapshot.needsAttention
        ? (largeText
              ? '도면에서 위치와 이동을 확인해 주세요.'
              : '도면에서 위치와 최근 이동 흐름을 먼저 확인해 주세요.')
        : (largeText
              ? '위험 알림 없이 안전하게 지내고 있어요.'
              : '위험 알림 없이 안정적인 생활 흐름이 확인되고 있어요.');

    return AppCard(
      onTap: onOpenMap,
      padding: EdgeInsets.all(largeText ? 18 : 20),
      child: largeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _SummaryIcon(snapshot: snapshot, color: color, large: true),
                    const Spacer(),
                    _SummaryMetaPill(
                      icon: Icons.map_rounded,
                      label: '도면 보기',
                      color: color,
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: color.withValues(alpha: 0.72),
                      size: 28,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 23,
                    height: 1.16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 16,
                    height: 1.38,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryMetaPill(
                      icon: Icons.place_rounded,
                      label: snapshot.room,
                      color: AppColors.primaryDark,
                    ),
                    _SummaryMetaPill(
                      icon: Icons.schedule_rounded,
                      label: snapshot.lastUpdatedText,
                      color: AppColors.primaryDark,
                    ),
                    _DataSourcePill(snapshot: snapshot),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryIcon(snapshot: snapshot, color: color),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 21,
                          height: 1.18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        body,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 16,
                          height: 1.45,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '최근 확인  ${snapshot.room} · ${snapshot.lastUpdatedText}',
                        style: const TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _DataSourcePill(snapshot: snapshot),
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

class _SummaryIcon extends StatelessWidget {
  const _SummaryIcon({
    required this.snapshot,
    required this.color,
    this.large = false,
  });

  final SafetySnapshot snapshot;
  final Color color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: large ? 48 : 44,
      height: large ? 48 : 44,
      decoration: BoxDecoration(
        color: statusSoftColor(snapshot.status),
        shape: BoxShape.circle,
      ),
      child: Icon(
        statusIcon(snapshot.status),
        color: color,
        size: large ? 27 : 24,
      ),
    );
  }
}

class _SummaryMetaPill extends StatelessWidget {
  const _SummaryMetaPill({
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

class _DataSourcePill extends StatelessWidget {
  const _DataSourcePill({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.isLiveSensorSource
        ? AppColors.success
        : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            snapshot.isLiveSensorSource
                ? Icons.sensors_rounded
                : Icons.play_circle_rounded,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 6),
          Text(
            snapshot.dataSourceLabel,
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

class _ConnectionNoticeCard extends StatelessWidget {
  const _ConnectionNoticeCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.warningSoft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.cloud_sync_rounded,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '마지막 상태를 보여주는 중이에요',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  cleanText(snapshot.connectionNote, '실시간 정보를 다시 확인하고 있어요.'),
                  style: const TextStyle(
                    color: AppColors.muted,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      color: AppColors.warning.withValues(alpha: 0.76),
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        '저장된 마지막 상태를 표시 중',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.1;
    final title = largeText ? '연락이 필요한가요?' : '어르신께 연락이 필요한가요?';
    final body = largeText ? '전화와 알림 화면을 바로 열어요.' : '등록된 번호로 바로 연결해요.';

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 15,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (largeText)
            Column(
              children: [
                GhostButton(
                  label: '전화하기',
                  icon: Icons.call_rounded,
                  onPressed: () => _dial(context, target?.phone ?? ''),
                ),
                const SizedBox(height: 10),
                PrimaryButton(
                  label: '알림 보기',
                  icon: Icons.notifications_rounded,
                  color: statusColor(snapshot.status),
                  onPressed: onOpenAlerts,
                ),
              ],
            )
          else
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
