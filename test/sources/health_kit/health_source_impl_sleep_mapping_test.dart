// Table-driven test for `HealthSourceImpl._mapHealthSleepType`.
//
// Covers every `HealthDataType.SLEEP_*` value that `package:health` ships.
// If the package adds a new SLEEP_* enum value in a future version, the
// mapping switch has no fallthrough default for SLEEP_* values and will
// fail analysis — this test pins that guarantee at the test level too,
// asserting every known SLEEP_* maps to either a concrete `SleepStage`
// or `null` (for SLEEP_WRIST_TEMPERATURE, which is temperature-during-sleep
// and not a stage).

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_impl.dart';

void main() {
  final impl = HealthSourceImpl();

  group('_mapHealthSleepType', () {
    // Table of (input HealthDataType, expected SleepStage / null).
    // Every SLEEP_* value in `HealthDataType` must appear exactly once.
    final table = <HealthDataType, SleepStage?>{
      HealthDataType.SLEEP_IN_BED: SleepStage.inBed,
      HealthDataType.SLEEP_ASLEEP: SleepStage.asleepUnspecified,
      HealthDataType.SLEEP_LIGHT: SleepStage.asleepCore,
      HealthDataType.SLEEP_DEEP: SleepStage.asleepDeep,
      HealthDataType.SLEEP_REM: SleepStage.asleepREM,
      HealthDataType.SLEEP_AWAKE: SleepStage.awake,
      HealthDataType.SLEEP_AWAKE_IN_BED: SleepStage.awake,
      HealthDataType.SLEEP_OUT_OF_BED: SleepStage.awake,
      HealthDataType.SLEEP_SESSION: SleepStage.asleepUnspecified,
      HealthDataType.SLEEP_UNKNOWN: SleepStage.asleepUnspecified,
      HealthDataType.SLEEP_WRIST_TEMPERATURE: null,
    };

    for (final entry in table.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(debugMapHealthSleepType(impl, entry.key), equals(entry.value));
      });
    }

    test('non-SLEEP_* types return null (no silent promotion)', () {
      expect(debugMapHealthSleepType(impl, HealthDataType.WEIGHT), isNull);
      expect(
        debugMapHealthSleepType(
          impl,
          HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        ),
        isNull,
      );
      expect(
        debugMapHealthSleepType(impl, HealthDataType.RESTING_HEART_RATE),
        isNull,
      );
    });

    test('every HealthDataType.SLEEP_* value is covered by the table', () {
      // Find every `SLEEP_*` value by name. If the package adds a new one,
      // this test fails — forcing the mapping table to update in lock-step.
      final allSleepTypes = HealthDataType.values
          .where((t) => t.name.startsWith('SLEEP_'))
          .toSet();
      expect(allSleepTypes, equals(table.keys.toSet()));
    });
  });
}
