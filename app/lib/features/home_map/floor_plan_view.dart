import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../shared/ui/app_ui.dart';

const _mapAssetPath = 'assets/images/hanium_two_room_app_map_base.png';
const _mapImageSize = Size(768, 980);
const _planRectInImage = Rect.fromLTWH(137, 86, 440, 792);

class FloorPlanView extends StatelessWidget {
  const FloorPlanView({
    required this.snapshot,
    this.compact = false,
    this.showPath,
    super.key,
  });

  final SafetySnapshot snapshot;
  final bool compact;
  final bool? showPath;

  @override
  Widget build(BuildContext context) {
    final shouldShowPath =
        snapshot.locationSharingEnabled &&
        (showPath ?? snapshot.settingBool('showPath', true));

    return AspectRatio(
      aspectRatio: _mapImageSize.width / _mapImageSize.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final planRect = _scaledPlanRect(size);
          final personPoint = _personPoint(snapshot);
          final personPosition = _toPlanOffset(planRect, personPoint);
          const markerWidth = 118.0;
          const markerHeight = 86.0;

          return ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 24 : 30),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Image.asset(
                    _mapAssetPath,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                if (shouldShowPath)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MovementOverlayPainter(
                        planRect: planRect,
                        path: _movementPath(snapshot),
                        color: statusColor(snapshot.status),
                      ),
                    ),
                  ),
                if (snapshot.locationSharingEnabled)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 120),
                    curve: Curves.easeOutCubic,
                    left: (personPosition.dx - markerWidth / 2)
                        .clamp(8.0, size.width - markerWidth - 8)
                        .toDouble(),
                    top: (personPosition.dy - markerHeight * 0.64)
                        .clamp(8.0, size.height - markerHeight - 8)
                        .toDouble(),
                    child: SizedBox(
                      width: markerWidth,
                      height: markerHeight,
                      child: MiniPersonMarker(snapshot: snapshot),
                    ),
                  ),
                if (!snapshot.locationSharingEnabled)
                  const _LocationHiddenOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }
}

Rect _scaledPlanRect(Size size) {
  return Rect.fromLTWH(
    size.width * (_planRectInImage.left / _mapImageSize.width),
    size.height * (_planRectInImage.top / _mapImageSize.height),
    size.width * (_planRectInImage.width / _mapImageSize.width),
    size.height * (_planRectInImage.height / _mapImageSize.height),
  );
}

Offset _toPlanOffset(Rect planRect, Offset point) {
  final x = point.dx.clamp(0.0, 1.0).toDouble();
  final y = point.dy.clamp(0.0, 1.0).toDouble();
  return Offset(
    planRect.left + planRect.width * x,
    planRect.top + planRect.height * y,
  );
}

Offset _personPoint(SafetySnapshot snapshot) {
  return Offset(
    snapshot.x.clamp(0.0, 1.0).toDouble(),
    snapshot.y.clamp(0.0, 1.0).toDouble(),
  );
}

List<Offset> _movementPath(SafetySnapshot snapshot) {
  final cleaned = snapshot.movementPath
      .map(
        (point) => Offset(
          point.dx.clamp(0.0, 1.0).toDouble(),
          point.dy.clamp(0.0, 1.0).toDouble(),
        ),
      )
      .toList();

  if (cleaned.length >= 2) return cleaned;

  final current = _personPoint(snapshot);
  return [
    Offset(
      (current.dx - 0.22).clamp(0.0, 1.0).toDouble(),
      (current.dy - 0.18).clamp(0.0, 1.0).toDouble(),
    ),
    Offset(
      (current.dx - 0.12).clamp(0.0, 1.0).toDouble(),
      (current.dy - 0.08).clamp(0.0, 1.0).toDouble(),
    ),
    Offset(
      (current.dx - 0.04).clamp(0.0, 1.0).toDouble(),
      (current.dy - 0.02).clamp(0.0, 1.0).toDouble(),
    ),
    current,
  ];
}

