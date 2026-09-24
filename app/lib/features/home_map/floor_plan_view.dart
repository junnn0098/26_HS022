import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/safety_models.dart';
import '../../shared/ui/app_ui.dart';

const _viewAspectRatio = 0.78;
const _planAspectRatio = 480 / 550;

class FloorPlanView extends StatelessWidget {
  const FloorPlanView({required this.snapshot, this.compact = false, this.showPath, super.key});

  final SafetySnapshot snapshot;
  final bool compact;
  final bool? showPath;

  @override
  Widget build(BuildContext context) {
    final shouldShowPath =
        snapshot.locationSharingEnabled && (showPath ?? snapshot.settingBool('showPath', true));

    return AspectRatio(
      aspectRatio: _viewAspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final planRect = _planRectFor(size, compact: compact);
          final personPoint = _personPoint(snapshot);
          final personPosition = _toPlanOffset(planRect, personPoint);
          const markerSize = 44.0;

          return ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 24 : 30),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FloorPlanPainter(planRect: planRect, compact: compact),
                  ),
                ),
                if (shouldShowPath)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MovementOverlayPainter(
                        planRect: planRect,
                        path: _movementPath(snapshot),
                        color: _trailColor(snapshot.status),
                      ),
                    ),
                  ),
                if (snapshot.locationSharingEnabled)
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    left: (personPosition.dx - markerSize / 2)
                        .clamp(8.0, size.width - markerSize - 8)
                        .toDouble(),
                    top: (personPosition.dy - markerSize / 2)
                        .clamp(8.0, size.height - markerSize - 8)
                        .toDouble(),
                    child: SizedBox(
                      width: markerSize,
                      height: markerSize,
                      child: MiniPersonMarker(snapshot: snapshot),
                    ),
                  ),
                if (!snapshot.locationSharingEnabled) const _LocationHiddenOverlay(),
              ],
            ),
          );
        },
      ),
    );
  }
}

Rect _planRectFor(Size size, {required bool compact}) {
  final horizontalPadding = compact ? 10.0 : 16.0;
  final topPadding = compact ? 10.0 : 16.0;
  final legendHeight = compact ? 30.0 : 38.0;
  final availableWidth = size.width - horizontalPadding * 2;
  final availableHeight = size.height - topPadding * 2 - legendHeight;

  var width = availableWidth;
  var height = width / _planAspectRatio;
  if (height > availableHeight) {
    height = availableHeight;
    width = height * _planAspectRatio;
  }

  return Rect.fromLTWH((size.width - width) / 2, topPadding, width, height);
}

Rect _roomRect(Rect planRect, double x, double y, double w, double h) {
  return Rect.fromLTWH(
    planRect.left + planRect.width * x,
    planRect.top + planRect.height * y,
    planRect.width * w,
    planRect.height * h,
  );
}

Offset _toPlanOffset(Rect planRect, Offset point) {
  final x = point.dx.clamp(0.0, 1.0).toDouble();
  final y = point.dy.clamp(0.0, 1.0).toDouble();
  return Offset(planRect.left + planRect.width * x, planRect.top + planRect.height * y);
}

Offset _personPoint(SafetySnapshot snapshot) {
  return Offset(snapshot.x.clamp(0.0, 1.0).toDouble(), snapshot.y.clamp(0.0, 1.0).toDouble());
}

Color _trailColor(SafetyStatus status) {
  return switch (status) {
    SafetyStatus.normal => const Color(0xFF6178FF),
    SafetyStatus.out => AppColors.warning,
    SafetyStatus.still => const Color(0xFF7C86FF),
    SafetyStatus.danger => AppColors.danger,
  };
}

