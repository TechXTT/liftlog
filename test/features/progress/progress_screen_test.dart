import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/body_weight_log_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/food_entry_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/progress/progress_data.dart';
import 'package:liftlog_app/features/progress/progress_providers.dart';
import 'package:liftlog_app/features/progress/progress_screen.dart';
import 'package:liftlog_app/features/progress/weekly_volume_bars.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/shell/root_shell.dart';

void main() {
  late AppDatabase db;

  // Frozen "now" anchoring all windows to 2026-04-23 so the test data lands
  // inside 7d / 30d / all deterministically.
  final fakeNow = DateTime(2026, 4, 23, 12);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app({List<Override> extra = const []}) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressNowProvider.overrideWithValue(fakeNow),
          ...extra,
        ],
        child: const MaterialApp(home: ProgressScreen()),
      );

  testWidgets('tab appears as 5th icon in root shell and tapping renders Progress',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          progressNowProvider.overrideWithValue(fakeNow),
        ],
        child: const MaterialApp(home: RootShell()),
      ),
    );
    await tester.pumpAndSettle();

    // 5 destinations total.
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Progress'), findsOneWidget);

    // Tap the Progress tab — screen should render its AppBar title.
    await tester.tap(find.text('Progress'));
    await tester.pumpAndSettle();

    // AppBar title "Progress" + the NavigationDestination label "Progress"
    // both exist — so we expect at least 2 occurrences.
    expect(find.text('Progress'), findsAtLeastNWidgets(2));
    // Empty DB → combined empty-state copy renders (per AC #4).
    expect(find.text('Not enough data yet.'), findsOneWidget);
    // Segmented selector is always visible.
    expect(find.text('7d'), findsOneWidget);
    expect(find.text('30d'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('window toggle swaps the kcal series length', (tester) async {
    // Fixture: an entry 10 days ago (inside 30d, outside 7d) + an entry today.
    final foodRepo = FoodEntryRepository(db);
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: fakeNow.subtract(const Duration(days: 10)),
      name: const Value('Old meal'),
      kcal: 400,
      proteinG: 20.0,
      mealType: MealType.lunch,
      entryType: FoodEntryType.manual,
    ));
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: fakeNow,
      name: const Value('Today meal'),
      kcal: 600,
      proteinG: 30.0,
      mealType: MealType.lunch,
      entryType: FoodEntryType.manual,
    ));
    // Two weight logs so the sparkline shows up; both in-window for all three.
    final wRepo = BodyWeightLogRepository(db);
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow.subtract(const Duration(days: 2)),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow,
      value: 80.5,
      unit: WeightUnit.kg,
    ));

    // Start at 7d — only the "today" food entry is inside.
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Grab the KcalSeries exposed via the provider to assert day-count.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProgressScreen)),
    );
    KcalSeries kcal = await container.read(kcalSeriesProvider.future);
    expect(kcal.days.length, 7, reason: '7d window → 7 buckets');
    expect(kcal.loggedDayCount, 1, reason: 'only today is logged inside 7d');

    // Flip to 30d via provider-override style tap on the segmented button.
    await tester.tap(find.text('30d'));
    await tester.pumpAndSettle();

    kcal = await container.read(kcalSeriesProvider.future);
    expect(kcal.days.length, 30, reason: '30d window → 30 buckets');
    expect(kcal.loggedDayCount, 2,
        reason: 'both the 10-day-old entry and today are inside 30d');

    // Flip to All — in this fixture the oldest entry is 10 days back, so the
    // aggregator emits ~11 buckets (today inclusive).
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    kcal = await container.read(kcalSeriesProvider.future);
    expect(kcal.days.length, 11);
    expect(kcal.loggedDayCount, 2);

    await _drainDriftTimers(tester);
  });

  testWidgets('mixed-unit window shows banner and renders single-unit sparkline',
      (tester) async {
    final wRepo = BodyWeightLogRepository(db);
    // Older entry in lb, newer entry in kg — dominant should be kg.
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow.subtract(const Duration(days: 2)),
      value: 176.0,
      unit: WeightUnit.lb,
    ));
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow.subtract(const Duration(days: 1)),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow,
      value: 80.5,
      unit: WeightUnit.kg,
    ));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Mixed units — showing kg only'), findsOneWidget);

    // Painter receives the series via the provider; assert it's kg-only.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProgressScreen)),
    );
    final w = await container.read(weightSeriesProvider.future);
    expect(w.dominantUnit, WeightUnit.kg);
    expect(w.mixedUnits, isTrue);
    expect(w.points.length, 2);
    expect(w.points.every((p) => p.value < 100), isTrue,
        reason: 'lb value 176 must be dropped, never silently converted');

    await _drainDriftTimers(tester);
  });

  testWidgets('weight-only-empty: kcal renders, weight shows empty copy',
      (tester) async {
    final foodRepo = FoodEntryRepository(db);
    await foodRepo.add(FoodEntriesCompanion.insert(
      timestamp: fakeNow,
      name: const Value('Lunch'),
      kcal: 500,
      proteinG: 30.0,
      mealType: MealType.lunch,
      entryType: FoodEntryType.manual,
    ));
    // No weight logs at all.

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.text('Not enough weight data yet — log at least 2 entries.'),
      findsOneWidget,
    );
    expect(find.text('No calorie data for this window.'), findsNothing);
    expect(find.text('Not enough data yet.'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('kcal-only-empty: weight renders, kcal shows empty copy',
      (tester) async {
    final wRepo = BodyWeightLogRepository(db);
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow.subtract(const Duration(days: 2)),
      value: 80.0,
      unit: WeightUnit.kg,
    ));
    await wRepo.add(BodyWeightLogsCompanion.insert(
      timestamp: fakeNow,
      value: 80.5,
      unit: WeightUnit.kg,
    ));
    // No food entries.

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('No calorie data for this window.'), findsOneWidget);
    expect(
      find.text('Not enough weight data yet — log at least 2 entries.'),
      findsNothing,
    );
    expect(find.text('Not enough data yet.'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('both-empty: shows single combined message, no per-section empty',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Not enough data yet.'), findsOneWidget);
    // The per-section empty copy must NOT appear when the combined message
    // is shown — otherwise the user sees three empty messages stacked.
    expect(
      find.text('Not enough weight data yet — log at least 2 entries.'),
      findsNothing,
    );
    expect(find.text('No calorie data for this window.'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets(
      'weekly-volume: empty section copy renders when there are no completed sets',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Dedicated copy for the volume section — distinct from the weight /
    // kcal empty-state copy and from the combined empty message.
    expect(
      find.text('Workouts — completed sets/week (last 8 weeks)'),
      findsOneWidget,
    );
    expect(
      find.text('No completed sets in the last 8 weeks.'),
      findsOneWidget,
    );
    // Bars must not render when the series is empty.
    expect(find.byType(WeeklyVolumeBars), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets(
      'weekly-volume: bars render when there are completed sets, '
      'planned/skipped excluded', (tester) async {
    final sessionRepo = WorkoutSessionRepository(db);
    final setRepo = ExerciseSetRepository(db);

    // Session this current week (Monday 2026-04-20). fakeNow is Thu 4/23.
    final sessionId = await sessionRepo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 22, 18),
    ));
    // 3 completed, 2 planned, 1 skipped → only 3 counted.
    final statuses = [
      WorkoutSetStatus.completed,
      WorkoutSetStatus.completed,
      WorkoutSetStatus.completed,
      WorkoutSetStatus.planned,
      WorkoutSetStatus.planned,
      WorkoutSetStatus.skipped,
    ];
    for (var i = 0; i < statuses.length; i++) {
      await setRepo.add(ExerciseSetsCompanion.insert(
        sessionId: sessionId,
        exerciseName: 'Bench Press',
        reps: 8,
        weight: 80.0,
        weightUnit: WeightUnit.kg,
        status: statuses[i],
        orderIndex: i,
      ));
    }

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(WeeklyVolumeBars), findsOneWidget);
    expect(
      find.text('No completed sets in the last 8 weeks.'),
      findsNothing,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProgressScreen)),
    );
    final volume = await container.read(weeklyVolumeProvider.future);
    expect(volume.completedSets.length, 8);
    expect(volume.completedSets.last, 3,
        reason: 'only completed sets count; planned and skipped excluded');
    expect(volume.isEmpty, isFalse);

    await _drainDriftTimers(tester);
  });
}

/// Drift schedules a zero-duration Timer when its stream is cancelled on
/// dispose. Advance fake_async's clock so the Timer fires before the
/// framework's post-test !timersPending invariant check runs.
Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
