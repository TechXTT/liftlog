import 'package:flutter/material.dart';

import 'progress_data.dart';

/// A deliberately-bare weight sparkline. No axes, no labels, no grid — just a
/// polyline auto-fit to the min/max of whatever points it receives. Points
/// are already filtered to a single unit by the aggregator; this widget never
/// converts or relabels anything.
class WeightSparkline extends StatelessWidget {
  const WeightSparkline({super.key, required this.points});

  final List<WeightPoint> points;

  static const double height = 140;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: WeightSparklinePainter(points: points, color: color),
      ),
    );
  }
}

class WeightSparklinePainter extends CustomPainter {
  WeightSparklinePainter({required this.points, required this.color});

  final List<WeightPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    // X scale: linear by timestamp. Using ms-since-epoch keeps the arithmetic
    // simple; no risk of overflow for realistic body-weight log ranges.
    final tMin = points.first.timestamp.millisecondsSinceEpoch.toDouble();
    final tMax = points.last.timestamp.millisecondsSinceEpoch.toDouble();
    final tSpan = (tMax - tMin).abs() < 1 ? 1.0 : tMax - tMin;

    // Y scale: auto-fit to actual min/max with a small vertical padding so
    // the line never grazes the edge. If all values are identical, draw a
    // horizontal line in the middle.
    var yMin = points.first.value;
    var yMax = points.first.value;
    for (final p in points) {
      if (p.value < yMin) yMin = p.value;
      if (p.value > yMax) yMax = p.value;
    }
    final yRange = yMax - yMin;
    final paddedMin = yRange == 0 ? yMin - 1 : yMin - yRange * 0.1;
    final paddedMax = yRange == 0 ? yMax + 1 : yMax + yRange * 0.1;
    final ySpan = paddedMax - paddedMin;

    const paddingX = 4.0;
    const paddingY = 4.0;
    final plotW = size.width - paddingX * 2;
    final plotH = size.height - paddingY * 2;

    Offset project(WeightPoint p) {
      final tx = (p.timestamp.millisecondsSinceEpoch - tMin) / tSpan;
      // Flip Y so larger values render higher on the canvas.
      final ty = 1 - ((p.value - paddedMin) / ySpan);
      return Offset(paddingX + tx * plotW, paddingY + ty * plotH);
    }

    final path = Path()..moveTo(project(points.first).dx, project(points.first).dy);
    for (var i = 1; i < points.length; i++) {
      final o = project(points[i]);
      path.lineTo(o.dx, o.dy);
    }

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    // Dot at each data point so sparse series remain visible.
    final dotPaint = Paint()..color = color;
    for (final p in points) {
      canvas.drawCircle(project(p), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant WeightSparklinePainter old) =>
      old.points != points || old.color != color;
}
