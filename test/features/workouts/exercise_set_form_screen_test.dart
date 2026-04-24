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
  late ExerciseRepository exercisesRepo;
  late int sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = WorkoutSessionRepository(db);
    setsRepo = ExerciseSetRepository(db);
    exercisesRepo = ExerciseRepository(db);
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

  // ---------------------------------------------------------------------
  // Canonical exercise picker (#60)
  // ---------------------------------------------------------------------

  testWidgets(
      'typeahead: select existing exercise links set.exerciseId to its row',
      (tester) async {
    // Seed three canonical exercises; only one has "Be" as a prefix.
    await exercisesRepo.addIfMissing('Squat', source: Source.userEntered);
    final bench =
        await exercisesRepo.addIfMissing('Bench Press', source: Source.userEntered);
    await exercisesRepo.addIfMissing('Deadlift', source: Source.userEntered);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 0),
    ));
    await tester.pumpAndSettle();

    // Type into the Exercise field. The Autocomplete widget's
    // optionsBuilder is async (it awaits listAll), so we pumpAndSettle
    // to let the suggestion overlay appear.
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise'), 'Be');
    await tester.pumpAndSettle();

    // Exactly one suggestion — "Bench Press" — is rendered in the overlay.
    // The field text itself also equals "Be", so the "Bench Press" visible
    // in the overlay is distinct from the field content.
    expect(find.text('Bench Press'), findsOneWidget);

    // Tap the suggestion. This fires Autocomplete.onSelected, which both
    // populates the text field to "Bench Press" and latches the
    // canonical exerciseId in the screen state.
    await tester.tap(find.text('Bench Press'));
    await tester.pumpAndSettle();

    // Fill the remaining fields and save.
    await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '8');
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '80');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final list = await setsRepo.listForSession(sessionId);
    expect(list, hasLength(1));
    final s = list.single;
    expect(s.exerciseName, 'Bench Press');
    expect(s.exerciseId, bench.id,
        reason: 'tapping a suggestion must link the canonical exercises row');

    // No new exercises row was created — the existing one was reused.
    final all = await exercisesRepo.listAll();
    expect(all, hasLength(3));
  });

  testWidgets(
      'type-new-name: save creates a new exercises row and links the set',
      (tester) async {
    // No pre-seeded exercises. The form must insert a new row on save
    // and link the set's FK to it.
    expect(await exercisesRepo.listAll(), isEmpty);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 0),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Exercise'), 'Deadlift');
    await tester.pumpAndSettle();

    // With an empty exercises table there are no suggestions — the user
    // types a brand-new name and saves. The screen must take the
    // find-or-create branch (findByName miss → addIfMissingUserEntered).
    await tester.enterText(find.widgetWithText(TextFormField, 'Reps'), '5');
    await tester.enterText(find.widgetWithText(TextFormField, 'Weight'), '140');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final exercises = await exercisesRepo.listAll();
    expect(exercises, hasLength(1),
        reason: 'a brand-new exercise name must create one canonical row');
    final created = exercises.single;
    expect(created.canonicalName, 'Deadlift');

    final sets = await setsRepo.listForSession(sessionId);
    expect(sets, hasLength(1));
    expect(sets.single.exerciseId, created.id,
        reason: 'the just-saved set must link to the freshly-created row');
  });

  testWidgets('edit: existing exerciseId → field prefilled with canonical name',
      (tester) async {
    final bench =
        await exercisesRepo.addIfMissing('Bench Press', source: Source.userEntered);
    await setsRepo.add(ExerciseSetsCompanion.insert(
      sessionId: sessionId,
      exerciseName: 'Bench Press',
      reps: 8,
      weight: 80,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.completed,
      orderIndex: 0,
      exerciseId: Value(bench.id),
    ));
    final existing = (await setsRepo.listForSession(sessionId)).single;
    expect(existing.exerciseId, bench.id, reason: 'seeded with FK set');

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, existing: existing),
    ));
    await tester.pumpAndSettle();

    // Field prefilled with the canonical name. Scope to the TextFormField
    // so we don't also match the recent-exercises chip with the same name.
    expect(find.widgetWithText(TextFormField, 'Bench Press'), findsOneWidget);

    // Re-save without editing; the FK must survive the round trip.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await setsRepo.listForSession(sessionId)).single;
    expect(after.exerciseId, bench.id,
        reason: 'edit save preserves the canonical exerciseId');
  });

  testWidgets('edit: null exerciseId → field prefilled with raw exerciseName',
      (tester) async {
    // Seed a set without linking it to any `exercises` row — mirrors the
    // pre-S5.1 state where historical rows have `exercise_id = null` and
    // no matching canonical entry exists to backfill from.
    await setsRepo.add(ExerciseSetsCompanion.insert(
      sessionId: sessionId,
      exerciseName: 'Legacy Lift',
      reps: 10,
      weight: 50,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.completed,
      orderIndex: 0,
    ));
    final existing = (await setsRepo.listForSession(sessionId)).single;
    expect(existing.exerciseId, isNull,
        reason: 'precondition: the seeded row has no FK');

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, existing: existing),
    ));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Legacy Lift'), findsOneWidget);
  });
}
