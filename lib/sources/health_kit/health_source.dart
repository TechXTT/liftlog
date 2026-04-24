// Façade for the HealthKit integration source (issues #43, #50).
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
// * HRV is surfaced in milliseconds (HealthKit's native unit for SDNN).
//   Resting HR is in BPM. Sleep samples carry a stage (`SleepStage`) plus
//   a start/end interval — HealthKit sleep is interval-shaped, not
//   instantaneous.
// * `Source` is deliberately NOT a field on the value classes. Feature
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

/// A single Heart-Rate-Variability sample, expressed as SDNN in
/// milliseconds — HealthKit's native unit for HRV
/// (`HKQuantityTypeIdentifierHeartRateVariabilitySDNN`).
///
/// Instantaneous: samples carry a start/end pair in HealthKit but the
/// two are equal for HRV, so we surface a single `timestamp`.
class HKHRVSample {
  const HKHRVSample({
    required this.sourceId,
    required this.timestamp,
    required this.sdnnMs,
  });

  /// Stable identifier from the underlying HKSample's source.
  final String sourceId;

  /// Wall-clock time the sample was recorded.
  final DateTime timestamp;

  /// SDNN in milliseconds. No silent conversion — HealthKit always reports
  /// this in ms; we pass it through. Callers compute averages / trends at
  /// the consumer layer, not here.
  final double sdnnMs;

  @override
  bool operator ==(Object other) =>
      other is HKHRVSample &&
      other.sourceId == sourceId &&
      other.timestamp == timestamp &&
      other.sdnnMs == sdnnMs;

  @override
  int get hashCode => Object.hash(sourceId, timestamp, sdnnMs);

  @override
  String toString() =>
      'HKHRVSample(sourceId: $sourceId, timestamp: $timestamp, '
      'sdnnMs: $sdnnMs)';
}

/// A single resting-heart-rate sample, in beats-per-minute.
///
/// Instantaneous: HealthKit resting HR samples are point-in-time (iOS
/// computes a per-day value from overnight HR readings).
class HKRestingHRSample {
  const HKRestingHRSample({
    required this.sourceId,
    required this.timestamp,
    required this.bpm,
  });

  /// Stable identifier from the underlying HKSample's source.
  final String sourceId;

  /// Wall-clock time the sample was recorded.
  final DateTime timestamp;

  /// Resting HR in BPM.
  final double bpm;

  @override
  bool operator ==(Object other) =>
      other is HKRestingHRSample &&
      other.sourceId == sourceId &&
      other.timestamp == timestamp &&
      other.bpm == bpm;

  @override
  int get hashCode => Object.hash(sourceId, timestamp, bpm);

  @override
  String toString() =>
      'HKRestingHRSample(sourceId: $sourceId, timestamp: $timestamp, '
      'bpm: $bpm)';
}

/// Sleep stages surfaced by the façade.
///
/// Maps HealthKit's `HKCategoryValueSleepAnalysis` values into a compact,
/// exhaustively-switch-able enum. Any renderer must enumerate all six
/// values — canonical-enum rule (see CLAUDE.md).
///
/// Mapping (see `health_source_impl.dart::_mapHealthSleepType`):
///   inBed              — user is in bed (sleeping or awake-in-bed)
///   asleepUnspecified  — generic asleep (pre-iOS 16 category value)
///   asleepCore         — iOS 16+ "core" / light sleep stage
///   asleepDeep         — iOS 16+ deep sleep stage
///   asleepREM          — iOS 16+ REM sleep stage
///   awake              — explicitly awake (out-of-bed or awake-in-bed)
enum SleepStage {
  inBed,
  asleepUnspecified,
  asleepCore,
  asleepDeep,
  asleepREM,
  awake,
}

/// A single sleep-stage sample. Sleep samples are interval-shaped in
/// HealthKit (a stretch of REM, a stretch of deep, etc.), so this value
/// class carries a start/end pair rather than a single timestamp.
class HKSleepStageSample {
  const HKSleepStageSample({
    required this.sourceId,
    required this.start,
    required this.end,
    required this.stage,
  });

  /// Stable identifier from the underlying HKSample's source.
  final String sourceId;

  /// Inclusive start of the sleep-stage interval.
  final DateTime start;

  /// Exclusive end of the sleep-stage interval.
  final DateTime end;

  /// Which stage this interval represents. See [SleepStage].
  final SleepStage stage;

  @override
  bool operator ==(Object other) =>
      other is HKSleepStageSample &&
      other.sourceId == sourceId &&
      other.start == start &&
      other.end == end &&
      other.stage == stage;

  @override
  int get hashCode => Object.hash(sourceId, start, end, stage);

  @override
  String toString() =>
      'HKSleepStageSample(sourceId: $sourceId, start: $start, end: $end, '
      'stage: $stage)';
}

/// Workout activity buckets surfaced by the façade.
///
/// The `health` package's `HealthWorkoutActivityType` ships ~80 values
/// covering every HKWorkoutActivityType Apple has ever defined plus the
/// Android Health Connect bucket set. Surfacing that full fan-out to the
/// UI would both (a) bloat the renderer switch and (b) leak a package
/// enum through the façade. Instead, we compress into a small, stable
/// set tied to the user's domain: strength training variants the lifter
/// is most likely to log, plus a handful of the common cardio buckets,
/// and an explicit `other` bucket for everything else.
///
/// `other` is the **explicit** catch-all, not a silent fallback. Every
/// renderer must enumerate all ten cases in a `switch` — canonical-enum
/// rule (see CLAUDE.md).
///
/// Mapping lives in `health_source_impl.dart::_mapHealthWorkoutType`
/// (exposed via `debugMapHealthWorkoutType` for the table-driven mapping
/// test, same seam as the sleep mapper).
enum HKWorkoutType {
  traditionalStrengthTraining,
  functionalStrengthTraining,
  coreTraining,
  highIntensityIntervalTraining,
  running,
  walking,
  cycling,
  yoga,
  other,
}

