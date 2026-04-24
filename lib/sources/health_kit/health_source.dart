// Façade for the HealthKit integration source (issue #43).
//
// This file is the public boundary of `lib/sources/health_kit/`. Feature
// code is only ever allowed to import from this file — the arch guardrail
// in `test/arch/data_access_boundary_test.dart` enforces that via the
// `<name>_source.dart` naming convention.
//
// Trust-rule notes:
// * Pure Dart. No `package:health` import here, no Flutter imports beyond
//   what's strictly needed (today: nothing). Keeps the façade swap-in
//   testable without a live HealthKit bridge.
// * `WeightUnit` passes through unchanged — no silent unit conversion at
//   the boundary. The implementation maps `HealthDataUnit.KILOGRAM` /
//   `HealthDataUnit.POUND` to `WeightUnit.kg` / `WeightUnit.lb`; samples
//   in other mass units are dropped rather than auto-converted (see the
//   trust-rule in CLAUDE.md about unit mixing).
// * `Source` is deliberately NOT a field on `HKBodyWeightSample`. Feature
//   code must not construct `Source.` values directly (arch rule). The
//   provenance is implicit: anything coming out of this façade is
//   HealthKit-sourced. UI derives the badge from the sample's *type*
//   (a `HKBodyWeightSample` always gets the HealthKit badge), not from
//   a `Source` field.

import '../../data/enums.dart';

/// A single body-weight sample surfaced by the HealthKit bridge.
///
/// Immutable, value-equal, pure Dart. Features consume this directly.
class HKBodyWeightSample {
  const HKBodyWeightSample({
    required this.sourceId,
    required this.timestamp,
    required this.value,
    required this.unit,
  });

  /// Stable identifier from the underlying HKSample's source (the app or
  /// device that wrote the sample into HealthKit — e.g. the Health app
  /// itself, a smart scale vendor app, or LiftLog if it ever writes).
  /// Used for de-duplication across a refresh cycle.
  final String sourceId;

  /// Wall-clock time the sample was recorded. HealthKit samples carry
  /// a start/end pair; body-weight samples are instantaneous, so we use
  /// the start time.
  final DateTime timestamp;

  /// Numeric weight value in [unit]. No silent conversion — whatever the
  /// HK unit was, it comes out here as-is with the matching [unit].
  final double value;

  /// Unit the value is expressed in. Only `kg` / `lb` are emitted; see
  /// the mapping note at the top of this file.
  final WeightUnit unit;

  @override
  bool operator ==(Object other) =>
      other is HKBodyWeightSample &&
      other.sourceId == sourceId &&
      other.timestamp == timestamp &&
      other.value == value &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(sourceId, timestamp, value, unit);

  @override
  String toString() =>
      'HKBodyWeightSample(sourceId: $sourceId, timestamp: $timestamp, '
      'value: $value, unit: $unit)';
}

/// Pure-Dart façade for a HealthKit body-weight source.
///
/// The only implementation today (`HealthSourceImpl`) wraps
/// `package:health`. Tests inject `HealthSourceFake`.
///
/// Implementations must:
/// * Surface errors on the returned Future / Stream — no silent fallback.
/// * Return an empty list (not an error) when not authorized, so the UI
///   can fall back to user-entered rows without a nag toast.
/// * Never mutate Drift state from inside this façade — HK samples are
///   read-only passthrough this sprint.
abstract class HealthSource {
  /// Requests read access to body-weight samples. Returns `true` if the
  /// permission dialog completed without error (iOS never discloses the
  /// user's actual choice for READ access by design).
  Future<bool> requestPermissions();

  /// Returns `true` if the plugin believes read access is authorized.
  /// On iOS this is best-effort — HealthKit intentionally obscures read
  /// permission state to protect privacy.
  Future<bool> isAuthorized();

  /// One-shot fetch of body-weight samples in `[from, to)` (from-inclusive,
  /// to-exclusive). Ordered newest-first. Returns an empty list when not
  /// authorized; surfaces any other error to the caller.
  Future<List<HKBodyWeightSample>> listBodyWeight({
    required DateTime from,
    required DateTime to,
  });

  /// Streams body-weight samples in `[from, to)`. The first emission is
  /// the initial fetch; subsequent emissions reflect polling. Cancelling
  /// the subscription stops polling.
  ///
  /// TODO(s4.3-followup): replace the poll loop with an HKObserverQuery
  /// bridge once the plugin exposes it cleanly. For v1, poll cadence of
  /// ~60s is the simplest working shape — body-weight samples are low-
  /// velocity data and the UI refreshes on pull-to-refresh anyway.
  Stream<List<HKBodyWeightSample>> watchBodyWeight({
    required DateTime from,
    required DateTime to,
  });
}
