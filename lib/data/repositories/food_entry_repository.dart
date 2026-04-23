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

  Stream<List<FoodEntry>> watchAll() => (_db.select(
    _db.foodEntries,
  )..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).watch();

  Future<List<FoodEntry>> listAll() => (_db.select(
    _db.foodEntries,
  )..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).get();

  Stream<List<FoodEntry>> watchByDate(DateTime day) {
    final range = DayRange(day);
    return (_db.select(_db.foodEntries)
          ..where((t) => t.timestamp.isBetweenValues(range.start, range.end))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch();
  }

  Future<List<FoodEntry>> listByDate(DateTime day) {
    final range = DayRange(day);
    return (_db.select(_db.foodEntries)
          ..where((t) => t.timestamp.isBetweenValues(range.start, range.end))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
  }

  /// Returns entries whose `timestamp` falls in `[from, to)` (from inclusive,
  /// to exclusive), ordered by timestamp descending.
  Future<List<FoodEntry>> listRange(DateTime from, DateTime to) =>
      (_db.select(_db.foodEntries)
            ..where(
              (t) =>
                  t.timestamp.isBiggerOrEqualValue(from) &
                  t.timestamp.isSmallerThanValue(to),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .get();

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

  Future<DailyTotals> listDailyTotals(DateTime day) async {
    final entries = await listByDate(day);
    var kcal = 0;
    var protein = 0.0;
    for (final e in entries) {
      kcal += e.kcal;
      protein += e.proteinG;
    }
    return DailyTotals(kcal: kcal, proteinG: protein);
  }

  /// Returns the most recent distinct-by-name entries, newest first.
  ///
  /// Used by the Food tab's recent-foods quick-add strip. "Distinct" means
  /// we keep only the newest entry per `name`; older rows with the same
  /// name are collapsed away. `limit` caps the result length after
  /// collapsing, so callers get a stable number of chips regardless of how
  /// many duplicate rows exist upstream.
  ///
  /// The implementation is deliberately simple: pull every entry ordered
  /// by timestamp descending, then group-by-name in Dart. A window-function
  /// SQL variant would be faster at large row counts but isn't warranted
  /// today.
  Stream<List<FoodEntry>> watchRecentDistinctNames({int limit = 10}) {
    return (_db.select(_db.foodEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch()
        .map((entries) => _collapseByName(entries, limit));
  }

  Future<List<FoodEntry>> listRecentDistinctNames({int limit = 10}) async {
    final entries = await (_db.select(
      _db.foodEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).get();
    return _collapseByName(entries, limit);
  }

  /// Collapses [entries] (already newest-first) to the first hit per `name`,
  /// then caps at [limit]. Empty names are kept as a single bucket — matches
  /// how the food form treats them elsewhere.
  List<FoodEntry> _collapseByName(List<FoodEntry> entries, int limit) {
    final seen = <String>{};
    final out = <FoodEntry>[];
    for (final e in entries) {
      if (!seen.add(e.name)) continue;
      out.add(e);
      if (out.length >= limit) break;
    }
    return out;
  }

  Stream<List<DailySummary>> watchDailySummaries() {
    return (_db.select(_db.foodEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .watch()
        .map(_summarize);
  }

  Future<List<DailySummary>> listDailySummaries() async {
    final entries = await (_db.select(
      _db.foodEntries,
    )..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).get();
    return _summarize(entries);
  }

  List<DailySummary> _summarize(List<FoodEntry> entries) {
    final buckets = <DateTime, List<FoodEntry>>{};
    for (final e in entries) {
      final day = DateTime(
        e.timestamp.year,
        e.timestamp.month,
        e.timestamp.day,
      );
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
    }).toList()..sort((a, b) => b.day.compareTo(a.day));
    return summaries;
  }
}
