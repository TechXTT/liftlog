// HealthKit signal tiles for the Progress tab (issue #62 / S6.4).
//
// Three small tiles arranged in a row below the summary card:
//   HRV SDNN (ms)    |    Resting HR (bpm)    |    Sleep last night (h)
//
// Trust rules encoded here:
// * Raw numbers only — no "recovered / tired / great job" copy. These tiles
//   surface signal, never judgment (v2 trust rule: signal, not judgment).
// * Empty / stale data renders as em-dash (U+2014), never as a fabricated
//   `0`. Trust rule: no silent fallbacks.
// * When HealthKit is not authorized, the tile still renders an em-dash
//   plus a hint ("Enable HealthKit in Settings") — no nag toast, no
//   empty-state banner.
// * No loading spinner: while the read is in flight the tile shows "—",
//   same as the no-data state. The brief explicitly picks this over a
//   skeleton — simpler and a HK read is fast enough in practice that the
//   transient "—" is rarely visible.
//
// Arch note: this file imports only the `_source.dart` façade from
// `lib/sources/health_kit/` (via the `HKHRVSample` / `HKRestingHRSample` /
// `HKSleepStageSample` value types). Widget tests inject `HealthSourceFake`
// via `healthSourceProvider` overrides — no test touches real HealthKit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';
import 'hk_signal_providers.dart';
import 'progress_data.dart';
import 'progress_providers.dart';

/// A row of three HealthKit signal tiles (HRV, resting HR, sleep) rendered
/// below the Progress summary card.
///
/// Layout: a `Row` with `spaceEvenly` so the three tiles distribute across
/// the viewport without depending on a parent `Wrap`. Inside a `ListView`
/// (as on the Progress screen), each tile is width-constrained by the
/// overall row — fine at iPhone 15 portrait width.
class HKSignalTilesRow extends StatelessWidget {
  const HKSignalTilesRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: HKHRVTile()),
          Expanded(child: HKRestingHRTile()),
          Expanded(child: HKSleepTile()),
        ],
      ),
    );
  }
}

/// Shared visual shell for a single signal tile. Renders the value line
/// (headline-sized), a unit under it (`ms` / `bpm` / `h`), a small subtitle
/// labeling the metric, and an optional "not authorized" hint.
///
/// [value] is null iff there is no displayable reading (stale / no data /
/// not authorized) — the tile renders an em-dash in that case. [authorized]
/// controls whether the "Enable HealthKit in Settings" hint surfaces
/// beneath. When authorized + no data, no hint: the em-dash alone is the
/// honest signal.
class _SignalTile extends StatelessWidget {
  const _SignalTile({
    required this.value,
    required this.unit,
    required this.label,
    required this.authorized,
  });

  /// Pre-formatted value string (e.g. `"47"`, `"62"`, `"7.4"`). Null when
  /// there is no honest number to show — renders as em-dash.
  final String? value;

  /// Unit label displayed just under the value (`ms` / `bpm` / `h`).
  final String unit;

  /// Metric label rendered below the unit (`HRV SDNN` / `Resting HR` /
  /// `Sleep last night`).
  final String label;

