import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/features/progress/progress_data.dart';

BodyWeightLog _weight(DateTime t, double v, WeightUnit u) =>
    BodyWeightLog(id: 1, timestamp: t, value: v, unit: u);

FoodEntry _food(DateTime t, int kcal) => FoodEntry(
      id: 1,
      timestamp: t,
      name: '',
      kcal: kcal,
      proteinG: 0.0,
      mealType: MealType.other,
      entryType: FoodEntryType.manual,
      note: null,
    );

void main() {
  group('resolveWindow', () {
    final now = DateTime(2026, 4, 23, 15, 30); // mid-day

    test('sevenDays spans today + 6 prior days', () {
      final r = resolveWindow(ProgressWindow.sevenDays, now: now);
      expect(r.from, DateTime(2026, 4, 17));
      expect(r.to, DateTime(2026, 4, 24));
    });

    test('thirtyDays spans today + 29 prior days', () {
      final r = resolveWindow(ProgressWindow.thirtyDays, now: now);
      expect(r.from, DateTime(2026, 3, 25));
      expect(r.to, DateTime(2026, 4, 24));
    });

    test('all uses epoch-0 as from', () {
      final r = resolveWindow(ProgressWindow.all, now: now);
      expect(r.from.millisecondsSinceEpoch, 0);
      expect(r.to, DateTime(2026, 4, 24));
    });
  });

  group('buildWeightSeries', () {
    test('empty logs yields empty series with no dominant unit', () {
      final s = buildWeightSeries(const []);
      expect(s.isEmpty, isTrue);
      expect(s.dominantUnit, isNull);
      expect(s.mixedUnits, isFalse);
      expect(s.hasEnoughForSparkline, isFalse);
    });

    test('single-unit logs: no mixed flag, dominant = that unit', () {
      final s = buildWeightSeries([
        _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
        _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
      ]);
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.mixedUnits, isFalse);
      expect(s.points.length, 2);
      expect(s.hasEnoughForSparkline, isTrue);
    });

    test('sorts points chronologically regardless of input order', () {
      final s = buildWeightSeries([
        _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
        _weight(DateTime(2026, 4, 18), 79.0, WeightUnit.kg),
        _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
      ]);
      expect(
        s.points.map((p) => p.timestamp).toList(),
        [
          DateTime(2026, 4, 18),
          DateTime(2026, 4, 20),
          DateTime(2026, 4, 22),
        ],
      );
    });

    test('mixed units: dominant = most recent unit, others dropped', () {
      // Most recent is kg → dominant kg, the lb point is dropped.
      final s = buildWeightSeries([
        _weight(DateTime(2026, 4, 18), 176.0, WeightUnit.lb),
        _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
        _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
      ]);
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.mixedUnits, isTrue);
      expect(s.points.length, 2);
      expect(s.points.every((p) => p.value < 100), isTrue,
          reason: 'lb value 176 must be dropped; never silently converted');
    });

    test('mixed units, most recent is lb: drops kg points', () {
      final s = buildWeightSeries([
        _weight(DateTime(2026, 4, 18), 80.0, WeightUnit.kg),
        _weight(DateTime(2026, 4, 22), 176.0, WeightUnit.lb),
      ]);
      expect(s.dominantUnit, WeightUnit.lb);
      expect(s.mixedUnits, isTrue);
      expect(s.points.length, 1);
      expect(s.points.single.value, 176.0);
    });
  });

  group('buildKcalSeries', () {
    test('bounded window: emits one bucket per day, 0 for empty days', () {
      final from = DateTime(2026, 4, 20);
      final to = DateTime(2026, 4, 24); // exclusive → 4 days
      final entries = [
        _food(DateTime(2026, 4, 20, 8), 300),
        _food(DateTime(2026, 4, 20, 13), 500),
        // 4/21, 4/22 empty
        _food(DateTime(2026, 4, 23, 9), 600),
      ];
      final s = buildKcalSeries(entries, from: from, to: to);
      expect(s.days.length, 4);
      expect(s.days[0].day, DateTime(2026, 4, 20));
      expect(s.days[0].kcal, 800);
      expect(s.days[1].kcal, 0);
      expect(s.days[2].kcal, 0);
      expect(s.days[3].kcal, 600);
      expect(s.loggedDayCount, 2);
      expect(s.maxKcal, 800);
    });

    test('local-day bucketing: entries early and late in the day aggregate', () {
      final from = DateTime(2026, 4, 22);
      final to = DateTime(2026, 4, 23);
      final s = buildKcalSeries(
        [
          _food(DateTime(2026, 4, 22, 0, 5), 100),
          _food(DateTime(2026, 4, 22, 23, 55), 900),
        ],
        from: from,
        to: to,
      );
      expect(s.days.length, 1);
      expect(s.days.single.kcal, 1000);
    });

    test('all-window with entries derives first bucket from oldest entry', () {
      final s = buildKcalSeries(
        [
          _food(DateTime(2026, 4, 20, 12), 500),
          _food(DateTime(2026, 4, 22, 12), 700),
        ],
        from: DateTime.fromMillisecondsSinceEpoch(0),
        to: DateTime(2026, 4, 24),
      );
      expect(s.days.first.day, DateTime(2026, 4, 20));
      expect(s.days.length, 4); // 4/20, 4/21, 4/22, 4/23
      expect(s.days.last.day, DateTime(2026, 4, 23));
    });

    test('all-window with no entries degrades to a single zero-bucket', () {
      final s = buildKcalSeries(
        const [],
        from: DateTime.fromMillisecondsSinceEpoch(0),
        to: DateTime(2026, 4, 24),
      );
      expect(s.days.length, 1);
      expect(s.days.single.kcal, 0);
      expect(s.isEmpty, isTrue);
      expect(s.loggedDayCount, 0);
    });
  });
}