List<Offset> _movementPath(SafetySnapshot snapshot) {
  final cleaned = snapshot.movementPath
      .map(
        (point) => Offset(point.dx.clamp(0.0, 1.0).toDouble(), point.dy.clamp(0.0, 1.0).toDouble()),
      )
      .toList();

  if (cleaned.length >= 2) {
    const visiblePointCount = 4;
    if (cleaned.length <= visiblePointCount) return cleaned;
    return cleaned.sublist(cleaned.length - visiblePointCount);
  }

  final current = _personPoint(snapshot);
  return [
    Offset(
      (current.dx - 0.16).clamp(0.0, 1.0).toDouble(),
      (current.dy - 0.11).clamp(0.0, 1.0).toDouble(),
    ),
    Offset(
      (current.dx - 0.08).clamp(0.0, 1.0).toDouble(),
      (current.dy - 0.04).clamp(0.0, 1.0).toDouble(),
    ),
    current,
  ];
}

class _FloorPlanPainter extends CustomPainter {
  const _FloorPlanPainter({required this.planRect, required this.compact});

  final Rect planRect;
  final bool compact;

  static const _wall = Color(0xFF303948);
  static const _thinLine = Color(0xFFD8DEE9);
  static const _grid = Color(0xFFE8EDF5);
  static const _label = Color(0xFF162033);
  static const _furnitureStroke = Color(0xFF9AA6B8);

  @override
  void paint(Canvas canvas, Size size) {
    _drawBase(canvas, size);
    _drawRooms(canvas);
    _drawGrid(canvas);
    _drawWalls(canvas);
    _drawDoorsAndWindows(canvas);
    _drawFurniture(canvas);
    _drawSensorsAndRouter(canvas);
    _drawLegend(canvas, size);
  }