  /// Whether HealthKit is authorized. Drives the "Enable HealthKit in
  /// Settings" hint shown on the unauthorized path.
  final bool authorized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // U+2014 EM DASH — matches the SummaryCard null-marker. Widget tests
    // assert on this literal; must stay exact.
    final displayValue = value ?? '\u2014';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          displayValue,
          style: theme.textTheme.headlineMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          unit,
          style: theme.textTheme.labelMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (!authorized) ...[
          const SizedBox(height: 4),
          Text(
            'Enable HealthKit in Settings',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Async authorization read: we render as "not authorized" while loading
/// or on error, too — erring toward hiding the absence-of-signal rather
/// than flashing "authorized" before the real state resolves. Same
/// convention as `workout_list_screen.dart`.
bool _collapseAuthorized(AsyncValue<bool> auth) =>
    auth.maybeWhen(data: (v) => v, orElse: () => false);

/// HRV (SDNN) tile. Reads `hkHRVProvider` with a 48h window ending at the
/// test-override-able `progressNowProvider`. Rounds to the nearest whole ms
/// for display — HRV users don't care about sub-ms precision and the tile
/// is narrow.
class HKHRVTile extends ConsumerWidget {
  const HKHRVTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(progressNowProvider);
    final range = DateRange(now.subtract(const Duration(hours: 48)), now);
    final auth = ref.watch(hkIsAuthorizedSignalProvider);
    final samples = ref.watch(hkHRVProvider(range));
    final authorized = _collapseAuthorized(auth);

    String? value;
    if (authorized) {
      final list = samples.maybeWhen(
        data: (v) => v,
        orElse: () => const <HKHRVSample>[],
      );
      final latest = latestHRVSdnn(list, now);
      if (latest != null) value = latest.round().toString();
    }

    return _SignalTile(
      value: value,
      unit: 'ms',
      label: 'HRV SDNN',
      authorized: authorized,
    );
  }
}

/// Resting HR tile. Reads `hkRestingHRProvider` with a 48h window.
class HKRestingHRTile extends ConsumerWidget {
  const HKRestingHRTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(progressNowProvider);
    final range = DateRange(now.subtract(const Duration(hours: 48)), now);
    final auth = ref.watch(hkIsAuthorizedSignalProvider);
    final samples = ref.watch(hkRestingHRProvider(range));
    final authorized = _collapseAuthorized(auth);

    String? value;
    if (authorized) {
      final list = samples.maybeWhen(
        data: (v) => v,
        orElse: () => const <HKRestingHRSample>[],
      );
      final latest = latestRestingHRBpm(list, now);
      if (latest != null) value = latest.round().toString();
    }

    return _SignalTile(
      value: value,
      unit: 'bpm',
      label: 'Resting HR',
      authorized: authorized,
    );
  }
}

/// Sleep-last-night tile. Reads `hkSleepProvider` with a window wide
/// enough to guarantee every last-night interval is fetched: we ask from
/// 20:00 yesterday through 12:00 today. The aggregator
/// ([lastNightSleepDuration]) re-clips each sample to the window itself.
class HKSleepTile extends ConsumerWidget {
  const HKSleepTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(progressNowProvider);
    final windowStart = DateTime(now.year, now.month, now.day - 1, 20);
    final windowEnd = DateTime(now.year, now.month, now.day, 12);
    final range = DateRange(windowStart, windowEnd);
    final auth = ref.watch(hkIsAuthorizedSignalProvider);
    final samples = ref.watch(hkSleepProvider(range));
    final authorized = _collapseAuthorized(auth);

    String? value;
    if (authorized) {
      final list = samples.maybeWhen(
        data: (v) => v,
        orElse: () => const <HKSleepStageSample>[],
      );
      final duration = lastNightSleepDuration(list, now);
      if (duration != null) {
        // Hours with one decimal — e.g. `7.4`. Minute precision is too
        // jittery for a single glance tile and HK's own sleep UI uses
        // hours-with-one-decimal too.
        final hours = duration.inMinutes / 60.0;
        value = hours.toStringAsFixed(1);
      }
    }

    return _SignalTile(
      value: value,
      unit: 'h',
      label: 'Sleep last night',
      authorized: authorized,
    );
  }
}

/// Authorization state for the HK signal tiles. Kept here (not in
/// `hk_signal_providers.dart`) so plumbing-only consumers don't pick up
/// a dependency on `healthSourceProvider.isAuthorized()` they don't use.
///
/// Same contract as `hkIsAuthorizedProvider` in
/// `lib/features/workouts/hk_workout_providers.dart` — we deliberately
/// duplicate the provider rather than cross-import a sibling feature's
/// file.
final hkIsAuthorizedSignalProvider = FutureProvider<bool>((ref) {
  final hk = ref.watch(healthSourceProvider);
  return hk.isAuthorized();
});
