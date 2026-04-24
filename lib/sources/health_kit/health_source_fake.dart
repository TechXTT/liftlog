// Test-only fake for the `HealthSource` façade.
//
// Injected via Riverpod provider override in widget tests so we never
// touch `package:health` from a test. Lives under `lib/sources/` (not
// `test/`) so production providers can also import it when running in a
// simulator-without-HealthKit context — but those production overrides
// must be gated explicitly; nothing does that today.

import 'dart:async';

import 'health_source.dart';

/// Stubbed `HealthSource` that returns whatever was handed to it.
///
/// Use `HealthSourceFake.authorized(samples)` for the happy path,
/// `HealthSourceFake.notAuthorized()` for the denied / never-asked path,
/// and `HealthSourceFake.throwing(err)` to simulate a native error.
class HealthSourceFake implements HealthSource {
  HealthSourceFake({
    required bool authorized,
    List<HKBodyWeightSample> samples = const [],
    Object? error,
    bool permissionGrantOutcome = true,
  }) : _authorized = authorized,
       _samples = List.unmodifiable(samples),
       _error = error,
       _permissionGrantOutcome = permissionGrantOutcome;

  /// Convenience: authorized, returns the given samples on list/watch.
  factory HealthSourceFake.authorized(List<HKBodyWeightSample> samples) =>
      HealthSourceFake(authorized: true, samples: samples);

  /// Convenience: not authorized. `listBodyWeight` returns empty (per the
  /// façade contract). `requestPermissions` returns [permissionGrantOutcome].
  factory HealthSourceFake.notAuthorized({
    bool permissionGrantOutcome = true,
  }) => HealthSourceFake(
    authorized: false,
    permissionGrantOutcome: permissionGrantOutcome,
  );

  /// Convenience: throws [error] from every list/watch call — use to
  /// exercise the error path without needing a real plugin.
  factory HealthSourceFake.throwing(Object error) =>
      HealthSourceFake(authorized: true, error: error);

  final bool _authorized;
  final List<HKBodyWeightSample> _samples;
  final Object? _error;
  final bool _permissionGrantOutcome;

  int requestPermissionsCallCount = 0;
  int listCallCount = 0;

  @override
  Future<bool> requestPermissions() async {
    requestPermissionsCallCount += 1;
    return _permissionGrantOutcome;
  }

  @override
  Future<bool> isAuthorized() async => _authorized;

  @override
  Future<List<HKBodyWeightSample>> listBodyWeight({
    required DateTime from,
    required DateTime to,
  }) async {
    listCallCount += 1;
    if (_error != null) throw _error;
    if (!_authorized) return const [];
    // Filter to the requested range — matches the real impl's semantics.
    final inRange =
        _samples
            .where(
              (s) => !s.timestamp.isBefore(from) && s.timestamp.isBefore(to),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return inRange;
  }

  @override
  Stream<List<HKBodyWeightSample>> watchBodyWeight({
    required DateTime from,
    required DateTime to,
  }) async* {
    // Single emission is enough for widget tests; production impl polls.
    yield await listBodyWeight(from: from, to: to);
  }
}