  void _drawBase(Canvas canvas, Size size) {
    final background = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(compact ? 24 : 30),
    );
    canvas.drawRRect(background, Paint()..color = const Color(0xFFF8FAFF));
    canvas.drawRRect(
      background.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFFE5EBF5),
    );
  }

  void _drawRooms(Canvas canvas) {
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.00, 0.00, 0.50, 0.39),
      label: '침실-2',
      fill: const Color(0xFFF7FAFF),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.50, 0.00, 0.50, 0.255),
      label: '주방',
      fill: const Color(0xFFFFF0BF),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.00, 0.39, 0.50, 0.175),
      label: '거실',
      fill: const Color(0xFFEAF7F1),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.50, 0.255, 0.22, 0.31),
      label: '욕실',
      fill: const Color(0xFFDFF5F8),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.00, 0.565, 0.50, 0.435),
      label: '침실-1',
      fill: const Color(0xFFE7F0FF),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.50, 0.565, 0.50, 0.435),
      label: '현관',
      fill: const Color(0xFFF0DDF5),
    );
    _drawRoom(
      canvas,
      rect: _roomRect(planRect, 0.72, 0.255, 0.28, 0.31),
      label: '현관',
      fill: const Color(0xFFF0DDF5),
      showLabel: false,
    );
  }

  void _drawRoom(
    Canvas canvas, {
    required Rect rect,
    required String label,
    required Color fill,
    bool showLabel = true,
  }) {
    canvas.drawRect(rect, Paint()..color = fill);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _thinLine,
    );
    if (showLabel) {
      _drawText(
        canvas,
        label,
        rect.topLeft + const Offset(8, 8),
        fontSize: compact ? 9.5 : 11,
        fontWeight: FontWeight.w900,
      );
    }
  }

  void _drawGrid(Canvas canvas) {
    final paint = Paint()
      ..color = _grid.withValues(alpha: 0.70)
      ..strokeWidth = 0.55;

    for (var i = 1; i < 10; i++) {
      final x = planRect.left + planRect.width * i / 10;
      canvas.drawLine(Offset(x, planRect.top), Offset(x, planRect.bottom), paint);
    }
    for (var i = 1; i < 18; i++) {
      final y = planRect.top + planRect.height * i / 18;
      canvas.drawLine(Offset(planRect.left, y), Offset(planRect.right, y), paint);
    }
  }

  void _drawWalls(Canvas canvas) {
    final wallPaint = Paint()
      ..color = _wall
      ..strokeWidth = compact ? 2.6 : 3.4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.miter;

    canvas.drawRect(planRect, wallPaint);
    _line(canvas, 0.50, 0.00, 0.50, 1.00, wallPaint);
    _line(canvas, 0.00, 0.39, 1.00, 0.39, wallPaint);
    _line(canvas, 0.00, 0.565, 0.50, 0.565, wallPaint);
    _line(canvas, 0.50, 0.255, 1.00, 0.255, wallPaint);
    _line(canvas, 0.72, 0.255, 0.72, 0.565, wallPaint);
    _line(canvas, 0.50, 0.565, 1.00, 0.565, wallPaint);
    _line(canvas, 0.72, 0.565, 0.72, 1.00, wallPaint);
    _line(canvas, 0.72, 0.72, 1.00, 0.72, wallPaint);
  }

  void _line(Canvas canvas, double x1, double y1, double x2, double y2, Paint paint) {
    canvas.drawLine(
      _toPlanOffset(planRect, Offset(x1, y1)),
      _toPlanOffset(planRect, Offset(x2, y2)),
      paint,
    );
  }

  void _drawDoorsAndWindows(Canvas canvas) {
    final doorPaint = Paint()
      ..color = const Color(0xFF5E6A7C)
      ..strokeWidth = compact ? 1.2 : 1.6
      ..style = PaintingStyle.stroke;
    final windowPaint = Paint()
      ..color = const Color(0xFF5EB6E6)
      ..strokeWidth = compact ? 1.1 : 1.5
      ..strokeCap = StrokeCap.round;

    _door(canvas, const Offset(0.50, 0.39), 0.14, 0, -math.pi / 2, doorPaint);
    _door(canvas, const Offset(0.72, 0.565), 0.11, math.pi, math.pi / 2, doorPaint);
    _door(canvas, const Offset(0.72, 0.755), 0.12, -math.pi, -math.pi / 2, doorPaint);
    _door(canvas, const Offset(1.00, 0.79), 0.13, math.pi, math.pi / 2, doorPaint);

    _window(canvas, const Offset(0.06, 0.00), const Offset(0.38, 0.00), windowPaint);
    _window(canvas, const Offset(0.62, 0.00), const Offset(0.92, 0.00), windowPaint);
    _window(canvas, const Offset(0.00, 0.43), const Offset(0.00, 0.54), windowPaint);
    _window(canvas, const Offset(0.14, 1.00), const Offset(0.42, 1.00), windowPaint);
    _window(canvas, const Offset(1.00, 0.32), const Offset(1.00, 0.53), windowPaint);
  }

  void _door(
    Canvas canvas,
    Offset hinge,
    double radiusRatio,
    double start,
    double sweep,
    Paint paint,
  ) {
    final center = _toPlanOffset(planRect, hinge);
    final radius = planRect.width * radiusRatio;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, paint);
    final end = center + Offset(math.cos(start + sweep), math.sin(start + sweep)) * radius;
    canvas.drawLine(center, end, paint);
  }

  void _window(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(_toPlanOffset(planRect, start), _toPlanOffset(planRect, end), paint);
  }

  void _drawFurniture(Canvas canvas) {
    _drawBed(canvas, _roomRect(planRect, 0.07, 0.12, 0.32, 0.13));
    _drawWardrobe(canvas, _roomRect(planRect, 0.41, 0.09, 0.055, 0.23));
    _drawDesk(canvas, _roomRect(planRect, 0.09, 0.31, 0.23, 0.055));

    _drawKitchenCounter(canvas, _roomRect(planRect, 0.56, 0.12, 0.32, 0.10));
    _drawFridge(canvas, _roomRect(planRect, 0.89, 0.05, 0.07, 0.17));

    _drawSofa(canvas, _roomRect(planRect, 0.07, 0.42, 0.26, 0.075));
    _drawCoffeeTable(canvas, _roomRect(planRect, 0.36, 0.43, 0.12, 0.06));
    _drawTvStand(canvas, _roomRect(planRect, 0.09, 0.535, 0.30, 0.025));

    _drawBath(canvas, _roomRect(planRect, 0.55, 0.41, 0.085, 0.14));
    _drawToilet(canvas, _roomRect(planRect, 0.66, 0.34, 0.045, 0.075));
    _drawSink(canvas, _roomRect(planRect, 0.66, 0.50, 0.05, 0.075));

    _drawBed(canvas, _roomRect(planRect, 0.07, 0.70, 0.36, 0.17), doubleBed: true);
    _drawBench(canvas, _roomRect(planRect, 0.07, 0.93, 0.36, 0.035));
    _drawWardrobe(canvas, _roomRect(planRect, 0.43, 0.64, 0.05, 0.22));

    _drawShoeCabinet(canvas, _roomRect(planRect, 0.77, 0.73, 0.10, 0.18));
    _drawBench(canvas, _roomRect(planRect, 0.56, 0.92, 0.29, 0.05));
  }

  void _drawBed(Canvas canvas, Rect rect, {bool doubleBed = false}) {
    _rounded(canvas, rect, const Color(0xFFDCE8F8));
    _rounded(canvas, rect.deflate(4), const Color(0xFFEAF2FF), stroke: true);
    final pillowW = rect.width * (doubleBed ? 0.32 : 0.38);
    final pillowH = rect.height * 0.22;
    _rounded(
      canvas,
      Rect.fromLTWH(rect.left + 6, rect.top + 7, pillowW, pillowH),
      Colors.white.withValues(alpha: 0.82),
      radius: 4,
      stroke: true,
    );
    if (doubleBed) {
      _rounded(
        canvas,
        Rect.fromLTWH(rect.right - pillowW - 6, rect.top + 7, pillowW, pillowH),
        Colors.white.withValues(alpha: 0.82),
        radius: 4,
        stroke: true,
      );
    }
    canvas.drawLine(
      Offset(rect.left + 8, rect.center.dy),
      Offset(rect.right - 8, rect.center.dy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
  }

  void _drawWardrobe(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFD4C18B), radius: 6);
    canvas.drawLine(
      Offset(rect.center.dx, rect.top + 4),
      Offset(rect.center.dx, rect.bottom - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.52)
        ..strokeWidth = 0.8,
    );
  }

  void _drawDesk(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFDFCF99), radius: 5);
    final chair = Rect.fromCenter(
      center: Offset(rect.center.dx, rect.bottom + rect.height * 0.45),
      width: rect.width * 0.24,
      height: rect.height * 0.55,
    );
    _rounded(canvas, chair, const Color(0xFFB4C4B8), radius: 4);
  }

  void _drawKitchenCounter(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFE0C98A), radius: 5);
    final sink = Rect.fromLTWH(rect.left + 6, rect.top + 4, rect.width * 0.20, rect.height - 8);
    canvas.drawOval(sink, Paint()..color = Colors.white.withValues(alpha: 0.78));
    for (var i = 0; i < 4; i++) {
      final cx = rect.right - 8 - i * 9;
      canvas.drawCircle(
        Offset(cx, rect.center.dy),
        3.2,
        Paint()..color = Colors.white.withValues(alpha: 0.75),
      );
    }
  }

  void _drawFridge(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFE8EEF8), radius: 5, stroke: true);
    canvas.drawLine(
      Offset(rect.left + 3, rect.center.dy),
      Offset(rect.right - 3, rect.center.dy),
      Paint()
        ..color = _furnitureStroke.withValues(alpha: 0.55)
        ..strokeWidth = 0.8,
    );
  }

  void _drawSofa(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFB6C9BC), radius: 8);
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.33, rect.top + 4),
      Offset(rect.left + rect.width * 0.33, rect.bottom - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8,
    );
    canvas.drawLine(
      Offset(rect.left + rect.width * 0.66, rect.top + 4),
      Offset(rect.left + rect.width * 0.66, rect.bottom - 4),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8,
    );
  }

  void _drawCoffeeTable(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFD9C78A), radius: 5);
    canvas.drawCircle(
      rect.centerLeft + Offset(rect.width * 0.35, 0),
      4,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      rect.centerRight - Offset(rect.width * 0.35, 0),
      4,
      Paint()..color = Colors.white,
    );
  }

  void _drawTvStand(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFF9CA9B8), radius: 3);
  }

  void _drawBath(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFF9DCCD5), radius: 7);
    canvas.drawOval(rect.deflate(5), Paint()..color = Colors.white.withValues(alpha: 0.80));
  }

  void _drawToilet(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFEAF2F5), radius: 4, stroke: true);
    canvas.drawOval(rect.deflate(3), Paint()..color = Colors.white);
  }

  void _drawSink(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFEAF2F5), radius: 4, stroke: true);
    canvas.drawCircle(rect.center, rect.shortestSide * 0.34, Paint()..color = Colors.white);
  }

  void _drawShoeCabinet(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFC49BD4), radius: 7);
  }

  void _drawBench(Canvas canvas, Rect rect) {
    _rounded(canvas, rect, const Color(0xFFB7C2CA), radius: 4);
  }

  void _rounded(Canvas canvas, Rect rect, Color color, {double radius = 8, bool stroke = false}) {
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = stroke ? _furnitureStroke.withValues(alpha: 0.60) : color
        ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = 1,
    );
  }

  void _drawSensorsAndRouter(Canvas canvas) {
    _drawSensorNode(
      canvas,
      point: planRect.topLeft,
      label: 'ESP32-1',
      subLabel: compact ? null : '(0,0)',
      alignRight: true,
      alignBottom: true,
    );
    _drawSensorNode(
      canvas,
      point: planRect.topRight,
      label: 'ESP32-2',
      subLabel: compact ? null : '수신',
      alignRight: false,
      alignBottom: true,
    );
    _drawSensorNode(
      canvas,
      point: planRect.bottomLeft,
      label: 'ESP32-3',
      subLabel: compact ? null : '수신',
      alignRight: true,
      alignBottom: false,
    );
    _drawSensorNode(
      canvas,
      point: planRect.bottomRight,
      label: 'ESP32-4',
      subLabel: compact ? null : '수신',
      alignRight: false,
      alignBottom: false,
    );

    final router = _roomRect(planRect, 0.74, 0.88, 0.20, 0.06);
    _rounded(canvas, router, Colors.white, radius: 5, stroke: true);
    _drawText(
      canvas,
      'ipTIME AP',
      router.centerLeft + const Offset(7, -5),
      fontSize: compact ? 6.5 : 7.5,
      color: const Color(0xFF536176),
      fontWeight: FontWeight.w800,
    );
    final wifiCenter = Offset(router.left + 9, router.center.dy);
    final wifiPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.primary;
    for (var i = 1; i <= 3; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: wifiCenter, radius: i * 3.0),
        -math.pi * 0.78,
        math.pi * 0.56,
        false,
        wifiPaint,
      );
    }
  }

  void _drawSensorNode(
    Canvas canvas, {
    required Offset point,
    required String label,
    required bool alignRight,
    required bool alignBottom,
    String? subLabel,
  }) {
    final outerPaint = Paint()..color = Colors.white.withValues(alpha: 0.96);
    final ringPaint = Paint()..color = AppColors.success.withValues(alpha: compact ? 0.24 : 0.18);
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 2.4 : 2.8
      ..color = AppColors.success.withValues(alpha: 0.62);
    final corePaint = Paint()..color = AppColors.success;

    canvas.drawCircle(point, compact ? 14 : 18, outerPaint);
    canvas.drawCircle(point, compact ? 13 : 17, ringPaint);
    canvas.drawCircle(point, compact ? 9.5 : 12, haloPaint);
    canvas.drawCircle(point, compact ? 6.0 : 7.6, corePaint);

    final labelWidth = compact ? 54.0 : 64.0;
    final labelHeight = compact ? 18.0 : 27.0;
    final dx = alignRight ? 10.0 : -labelWidth - 10.0;
    final dy = alignBottom ? 4.0 : -labelHeight - 4.0;
    final rect = Rect.fromLTWH(point.dx + dx, point.dy + dy, labelWidth, labelHeight);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(compact ? 7 : 9));

    canvas.drawRRect(
      rrect,
      Paint()..color = const Color(0xFFECFFF7).withValues(alpha: 0.96),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? 0.8 : 1.1
        ..color = AppColors.success.withValues(alpha: 0.48),
    );
    _drawText(
      canvas,
      label,
      rect.topLeft + Offset(compact ? 6 : 7, compact ? 5.0 : 5.0),
      fontSize: compact ? 7.5 : 8.8,
      color: const Color(0xFF0A8D65),
      fontWeight: FontWeight.w900,
    );
    if (subLabel != null) {
      _drawText(
        canvas,
        subLabel,
        rect.topLeft + const Offset(7, 16.3),
        fontSize: 6.4,
        color: const Color(0xFF477965),
        fontWeight: FontWeight.w800,
      );
    }
  }

  void _drawLegend(Canvas canvas, Size size) {
    final top = planRect.bottom + (compact ? 8 : 10);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, top + 12),
      width: math.min(size.width - 28, compact ? 180 : 220),
      height: compact ? 24 : 28,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(999));
    canvas.drawRRect(rrect, Paint()..color = Colors.white.withValues(alpha: 0.92));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = const Color(0xFFE4EAF4),
    );

    var x = rect.left + 12;
    x = _legendItem(canvas, Offset(x, rect.center.dy), AppColors.success, 'ESP32-S3 수신 노드');
    _legendItem(canvas, Offset(x + 10, rect.center.dy), AppColors.primary, '실제 AP 위치');
  }

  double _legendItem(Canvas canvas, Offset origin, Color color, String label) {
    canvas.drawCircle(origin, compact ? 2.8 : 3.3, Paint()..color = color);
    final width = _drawText(
      canvas,
      label,
      origin + Offset(compact ? 7 : 8, compact ? -5.4 : -6),
      fontSize: compact ? 7.2 : 8.2,
      color: const Color(0xFF657086),
      fontWeight: FontWeight.w800,
    );
    return origin.dx + width + (compact ? 18 : 22);
  }

  double _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    double fontSize = 10,
    Color color = _label,
    FontWeight fontWeight = FontWeight.w700,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight, height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    painter.paint(canvas, offset);
    return painter.width;
  }

  @override
  bool shouldRepaint(covariant _FloorPlanPainter oldDelegate) {
    return oldDelegate.planRect != planRect || oldDelegate.compact != compact;
  }
}

