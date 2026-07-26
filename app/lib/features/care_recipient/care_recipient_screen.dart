import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../core/services/emergency_actions.dart';
import '../../core/state/safety_controller.dart';
import '../../shared/ui/app_ui.dart';
import '../home_map/floor_plan_view.dart';

class CareRecipientScreen extends StatefulWidget {
  const CareRecipientScreen({
    required this.controller,
    required this.onSwitchRole,
    super.key,
  });

  final SafetyController controller;
  final VoidCallback onSwitchRole;

  @override
  State<CareRecipientScreen> createState() => _CareRecipientScreenState();
}

class _CareRecipientScreenState extends State<CareRecipientScreen> {
  final _actionKey = GlobalKey();
  final _locationKey = GlobalKey();
  final _tipsKey = GlobalKey();

  bool _showDetailMap = false;

  void _scrollTo(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = key.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _openLocationSection() {
    setState(() {
      _showDetailMap = true;
    });
    widget.controller.updateSetting('locationSharingEnabled', true);
    _scrollTo(_locationKey);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final snapshot = widget.controller.snapshot;
        final rhythm = _LifeRhythm.from(snapshot);
        final shareLocation = snapshot.locationSharingEnabled;

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'switch-to-guardian',
            onPressed: widget.onSwitchRole,
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('보호자 모드'),
          ),
          body: ScreenScaffold(
            title: '내 안전 상태',
            subtitle: '위치 공유와 도움 요청을 직접 관리해요',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                _MoodHero(
                  snapshot: snapshot,
                  rhythm: rhythm,
                  onLocationTap: _openLocationSection,
                  onStatusTap: () => _scrollTo(_actionKey),
                  onPoseTap: () => _scrollTo(_tipsKey),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _actionKey,
                  child: _ImmediateActionCard(
                    snapshot: snapshot,
                    rhythm: rhythm,
                  ),
                ),
                KeyedSubtree(
                  key: _locationKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('위치 공유'),
                      _LocationShareCard(
                        snapshot: snapshot,
                        shareLocation: shareLocation,
                        showDetailMap: _showDetailMap,
                        onShareChanged: (value) {
                          setState(() {
                            if (!value) _showDetailMap = false;
                          });
                          widget.controller.updateSetting(
                            'locationSharingEnabled',
                            value,
                          );
                        },
                        onToggleMap: () =>
                            setState(() => _showDetailMap = !_showDetailMap),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: shareLocation && _showDetailMap
                            ? Padding(
                                key: const ValueKey('care-location-map'),
                                padding: const EdgeInsets.only(top: 12),
                                child: FloorPlanView(
                                  snapshot: snapshot,
                                  compact: true,
                                  showPath: false,
                                ),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('hidden-map'),
                              ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('오늘의 한 줄'),
                _LifeDiaryCard(rhythm: rhythm),
                KeyedSubtree(
                  key: _tipsKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionTitle('오늘 챙길 것'),
                      _CareTipsCard(rhythm: rhythm),
                    ],
                  ),
                ),
                const SectionTitle('도움이 필요할 때'),
                _GuardianSupportCard(
                  snapshot: snapshot,
                  onMarkSafe: widget.controller.notifyCareRecipientSafe,
                ),
                const SizedBox(height: 82),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MoodHero extends StatelessWidget {
  const _MoodHero({
    required this.snapshot,
    required this.rhythm,
    required this.onLocationTap,
    required this.onStatusTap,
    required this.onPoseTap,
  });

  final SafetySnapshot snapshot;
  final _LifeRhythm rhythm;
  final VoidCallback onLocationTap;
  final VoidCallback onStatusTap;
  final VoidCallback onPoseTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _heroGradient(snapshot.status),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -28,
              top: -42,
              child: Container(
                width: 142,
                height: 142,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(
                        statusIcon(snapshot.status),
                        color: Colors.white,
                        size: 36,
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
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  rhythm.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 29,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 11),
                Text(
                  rhythm.message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    height: 1.46,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(
                      icon: Icons.place_rounded,
                      label: snapshot.room,
                      onTap: onLocationTap,
                    ),
                    _HeroChip(
                      icon: statusIcon(snapshot.status),
                      label: rhythm.badge,
                      onTap: onStatusTap,
                    ),
                    _HeroChip(
                      icon: Icons.person_pin_circle_rounded,
                      label: '${snapshot.poseLabel} 상태',
                      onTap: onPoseTap,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withValues(alpha: 0.86),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _ImmediateActionCard extends StatelessWidget {
  const _ImmediateActionCard({
    required this.snapshot,
    required this.rhythm,
  });

  final SafetySnapshot snapshot;
  final _LifeRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(snapshot.status);
    return AppCard(
      color: statusSoftColor(snapshot.status),
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(rhythm.actionIcon, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rhythm.actionTitle,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  rhythm.actionMessage,
                  style: const TextStyle(
                    color: AppColors.text,
                    height: 1.42,
                    fontWeight: FontWeight.w800,
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

class _LocationShareCard extends StatelessWidget {
  const _LocationShareCard({
    required this.snapshot,
    required this.shareLocation,
    required this.showDetailMap,
    required this.onShareChanged,
    required this.onToggleMap,
  });

  final SafetySnapshot snapshot;
  final bool shareLocation;
  final bool showDetailMap;
  final ValueChanged<bool> onShareChanged;
  final VoidCallback onToggleMap;

  @override
  Widget build(BuildContext context) {
    final color = shareLocation ? AppColors.success : AppColors.warning;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: shareLocation
                      ? AppColors.successSoft
                      : AppColors.warningSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  shareLocation
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shareLocation ? '위치 공유가 켜져 있어요' : '위치 공유가 꺼져 있어요',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      shareLocation
                          ? '도움이 필요할 때 보호자가 현재 위치를 빠르게 확인할 수 있어요.'
                          : '위급할 때 보호자가 위치를 바로 확인하기 어려울 수 있어요.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.38,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(value: shareLocation, onChanged: onShareChanged),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                _ShareInfoRow(
                  icon: Icons.home_rounded,
                  title: shareLocation ? '지금 위치' : '현재 상태',
                  value: shareLocation ? snapshot.room : '공유 꺼짐',
                ),
                const Divider(height: 20, color: AppColors.border),
                const _ShareInfoRow(
                  icon: Icons.notifications_active_rounded,
                  title: '공유 내용',
                  value: '위치 · 위험 · 괜찮음',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: shareLocation ? onToggleMap : null,
              icon: Icon(
                showDetailMap ? Icons.expand_less_rounded : Icons.map_rounded,
              ),
              label: Text(showDetailMap ? '내 위치 닫기' : '내 위치 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareInfoRow extends StatelessWidget {
  const _ShareInfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 10),
        Flexible(
          flex: 5,
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _LifeDiaryCard extends StatelessWidget {
  const _LifeDiaryCard({required this.rhythm});

  final _LifeRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘의 생활 메모',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  rhythm.diary,
                  style: const TextStyle(
                    color: AppColors.text,
                    height: 1.52,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
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

class _CareTipsCard extends StatelessWidget {
  const _CareTipsCard({required this.rhythm});

  final _LifeRhythm rhythm;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < rhythm.tips.length; i++) ...[
            _CareTipRow(index: i + 1, text: rhythm.tips[i]),
            if (i != rhythm.tips.length - 1)
              const Divider(height: 22, color: AppColors.border),
          ],
        ],
      ),
    );
  }
}

class _CareTipRow extends StatelessWidget {
  const _CareTipRow({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.text,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GuardianSupportCard extends StatelessWidget {
  const _GuardianSupportCard({
    required this.snapshot,
    required this.onMarkSafe,
  });

  final SafetySnapshot snapshot;
  final Future<void> Function() onMarkSafe;

  Future<void> _callPhone(
    BuildContext context,
    String phone, {
    required String errorMessage,
  }) async {
    final ok = await EmergencyActions.dial(phone);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
    }
  }

  Future<void> _callGuardian(BuildContext context) async {
    final guardian = snapshot.primaryGuardian;
    final phone = guardian?.phone ?? '';
    await _callPhone(
      context,
      phone,
      errorMessage: '등록된 보호자 전화번호를 확인해 주세요.',
    );
  }

  Future<void> _callEmergency(BuildContext context) async {
    await _callPhone(
      context,
      '119',
      errorMessage: '전화 앱을 열 수 없어요. 직접 119에 전화해 주세요.',
    );
  }

  Future<void> _markSafe(BuildContext context) async {
    await onMarkSafe();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('괜찮다고 보호자에게 알렸어요.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guardian = snapshot.primaryGuardian;
    final isDanger = snapshot.isDanger;
    return AppCard(
      color: isDanger ? AppColors.dangerSoft : AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isDanger ? Colors.white : AppColors.dangerSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  isDanger ? Icons.local_hospital_rounded : Icons.favorite_rounded,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDanger ? '위급하면 바로 도움을 요청하세요' : '혼자 해결하지 않아도 돼요',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      guardian == null
                          ? '보호자 연락처를 등록하면 바로 연결할 수 있어요.'
                          : '${guardian.name}에게 바로 연락할 수 있어요.',
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
          const SizedBox(height: 18),
          if (isDanger) ...[
            PrimaryButton(
              label: '119에 전화하기',
              icon: Icons.local_phone_rounded,
              color: AppColors.danger,
              onPressed: () => _callEmergency(context),
            ),
            const SizedBox(height: 10),
          ],
          PrimaryButton(
            label: '보호자에게 전화하기',
            icon: Icons.call_rounded,
            onPressed: () => _callGuardian(context),
          ),
          const SizedBox(height: 10),
          GhostButton(
            label: '괜찮다고 알리기',
            icon: Icons.check_circle_rounded,
            onPressed: () => _markSafe(context),
          ),
        ],
      ),
    );
  }
}

class _LifeRhythm {
  const _LifeRhythm({
    required this.title,
    required this.message,
    required this.diary,
    required this.badge,
    required this.actionTitle,
    required this.actionMessage,
    required this.actionIcon,
    required this.tips,
  });

  final String title;
  final String message;
  final String diary;
  final String badge;
  final String actionTitle;
  final String actionMessage;
  final IconData actionIcon;
  final List<String> tips;

  factory _LifeRhythm.from(SafetySnapshot snapshot) {
    if (snapshot.status == SafetyStatus.danger) {
      return _LifeRhythm(
        title: '잠시 멈춰서 확인해요',
        message: '${snapshot.room}에서 평소와 다른 움직임이 확인됐어요. 보호자에게도 알려졌어요.',
        diary:
            '오늘 ${snapshot.room}에서 갑작스러운 움직임 변화가 있었어요. 무리해서 바로 일어나지 말고 몸 상태를 먼저 확인해 주세요.',
        badge: '도움 필요',
        actionTitle: '지금은 무리하지 마세요',
        actionMessage: '통증이 있거나 어지러우면 바로 보호자나 119에 연락해 주세요.',
        actionIcon: Icons.warning_rounded,
        tips: const [
          '바로 일어나지 말고 잠시 앉거나 누운 상태로 몸 상태를 확인해요.',
          '통증, 어지러움, 숨참이 있으면 보호자에게 바로 전화해요.',
          '혼자 움직이기 어렵다면 119 도움을 요청해요.',
        ],
      );
    }

    if (snapshot.status == SafetyStatus.still) {
      return _LifeRhythm(
        title: '쉬는 시간이 길었어요',
        message: '${snapshot.room}에서 움직임이 적게 확인됐어요. 몸은 괜찮으신가요?',
        diary: '오늘은 활동량이 조금 낮게 보였어요. 물 한 잔 마시고 천천히 몸을 움직여 보면 좋아요.',
        badge: '천천히 확인',
        actionTitle: '천천히 몸 상태를 봐요',
        actionMessage: '갑자기 일어나지 말고, 괜찮으면 가볍게 움직여 주세요.',
        actionIcon: Icons.self_improvement_rounded,
        tips: const [
          '갑자기 일어나지 말고 천천히 몸을 움직여요.',
          '물 한 잔을 마시고 몸 상태를 확인해요.',
          '불편함이 계속되면 보호자에게 알려요.',
        ],
      );
    }

    if (snapshot.status == SafetyStatus.out) {
      return _LifeRhythm(
        title: '현관 쪽 움직임이 있었어요',
        message: '외출 전후 움직임처럼 보이는 상태가 확인됐어요.',
        diary: '오늘은 현관 쪽 이동이 확인됐어요. 외출 전이라면 문단속과 소지품을 한 번 확인해 주세요.',
        badge: '외출 확인',
        actionTitle: '문단속을 한 번 확인해요',
        actionMessage: '외출 중이면 보호자에게 귀가 시간을 알려두면 좋아요.',
        actionIcon: Icons.door_front_door_rounded,
        tips: const [
          '외출 전이라면 문단속과 소지품을 확인해요.',
          '외출 후라면 휴대폰과 열쇠를 챙겼는지 확인해요.',
          '낯선 사람이 있거나 불안하면 바로 도움을 요청해요.',
        ],
      );
    }

    return _LifeRhythm(
      title: '평소와 비슷해요',
      message: '${snapshot.room}에서 안정적인 생활 움직임이 확인됐어요.',
      diary:
          '오늘은 평소와 비슷한 리듬으로 움직이고 있어요. 특별히 확인할 위험 알림 없이 안정적인 하루예요.',
      badge: '안정적',
      actionTitle: '평소처럼 지내도 괜찮아요',
      actionMessage: '위치 공유를 켜 두면 도움이 필요할 때 보호자가 빠르게 확인할 수 있어요.',
      actionIcon: Icons.check_circle_rounded,
      tips: const [
        '평소처럼 생활하셔도 괜찮아요.',
        '가볍게 스트레칭하고 물을 챙겨 마시면 좋아요.',
        '위치 공유를 켜 두면 위험 상황 때 보호자가 빠르게 확인할 수 있어요.',
      ],
    );
  }
}

List<Color> _heroGradient(SafetyStatus status) {
  return switch (status) {
    SafetyStatus.danger => const [AppColors.danger, Color(0xFFFF8DA0)],
    SafetyStatus.out => const [Color(0xFFFFB648), Color(0xFFFB7185)],
    SafetyStatus.still => const [Color(0xFFF59E0B), Color(0xFF8B5CF6)],
    SafetyStatus.normal => const [Color(0xFF25C184), Color(0xFF5B6CF6)],
  };
}
