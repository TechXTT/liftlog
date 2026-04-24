// `CloudKitSource` backed by a real platform `MethodChannel`. This is
// the only place in the app that opens the
// `dev.techxtt.liftlog/cloudkit` channel; feature code must never talk
// to the channel directly (arch rule — enforced).
//
// Trust-rule notes:
// * No silent fallback. If the native side returns an out-of-range raw
//   status, we throw [CloudKitUnknownError] rather than coercing to
//   `couldNotDetermine` (which is a meaningful CKAccountStatus in its
//   own right — Apple uses it for "the dialog hasn't finished yet").
// * `MissingPluginException` propagates unchanged. Callers decide what
//   to do (e.g. treat as "CloudKit not wired on this platform" without
//   mutating any persistent state).
// * `PlatformError` from the native side is re-typed as
//   [CloudKitChannelError] so feature code never imports
//   `package:flutter/services.dart` just to catch a platform error.
//
// Wire protocol (S7.2 / #70, extended S7.3 / #71) — MUST match
// `CloudKitRecordCodec.swift`:
//
//   ensureZoneExists (S7.3):
//     args    = { "zoneName": String }
//     returns: null on success; `FlutterError` on failure (re-raised as
//              [CloudKitChannelError]). Idempotent — creating an
//              existing zone succeeds naturally (CloudKit upserts by
//              zone ID).
//
//   saveRecord:
//     args = {
//       "recordType": String,
//       "recordName": String,
//       "zoneName":   String?  — S7.3: optional. When omitted/null,
//                                 Swift uses the default zone (back-compat
//                                 with S7.2 probe records). When set,
//                                 Swift uses
//                                 CKRecordZone.ID(zoneName: ...,
//                                   ownerName: CKCurrentUserDefaultName).
//       "fields": Map<String, List> where each value is
//                 a 2-element List<dynamic> of the form [typeTag, raw],
//                 typeTag ∈ {"string","int","double","bool","dateTime"},
//                 raw encoded as:
//                   "string"   → String
//                   "int"      → int (Int64 on Swift side)
//                   "double"   → double
//                   "bool"     → bool
//                   "dateTime" → int milliseconds-since-epoch (UTC),
//                                Swift decodes via
//                                Date(timeIntervalSince1970: ms/1000.0)
//     }
//     returns: null
//
//   getRecord:
//     args    = {
//       "recordType": String,
//       "recordName": String,
//       "zoneName":   String?  — same semantics as saveRecord.
//     }
//     returns: null if record does not exist (CKError.unknownItem);
//              otherwise Map with the same shape as saveRecord's args
//              (including "recordType" + "recordName" + "fields"). Note
//              that the returned map does NOT echo "zoneName"; the
//              caller already knows which zone it asked for.
//
// Unknown typeTag on decode → [CloudKitChannelError]. No fallback to
// String: the spike showed that lossy path is exactly the trust-rule
// violation S7.2 exists to prevent.

import 'package:flutter/services.dart';

import 'cloud_kit_source.dart';

/// Canonical channel name. Kept as a `const` so the name is identical on
/// both the test mock (`TestDefaultBinaryMessengerBinding`) and the real
/// bridge in `ios/Runner/CloudKit/CloudKitBridge.swift`.
///
/// Versioning note: if the channel contract ever changes
/// backward-incompatibly (e.g. a new enum value, a renamed method), bump
/// the name to `dev.techxtt.liftlog/cloudkit.v2` and update both sides
/// together. For the walking skeleton this is v1 implicit.
const String kCloudKitChannelName = 'dev.techxtt.liftlog/cloudkit';

/// Method name for the account-status handler. String literal lives here
/// and on the Swift side only — callers go through the façade.
const String _kGetAccountStatus = 'getAccountStatus';

/// Method name for `saveRecord`.
const String _kSaveRecord = 'saveRecord';

/// Method name for `getRecord`.
const String _kGetRecord = 'getRecord';

/// Method name for `ensureZoneExists` (S7.3).
const String _kEnsureZoneExists = 'ensureZoneExists';

// Wire typeTags. Mirrored on the Swift side in `CloudKitRecordCodec`.
const String _kTagString = 'string';
const String _kTagInt = 'int';
const String _kTagDouble = 'double';
const String _kTagBool = 'bool';
const String _kTagDateTime = 'dateTime';

