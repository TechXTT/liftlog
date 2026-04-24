import 'package:drift/drift.dart';

import '../database.dart';

class WorkoutSessionRepository {
  WorkoutSessionRepository(this._db);

  final AppDatabase _db;

  Future<int> add(WorkoutSessionsCompanion session) =>
      _db.into(_db.workoutSessions).insert(session);

  /// Writes every column of [session] including nullable columns that are
  /// being cleared (e.g. `endedAt: null`, `note: null`). We use `replace`
  /// rather than `update(...).write(...)` because `write` serializes with
  /// `nullToAbsent: true` and would silently preserve cleared nullables —
  /// a trust-rule violation. `replace` applies its own `whereSamePrimaryKey`
  /// so the caller must not add one.
  Future<void> update(WorkoutSession session) async {
    await _db.update(_db.workoutSessions).replace(session);
  }

  /// Persists a note on [sessionId]. Empty / whitespace-only strings are
  /// normalized to `null` so the column is either a real note or absent —
  /// keeps the UI's "+ Add note" vs. rendered-note branch a clean boolean.
  ///
  /// Read-then-`replace` (not `.write`) so clearing the note actually
  /// nulls the column (Drift's `write` silently drops nulls per the
  /// `write` vs. `replace` trust-rule skill).
  ///
  /// Errors surface to the caller — UI shows a SnackBar and does not
  /// mutate its own state (trust rule: no silent fallbacks).
  Future<void> updateNote(int sessionId, String? note) async {
    final row = await findById(sessionId);
    if (row == null) {
      throw StateError(
        'WorkoutSessionRepository.updateNote: session $sessionId not found',
      );
    }
    final normalized = (note == null || note.trim().isEmpty) ? null : note;
    await _db.update(_db.workoutSessions).replace(
          row.copyWith(note: Value(normalized)),
        );
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.workoutSessions)..where((t) => t.id.equals(id))).go();

  Stream<List<WorkoutSession>> watchAll() =>
      (_db.select(_db.workoutSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch();

  Future<List<WorkoutSession>> listAll() =>
      (_db.select(_db.workoutSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .get();

  Future<WorkoutSession?> findById(int id) =>
      (_db.select(_db.workoutSessions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Stream<WorkoutSession?> watchById(int id) =>
      (_db.select(_db.workoutSessions)..where((t) => t.id.equals(id)))
          .watchSingleOrNull();

  /// Returns every session whose `startedAt` falls in `[from, to)`, paired
  /// with the sets belonging to that session (ordered by `orderIndex` asc).
  ///
  /// Implementation is two queries rather than a SQL join: fetch sessions in
  /// range, then fetch sets whose `sessionId` is in that id set. For a
  /// single-user local tracker this is simpler than assembling a drift join
  /// and keeps the return shape trivially typed. Sessions with no sets yield
  /// a record with `sets: const []`.
  ///
  /// Callers (the Progress tab) further filter sets by
  /// [WorkoutSetStatus.completed]; we deliberately don't pre-filter here so
  /// future consumers can reuse the same method for planned / skipped
  /// buckets without another query path.
  Future<List<({WorkoutSession session, List<ExerciseSet> sets})>>
      listRangeWithSets(DateTime from, DateTime to) async {
    final sessions = await (_db.select(_db.workoutSessions)
          ..where((t) =>
              t.startedAt.isBiggerOrEqualValue(from) &
              t.startedAt.isSmallerThanValue(to))
          ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
        .get();
    if (sessions.isEmpty) return const [];

    final ids = sessions.map((s) => s.id).toList();
    final sets = await (_db.select(_db.exerciseSets)
          ..where((t) => t.sessionId.isIn(ids))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();

    // Bucket sets by sessionId so each session gets its own ordered list.
    final bySession = <int, List<ExerciseSet>>{};
    for (final s in sets) {
      bySession.putIfAbsent(s.sessionId, () => []).add(s);
    }
    return [
      for (final s in sessions)
        (session: s, sets: bySession[s.id] ?? const <ExerciseSet>[]),
    ];
  }
}
