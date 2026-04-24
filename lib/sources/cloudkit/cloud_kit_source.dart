// Façade for the custom CloudKit MethodChannel (issue #69, S7.1).
//
// This file is the public boundary of `lib/sources/cloudkit/`. Feature
// code is only ever allowed to import from this file — the arch guardrail
// in `test/arch/data_access_boundary_test.dart` enforces that via the
// `<name>_source.dart` naming convention.
//
// Trust-rule notes:
// * Pure Dart. No `MethodChannel` / `package:flutter` leak here — the
//   implementation file `method_channel_cloud_kit_source.dart` owns the
//   channel plumbing.
// * No silent fallback. Errors surface as typed Dart exceptions
//   ([CloudKitChannelError] / [CloudKitUnknownError]) or propagate as
//   `MissingPluginException` when the native side isn't registered.
//   Callers must decide what to do with a missing channel — we never
//   fabricate an account status.
// * Index-based enum wire protocol. The Swift side sends the raw
//   `CKAccountStatus` integer (0..4); we map it to [CloudKitAccountStatus]
//   by index with an explicit bounds check. See the enum docstring for
//   the ordering contract (it is load-bearing — Apple's order, not Dart's
//   declaration-order whim).
//
// This is the walking skeleton. S7.2 (#70) adds record CRUD; S7.3 (#71)
// adds zones. Keep this file small and honest.

/// CloudKit account status, mirroring Apple's `CKAccountStatus`.
///
/// Ordering is load-bearing: the native side sends the raw Apple integer
/// (0..4) across the channel; we map by index. Do NOT reorder the
/// declarations without a matching change to the Swift mapping + a
/// channel-version bump.
///
/// Apple mapping (as of iOS 16+):
///   couldNotDetermine        = 0 — HealthKit-style "we don't know yet"
///   available                = 1 — signed into iCloud and CloudKit is usable
///   restricted               = 2 — parental / MDM restrictions
///   noAccount                = 3 — no iCloud account on the device
///   temporarilyUnavailable   = 4 — transient (e.g. reauth required)
///
/// Canonical-enum rule applies: every renderer / switch over this enum
/// must enumerate all five cases. No `default` branches (see CLAUDE.md).
enum CloudKitAccountStatus {
  couldNotDetermine,
  available,
  restricted,
  noAccount,
  temporarilyUnavailable,
}

/// Raised when the CloudKit channel returns an integer outside the
/// known `CKAccountStatus` index range (0..4).
///
/// We never silently coerce to `couldNotDetermine` — that would be a
/// silent fallback masquerading as a known state. Surface loudly.
class CloudKitUnknownError implements Exception {
  const CloudKitUnknownError(this.rawStatus, [this.message]);

  /// The raw integer the native side sent. Preserved so the caller can
  /// log it and decide whether to retry, surface a diagnostic, etc.
  final int rawStatus;

  /// Optional explanatory message.
  final String? message;

  @override
  String toString() {
    final suffix = message == null ? '' : ': $message';
    return 'CloudKitUnknownError(rawStatus: $rawStatus)$suffix';
  }
}

/// Raised when the CloudKit channel surfaces a typed platform error
/// (`FlutterError` on the native side). Preserves Apple's error code +
/// message so callers can log or match.
class CloudKitChannelError implements Exception {
  const CloudKitChannelError({
    required this.code,
    required this.message,
    this.details,
  });

  /// Native-side error code (e.g. `"CK_ACCOUNT_STATUS_FAILED"`).
  final String code;

  /// Human-readable message from the native handler.
  final String message;

  /// Opaque details payload — typically the `NSError.localizedDescription`
  /// or the underlying `CKError` code. Pass-through; not parsed here.
  final Object? details;

  @override
  String toString() =>
      'CloudKitChannelError(code: $code, message: $message, details: $details)';
}

/// Pure-Dart façade for the CloudKit source.
///
/// The only production implementation today
/// (`MethodChannelCloudKitSource`) binds the
/// `dev.techxtt.liftlog/cloudkit` method channel. Tests inject
/// [FakeCloudKitSource] via the Riverpod provider override.
///
/// Implementations must:
/// * Surface errors on the returned Future — no silent fallback.
/// * Propagate `MissingPluginException` unchanged when the native side
///   isn't registered (e.g. running on an unsupported platform or before
///   the bridge registers on first launch). Callers decide whether to
///   degrade.
/// * Never fabricate an account status — an out-of-range raw value
///   throws [CloudKitUnknownError].
abstract class CloudKitSource {
  /// Asks the native side for the current `CKAccountStatus`.
  ///
  /// On iOS the underlying call is
  /// `CKContainer.default().accountStatus(completionHandler:)`. Returns
  /// one of the five [CloudKitAccountStatus] values; throws on any
  /// platform error or unrecognised raw value.
  Future<CloudKitAccountStatus> getAccountStatus();
}
