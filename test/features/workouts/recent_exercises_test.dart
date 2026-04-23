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
    // Sets have a NOT NULL FK to sessions with `ON DELETE CASCADE` under
    // `PRAGMA foreign_keys = ON`. A parent session row is required
    // before any set seed.
    sessionId = await sessionRepo.add(WorkoutSessionsCompanion.insert(
      startedAt: DateTime(2026, 4, 23, 18),
    ));
  });

  tearDown(() async => db.close());

  Future<void> seedSet(String name, int orderIndex) {
    return setsRepo.add(ExerciseSetsCompanion.insert(
      sessionId: sessionId,
      exerciseName: name,
      reps: 5,
      weight: 80,
      weightUnit: WeightUnit.kg,
      status: WorkoutSetStatus.completed,
      orderIndex: orderIndex,
    ));
  }

  testWidgets(
      'renders a chip per distinct recent exercise in newest-first order',
      (tester) async {
    await seedSet('Squat', 0);
    await seedSet('Bench Press', 1);
    await seedSet('Row', 2);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 3),
    ));
    await tester.pumpAndSettle();

    final chips = find.byType(ActionChip);
    expect(chips, findsNWidgets(3));

    // Recency order: latest insert first.
    expect(find.descendant(of: chips.at(0), matching: find.text('Row')),
        findsOneWidget);
    expect(find.descendant(of: chips.at(1), matching: find.text('Bench Press')),
        findsOneWidget);
    expect(find.descendant(of: chips.at(2), matching: find.text('Squat')),
        findsOneWidget);

    await _drainDriftTimers(tester);
  });

  testWidgets(
      'empty state: no ActionChips render when the DB has no sets',
      (tester) async {
    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 0),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ActionChip), findsNothing);

    await _drainDriftTimers(tester);
  });

  testWidgets(
      'tapping a chip fills the Exercise TextFormField with that value',
      (tester) async {
    await seedSet('Overhead Press', 0);
    await seedSet('Deadlift', 1);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 2),
    ));
    await tester.pumpAndSettle();

    // Start empty — the Exercise field is blank on the add form.
    expect(
      find.widgetWithText(TextFormField, 'Overhead Press'),
      findsNothing,
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Overhead Press'));
    await tester.pump();

    // After tap, the TextFormField labeled 'Exercise' now contains
    // 'Overhead Press'.
    expect(
      find.widgetWithText(TextFormField, 'Overhead Press'),
      findsOneWidget,
    );

    await _drainDriftTimers(tester);
  });

  testWidgets('tapping a chip parks the caret at the end of the name',
      (tester) async {
    await seedSet('Bench Press', 0);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 1),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Bench Press'));
    await tester.pump();

    // Grab the EditableText under the Exercise TextFormField and confirm
    // both the text and the caret position.
    final field = find.widgetWithText(TextFormField, 'Bench Press');
    expect(field, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    );
    expect(editable.controller.text, 'Bench Press');
    expect(
      editable.controller.selection,
      TextSelection.fromPosition(
        const TextPosition(offset: 'Bench Press'.length),
      ),
    );

    await _drainDriftTimers(tester);
  });

  testWidgets('tapping a chip does not auto-save the set', (tester) async {
    await seedSet('Deadlift', 0);

    await tester.pumpWidget(_host(
      db,
      ExerciseSetFormScreen(sessionId: sessionId, nextOrderIndex: 1),
    ));
    await tester.pumpAndSettle();

    final before = await setsRepo.listForSession(sessionId);
    expect(before, hasLength(1));

    await tester.tap(find.widgetWithText(ActionChip, 'Deadlift'));
    await tester.pump();

    // No new row until the user hits Save — tap only refills the field.
    final after = await setsRepo.listForSession(sessionId);
    expect(after, hasLength(1));

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
