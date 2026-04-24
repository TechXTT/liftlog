import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/features/progress/progress_data.dart';
import 'package:liftlog_app/sources/health_kit/health_source.dart';

BodyWeightLog _weight(DateTime t, double v, WeightUnit u) =>
    BodyWeightLog(id: 1, timestamp: t, value: v, unit: u, source: Source.userEntered);

HKBodyWeightSample _hk(
  DateTime t,
  double v,
  WeightUnit u, {
  String sourceId = 'com.apple.Health',
}) =>
    HKBodyWeightSample(sourceId: sourceId, timestamp: t, value: v, unit: u);

// Wide default window covering every test date used below. Individual tests
// can still pass their own bounds where the boundary matters.
final _windowFrom = DateTime(2026, 1, 1);
final _windowTo = DateTime(2026, 5, 1);

FoodEntry _food(DateTime t, int kcal) => FoodEntry(
      id: 1,
      timestamp: t,
      name: '',
      kcal: kcal,
      proteinG: 0.0,
      mealType: MealType.other,
      entryType: FoodEntryType.manual,
      note: null,
      source: Source.userEntered,
    );

WorkoutSession _session(int id, DateTime startedAt) => WorkoutSession(
      id: id,
      startedAt: startedAt,
      endedAt: null,
      note: null,
      source: Source.userEntered,
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
      source: Source.userEntered,
    );

WorkoutSession _sessionWithEnd(int id, DateTime startedAt, DateTime? endedAt) =>
    WorkoutSession(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt,
      note: null,
      source: Source.userEntered,
    );