class _MovementOverlayPainter extends CustomPainter {
  const _MovementOverlayPainter({
    required this.planRect,
    required this.path,
    required this.color,
  });

  final Rect planRect;
  final List<Offset> path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;

    final points = path.map((point) => _toPlanOffset(planRect, point)).toList();
    _drawTrailEcho(canvas, points);
    _drawDashedTrail(canvas, points);
  }

  void _drawTrailEcho(Canvas canvas, List<Offset> points) {
    for (var i = 0; i < points.length; i++) {
      final progress = (i + 1) / points.length;
      final point = points[i];

      canvas.drawCircle(
        point,
        10 + progress * 12,
        Paint()
          ..color = color.withValues(alpha: 0.035 + progress * 0.08)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        point,
        3.5 + progress * 3.5,
        Paint()
          ..color = color.withValues(alpha: 0.16 + progress * 0.28),
      );
    }
  }

  void _drawDashedTrail(Canvas canvas, List<Offset> points) {
    for (var i = 0; i < points.length - 1; i++) {
      final progress = (i + 1) / (points.length - 1);
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.07 + progress * 0.08)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round;
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.22 + progress * 0.42)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      _drawDashedLine(canvas, points[i], points[i + 1], glowPaint);
      _drawDashedLine(canvas, points[i], points[i + 1], linePaint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final vector = end - start;
    final distance = vector.distance;
    if (distance == 0) return;

    final direction = vector / distance;
    const dash = 9.0;
    const gap = 7.0;
    var current = 0.0;

    while (current < distance) {
      final next = (current + dash).clamp(0.0, distance).toDouble();
      canvas.drawLine(
        start + direction * current,
        start + direction * next,
        paint,
      );
      current += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _MovementOverlayPainter oldDelegate) {
    return oldDelegate.planRect != planRect ||
        oldDelegate.path != path ||
        oldDelegate.color != color;
  }
}

class MiniPersonMarker extends StatelessWidget {
  const MiniPersonMarker({required this.snapshot, super.key});

  final SafetySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final isDanger = snapshot.status == SafetyStatus.danger;
    final color = statusColor(snapshot.status);
    final room = snapshot.room == RoomResolver.unknown
        ? RoomResolver.fromPosition(snapshot.x, snapshot.y)
        : snapshot.room;
    final label = isDanger
        ? '$room · 낙상 의심'
        : '${snapshot.poseLabel} · $room';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.16)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF17213B).withValues(alpha: 0.09),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedRotation(
          turns: isDanger ? 0.25 : 0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 3,
                ),
              ],
            ),
            child: CustomPaint(
              painter: _PersonPainter(color: color, danger: isDanger),
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonPainter extends CustomPainter {
  const _PersonPainter({required this.color, required this.danger});

  final Color color;
  final bool danger;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(
      Offset(center.dx, size.height * 0.25),
      5,
      Paint()..color = color,
    );
    canvas.drawLine(
      Offset(center.dx, size.height * 0.36),
      Offset(center.dx, size.height * 0.62),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, size.height * 0.46),
      Offset(size.width * 0.28, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, size.height * 0.46),
      Offset(size.width * 0.72, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, size.height * 0.62),
      Offset(size.width * 0.34, size.height * 0.82),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx, size.height * 0.62),
      Offset(size.width * 0.66, size.height * 0.82),
      paint,
    );

    if (danger) {
      canvas.drawCircle(
        center,
        size.width * 0.54,
        Paint()..color = color.withValues(alpha: 0.12),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PersonPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.danger != danger;
  }
}

class _LocationHiddenOverlay extends StatelessWidget {
  const _LocationHiddenOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        alignment: Alignment.center,
        color: Colors.white.withValues(alpha: 0.52),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF17213B).withValues(alpha: 0.10),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_off_rounded, color: AppColors.muted),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  '피보호자가 위치 공유를 꺼두었어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
