import 'package:drift/drift.dart';

import '../database.dart';

class ExerciseSetRepository {
  ExerciseSetRepository(this._db);

  final AppDatabase _db;

  Future<int> add(ExerciseSetsCompanion set) =>
      _db.into(_db.exerciseSets).insert(set);

  Future<void> update(ExerciseSet set) =>
      (_db.update(_db.exerciseSets)..whereSamePrimaryKey(set)).write(set);

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