class _MovementOverlayPainter extends CustomPainter {
  const _MovementOverlayPainter({required this.planRect, required this.path, required this.color});

  final Rect planRect;
  final List<Offset> path;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (path.length < 2) return;

    final rawPoints = path.map((point) => _toPlanOffset(planRect, point)).toList();
    final points = _smoothPoints(rawPoints);
    _drawHumanAfterImages(canvas, points);
  }

  List<Offset> _smoothPoints(List<Offset> source) {
    if (source.length < 2) return source;
    if (source.length == 2) return _interpolateSegment(source.first, source.last, 10);

    final result = <Offset>[];
    for (var i = 0; i < source.length - 1; i++) {
      final p0 = source[(i - 1).clamp(0, source.length - 1).toInt()];
      final p1 = source[i];
      final p2 = source[i + 1];
      final p3 = source[(i + 2).clamp(0, source.length - 1).toInt()];

      for (var step = 0; step < 6; step++) {
        result.add(_catmullRom(p0, p1, p2, p3, step / 6));
      }
    }
    result.add(source.last);
    return result;
  }

  List<Offset> _interpolateSegment(Offset start, Offset end, int count) {
    return List.generate(count + 1, (index) {
      final t = index / count;
      return Offset.lerp(start, end, t)!;
    });
  }

  Offset _catmullRom(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final t2 = t * t;
    final t3 = t2 * t;
    return Offset(
      0.5 *
          ((2 * p1.dx) +
              (-p0.dx + p2.dx) * t +
              (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
              (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3),
      0.5 *
          ((2 * p1.dy) +
              (-p0.dy + p2.dy) * t +
              (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
              (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3),
    );
  }

  void _drawHumanAfterImages(Canvas canvas, List<Offset> points) {
    if (points.isEmpty) return;

    final ghostCount = math.min(4, points.length);
    for (var ghostIndex = 0; ghostIndex < ghostCount; ghostIndex++) {
      final t = ghostCount == 1 ? 1.0 : ghostIndex / (ghostCount - 1);
      final sourceIndex = ((points.length - 1) * t).round().clamp(0, points.length - 1).toInt();
      final point = points[sourceIndex];
      final isLatest = ghostIndex == ghostCount - 1;
      final alpha = isLatest ? 0.42 : 0.12 + ghostIndex * 0.075;
      final scale = isLatest ? 0.92 : 0.66 + ghostIndex * 0.08;
      final previous = points[math.max(0, sourceIndex - 1)];
      final next = points[math.min(points.length - 1, sourceIndex + 1)];
      final angle = _movementAngle(previous, next);

      _drawHumanGhost(canvas, point, angle: angle, alpha: alpha, scale: scale, latest: isLatest);
    }
  }

  double _movementAngle(Offset previous, Offset next) {
    final vector = next - previous;
    if (vector.distance < 0.01) return 0;
    return math.atan2(vector.dy, vector.dx) + math.pi / 2;
  }

  void _drawHumanGhost(
    Canvas canvas,
    Offset center, {
    required double angle,
    required double alpha,
    required double scale,
    required bool latest,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.scale(scale);

    final softShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: latest ? 0.08 : 0.045)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(const Offset(0, 3), latest ? 19 : 15, softShadowPaint);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: alpha * 0.52)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(Offset.zero, latest ? 24 : 19, glowPaint);

    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = latest ? 2.2 : 1.6
      ..color = color.withValues(alpha: alpha * 0.42);
    canvas.drawCircle(Offset.zero, latest ? 22 : 18, haloPaint);

    final bodyPaint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = latest ? 4.5 : 3.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final headPaint = Paint()..color = color.withValues(alpha: alpha);

    canvas.drawCircle(const Offset(0, -13), latest ? 4.6 : 3.8, headPaint);
    canvas.drawLine(const Offset(0, -7), const Offset(0, 8), bodyPaint);
    canvas.drawLine(const Offset(0, -2), const Offset(-8, 4), bodyPaint);
    canvas.drawLine(const Offset(0, -2), const Offset(8, 4), bodyPaint);
    canvas.drawLine(const Offset(0, 8), const Offset(-7, 18), bodyPaint);
    canvas.drawLine(const Offset(0, 8), const Offset(7, 18), bodyPaint);

    if (latest) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = color.withValues(alpha: 0.28);
      canvas.drawCircle(Offset.zero, 24, ringPaint);
    }

    canvas.restore();
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

    return Center(
      child: AnimatedRotation(
        turns: isDanger ? 0.25 : 0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: CustomPaint(
            painter: _PersonPainter(color: color, danger: isDanger),
          ),
        ),
      ),
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

    canvas.drawCircle(Offset(center.dx, size.height * 0.25), 5, Paint()..color = color);
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
      canvas.drawCircle(center, size.width * 0.54, Paint()..color = color.withValues(alpha: 0.12));
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
        color: Colors.white.withValues(alpha: 0.58),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 22),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.border),
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
                  style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
