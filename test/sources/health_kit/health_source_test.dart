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

  group('HKHRVSample value equality', () {
    test('two samples with identical fields compare equal', () {
      final a = HKHRVSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        sdnnMs: 54.0,
      );
      final b = HKHRVSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        sdnnMs: 54.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('samples that differ on any field compare unequal', () {
      final base = HKHRVSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        sdnnMs: 54.0,
      );
      expect(
        base,
        isNot(
          equals(
            HKHRVSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 21, 7),
              sdnnMs: 54.0,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            HKHRVSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 20, 7),
              sdnnMs: 42.0,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            HKHRVSample(
              sourceId: 'net.example.Wearable',
              timestamp: DateTime(2026, 4, 20, 7),
              sdnnMs: 54.0,
            ),
          ),
        ),
      );
    });
  });

  group('HKRestingHRSample value equality', () {
    test('two samples with identical fields compare equal', () {
      final a = HKRestingHRSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        bpm: 58.0,
      );
      final b = HKRestingHRSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        bpm: 58.0,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('samples that differ on any field compare unequal', () {
      final base = HKRestingHRSample(
        sourceId: 'com.apple.Health',
        timestamp: DateTime(2026, 4, 20, 7),
        bpm: 58.0,
      );
      expect(
        base,
        isNot(
          equals(
            HKRestingHRSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 21, 7),
              bpm: 58.0,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            HKRestingHRSample(
              sourceId: 'com.apple.Health',
              timestamp: DateTime(2026, 4, 20, 7),
              bpm: 62.0,
            ),
          ),
        ),
      );
    });
  });

  group('HKSleepStageSample value equality', () {
    test('two samples with identical fields compare equal', () {
      final a = HKSleepStageSample(
        sourceId: 'com.apple.Health',
        start: DateTime(2026, 4, 20, 23),
        end: DateTime(2026, 4, 21, 7),
        stage: SleepStage.asleepCore,
      );
      final b = HKSleepStageSample(
        sourceId: 'com.apple.Health',
        start: DateTime(2026, 4, 20, 23),
        end: DateTime(2026, 4, 21, 7),
        stage: SleepStage.asleepCore,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('samples that differ on any field compare unequal', () {
      final base = HKSleepStageSample(
        sourceId: 'com.apple.Health',
        start: DateTime(2026, 4, 20, 23),
        end: DateTime(2026, 4, 21, 7),
        stage: SleepStage.asleepCore,
      );
      expect(
        base,
        isNot(
          equals(
            HKSleepStageSample(
              sourceId: 'com.apple.Health',
              start: DateTime(2026, 4, 20, 23),
              end: DateTime(2026, 4, 21, 7),
              stage: SleepStage.asleepDeep,
            ),
          ),
        ),
      );
      expect(
        base,
        isNot(
          equals(
            HKSleepStageSample(
              sourceId: 'com.apple.Health',
              start: DateTime(2026, 4, 20, 22),
              end: DateTime(2026, 4, 21, 7),
              stage: SleepStage.asleepCore,
            ),
          ),
        ),
      );
    });
  });

  group('SleepStage canonical enum', () {
    // Dedicated coverage: every SleepStage value must be reachable in a
    // downstream consumer's `switch`. Since there's no UI consumer yet,
    // a tiny `_dummyLabel` helper proves the enum is fully enumerable
    // without a fallthrough default. If a new SleepStage value lands, the
    // analyzer flags the missing case here before it reaches prod.
    String dummyLabel(SleepStage s) => switch (s) {
      SleepStage.inBed => 'In bed',
      SleepStage.asleepUnspecified => 'Asleep',
      SleepStage.asleepCore => 'Core',
      SleepStage.asleepDeep => 'Deep',
      SleepStage.asleepREM => 'REM',
      SleepStage.awake => 'Awake',
    };

    test('every enum value resolves through an exhaustive switch', () {
      for (final s in SleepStage.values) {
        expect(dummyLabel(s), isNotEmpty);
      }
      // Length check pins the size — if someone adds a 7th stage, the
      // enum must be re-enumerated everywhere.
      expect(SleepStage.values, hasLength(6));
    });
  });

  group('HealthSourceFake — body weight contract', () {
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

  group('HealthSourceFake — HRV contract', () {
    final h1 = HKHRVSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 20, 7),
      sdnnMs: 48.0,
    );
    final h2 = HKHRVSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 22, 7),
      sdnnMs: 55.0,
    );

    test('authorized: listHRV returns range-filtered, newest-first', () async {
      final fake = HealthSourceFake.withHRV([h1, h2]);
      final got = await fake.listHRV(
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(got, equals([h2, h1]));
      expect(fake.listHRVCallCount, 1);
    });

    test(
      'authorized: range exclusion filters out samples outside window',
      () async {
        final fake = HealthSourceFake.withHRV([h1, h2]);
        final got = await fake.listHRV(
          from: DateTime(2026, 4, 21),
          to: DateTime(2026, 5, 1),
        );
        expect(got, equals([h2]));
      },
    );

    test('not authorized: listHRV returns []', () async {
      final fake = HealthSourceFake.notAuthorized();
      final got = await fake.listHRV(
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(got, isEmpty);
    });

    test('throwing fake surfaces the stubbed error for HRV', () async {
      final fake = HealthSourceFake.throwing(StateError('boom'));
      await expectLater(
        fake.listHRV(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1)),
        throwsA(isA<StateError>()),
      );
    });

    test('watchHRV emits the initial list', () async {
      final fake = HealthSourceFake.withHRV([h1, h2]);
      final first = await fake
          .watchHRV(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1))
          .first;
      expect(first, equals([h2, h1]));
    });
  });

  group('HealthSourceFake — resting HR contract', () {
    final r1 = HKRestingHRSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 20, 7),
      bpm: 58.0,
    );
    final r2 = HKRestingHRSample(
      sourceId: 'com.apple.Health',
      timestamp: DateTime(2026, 4, 22, 7),
      bpm: 60.0,
    );

    test(
      'authorized: listRestingHR returns range-filtered, newest-first',
      () async {
        final fake = HealthSourceFake.withRestingHR([r1, r2]);
        final got = await fake.listRestingHR(
          from: DateTime(2026, 4, 1),
          to: DateTime(2026, 5, 1),
        );
        expect(got, equals([r2, r1]));
        expect(fake.listRestingHRCallCount, 1);
      },
    );

    test('not authorized: listRestingHR returns []', () async {
      final fake = HealthSourceFake.notAuthorized();
      final got = await fake.listRestingHR(
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(got, isEmpty);
    });

    test('watchRestingHR emits the initial list', () async {
      final fake = HealthSourceFake.withRestingHR([r1, r2]);
      final first = await fake
          .watchRestingHR(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1))
          .first;
      expect(first, equals([r2, r1]));
    });
  });

  group('HealthSourceFake — sleep contract', () {
    // Two intervals: a deep-sleep stretch followed by REM.
    final deep = HKSleepStageSample(
      sourceId: 'com.apple.Health',
      start: DateTime(2026, 4, 20, 23),
      end: DateTime(2026, 4, 21, 1),
      stage: SleepStage.asleepDeep,
    );
    final rem = HKSleepStageSample(
      sourceId: 'com.apple.Health',
      start: DateTime(2026, 4, 21, 5),
      end: DateTime(2026, 4, 21, 7),
      stage: SleepStage.asleepREM,
    );

    test(
      'authorized: listSleep returns intervals newest-start-first',
      () async {
        final fake = HealthSourceFake.withSleep([deep, rem]);
        final got = await fake.listSleep(
          from: DateTime(2026, 4, 20),
          to: DateTime(2026, 4, 22),
        );
        expect(got, equals([rem, deep]));
        expect(fake.listSleepCallCount, 1);
      },
    );

    test(
      'overlap semantics: interval crossing the window boundary is kept',
      () async {
        // A sleep interval that starts before `from` and ends after `from`
        // should still be in the result — it's sleep during the window.
        final crossing = HKSleepStageSample(
          sourceId: 'com.apple.Health',
          start: DateTime(2026, 4, 19, 23),
          end: DateTime(2026, 4, 20, 1),
          stage: SleepStage.asleepCore,
        );
        final fake = HealthSourceFake.withSleep([crossing]);
        final got = await fake.listSleep(
          from: DateTime(2026, 4, 20),
          to: DateTime(2026, 4, 21),
        );
        expect(got, equals([crossing]));
      },
    );

    test('not authorized: listSleep returns []', () async {
      final fake = HealthSourceFake.notAuthorized();
      final got = await fake.listSleep(
        from: DateTime(2026, 4, 1),
        to: DateTime(2026, 5, 1),
      );
      expect(got, isEmpty);
    });

    test('watchSleep emits the initial list', () async {
      final fake = HealthSourceFake.withSleep([deep, rem]);
      final first = await fake
          .watchSleep(from: DateTime(2026, 4, 20), to: DateTime(2026, 4, 22))
          .first;
      expect(first, equals([rem, deep]));
    });
  });

  group('HealthSourceFake.authorizedWithSignals composite factory', () {
    test(
      'stubs multiple signals at once; omitted kinds default to []',
      () async {
        final weight = HKBodyWeightSample(
          sourceId: 'com.apple.Health',
          timestamp: DateTime(2026, 4, 20, 7),
          value: 80.0,
          unit: WeightUnit.kg,
        );
        final hrv = HKHRVSample(
          sourceId: 'com.apple.Health',
          timestamp: DateTime(2026, 4, 20, 7),
          sdnnMs: 50.0,
        );

        final fake = HealthSourceFake.authorizedWithSignals(
          weight: [weight],
          hrv: [hrv],
        );

        expect(
          await fake.listBodyWeight(
            from: DateTime(2026, 4, 1),
            to: DateTime(2026, 5, 1),
          ),
          equals([weight]),
        );
        expect(
          await fake.listHRV(
            from: DateTime(2026, 4, 1),
            to: DateTime(2026, 5, 1),
          ),
          equals([hrv]),
        );
        // Omitted signals — both default to [].
        expect(
          await fake.listRestingHR(
            from: DateTime(2026, 4, 1),
            to: DateTime(2026, 5, 1),
          ),
          isEmpty,
        );
        expect(
          await fake.listSleep(
            from: DateTime(2026, 4, 1),
            to: DateTime(2026, 5, 1),
          ),
          isEmpty,
        );
      },
    );

    test('throwing fake surfaces the stubbed error from every list', () async {
      final fake = HealthSourceFake.throwing(StateError('boom'));
      await expectLater(
        fake.listHRV(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1)),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        fake.listRestingHR(
          from: DateTime(2026, 4, 1),
          to: DateTime(2026, 5, 1),
        ),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        fake.listSleep(from: DateTime(2026, 4, 1), to: DateTime(2026, 5, 1)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
