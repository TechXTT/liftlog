// HealthKit workout providers (issue #51 / S5.4).
//
// Consumed by `WorkoutListScreen` to render an "External workouts"
// read-only section below the LiftLog session list. This file lives
// under `lib/features/workouts/` (alongside `workout_providers.dart`)
// because it's workouts-tab-scoped — not a general cross-feature HK
// signal like the ones in `lib/features/progress/hk_signal_providers.dart`.
//
// Arch note: imports only the `_source.dart` façade from
// `lib/sources/health_kit/`. Widget tests inject `HealthSourceFake` via
// the `healthSourceProvider` override.
//
// Range semantics: `from`-inclusive / `to`-exclusive, matching every
// `list*` method on the façade.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';
import '../progress/hk_signal_providers.dart';

/// Workout samples for a given window. Returns `[]` when workouts are
/// not authorized — partial HK denial is not a failure state (per the
/// façade contract).
final hkWorkoutsProvider =
    FutureProvider.family<List<HKWorkoutSample>, DateRange>((ref, range) {
      final hk = ref.watch(healthSourceProvider);
      return hk.listWorkouts(from: range.from, to: range.to);
    });

/// Convenience provider — 90-day rolling lookback, matching the cadence
/// used by `hkBodyWeightProvider`'s consumer in Progress. The Workouts
/// tab consumer reads this directly.
///
/// The range is computed fresh on each read so it tracks "now" across
/// provider invalidations. That means two reads a minute apart will use
/// different `DateRange` keys and both hit the underlying `listWorkouts`
/// — acceptable: HK reads are cheap relative to user action frequency.
final hkWorkoutsLast90dProvider = FutureProvider<List<HKWorkoutSample>>((ref) {
  final hk = ref.watch(healthSourceProvider);
  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 90));
  return hk.listWorkouts(from: from, to: now);
});

/// Whether HealthKit is authorized. Used by the Workouts tab to decide
/// whether to render the "External workouts" section at all — if not
/// authorized, the section is hidden (no nag toast, no empty state).
final hkIsAuthorizedProvider = FutureProvider<bool>((ref) {
  final hk = ref.watch(healthSourceProvider);
  return hk.isAuthorized();
});
