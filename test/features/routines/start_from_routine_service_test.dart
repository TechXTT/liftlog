// Unit tests for `StartFromRoutineService` (issue #61).
//
// Covers the seeding contract: a new `WorkoutSession` is created, and
// planned `ExerciseSet` rows are seeded one-per-target-set per
// line-item, with running `orderIndex`, `status = planned`, `exerciseId`
// linked, and the canonical name copied onto `exerciseName`.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/database.dart';
import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/data/repositories/exercise_repository.dart';
import 'package:liftlog_app/data/repositories/exercise_set_repository.dart';
import 'package:liftlog_app/data/repositories/routine_repository.dart';
import 'package:liftlog_app/data/repositories/workout_session_repository.dart';
import 'package:liftlog_app/features/routines/start_from_routine_service.dart';

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

  Future<int> seedRoutineWithTwoExercises() async {
    final routineId = await routineRepo.add(
      RoutinesCompanion.insert(name: 'Push A', createdAt: DateTime(2026, 4, 1)),
    );
    await routineRepo.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: routineId,
        exerciseId: benchId,
        orderIndex: 0,
        targetSets: const Value(3),
        targetReps: const Value(8),
        targetWeight: const Value(80.0),
        targetWeightUnit: const Value(WeightUnit.kg),
      ),
    );
    await routineRepo.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: routineId,
        exerciseId: squatId,
        orderIndex: 1,
        targetSets: const Value(2),
        targetReps: const Value(5),
        targetWeight: const Value(100.0),
        targetWeightUnit: const Value(WeightUnit.kg),
      ),
    );
    return routineId;
  }

  test('seeds planned sets with running orderIndex and linked exerciseId',
      () async {
    final routineId = await seedRoutineWithTwoExercises();
    final service = StartFromRoutineService(
      routineRepo: routineRepo,
      exerciseRepo: exerciseRepo,
      exerciseSetRepo: setsRepo,
      sessionRepo: sessionRepo,
    );

    final now = DateTime(2026, 4, 23, 9);
    final sessionId = await service.start(routineId, now: now);

    final session = await sessionRepo.findById(sessionId);
    expect(session, isNotNull);
    expect(session!.startedAt, now);
    expect(session.endedAt, isNull, reason: 'session is fresh / open');

    final sets = await setsRepo.listForSession(sessionId);
    // 3 bench + 2 squat = 5 seeded sets.
    expect(sets, hasLength(5));

    // orderIndex runs 0..4 across all five, in line-item order.
    for (var i = 0; i < sets.length; i++) {
      expect(sets[i].orderIndex, i);
      expect(
        sets[i].status,
        WorkoutSetStatus.planned,
        reason: 'seeded sets start as planned',
      );
    }

    // First 3 → Bench Press (benchId, 8 reps @ 80 kg).
    for (var i = 0; i < 3; i++) {
      expect(sets[i].exerciseName, 'Bench Press');
      expect(sets[i].exerciseId, benchId);
      expect(sets[i].reps, 8);
      expect(sets[i].weight, 80.0);
      expect(sets[i].weightUnit, WeightUnit.kg);
    }
    // Next 2 → Squat (squatId, 5 reps @ 100 kg).
    for (var i = 3; i < 5; i++) {
      expect(sets[i].exerciseName, 'Squat');
      expect(sets[i].exerciseId, squatId);
      expect(sets[i].reps, 5);
      expect(sets[i].weight, 100.0);
    }
  });

  test(
      'null target_weight → weight 0.0 and default unit kg; null target_sets → one set',
      () async {
    final routineId = await routineRepo.add(
      RoutinesCompanion.insert(
        name: 'Bodyweight',
        createdAt: DateTime(2026, 4, 1),
      ),
    );
    // Rep-only row: no weight → seed as 0.0 kg (routine form normally
    // enforces sets/reps ≥ 1, but the service must still handle nulls
    // defensively since older rows may exist).
    await routineRepo.addExercise(
      RoutineExercisesCompanion.insert(
        routineId: routineId,
        exerciseId: benchId,
        orderIndex: 0,
        targetSets: const Value(2),
        targetReps: const Value(10),
        // weight + unit omitted = null on read
      ),
    );
    final service = StartFromRoutineService(
      routineRepo: routineRepo,
      exerciseRepo: exerciseRepo,
      exerciseSetRepo: setsRepo,
      sessionRepo: sessionRepo,
    );

    final sessionId = await service.start(
      routineId,
      now: DateTime(2026, 4, 23),
    );
    final sets = await setsRepo.listForSession(sessionId);
    expect(sets, hasLength(2));
    for (final s in sets) {
      expect(s.weight, 0.0);
      expect(s.weightUnit, WeightUnit.kg);
      expect(s.reps, 10);
      expect(s.status, WorkoutSetStatus.planned);
    }
  });

  test('empty routine → session created but no sets seeded', () async {
    final routineId = await routineRepo.add(
      RoutinesCompanion.insert(name: 'Empty', createdAt: DateTime(2026, 4, 1)),
    );
    final service = StartFromRoutineService(
      routineRepo: routineRepo,
      exerciseRepo: exerciseRepo,
      exerciseSetRepo: setsRepo,
      sessionRepo: sessionRepo,
    );

    final sessionId = await service.start(
      routineId,
      now: DateTime(2026, 4, 23),
    );
    expect(await sessionRepo.findById(sessionId), isNotNull);
    expect(await setsRepo.listForSession(sessionId), isEmpty);
  });

  test(
    'weight-only null unit falls back to kg default (defensive for old rows)',
    () async {
      // Construct a pathological old row: has weight set but NO unit
      // (shouldn't happen through the UI, but the model allows it since
      // targetWeightUnit is nullable). Service must fall back to kg —
      // the documented default.
      final routineId = await routineRepo.add(
        RoutinesCompanion.insert(
          name: 'Legacy',
          createdAt: DateTime(2026, 4, 1),
        ),
      );
      await routineRepo.addExercise(
        RoutineExercisesCompanion.insert(
          routineId: routineId,
          exerciseId: benchId,
          orderIndex: 0,
          targetSets: const Value(1),
          targetReps: const Value(5),
          targetWeight: const Value(60.0),
          // targetWeightUnit omitted = null
        ),
      );
      final service = StartFromRoutineService(
        routineRepo: routineRepo,
        exerciseRepo: exerciseRepo,
        exerciseSetRepo: setsRepo,
        sessionRepo: sessionRepo,
      );
      final sessionId = await service.start(
        routineId,
        now: DateTime(2026, 4, 23),
      );
      final sets = await setsRepo.listForSession(sessionId);
      expect(sets, hasLength(1));
      expect(sets.single.weight, 60.0);
      expect(sets.single.weightUnit, WeightUnit.kg);
    },
  );
}
