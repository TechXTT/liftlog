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
}
