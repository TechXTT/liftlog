import 'package:drift/drift.dart';

import '../database.dart';

class WorkoutSessionRepository {
  WorkoutSessionRepository(this._db);

  final AppDatabase _db;

  Future<int> add(WorkoutSessionsCompanion session) =>
      _db.into(_db.workoutSessions).insert(session);

  Future<void> update(WorkoutSession session) =>
      (_db.update(_db.workoutSessions)..whereSamePrimaryKey(session))
          .write(session);

  Future<int> delete(int id) =>
      (_db.delete(_db.workoutSessions)..where((t) => t.id.equals(id))).go();

  Stream<List<WorkoutSession>> watchAll() =>
      (_db.select(_db.workoutSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch();

  Future<WorkoutSession?> findById(int id) =>
      (_db.select(_db.workoutSessions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();
}
