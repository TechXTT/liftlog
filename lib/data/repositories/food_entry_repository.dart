import 'package:drift/drift.dart';

import '../database.dart';
import '../day_range.dart';

class DailyTotals {
  const DailyTotals({required this.kcal, required this.proteinG});
  final int kcal;
  final double proteinG;
}

class DailySummary {
  const DailySummary({
    required this.day,
    required this.kcal,
    required this.proteinG,
  });
  final DateTime day;
  final int kcal;
  final double proteinG;
}

class FoodEntryRepository {
  FoodEntryRepository(this._db);

  final AppDatabase _db;

  Future<int> add(FoodEntriesCompanion entry) =>
      _db.into(_db.foodEntries).insert(entry);

  /// Writes every column of [entry], including nullable columns that are
  /// being cleared (e.g. `note: null`). We use `replace` rather than `write`
  /// because `write` serializes with `nullToAbsent: true` and would silently
  /// skip a cleared `note` — see `lib/features/food/food_entry_form_screen.dart`
  /// for the note-clear flow this enables. `replace` applies its own
  /// `whereSamePrimaryKey` so the caller must not add one.
  Future<void> update(FoodEntry entry) async {
    await _db.update(_db.foodEntries).replace(entry);
  }

  Future<int> delete(int id) =>
      (_db.delete(_db.foodEntries)..where((t) => t.id.equals(id))).go();

  Stream<List<FoodEntry>> watchAll() =>
      (_db.select(_db.foodEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .watch();

  Future<List<FoodEntry>> listAll() =>
      (_db.select(_db.foodEntries)
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .get();

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

  Stream<List<DailySummary>> watchDailySummaries() {
    return (_db.select(_db.foodEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch()
        .map((entries) {
      final buckets = <DateTime, List<FoodEntry>>{};
      for (final e in entries) {
        final day = DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day);
        buckets.putIfAbsent(day, () => []).add(e);
      }
      final summaries = buckets.entries.map((b) {
        var kcal = 0;
        var protein = 0.0;
        for (final e in b.value) {
          kcal += e.kcal;
          protein += e.proteinG;
        }
        return DailySummary(day: b.key, kcal: kcal, proteinG: protein);
      }).toList()
        ..sort((a, b) => b.day.compareTo(a.day));
      return summaries;
    });
  }
}
