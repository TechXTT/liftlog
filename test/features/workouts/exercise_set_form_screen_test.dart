import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/workouts/exercise_set_form_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: child),
  );
}

void main() {
  late AppDatabase db;
  late WorkoutSessionRepository sessionRepo;
  late ExerciseSetRepository setsRepo;
  late int sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = WorkoutSessionRepository(db);
    setsRepo = ExerciseSetRepository(db);
    sessionId = await sessionRepo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 18),
    ));
  });

  tearDown(() async => db.close());

  testWidgets('add form validates required name and numeric fields',
      (tester) async {
    await tester.pumpWidget(_host(db, ExerciseSetFormScreen(sessionId: sessionId)));

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Exercise name is required'), findsOneWidget);
    expect(find.text('Enter a whole number'), findsOneWidget);
    expect(find.text('Enter a number'), findsOneWidget);
  });

  testWidgets('valid save persists a set with correct session id, enums',
      (tester) async {
    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 0),
    ));

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise'), 'Bench Press');
    await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '8');
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '80');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final list = await setsRepo.listForSession(sessionId);
    expect(list, hasLength(1));
    final s = list.single;
    expect(s.sessionId, sessionId);
    expect(s.exerciseName, 'Bench Press');
    expect(s.reps, 8);
    expect(s.weight, 80.0);
    expect(s.weightUnit, WeightUnit.kg);
    expect(s.status, WorkoutSetStatus.completed);
    expect(s.orderIndex, 0);
  });

  testWidgets('edit preserves fields and updates on save', (tester) async {
    await setsRepo.add(ExerciseSetsCompanion.insert(
      sessionId: sessionId,
      exerciseName: 'Squat',
      reps: 5,
      weight: 100,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.planned,
      orderIndex: 0,
    ));
    final existing = (await setsRepo.listForSession(sessionId)).single;

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, existing: existing),
    ));
    await tester.pumpAndSettle();

    // The Exercise field must be pre-filled with the existing set's name.
    // Scope to the TextFormField so we don't also match the recent-
    // exercises chip (issue #39) that now renders the same name.
    expect(find.widgetWithText(TextFormField, 'Squat'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '6');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await setsRepo.listForSession(sessionId)).single;
    expect(after.reps, 6);
    expect(after.status, WorkoutSetStatus.planned, reason: 'status unchanged');
  });

  testWidgets('delete set → confirm removes it', (tester) async {
    await setsRepo.add(ExerciseSetsCompanion.insert(
      sessionId: sessionId,
      exerciseName: 'Row',
      reps: 10,
      weight: 50,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.completed,
      orderIndex: 0,
    ));
    final existing = (await setsRepo.listForSession(sessionId)).single;

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, existing: existing),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete set'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await setsRepo.listForSession(sessionId), isEmpty);
  });
}
