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
// S7.1 shipped `getAccountStatus`. S7.2 (#70) added record CRUD in the
// default zone. S7.3 (#71, this change) introduces record zones:
// `ensureZoneExists(zoneName:)` + optional `zoneName` on save/get. When
// `zoneName` is null (back-compat with S7.2 probe records), the default
// zone is used; when set, records live in the named custom zone under
// `CKCurrentUserDefaultName`. Keep this file small and honest.

/// Canonical app zone name. All real app data (post-S7.3) lives here,
/// not the default zone. One zone keeps change-feed wiring cheap (S7.5
/// uses `CKFetchRecordZoneChangesOperation` per zone) and scopes
/// `deleteRecordZone` to a single blast-radius for account reset.
///
/// S7.2 shipped probe records into the default zone — those are
/// disposable orphans post-S7.3; see Runbooks.md for cleanup.
const String kLiftLogZoneName = 'LiftLogZone';

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
/// * Preserve type fidelity on record round-trips. Saving a [CKDouble]
///   and fetching it back must return a [CKDouble] with bit-identical
///   value (the spike showed the `Map<String, String>` fallback loses
///   precision — trust rule "no silent mutation of totals" forbids that
///   path; see S7.2 issue #70).
abstract class CloudKitSource {
  /// Asks the native side for the current `CKAccountStatus`.
  ///
  /// On iOS the underlying call is
  /// `CKContainer.default().accountStatus(completionHandler:)`. Returns
  /// one of the five [CloudKitAccountStatus] values; throws on any
  /// platform error or unrecognised raw value.
  Future<CloudKitAccountStatus> getAccountStatus();

  /// Creates the custom record zone named [zoneName] in the private
  /// database if it does not already exist. Idempotent — a second call
  /// for the same name is a no-op.
  ///
  /// On iOS the underlying call is `CKModifyRecordZonesOperation`
  /// against `CKContainer.default().privateCloudDatabase`. CloudKit
  /// treats the op as an upsert by zone ID, so creating an existing
  /// zone succeeds naturally (no special-case "already exists" mapping
  /// required). Any real failure (network, auth, entitlement) surfaces
  /// as [CloudKitChannelError].
  ///
  /// Zones are owned by the current user
  /// (`CKCurrentUserDefaultName`) — S7.3 does not support shared /
  /// public zones (explicit v2 non-goal; see CLAUDE.md).
  Future<void> ensureZoneExists({required String zoneName});

  /// Saves [record] to the private database.
  ///
  /// When [zoneName] is null, the record lands in the default zone —
  /// kept for back-compat with S7.2 probe records. Callers handling
  /// real app data should pass [kLiftLogZoneName] and ensure the zone
  /// exists first via [ensureZoneExists].
  ///
  /// On iOS the underlying call is
  /// `CKDatabase.save(_:completionHandler:)` on
  /// `CKContainer.default().privateCloudDatabase`. CKRecord.save
  /// overwrites by default — callers that need conflict detection wait
  /// for S7.4's batch modify operation.
  ///
  /// Errors surface as [CloudKitChannelError]; a `MissingPluginException`
  /// propagates unchanged. Never fire-and-forget: the returned Future
  /// completes only when the native side has acknowledged the save.
  Future<void> saveRecord(CloudKitRecord record, {String? zoneName});

  /// Fetches a single record by [recordType] + [recordName] from the
  /// private database.
  ///
  /// When [zoneName] is null, the fetch targets the default zone (S7.2
  /// back-compat). When set, the record ID is scoped to the named
  /// custom zone under `CKCurrentUserDefaultName`. A record saved in
  /// the default zone is NOT visible from a custom zone and vice
  /// versa — zone scoping is absolute.
  ///
  /// Returns `null` when CloudKit reports the record does not exist
  /// (native-side maps `CKError.unknownItem` to a null result). Any
  /// other error surfaces as [CloudKitChannelError].
  ///
  /// Type fidelity guarantee: every field in the returned record uses
  /// the same [CloudKitValue] subtype as the saved record — see the
  /// round-trip test in
  /// `test/sources/cloud_kit_source_test.dart`.
  Future<CloudKitRecord?> getRecord({
    required String recordType,
    required String recordName,
    String? zoneName,
  });
}

/// Pure-Dart description of a single CloudKit record.
///
/// Fields are keyed by String name and carry typed [CloudKitValue]
/// payloads — the codec at the channel boundary uses the value's runtime
/// type to pick the right `CKRecord` setter on the Swift side, and the
/// typeTag on the wire to reconstruct the right subtype on decode.
///
/// Equality is value-based so tests can assert round-trip equality
/// directly.
class CloudKitRecord {
  const CloudKitRecord({
    required this.recordType,
    required this.recordName,
    required this.fields,
  });

