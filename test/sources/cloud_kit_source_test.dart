// Unit tests for the `CloudKitSource` façade (issue #69, S7.1).
//
// Exercises [FakeCloudKitSource] over every [CloudKitAccountStatus]
// value so the enum ordering — which is load-bearing on the native wire
// protocol — stays pinned. A reorder on either side without a matching
// Swift change will fail the status-decoding test in
// `method_channel_cloud_kit_source_test.dart`; this test pins the Dart
// side in isolation.

import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/sources/cloudkit/cloud_kit_source.dart';
import 'package:liftlog_app/sources/cloudkit/fake_cloud_kit_source.dart';

void main() {
  group('FakeCloudKitSource', () {
    test('returns the initial status handed to the ctor', () async {
      for (final status in CloudKitAccountStatus.values) {
        final fake = FakeCloudKitSource(initialStatus: status);
        expect(await fake.getAccountStatus(), equals(status));
      }
    });

    test('counts getAccountStatus calls', () async {
      final fake = FakeCloudKitSource(
        initialStatus: CloudKitAccountStatus.available,
      );
      expect(fake.getAccountStatusCallCount, 0);
      await fake.getAccountStatus();
      await fake.getAccountStatus();
      expect(fake.getAccountStatusCallCount, 2);
    });

    test('setStatus swaps the value returned on subsequent calls', () async {
      final fake = FakeCloudKitSource(
        initialStatus: CloudKitAccountStatus.couldNotDetermine,
      );
      expect(
        await fake.getAccountStatus(),
        equals(CloudKitAccountStatus.couldNotDetermine),
      );
      fake.setStatus(CloudKitAccountStatus.noAccount);
      expect(
        await fake.getAccountStatus(),
        equals(CloudKitAccountStatus.noAccount),
      );
    });

    test('throws the configured error from getAccountStatus', () async {
      final err = Exception('boom');
      final fake = FakeCloudKitSource(error: err);
      expect(() => fake.getAccountStatus(), throwsA(same(err)));
    });

    test(
      'defaults to couldNotDetermine when no initialStatus is given',
      () async {
        final fake = FakeCloudKitSource();
        expect(
          await fake.getAccountStatus(),
          equals(CloudKitAccountStatus.couldNotDetermine),
        );
      },
    );
  });

  group('CloudKitAccountStatus — ordering contract', () {
    // Load-bearing: the native Swift side sends `CKAccountStatus.rawValue`
    // and the Dart side maps by index. Apple's order is
    //   couldNotDetermine=0, available=1, restricted=2, noAccount=3,
    //   temporarilyUnavailable=4
    // Test pins Dart declaration-order against that contract. If this
    // breaks, fix the `enum` declaration — not the test.
    test('declaration order matches Apple CKAccountStatus raw values', () {
      expect(CloudKitAccountStatus.values, [
        CloudKitAccountStatus.couldNotDetermine,
        CloudKitAccountStatus.available,
        CloudKitAccountStatus.restricted,
        CloudKitAccountStatus.noAccount,
        CloudKitAccountStatus.temporarilyUnavailable,
      ]);
    });

    test('all five values are present', () {
      expect(CloudKitAccountStatus.values, hasLength(5));
    });
  });

  group('CloudKitUnknownError', () {
    test('preserves the raw status in toString', () {
      const err = CloudKitUnknownError(42, 'diagnostic');
      expect(err.toString(), contains('rawStatus: 42'));
      expect(err.toString(), contains('diagnostic'));
    });

    test('omits the colon suffix when message is null', () {
      const err = CloudKitUnknownError(99);
      expect(err.toString(), 'CloudKitUnknownError(rawStatus: 99)');
    });
  });

  group('CloudKitChannelError', () {
    test('preserves code + message + details in toString', () {
      const err = CloudKitChannelError(
        code: 'CK_ACCOUNT_STATUS_FAILED',
        message: 'account status fetch failed',
        details: 'ns-error-description',
      );
      expect(err.toString(), contains('CK_ACCOUNT_STATUS_FAILED'));
      expect(err.toString(), contains('account status fetch failed'));
      expect(err.toString(), contains('ns-error-description'));
    });
  });

  group('CloudKitValue — equality + hash', () {
    test('CKString equality and hash', () {
      expect(const CKString('a'), const CKString('a'));
      expect(const CKString('a').hashCode, const CKString('a').hashCode);
      expect(const CKString('a') == const CKString('b'), isFalse);
    });

    test('CKInt equality preserves integer precision', () {
      // Values near Int64.max — these are the ones that would be
      // silently stringified by the flutter_cloud_kit plugin.
      const big = CKInt(9007199254740992); // 2^53
      expect(big, const CKInt(9007199254740992));
      expect(big == const CKInt(9007199254740993), isFalse);
    });

    test('CKDouble equality preserves bit pattern', () {
      const pi = CKDouble(3.141592653589793);
      expect(pi, const CKDouble(3.141592653589793));
      expect(pi == const CKDouble(3.14), isFalse);
    });

    test('CKBool equality', () {
      expect(const CKBool(true), const CKBool(true));
      expect(const CKBool(true) == const CKBool(false), isFalse);
    });

    test('CKDateTime equality on absolute instant', () {
      final utc = DateTime.utc(2026, 4, 24, 12, 0, 0, 123);
      final localEquiv = utc.toLocal();
      expect(CKDateTime(utc), CKDateTime(localEquiv));
      expect(
        CKDateTime(utc) == CKDateTime(utc.add(const Duration(milliseconds: 1))),
        isFalse,
      );
    });

    test('heterogeneous subtypes never compare equal', () {
      // A Boolean true and an Int 1 shouldn't compare equal. Trust-rule
      // reason: a toggle (bool) and a count (int) must never silently
      // alias, even though their JSON/channel form might be
      // indistinguishable on an untyped path.
      expect(const CKBool(true) == const CKInt(1), isFalse);
      expect(const CKString('1') == const CKInt(1), isFalse);
    });
  });

  group('CloudKitRecord — equality + hash', () {
    test('equal when type + name + field map all match', () {
      const a = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {'note': CKString('ok'), 'kcal': CKInt(612)},
      );
      const b = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        // Different iteration order — must still compare equal since
        // CKRecord field order isn't semantic.
        fields: {'kcal': CKInt(612), 'note': CKString('ok')},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs on recordType', () {
      const a = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'x',
        fields: {},
      );
      const b = CloudKitRecord(
        recordType: 'OtherType',
        recordName: 'x',
        fields: {},
      );
      expect(a == b, isFalse);
    });

    test('differs on recordName', () {
      const a = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'a',
        fields: {},
      );
      const b = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'b',
        fields: {},
      );
      expect(a == b, isFalse);
    });

    test('differs on field value', () {
      const a = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'x',
        fields: {'kcal': CKInt(612)},
      );
      const b = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'x',
        fields: {'kcal': CKInt(613)},
      );
      expect(a == b, isFalse);
    });
  });

  group('FakeCloudKitSource — record CRUD', () {
    /// Helper: the canonical mixed-type spike record used across tests.
    /// One field of each of the 5 supported CloudKit value types.
    CloudKitRecord spikeRecord() {
      return CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {
          'title': const CKString('evening session'),
          'reps': const CKInt(12),
          'weightKg': const CKDouble(102.5),
          'wasPr': const CKBool(true),
          'when': CKDateTime(DateTime.utc(2026, 4, 24, 18, 30, 45, 789)),
        },
      );
    }

    test(
      'round-trips a record with all 5 value types, preserving equality',
      () async {
        final fake = FakeCloudKitSource();
        final saved = spikeRecord();
        await fake.saveRecord(saved);

        final fetched = await fake.getRecord(
          recordType: 'HealthSpike',
          recordName: 'spike-1',
        );

        expect(fetched, isNotNull);
        expect(fetched, equals(saved));
        // Spot-check DateTime precision — millisecond-accurate.
        expect(
          (fetched!.fields['when']! as CKDateTime).value.millisecondsSinceEpoch,
          (saved.fields['when']! as CKDateTime).value.millisecondsSinceEpoch,
        );
        expect(fake.saveRecordCallCount, 1);
        expect(fake.getRecordCallCount, 1);
      },
    );

    test('returns null for record that was never saved', () async {
      final fake = FakeCloudKitSource();
      final fetched = await fake.getRecord(
        recordType: 'HealthSpike',
        recordName: 'missing',
      );
      expect(fetched, isNull);
    });

    test('saveRecord upserts — second save overwrites the first', () async {
      final fake = FakeCloudKitSource();
      const v1 = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {'kcal': CKInt(600)},
      );
      const v2 = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {'kcal': CKInt(650)},
      );
      await fake.saveRecord(v1);
      await fake.saveRecord(v2);

      final fetched = await fake.getRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
      );
      expect(fetched, equals(v2));
    });

    test(
      'recordType namespaces recordName — same name in different types do not collide',
      () async {
        final fake = FakeCloudKitSource();
        const a = CloudKitRecord(
          recordType: 'TypeA',
          recordName: 'same',
          fields: {'v': CKInt(1)},
        );
        const b = CloudKitRecord(
          recordType: 'TypeB',
          recordName: 'same',
          fields: {'v': CKInt(2)},
        );
        await fake.saveRecord(a);
        await fake.saveRecord(b);

        expect(
          await fake.getRecord(recordType: 'TypeA', recordName: 'same'),
          equals(a),
        );
        expect(
          await fake.getRecord(recordType: 'TypeB', recordName: 'same'),
          equals(b),
        );
      },
    );

    test('configured error surfaces on saveRecord', () async {
      final err = Exception('network down');
      final fake = FakeCloudKitSource(error: err);
      const record = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'x',
        fields: {},
      );
      expect(() => fake.saveRecord(record), throwsA(same(err)));
    });

    test('configured error surfaces on getRecord', () async {
      final err = Exception('network down');
      final fake = FakeCloudKitSource(error: err);
      expect(
        () => fake.getRecord(recordType: 'HealthSpike', recordName: 'x'),
        throwsA(same(err)),
      );
    });
  });

  group('kLiftLogZoneName constant', () {
    // Load-bearing: the Dart façade exports this as the canonical app
    // zone name; Runbooks.md + feature code references the literal
    // "LiftLogZone". If this ever changes, CloudKit records land in a
    // different zone on next run — an incident, not a refactor. Pin it.
    test('equals "LiftLogZone"', () {
      expect(kLiftLogZoneName, 'LiftLogZone');
    });
  });

  group('FakeCloudKitSource — ensureZoneExists', () {
    test('first call creates the zone; createdZones reflects it', () async {
      final fake = FakeCloudKitSource();
      expect(fake.createdZones, isEmpty);

      await fake.ensureZoneExists(zoneName: kLiftLogZoneName);

      expect(fake.createdZones, contains(kLiftLogZoneName));
      expect(fake.createdZones, hasLength(1));
      expect(fake.ensureZoneExistsCallCount, 1);
    });

    test('second call with the same name is a no-op (idempotent)', () async {
      final fake = FakeCloudKitSource();
      await fake.ensureZoneExists(zoneName: kLiftLogZoneName);
      await fake.ensureZoneExists(zoneName: kLiftLogZoneName);

      // Still one zone created; call count reflects both invocations.
      expect(fake.createdZones, hasLength(1));
      expect(fake.createdZones, contains(kLiftLogZoneName));
      expect(fake.ensureZoneExistsCallCount, 2);
    });

    test('distinct zone names create distinct zones', () async {
      // Forward-looking: S7.3 only uses one zone, but the fake keeps
      // its tracking general so a future multi-zone strategy doesn't
      // need another test scaffold.
      final fake = FakeCloudKitSource();
      await fake.ensureZoneExists(zoneName: 'LiftLogZone');
      await fake.ensureZoneExists(zoneName: 'SomeOtherZone');

      expect(fake.createdZones, hasLength(2));
      expect(fake.createdZones, contains('LiftLogZone'));
      expect(fake.createdZones, contains('SomeOtherZone'));
    });

    test('configured error surfaces on ensureZoneExists', () async {
      final err = Exception('network down');
      final fake = FakeCloudKitSource(error: err);
      expect(
        () => fake.ensureZoneExists(zoneName: kLiftLogZoneName),
        throwsA(same(err)),
      );
    });

    test('createdZones view is unmodifiable', () {
      // Defensive: callers can't mutate internal fake state by
      // reaching into the accessor's returned set.
      final fake = FakeCloudKitSource();
      expect(
        () => fake.createdZones.add('sneaky'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('FakeCloudKitSource — zone-scoped CRUD', () {
    test('round-trip with explicit zoneName preserves the record', () async {
      final fake = FakeCloudKitSource();
      await fake.ensureZoneExists(zoneName: kLiftLogZoneName);

      const saved = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {'kcal': CKInt(612)},
      );
      await fake.saveRecord(saved, zoneName: kLiftLogZoneName);

      final fetched = await fake.getRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        zoneName: kLiftLogZoneName,
      );
      expect(fetched, equals(saved));
    });

    test(
      'record saved in default zone is NOT visible from LiftLogZone',
      () async {
        // Trust rule: zone scoping is absolute. A record in the default
        // zone must not bleed into a custom zone — otherwise cleanup
        // of S7.2 probe records wouldn't be isolable.
        final fake = FakeCloudKitSource();
        const record = CloudKitRecord(
          recordType: 'HealthSpike',
          recordName: 'spike-1',
          fields: {'v': CKInt(1)},
        );
        // Save into default zone (zoneName omitted == null).
        await fake.saveRecord(record);

        // Default-zone fetch sees it.
        expect(
          await fake.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
          ),
          equals(record),
        );
        // LiftLogZone fetch does NOT.
        expect(
          await fake.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
            zoneName: kLiftLogZoneName,
          ),
          isNull,
        );
      },
    );

    test(
      'record saved in LiftLogZone is NOT visible from default zone',
      () async {
        final fake = FakeCloudKitSource();
        const record = CloudKitRecord(
          recordType: 'HealthSpike',
          recordName: 'spike-1',
          fields: {'v': CKInt(1)},
        );
        await fake.saveRecord(record, zoneName: kLiftLogZoneName);

        // Custom-zone fetch sees it.
        expect(
          await fake.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
            zoneName: kLiftLogZoneName,
          ),
          equals(record),
        );
        // Default-zone fetch does NOT.
        expect(
          await fake.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
          ),
          isNull,
        );
      },
    );

    test(
      'same record name in different zones stores different records',
      () async {
        // Complementary to the isolation tests above: saves to each
        // zone keep their own copy.
        final fake = FakeCloudKitSource();
        const defaultRec = CloudKitRecord(
          recordType: 'HealthSpike',
          recordName: 'same',
          fields: {'v': CKInt(1)},
        );
        const customRec = CloudKitRecord(
          recordType: 'HealthSpike',
          recordName: 'same',
          fields: {'v': CKInt(2)},
        );
        await fake.saveRecord(defaultRec);
        await fake.saveRecord(customRec, zoneName: kLiftLogZoneName);

        expect(
          await fake.getRecord(recordType: 'HealthSpike', recordName: 'same'),
          equals(defaultRec),
        );
        expect(
          await fake.getRecord(
            recordType: 'HealthSpike',
            recordName: 'same',
            zoneName: kLiftLogZoneName,
          ),
          equals(customRec),
        );
      },
    );
  });
}
