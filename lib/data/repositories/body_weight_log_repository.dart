import 'package:drift/drift.dart';

import '../database.dart';

class BodyWeightLogRepository {
  BodyWeightLogRepository(this._db);

  final AppDatabase _db;

  Future<int> add(BodyWeightLogsCompanion log) =>
      _db.into(_db.bodyWeightLogs).insert(log);

  Future<void> update(BodyWeightLog log) =>
      (_db.update(_db.bodyWeightLogs)..whereSamePrimaryKey(log)).write(log);

  Future<int> delete(int id) =>
      (_db.delete(_db.bodyWeightLogs)..where((t) => t.id.equals(id))).go();

  Stream<List<BodyWeightLog>> watchAll() =>
      (_db.select(_db.bodyWeightLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .watch();

  Future<List<BodyWeightLog>> listAll() =>
      (_db.select(_db.bodyWeightLogs)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .get();
}
