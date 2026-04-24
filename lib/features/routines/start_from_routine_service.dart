import 'package:drift/drift.dart' show Value;

import '../../data/database.dart';
import '../../data/enums.dart';
import '../../data/repositories/exercise_repository.dart';
import '../../data/repositories/exercise_set_repository.dart';
import '../../data/repositories/routine_repository.dart';
import '../../data/repositories/workout_session_repository.dart';

/// Encapsulates the "start a workout from a routine" flow (#61).
///
/// Creates a new `WorkoutSession` and seeds it with `ExerciseSet` rows
/// built from the routine's line items: one row per `targetSets`, in
/// `orderIndex` order, with a running global `orderIndex` across every
/// exercise in the routine. Seeded sets always start in
/// `WorkoutSetStatus.planned` — the user flips them to `completed` /
/// `skipped` during the workout.
///
/// Fallbacks are explicit and conservative:
/// - `targetSets == null` → we seed one set. Routines without a set count
///   are rare (the form validates `>= 1`) but older rows may exist.
/// - `targetReps == null` → we seed `reps = 0`. The user will edit.
/// - `targetWeight == null` → we seed `weight = 0.0` (bodyweight / rep-only).
/// - `targetWeightUnit == null` → we seed `WeightUnit.kg`. `kg` is the
///   app default; the user can switch per set.
///
/// None of these mutate the routine itself — they're read-only fallbacks
/// at seed time, not silent rewrites of targets (trust rule: no silent
/// mutation of user-entered data).
///
/// If the canonical exercise row is missing (e.g. the user deleted it
/// after creating the routine), we throw a `StateError` rather than
/// falling back to an empty string — "no silent fallbacks" (CLAUDE.md).
/// The caller surfaces it as a save error.
class StartFromRoutineService {
  StartFromRoutineService({
    required RoutineRepository routineRepo,
    required ExerciseRepository exerciseRepo,
    required ExerciseSetRepository exerciseSetRepo,
    required WorkoutSessionRepository sessionRepo,
  }) : _routineRepo = routineRepo,
       _exerciseRepo = exerciseRepo,
       _exerciseSetRepo = exerciseSetRepo,
       _sessionRepo = sessionRepo;

  final RoutineRepository _routineRepo;
  final ExerciseRepository _exerciseRepo;
  final ExerciseSetRepository _exerciseSetRepo;
  final WorkoutSessionRepository _sessionRepo;

  /// Creates a new session + seeds planned sets from [routineId]'s line
  /// items. Returns the new `sessionId`.
  ///
  /// [now] is injectable so widget tests can assert deterministic
  /// `startedAt` values.
  Future<int> start(int routineId, {required DateTime now}) async {
    final lineItems = await _routineRepo.listExercises(routineId);
    if (lineItems.isEmpty) {
      // Empty routine → still create the session (user might want a
      // blank slate named by the routine), but seed no sets. Matches the
      // manual "Start workout" flow.
      return _sessionRepo.add(
        WorkoutSessionsCompanion.insert(startedAt: now),
      );
    }

    final sessionId = await _sessionRepo.add(
      WorkoutSessionsCompanion.insert(startedAt: now),
    );

    // Running global index across every exercise's sets, so the session
    // list renders in the same order the routine prescribed.
    var runningIndex = 0;
    for (final re in lineItems) {
      final exercise = await _exerciseRepo.findById(re.exerciseId);
      if (exercise == null) {
        // No silent fallback: if the canonical row was deleted, surface
        // rather than seed with a placeholder name. The caller converts
        // this into a SnackBar.
        throw StateError(
          'StartFromRoutineService: exercises row ${re.exerciseId} '
          'missing while seeding routine $routineId',
        );
      }
      final sets = re.targetSets ?? 1;
      final reps = re.targetReps ?? 0;
      final weight = re.targetWeight ?? 0.0;
      final unit = re.targetWeightUnit ?? WeightUnit.kg;
      for (var i = 0; i < sets; i++) {
        await _exerciseSetRepo.add(
          ExerciseSetsCompanion.insert(
            sessionId: sessionId,
            exerciseName: exercise.canonicalName,
            reps: reps,
            weight: weight,
            weightUnit: unit,
            status: WorkoutSetStatus.planned,
            orderIndex: runningIndex,
            exerciseId: Value(re.exerciseId),
          ),
        );
        runningIndex++;
      }
    }
    return sessionId;
  }
}
