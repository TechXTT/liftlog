// Concrete `HealthSource` backed by `package:health`. This file is the
// only place in the app that imports `package:health`; feature code
// must never import it (arch rule — enforced).
//
// Trust-rule notes:
// * No silent unit conversion. Samples arrive from the plugin tagged
//   with a `HealthDataUnit`; we map only `KILOGRAM`→`kg` and `POUND`→`lb`.
//   Samples in other mass units (gram, ounce, stone) are DROPPED, not
//   coerced. If that matters later, the user will add them manually or
//   we'll extend the mapping explicitly — never silently.
// * `list*()` returns `[]` when the corresponding data kind is not
//   authorized. Partial HK denial (e.g. WEIGHT granted but HRV denied)
//   is per-method: each list* call checks its own permission slice.
//   Native errors still surface via `Future.error`.
// * `watch*()` uses a 60-second poll — see the façade comment for
//   the rationale and the TODO.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../data/enums.dart';
import 'health_source.dart';

/// Default polling cadence for the `watch*` streams. Exposed as a
/// top-level constant for test-targeted overrides (none today) and for
/// documentation. Matches the cadence agreed in S4.3 for body-weight.
const Duration _kPollInterval = Duration(seconds: 60);

class HealthSourceImpl implements HealthSource {
  HealthSourceImpl({Health? plugin}) : _plugin = plugin ?? Health();

  final Health _plugin;
  bool _configured = false;

