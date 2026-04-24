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

  group('saveRecord — wire encoding', () {
    test('encodes one field of each of the 5 supported types', () async {
      MethodCall? observed;
      mockChannel((call) async {
        observed = call;
        return null;
      });
      final source = MethodChannelCloudKitSource();
      final when = DateTime.utc(2026, 4, 24, 18, 30, 45, 789);
      final record = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {
          'title': const CKString('evening session'),
          'reps': const CKInt(12),
          'weightKg': const CKDouble(102.5),
          'wasPr': const CKBool(true),
          'when': CKDateTime(when),
        },
      );

      await source.saveRecord(record);

      expect(observed, isNotNull);
      expect(observed!.method, 'saveRecord');
      final args = observed!.arguments as Map;
      expect(args['recordType'], 'HealthSpike');
      expect(args['recordName'], 'spike-1');
      final fields = args['fields'] as Map;

      expect(fields['title'], equals(['string', 'evening session']));
      expect(fields['reps'], equals(['int', 12]));
      expect(fields['weightKg'], equals(['double', 102.5]));
      expect(fields['wasPr'], equals(['bool', true]));
      expect(fields['when'], equals(['dateTime', when.millisecondsSinceEpoch]));
    });

    test('PlatformException on save → CloudKitChannelError', () async {
      mockChannel((_) async {
        throw PlatformException(
          code: 'CK_SAVE_RECORD_FAILED',
          message: 'network unavailable',
          details: 'nserror-details',
        );
      });
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () => source.saveRecord(
          const CloudKitRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
            fields: {'v': CKInt(1)},
          ),
        ),
        throwsA(
          isA<CloudKitChannelError>().having(
            (e) => e.code,
            'code',
            'CK_SAVE_RECORD_FAILED',
          ),
        ),
      );
    });
  });

  group('getRecord — wire decoding', () {
    test('decodes each typeTag to the correct CloudKitValue subtype', () async {
      final whenMs = DateTime.utc(
        2026,
        4,
        24,
        18,
        30,
        45,
        789,
      ).millisecondsSinceEpoch;
      mockChannel((call) async {
        expect(call.method, 'getRecord');
        final args = call.arguments as Map;
        expect(args['recordType'], 'HealthSpike');
        expect(args['recordName'], 'spike-1');
        return <String, Object?>{
          'recordType': 'HealthSpike',
          'recordName': 'spike-1',
          'fields': <String, Object?>{
            'title': <Object?>['string', 'evening session'],
            'reps': <Object?>['int', 12],
            'weightKg': <Object?>['double', 102.5],
            'wasPr': <Object?>['bool', true],
            'when': <Object?>['dateTime', whenMs],
          },
        };
      });

      final source = MethodChannelCloudKitSource();
      final fetched = await source.getRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
      );

      expect(fetched, isNotNull);
      expect(fetched!.recordType, 'HealthSpike');
      expect(fetched.recordName, 'spike-1');
      expect(fetched.fields['title'], const CKString('evening session'));
      expect(fetched.fields['reps'], const CKInt(12));
      expect(fetched.fields['weightKg'], const CKDouble(102.5));
      expect(fetched.fields['wasPr'], const CKBool(true));
      expect(
        (fetched.fields['when']! as CKDateTime).value.millisecondsSinceEpoch,
        whenMs,
      );
      // The decoded DateTime surfaces as UTC — Swift side sends UTC.
      expect((fetched.fields['when']! as CKDateTime).value.isUtc, isTrue);
    });

    test(
      'null channel response → null record (get-by-id "not found")',
      () async {
        mockChannel((_) async => null);
        final source = MethodChannelCloudKitSource();
        final fetched = await source.getRecord(
          recordType: 'HealthSpike',
          recordName: 'missing',
        );
        expect(fetched, isNull);
      },
    );

    test(
      'unknown typeTag → CloudKitChannelError (no silent fallback)',
      () async {
        mockChannel(
          (_) async => <String, Object?>{
            'recordType': 'HealthSpike',
            'recordName': 'spike-1',
            'fields': <String, Object?>{
              'weird': <Object?>['asset', 'file://whatever'],
            },
          },
        );
        final source = MethodChannelCloudKitSource();
        await expectLater(
          () => source.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
          ),
          throwsA(
            isA<CloudKitChannelError>().having(
              (e) => e.code,
              'code',
              'CK_UNKNOWN_TYPE_TAG',
            ),
          ),
        );
      },
    );

    test(
      'malformed field (not a 2-element list) → CloudKitChannelError',
      () async {
        mockChannel(
          (_) async => <String, Object?>{
            'recordType': 'HealthSpike',
            'recordName': 'spike-1',
            'fields': <String, Object?>{'bad': 'just-a-string'},
          },
        );
        final source = MethodChannelCloudKitSource();
        await expectLater(
          () => source.getRecord(
            recordType: 'HealthSpike',
            recordName: 'spike-1',
          ),
          throwsA(
            isA<CloudKitChannelError>().having(
              (e) => e.code,
              'code',
              'CK_MALFORMED_FIELD',
            ),
          ),
        );
      },
    );

    test('type mismatch for declared tag → CloudKitChannelError', () async {
      // Tag says "int" but value is a Double. No silent coercion.
      mockChannel(
        (_) async => <String, Object?>{
          'recordType': 'HealthSpike',
          'recordName': 'spike-1',
          'fields': <String, Object?>{
            'reps': <Object?>['int', 3.14],
          },
        },
      );
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () =>
            source.getRecord(recordType: 'HealthSpike', recordName: 'spike-1'),
        throwsA(
          isA<CloudKitChannelError>().having(
            (e) => e.code,
            'code',
            'CK_MALFORMED_FIELD',
          ),
        ),
      );
    });

    test('response not a Map → CloudKitChannelError', () async {
      mockChannel((_) async => 'definitely-not-a-map');
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () =>
            source.getRecord(recordType: 'HealthSpike', recordName: 'spike-1'),
        throwsA(
          isA<CloudKitChannelError>().having(
            (e) => e.code,
            'code',
            'CK_MALFORMED_RESPONSE',
          ),
        ),
      );
    });

    test('PlatformException on get → CloudKitChannelError', () async {
      mockChannel((_) async {
        throw PlatformException(
          code: 'CK_GET_RECORD_FAILED',
          message: 'boom',
          details: 'nserror-details',
        );
      });
      final source = MethodChannelCloudKitSource();
      await expectLater(
        () =>
            source.getRecord(recordType: 'HealthSpike', recordName: 'spike-1'),
        throwsA(
          isA<CloudKitChannelError>().having(
            (e) => e.code,
            'code',
            'CK_GET_RECORD_FAILED',
          ),
        ),
      );
    });
  });

  group('round-trip through encode → decode on the same channel', () {
    test('every value type survives an encode → decode cycle', () async {
      // Capture the Dart-side encoded payload, then synthesize a
      // plausible Swift-side response with the same field shape and
      // assert decode → original record. This proves the Dart encoder
      // and Dart decoder agree on the wire contract — the Swift side
      // is covered by the separate device-verification step.
      late Map<String, Object?> savedArgs;
      mockChannel((call) async {
        if (call.method == 'saveRecord') {
          savedArgs = Map<String, Object?>.from(call.arguments as Map);
          return null;
        }
        if (call.method == 'getRecord') {
          // Synthesize the Swift-side response from the save args.
          return <String, Object?>{
            'recordType': savedArgs['recordType'],
            'recordName': savedArgs['recordName'],
            'fields': savedArgs['fields'],
          };
        }
        return null;
      });

      final source = MethodChannelCloudKitSource();
      final original = CloudKitRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
        fields: {
          's': const CKString('hello'),
          'i': const CKInt(9007199254740992),
          'd': const CKDouble(3.141592653589793),
          'b': const CKBool(false),
          't': CKDateTime(DateTime.utc(2026, 4, 24, 12, 34, 56, 789)),
        },
      );

      await source.saveRecord(original);
      final fetched = await source.getRecord(
        recordType: 'HealthSpike',
        recordName: 'spike-1',
      );

      expect(fetched, equals(original));
    });
  });
}
