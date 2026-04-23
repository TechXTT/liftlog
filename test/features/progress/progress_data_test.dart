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

WorkoutSession _session(int id, DateTime startedAt) => WorkoutSession(
      id: id,
      startedAt: startedAt,
      endedAt: null,
      note: null,
    );

ExerciseSet _set(int sessionId, WorkoutSetStatus status, {int order = 0}) =>
    ExerciseSet(
      id: sessionId * 100 + order,
      sessionId: sessionId,
      exerciseName: 'Bench Press',
      reps: 8,
      weight: 80.0,
      weightUnit: WeightUnit.kg,
      status: status,
      orderIndex: order,
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

  group('buildWeeklyVolumeSeries', () {
    // Anchor "now" on Thursday 2026-04-23 so the current ISO week starts
    // Monday 2026-04-20. That makes bucket math easy to eyeball.
    final now = DateTime(2026, 4, 23, 15, 30);

    test('emits 8 buckets with Monday anchors, oldest first', () {
      final s = buildWeeklyVolumeSeries(const [], const [], now);
      expect(s.weekStarts.length, 8);
      expect(s.completedSets.length, 8);
      // Current week's Monday is the last bucket.
      expect(s.weekStarts.last, DateTime(2026, 4, 20));
      // 7 weeks before that is the first bucket.
      expect(s.weekStarts.first, DateTime(2026, 3, 2));
      // Every bucket is a local-midnight Monday. Compare by calendar components
      // rather than `Duration.inDays` — on DST weeks two consecutive civil
      // Mondays are only 23 or 25 wall-clock hours apart, so `.inDays` rounds
      // to 6, not 7. Calendar-day arithmetic is what we care about.
      for (var i = 0; i < s.weekStarts.length; i++) {
        final monday = s.weekStarts[i];
        expect(monday.weekday, DateTime.monday,
            reason: 'bucket $i must start on a Monday');
        expect(monday.hour, 0);
        expect(monday.minute, 0);
        final expected = DateTime(2026, 4, 20 - 7 * (7 - i));
        expect(monday, expected, reason: 'bucket $i mismatch');
      }
    });

    test('empty input: all weeks zero, isEmpty true', () {
      final s = buildWeeklyVolumeSeries(const [], const [], now);
      expect(s.completedSets, everyElement(0));
      expect(s.isEmpty, isTrue);
    });

    test('completed sets count, planned and skipped do not — current week', () {
      // Wednesday 2026-04-22 → inside current week (Monday 4/20).
      final session = _session(1, DateTime(2026, 4, 22, 18));
      final sets = [
        _set(1, WorkoutSetStatus.completed, order: 0),
        _set(1, WorkoutSetStatus.completed, order: 1),
        _set(1, WorkoutSetStatus.completed, order: 2),
        _set(1, WorkoutSetStatus.planned, order: 3),
        _set(1, WorkoutSetStatus.planned, order: 4),
        _set(1, WorkoutSetStatus.skipped, order: 5),
      ];
      final s = buildWeeklyVolumeSeries(sets, [session], now);
      expect(s.completedSets.last, 3,
          reason: 'only 3 completed sets count; planned and skipped excluded');
      for (var i = 0; i < 7; i++) {
        expect(s.completedSets[i], 0);
      }
      expect(s.isEmpty, isFalse);
    });

    test('sets across two different weeks bucket into their own weeks', () {
      // Week of 4/20: 2 completed sets (current week, index 7).
      final sessionA = _session(1, DateTime(2026, 4, 21, 18));
      // Week of 4/13: 4 completed sets (prior week, index 6).
      final sessionB = _session(2, DateTime(2026, 4, 15, 12));
      final sets = [
        _set(1, WorkoutSetStatus.completed, order: 0),
        _set(1, WorkoutSetStatus.completed, order: 1),
        _set(2, WorkoutSetStatus.completed, order: 0),
        _set(2, WorkoutSetStatus.completed, order: 1),
        _set(2, WorkoutSetStatus.completed, order: 2),
        _set(2, WorkoutSetStatus.completed, order: 3),
      ];
      final s = buildWeeklyVolumeSeries(sets, [sessionA, sessionB], now);
      expect(s.completedSets[7], 2, reason: 'current week');
      expect(s.completedSets[6], 4, reason: 'prior week');
      for (var i = 0; i < 6; i++) {
        expect(s.completedSets[i], 0);
      }
    });

    test('all-skipped 8-week window: isEmpty true', () {
      // One session per week for all 8 weeks, each with only skipped sets.
      final sessions = <WorkoutSession>[];
      final sets = <ExerciseSet>[];
      for (var i = 0; i < 8; i++) {
        final monday = DateTime(2026, 3, 2 + 7 * i);
        final session =
            _session(i + 1, DateTime(monday.year, monday.month, monday.day, 12));
        sessions.add(session);
        sets.add(_set(i + 1, WorkoutSetStatus.skipped, order: 0));
        sets.add(_set(i + 1, WorkoutSetStatus.skipped, order: 1));
      }
      final s = buildWeeklyVolumeSeries(sets, sessions, now);
      expect(s.completedSets, everyElement(0));
      expect(s.isEmpty, isTrue);
    });

    test('sessions outside the 8-week window are ignored', () {
      // 9 weeks back — before windowStart.
      final oldSession = _session(1, DateTime(2026, 2, 20, 12));
      final sets = [
        _set(1, WorkoutSetStatus.completed, order: 0),
        _set(1, WorkoutSetStatus.completed, order: 1),
      ];
      final s = buildWeeklyVolumeSeries(sets, [oldSession], now);
      expect(s.isEmpty, isTrue,
          reason: 'sets attached to out-of-window sessions must be ignored');
    });

    test('orphan sets (session not in list) are ignored', () {
      final s = buildWeeklyVolumeSeries(
        [_set(99, WorkoutSetStatus.completed)],
        const [],
        now,
      );
      expect(s.isEmpty, isTrue);
    });

    test('session on Monday midnight buckets to that Monday, not previous week',
        () {
      final session = _session(1, DateTime(2026, 4, 20));
      final s = buildWeeklyVolumeSeries(
        [_set(1, WorkoutSetStatus.completed)],
        [session],
        now,
      );
      expect(s.completedSets[7], 1);
      expect(s.completedSets[6], 0);
    });

    test('session on Sunday 23:59 buckets to the Monday before it', () {
      final session = _session(1, DateTime(2026, 4, 19, 23, 59));
      final s = buildWeeklyVolumeSeries(
        [_set(1, WorkoutSetStatus.completed)],
        [session],
        now,
      );
      expect(s.completedSets[6], 1, reason: 'prior week (Mon 4/13)');
      expect(s.completedSets[7], 0);
    });
  });
}
