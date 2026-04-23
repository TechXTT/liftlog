import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import 'progress_data.dart';

/// Currently selected time window for the Progress tab. Widget state lives in
/// a [StateProvider] so changing it from `SegmentedButton` is a single
/// `ref.read(...).state = ...` assignment.
final progressWindowProvider =
    StateProvider<ProgressWindow>((ref) => ProgressWindow.sevenDays);

/// A wall-clock provider — overridable in tests to make window resolution
/// deterministic. Prod callers get the real time.
final progressNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// Weight series for the currently-selected window. Uses the one-shot
/// `listRange` repository method (not `watch*`) so widget tests don't hang
/// under Drift + fake_async.
final weightSeriesProvider = FutureProvider<WeightSeries>((ref) async {
  final window = ref.watch(progressWindowProvider);
  final now = ref.watch(progressNowProvider);
  final range = resolveWindow(window, now: now);
  final repo = ref.watch(bodyWeightLogRepositoryProvider);
  final logs = await repo.listRange(range.from, range.to);
  return buildWeightSeries(logs);
});

/// Daily kcal series for the currently-selected window.
final kcalSeriesProvider = FutureProvider<KcalSeries>((ref) async {
  final window = ref.watch(progressWindowProvider);
  final now = ref.watch(progressNowProvider);
  final range = resolveWindow(window, now: now);
  final repo = ref.watch(foodEntryRepositoryProvider);
  final entries = await repo.listRange(range.from, range.to);
  return buildKcalSeries(entries, from: range.from, to: range.to);
});

/// Weekly completed-set volume for the trailing 8 ISO weeks. Independent of
/// the 7d / 30d / all selector — the brief fixes this section at 8 weeks.
/// Uses the one-shot `listRangeWithSets` repository method (not `watch*`) so
/// widget tests don't hang under Drift + fake_async.
final weeklyVolumeProvider = FutureProvider<WeeklyVolumeSeries>((ref) async {
  final now = ref.watch(progressNowProvider);
  // Range = Monday-of(now) - 7 weeks through Monday-of(now) + 7 days.
  // Compute here so the repo call only fetches sessions that matter — the
  // aggregator does an identical bucketing pass, but it's cheaper to let
  // SQLite filter at the data layer first.
  final today = DateTime(now.year, now.month, now.day);
  final currentMonday =
      DateTime(today.year, today.month, today.day - (today.weekday - 1));
  final from = DateTime(
    currentMonday.year,
    currentMonday.month,
    currentMonday.day - 7 * 7,
  );
  final to = DateTime(
    currentMonday.year,
    currentMonday.month,
    currentMonday.day + 7,
  );
  final repo = ref.watch(workoutSessionRepositoryProvider);
  final grouped = await repo.listRangeWithSets(from, to);

  // Flatten to the shape buildWeeklyVolumeSeries expects. We hold onto both
  // the session objects (for startedAt) and their sets.
  final sessions = [for (final g in grouped) g.session];
  final sets = [for (final g in grouped) ...g.sets];
  return buildWeeklyVolumeSeries(sets, sessions, now);
});
