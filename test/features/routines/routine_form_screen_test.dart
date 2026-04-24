// Widget tests for `RoutineFormScreen` (#61).
//
// Covers create, edit, reorder, and delete flows. The Exercise picker
// reuses the S6.2 Autocomplete pattern — we seed the `Exercises` catalog
// up-front and drive the picker by tapping suggestions (same technique
// as `exercise_set_form_screen_test.dart`).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/features/routines/routine_form_screen.dart';
import 'package:liftlog_app/providers/app_providers.dart';

Widget _host(AppDatabase db, Widget child) {
  return ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: child),
  );
}

/// Sets a tall viewport so multi-row forms fit on one screen without
/// scrolling. The default 800×600 test surface clips the second row's
/// bottom controls + the "Add exercise" / "Save" affordances once two
/// exercise cards are stacked. We expand vertically only — width stays
/// at the Material default.
void _useTallViewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 2400);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late AppDatabase db;
  late RoutineRepository routineRepo;
  late ExerciseRepository exerciseRepo;
  late int benchId;
  late int squatId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    routineRepo = RoutineRepository(db);
    exerciseRepo = ExerciseRepository(db);
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

  /// Fills the Nth exercise row's Autocomplete field + target ints.
  /// Seeds targetSets/targetReps only (weight omitted → bodyweight).
  Future<void> fillRow(
    WidgetTester tester, {
    required int rowIndex,
    required String exerciseName,
    required String sets,
    required String reps,
  }) async {
    // There may be multiple 'Exercise' TextFormFields — scope by rowIndex.
    final exerciseFields = find.widgetWithText(TextFormField, 'Exercise');
    await tester.enterText(exerciseFields.at(rowIndex), exerciseName);
    await tester.pumpAndSettle();
    // Tap the Autocomplete suggestion to latch the canonical id.
    await tester.tap(find.text(exerciseName).last);
    await tester.pumpAndSettle();

    final setsFields = find.widgetWithText(TextFormField, 'Sets');
    final repsFields = find.widgetWithText(TextFormField, 'Reps');
    await tester.enterText(setsFields.at(rowIndex), sets);
    await tester.enterText(repsFields.at(rowIndex), reps);
    await tester.pumpAndSettle();
  }

  testWidgets('create routine with 2 exercises → saves + persists',
      (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(_host(db, const RoutineFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Push A',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes'),
      'Feels good',
    );

    // Add first row, fill with Bench Press / 3 / 8.
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await fillRow(
      tester,
      rowIndex: 0,
      exerciseName: 'Bench Press',
      sets: '3',
      reps: '8',
    );

    // Add second row, fill with Squat / 4 / 5.
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await fillRow(
      tester,
      rowIndex: 1,
      exerciseName: 'Squat',
      sets: '4',
      reps: '5',
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // Routine row persisted.
    final routines = await routineRepo.listAll();
    expect(routines, hasLength(1));
    final routine = routines.single;
    expect(routine.name, 'Push A');
    expect(routine.notes, 'Feels good');

    // Two line items persisted in order.
    final items = await routineRepo.listExercises(routine.id);
    expect(items, hasLength(2));
    expect(items[0].exerciseId, benchId);
    expect(items[0].orderIndex, 0);
    expect(items[0].targetSets, 3);
    expect(items[0].targetReps, 8);
    expect(items[1].exerciseId, squatId);
    expect(items[1].orderIndex, 1);
    expect(items[1].targetSets, 4);
    expect(items[1].targetReps, 5);

    await _drainDriftTimers(tester);
  });

  testWidgets('edit routine name → save → persisted', (tester) async {
    final id = await routineRepo.add(
      RoutinesCompanion.insert(
        name: 'Original',
        createdAt: DateTime(2026, 4, 20),
      ),
    );
    final existing = (await routineRepo.findById(id))!;

    await tester.pumpWidget(
      _host(db, RoutineFormScreen(existing: existing)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'Renamed',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = (await routineRepo.findById(id))!;
    expect(after.name, 'Renamed');
    // createdAt preserved (trust rule — no silent mutation).
    expect(after.createdAt, DateTime(2026, 4, 20));

    await _drainDriftTimers(tester);
  });

  testWidgets('reorder exercises with arrow buttons → persists', (
    tester,
  ) async {
    final id = await routineRepo.add(
      RoutinesCompanion.insert(
        name: 'Mixed',
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
    final existing = (await routineRepo.findById(id))!;

    _useTallViewport(tester);
    await tester.pumpWidget(
      _host(db, RoutineFormScreen(existing: existing)),
    );
    await tester.pumpAndSettle();

    // Move row 1 (Squat) up so the order becomes Squat, Bench Press.
    final moveUpButtons = find.widgetWithIcon(IconButton, Icons.arrow_upward);
    // Row 0's up-button is disabled (isFirst), so we target row 1's.
    await tester.tap(moveUpButtons.at(1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final after = await routineRepo.listExercises(id);
    expect(after, hasLength(2));
    expect(
      after[0].exerciseId,
      squatId,
      reason: 'Squat moved to orderIndex 0',
    );
    expect(
      after[1].exerciseId,
      benchId,
      reason: 'Bench dropped to orderIndex 1',
    );

    await _drainDriftTimers(tester);
  });

  testWidgets('delete routine (AppBar trash) → confirm → cascade removes rows',
      (tester) async {
    final id = await routineRepo.add(
      RoutinesCompanion.insert(
        name: 'Doomed',
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
      ),
    );
    final existing = (await routineRepo.findById(id))!;
    expect(await routineRepo.listExercises(id), hasLength(1));

    await tester.pumpWidget(
      _host(db, RoutineFormScreen(existing: existing)),
    );
    await tester.pumpAndSettle();

    // Tap the AppBar trash icon.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    // Confirm dialog → tap Delete.
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Routine gone + cascade removed the line item.
    expect(await routineRepo.findById(id), isNull);
    expect(await routineRepo.listExercises(id), isEmpty);

    await _drainDriftTimers(tester);
  });

  testWidgets('remove exercise row → confirm → disappears from draft',
      (tester) async {
    _useTallViewport(tester);
    await tester.pumpWidget(_host(db, const RoutineFormScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      'TwoRows',
    );
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await fillRow(
      tester,
      rowIndex: 0,
      exerciseName: 'Bench Press',
      sets: '3',
      reps: '8',
    );
    await tester.tap(find.text('Add exercise'));
    await tester.pumpAndSettle();
    await fillRow(
      tester,
      rowIndex: 1,
      exerciseName: 'Squat',
      sets: '4',
      reps: '5',
    );

    // Tap the close button on row 1 (index 1 → second close icon).
    final closeButtons = find.widgetWithIcon(IconButton, Icons.close);
    await tester.tap(closeButtons.at(1));
    await tester.pumpAndSettle();

    // Confirm removal.
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    // Save and verify only Bench Press persisted.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final routines = await routineRepo.listAll();
    expect(routines, hasLength(1));
    final items = await routineRepo.listExercises(routines.single.id);
    expect(items, hasLength(1));
    expect(items.single.exerciseId, benchId);

    await _drainDriftTimers(tester);
  });
}

Future<void> _drainDriftTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
