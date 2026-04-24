import '../../data/database.dart';
import '../../data/enums.dart';
import '../../sources/health_kit/health_source.dart';

/// Time-window selector for the Progress tab. Enumerated exhaustively; never
/// fall through to a default case.
enum ProgressWindow { sevenDays, thirtyDays, all }

/// A single point on the weight sparkline. Kept portable (no UI types) so the
/// aggregator can stay a pure-Dart function that's trivial to unit test.
///
/// `isFromHealthKit` is a feature-local provenance flag — deliberately NOT a
/// `Source.` value. Feature code never constructs `Source` values raw (see
/// the arch guardrail in `test/arch/data_access_boundary_test.dart` and the
/// canonical-enum-non-conflation rule in CLAUDE.md). The flag is true iff
/// the point was sourced from a HealthKit sample rather than a user-entered
/// Drift row.
class WeightPoint {
  const WeightPoint({
    required this.timestamp,
    required this.value,
    this.isFromHealthKit = false,
  });
  final DateTime timestamp;
  final double value;
  final bool isFromHealthKit;
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

/// Number of calendar days in the `[from, to)` window. `from` is inclusive,
/// `to` is exclusive; both are truncated to local-midnight before the count
/// so a partial day on either end still counts as 1.
///
/// We walk by calendar-day increments (`DateTime(y, m, d + 1)`) rather than
/// dividing `Duration.inDays` — on DST transition days two consecutive civil
/// midnights are 23 or 25 wall-clock hours apart, and `.inDays` rounds the
/// short direction. Calendar-day arithmetic is the only way to stay exact.
///
/// Used as the denominator for the Progress summary's averages: dividing by
/// the number of calendar days in the window (not the number of logged days)
/// is the "seven-day average" a user expects, even with gaps.
int calendarDaysInWindow({required DateTime from, required DateTime to}) {
  final start = _dayOf(from);
  final end = _dayOf(to);
  if (!start.isBefore(end)) return 0;
  var count = 0;
  var cursor = start;
  while (cursor.isBefore(end)) {
    count += 1;
    cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
  }
  return count;
}

/// Returns the local-midnight Monday of the ISO week that [t] falls in.
/// [DateTime.weekday] is `1` for Monday through `7` for Sunday, so subtracting
/// `(weekday - 1)` civil days always lands on that week's Monday. Calendar
/// arithmetic (not `Duration`) so DST-day weeks don't drift by an hour.
DateTime _mondayOf(DateTime t) {
  final day = _dayOf(t);
  return DateTime(day.year, day.month, day.day - (day.weekday - 1));
}

/// Internal merged record for one day of weight data. Carries the unit
/// alongside the value + provenance so the dominant-unit filter downstream
/// can see both user-entered rows and HK samples through the same shape.
class _MergedWeight {
  const _MergedWeight({
    required this.timestamp,
    required this.value,
    required this.unit,
    required this.isFromHealthKit,
  });
  final DateTime timestamp;
  final double value;
  final WeightUnit unit;
  final bool isFromHealthKit;
}

/// Builds a [WeightSeries] from user-entered logs and HealthKit samples.
///
/// Responsibilities:
///
/// 1. Day-bucket dedup: for each local-calendar day, a user-entered log wins
///    over any HK sample (data-source precedence `user_entered` >
///    `saved_template` > `default` — HK is effectively the `default` lane
///    here). When both are present on the same day, only the user-entered
///    row contributes. When multiple HK samples land on the same day, the
///    most recent sample wins.
/// 2. Pick a dominant unit against the merged set. If the merged day-buckets
///    carry more than one unit, the most recent bucket's unit wins — this is
///    what the "Mixed units — showing kg only" banner reflects. Never
///    silently convert (trust rule).
/// 3. Filter to only that unit's points.
/// 4. Sort chronologically so the painter can walk left-to-right. Stamp each
///    [WeightPoint] with `isFromHealthKit` so the widget layer can surface a
///    HealthKit badge without re-interrogating the repositories.
///
/// [isFromHealthKit] is a feature-local provenance flag — deliberately NOT a
/// `Source.` value. Feature code never constructs `Source` values raw (see
/// the arch guardrail + the canonical-enum non-conflation rule in CLAUDE.md).
///
/// Keeping this in the aggregator (not the widget) means:
/// - The "mixed unit" and "HK/user dedup" behavior is unit-testable without
///   pumping widgets.
/// - The sparkline painter receives a single-unit list and doesn't need to
///   know about [WeightUnit] at all.
WeightSeries buildWeightSeries({
  required List<BodyWeightLog> userEntered,
  required List<HKBodyWeightSample> hkSamples,
  required DateTime from,
  required DateTime to,
}) {
  // --- Build the day-keyed merge map. ---
  // User-entered wins per the data-source precedence rule, so we layer
  // user-entered over HK rather than the other way around. HK samples are
  // kept newest-wins per-day before merging so a single day with multiple
  // HK readings collapses to one bucket deterministically.
  final merged = <DateTime, _MergedWeight>{};

  // Pass 1: HK samples, keeping the most recent sample per day. `isBefore`
  // is strict, so ties resolve to whichever we saw second — we prefer to be
  // explicit and compare timestamps directly.
  for (final s in hkSamples) {
    final day = _dayOf(s.timestamp);
    final existing = merged[day];
    if (existing == null || s.timestamp.isAfter(existing.timestamp)) {
      merged[day] = _MergedWeight(
        timestamp: s.timestamp,
        value: s.value,
        unit: s.unit,
        isFromHealthKit: true,
      );
    }
  }

  // Pass 2: user-entered logs. These overwrite any HK bucket on the same
  // day — data-source precedence. If two user-entered logs land on the
  // same day, keep the most recent one (mirrors the HK newest-wins rule
  // so "which value shows up on the sparkline" is consistent).
  for (final l in userEntered) {
    final day = _dayOf(l.timestamp);
    final existing = merged[day];
    if (existing == null ||
        existing.isFromHealthKit ||
        l.timestamp.isAfter(existing.timestamp)) {
      merged[day] = _MergedWeight(
        timestamp: l.timestamp,
        value: l.value,
        unit: l.unit,
        isFromHealthKit: false,
      );
    }
  }

  // The `from`/`to` params are part of the signature so callers don't have
  // to filter themselves, but the merge above is already bounded by the
  // data the provider hands us (both sides are fetched against the same
  // window). The explicit params also future-proof the function if a caller
  // ever passes unfiltered inputs. Apply them defensively — drop any bucket
  // whose day falls outside `[_dayOf(from), _dayOf(to))`.
  final fromDay = _dayOf(from);
  final toDay = _dayOf(to);
  final bounded = <_MergedWeight>[
    for (final e in merged.values)
      if (!_dayOf(e.timestamp).isBefore(fromDay) &&
          _dayOf(e.timestamp).isBefore(toDay))
        e,
  ];

  if (bounded.isEmpty) {
    return const WeightSeries(
      points: [],
      dominantUnit: null,
      mixedUnits: false,
    );
  }

  // Most-recent bucket's unit is the one we show.
  final sortedDesc = [...bounded]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  final dominant = sortedDesc.first.unit;

  final hasKg = bounded.any((e) => e.unit == WeightUnit.kg);
  final hasLb = bounded.any((e) => e.unit == WeightUnit.lb);
  final mixed = hasKg && hasLb;

  final filtered = bounded.where((e) => e.unit == dominant).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  final points = filtered
      .map((e) => WeightPoint(
            timestamp: e.timestamp,
            value: e.value,
            isFromHealthKit: e.isFromHealthKit,
          ))
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

/// The at-a-glance summary rendered above the window selector on the
/// Progress tab. Every field is nullable because the card shows an em-dash
/// for any metric that can't be computed honestly (no data, mixed units,
/// etc) — the alternative would be to fabricate a `0` that reads as "logged
/// zero", and that's a trust-rule violation.
///
/// Nullability rules (deliberately encoded in the aggregator so the widget
/// stays dumb):
/// - [avgKcalPerDay], [avgProteinGPerDay]: `null` when the window contains
///   zero calendar days (shouldn't happen in practice) or when there are no
///   food entries at all in the `all`-window case (no anchor for the day
///   count). Otherwise we divide total kcal / protein by the number of
///   *calendar* days in the window — not the count of logged days — so a
///   user with 2 logged days in a 7-day window sees `total / 7`, which is
///   the "average day" number they expect.
/// - [weightDelta]: `null` when the weight series has fewer than 2 points
///   in the dominant unit, OR when the window has mixed units. We never
///   display a delta that crosses a unit boundary (no silent conversion).
/// - [weightDeltaUnit]: null iff [weightDelta] is null.
/// - [sessionsCompleted]: `0` is a valid value — never null. A window with
///   no finished sessions renders "0 completed", not an em-dash, because
///   that count *is* meaningful: it means "you finished nothing in this
///   window", which is the honest read.
class ProgressSummary {
  const ProgressSummary({
    required this.avgKcalPerDay,
    required this.avgProteinGPerDay,
    required this.weightDelta,
    required this.weightDeltaUnit,
    required this.sessionsCompleted,
  });

  final int? avgKcalPerDay;
  final double? avgProteinGPerDay;
  final double? weightDelta;
  final WeightUnit? weightDeltaUnit;
  final int sessionsCompleted;
}

/// Builds a [ProgressSummary] for the `[from, to)` window.
///
/// Inputs are already-filtered lists from the repositories (so this stays
/// pure-Dart and trivially unit-testable). The caller is responsible for
/// passing lists filtered to the window — we don't re-filter here, to keep
/// a single source of truth for the window math.
///
/// `weightSeries` carries `mixedUnits` and `dominantUnit`; both decisions
/// about the delta flow through it. When `mixedUnits == true`, the delta
/// is `null` even if the filtered series has 2+ points, because mixing
/// units across a single metric is exactly what the trust rule forbids.
ProgressSummary buildProgressSummary({
  required List<FoodEntry> foods,
  required WeightSeries weightSeries,
  required List<({WorkoutSession session, List<ExerciseSet> sets})> sessionsWithSets,
  required DateTime from,
  required DateTime to,
}) {
  // --- Averages: divide by *calendar* days, not logged days. ---
  // If there are no food entries in the window we render em-dashes rather
  // than "0 kcal/day": a synthesized zero would read as "you logged zero",
  // which is a different claim than "nothing to average". Trust rule:
  // empty data must surface as em-dash, never as a fabricated number.
  //
  // For bounded windows the denominator is the number of calendar days in
  // the window. For the all-window (from == epoch-0), the denominator is
  // the number of calendar days between the oldest entry's day and `to` —
  // otherwise we'd divide by thousands of empty days back to 1970.
  int? avgKcal;
  double? avgProtein;
  if (foods.isNotEmpty) {
    final DateTime effectiveFrom;
    if (from.millisecondsSinceEpoch <= 0) {
      final oldest =
          foods.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b);
      effectiveFrom = _dayOf(oldest);
    } else {
      effectiveFrom = from;
    }
    final days = calendarDaysInWindow(from: effectiveFrom, to: to);
    if (days > 0) {
      var totalKcal = 0;
      var totalProtein = 0.0;
      for (final e in foods) {
        totalKcal += e.kcal;
        totalProtein += e.proteinG;
      }
      avgKcal = (totalKcal / days).round();
      avgProtein = totalProtein / days;
    }
  }

  // --- Weight delta: last - first, only in dominant unit. ---
  // Trust rule: never synthesize a delta that crosses kg↔lb. Both the
  // `mixedUnits == true` case and the `<2 points` case resolve to null,
  // and both are covered by dedicated unit tests.
  double? weightDelta;
  WeightUnit? weightDeltaUnit;
  if (!weightSeries.mixedUnits &&
      weightSeries.points.length >= 2 &&
      weightSeries.dominantUnit != null) {
    final first = weightSeries.points.first.value;
    final last = weightSeries.points.last.value;
    weightDelta = last - first;
    weightDeltaUnit = weightSeries.dominantUnit;
  }

  // --- Sessions completed in window. ---
  // "Completed" means `endedAt != null` — an in-progress session doesn't
  // count toward a window's completion metric. Window membership is by
  // `startedAt`, matching how every other range filter in this file works.
  var sessionsCompleted = 0;
  for (final g in sessionsWithSets) {
    final s = g.session;
    if (s.endedAt == null) continue;
    if (s.startedAt.isBefore(from)) continue;
    if (!s.startedAt.isBefore(to)) continue;
    sessionsCompleted += 1;
  }

  return ProgressSummary(
    avgKcalPerDay: avgKcal,
    avgProteinGPerDay: avgProtein,
    weightDelta: weightDelta,
    weightDeltaUnit: weightDeltaUnit,
    sessionsCompleted: sessionsCompleted,
  );
}

/// Latest HRV SDNN value (ms) from samples, restricted to the last 48h
/// before [now]. Returns `null` when no sample falls inside that window —
/// the tile then renders an em-dash.
///
/// We deliberately refuse to surface HRV older than 48h as "current": the
/// signal changes meaning rapidly and stale data presented as live would
/// be dishonest (trust rule — signal, not judgment; no silent fallbacks).
double? latestHRVSdnn(List<HKHRVSample> samples, DateTime now) {
  final cutoff = now.subtract(const Duration(hours: 48));
  final recent = [
    for (final s in samples)
      if (s.timestamp.isAfter(cutoff)) s,
  ];
  if (recent.isEmpty) return null;
  recent.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return recent.first.sdnnMs;
}

/// Latest resting-HR value (BPM) from samples, restricted to the last 48h.
/// Same shape + rationale as [latestHRVSdnn].
double? latestRestingHRBpm(List<HKRestingHRSample> samples, DateTime now) {
  final cutoff = now.subtract(const Duration(hours: 48));
  final recent = [
    for (final s in samples)
      if (s.timestamp.isAfter(cutoff)) s,
  ];
  if (recent.isEmpty) return null;
  recent.sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return recent.first.bpm;
}

/// Total "last night" sleep duration — the sum of asleep-* stage intervals
/// inside the civil window 20:00 yesterday → 12:00 today. Returns `null`
/// when the summed duration is less than 30 minutes — too thin to surface
/// as a meaningful "last night" number; better to render an em-dash.
///
/// The window is derived from local-civil midnights, so on DST transition
/// nights the wall-clock width differs from a normal 16h: ~15h on spring
/// forward, ~17h on fall back. That's intentional — we're answering
/// "what happened between 8pm yesterday and noon today in the user's
/// local time" — following civil time across a clock change is the
/// correct behavior.
///
/// Intervals that straddle the window edges are clipped so only the
/// in-window portion counts. [SleepStage.inBed] and [SleepStage.awake]
/// are deliberately excluded — `inBed` is a presence marker, `awake`
/// obviously isn't sleep. The switch is exhaustive per the canonical-enum
/// rule (no `default`); adding a new `SleepStage` value will surface as
/// a compile error forcing a decision here.
Duration? lastNightSleepDuration(
  List<HKSleepStageSample> samples,
  DateTime now,
) {
  final windowStart = DateTime(now.year, now.month, now.day - 1, 20);
  final windowEnd = DateTime(now.year, now.month, now.day, 12);
  var total = Duration.zero;
  for (final sample in samples) {
    // Skip intervals that don't touch the window at all.
    if (!sample.end.isAfter(windowStart)) continue;
    if (!sample.start.isBefore(windowEnd)) continue;
    // Clip to the window so boundary-straddling intervals only
    // contribute their in-window portion.
    final start =
        sample.start.isAfter(windowStart) ? sample.start : windowStart;
    final end = sample.end.isBefore(windowEnd) ? sample.end : windowEnd;
    switch (sample.stage) {
      case SleepStage.asleepCore:
      case SleepStage.asleepDeep:
      case SleepStage.asleepREM:
      case SleepStage.asleepUnspecified:
        total += end.difference(start);
      case SleepStage.awake:
      case SleepStage.inBed:
        // Deliberately excluded; see doc comment.
        break;
    }
  }
  if (total < const Duration(minutes: 30)) return null;
  return total;
}
