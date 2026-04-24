// HealthKit signal providers (issue #50 / S5.3).
//
// Plumbing only — no UI consumer this sprint. These `FutureProvider.family`
// providers expose HRV, resting-HR, and sleep-stage reads through the
// `HealthSource` façade so a later sprint (when the UX design lands) can
// wire them into a Progress card / Home surface without reshuffling the
// data layer.
//
// Arch note: this file imports only the `_source.dart` façade from
// `lib/sources/health_kit/`. Widget tests inject `HealthSourceFake` via
// `healthSourceProvider` overrides — no test ever touches the underlying
// HK plugin.
//
// Range semantics: all three providers use a `DateRange` key with
// `from`-inclusive / `to`-exclusive interpretation — matches every
// `list*` method on the façade and every `listRange` on our repositories.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';
import '../../sources/health_kit/health_source.dart';

/// Key type for the HK signal `FutureProvider.family` providers below.
///
/// `==` + `hashCode` are load-bearing — Riverpod uses the key identity
/// to dedupe, so two `DateRange(a, b)` values constructed separately must
/// hash and compare equal or every widget rebuild issues a fresh HK read.
class DateRange {
  const DateRange(this.from, this.to);

  /// Inclusive start of the range.
  final DateTime from;

  /// Exclusive end of the range.
  final DateTime to;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DateRange($from, $to)';
}

/// HRV (SDNN, ms) samples for a given window. Returns `[]` when HRV is
/// not authorized — partial HK denial is not a failure state (per façade
/// contract).
final hkHRVProvider = FutureProvider.family<List<HKHRVSample>, DateRange>((
  ref,
  range,
) {
  final hk = ref.watch(healthSourceProvider);
  return hk.listHRV(from: range.from, to: range.to);
});

/// Resting-HR (BPM) samples for a given window. Returns `[]` when not
/// authorized.
final hkRestingHRProvider =
    FutureProvider.family<List<HKRestingHRSample>, DateRange>((ref, range) {
      final hk = ref.watch(healthSourceProvider);
      return hk.listRestingHR(from: range.from, to: range.to);
    });

/// Sleep-stage samples for a given window. Each sample is an interval
/// (start/end) tagged with a [SleepStage]. Returns `[]` when not
/// authorized.
final hkSleepProvider =
    FutureProvider.family<List<HKSleepStageSample>, DateRange>((ref, range) {
      final hk = ref.watch(healthSourceProvider);
      return hk.listSleep(from: range.from, to: range.to);
    });
