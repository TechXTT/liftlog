import 'package:drift/drift.dart';

import '../database.dart';
import '../day_range.dart';

class DailyTotals {
  const DailyTotals({required this.kcal, required this.proteinG});
  final int kcal;
  final double proteinG;
}

class FoodEntryRepository {
  FoodEntryRepository(this._db);

  final AppDatabase _db;

  Future<int> add(FoodEntriesCompanion entry) =>
      _db.into(_db.foodEntries).insert(entry);

  Future<void> update(FoodEntry entry) =>
      (_db.update(_db.foodEntries)..whereSamePrimaryKey(entry)).write(entry);

  Future<int> delete(int id) =>
      (_db.delete(_db.foodEntries)..where((t) => t.id.equals(id))).go();

  Stream<List<FoodEntry>> watchAll() =>
      (_db.select(_db.foodEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .watch();

  Stream<List<FoodEntry>> watchByDate(DateTime day) {
    final range = DayRange(day);
    return (_db.select(_db.foodEntries)
          ..where((t) => t.timestamp.isBetweenValues(range.start, range.end))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch();
  }

  Stream<DailyTotals> watchDailyTotals(DateTime day) {
    return watchByDate(day).map((entries) {
      var kcal = 0;
      var protein = 0.0;
      for (final e in entries) {
        kcal += e.kcal;
        protein += e.proteinG;
      }
      return DailyTotals(kcal: kcal, proteinG: protein);
    });
  }
}
