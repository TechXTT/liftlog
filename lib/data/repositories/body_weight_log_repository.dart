import 'package:drift/drift.dart';

import '../database.dart';

class BodyWeightLogRepository {
  BodyWeightLogRepository(this._db);

  final AppDatabase _db;

  Future<int> add(BodyWeightLogsCompanion log) =>
      _db.into(_db.bodyWeightLogs).insert(log);

  /// Writes every column of [log] including any nullable columns that are
  /// being cleared. We use `replace` rather than `update(...).write(...)`
  /// because `write` serializes with `nullToAbsent: true` and would silently
  /// preserve cleared nullables — a trust-rule violation. `replace` applies
  /// its own `whereSamePrimaryKey` so the caller must not add one.
  Future<void> update(BodyWeightLog log) async {
    await _db.update(_db.bodyWeightLogs).replace(log);
  }

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

  /// Returns logs whose `timestamp` falls in `[from, to)` (from inclusive,
  /// to exclusive), ordered by timestamp descending. Used by range-based
  /// widget queries that would otherwise hang under Drift + fake_async.
  Future<List<BodyWeightLog>> listRange(DateTime from, DateTime to) =>
      (_db.select(_db.bodyWeightLogs)
            ..where((t) =>
                t.timestamp.isBiggerOrEqualValue(from) &
                t.timestamp.isSmallerThanValue(to))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .get();
}
