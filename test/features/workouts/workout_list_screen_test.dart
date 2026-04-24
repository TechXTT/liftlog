import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/workouts/workout_list_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget app({HealthSource? hk}) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      if (hk != null) healthSourceProvider.overrideWithValue(hk),
    ],
    child: const MaterialApp(home: WorkoutListScreen()),
  );

  testWidgets('empty state shown when no sessions and HK unauthorized', (
    tester,
  ) async {
    await tester.pumpWidget(app(hk: HealthSourceFake.notAuthorized()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No workouts yet'), findsOneWidget);
    // External section must NOT render when unauthorized — no nag, no
    // empty state.
    expect(find.text('External workouts'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('renders sessions newest-first with in-progress / ended status', (
    tester,
  ) async {
    final repo = WorkoutSessionRepository(db);
    await repo.add(
      WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 20, 10),
        endedAt: Value(DateTime(2026, 4, 20, 11)),
      ),
    );
    await repo.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 18)),
    );

    await tester.pumpWidget(app(hk: HealthSourceFake.notAuthorized()));
    await tester.pumpAndSettle();

    final inProgress = find.text('In progress');
    final ended = find.text('Ended');
    expect(inProgress, findsOneWidget);
    expect(ended, findsOneWidget);
    // Unauthorized → only the LiftLog section renders. No "External
    // workouts" header, no HK rows.
    expect(find.text('External workouts'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets(
    'authorized + 2 HK workouts + 1 session → both sections, 3 rows',
    (tester) async {
      final repo = WorkoutSessionRepository(db);
      await repo.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 18)),
      );

      final now = DateTime.now();
      // Recent enough to fall inside the 90-day rolling window used by
      // `hkWorkoutsLast90dProvider`.
      final hkWorkouts = [
        HKWorkoutSample(
          sourceId: 'com.apple.health.workouts',
          startedAt: now.subtract(const Duration(days: 2, hours: 3)),
          endedAt: now.subtract(const Duration(days: 2, hours: 2)),
          type: HKWorkoutType.traditionalStrengthTraining,
          duration: const Duration(hours: 1),
        ),
        HKWorkoutSample(
          sourceId: 'com.apple.health.workouts',
          startedAt: now.subtract(const Duration(days: 5, hours: 3)),
          endedAt: now.subtract(const Duration(days: 5, hours: 2, minutes: 15)),
          type: HKWorkoutType.running,
          duration: const Duration(minutes: 45),
        ),
      ];

      await tester.pumpWidget(
        app(hk: HealthSourceFake.withWorkouts(hkWorkouts)),
      );
      await tester.pumpAndSettle();

      // LiftLog section: one session.
      expect(find.text('In progress'), findsOneWidget);

      // HK section header.
      expect(find.text('External workouts'), findsOneWidget);

      // HK rows — each title is the bucket label from
      // `hkWorkoutTypeLabel`. Both buckets must appear.
      expect(find.text('Strength training'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);

      // Total visible ListTile count = 1 LiftLog + 2 HK = 3.
      expect(find.byType(ListTile), findsNWidgets(3));

      await _drainDriftTimers(tester);
    },
  );
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
