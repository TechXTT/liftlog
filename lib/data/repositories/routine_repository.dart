import 'package:drift/drift.dart';

import '../database.dart';

/// Access to the `Routines` + `RoutineExercises` tables (schema v4 —
/// issue #52).
///
/// A routine is a reusable workout template: a named lineup of
/// exercises with optional per-exercise target sets/reps/weight.
/// Sprint 5 lands the data layer only — no UI reads or writes routines
/// yet, so this repository's surface is deliberately minimal: full
/// CRUD on both tables, a transactional reorder helper, and the usual
/// `watch*` / `list*` pair per the v2.0 trust rules (every watcher
/// pairs with a one-shot so widget tests avoid Drift + fake_async
/// hangs).
///
/// FK note: `RoutineExercises.routineId` is `ON DELETE CASCADE`, so
/// `delete(routineId)` removes the routine's lineup automatically.
/// The cascade is enforced at the SQLite layer via
/// `PRAGMA foreign_keys = ON` in `AppDatabase.beforeOpen`. Unrelated
/// `ExerciseSet` rows — from real workout sessions — are untouched.
class RoutineRepository {
  RoutineRepository(this._db);

  final AppDatabase _db;

  /// Inserts [routine] and returns the new row's `id`.
  Future<int> add(RoutinesCompanion routine) =>
      _db.into(_db.routines).insert(routine);

  /// Writes every column of [routine] including any nullable columns
  /// that are being cleared (e.g. `notes: null`). We use `replace`
  /// rather than `update(...).write(...)` because `write` serializes
  /// with `nullToAbsent: true` and would silently preserve cleared
  /// nullables — a trust-rule violation ("no silent mutation"). See
  /// the arch guardrail in `test/arch/data_access_boundary_test.dart`.
  /// `replace` applies its own `whereSamePrimaryKey` so the caller
  /// must not add one.
  Future<void> update(Routine routine) async {
    await _db.update(_db.routines).replace(routine);
  }

  /// Deletes the routine with [routineId]. `RoutineExercises` rows
  /// referencing this routine are removed by SQLite's
  /// `ON DELETE CASCADE`. Unrelated `ExerciseSet` rows are untouched.
  Future<int> delete(int routineId) =>
      (_db.delete(_db.routines)..where((t) => t.id.equals(routineId))).go();

  /// Every routine, newest-first by `createdAt` with `id DESC` as the
  /// tie-breaker (mirrors `ExerciseRepository.listAll` / `watchAll`).
  Future<List<Routine>> listAll() =>
      (_db.select(_db.routines)..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
          .get();

  /// Streaming counterpart to [listAll]. Widget tests should prefer
  /// [listAll] to avoid the Drift + fake_async hang.
  Stream<List<Routine>> watchAll() =>
      (_db.select(_db.routines)..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
          .watch();

  /// Returns the routine with [id], or `null` if no row matches.
  Future<Routine?> findById(int id) => (_db.select(
    _db.routines,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Every line item for [routineId], ordered by `orderIndex` ascending.
  Future<List<RoutineExercise>> listExercises(int routineId) =>
      (_db.select(_db.routineExercises)
            ..where((t) => t.routineId.equals(routineId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  /// Streaming counterpart to [listExercises].
  Stream<List<RoutineExercise>> watchExercises(int routineId) =>
      (_db.select(_db.routineExercises)
            ..where((t) => t.routineId.equals(routineId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch();

  /// Every line item across every routine, ordered by `id` ascending
  /// for deterministic output. Added for the data-export flow (issue
  /// #52) which needs a flat dump of all rows; [listExercises] is
  /// scoped to a single routine.
  Future<List<RoutineExercise>> listAllExercises() => (_db.select(
    _db.routineExercises,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Inserts a new line item and returns the new row's `id`.
  Future<int> addExercise(RoutineExercisesCompanion exercise) =>
      _db.into(_db.routineExercises).insert(exercise);

  /// Deletes a single routine-exercise line item by id.
  ///
  /// Added (#61) for the routine form's "save = wipe-and-rewrite" flow
  /// on edit: after the user reorders / adds / removes rows in the
  /// in-memory draft, the form deletes every existing line item and
  /// re-inserts the draft rows in order. Scoped by line-item id so the
  /// caller can target exactly the rows they want to remove.
  Future<int> deleteExercise(int lineItemId) =>
      (_db.delete(
        _db.routineExercises,
      )..where((t) => t.id.equals(lineItemId))).go();

  /// Rewrites `orderIndex` on every row in [exerciseIds] for the
  /// routine [routineId], in the order the caller supplied. The update
  /// runs inside a single Drift transaction so a partial reorder is
  /// never committed.
  ///
  /// Semantics: [exerciseIds] is the caller's desired ordering — the
  /// row whose id is `exerciseIds[0]` gets `orderIndex = 0`,
  /// `exerciseIds[1]` gets `orderIndex = 1`, etc. Callers are
  /// responsible for passing every id belonging to the routine
  /// exactly once; this method does not validate that. Ids not
  /// belonging to [routineId] are skipped (the per-row update matches
  /// on both `id` and `routineId` so stray ids don't mutate rows on
  /// another routine).
  Future<void> reorderExercises(int routineId, List<int> exerciseIds) async {
    // Read-then-replace loop: fetch each target row, rewrite its
    // `orderIndex`, and pass the full row back through `replace()`.
    // This keeps us on the trust-rule compliant `replace` path (no
    // silent null-preservation from `write(..., nullToAbsent: true)`)
    // while still being transactional — a partial reorder can never
    // land. Rows whose id doesn't belong to [routineId] are skipped
    // by the `getSingleOrNull` guard.
    await _db.transaction(() async {
      for (var i = 0; i < exerciseIds.length; i++) {
        final row =
            await (_db.select(_db.routineExercises)..where(
                  (t) =>
                      t.id.equals(exerciseIds[i]) &
                      t.routineId.equals(routineId),
                ))
                .getSingleOrNull();
        if (row == null) continue;
        await _db
            .update(_db.routineExercises)
            .replace(row.copyWith(orderIndex: i));
      }
    });
  }
}