FoodEntry _foodWithProtein(DateTime t, int kcal, double proteinG) => FoodEntry(
      id: 1,
      timestamp: t,
      name: '',
      kcal: kcal,
      proteinG: proteinG,
      mealType: MealType.other,
      entryType: FoodEntryType.manual,
      note: null,
      source: Source.userEntered,
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
      final s = buildWeightSeries(
        userEntered: const [],
        hkSamples: const [],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.isEmpty, isTrue);
      expect(s.dominantUnit, isNull);
      expect(s.mixedUnits, isFalse);
      expect(s.hasEnoughForSparkline, isFalse);
    });

    test('single-unit logs: no mixed flag, dominant = that unit', () {
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.mixedUnits, isFalse);
      expect(s.points.length, 2);
      expect(s.hasEnoughForSparkline, isTrue);
      expect(
        s.points.every((p) => !p.isFromHealthKit),
        isTrue,
        reason: 'all user-entered → no HK flag on any point',
      );
    });

    test('sorts points chronologically regardless of input order', () {
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
          _weight(DateTime(2026, 4, 18), 79.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: _windowFrom,
        to: _windowTo,
      );
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
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 18), 176.0, WeightUnit.lb),
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.mixedUnits, isTrue);
      expect(s.points.length, 2);
      expect(s.points.every((p) => p.value < 100), isTrue,
          reason: 'lb value 176 must be dropped; never silently converted');
    });

    test('mixed units, most recent is lb: drops kg points', () {
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 18), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 22), 176.0, WeightUnit.lb),
        ],
        hkSamples: const [],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.dominantUnit, WeightUnit.lb);
      expect(s.mixedUnits, isTrue);
      expect(s.points.length, 1);
      expect(s.points.single.value, 176.0);
    });

    test(
        'same-day dedup: user-entered wins over HK sample '
        '(data-source precedence)', () {
      // Both sides land on 4/20. Per the data-source precedence rule
      // (user_entered > saved_template > default), the user-entered row
      // wins — we never surface the HK value for that day.
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 20, 8), 80.5, WeightUnit.kg),
        ],
        hkSamples: [
          _hk(DateTime(2026, 4, 20, 7), 79.9, WeightUnit.kg),
        ],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.points.length, 1);
      expect(s.points.single.value, 80.5,
          reason: 'user-entered wins, HK value is dropped');
      expect(s.points.single.isFromHealthKit, isFalse);
    });

    test(
        'different-day merge: 2 points, isFromHealthKit flags match their '
        'origin', () {
      // User-entered on 4/20, HK on 4/22 → both survive as separate days.
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
        ],
        hkSamples: [
          _hk(DateTime(2026, 4, 22), 80.5, WeightUnit.kg),
        ],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.points.length, 2);
      // Chronological: 4/20 first, 4/22 second.
      expect(s.points[0].timestamp, DateTime(2026, 4, 20));
      expect(s.points[0].isFromHealthKit, isFalse);
      expect(s.points[1].timestamp, DateTime(2026, 4, 22));
      expect(s.points[1].isFromHealthKit, isTrue);
    });

    test('HK-only day: single point with isFromHealthKit true', () {
      // No user-entered data at all — the HK sample contributes a point.
      final s = buildWeightSeries(
        userEntered: const [],
        hkSamples: [
          _hk(DateTime(2026, 4, 21), 79.8, WeightUnit.kg),
          _hk(DateTime(2026, 4, 23), 80.0, WeightUnit.kg),
        ],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.points.length, 2);
      expect(s.points.every((p) => p.isFromHealthKit), isTrue);
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.mixedUnits, isFalse);
    });

    test('mixed units across HK + user-entered triggers the banner', () {
      // HK sample is lb, user-entered is kg, different days → merged set
      // carries both units → mixedUnits true. Most recent is user-entered
      // kg → dominant kg → lb HK point drops out.
      final s = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 22), 80.0, WeightUnit.kg),
        ],
        hkSamples: [
          _hk(DateTime(2026, 4, 18), 176.0, WeightUnit.lb),
        ],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.mixedUnits, isTrue);
      expect(s.dominantUnit, WeightUnit.kg);
      expect(s.points.length, 1);
      expect(s.points.single.value, 80.0,
          reason: 'lb HK value must drop out — never silently converted');
      expect(s.points.single.isFromHealthKit, isFalse);
    });

    test(
        'multiple HK samples same day → newest wins (and carries the HK flag)',
        () {
      // Three HK samples on 4/21 at 07:00, 12:30 and 19:45. The 19:45
      // reading is the most recent and is the one that must surface.
      final s = buildWeightSeries(
        userEntered: const [],
        hkSamples: [
          _hk(DateTime(2026, 4, 21, 7), 79.5, WeightUnit.kg),
          _hk(DateTime(2026, 4, 21, 19, 45), 79.9, WeightUnit.kg),
          _hk(DateTime(2026, 4, 21, 12, 30), 79.7, WeightUnit.kg),
        ],
        from: _windowFrom,
        to: _windowTo,
      );
      expect(s.points.length, 1);
      expect(s.points.single.value, 79.9,
          reason: 'newest HK sample for the day wins');
      expect(s.points.single.isFromHealthKit, isTrue);
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

  group('calendarDaysInWindow', () {
    test('bounded 7-day window returns 7', () {
      expect(
        calendarDaysInWindow(
          from: DateTime(2026, 4, 17),
          to: DateTime(2026, 4, 24),
        ),
        7,
      );
    });

    test('single-day window returns 1', () {
      expect(
        calendarDaysInWindow(
          from: DateTime(2026, 4, 23),
          to: DateTime(2026, 4, 24),
        ),
        1,
      );
    });

    test('from >= to returns 0', () {
      expect(
        calendarDaysInWindow(
          from: DateTime(2026, 4, 24),
          to: DateTime(2026, 4, 24),
        ),
        0,
      );
    });

    test('truncates sub-day times to midnight on both ends', () {
      // from = 4/17 23:59 → truncates to 4/17 00:00.
      // to   = 4/24 00:01 → truncates to 4/24 00:00.
      expect(
        calendarDaysInWindow(
          from: DateTime(2026, 4, 17, 23, 59),
          to: DateTime(2026, 4, 24, 0, 1),
        ),
        7,
      );
    });
  });

  group('buildProgressSummary', () {
    final now = DateTime(2026, 4, 23, 15, 30); // Thursday
    final range = resolveWindow(ProgressWindow.sevenDays, now: now);

    test('populated 7d window: averages + delta + sessions all non-null', () {
      // 2 food entries across 2 days inside the window → denominator is 7
      // (calendar days), NOT 2. This is the core "averages use calendar
      // days, not logged-day count" contract (AC #2).
      final foods = [
        _foodWithProtein(DateTime(2026, 4, 19, 12), 700, 40.0),
        _foodWithProtein(DateTime(2026, 4, 23, 13), 1400, 80.0),
      ];
      final weight = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 17), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 23), 80.7, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: range.from,
        to: range.to,
      );
      final session = _sessionWithEnd(
        1,
        DateTime(2026, 4, 22, 18),
        DateTime(2026, 4, 22, 19),
      );
      final grouped = [
        (
          session: session,
          sets: <ExerciseSet>[_set(1, WorkoutSetStatus.completed)],
        ),
      ];
      final s = buildProgressSummary(
        foods: foods,
        weightSeries: weight,
        sessionsWithSets: grouped,
        from: range.from,
        to: range.to,
      );
      // (700 + 1400) / 7 = 300 kcal/day.
      expect(s.avgKcalPerDay, 300);
      // (40 + 80) / 7 ≈ 17.14 g/day. Compare with tolerance for floating-point.
      expect(s.avgProteinGPerDay, closeTo(120.0 / 7.0, 0.0001));
      // Delta is 80.7 - 80.0 = 0.7 kg (rounding tolerance for FP).
      expect(s.weightDelta, closeTo(0.7, 0.0001));
      expect(s.weightDeltaUnit, WeightUnit.kg);
      expect(s.sessionsCompleted, 1);
    });

    test('averages divide by 7 calendar days, not 2 logged days (AC #2)', () {
      // Only 2 days have entries, but the window is 7 calendar days wide.
      // Denominator must be 7 — not 2. Testing the exact kcal value catches
      // any accidental regression to logged-day arithmetic.
      final foods = [
        _foodWithProtein(DateTime(2026, 4, 19, 9), 1400, 100.0),
        _foodWithProtein(DateTime(2026, 4, 23, 9), 700, 50.0),
      ];
      final s = buildProgressSummary(
        foods: foods,
        weightSeries: const WeightSeries(
          points: [],
          dominantUnit: null,
          mixedUnits: false,
        ),
        sessionsWithSets: const [],
        from: range.from,
        to: range.to,
      );
      expect(s.avgKcalPerDay, 300, reason: '(1400+700)/7 = 300');
      expect(s.avgProteinGPerDay, closeTo(150.0 / 7.0, 0.0001));
    });

    test('empty window: averages null, delta null, sessions 0', () {
      final weight = buildWeightSeries(
        userEntered: const [],
        hkSamples: const [],
        from: range.from,
        to: range.to,
      );
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: weight,
        sessionsWithSets: const [],
        from: range.from,
        to: range.to,
      );
      expect(s.avgKcalPerDay, isNull);
      expect(s.avgProteinGPerDay, isNull);
      expect(s.weightDelta, isNull);
      expect(s.weightDeltaUnit, isNull);
      expect(s.sessionsCompleted, 0);
    });

    test('single-unit delta: last minus first in dominant unit', () {
      // 3 kg points inside the window. Delta = 81.0 - 80.0 = 1.0 kg.
      final weight = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 17), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 20), 80.5, WeightUnit.kg),
          _weight(DateTime(2026, 4, 23), 81.0, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: range.from,
        to: range.to,
      );
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: weight,
        sessionsWithSets: const [],
        from: range.from,
        to: range.to,
      );
      expect(s.weightDelta, closeTo(1.0, 0.0001));
      expect(s.weightDeltaUnit, WeightUnit.kg);
    });

    test('mixed-unit window: weight delta is null (never silently converted)',
        () {
      // Trust rule: don't fabricate a delta that crosses kg↔lb, even if we
      // could filter to the dominant unit and have 2+ points left.
      final weight = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 17), 176.0, WeightUnit.lb),
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
          _weight(DateTime(2026, 4, 23), 80.5, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: range.from,
        to: range.to,
      );
      expect(weight.mixedUnits, isTrue); // sanity check
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: weight,
        sessionsWithSets: const [],
        from: range.from,
        to: range.to,
      );
      expect(s.weightDelta, isNull);
      expect(s.weightDeltaUnit, isNull);
    });

    test('single weight point: delta is null', () {
      final weight = buildWeightSeries(
        userEntered: [
          _weight(DateTime(2026, 4, 20), 80.0, WeightUnit.kg),
        ],
        hkSamples: const [],
        from: range.from,
        to: range.to,
      );
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: weight,
        sessionsWithSets: const [],
        from: range.from,
        to: range.to,
      );
      expect(s.weightDelta, isNull);
      expect(s.weightDeltaUnit, isNull);
    });

    test('in-progress sessions do not count toward sessionsCompleted', () {
      // Session started in-window but never ended → endedAt is null → skip.
      final inProgress = _sessionWithEnd(
        1,
        DateTime(2026, 4, 22, 18),
        null,
      );
      final finished = _sessionWithEnd(
        2,
        DateTime(2026, 4, 21, 18),
        DateTime(2026, 4, 21, 19),
      );
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: const WeightSeries(
          points: [],
          dominantUnit: null,
          mixedUnits: false,
        ),
        sessionsWithSets: [
          (session: inProgress, sets: const <ExerciseSet>[]),
          (session: finished, sets: const <ExerciseSet>[]),
        ],
        from: range.from,
        to: range.to,
      );
      expect(s.sessionsCompleted, 1);
    });

    test('sessions outside window are excluded', () {
      // Session ended but startedAt is before the window → not counted.
      final out = _sessionWithEnd(
        1,
        DateTime(2026, 4, 10, 18),
        DateTime(2026, 4, 10, 19),
      );
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: const WeightSeries(
          points: [],
          dominantUnit: null,
          mixedUnits: false,
        ),
        sessionsWithSets: [
          (session: out, sets: const <ExerciseSet>[]),
        ],
        from: range.from,
        to: range.to,
      );
      expect(s.sessionsCompleted, 0);
    });

    test('all-window, no entries: averages null (no honest denominator)', () {
      final allRange = resolveWindow(ProgressWindow.all, now: now);
      final s = buildProgressSummary(
        foods: const [],
        weightSeries: const WeightSeries(
          points: [],
          dominantUnit: null,
          mixedUnits: false,
        ),
        sessionsWithSets: const [],
        from: allRange.from,
        to: allRange.to,
      );
      expect(s.avgKcalPerDay, isNull);
      expect(s.avgProteinGPerDay, isNull);
    });

    test('all-window with entries: divides by days from oldest entry to today',
        () {
      // Oldest entry on 4/20, "now" is 4/23 → span is 4 calendar days
      // (4/20, 4/21, 4/22, 4/23). Totals 2000 kcal / 4 = 500 kcal/day.
      final foods = [
        _foodWithProtein(DateTime(2026, 4, 20, 12), 1200, 60.0),
        _foodWithProtein(DateTime(2026, 4, 23, 12), 800, 40.0),
      ];
      final allRange = resolveWindow(ProgressWindow.all, now: now);
      final s = buildProgressSummary(
        foods: foods,
        weightSeries: const WeightSeries(
          points: [],
          dominantUnit: null,
          mixedUnits: false,
        ),
        sessionsWithSets: const [],
        from: allRange.from,
        to: allRange.to,
      );
      expect(s.avgKcalPerDay, 500);
      expect(s.avgProteinGPerDay, closeTo(25.0, 0.0001));
    });
  });

  group('latestHRVSdnn', () {
    final now = DateTime(2026, 4, 23, 12);

    test('empty list returns null', () {
      expect(latestHRVSdnn(const [], now), isNull);
    });

    test('sample inside the 48h window returns its SDNN', () {
      final samples = [
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 6)),
          sdnnMs: 47.0,
        ),
      ];
      expect(latestHRVSdnn(samples, now), 47.0);
    });

    test('sample older than 48h is ignored', () {
      final samples = [
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 72)),
          sdnnMs: 47.0,
        ),
      ];
      expect(latestHRVSdnn(samples, now), isNull);
    });

    test('sample exactly at the 48h cutoff is excluded (strict isAfter)', () {
      // cutoff = now - 48h, and the filter uses isAfter(cutoff) which is
      // strict — a sample at the cutoff instant does NOT count.
      final samples = [
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 48)),
          sdnnMs: 50.0,
        ),
      ];
      expect(latestHRVSdnn(samples, now), isNull);
    });

    test('multiple in-window samples: newest wins', () {
      final samples = [
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 36)),
          sdnnMs: 40.0,
        ),
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 3)),
          sdnnMs: 52.0,
        ),
        HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 18)),
          sdnnMs: 45.0,
        ),
      ];
      expect(latestHRVSdnn(samples, now), 52.0);
    });
  });

  group('latestRestingHRBpm', () {
    final now = DateTime(2026, 4, 23, 12);

    test('empty list returns null', () {
      expect(latestRestingHRBpm(const [], now), isNull);
    });

    test('sample inside the 48h window returns its BPM', () {
      final samples = [
        HKRestingHRSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 4)),
          bpm: 58.0,
        ),
      ];
      expect(latestRestingHRBpm(samples, now), 58.0);
    });

    test('sample older than 48h is ignored', () {
      final samples = [
        HKRestingHRSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 100)),
          bpm: 58.0,
        ),
      ];
      expect(latestRestingHRBpm(samples, now), isNull);
    });

    test('multiple in-window samples: newest wins', () {
      final samples = [
        HKRestingHRSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 40)),
          bpm: 62.0,
        ),
        HKRestingHRSample(
          sourceId: 'com.apple.Health',
          timestamp: now.subtract(const Duration(hours: 2)),
          bpm: 59.0,
        ),
      ];
      expect(latestRestingHRBpm(samples, now), 59.0);
    });
  });

  group('lastNightSleepDuration', () {
    // Anchor "now" at Thu 2026-04-23 10:00 — the last-night window is
    // Wed 20:00 through Thu 12:00 local.
    final now = DateTime(2026, 4, 23, 10);

    HKSleepStageSample sleep(DateTime start, DateTime end, SleepStage stage) =>
        HKSleepStageSample(
          sourceId: 'com.apple.Health',
          start: start,
          end: end,
          stage: stage,
        );

    test('empty list returns null', () {
      expect(lastNightSleepDuration(const [], now), isNull);
    });

    test('only asleep-* intervals contribute, totals >= 30 min', () {
      final samples = [
        sleep(
          DateTime(2026, 4, 22, 23),
          DateTime(2026, 4, 23, 2),
          SleepStage.asleepCore,
        ), // 3h
        sleep(
          DateTime(2026, 4, 23, 2),
          DateTime(2026, 4, 23, 3),
          SleepStage.asleepDeep,
        ), // 1h
        sleep(
          DateTime(2026, 4, 23, 3),
          DateTime(2026, 4, 23, 6),
          SleepStage.asleepREM,
        ), // 3h
        sleep(
          DateTime(2026, 4, 23, 6),
          DateTime(2026, 4, 23, 7),
          SleepStage.asleepUnspecified,
        ), // 1h
      ];
      expect(
        lastNightSleepDuration(samples, now),
        const Duration(hours: 8),
      );
    });

    test('inBed and awake intervals are ignored', () {
      final samples = [
        // 30 min of actual sleep → enough to clear the 30 min floor.
        sleep(
          DateTime(2026, 4, 23, 3),
          DateTime(2026, 4, 23, 3, 30),
          SleepStage.asleepCore,
        ),
        // 8 hours of inBed + awake — must NOT contribute.
        sleep(
          DateTime(2026, 4, 22, 22),
          DateTime(2026, 4, 23, 6),
          SleepStage.inBed,
        ),
        sleep(
          DateTime(2026, 4, 23, 4),
          DateTime(2026, 4, 23, 5),
          SleepStage.awake,
        ),
      ];
      expect(
        lastNightSleepDuration(samples, now),
        const Duration(minutes: 30),
      );
    });

    test('interval before the window start is clipped (early portion dropped)',
        () {
      // 19:00 → 22:00 Wed, but window starts 20:00 → only 20:00–22:00
      // (2h) counts. Add another 2h in-window to stay above the 30-min
      // floor visibly.
      final samples = [
        sleep(
          DateTime(2026, 4, 22, 19),
          DateTime(2026, 4, 22, 22),
          SleepStage.asleepCore,
        ),
        sleep(
          DateTime(2026, 4, 22, 22),
          DateTime(2026, 4, 23, 0),
          SleepStage.asleepCore,
        ),
      ];
      expect(
        lastNightSleepDuration(samples, now),
        const Duration(hours: 4),
      );
    });

    test('interval after the window end is clipped (late portion dropped)',
        () {
      // 10:00 → 14:00 Thu, window ends 12:00 → only 10:00–12:00 (2h) counts.
      final samples = [
        sleep(
          DateTime(2026, 4, 23, 10),
          DateTime(2026, 4, 23, 14),
          SleepStage.asleepCore,
        ),
      ];
      expect(
        lastNightSleepDuration(samples, now),
        const Duration(hours: 2),
      );
    });

    test('total below 30 min returns null', () {
      final samples = [
        // 15 min total asleep — below the floor.
        sleep(
          DateTime(2026, 4, 23, 3),
          DateTime(2026, 4, 23, 3, 15),
          SleepStage.asleepCore,
        ),
      ];
      expect(lastNightSleepDuration(samples, now), isNull);
    });

    test('fully-before or fully-after the window: ignored entirely', () {
      final samples = [
        // Tue 10:00–12:00 — well before the window.
        sleep(
          DateTime(2026, 4, 22, 10),
          DateTime(2026, 4, 22, 12),
          SleepStage.asleepCore,
        ),
        // Thu 13:00–15:00 — after the 12:00 window end.
        sleep(
          DateTime(2026, 4, 23, 13),
          DateTime(2026, 4, 23, 15),
          SleepStage.asleepDeep,
        ),
      ];
      expect(lastNightSleepDuration(samples, now), isNull);
    });
  });
}
