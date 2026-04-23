import 'package:flutter/material.dart';

import 'progress_data.dart';

/// Weekly completed-sets bar chart. One bar per ISO week in the trailing
/// 8-week window; 0-weeks render as a gap (no bar) rather than a zero-height
/// bar, matching the kcal chart's style. Ruthlessly simple — no axes, no
/// tooltips, no labels (see issue #24).
class WeeklyVolumeBars extends StatelessWidget {
  const WeeklyVolumeBars({super.key, required this.series});

  final WeeklyVolumeSeries series;

  static const double height = 140;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: WeeklyVolumeBarsPainter(series: series, color: color),
      ),
    );
  }
}

class WeeklyVolumeBarsPainter extends CustomPainter {
  WeeklyVolumeBarsPainter({required this.series, required this.color});

  final WeeklyVolumeSeries series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final counts = series.completedSets;
    if (counts.isEmpty) return;

    // Y scale from the window's max. If everything is zero we draw nothing —
    // the screen already renders the dedicated empty-state copy in that case.
    var maxCount = 0;
    for (final c in counts) {
      if (c > maxCount) maxCount = c;
    }
    if (maxCount == 0) return;

    const paddingX = 4.0;
    const paddingY = 4.0;
    final plotW = size.width - paddingX * 2;
    final plotH = size.height - paddingY * 2;

    // Bar width: equal slot per week (8 weeks fixed), bar ~80% of slot.
    // Min 2px so narrow iPhone viewports still render something.
    final slot = plotW / counts.length;
    final barW = (slot * 0.8).clamp(2.0, slot);
    final barOffset = (slot - barW) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < counts.length; i++) {
      final c = counts[i];
      if (c <= 0) continue;
      final h = (c / maxCount) * plotH;
      final x = paddingX + i * slot + barOffset;
      final y = paddingY + (plotH - h);
      canvas.drawRect(Rect.fromLTWH(x, y, barW, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant WeeklyVolumeBarsPainter old) =>
      old.series != series || old.color != color;
}