class MethodChannelCloudKitSource implements CloudKitSource {
  /// Construct a source backed by the default channel name. Pass
  /// [channel] in tests to inject a mock-backed channel.
  MethodChannelCloudKitSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kCloudKitChannelName);

  final MethodChannel _channel;

  @override
  Future<CloudKitAccountStatus> getAccountStatus() async {
    // `invokeMethod<int>` returns `int?` — the native side sends an
    // `NSNumber` which Flutter decodes as `int`. A `null` return means
    // the handler did not respond with an `Int`; treat that as an
    // unknown status so we never fabricate a real value.
    final int? raw;
    try {
      raw = await _channel.invokeMethod<int>(_kGetAccountStatus);
    } on PlatformException catch (e) {
      // Re-type so feature code catches `CloudKitChannelError` without
      // importing `package:flutter/services.dart`.
      throw CloudKitChannelError(
        code: e.code,
        message: e.message ?? '',
        details: e.details,
      );
    }

    if (raw == null) {
      throw const CloudKitUnknownError(
        -1,
        'native handler returned null; expected Int',
      );
    }

    // Bounds-check before the `values[raw]` indexing — `List.operator[]`
    // throws a `RangeError` on out-of-range, but we'd rather surface a
    // typed `CloudKitUnknownError` so callers can match on it.
    if (raw < 0 || raw >= CloudKitAccountStatus.values.length) {
      throw CloudKitUnknownError(
        raw,
        'raw status outside known CKAccountStatus range (0..'
        '${CloudKitAccountStatus.values.length - 1})',
      );
    }
    return CloudKitAccountStatus.values[raw];
  }

  @override
  Future<void> ensureZoneExists({required String zoneName}) async {
    try {
      await _channel.invokeMethod<void>(_kEnsureZoneExists, <String, Object?>{
        'zoneName': zoneName,
      });
    } on PlatformException catch (e) {
      throw CloudKitChannelError(
        code: e.code,
        message: e.message ?? '',
        details: e.details,
      );
    }
  }

  @override
  Future<void> saveRecord(CloudKitRecord record, {String? zoneName}) async {
    final encodedFields = <String, List<Object?>>{};
    for (final entry in record.fields.entries) {
      encodedFields[entry.key] = _encodeValue(entry.value);
    }
    // Build the args map explicitly. When `zoneName` is null we omit
    // the key entirely rather than sending a `"zoneName": null` — the
    // Swift side reads it as `args["zoneName"] as? String` which
    // treats missing and null identically, but omitting keeps the wire
    // clean and matches the S7.2 back-compat contract.
    final args = <String, Object?>{
      'recordType': record.recordType,
      'recordName': record.recordName,
      'fields': encodedFields,
    };
    if (zoneName != null) {
      args['zoneName'] = zoneName;
    }
    try {
      await _channel.invokeMethod<void>(_kSaveRecord, args);
    } on PlatformException catch (e) {
      throw CloudKitChannelError(
        code: e.code,
        message: e.message ?? '',
        details: e.details,
      );
    }
  }

  @override
  Future<CloudKitRecord?> getRecord({
    required String recordType,
    required String recordName,
    String? zoneName,
  }) async {
    final args = <String, Object?>{
      'recordType': recordType,
      'recordName': recordName,
    };
    if (zoneName != null) {
      args['zoneName'] = zoneName;
    }
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>(_kGetRecord, args);
    } on PlatformException catch (e) {
      throw CloudKitChannelError(
        code: e.code,
        message: e.message ?? '',
        details: e.details,
      );
    }

    // Native side returns null for CKError.unknownItem — get-by-id
    // semantics: "not found" is a value, not an error.
    if (raw == null) return null;

    if (raw is! Map) {
      throw CloudKitChannelError(
        code: 'CK_MALFORMED_RESPONSE',
        message: 'getRecord expected Map response, got ${raw.runtimeType}',
        details: raw,
      );
    }
    return _decodeRecord(raw);
  }
}

/// Encodes a [CloudKitValue] as its 2-element `[typeTag, raw]` wire
/// form. Exhaustive switch over the sealed subtype hierarchy — the Dart
/// analyzer enforces that any future subtype must be handled here.
List<Object?> _encodeValue(CloudKitValue value) {
  return switch (value) {
    CKString(:final value) => <Object?>[_kTagString, value],
    CKInt(:final value) => <Object?>[_kTagInt, value],
    CKDouble(:final value) => <Object?>[_kTagDouble, value],
    CKBool(:final value) => <Object?>[_kTagBool, value],
    // Milliseconds-since-epoch. `millisecondsSinceEpoch` on a Dart
    // `DateTime` returns the absolute instant regardless of the
    // DateTime's `isUtc` flag — exactly what we want on the wire.
    CKDateTime(:final value) => <Object?>[
      _kTagDateTime,
      value.millisecondsSinceEpoch,
    ],
  };
}

