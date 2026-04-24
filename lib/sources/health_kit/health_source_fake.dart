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
/// Factory helpers:
/// * `HealthSourceFake.authorized(samples)` — happy path, body-weight only.
/// * `HealthSourceFake.notAuthorized()` — every list* returns `[]`.
/// * `HealthSourceFake.throwing(err)` — every list* throws.
/// * `HealthSourceFake.withHRV(samples)` — authorized, only HRV stubbed.
/// * `HealthSourceFake.withRestingHR(samples)` — authorized, only resting HR.
/// * `HealthSourceFake.withSleep(samples)` — authorized, only sleep stubbed.
/// * `HealthSourceFake.withWorkouts(samples)` — authorized, only workouts
///   stubbed.
/// * `HealthSourceFake.authorizedWithSignals({weight, hrv, restingHR,
///   sleep, workouts})` — composite, for widget tests that want to stub
///   multiple signals at once.
class HealthSourceFake implements HealthSource {
  HealthSourceFake({
    required bool authorized,
    List<HKBodyWeightSample> samples = const [],
    List<HKHRVSample> hrvSamples = const [],
    List<HKRestingHRSample> restingHrSamples = const [],
    List<HKSleepStageSample> sleepSamples = const [],
    List<HKWorkoutSample> workoutSamples = const [],
    Object? error,
    bool permissionGrantOutcome = true,
  }) : _authorized = authorized,
       _samples = List.unmodifiable(samples),
       _hrvSamples = List.unmodifiable(hrvSamples),
       _restingHrSamples = List.unmodifiable(restingHrSamples),
       _sleepSamples = List.unmodifiable(sleepSamples),
       _workoutSamples = List.unmodifiable(workoutSamples),
       _error = error,
       _permissionGrantOutcome = permissionGrantOutcome;

  /// Convenience: authorized, returns the given body-weight samples on
  /// list/watch. Other signals (HRV / resting HR / sleep) return `[]` —
  /// use [HealthSourceFake.authorizedWithSignals] for multi-signal tests.
  factory HealthSourceFake.authorized(List<HKBodyWeightSample> samples) =>
      HealthSourceFake(authorized: true, samples: samples);

  /// Convenience: not authorized. `list*` methods return `[]` (per the
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

  /// Convenience: authorized, HRV samples only. `listBodyWeight` /
  /// `listRestingHR` / `listSleep` all return `[]`.
  factory HealthSourceFake.withHRV(List<HKHRVSample> samples) =>
      HealthSourceFake(authorized: true, hrvSamples: samples);

  /// Convenience: authorized, resting-HR samples only.
  factory HealthSourceFake.withRestingHR(List<HKRestingHRSample> samples) =>
      HealthSourceFake(authorized: true, restingHrSamples: samples);

  /// Convenience: authorized, sleep-stage samples only.
  factory HealthSourceFake.withSleep(List<HKSleepStageSample> samples) =>
      HealthSourceFake(authorized: true, sleepSamples: samples);

  /// Convenience: authorized, workout samples only.
  factory HealthSourceFake.withWorkouts(List<HKWorkoutSample> samples) =>
      HealthSourceFake(authorized: true, workoutSamples: samples);

  /// Composite factory: authorized, stub multiple signal kinds at once.
  /// Any omitted kind defaults to `[]`. Use this from widget tests that
  /// exercise several HK signals simultaneously.
  factory HealthSourceFake.authorizedWithSignals({
    List<HKBodyWeightSample> weight = const [],
    List<HKHRVSample> hrv = const [],
    List<HKRestingHRSample> restingHR = const [],
    List<HKSleepStageSample> sleep = const [],
    List<HKWorkoutSample> workouts = const [],
  }) => HealthSourceFake(
    authorized: true,
    samples: weight,
    hrvSamples: hrv,
    restingHrSamples: restingHR,
    sleepSamples: sleep,
    workoutSamples: workouts,
  );

  final bool _authorized;
  final List<HKBodyWeightSample> _samples;
  final List<HKHRVSample> _hrvSamples;
  final List<HKRestingHRSample> _restingHrSamples;
  final List<HKSleepStageSample> _sleepSamples;
  final List<HKWorkoutSample> _workoutSamples;
  final Object? _error;
  final bool _permissionGrantOutcome;

  int requestPermissionsCallCount = 0;
  int listCallCount = 0;
  int listHRVCallCount = 0;
  int listRestingHRCallCount = 0;
  int listSleepCallCount = 0;
  int listWorkoutsCallCount = 0;

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

  @override
  Future<List<HKHRVSample>> listHRV({
    required DateTime from,
    required DateTime to,
  }) async {
    listHRVCallCount += 1;
    if (_error != null) throw _error;
    if (!_authorized) return const [];
    final inRange =
        _hrvSamples
            .where(
              (s) => !s.timestamp.isBefore(from) && s.timestamp.isBefore(to),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return inRange;
  }

  @override
  Stream<List<HKHRVSample>> watchHRV({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield await listHRV(from: from, to: to);
  }

  @override
  Future<List<HKRestingHRSample>> listRestingHR({
    required DateTime from,
    required DateTime to,
  }) async {
    listRestingHRCallCount += 1;
    if (_error != null) throw _error;
    if (!_authorized) return const [];
    final inRange =
        _restingHrSamples
            .where(
              (s) => !s.timestamp.isBefore(from) && s.timestamp.isBefore(to),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return inRange;
  }

  @override
  Stream<List<HKRestingHRSample>> watchRestingHR({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield await listRestingHR(from: from, to: to);
  }

  @override
  Future<List<HKSleepStageSample>> listSleep({
    required DateTime from,
    required DateTime to,
  }) async {
    listSleepCallCount += 1;
    if (_error != null) throw _error;
    if (!_authorized) return const [];
    // Overlap semantics: a sleep interval that touches the window at all
    // is in range. Matches how a consumer would reason about "samples
    // during this window" — a stretch of sleep spanning the window
    // boundary shouldn't be dropped.
    final inRange =
        _sleepSamples
            .where((s) => s.start.isBefore(to) && s.end.isAfter(from))
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start));
    return inRange;
  }

  @override
  Stream<List<HKSleepStageSample>> watchSleep({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield await listSleep(from: from, to: to);
  }

  @override
  Future<List<HKWorkoutSample>> listWorkouts({
    required DateTime from,
    required DateTime to,
  }) async {
    listWorkoutsCallCount += 1;
    if (_error != null) throw _error;
    if (!_authorized) return const [];
    // `startedAt` in range — from-inclusive, to-exclusive, matching
    // `listBodyWeight` semantics. Workouts are interval-shaped, but a
    // workout is "in" a window if it started during the window; that
    // matches how a consumer reasons about "workouts on this date."
    final inRange =
        _workoutSamples
            .where(
              (s) => !s.startedAt.isBefore(from) && s.startedAt.isBefore(to),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return inRange;
  }

  @override
  Stream<List<HKWorkoutSample>> watchWorkouts({
    required DateTime from,
    required DateTime to,
  }) async* {
    yield await listWorkouts(from: from, to: to);
  }
}
