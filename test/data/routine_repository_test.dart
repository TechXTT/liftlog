// Unit tests for `RoutineRepository` (schema v4, issue #52).
//
// Mirrors the shape of `exercise_repository_test.dart`: an in-memory
// Drift DB, the repo under test, full CRUD on both parent (routines)
// and child (routine_exercises) rows, plus reorder + cascade-delete
// assertions. Routines don't exist without exercises in the catalog,
// so each test seeds a couple of `Exercises` rows up-front to satisfy
// the `routine_exercises.exerciseId` FK.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';

void main() {
  late AppDatabase db;
  late RoutineRepository repo;
  late ExerciseRepository exerciseRepo;
  late int benchId;
  late int squatId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RoutineRepository(db);
    exerciseRepo = ExerciseRepository(db);
    // Seed the exercises catalog so routine_exercises FKs resolve.
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

  group('routines CRUD', () {
    test('add + findById + listAll round-trip', () async {
      final id = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
      expect(id, isPositive);

      final found = await repo.findById(id);
      expect(found, isNotNull);
      expect(found!.name, 'Push A');
      expect(found.notes, isNull);
      expect(
        found.source,
        Source.userEntered,
        reason: 'source defaults to userEntered per schema DEFAULT',
      );

      final all = await repo.listAll();
      expect(all, hasLength(1));
      expect(all.single.id, id);
    });

    test('findById returns null for unknown id', () async {
      expect(await repo.findById(999), isNull);
    });

    test('update writes every column (including cleared notes)', () async {
      final id = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          notes: const Value('initial notes'),
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
      final routine = (await repo.findById(id))!;

      // Update name + clear notes. `replace` (not `write`) is the
      // trust-rule compliant path — `write` would silently preserve
      // the cleared `notes` via `nullToAbsent: true`.
      final edited = routine.copyWith(
        name: 'Push A (revised)',
        notes: const Value(null),
      );
      await repo.update(edited);

      final after = (await repo.findById(id))!;
      expect(after.name, 'Push A (revised)');
      expect(after.notes, isNull, reason: 'cleared notes must stay cleared');
    });

    test('delete removes the routine', () async {
      final id = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
      expect(await repo.findById(id), isNotNull);
      final deleted = await repo.delete(id);
      expect(deleted, 1);
      expect(await repo.findById(id), isNull);
    });

    test(
      'listAll orders newest-first by createdAt (id DESC as tiebreak)',
      () async {
        await repo.add(
          RoutinesCompanion.insert(
            name: 'Oldest',
            createdAt: DateTime(2026, 4, 1),
          ),
        );
        await repo.add(
          RoutinesCompanion.insert(
            name: 'Middle',
            createdAt: DateTime(2026, 4, 10),
          ),
        );
        await repo.add(
          RoutinesCompanion.insert(
            name: 'Newest',
            createdAt: DateTime(2026, 4, 20),
          ),
        );

        final all = await repo.listAll();
        expect(all.map((r) => r.name).toList(), ['Newest', 'Middle', 'Oldest']);
      },
    );

    test('watchAll emits rows ordered newest-first', () async {
      await repo.add(
        RoutinesCompanion.insert(
          name: 'Older',
          createdAt: DateTime(2026, 4, 10),
        ),
      );
      await repo.add(
        RoutinesCompanion.insert(
          name: 'Newer',
          createdAt: DateTime(2026, 4, 20),
        ),
      );

      final rows = await repo.watchAll().first;
      expect(rows.map((r) => r.name).toList(), ['Newer', 'Older']);
    });
  });

  group('routine_exercises CRUD', () {
    late int routineId;

    setUp(() async {
      routineId = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
    });

    test('addExercise + listExercises round-trip with every field', () async {
      final id = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
          targetSets: const Value(4),
          targetReps: const Value(8),
          targetWeight: const Value(80.0),
          targetWeightUnit: const Value(WeightUnit.kg),
        ),
      );
      expect(id, isPositive);

      final rows = await repo.listExercises(routineId);
      expect(rows, hasLength(1));
      final row = rows.single;
      expect(row.routineId, routineId);
      expect(row.exerciseId, benchId);
      expect(row.orderIndex, 0);
      expect(row.targetSets, 4);
      expect(row.targetReps, 8);
      expect(row.targetWeight, 80.0);
      expect(row.targetWeightUnit, WeightUnit.kg);
    });

    test('addExercise accepts all-null target fields', () async {
      final id = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
        ),
      );
      final row = (await repo.listExercises(routineId)).single;
      expect(row.id, id);
      expect(row.targetSets, isNull);
      expect(row.targetReps, isNull);
      expect(row.targetWeight, isNull);
      expect(row.targetWeightUnit, isNull);
    });

    test(
      'listExercises returns rows ordered by orderIndex ascending',
      () async {
        // Insert in a non-sorted order to prove the query sorts.
        await repo.addExercise(
          RoutineExercisesCompanion.insert(
            routineId: routineId,
            exerciseId: squatId,
            orderIndex: 2,
          ),
        );
        await repo.addExercise(
          RoutineExercisesCompanion.insert(
            routineId: routineId,
            exerciseId: benchId,
            orderIndex: 0,
          ),
        );
        await repo.addExercise(
          RoutineExercisesCompanion.insert(
            routineId: routineId,
            exerciseId: squatId,
            orderIndex: 1,
          ),
        );

        final rows = await repo.listExercises(routineId);
        expect(rows.map((r) => r.orderIndex).toList(), [0, 1, 2]);
      },
    );

    test('watchExercises emits rows ordered by orderIndex ascending', () async {
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 1,
        ),
      );
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: squatId,
          orderIndex: 0,
        ),
      );

      final rows = await repo.watchExercises(routineId).first;
      expect(rows.map((r) => r.orderIndex).toList(), [0, 1]);
    });

    test('listExercises for a different routine does not leak rows', () async {
      final otherId = await repo.add(
        RoutinesCompanion.insert(
          name: 'Pull A',
          createdAt: DateTime(2026, 4, 20, 13),
        ),
      );
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
        ),
      );
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: otherId,
          exerciseId: squatId,
          orderIndex: 0,
        ),
      );

      final a = await repo.listExercises(routineId);
      final b = await repo.listExercises(otherId);
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.single.exerciseId, benchId);
      expect(b.single.exerciseId, squatId);
    });
  });

  group('reorderExercises', () {
    late int routineId;
    late List<int> originalIds;

    setUp(() async {
      routineId = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
      final aId = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
        ),
      );
      final bId = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: squatId,
          orderIndex: 1,
        ),
      );
      final cId = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 2,
        ),
      );
      originalIds = [aId, bId, cId];
    });

    test('rewrites order_index in caller-supplied order', () async {
      // Reverse the order: c, b, a.
      await repo.reorderExercises(routineId, [
        originalIds[2],
        originalIds[1],
        originalIds[0],
      ]);

      final rows = await repo.listExercises(routineId);
      expect(rows.map((r) => r.id).toList(), [
        originalIds[2],
        originalIds[1],
        originalIds[0],
      ]);
      expect(rows.map((r) => r.orderIndex).toList(), [0, 1, 2]);
    });

    test('ignores ids that belong to a different routine', () async {
      // A second routine with one exercise — its id must not be
      // rewritten by a reorder scoped to the first routine.
      final otherId = await repo.add(
        RoutinesCompanion.insert(
          name: 'Pull A',
          createdAt: DateTime(2026, 4, 20, 13),
        ),
      );
      final strayId = await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: otherId,
          exerciseId: squatId,
          orderIndex: 99,
        ),
      );

      // Caller mistakenly includes `strayId` — the per-row where clause
      // on `routineId` must keep the stray row untouched.
      await repo.reorderExercises(routineId, [strayId, ...originalIds]);

      final strayRow = (await repo.listExercises(otherId)).single;
      expect(strayRow.id, strayId);
      expect(
        strayRow.orderIndex,
        99,
        reason: 'stray routine_exercise row must not be reindexed',
      );
    });

    test('leaves non-targeted columns alone', () async {
      // Attach targets to one row; after reorder those targets should
      // still be intact (partial column update via `.write()`).
      final rowsBefore = await repo.listExercises(routineId);
      final mid = rowsBefore[1];
      await db
          .update(db.routineExercises)
          .replace(
            mid.copyWith(
              targetSets: const Value(5),
              targetReps: const Value(5),
              targetWeight: const Value(100.0),
              targetWeightUnit: const Value(WeightUnit.kg),
            ),
          );

      await repo.reorderExercises(routineId, [
        originalIds[2],
        originalIds[1],
        originalIds[0],
      ]);

      final updated = (await repo.listExercises(
        routineId,
      )).firstWhere((r) => r.id == mid.id);
      expect(updated.targetSets, 5);
      expect(updated.targetReps, 5);
      expect(updated.targetWeight, 100.0);
      expect(updated.targetWeightUnit, WeightUnit.kg);
    });
  });

  group('cascade delete', () {
    test('deleting a routine removes its exercises', () async {
      final routineId = await repo.add(
        RoutinesCompanion.insert(
          name: 'Push A',
          createdAt: DateTime(2026, 4, 20, 12),
        ),
      );
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
        ),
      );
      await repo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: squatId,
          orderIndex: 1,
        ),
      );

      expect(await repo.listExercises(routineId), hasLength(2));

      await repo.delete(routineId);

      expect(
        await repo.listExercises(routineId),
        isEmpty,
        reason: 'ON DELETE CASCADE must remove the lineup',
      );
      expect(
        await repo.listAllExercises(),
        isEmpty,
        reason: 'no orphan routine_exercises rows should survive the cascade',
      );
    });

    test(
      'deleting a routine does not touch unrelated ExerciseSet rows',
      () async {
        // Create a real workout session + its sets. These live on
        // `workout_sessions` / `exercise_sets`, not on routines.
        final sessions = WorkoutSessionRepository(db);
        final sets = ExerciseSetRepository(db);
        final sessionId = await sessions.add(
          WorkoutSessionsCompanion.insert(startedAt: DateTime(2026, 4, 22, 9)),
        );
        await sets.add(
          ExerciseSetsCompanion.insert(
            sessionId: sessionId,
            exerciseName: 'Bench Press',
            reps: 8,
            weight: 80.0,
            weightUnit: WeightUnit.kg,
            status: WorkoutSetStatus.completed,
            orderIndex: 0,
          ),
        );

        // Create a routine + lineup, then delete the routine.
        final routineId = await repo.add(
          RoutinesCompanion.insert(
            name: 'Push A',
            createdAt: DateTime(2026, 4, 20, 12),
          ),
        );
        await repo.addExercise(
          RoutineExercisesCompanion.insert(
            routineId: routineId,
            exerciseId: benchId,
            orderIndex: 0,
          ),
        );

        await repo.delete(routineId);

        // The routine's lineup is gone …
        expect(await repo.listExercises(routineId), isEmpty);
        // … but the real workout's sets are untouched.
        final remaining = await sets.listForSession(sessionId);
        expect(remaining, hasLength(1));
        expect(remaining.single.exerciseName, 'Bench Press');
      },
    );
  });
}