/// A single workout sample surfaced by the HealthKit bridge.
///
/// HealthKit workouts are interval-shaped (start + end), so this value
/// class carries both plus a pre-computed [duration] for consumer
/// convenience. [type] is the compressed [HKWorkoutType] bucket — see the
/// enum doc for the rationale.
///
/// Immutable, value-equal, pure Dart.
class HKWorkoutSample {
  const HKWorkoutSample({
    required this.sourceId,
    required this.startedAt,
    required this.endedAt,
    required this.type,
    required this.duration,
  });

  /// Stable identifier from the underlying HKSample's source — the app or
  /// device that recorded the workout (the Apple Watch's companion, a
  /// third-party workout tracker, or a manual entry in the Health app).
  /// Used for de-duplication across a refresh cycle.
  final String sourceId;

  /// Inclusive start of the workout interval.
  final DateTime startedAt;

  /// Exclusive end of the workout interval.
  final DateTime endedAt;

  /// Which bucket this workout maps to. See [HKWorkoutType].
  final HKWorkoutType type;

  /// Pre-computed duration. HealthKit reports this explicitly on the
  /// sample; we pass it through rather than recomputing from
  /// `endedAt - startedAt` so pause/resume gaps (which Apple tracks
  /// natively) aren't accidentally counted as active time.
  final Duration duration;

  @override
  bool operator ==(Object other) =>
      other is HKWorkoutSample &&
      other.sourceId == sourceId &&
      other.startedAt == startedAt &&
      other.endedAt == endedAt &&
      other.type == type &&
      other.duration == duration;

  @override
  int get hashCode => Object.hash(sourceId, startedAt, endedAt, type, duration);

  @override
  String toString() =>
      'HKWorkoutSample(sourceId: $sourceId, startedAt: $startedAt, '
      'endedAt: $endedAt, type: $type, duration: $duration)';
}

/// Pure-Dart façade for a HealthKit source.
///
/// The only implementation today (`HealthSourceImpl`) wraps
/// `package:health`. Tests inject `HealthSourceFake`.
///
/// Implementations must:
/// * Surface errors on the returned Future / Stream — no silent fallback.
/// * Return an empty list (not an error) when a specific data type is
///   not authorized, so the UI can fall back gracefully without a nag
///   toast. Per-type denial is per-method: if WEIGHT is authorized but
///   HRV isn't, `listBodyWeight` returns data and `listHRV` returns `[]`.
/// * Never mutate Drift state from inside this façade — HK samples are
///   read-only passthrough this sprint.
abstract class HealthSource {
  /// Requests read access to body-weight, HRV, resting-HR, and sleep
  /// samples in one permission dialog. Returns `true` if the dialog
  /// completed without error (iOS never discloses the user's actual
  /// choice for READ access by design).
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

  /// One-shot fetch of HRV (SDNN) samples in `[from, to)`. Ordered
  /// newest-first. Returns `[]` when HRV is not authorized — partial
  /// HK denial does not throw.
  Future<List<HKHRVSample>> listHRV({
    required DateTime from,
    required DateTime to,
  });

  /// Streams HRV samples in `[from, to)`. Same 60s poll semantics as
  /// [watchBodyWeight].
  Stream<List<HKHRVSample>> watchHRV({
    required DateTime from,
    required DateTime to,
  });

  /// One-shot fetch of resting-HR samples in `[from, to)`. Ordered
  /// newest-first. Returns `[]` when not authorized.
  Future<List<HKRestingHRSample>> listRestingHR({
    required DateTime from,
    required DateTime to,
  });

  /// Streams resting-HR samples in `[from, to)`. Same 60s poll semantics
  /// as [watchBodyWeight].
  Stream<List<HKRestingHRSample>> watchRestingHR({
    required DateTime from,
    required DateTime to,
  });

  /// One-shot fetch of sleep-stage samples in `[from, to)`. A night's
  /// sleep is returned as multiple intervals (one per stage transition).
  /// Ordered newest-first by `start`. Returns `[]` when not authorized.
  Future<List<HKSleepStageSample>> listSleep({
    required DateTime from,
    required DateTime to,
  });

  /// Streams sleep-stage samples in `[from, to)`. Same 60s poll semantics
  /// as [watchBodyWeight].
  Stream<List<HKSleepStageSample>> watchSleep({
    required DateTime from,
    required DateTime to,
  });

  /// One-shot fetch of workout samples in `[from, to)`. A workout whose
  /// `startedAt` falls inside the window is included. Ordered
  /// newest-first by `startedAt`. Returns `[]` when workouts are not
  /// authorized — partial HK denial does not throw.
  Future<List<HKWorkoutSample>> listWorkouts({
    required DateTime from,
    required DateTime to,
  });

  /// Streams workout samples in `[from, to)`. Same 60s poll semantics as
  /// [watchBodyWeight].
  Stream<List<HKWorkoutSample>> watchWorkouts({
    required DateTime from,
    required DateTime to,
  });
}