  // Per-kind type lists. Keeping them separate lets `isAuthorized*` and
  // `list*` check only the specific data kind — per-method partial denial
  // (e.g. WEIGHT granted, HRV denied) per the façade contract.
  static const List<HealthDataType> _bodyWeightTypes = [HealthDataType.WEIGHT];
  static const List<HealthDataType> _hrvTypes = [
    HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];
  static const List<HealthDataType> _restingHrTypes = [
    HealthDataType.RESTING_HEART_RATE,
  ];
  // iOS sleep types supported by `package:health` v13 on iOS. We enumerate
  // every iOS `SLEEP_*` the plugin ships; anything it doesn't expose isn't
  // our problem, and the `_mapHealthSleepType` switch is exhaustive over
  // every `HealthDataType.SLEEP_*` the enum defines.
  static const List<HealthDataType> _sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_IN_BED,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
  ];

  /// Union of every type we request at permission-dialog time. Requesting
  /// them together shows a single HealthKit permission sheet to the user
  /// rather than four separate dialogs.
  static const List<HealthDataType> _allTypes = [
    ..._bodyWeightTypes,
    ..._hrvTypes,
    ..._restingHrTypes,
    ..._sleepTypes,
  ];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _plugin.configure();
    _configured = true;
  }

  @override
  Future<bool> requestPermissions() async {
    await _ensureConfigured();
    return _plugin.requestAuthorization(
      _allTypes,
      permissions: List<HealthDataAccess>.filled(
        _allTypes.length,
        HealthDataAccess.READ,
      ),
    );
  }

  @override
  Future<bool> isAuthorized() async {
    await _ensureConfigured();
    // Aggregate permission check — used by the Settings → HealthKit UI
    // to decide the "Sync" button affordance. Per-method list* calls
    // still short-circuit on their own per-kind permission to honor
    // partial denial.
    final result = await _plugin.hasPermissions(
      _allTypes,
      permissions: List<HealthDataAccess>.filled(
        _allTypes.length,
        HealthDataAccess.READ,
      ),
    );
    // On iOS `hasPermissions` returns `null` for READ because HealthKit
    // intentionally obscures read-permission state. Treat null as "we
    // don't know — assume unauthorized until the user grants." Callers
    // use this only for UI affordances (the Sync button); the actual
    // list call still handles the empty-when-unauthorized case.
    return result == true;
  }

  /// Per-kind authorization check. Returns `true` when the plugin reports
  /// authorization for [types]; treats the iOS `null` ambiguity as
  /// unauthorized (same convention as [isAuthorized]).
  Future<bool> _isAuthorizedFor(List<HealthDataType> types) async {
    final result = await _plugin.hasPermissions(
      types,
      permissions: List<HealthDataAccess>.filled(
        types.length,
        HealthDataAccess.READ,
      ),
    );
    return result == true;
  }

  @override
  Future<List<HKBodyWeightSample>> listBodyWeight({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ensureConfigured();
    if (!await _isAuthorizedFor(_bodyWeightTypes)) return const [];

    final points = await _plugin.getHealthDataFromTypes(
      types: _bodyWeightTypes,
      startTime: from,
      endTime: to,
    );

    final samples = <HKBodyWeightSample>[];
    for (final point in points) {
      final sample = _toBodyWeightSample(point);
      if (sample != null) samples.add(sample);
    }
    samples.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return samples;
  }

  @override
  Stream<List<HKBodyWeightSample>> watchBodyWeight({
    required DateTime from,
    required DateTime to,
  }) =>
      _pollStream<HKBodyWeightSample>(() => listBodyWeight(from: from, to: to));

  @override
  Future<List<HKHRVSample>> listHRV({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ensureConfigured();
    if (!await _isAuthorizedFor(_hrvTypes)) return const [];

    final points = await _plugin.getHealthDataFromTypes(
      types: _hrvTypes,
      startTime: from,
      endTime: to,
    );

    final samples = <HKHRVSample>[];
    for (final point in points) {
      final sample = _toHRVSample(point);
      if (sample != null) samples.add(sample);
    }
    samples.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return samples;
  }

  @override
  Stream<List<HKHRVSample>> watchHRV({
    required DateTime from,
    required DateTime to,
  }) => _pollStream<HKHRVSample>(() => listHRV(from: from, to: to));

  @override
  Future<List<HKRestingHRSample>> listRestingHR({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ensureConfigured();
    if (!await _isAuthorizedFor(_restingHrTypes)) return const [];

    final points = await _plugin.getHealthDataFromTypes(
      types: _restingHrTypes,
      startTime: from,
      endTime: to,
    );

    final samples = <HKRestingHRSample>[];
    for (final point in points) {
      final sample = _toRestingHRSample(point);
      if (sample != null) samples.add(sample);
    }
    samples.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return samples;
  }

  @override
  Stream<List<HKRestingHRSample>> watchRestingHR({
    required DateTime from,
    required DateTime to,
  }) => _pollStream<HKRestingHRSample>(() => listRestingHR(from: from, to: to));

  @override
  Future<List<HKSleepStageSample>> listSleep({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ensureConfigured();
    if (!await _isAuthorizedFor(_sleepTypes)) return const [];

    final points = await _plugin.getHealthDataFromTypes(
      types: _sleepTypes,
      startTime: from,
      endTime: to,
    );

    final samples = <HKSleepStageSample>[];
    for (final point in points) {
      final sample = _toSleepStageSample(point);
      if (sample != null) samples.add(sample);
    }
    // Newest-first by start time — matches the other list* methods.
    samples.sort((a, b) => b.start.compareTo(a.start));
    return samples;
  }

  @override
  Stream<List<HKSleepStageSample>> watchSleep({
    required DateTime from,
    required DateTime to,
  }) => _pollStream<HKSleepStageSample>(() => listSleep(from: from, to: to));

  /// Shared poll-on-subscribe / poll-every-N / cancel-on-unsubscribe
  /// implementation used by every `watch*` method. Kept private so the
  /// shape is consistent across data kinds — they all share the 60s
  /// cadence and the onListen/onCancel semantics.
  Stream<List<T>> _pollStream<T>(Future<List<T>> Function() fetch) {
    late StreamController<List<T>> controller;
    Timer? timer;

    Future<void> emit() async {
      try {
        final samples = await fetch();
        if (!controller.isClosed) controller.add(samples);
      } catch (err, stack) {
        if (!controller.isClosed) controller.addError(err, stack);
      }
    }

    controller = StreamController<List<T>>(
      onListen: () {
        emit();
        timer = Timer.periodic(_kPollInterval, (_) => emit());
      },
      onCancel: () {
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  /// Maps a raw `HealthDataPoint` to our façade `HKBodyWeightSample`.
  /// Returns `null` for points we choose to drop:
  ///   * non-WEIGHT types (shouldn't happen given we only ask for WEIGHT)
  ///   * mass units other than KILOGRAM / POUND (no silent conversion)
  ///   * non-numeric values (shouldn't happen for WEIGHT, but guard)
  HKBodyWeightSample? _toBodyWeightSample(HealthDataPoint point) {
    if (point.type != HealthDataType.WEIGHT) return null;
    final WeightUnit? unit = switch (point.unit) {
      HealthDataUnit.KILOGRAM => WeightUnit.kg,
      HealthDataUnit.POUND => WeightUnit.lb,
      _ => null,
    };
    if (unit == null) return null;
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    return HKBodyWeightSample(
      sourceId: point.sourceId,
      timestamp: point.dateFrom,
      value: value.numericValue.toDouble(),
      unit: unit,
    );
  }

  /// Maps a raw `HealthDataPoint` to `HKHRVSample`. Returns `null` for
  /// unexpected shapes (wrong type, non-numeric value).
  HKHRVSample? _toHRVSample(HealthDataPoint point) {
    if (point.type != HealthDataType.HEART_RATE_VARIABILITY_SDNN) return null;
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    // HK reports SDNN in MILLISECOND — no conversion needed.
    return HKHRVSample(
      sourceId: point.sourceId,
      timestamp: point.dateFrom,
      sdnnMs: value.numericValue.toDouble(),
    );
  }

  /// Maps a raw `HealthDataPoint` to `HKRestingHRSample`. Returns `null`
  /// for unexpected shapes.
  HKRestingHRSample? _toRestingHRSample(HealthDataPoint point) {
    if (point.type != HealthDataType.RESTING_HEART_RATE) return null;
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    return HKRestingHRSample(
      sourceId: point.sourceId,
      timestamp: point.dateFrom,
      bpm: value.numericValue.toDouble(),
    );
  }

  /// Maps a raw `HealthDataPoint` to `HKSleepStageSample`. Returns `null`
  /// if the point isn't a sleep type. Stage mapping is via
  /// [_mapHealthSleepType].
  HKSleepStageSample? _toSleepStageSample(HealthDataPoint point) {
    final stage = _mapHealthSleepType(point.type);
    if (stage == null) return null;
    return HKSleepStageSample(
      sourceId: point.sourceId,
      start: point.dateFrom,
      end: point.dateTo,
      stage: stage,
    );
  }

  /// Maps the `health` package's `HealthDataType.SLEEP_*` values into our
  /// compact [SleepStage] enum.
  ///
  /// Returns `null` for any non-SLEEP_* type — callers drop those points
  /// (we don't want a silent fallback that e.g. turns WEIGHT into
  /// asleepUnspecified).
  ///
  /// Enumeration rationale:
  ///   SLEEP_IN_BED        → inBed
  ///   SLEEP_ASLEEP        → asleepUnspecified (generic pre-iOS 16 value)
  ///   SLEEP_LIGHT         → asleepCore        (iOS 16+ core == light)
  ///   SLEEP_DEEP          → asleepDeep
  ///   SLEEP_REM           → asleepREM
  ///   SLEEP_AWAKE         → awake
  ///   SLEEP_AWAKE_IN_BED  → awake             (user awake, still in bed)
  ///   SLEEP_OUT_OF_BED    → awake             (user got up)
  ///   SLEEP_SESSION       → asleepUnspecified (container for a whole
  ///                                            sleep session — fold into
  ///                                            the generic bucket until a
  ///                                            consumer needs it)
  ///   SLEEP_UNKNOWN       → asleepUnspecified (explicit unknown — use the
  ///                                            generic "asleep but no
  ///                                            stage detail" bucket)
  ///   SLEEP_WRIST_TEMPERATURE — not a sleep stage; returns null and the
  ///                             caller drops it.
  SleepStage? _mapHealthSleepType(HealthDataType type) {
    return switch (type) {
      HealthDataType.SLEEP_IN_BED => SleepStage.inBed,
      HealthDataType.SLEEP_ASLEEP => SleepStage.asleepUnspecified,
      HealthDataType.SLEEP_LIGHT => SleepStage.asleepCore,
      HealthDataType.SLEEP_DEEP => SleepStage.asleepDeep,
      HealthDataType.SLEEP_REM => SleepStage.asleepREM,
      HealthDataType.SLEEP_AWAKE => SleepStage.awake,
      HealthDataType.SLEEP_AWAKE_IN_BED => SleepStage.awake,
      HealthDataType.SLEEP_OUT_OF_BED => SleepStage.awake,
      HealthDataType.SLEEP_SESSION => SleepStage.asleepUnspecified,
      HealthDataType.SLEEP_UNKNOWN => SleepStage.asleepUnspecified,
      // SLEEP_WRIST_TEMPERATURE is a temperature-during-sleep sample, not a
      // stage — drop it.
      HealthDataType.SLEEP_WRIST_TEMPERATURE => null,
      // Non-SLEEP_* type — drop. We don't want a default fallback that
      // silently promotes e.g. a WEIGHT point into a sleep sample.
      _ => null,
    };
  }
}

/// Test-only hook — exposes `_mapHealthSleepType` without loosening the
/// visibility of the rest of the impl. Lives at library scope (same file)
/// so it can reach the private method.
///
/// This is the documented seam for `health_source_impl_sleep_mapping_test.dart`:
/// given every `HealthDataType.SLEEP_*` enum value (including
/// `SLEEP_WRIST_TEMPERATURE`), it returns the same [SleepStage] / null the
/// `listSleep` pipeline would — proving the mapping is exhaustive.
@visibleForTesting
SleepStage? debugMapHealthSleepType(
  HealthSourceImpl impl,
  HealthDataType type,
) => impl._mapHealthSleepType(type);
