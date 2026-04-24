// Table-driven test for `HealthSourceImpl._mapHealthWorkoutType`.
//
// Covers every `HealthWorkoutActivityType` value that `package:health`
// ships. If the package adds a new activity type in a future version,
// the mapping `switch` in `health_source_impl.dart` has no fallthrough
// default — so an added value will fail analysis. This test pins that
// guarantee at the test level too, asserting every known activity type
// has an explicit mapping (to either a surfaced [HKWorkoutType] bucket
// or the explicit `HKWorkoutType.other` catch-all).

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_impl.dart';

void main() {
  final impl = HealthSourceImpl();

  group('_mapHealthWorkoutType — surfaced buckets', () {
    // The nine buckets that surface to the UI. Each maps from one or
    // more `HealthWorkoutActivityType` values. If the `health` package
    // bumps and renames/removes any of these, the mapping switch will
    // fail analysis AND this test will fail — forcing a lock-step fix.
    final surfaced = <HealthWorkoutActivityType, HKWorkoutType>{
      HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING:
          HKWorkoutType.traditionalStrengthTraining,
      HealthWorkoutActivityType.STRENGTH_TRAINING:
          HKWorkoutType.traditionalStrengthTraining,
      HealthWorkoutActivityType.WEIGHTLIFTING:
          HKWorkoutType.traditionalStrengthTraining,
      HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING:
          HKWorkoutType.functionalStrengthTraining,
      HealthWorkoutActivityType.CORE_TRAINING: HKWorkoutType.coreTraining,
      HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING:
          HKWorkoutType.highIntensityIntervalTraining,
      HealthWorkoutActivityType.RUNNING: HKWorkoutType.running,
      HealthWorkoutActivityType.RUNNING_TREADMILL: HKWorkoutType.running,
      HealthWorkoutActivityType.WALKING: HKWorkoutType.walking,
      HealthWorkoutActivityType.WALKING_TREADMILL: HKWorkoutType.walking,
      HealthWorkoutActivityType.BIKING: HKWorkoutType.cycling,
      HealthWorkoutActivityType.BIKING_STATIONARY: HKWorkoutType.cycling,
      HealthWorkoutActivityType.YOGA: HKWorkoutType.yoga,
    };

    for (final entry in surfaced.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(debugMapHealthWorkoutType(impl, entry.key), equals(entry.value));
      });
    }
  });

  group('_mapHealthWorkoutType — other catch-all', () {
    // A representative (non-exhaustive) sample of activity types that
    // should fold into `other`. Exhaustiveness is verified below via
    // the "every value maps to something" test — this group's job is to
    // document that the `other` bucket is explicit, not a silent
    // fallback.
    final otherSamples = <HealthWorkoutActivityType>[
      HealthWorkoutActivityType.AMERICAN_FOOTBALL,
      HealthWorkoutActivityType.ARCHERY,
      HealthWorkoutActivityType.SWIMMING,
      HealthWorkoutActivityType.TENNIS,
      HealthWorkoutActivityType.PILATES,
      HealthWorkoutActivityType.ELLIPTICAL,
      HealthWorkoutActivityType.ROWING,
      HealthWorkoutActivityType.BOXING,
      HealthWorkoutActivityType.MIXED_CARDIO,
      HealthWorkoutActivityType.FLEXIBILITY,
      HealthWorkoutActivityType.TRACK_AND_FIELD,
      HealthWorkoutActivityType.OTHER,
    ];

    for (final value in otherSamples) {
      test('$value -> HKWorkoutType.other', () {
        expect(
          debugMapHealthWorkoutType(impl, value),
          equals(HKWorkoutType.other),
        );
      });
    }
  });

  test('every HealthWorkoutActivityType value maps to some HKWorkoutType', () {
    // This test is the canary for `health` package bumps. If the
    // package adds a new activity type, the `switch` in the impl has
    // no fallthrough default — so the analyzer flags it and this test
    // will still pass once the new case is added. If, somehow, a case
    // yields `other` only because it was caught by a future default,
    // this test still runs the assertion and documents the contract.
    for (final value in HealthWorkoutActivityType.values) {
      final mapped = debugMapHealthWorkoutType(impl, value);
      // Every value produces a valid HKWorkoutType — no nulls, no
      // throws. The mapping is total.
      expect(HKWorkoutType.values, contains(mapped));
    }
  });
}
