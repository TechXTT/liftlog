import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/features/progress/kcal_bars.dart';
import 'package:liftlog_app/features/progress/progress_data.dart';

void main() {
  group('KcalBarsPainter', () {
    test('paint() handles empty, all-zero, and mixed-value days without throwing', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(300, 140);

      KcalBarsPainter(days: const [], color: Colors.blue).paint(canvas, size);

      KcalBarsPainter(
        days: [
          DailyKcal(day: DateTime(2026, 4, 20), kcal: 0),
          DailyKcal(day: DateTime(2026, 4, 21), kcal: 0),
        ],
        color: Colors.blue,
      ).paint(canvas, size);

      KcalBarsPainter(
        days: [
          DailyKcal(day: DateTime(2026, 4, 20), kcal: 400),
          DailyKcal(day: DateTime(2026, 4, 21), kcal: 0),
          DailyKcal(day: DateTime(2026, 4, 22), kcal: 2200),
          DailyKcal(day: DateTime(2026, 4, 23), kcal: 1500),
        ],
        color: Colors.blue,
      ).paint(canvas, size);

      // 30-day window stresses the min-bar-width clamp.
      KcalBarsPainter(
        days: List.generate(
          30,
          (i) => DailyKcal(day: DateTime(2026, 4, 1).add(Duration(days: i)), kcal: i * 80),
        ),
        color: Colors.blue,
      ).paint(canvas, size);

      recorder.endRecording();
    });

    test('shouldRepaint reflects days / color changes', () {
      final days = [
        DailyKcal(day: DateTime(2026, 4, 22), kcal: 1500),
        DailyKcal(day: DateTime(2026, 4, 23), kcal: 1800),
      ];
      final a = KcalBarsPainter(days: days, color: Colors.blue);
      final sameRef = KcalBarsPainter(days: days, color: Colors.blue);
      expect(a.shouldRepaint(sameRef), isFalse);

      final otherDays = KcalBarsPainter(
        days: [DailyKcal(day: DateTime(2026, 4, 22), kcal: 100)],
        color: Colors.blue,
      );
      expect(a.shouldRepaint(otherDays), isTrue);

      final otherColor = KcalBarsPainter(days: days, color: Colors.red);
      expect(a.shouldRepaint(otherColor), isTrue);
    });
  });
}
