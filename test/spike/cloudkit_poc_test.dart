// SPIKE (issue #63): throwaway PoC exercising the flutter_cloud_kit 0.0.3
// public API shape to document what's actually callable from Dart and what
// the failure mode looks like under Flutter's test harness (which has no
// live iOS runtime).
//
// This file is NOT production code and lives only on
// `spike/cloudkit-e3-viability`. It must NOT merge to main.
//
// Expected behavior under `flutter test` (no iOS runtime):
//   - the test compiles and imports succeed (proves the Dart API shape)
//   - every plugin call throws MissingPluginException because there is no
//     platform-side handler registered in the test harness
//   - the test catches those and records them — the point is empirical
//     evidence of the plugin's Dart surface, not CloudKit round-trips
//
// Actual CloudKit reachability requires a physical iPhone or Simulator
// run signed into iCloud. That is out of scope for this spike per PM
// policy — the founder will validate on-device post-spike.

import 'package:flutter/services.dart';
import 'package:flutter_cloud_kit/flutter_cloud_kit.dart';
import 'package:flutter_cloud_kit/types/cloud_kit_account_status.dart';
import 'package:flutter_cloud_kit/types/database_scope.dart';
import 'package:flutter_test/flutter_test.dart';

const _containerId = 'iCloud.dev.techxtt.liftlogApp';
const _recordType = 'SpikeRecord';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('flutter_cloud_kit 0.0.3 API shape', () {
    late FlutterCloudKit cloudKit;

    setUp(() {
      cloudKit = FlutterCloudKit(containerId: _containerId);
    });

    test('getAccountStatus is callable; throws MissingPluginException under test harness',
        () async {
      try {
        final CloudKitAccountStatus status = await cloudKit.getAccountStatus();
        // On an iOS device with no iCloud signed in, expected: CloudKitAccountStatus.noAccount.
        // Under `flutter test` this branch should NOT fire — the channel is unregistered.
        fail(
            'Unexpected success under test harness — got $status. '
            'A live iOS runtime was not expected here.');
      } on MissingPluginException catch (e) {
        // EXPECTED under `flutter test`.
        // Proves: (1) the Dart API binds, (2) method channel name is
        // `app.fuelet.flutter_cloud_kit`, (3) the call reached the platform
        // boundary. CloudKit reachability itself still needs a device run.
        expect(e.message, contains('getAccountStatus'));
      }
    });

    test('saveRecord argument shape (recordType + Map<String,String>)', () async {
      try {
        await cloudKit.saveRecord(
          scope: CloudKitDatabaseScope.private,
          recordType: _recordType,
          record: {
            'spike': 'ok',
            'timestamp': DateTime.now().toIso8601String(),
          },
          recordName: 'spike-record-1',
        );
        fail('Unexpected success under test harness.');
      } on MissingPluginException catch (e) {
        expect(e.message, contains('saveRecord'));
      }
    });

    test('getRecord by recordName', () async {
      try {
        await cloudKit.getRecord(
          scope: CloudKitDatabaseScope.private,
          recordName: 'spike-record-1',
        );
        fail('Unexpected success under test harness.');
      } on MissingPluginException catch (e) {
        expect(e.message, contains('getRecord'));
      }
    });

    test('getRecordsByType', () async {
      try {
        await cloudKit.getRecordsByType(
          scope: CloudKitDatabaseScope.private,
          recordType: _recordType,
        );
        fail('Unexpected success under test harness.');
      } on MissingPluginException catch (e) {
        expect(e.message, contains('getRecordsByType'));
      }
    });

    test('deleteRecord by recordName', () async {
      try {
        await cloudKit.deleteRecord(
          scope: CloudKitDatabaseScope.private,
          recordName: 'spike-record-1',
        );
        fail('Unexpected success under test harness.');
      } on MissingPluginException catch (e) {
        expect(e.message, contains('deleteRecord'));
      }
    });

    test('CloudKitDatabaseScope enum shape matches expectation', () {
      // Documented enum from lib/types/database_scope.dart.
      // NOTE: `public` and `shared` compile in Dart, but the native Swift
      // impl only handles `"private"` — public/shared will throw
      // "Cannot create a database for the provided scope" at runtime.
      // See darwin/Classes/util/FlutterInteropUtils.swift:52-64.
      expect(CloudKitDatabaseScope.values, hasLength(3));
      expect(CloudKitDatabaseScope.values.map((e) => e.name),
          containsAll(<String>['public', 'private', 'shared']));
    });

    test('CloudKitAccountStatus enum shape matches expectation', () {
      // Documented enum from lib/types/cloud_kit_account_status.dart.
      expect(
        CloudKitAccountStatus.values.map((e) => e.name).toSet(),
        {
          'couldNotDetermine',
          'available',
          'restricted',
          'noAccount',
          'temporarilyUnavailable',
          'unknown',
        },
      );
    });

    test('identifier validator rejects invalid record types', () {
      // The Dart layer calls `validateCloudKitIdentifier` before saveRecord
      // to avoid Objective-C fatal crashes on malformed identifiers.
      // See: flutter_cloud_kit.dart:15-21.
      expect(
        () => cloudKit.saveRecord(
          scope: CloudKitDatabaseScope.private,
          recordType: '1StartsWithDigit',
          record: {'k': 'v'},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
