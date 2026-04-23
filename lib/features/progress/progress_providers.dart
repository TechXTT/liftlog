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
