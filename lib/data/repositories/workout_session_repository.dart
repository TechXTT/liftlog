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
}
