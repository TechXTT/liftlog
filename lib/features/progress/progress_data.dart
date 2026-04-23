import '../../data/database.dart';
import '../../data/enums.dart';

/// Time-window selector for the Progress tab. Enumerated exhaustively; never
/// fall through to a default case.
enum ProgressWindow { sevenDays, thirtyDays, all }

/// A single point on the weight sparkline. Kept portable (no UI types) so the
/// aggregator can stay a pure-Dart function that's trivial to unit test.
class WeightPoint {
  const WeightPoint({required this.timestamp, required this.value});
  final DateTime timestamp;
  final double value;
}

/// Output of the weight aggregator. `dominantUnit` is the unit the sparkline
/// should draw in, picked to match the most recent log in the window. When the
/// window contains logs in more than one unit, [mixedUnits] is true — the UI
/// layer uses that to render the "mixed units" banner. We deliberately never
/// convert between kg and lb (trust rule: no silent unit conversion).
class WeightSeries {
  const WeightSeries({
    required this.points,
    required this.dominantUnit,
    required this.mixedUnits,
  });

  final List<WeightPoint> points;
  final WeightUnit? dominantUnit;
  final bool mixedUnits;

  bool get isEmpty => points.isEmpty;
  bool get hasEnoughForSparkline => points.length >= 2;
}

/// One daily kcal bucket. `day` is the local-calendar midnight of that day.
class DailyKcal {
  const DailyKcal({required this.day, required this.kcal});
  final DateTime day;
  final int kcal;
}

/// Output of the kcal aggregator. `days` has one entry per day in the window
/// (inclusive from → exclusive to), in chronological order. A day with no
/// food entries contributes a 0, so the bar chart can show a visible gap.
class KcalSeries {
  const KcalSeries({required this.days});
  final List<DailyKcal> days;

  bool get isEmpty => days.every((d) => d.kcal == 0);
  int get loggedDayCount => days.where((d) => d.kcal > 0).length;
  int get maxKcal =>
      days.isEmpty ? 0 : days.map((d) => d.kcal).reduce((a, b) => a > b ? a : b);
}

/// Resolves a [ProgressWindow] to a `[from, to)` instant range. `to` is
/// exclusive and anchored to midnight-after-`now` so "today" always shows up
/// as the final day bucket.
///
/// For `all`, `from` is `DateTime.fromMillisecondsSinceEpoch(0)` — the
/// repository range queries treat everything newer as in-window. Good enough
/// for a single-user local tracker.
({DateTime from, DateTime to}) resolveWindow(
  ProgressWindow window, {
  required DateTime now,
}) {
  // Use calendar-day arithmetic (via DateTime constructor) rather than
  // `Duration` so DST transitions can't slip the window into the wrong day.
  final todayStart = DateTime(now.year, now.month, now.day);
  final to = DateTime(now.year, now.month, now.day + 1);
  switch (window) {
    case ProgressWindow.sevenDays:
      // 7 days total including today: today + 6 prior days.
      return (from: DateTime(now.year, now.month, now.day - 6), to: to);
    case ProgressWindow.thirtyDays:
      return (from: DateTime(now.year, now.month, now.day - 29), to: to);
    case ProgressWindow.all:
      return (from: DateTime.fromMillisecondsSinceEpoch(0), to: to);
  }
}

/// Returns the local-midnight day that [t] falls within. Pure function so day
/// bucketing stays testable without touching [DateTime.now].
DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Builds a [WeightSeries] from raw logs. Responsibilities:
///
/// 1. Pick a dominant unit. If logs are in more than one unit, the most recent
///    log wins — this is what the "Mixed units — showing kg only" banner
///    reflects. Never silently convert (trust rule).
/// 2. Filter to only that unit's points.
/// 3. Sort chronologically so the painter can walk left-to-right.
///
/// Keeping this in the aggregator (not the widget) means:
/// - The "mixed unit" behavior is unit-testable without pumping widgets.
/// - The sparkline painter receives a single-unit list and doesn't need to
///   know about [WeightUnit] at all.
WeightSeries buildWeightSeries(List<BodyWeightLog> logs) {
  if (logs.isEmpty) {
    return const WeightSeries(points: [], dominantUnit: null, mixedUnits: false);
  }

  // Find the most-recent-log unit — that's the one we show.
  final sortedDesc = [...logs]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final dominant = sortedDesc.first.unit;

  final hasKg = logs.any((l) => l.unit == WeightUnit.kg);
  final hasLb = logs.any((l) => l.unit == WeightUnit.lb);
  final mixed = hasKg && hasLb;

  final filtered = logs.where((l) => l.unit == dominant).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final points = filtered
      .map((l) => WeightPoint(timestamp: l.timestamp, value: l.value))
      .toList();

  return WeightSeries(
    points: points,
    dominantUnit: dominant,
    mixedUnits: mixed,
  );
}

/// Builds a [KcalSeries] from raw food entries. Entries are bucketed by
/// local-calendar day; each day in `[from, to)` gets one bucket, including
/// days with no entries (kcal = 0) so the bar chart renders a consistent
/// day-count.
///
/// Assumes `from` is already at local midnight. Walks forward by 24-hour
/// increments rather than arithmetic day math so DST transitions don't shift
/// buckets; for a single-user iPhone tracker that's fine.
KcalSeries buildKcalSeries(
  List<FoodEntry> entries, {
  required DateTime from,
  required DateTime to,
}) {
  // Short-circuit: `all`-window resolves `from` to epoch-0. We instead derive
  // the first bucket from the oldest entry's day — empty-day padding back to
  // 1970 would produce tens of thousands of zero bars.
  final DateTime effectiveFrom;
  if (from.millisecondsSinceEpoch <= 0) {
    if (entries.isEmpty) {
      effectiveFrom = DateTime(to.year, to.month, to.day).subtract(const Duration(days: 1));
    } else {
      final oldest =
          entries.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
      effectiveFrom = _dayOf(oldest);
    }
  } else {
    effectiveFrom = _dayOf(from);
  }

  // Bucket entries by day.
  final buckets = <DateTime, int>{};
  for (final e in entries) {
    final day = _dayOf(e.timestamp);
    buckets[day] = (buckets[day] ?? 0) + e.kcal;
  }

  // Emit one row per day in the range. Include 0-rows for visible gaps.
  // Advance by calendar day (not `Duration(days: 1)`) so DST transitions
  // don't skip or duplicate a day in the series.
  final days = <DailyKcal>[];
  var cursor = effectiveFrom;
  final end = DateTime(to.year, to.month, to.day);
  while (cursor.isBefore(end)) {
    days.add(DailyKcal(day: cursor, kcal: buckets[cursor] ?? 0));
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return KcalSeries(days: days);
}