/// Decodes a `[typeTag, raw]` wire entry back into a [CloudKitValue].
///
/// Unknown typeTag → [CloudKitChannelError]. No silent fallback to
/// String — the spike showed that's exactly the lossy trap we're here
/// to prevent.
CloudKitValue _decodeValue(String fieldName, Object? wire) {
  if (wire is! List || wire.length != 2) {
    throw CloudKitChannelError(
      code: 'CK_MALFORMED_FIELD',
      message:
          'field "$fieldName": expected 2-element [typeTag, value] list, '
          'got ${wire.runtimeType}',
      details: wire,
    );
  }
  final tag = wire[0];
  final raw = wire[1];
  if (tag is! String) {
    throw CloudKitChannelError(
      code: 'CK_MALFORMED_FIELD',
      message:
          'field "$fieldName": typeTag must be String, got ${tag.runtimeType}',
      details: wire,
    );
  }

  switch (tag) {
    case _kTagString:
      if (raw is! String) {
        throw CloudKitChannelError(
          code: 'CK_MALFORMED_FIELD',
          message:
              'field "$fieldName": typeTag "$tag" expected String value, '
              'got ${raw.runtimeType}',
          details: wire,
        );
      }
      return CKString(raw);
    case _kTagInt:
      if (raw is! int) {
        throw CloudKitChannelError(
          code: 'CK_MALFORMED_FIELD',
          message:
              'field "$fieldName": typeTag "$tag" expected int value, '
              'got ${raw.runtimeType}',
          details: wire,
        );
      }
      return CKInt(raw);
    case _kTagDouble:
      // Swift NSNumber(value: Double) arrives as `double` in the
      // standard codec. Guard to keep the codec honest.
      if (raw is! double) {
        throw CloudKitChannelError(
          code: 'CK_MALFORMED_FIELD',
          message:
              'field "$fieldName": typeTag "$tag" expected double value, '
              'got ${raw.runtimeType}',
          details: wire,
        );
      }
      return CKDouble(raw);
    case _kTagBool:
      if (raw is! bool) {
        throw CloudKitChannelError(
          code: 'CK_MALFORMED_FIELD',
          message:
              'field "$fieldName": typeTag "$tag" expected bool value, '
              'got ${raw.runtimeType}',
          details: wire,
        );
      }
      return CKBool(raw);
    case _kTagDateTime:
      if (raw is! int) {
        throw CloudKitChannelError(
          code: 'CK_MALFORMED_FIELD',
          message:
              'field "$fieldName": typeTag "$tag" expected int ms-since-epoch, '
              'got ${raw.runtimeType}',
          details: wire,
        );
      }
      // Swift sends UTC; surface as UTC on the Dart side. Callers that
      // want local time can `.toLocal()`.
      return CKDateTime(DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true));
    default:
      throw CloudKitChannelError(
        code: 'CK_UNKNOWN_TYPE_TAG',
        message:
            'field "$fieldName": unknown typeTag "$tag"; expected one of '
            '$_kTagString, $_kTagInt, $_kTagDouble, $_kTagBool, $_kTagDateTime',
        details: wire,
      );
  }
}

/// Decodes the top-level `getRecord` response map to [CloudKitRecord].
CloudKitRecord _decodeRecord(Map<Object?, Object?> raw) {
  final recordType = raw['recordType'];
  final recordName = raw['recordName'];
  final rawFields = raw['fields'];
  if (recordType is! String) {
    throw CloudKitChannelError(
      code: 'CK_MALFORMED_RESPONSE',
      message: 'getRecord response missing "recordType" String',
      details: raw,
    );
  }
  if (recordName is! String) {
    throw CloudKitChannelError(
      code: 'CK_MALFORMED_RESPONSE',
      message: 'getRecord response missing "recordName" String',
      details: raw,
    );
  }
  if (rawFields is! Map) {
    throw CloudKitChannelError(
      code: 'CK_MALFORMED_RESPONSE',
      message:
          'getRecord response "fields" must be a Map, got '
          '${rawFields.runtimeType}',
      details: raw,
    );
  }
  final fields = <String, CloudKitValue>{};
  for (final entry in rawFields.entries) {
    final key = entry.key;
    if (key is! String) {
      throw CloudKitChannelError(
        code: 'CK_MALFORMED_RESPONSE',
        message:
            'getRecord response field key must be String, got '
            '${key.runtimeType}',
        details: raw,
      );
    }
    fields[key] = _decodeValue(key, entry.value);
  }
  return CloudKitRecord(
    recordType: recordType,
    recordName: recordName,
    fields: fields,
  );
}
