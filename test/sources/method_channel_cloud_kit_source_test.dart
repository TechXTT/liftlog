// Unit tests for `MethodChannelCloudKitSource` (issue #69, S7.1).
//
// Uses `TestDefaultBinaryMessengerBinding` to stub the native side so
// nothing in the test tree opens the real `dev.techxtt.liftlog/cloudkit`
// channel. Verifies:
// * the channel name matches the Swift-side constant
// * the method name is `getAccountStatus`
// * every `CKAccountStatus` index (0..4) decodes to the correct enum
// * out-of-range int throws `CloudKitUnknownError`
// * a thrown `PlatformException` is re-raised as `CloudKitChannelError`
// * a null return throws `CloudKitUnknownError` (no silent fabrication)

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liftlog_app/sources/cloudkit/cloud_kit_source.dart';
import 'package:liftlog_app/sources/cloudkit/method_channel_cloud_kit_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(kCloudKitChannelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Register a mock handler on the canonical channel. Records the last
  /// invoked method name so each test can verify the wire contract.
  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      return handler(call);
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('channel contract', () {
    test('uses the canonical channel name', () {
      expect(kCloudKitChannelName, 'dev.techxtt.liftlog/cloudkit');
    });

    test('invokes "getAccountStatus" method', () async {
      String? observedMethod;
      mockChannel((call) async {
        observedMethod = call.method;
        return 1;
      });
      final source = MethodChannelCloudKitSource();
      await source.getAccountStatus();
      expect(observedMethod, 'getAccountStatus');
    });
  });

  group('getAccountStatus — index decoding', () {
    // Apple's raw ordering: couldNotDetermine=0, available=1,
    // restricted=2, noAccount=3, temporarilyUnavailable=4. The table
    // below pins both the wire protocol and the Dart enum decl order.
    const wireTable = <int, CloudKitAccountStatus>{
      0: CloudKitAccountStatus.couldNotDetermine,
      1: CloudKitAccountStatus.available,
      2: CloudKitAccountStatus.restricted,
      3: CloudKitAccountStatus.noAccount,
      4: CloudKitAccountStatus.temporarilyUnavailable,
    };

    for (final entry in wireTable.entries) {
      test('raw ${entry.key} → ${entry.value.name}', () async {
        mockChannel((_) async => entry.key);
        final source = MethodChannelCloudKitSource();
        expect(await source.getAccountStatus(), entry.value);
      });
    }

    test('throws CloudKitUnknownError on out-of-range high int', () async {
      mockChannel((_) async => 99);
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () => source.getAccountStatus(),
        throwsA(
          isA<CloudKitUnknownError>().having(
            (e) => e.rawStatus,
            'rawStatus',
            99,
          ),
        ),
      );
    });

    test('throws CloudKitUnknownError on negative int', () async {
      mockChannel((_) async => -1);
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () => source.getAccountStatus(),
        throwsA(
          isA<CloudKitUnknownError>().having(
            (e) => e.rawStatus,
            'rawStatus',
            -1,
          ),
        ),
      );
    });

    test(
      'throws CloudKitUnknownError on null return (no silent fabrication)',
      () async {
        mockChannel((_) async => null);
        final source = MethodChannelCloudKitSource();
        await expectLater(
          () => source.getAccountStatus(),
          throwsA(isA<CloudKitUnknownError>()),
        );
      },
    );
  });

  group('getAccountStatus — error surfacing', () {
    test('PlatformException → CloudKitChannelError', () async {
      mockChannel((_) async {
        throw PlatformException(
          code: 'CK_ACCOUNT_STATUS_FAILED',
          message: 'native failure',
          details: 'underlying-nserror',
        );
      });
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () => source.getAccountStatus(),
        throwsA(
          isA<CloudKitChannelError>()
              .having((e) => e.code, 'code', 'CK_ACCOUNT_STATUS_FAILED')
              .having((e) => e.message, 'message', 'native failure')
              .having((e) => e.details, 'details', 'underlying-nserror'),
        ),
      );
    });

    test('MissingPluginException propagates unchanged', () async {
      // No mock handler → Flutter surfaces MissingPluginException. Trust
      // rule: don't fabricate a status; let the caller decide.
      messenger.setMockMethodCallHandler(channel, null);
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () => source.getAccountStatus(),
        throwsA(isA<MissingPluginException>()),
      );
    });
  });
}
