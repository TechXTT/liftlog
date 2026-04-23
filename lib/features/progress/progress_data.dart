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

/// Returns the local-midnight Monday of the ISO week that [t] falls in.
/// [DateTime.weekday] is `1` for Monday through `7` for Sunday, so subtracting
/// `(weekday - 1)` civil days always lands on that week's Monday. Calendar
/// arithmetic (not `Duration`) so DST-day weeks don't drift by an hour.
DateTime _mondayOf(DateTime t) {
  final day = _dayOf(t);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

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

/// Output of the weekly-volume aggregator. `weekStarts[i]` is the local
/// midnight of the Monday that starts week `i`; `completedSets[i]` is the
/// count of sets with `WorkoutSetStatus.completed` whose parent session's
/// `startedAt` falls inside `[weekStarts[i], weekStarts[i] + 7 days)`.
///
/// Both lists have identical length (the fixed 8-week window). `isEmpty`
/// is true iff every bucket is zero — the UI uses that for the dedicated
/// empty-state copy rather than rendering eight blank bars.
class WeeklyVolumeSeries {
  const WeeklyVolumeSeries({
    required this.weekStarts,
    required this.completedSets,
  });

  final List<DateTime> weekStarts;
  final List<int> completedSets;

  bool get isEmpty => completedSets.every((c) => c == 0);
  int get maxCompletedSets => completedSets.isEmpty
      ? 0
      : completedSets.reduce((a, b) => a > b ? a : b);
}

/// Builds a [WeeklyVolumeSeries] covering the 8 most recent ISO weeks ending
/// at the week of `now`. Sets are bucketed by their parent session's
/// `startedAt` (not by the set's own create time — sets don't carry one in
/// this schema). Only `WorkoutSetStatus.completed` sets count toward volume.
///
/// ISO week: Monday-to-Sunday. `weekStarts[0]` is the oldest Monday in the
/// window, `weekStarts[7]` is the Monday of `now`'s week.
WeeklyVolumeSeries buildWeeklyVolumeSeries(
  List<ExerciseSet> sets,
  List<WorkoutSession> sessions,
  DateTime now,
) {
  // Build the 8 Mondays, oldest first. Calendar arithmetic via DateTime()
  // — never Duration — so DST-week boundaries are always exactly 7 civil
  // days apart.
  final currentMonday = _mondayOf(now);
  final weekStarts = <DateTime>[
    for (var i = 7; i >= 0; i--)
      DateTime(currentMonday.year, currentMonday.month, currentMonday.day - 7 * i),
  ];
  final windowStart = weekStarts.first;
  final windowEnd = DateTime(
    currentMonday.year,
    currentMonday.month,
    currentMonday.day + 7,
  );

  // Index Monday → bucket position (0..7). Cheaper and DST-safe than
  // re-deriving bucket index from a civil-day difference — we hit a DST
  // week in testing where `Duration.inDays` rounded to 6 instead of 7.
  final mondayIndex = <DateTime, int>{
    for (var i = 0; i < weekStarts.length; i++) weekStarts[i]: i,
  };

  // sessionId → startedAt for O(1) lookup when iterating sets. Sessions
  // outside the 8-week window never contribute, so their sets are skipped.
  final sessionStart = <int, DateTime>{};
  for (final s in sessions) {
    if (s.startedAt.isBefore(windowStart)) continue;
    if (!s.startedAt.isBefore(windowEnd)) continue;
    sessionStart[s.id] = s.startedAt;
  }

  final counts = List<int>.filled(8, 0);
  for (final set in sets) {
    final sessionStartedAt = sessionStart[set.sessionId];
    if (sessionStartedAt == null) continue; // session not in 8-week window

    // Exhaustive switch over WorkoutSetStatus: planned & skipped are
    // deliberately excluded because "weekly volume" in this app means
    // work actually performed. A planned set is an intent that may never
    // happen; a skipped set is explicit non-completion — neither
    // represents volume a user should feel credit for.
    bool countThis;
    switch (set.status) {
      case WorkoutSetStatus.planned:
        countThis = false;
      case WorkoutSetStatus.completed:
        countThis = true;
      case WorkoutSetStatus.skipped:
        countThis = false;
    }
    if (!countThis) continue;

    // Bucket by Monday-of-week. Look the set's Monday up in the pre-built
    // index — safer than computing a civil-day difference here.
    final weekMonday = _mondayOf(sessionStartedAt);
    final index = mondayIndex[weekMonday];
    if (index == null) continue; // defensive: outside window
    counts[index] += 1;
  }

  return WeeklyVolumeSeries(weekStarts: weekStarts, completedSets: counts);
}
