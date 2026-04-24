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
}
