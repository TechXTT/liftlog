import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/features/progress/progress_data.dart';
import 'package:liftlog_app/features/progress/weekly_volume_bars.dart';

WeeklyVolumeSeries _series(List<int> counts) {
  // Eight Mondays oldest-first; exact dates don't matter for painter logic.
  final starts = [for (var i = 0; i < 8; i++) DateTime(2026, 3, 2 + 7 * i)];
  return WeeklyVolumeSeries(weekStarts: starts, completedSets: counts);
}

void main() {
  group('WeeklyVolumeBarsPainter', () {
    test(
      'paint() handles empty, all-zero, and mixed-count weeks without throwing',
      () {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        const size = Size(300, 140);

        WeeklyVolumeBarsPainter(
          series: const WeeklyVolumeSeries(weekStarts: [], completedSets: []),
          color: Colors.blue,
        ).paint(canvas, size);

        WeeklyVolumeBarsPainter(
          series: _series(const [0, 0, 0, 0, 0, 0, 0, 0]),
          color: Colors.blue,
        ).paint(canvas, size);

        WeeklyVolumeBarsPainter(
          series: _series(const [2, 0, 5, 3, 0, 12, 8, 10]),
          color: Colors.blue,
        ).paint(canvas, size);

        recorder.endRecording();
      },
    );

    test('shouldRepaint reflects series / color changes', () {
      final s = _series(const [3, 4, 5, 6, 7, 8, 9, 10]);
      final a = WeeklyVolumeBarsPainter(series: s, color: Colors.blue);
      final sameRef = WeeklyVolumeBarsPainter(series: s, color: Colors.blue);
      expect(a.shouldRepaint(sameRef), isFalse);

      final other = WeeklyVolumeBarsPainter(
        series: _series(const [0, 0, 0, 0, 0, 0, 0, 1]),
        color: Colors.blue,
      );
      expect(a.shouldRepaint(other), isTrue);

      final otherColor = WeeklyVolumeBarsPainter(series: s, color: Colors.red);
      expect(a.shouldRepaint(otherColor), isTrue);
    });
  });
}
