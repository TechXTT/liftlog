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
// * `listBodyWeight` returns `[]` when not authorized. That's an agreed
//   contract with the UI (no toast, no nag). Errors from the native side
//   still surface via `Future.error`.
// * `watchBodyWeight` uses a 60-second poll — see the façade comment for
//   the rationale and the TODO.

import 'dart:async';

import 'package:health/health.dart';

import '../../data/enums.dart';
import 'health_source.dart';

/// Default polling cadence for `watchBodyWeight`. Exposed as a
/// top-level constant for test-targeted overrides (none today) and for
/// documentation.
const Duration _kBodyWeightPollInterval = Duration(seconds: 60);

class HealthSourceImpl implements HealthSource {
  HealthSourceImpl({Health? plugin}) : _plugin = plugin ?? Health();

  final Health _plugin;
  bool _configured = false;

  static const List<HealthDataType> _bodyWeightTypes = [HealthDataType.WEIGHT];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _plugin.configure();
    _configured = true;
  }

  @override
  Future<bool> requestPermissions() async {
    await _ensureConfigured();
    return _plugin.requestAuthorization(
      _bodyWeightTypes,
      permissions: const [HealthDataAccess.READ],
    );
  }

  @override
  Future<bool> isAuthorized() async {
    await _ensureConfigured();
    final result = await _plugin.hasPermissions(
      _bodyWeightTypes,
      permissions: const [HealthDataAccess.READ],
    );
    // On iOS `hasPermissions` returns `null` for READ because HealthKit
    // intentionally obscures read-permission state. Treat null as "we
    // don't know — assume unauthorized until the user grants." Callers
    // use this only for UI affordances (the Sync button); the actual
    // list call still handles the empty-when-unauthorized case.
    return result == true;
  }

  @override
  Future<List<HKBodyWeightSample>> listBodyWeight({
    required DateTime from,
    required DateTime to,
  }) async {
    await _ensureConfigured();
    // Surface the "not authorized" state as an empty list per the façade
    // contract — the UI falls back to user-entered rows, no toast.
    final authorized = await isAuthorized();
    if (!authorized) return const [];

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
    // Newest-first to match the façade contract and the UI's expected
    // ordering in the merged list.
    samples.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return samples;
  }

  @override
  Stream<List<HKBodyWeightSample>> watchBodyWeight({
    required DateTime from,
    required DateTime to,
  }) {
    // Poll-on-subscribe, poll-every-N, cancel-on-unsubscribe. Kept
    // deliberately simple; see the TODO in the façade.
    late StreamController<List<HKBodyWeightSample>> controller;
    Timer? timer;

    Future<void> emit() async {
      try {
        final samples = await listBodyWeight(from: from, to: to);
        if (!controller.isClosed) controller.add(samples);
      } catch (err, stack) {
        if (!controller.isClosed) controller.addError(err, stack);
      }
    }

    controller = StreamController<List<HKBodyWeightSample>>(
      onListen: () {
        emit();
        timer = Timer.periodic(_kBodyWeightPollInterval, (_) => emit());
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
}