  /// CloudKit record type name (e.g. `"HealthSpike"`). Must match the
  /// type registered in the CloudKit container schema — on first save
  /// CloudKit auto-registers the type, but the developer still has to
  /// configure queryable / sortable indexes in the CloudKit Console if
  /// the record is ever queried. See Runbooks.md.
  final String recordType;

  /// CloudKit record name (unique within the record type + zone).
  /// Produced by the caller — CloudKit does not auto-generate.
  final String recordName;

  /// Field payload. Keys are field names (on Swift side, the CKRecord
  /// key). Values carry both the Dart type and the raw value.
  final Map<String, CloudKitValue> fields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CloudKitRecord) return false;
    if (other.recordType != recordType) return false;
    if (other.recordName != recordName) return false;
    if (other.fields.length != fields.length) return false;
    for (final entry in fields.entries) {
      if (other.fields[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    recordType,
    recordName,
    // Order-independent hash of the field map — CloudKit record fields
    // have no intrinsic order, and two records with the same fields in
    // different iteration orders should still compare equal.
    Object.hashAllUnordered(
      fields.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() =>
      'CloudKitRecord(recordType: $recordType, recordName: $recordName, fields: $fields)';
}

/// Sealed root for all value types that can cross the CloudKit channel.
///
/// Sealed so exhaustive switches are compiler-enforced — adding a new
/// subtype (asset / reference, post-S7.2) forces every consumer's switch
/// to grow a branch at compile time, matching the canonical-enum rule in
/// CLAUDE.md ("no fallthrough defaults").
///
/// Round-trip contract: every subtype preserves its underlying Dart
/// value bit-for-bit across the channel. `DateTime` values round-trip
/// through millisecond-since-epoch (UTC); sub-millisecond precision is
/// truncated by the wire protocol. Documented in
/// `method_channel_cloud_kit_source.dart` / `CloudKitRecordCodec.swift`.
sealed class CloudKitValue {
  const CloudKitValue();
}

/// String field value.
class CKString extends CloudKitValue {
  const CKString(this.value);
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CKString && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CKString($value)';
}

/// 64-bit signed integer field value. Preserves integer precision — the
/// Swift side uses `NSNumber(value: Int64)` so values up to 2^63-1
/// survive the round-trip without being coerced to `Double`.
class CKInt extends CloudKitValue {
  const CKInt(this.value);
  final int value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CKInt && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CKInt($value)';
}

/// 64-bit double-precision float field value. The Swift side uses
/// `NSNumber(value: Double)` so IEEE 754 bit-pattern is preserved.
class CKDouble extends CloudKitValue {
  const CKDouble(this.value);
  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CKDouble && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CKDouble($value)';
}

/// Boolean field value. Crosses the channel as an explicit `"bool"`
/// typeTag (rather than riding as an Int) so a future consumer that
/// grows e.g. a tri-state flag type doesn't collide with 0/1 ints.
class CKBool extends CloudKitValue {
  const CKBool(this.value);
  final bool value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CKBool && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'CKBool($value)';
}

/// DateTime field value.
///
/// Wire encoding: milliseconds-since-epoch as an `int`, tagged
/// `"dateTime"`. The Swift side converts to `NSDate` via
/// `Date(timeIntervalSince1970: ms / 1000.0)`. Round-trip precision is
/// milliseconds; Dart's sub-millisecond microsecond precision is
/// truncated at the wire boundary.
///
/// The underlying [DateTime] is preserved as-given — no implicit
/// UTC conversion. Callers that want UTC should pass a UTC `DateTime`;
/// callers that want local time should pass a local `DateTime`. The
/// codec carries the absolute instant (milliseconds since epoch) either
/// way, so the instant is preserved; only the `isUtc` flag may differ
/// on the return trip (Swift returns UTC, which Dart surfaces as a UTC
/// `DateTime`).
class CKDateTime extends CloudKitValue {
  const CKDateTime(this.value);
  final DateTime value;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CKDateTime) return false;
    // Equality on the absolute instant — matches the round-trip
    // contract. Two DateTimes that represent the same millisecond
    // instant compare equal even if one is local and one is UTC.
    return other.value.millisecondsSinceEpoch == value.millisecondsSinceEpoch;
  }

  @override
  int get hashCode => value.millisecondsSinceEpoch.hashCode;

  @override
  String toString() => 'CKDateTime($value)';
}
