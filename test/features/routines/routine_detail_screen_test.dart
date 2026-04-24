// Widget tests for `RoutineDetailScreen` (#61).
//
// Renders a routine with a couple of line items, asserts the detail
// displays them with formatted targets, and exercises the
// "Start workout" flow end-to-end: the service seeds planned sets +
// the screen navigates to `WorkoutSessionScreen`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/routines/routine_detail_screen.dart';
import 'package:liftlog_app/features/workouts/workout_session_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late RoutineRepository routineRepo;
  late ExerciseRepository exerciseRepo;
  late ExerciseSetRepository setsRepo;
  late WorkoutSessionRepository sessionRepo;
  late int benchId;
  late int squatId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    routineRepo = RoutineRepository(db);
    exerciseRepo = ExerciseRepository(db);
    setsRepo = ExerciseSetRepository(db);
    sessionRepo = WorkoutSessionRepository(db);
    final bench = await exerciseRepo.addIfMissing(
      'Bench Press',
      source: Source.userEntered,
    );
    final squat = await exerciseRepo.addIfMissing(
      'Squat',
      source: Source.userEntered,
    );
    benchId = bench.id;
    squatId = squat.id;
  });

  tearDown(() async => db.close());

  Future<int> seedRoutine() async {
    final id = await routineRepo.add(
      RoutinesCompanion.insert(
        name: 'Push A',
        notes: const Value('Upper body'),
        createdAt: DateTime(2026, 4, 20),
      ),
    );
    await routineRepo.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: id,
        exerciseId: benchId,
        orderIndex: 0,
        targetSets: const Value(3),
        targetReps: const Value(8),
        targetWeight: const Value(80),
        targetWeightUnit: const Value(WeightUnit.kg),
      ),
    );
    await routineRepo.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: id,
        exerciseId: squatId,
        orderIndex: 1,
        targetSets: const Value(4),
        targetReps: const Value(5),
      ),
    );
    return id;
  }

  testWidgets('renders routine name, notes, and line items', (tester) async {
    final id = await seedRoutine();

    await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
    await tester.pumpAndSettle();

    expect(find.text('Push A'), findsOneWidget);
    expect(find.text('Upper body'), findsOneWidget);
    expect(find.text('Bench Press'), findsOneWidget);
    expect(find.text('Squat'), findsOneWidget);
    // Targets rendered as "N × M" (and weight when present).
    expect(find.text('3 × 8 · 80 kg'), findsOneWidget);
    expect(find.text('4 × 5'), findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets(
    'Start workout seeds planned sets + navigates to WorkoutSessionScreen',
    (tester) async {
      final id = await seedRoutine();

      await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start workout'));
      await tester.pumpAndSettle();

      // Confirm dialog opens — tap Start to proceed without editing the note.
      await tester.tap(find.widgetWithText(TextButton, 'Start'));
      await tester.pumpAndSettle();

      // Navigation landed on WorkoutSessionScreen.
      expect(find.byType(WorkoutSessionScreen), findsOneWidget);
      // Routine detail replaced — back nav returns to Routines, not detail.
      expect(find.byType(RoutineDetailScreen), findsNothing);

      // Session created with seeded sets.
      final sessions = await sessionRepo.listAll();
      expect(sessions, hasLength(1));
      final sessionId = sessions.single.id;
      final sets = await setsRepo.listForSession(sessionId);
      // 3 bench + 4 squat = 7 total seeded sets.
      expect(sets, hasLength(7));
      for (var i = 0; i < sets.length; i++) {
        expect(sets[i].status, WorkoutSetStatus.planned);
        expect(sets[i].orderIndex, i);
      }
      // First 3 → Bench Press.
      expect(sets.take(3).every((s) => s.exerciseId == benchId), isTrue);
      // Next 4 → Squat.
      expect(sets.skip(3).every((s) => s.exerciseId == squatId), isTrue);

      await _drainDriftTimers(tester);
    },
  );

  testWidgets(
    'Start workout confirm dialog pre-populates from routine.notes and '
    'persists on confirm',
    (tester) async {
      final id = await seedRoutine();

      await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start workout'));
      await tester.pumpAndSettle();

      // Dialog renders with the routine's notes pre-populated in the field.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.widgetWithText(TextField, 'Upper body'),
        findsOneWidget,
        reason: 'note field pre-populated from routines.notes',
      );

      // Edit the note before confirming.
      await tester.enterText(find.byType(TextField), 'Starting strong');
      await tester.tap(find.widgetWithText(TextButton, 'Start'));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutSessionScreen), findsOneWidget);

      final sessions = await sessionRepo.listAll();
      expect(sessions, hasLength(1));
      expect(sessions.single.note, 'Starting strong');

      await _drainDriftTimers(tester);
    },
  );

  testWidgets(
    'Start workout confirm dialog Cancel aborts (no session created)',
    (tester) async {
      final id = await seedRoutine();

      await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start workout'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // No navigation; no session; still on the detail screen.
      expect(find.byType(WorkoutSessionScreen), findsNothing);
      expect(find.byType(RoutineDetailScreen), findsOneWidget);
      expect(await sessionRepo.listAll(), isEmpty);

      await _drainDriftTimers(tester);
    },
  );

  testWidgets(
    'Start workout confirm dialog clearing the note persists null',
    (tester) async {
      final id = await seedRoutine();

      await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Start workout'));
      await tester.pumpAndSettle();

      // Clear pre-populated note, then confirm.
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.widgetWithText(TextButton, 'Start'));
      await tester.pumpAndSettle();

      final sessions = await sessionRepo.listAll();
      expect(sessions, hasLength(1));
      expect(
        sessions.single.note,
        isNull,
        reason: 'empty string normalizes to null',
      );

      await _drainDriftTimers(tester);
    },
  );

  testWidgets('Start workout disabled when routine has no exercises', (
    tester,
  ) async {
    final id = await routineRepo.add(
      RoutinesCompanion.insert(name: 'Empty', createdAt: DateTime(2026, 4, 20)),
    );

    await tester.pumpWidget(_host(db, RoutineDetailScreen(routineId: id)));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start workout'),
    );
    expect(button.onPressed, isNull);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
