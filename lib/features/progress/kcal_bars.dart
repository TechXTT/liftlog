import 'package:flutter/material.dart';

import 'progress_data.dart';

/// Daily kcal bar chart. One bar per day in the current window, including
/// 0-value bars for days with no logged entries (visible gap, not a
/// misleading inferred value). Ruthlessly simple — no axes or tooltips.
class KcalBars extends StatelessWidget {
  const KcalBars({super.key, required this.days});

  final List<DailyKcal> days;

  static const double height = 140;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: KcalBarsPainter(days: days, color: color),
      ),
    );
  }
}

class KcalBarsPainter extends CustomPainter {
  KcalBarsPainter({required this.days, required this.color});

  final List<DailyKcal> days;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;

    // Pick the y-scale from the max of the window. If every day is 0 we
    // simply render no bars (empty-state copy handles the user-facing case).
    var maxKcal = 0;
    for (final d in days) {
      if (d.kcal > maxKcal) maxKcal = d.kcal;
    }
    if (maxKcal == 0) return;

    const paddingX = 4.0;
    const paddingY = 4.0;
    final plotW = size.width - paddingX * 2;
    final plotH = size.height - paddingY * 2;

    // Bar width: divide available width into N equal slots, then draw each
    // bar filling ~80% of its slot. 2px minimum so 30d windows stay visible
    // on a 393pt-wide iPhone viewport.
    final slot = plotW / days.length;
    final barW = (slot * 0.8).clamp(2.0, slot);
    final barOffset = (slot - barW) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      if (d.kcal <= 0) continue;
      final h = (d.kcal / maxKcal) * plotH;
      final x = paddingX + i * slot + barOffset;
      final y = paddingY + (plotH - h);
      canvas.drawRect(Rect.fromLTWH(x, y, barW, h), paint);
    }
  }

  @override
  bool shouldRepaint(covariant KcalBarsPainter old) =>
      old.days != days || old.color != color;
}
