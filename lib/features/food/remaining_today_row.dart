// "Remaining today" row on the Food tab (schema v5, issue #59 —
// E5 kickoff).
//
// Three states, driven by `DailyTargetRepository.activeOn(now)` and
// `todayTotalsProvider`:
//
//   1. No target ever set (or every target has a future
//      `effective_from`): renders a "Set a daily target in Settings"
//      affordance. Tapping it jumps the root shell to the Settings
//      tab so the user can set one — implemented via the
//      [onRequestSettings] callback so the widget stays
//      navigation-agnostic.
//
//   2. Under target: "Remaining today · N kcal · M g protein" where
//      N = target_kcal - eaten_kcal and M = target_protein - eaten_protein.
//
//   3. Over target: "Over by N kcal · M g protein" with the same
//      arithmetic reversed.
//
// Trust rule compliance (issue #59 explicit): raw arithmetic only.
// No "on track" / "crushing it" / "slow down" copy. Numbers routed
// through `lib/ui/formatters.dart` (`formatKcal` / `formatGrams`).
// If the repo read fails, surface the error rather than silently
// falling back — per CLAUDE.md "no silent fallbacks".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/repositories/food_entry_repository.dart';
import '../../providers/app_providers.dart';
import '../../ui/formatters.dart';
import 'food_providers.dart';

/// Reads `activeOn(DateTime.now())` as a one-shot. Re-read whenever
/// the user sets a target on Settings (the Settings section
/// invalidates its own provider; this one re-runs on rebuild because
/// we watch `appDatabaseProvider` indirectly through the repo).
final activeDailyTargetProvider = FutureProvider<DailyTarget?>((ref) {
  final repo = ref.watch(dailyTargetRepositoryProvider);
  return repo.activeOn(DateTime.now());
});

class RemainingTodayRow extends ConsumerWidget {
  const RemainingTodayRow({super.key, this.onRequestSettings});

  /// Invoked when the user taps "Set a daily target in Settings" in
  /// the no-target state. The root shell wires this to switch its
  /// selected tab to Settings. Null is fine for standalone tests and
  /// for contexts where there's no settings tab to switch to — in
  /// that case the tap is a no-op.
  final VoidCallback? onRequestSettings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final target = ref.watch(activeDailyTargetProvider);
    final totals = ref.watch(todayTotalsProvider);

    return target.when(
      loading: () => const SizedBox(height: 40),
      error: (err, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text('Target unavailable: $err'),
      ),
      data: (activeTarget) => totals.when(
        loading: () => const SizedBox(height: 40),
        error: (err, _) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text('Totals unavailable: $err'),
        ),
        data: (eaten) => _render(context, activeTarget, eaten),
      ),
    );
  }

  Widget _render(
    BuildContext context,
    DailyTarget? activeTarget,
    DailyTotals eaten,
  ) {
    if (activeTarget == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: InkWell(
          onTap: onRequestSettings,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Set a daily target in Settings'),
          ),
        ),
      );
    }

    final kcalDelta = activeTarget.kcal - eaten.kcal;
    final proteinDelta = activeTarget.proteinG - eaten.proteinG;
    // Over if either axis is over. The issue specifies only two
    // target-set states ("Under" / "Over"), so define "over" as
    // either axis having gone past the target — matches a single
    // person's expectation that blowing the kcal goal by 200 while
    // staying under protein still reads as "over". We render both
    // axes on each line anyway; this choice only flips the lead
    // word.
    final isOver = kcalDelta < 0 || proteinDelta < 0;

    final String text;
    if (isOver) {
      final kcalOver = -kcalDelta;
      final proteinOver = -proteinDelta;
      text =
          'Over by ${formatKcal(kcalOver)} kcal · '
          '${formatGrams(proteinOver)} g protein';
    } else {
      text =
          'Remaining today · ${formatKcal(kcalDelta)} kcal · '
          '${formatGrams(proteinDelta)} g protein';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(text),
    );
  }
}
