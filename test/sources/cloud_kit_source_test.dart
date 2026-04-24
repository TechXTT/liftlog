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
}
