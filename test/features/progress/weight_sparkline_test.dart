import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/features/progress/progress_data.dart';
import 'package:liftlog_app/features/progress/weight_sparkline.dart';

void main() {
  group('WeightSparklinePainter', () {
    test('paint() does not throw for empty, single, and multi-point inputs', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size(300, 140);

      WeightSparklinePainter(points: const [], color: Colors.blue)
          .paint(canvas, size);
      WeightSparklinePainter(
        points: [WeightPoint(timestamp: DateTime(2026, 4, 20), value: 80.0)],
        color: Colors.blue,
      ).paint(canvas, size);
      WeightSparklinePainter(
        points: [
          WeightPoint(timestamp: DateTime(2026, 4, 20), value: 80.0),
          WeightPoint(timestamp: DateTime(2026, 4, 22), value: 80.5),
          WeightPoint(timestamp: DateTime(2026, 4, 23), value: 79.8),
        ],
        color: Colors.blue,
      ).paint(canvas, size);

      // Also survives identical-y values (yRange == 0 branch).
      WeightSparklinePainter(
        points: [
          WeightPoint(timestamp: DateTime(2026, 4, 20), value: 80.0),
          WeightPoint(timestamp: DateTime(2026, 4, 21), value: 80.0),
        ],
        color: Colors.blue,
      ).paint(canvas, size);

      recorder.endRecording();
    });

    test('shouldRepaint returns true when points or color change, false otherwise', () {
      final points = [
        WeightPoint(timestamp: DateTime(2026, 4, 20), value: 80.0),
        WeightPoint(timestamp: DateTime(2026, 4, 22), value: 80.5),
      ];
      final a = WeightSparklinePainter(points: points, color: Colors.blue);
      final sameRef = WeightSparklinePainter(points: points, color: Colors.blue);
      expect(a.shouldRepaint(sameRef), isFalse);

      final differentPoints = WeightSparklinePainter(
        points: [
          WeightPoint(timestamp: DateTime(2026, 4, 20), value: 81.0),
        ],
        color: Colors.blue,
      );
      expect(a.shouldRepaint(differentPoints), isTrue);

      final differentColor =
          WeightSparklinePainter(points: points, color: Colors.red);
      expect(a.shouldRepaint(differentColor), isTrue);
    });
  });
}
