import 'package:drift/drift.dart';

import '../database.dart';

class ExerciseSetRepository {
  ExerciseSetRepository(this._db);

  final AppDatabase _db;

  Future<int> add(ExerciseSetsCompanion set) =>
      _db.into(_db.exerciseSets).insert(set);

  /// Writes every column of [set] including any nullable columns that are
  /// being cleared. We use `replace` rather than `update(...).write(...)`
  /// because `write` serializes with `nullToAbsent: true` and would silently
  /// preserve cleared nullables — a trust-rule violation. Defensive: the
  /// current `ExerciseSets` table has no nullables, but this keeps the
  /// pattern consistent and future-proof. `replace` applies its own
  /// `whereSamePrimaryKey` so the caller must not add one.
  Future<void> update(ExerciseSet set) async {
    await _db.update(_db.exerciseSets).replace(set);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.exerciseSets)..where((t) => t.id.equals(id))).go();

  Stream<List<ExerciseSet>> watchForSession(int sessionId) =>
      (_db.select(_db.exerciseSets)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .watch();

  Future<List<ExerciseSet>> listForSession(int sessionId) =>
      (_db.select(_db.exerciseSets)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
          .get();

  /// Returns every exercise set across all sessions, ordered by `id`
  /// ascending for deterministic output. Added for the data-export flow
  /// (issue #37) which needs a flat dump of all rows; the other
  /// `watch*`/`list*` pairs on this repository are session-scoped.
  Future<List<ExerciseSet>> listAll() => (_db.select(
    _db.exerciseSets,
  )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Streams every set for [sessionId], each paired with its canonical
  /// [Exercise] row (via the `exercise_id` FK) when one exists.
  ///
  /// Sets are ordered by `orderIndex` ascending — the authoritative
  /// within-session ordering — so callers can group them by
  /// exercise and still preserve the user's recorded sequence within
  /// each group.
  ///
  /// Uses a LEFT OUTER JOIN so legacy sets with `exercise_id = NULL`
  /// still surface with `exercise: null`; the feature layer renders
  /// those as a fallback group using the set's raw `exerciseName`
  /// (S7.5 / issue #73). Silent data loss — dropping rows whose FK
  /// didn't backfill — is a trust-rule violation.
  Stream<List<({ExerciseSet set, Exercise? exercise})>>
  watchSessionSetsWithExercise(int sessionId) {
    final query =
        _db.select(_db.exerciseSets).join([
            leftOuterJoin(
              _db.exercises,
              _db.exercises.id.equalsExp(_db.exerciseSets.exerciseId),
            ),
          ])
          ..where(_db.exerciseSets.sessionId.equals(sessionId))
          ..orderBy([OrderingTerm.asc(_db.exerciseSets.orderIndex)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          (
            set: r.readTable(_db.exerciseSets),
            exercise: r.readTableOrNull(_db.exercises),
          ),
      ],
    );
  }

  /// One-shot sibling of [watchSessionSetsWithExercise]. Widget tests
  /// use this to avoid the Drift + fake_async hang on stream reads
  /// (see `vault/05 Architecture/Skills.md` — Drift + fake_async).
  Future<List<({ExerciseSet set, Exercise? exercise})>>
  listSessionSetsWithExercise(int sessionId) async {
    final query =
        _db.select(_db.exerciseSets).join([
            leftOuterJoin(
              _db.exercises,
              _db.exercises.id.equalsExp(_db.exerciseSets.exerciseId),
            ),
          ])
          ..where(_db.exerciseSets.sessionId.equals(sessionId))
          ..orderBy([OrderingTerm.asc(_db.exerciseSets.orderIndex)]);
    final rows = await query.get();
    return [
      for (final r in rows)
        (
          set: r.readTable(_db.exerciseSets),
          exercise: r.readTableOrNull(_db.exercises),
        ),
    ];
  }

  /// Returns up to [limit] distinct exercise names across all sessions,
  /// ordered by most recent use (newest first).
  ///
  /// Used by the Exercise Set form's recent-exercises chip strip (issue
  /// #39): tap a chip to refill the `Exercise` text field with one tap
  /// instead of retyping "Bench Press" every set.
  ///
  /// Implementation: pull every set, re-sort by `id` descending (`id` is an
  /// autoincrement surrogate for insert recency — cheaper than a new
  /// `orderBy` query and matches `listAll`'s existing asc ordering by just
  /// reversing in Dart), then dedup by `exerciseName` keeping first
  /// occurrence. A SQL window-function variant would be faster at large
  /// row counts but isn't warranted at single-user scale.
  ///
  /// Known behavior: names differing only in whitespace (e.g. "Bench
  /// Press" vs "Bench Press ") are kept as distinct chips. We deliberately
  /// do NOT trim/canonicalize — that would silently mutate what the user
  /// sees, a trust-rule violation. See issue #39 risk note.
  Future<List<String>> listRecentDistinctExerciseNames({int limit = 10}) async {
    final all = await listAll();
    all.sort((a, b) => b.id.compareTo(a.id));
    final seen = <String>{};
    final out = <String>[];
    for (final s in all) {
      if (seen.add(s.exerciseName)) {
        out.add(s.exerciseName);
        if (out.length == limit) break;
      }
    }
    return out;
  }
}
