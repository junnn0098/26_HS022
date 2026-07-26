import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../core/state/safety_controller.dart';
import '../../shared/ui/app_ui.dart';
import 'floor_plan_view.dart';

class HomeMapScreen extends StatelessWidget {
  const HomeMapScreen({required this.controller, super.key});

  final SafetyController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FigmaHeader(snapshot: snapshot),
                const SizedBox(height: 18),
                _FigmaMapCard(
                  snapshot: snapshot,
                  onRefresh: controller.refreshAll,
                  onExpand: () => _showExpandedMap(context),
                  onGuide: () => _showMapGuide(context),
                ),
                const SizedBox(height: 16),
                _FigmaStatusCard(snapshot: snapshot),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMapGuide(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '집 안 도면 읽는 법',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            SizedBox(height: 12),
            Text(
              '방 구조, 현재 위치, 최근 이동 흐름을 한눈에 보여줘요. '
              '초록 원은 ESP32 수신 노드, 사람 아이콘은 현재 위치, 점선은 최근 움직임이에요.',
              style: TextStyle(height: 1.5, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  void _showExpandedMap(BuildContext context) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '도면 확대 닫기',
      barrierColor: const Color(0xFF0F172A).withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final snapshot = controller.snapshot;
          return SafeArea(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '집 안 도면 확대',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                snapshot.isLocationHidden
                                    ? '현재 위치 공유가 꺼져 있어요'
                                    : '${snapshot.room} · ${snapshot.poseLabel} 상태',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () => Navigator.of(context).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.16,
                            ),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Center(
                        child: Hero(
                          tag: 'home-floor-plan',
                          child: InteractiveViewer(
                            minScale: 0.9,
                            maxScale: 3.2,
                            boundaryMargin: const EdgeInsets.all(80),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: FloorPlanView(snapshot: snapshot),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '손가락으로 확대/축소해서 자세히 볼 수 있어요',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _FigmaHeader extends StatelessWidget {
  const _FigmaHeader({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final badgeLabel = snapshot.isLocationHidden
        ? '위치 비공개'
        : snapshot.isDanger
        ? '확인 필요'
        : snapshot.needsAttention
        ? '확인 필요'
        : '안정적';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '집 안 상태',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 24,
                  height: 1.04,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.isLocationHidden
                    ? '피보호자가 위치 공유를 꺼둔 상태예요'
                    : '${snapshot.careTarget?.name ?? '어르신'} · 위치와 생활 흐름 확인',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        StatusBadge(status: snapshot.status, label: badgeLabel),
      ],
    );
  }
}

class _FigmaMapCard extends StatelessWidget {
  const _FigmaMapCard({
    required this.snapshot,
    required this.onRefresh,
    required this.onExpand,
    required this.onGuide,
  });

  final SafetySnapshot snapshot;
  final VoidCallback onRefresh;
  final VoidCallback onExpand;
  final VoidCallback onGuide;

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFFE7ECF4)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF17213B).withValues(alpha: 0.07),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.my_location_rounded,
                          color: AppColors.primary,
                          size: 17,
                        ),
                        SizedBox(width: 8),
                        Text(
                          '현재 위치 중심',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _CircleAction(icon: Icons.add_rounded, onTap: onRefresh),
                const SizedBox(width: 8),
                _CircleAction(icon: Icons.menu_rounded, onTap: onGuide),
              ],
            ),
            const SizedBox(height: 14),
            PressableScale(
              onTap: onExpand,
              child: Hero(
                tag: 'home-floor-plan',
                child: FloorPlanView(snapshot: snapshot),
              ),
            ),
          ],
        ),
    );
  }
}

class _FigmaStatusCard extends StatelessWidget {
  const _FigmaStatusCard({required this.snapshot});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    final isSafe = snapshot.status == SafetyStatus.normal;
    final displayRoom = snapshot.isLocationHidden
        ? '위치 비공개'
        : RoomResolver.fromPosition(snapshot.x, snapshot.y);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isSafe
            ? const Color(0xFFE8FFF5)
            : statusSoftColor(snapshot.status),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
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
                  isSafe ? '평소와 비슷하게 지내고 있어요' : snapshot.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  snapshot.isLocationHidden
                      ? '피보호자가 현재 위치 공유를 꺼두었어요'
                      : '$displayRoom에서 ${snapshot.poseLabel} 상태 · ${snapshot.lastUpdatedText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12,
                    height: 1.35,
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

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3FA),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF17213B).withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(icon, color: AppColors.primaryDark),
      ),
    );
  }
}
