import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/data/enums.dart';
import 'package:liftlog_app/sources/health_kit/health_source.dart';
import 'package:liftlog_app/sources/health_kit/health_source_fake.dart';

void main() {
  group('HKBodyWeightSample value equality', () {
    test('two samples with identical fields compare equal', () {
      final a = HKBodyWeightSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        value: 80.0,
        unit: WeightUnit.kg,
      );
      final b = HKBodyWeightSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        value: 80.0,
        unit: WeightUnit.kg,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('samples that differ on any field compare unequal', () {
      final base = HKBodyWeightSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        value: 80.0,
        unit: WeightUnit.kg,
      );
      // Different timestamp.
      expect(
        base,
        isNot(
          equals(
            HKBodyWeightSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 21, 7),
              value: 80.0,
              unit: WeightUnit.kg,
            ),
          ),
        ),
      );
      // Different unit.
      expect(
        base,
        isNot(
          equals(
            HKBodyWeightSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 20, 7),
              value: 80.0,
              unit: WeightUnit.lb,
            ),
          ),
        ),
      );
      // Different value.
      expect(
        base,
        isNot(
          equals(
            HKBodyWeightSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 20, 7),
              value: 80.5,
              unit: WeightUnit.kg,
            ),
          ),
        ),
      );
      // Different sourceId.
      expect(
        base,
        isNot(
          equals(
            HKBodyWeightSample(
              sourceId: 'net.example.Scale',
              timestamp: DateTime(2026, 4, 20, 7),
              value: 80.0,
              unit: WeightUnit.kg,
            ),
          ),
        ),
      );
    });
  });

  group('HealthSourceFake contract', () {
    final s1 = HKBodyWeightSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 20, 7),
      value: 80.0,
      unit: WeightUnit.kg,
    );
    final s2 = HKBodyWeightSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 23, 7),
      value: 176.0,
      unit: WeightUnit.lb,
    );

    test(
      'authorized: listBodyWeight returns range-filtered, newest-first',
      () async {
        final fake = HealthSourceFake.authorized([s1, s2]);
        final got = await fake.listBodyWeight(
          from: DateTime(2026, 4, 1),
          to: DateTime(2026, 5, 1),
        );
        expect(got, equals([s2, s1]));
      },
    );

    test(
      'authorized: range exclusion filters out samples outside window',
      () async {
        final fake = HealthSourceFake.authorized([s1, s2]);
        final got = await fake.listBodyWeight(
          from: DateTime(2026, 4, 21),
          to: DateTime(2026, 5, 1),
        );
        expect(got, equals([s2]));
      },
    );

    test('not authorized: listBodyWeight returns []', () async {
      final fake = HealthSourceFake.notAuthorized();
      final got = await fake.listBodyWeight(
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(got, isEmpty);
      expect(await fake.isAuthorized(), isFalse);
    });

    test(
      'requestPermissions: records the call and returns the stub outcome',
      () async {
        final granting = HealthSourceFake.notAuthorized();
        final denying = HealthSourceFake.notAuthorized(
          permissionGrantOutcome: false,
        );

        expect(await granting.requestPermissions(), isTrue);
        expect(await denying.requestPermissions(), isFalse);

        expect(granting.requestPermissionsCallCount, 1);
        expect(denying.requestPermissionsCallCount, 1);
      },
    );

    test('throwing fake surfaces the stubbed error', () async {
      final fake = HealthSourceFake.throwing(StateError('boom'));
      await expectLater(
        fake.listBodyWeight(
          from: DateTime(2026, 4, 1),
          to: DateTime(2026, 5, 1),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('watchBodyWeight emits the initial list', () async {
      final fake = HealthSourceFake.authorized([s1, s2]);
      final first = await fake
          .watchBodyWeight(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1))
          .first;
      expect(first, equals([s2, s1]));
    });
  });
}
