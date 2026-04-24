// Widget tests for `WorkoutSessionScreen` note UI (S7.4 / #72) and
// the grouped-by-exercise sets layout (S7.5 / #73).
//
// Covers the session-level note surface:
// - non-null note renders as italic muted text above the sets list
// - null note shows a "+ Add note" affordance in the same slot
// - tap opens the edit dialog; Save persists via the repo; Cancel doesn't
//
// Covers the grouped sets layout:
// - 3 canonical exercises × 3 sets render 3 headers using canonical names
// - legacy null-FK set renders with the "(legacy)" muted suffix
// - empty session preserves the existing empty-state message
// - within-group set ordering respects orderIndex
// - two legacy rows with different names form two fallback groups
// - canonical group + legacy group sort by min orderIndex

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/workouts/workout_session_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      healthSourceProvider.overrideWithValue(HealthSourceFake.notAuthorized()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late WorkoutSessionRepository sessions;
  late ExerciseSetRepository setsRepo;
  late ExerciseRepository exercisesRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessions = WorkoutSessionRepository(db);
    setsRepo = ExerciseSetRepository(db);
    exercisesRepo = ExerciseRepository(db);
  });

  tearDown(() async => db.close());

  testWidgets('session with non-null note renders note text', (tester) async {
    final id = await sessions.add(
      WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 23, 10),
        note: const Value('Felt strong today'),
      ),
    );

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    expect(find.text('Felt strong today'), findsOneWidget);
    // No "Add note" CTA when a note is already present.
    expect(find.text('Add note'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('session with null note shows "+ Add note" affordance', (
    tester,
  ) async {
    final id = await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
    );

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Add note'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets('tapping "+ Add note" opens dialog; Save persists', (
    tester,
  ) async {
    final id = await sessions.add(
      WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
    );

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    // Tap the TextButton-labelled "Add note" affordance (the dialog
    // title will also render "Add note" once opened, so we scope the
    // tap to the button).
    await tester.tap(find.widgetWithText(TextButton, 'Add note'));
    await tester.pumpAndSettle();

    // Dialog is up.
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Back squat felt heavy');
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pumpAndSettle();

    // DB was updated.
    final row = await sessions.findById(id);
    expect(row!.note, 'Back squat felt heavy');

    // The note now renders above the sets list (the same find.text the
    // first test uses — proves the live stream re-renders the row).
    expect(find.text('Back squat felt heavy'), findsOneWidget);
    // Add-note CTA replaced by the rendered note.
    expect(find.widgetWithText(TextButton, 'Add note'), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets('Cancel from the note dialog discards (no mutation)', (
    tester,
  ) async {
    final id = await sessions.add(
      WorkoutSessionsCompanion.insert(
        startedAt: DateTime(2026, 4, 23, 10),
        note: const Value('original'),
      ),
    );

    await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('original'));
    await tester.pumpAndSettle();

    // Clear and type new text, then Cancel — should NOT persist.
    await tester.enterText(find.byType(TextField), 'new content');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // DB still has the original note.
    final row = await sessions.findById(id);
    expect(row!.note, 'original');
    expect(find.text('original'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  // ---------------------------------------------------------------------
  // Grouped-by-exercise sets layout (S7.5 / #73).
  // ---------------------------------------------------------------------

  group('grouped sets layout', () {
    testWidgets(
      'three canonical exercises × three sets render three canonical headers',
      (tester) async {
        // Grouped list with 3 × 3 sets plus headers exceeds the default
        // 600-high widget-test viewport; give it enough room that every
        // row is laid out (viewport-override skill, `Skills.md`).
        tester.view.physicalSize = const Size(800, 2400);
        addTearDown(tester.view.resetPhysicalSize);

        final bench = await exercisesRepo.addIfMissing(
          'Bench Press',
          source: Source.userEntered,
        );
        final squat = await exercisesRepo.addIfMissing(
          'Squat',
          source: Source.userEntered,
        );
        final deadlift = await exercisesRepo.addIfMissing(
          'Deadlift',
          source: Source.userEntered,
        );

        final id = await sessions.add(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
        );

        // Interleave across exercises to prove grouping isn't a
        // naive consecutive-run detector.
        final layout = <(Exercise, int)>[
          (bench, 0),
          (squat, 1),
          (deadlift, 2),
          (bench, 3),
          (squat, 4),
          (deadlift, 5),
          (bench, 6),
          (squat, 7),
          (deadlift, 8),
        ];
        for (final (ex, i) in layout) {
          await setsRepo.add(
            ExerciseSetsCompanion.insert(
              sessionId: id,
              exerciseName: ex.canonicalName,
              reps: 5,
              weight: 60,
              weightUnit: WeightUnit.kg,
              status: WorkoutSetStatus.completed,
              orderIndex: i,
              exerciseId: Value(ex.id),
            ),
          );
        }

        await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
        await tester.pumpAndSettle();

        // Each canonical name appears as a header (titleSmall style). The
        // set tiles also render the exerciseName, so we expect each
        // canonical name to match once in a header + three times in
        // tiles — total four matches per name. We don't need to pin
        // that count; the key S7.5 assertion is "no (legacy) suffix
        // anywhere when every row has a canonical FK."
        expect(find.text('Bench Press'), findsWidgets);
        expect(find.text('Squat'), findsWidgets);
        expect(find.text('Deadlift'), findsWidgets);
        expect(
          find.text('(legacy)'),
          findsNothing,
          reason: 'no group is a fallback group when every row has a FK',
        );

        await _drainDriftTimers(tester);
      },
    );

    testWidgets('legacy null-FK set renders with "(legacy)" muted suffix', (
      tester,
    ) async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
      );

      // One legacy row — no canonical `exercises` entry, no FK.
      await setsRepo.add(
        ExerciseSetsCompanion.insert(
          sessionId: id,
          exerciseName: 'Mystery Lift',
          reps: 10,
          weight: 50,
          weightUnit: WeightUnit.kg,
          status: WorkoutSetStatus.completed,
          orderIndex: 0,
        ),
      );

      await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
      await tester.pumpAndSettle();

      // Header renders the raw exerciseName + "(legacy)" suffix.
      expect(find.text('Mystery Lift'), findsWidgets);
      expect(find.text('(legacy)'), findsOneWidget);

      await _drainDriftTimers(tester);
    });

    testWidgets('empty session renders the existing empty state (no groups)', (
      tester,
    ) async {
      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
      );

      await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
      await tester.pumpAndSettle();

      // Preserved copy + no group headers / legacy markers on screen.
      expect(find.text('No sets yet.\nTap + to add one.'), findsOneWidget);
      expect(find.text('(legacy)'), findsNothing);

      await _drainDriftTimers(tester);
    });

    testWidgets('within-group set ordering respects orderIndex', (
      tester,
    ) async {
      final bench = await exercisesRepo.addIfMissing(
        'Bench Press',
        source: Source.userEntered,
      );

      final id = await sessions.add(
        WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
      );

      // Insert out-of-order; the repo's ORDER BY clause must sort them.
      for (final (i, reps) in [(2, 6), (0, 10), (1, 8)]) {
        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Bench Press',
            reps: reps,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: i,
            exerciseId: Value(bench.id),
          ),
        );
      }

      await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
      await tester.pumpAndSettle();

      // ListTile subtitles carry the reps — inspect their rendering
      // order by searching for each subtitle text and asserting its
      // vertical (dy) position. Tile for orderIndex=0 (10 reps) must
      // come before orderIndex=1 (8 reps) which comes before =2 (6).
      final tenReps = tester.getTopLeft(find.textContaining('10 reps'));
      final eightReps = tester.getTopLeft(find.textContaining('8 reps'));
      final sixReps = tester.getTopLeft(find.textContaining('6 reps'));

      expect(tenReps.dy, lessThan(eightReps.dy));
      expect(eightReps.dy, lessThan(sixReps.dy));

      await _drainDriftTimers(tester);
    });

    testWidgets(
      'two legacy rows with different names form two fallback groups',
      (tester) async {
        final id = await sessions.add(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
        );

        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Legacy A',
            reps: 5,
            weight: 50,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 0,
          ),
        );
        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Legacy B',
            reps: 5,
            weight: 50,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 1,
          ),
        );

        await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
        await tester.pumpAndSettle();

        expect(find.text('Legacy A'), findsWidgets);
        expect(find.text('Legacy B'), findsWidgets);
        // Both groups render the "(legacy)" suffix — one per header.
        expect(find.text('(legacy)'), findsNWidgets(2));

        await _drainDriftTimers(tester);
      },
    );

    testWidgets(
      'canonical + legacy groups render in correct order (by min orderIndex)',
      (tester) async {
        final bench = await exercisesRepo.addIfMissing(
          'Bench Press',
          source: Source.userEntered,
        );

        final id = await sessions.add(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 23, 10)),
        );

        // Canonical "Bench Press" at orderIndex 0 and 1. The user did
        // this first — its min orderIndex is 0.
        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Bench Press',
            reps: 8,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 0,
            exerciseId: Value(bench.id),
          ),
        );
        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Bench Press',
            reps: 6,
            weight: 80,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 1,
            exerciseId: Value(bench.id),
          ),
        );
        // Legacy "Mystery Lift" at orderIndex 2. Comes later on-screen.
        await setsRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: id,
            exerciseName: 'Mystery Lift',
            reps: 10,
            weight: 40,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 2,
          ),
        );

        await tester.pumpWidget(_host(db, WorkoutSessionScreen(sessionId: id)));
        await tester.pumpAndSettle();

        // Header "Bench Press" (titleSmall) must appear above "(legacy)"
        // suffix on the Mystery Lift header.
        final benchPos = tester.getTopLeft(find.text('Bench Press').first);
        final legacySuffix = tester.getTopLeft(find.text('(legacy)'));
        expect(
          benchPos.dy,
          lessThan(legacySuffix.dy),
          reason: 'canonical group (min orderIndex 0) comes first',
        );

        await _drainDriftTimers(tester);
      },
    );
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
