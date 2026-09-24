import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../shared/ui/app_ui.dart';
import '../home_map/floor_plan_view.dart';

class EventReplayScreen extends StatefulWidget {
  const EventReplayScreen({
    required this.alert,
    required this.baseSnapshot,
    super.key,
  });

  final AlertEvent alert;
  final SafetySnapshot baseSnapshot;

  @override
  State<EventReplayScreen> createState() => _EventReplayScreenState();
}

class _EventReplayScreenState extends State<EventReplayScreen> {
  static const _frameInterval = Duration(milliseconds: 70);

  late final List<_ReplayFrame> _frames;
  Timer? _timer;
  int _index = 0;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _frames = _ReplayFrame.buildFor(widget.alert, widget.baseSnapshot);
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    if (!_playing) return;
    _timer = Timer.periodic(_frameInterval, (_) {
      if (!mounted) return;
      setState(() {
        if (_index >= _frames.length - 1) {
          _playing = false;
          _timer?.cancel();
        } else {
          _index += 1;
        }
      });
    });
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    _start();
  }

  void _restart() {
    setState(() {
      _index = 0;
      _playing = true;
    });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frames[_index];
    final replaySnapshot = _snapshotForFrame(frame);
    final color = statusColor(frame.status);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ScreenScaffold(
        title: '상황 재연',
        subtitle: '알림 발생 흐름을 15프레임으로 다시 확인해요',
        trailing: IconButton.filled(
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primaryDark,
          ),
          icon: const Icon(Icons.close_rounded),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            _ReplaySummaryCard(alert: widget.alert, frame: frame),
            const SizedBox(height: 14),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _ReplayStatusPill(
                          color: color,
                          label: frame.label,
                          timeLabel: frame.timeLabel,
                          frameLabel: '${_index + 1}/${_frames.length}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _RoundReplayButton(
                        icon: _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        onTap: _togglePlay,
                      ),
                      const SizedBox(width: 8),
                      _RoundReplayButton(
                        icon: Icons.replay_rounded,
                        onTap: _restart,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ReplayProgressBar(frames: _frames, currentIndex: _index),
                  const SizedBox(height: 14),
                  FloorPlanView(snapshot: replaySnapshot, showPath: true),
                  const SizedBox(height: 12),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: color,
                      inactiveTrackColor: color.withValues(alpha: 0.16),
                      thumbColor: color,
                      overlayColor: color.withValues(alpha: 0.12),
                    ),
                    child: Slider(
                      value: _index.toDouble(),
                      min: 0,
                      max: (_frames.length - 1).toDouble(),
                      divisions: _frames.length - 1,
                      onChanged: (value) {
                        setState(() {
                          _index = value.round();
                          _playing = false;
                        });
                        _timer?.cancel();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SectionTitle('재연 해석'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    frame.description,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 17,
                      height: 1.45,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReplayMetricRow(frame: frame, alert: widget.alert),
                ],
              ),
            ),
            const SectionTitle('보호자 확인 순서'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  _CheckStep(
                    number: 1,
                    icon: Icons.map_rounded,
                    title: '도면에서 위치 확인',
                    body: '${widget.alert.room} 근처에서 발생한 흐름인지 먼저 확인해요.',
                    color: AppColors.primary,
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  _CheckStep(
                    number: 2,
                    icon: Icons.call_rounded,
                    title: '응답 여부 확인',
                    body: '전화나 메시지로 피보호자의 상태를 확인해요.',
                    color: AppColors.warning,
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  _CheckStep(
                    number: 3,
                    icon: Icons.local_hospital_rounded,
                    title: widget.alert.status == SafetyStatus.danger
                        ? '즉각 조치 판단'
                        : '추가 변화 관찰',
                    body: widget.alert.status == SafetyStatus.danger
                        ? '응답이 없거나 낙상이 의심되면 119 신고 정보를 확인해요.'
                        : '같은 알림이 반복되면 위험 단계로 보고 다시 확인해요.',
                    color: widget.alert.status == SafetyStatus.danger
                        ? AppColors.danger
                        : AppColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  SafetySnapshot _snapshotForFrame(_ReplayFrame frame) {
    final visiblePath = _frames
        .take(_index + 1)
        .map((frame) => frame.point)
        .toList();
    return widget.baseSnapshot.copyWith(
      status: frame.status,
      room: RoomResolver.fromPosition(frame.point.dx, frame.point.dy),
      pose: poseFromStatus(frame.status),
      x: frame.point.dx,
      y: frame.point.dy,
      confidence: frame.confidence,
      lastUpdated: DateTime.now(),
      movementPath: visiblePath,
    );
  }
}

class _ReplaySummaryCard extends StatelessWidget {
  const _ReplaySummaryCard({required this.alert, required this.frame});

  final AlertEvent alert;
  final _ReplayFrame frame;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(alert.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [statusSoftColor(alert.status), Colors.white],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon(alert.status), color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${alert.room} · ${alert.time}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  frame.description,
                  style: const TextStyle(
                    color: AppColors.text,
                    height: 1.42,
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

class _ReplayStatusPill extends StatelessWidget {
  const _ReplayStatusPill({
    required this.color,
    required this.label,
    required this.timeLabel,
    required this.frameLabel,
  });

  final Color color;
  final String label;
  final String timeLabel;
  final String frameLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.movie_filter_rounded, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$timeLabel · $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            frameLabel,
            style: TextStyle(
              color: color.withValues(alpha: 0.78),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundReplayButton extends StatelessWidget {
  const _RoundReplayButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        width: 42,
        height: 42,
        decoration: const BoxDecoration(
          color: AppColors.primarySoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primary),
      ),
    );
  }
}

class _ReplayProgressBar extends StatelessWidget {
  const _ReplayProgressBar({required this.frames, required this.currentIndex});

  final List<_ReplayFrame> frames;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < frames.length; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: i == currentIndex ? 10 : 7,
              decoration: BoxDecoration(
                color: i <= currentIndex
                    ? statusColor(
                        frames[i].status,
                      ).withValues(alpha: i == currentIndex ? 1 : 0.36)
                    : AppColors.primarySoft,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i != frames.length - 1) const SizedBox(width: 3),
        ],
      ],
    );
  }
}

class _ReplayMetricRow extends StatelessWidget {
  const _ReplayMetricRow({required this.frame, required this.alert});

  final _ReplayFrame frame;
  final AlertEvent alert;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MetricPill(
          icon: Icons.place_rounded,
          label: '위치',
          value: RoomResolver.fromPosition(frame.point.dx, frame.point.dy),
          color: AppColors.primary,
        ),
        _MetricPill(
          icon: Icons.timeline_rounded,
          label: '프레임',
          value: '${frame.index + 1}/15',
          color: AppColors.success,
        ),
        _MetricPill(
          icon: Icons.verified_rounded,
          label: '신뢰도',
          value: '${(frame.confidence * 100).round()}%',
          color: statusColor(alert.status),
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            '$label · $value',
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

class _CheckStep extends StatelessWidget {
  const _CheckStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final int number;
  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$number',
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  body,
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
      ),
    );
  }
}

class _ReplayFrame {
  const _ReplayFrame({
    required this.index,
    required this.label,
    required this.description,
    required this.timeLabel,
    required this.status,
    required this.point,
    required this.confidence,
  });

  final int index;
  final String label;
  final String description;
  final String timeLabel;
  final SafetyStatus status;
  final Offset point;
  final double confidence;

  static List<_ReplayFrame> buildFor(AlertEvent alert, SafetySnapshot base) {
    final target = _targetPoint(alert, base);
    final start = Offset(
      (target.dx - 0.24).clamp(0.10, 0.88).toDouble(),
      (target.dy - 0.20).clamp(0.10, 0.88).toDouble(),
    );
    final isDanger = alert.status == SafetyStatus.danger;
    final attentionStatus = isDanger ? SafetyStatus.out : alert.status;

    return [
      for (var i = 0; i < 15; i++)
        _ReplayFrame(
          index: i,
          label: _labelFor(i, alert),
          description: _descriptionFor(i, alert),
          timeLabel: _timeLabelFor(i),
          status: i < 8
              ? SafetyStatus.normal
              : i < 12
              ? attentionStatus
              : alert.status,
          point: Offset.lerp(start, target, _easeOutCubic(i / 14))!,
          confidence: (0.76 + (i / 14) * (isDanger ? 0.17 : 0.11))
              .clamp(0.0, 0.98)
              .toDouble(),
        ),
    ];
  }

  static String _labelFor(int index, AlertEvent alert) {
    if (index < 8) return '평소 이동';
    if (index < 12) {
      return alert.status == SafetyStatus.danger ? '급격한 변화' : '주의 변화';
    }
    return alert.status == SafetyStatus.normal ? '정상 확인' : alert.title;
  }

  static String _descriptionFor(int index, AlertEvent alert) {
    if (index < 8) {
      return '평소 생활 움직임과 유사한 이동 흐름이 확인되는 구간이에요.';
    }
    if (index < 12) {
      return alert.status == SafetyStatus.danger
          ? '짧은 시간 안에 움직임 패턴이 크게 변해 위험 후보로 올라간 구간이에요.'
          : '평소와 다른 위치 변화가 감지되어 주의 단계로 넘어가는 구간이에요.';
    }
    return alert.message;
  }

  static String _timeLabelFor(int index) {
    final seconds = 14 - index;
    if (seconds == 0) return '발생 시점';
    return '발생 $seconds초 전';
  }

  static double _easeOutCubic(double value) {
    final inverted = 1 - value;
    return 1 - inverted * inverted * inverted;
  }

  static Offset _targetPoint(AlertEvent alert, SafetySnapshot base) {
    if (alert.room == RoomResolver.bedroom2) return const Offset(0.25, 0.18);
    if (alert.room == RoomResolver.kitchen) return const Offset(0.73, 0.17);
    if (alert.room == RoomResolver.living) return const Offset(0.32, 0.44);
    if (alert.room == RoomResolver.bathroom) return const Offset(0.64, 0.44);
    if (alert.room == RoomResolver.bedroom) return const Offset(0.30, 0.78);
    if (alert.room == RoomResolver.entrance) return const Offset(0.78, 0.76);

    return Offset(
      base.x.clamp(0.10, 0.90).toDouble(),
      base.y.clamp(0.10, 0.90).toDouble(),
    );
  }
}
