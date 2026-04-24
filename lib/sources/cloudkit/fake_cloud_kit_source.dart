// Test-only fake for the [CloudKitSource] façade.
//
// Injected via Riverpod provider override in unit / widget tests so
// nothing in the test tree opens the `dev.techxtt.liftlog/cloudkit`
// platform channel. Lives under `lib/sources/` (not `test/`) so that
// future production overrides can also import it when running in a
// simulator-without-CloudKit context — but those production overrides
// must be gated explicitly; nothing does that today.

import 'cloud_kit_source.dart';

/// Sentinel zone-key for records saved with `zoneName == null` (i.e.
/// the default zone). Can't be a real CloudKit zone name — Apple's
/// default zone name is the literal `"_defaultZone"`, but we want a
/// marker the test tree can't accidentally collide with when it
/// constructs a custom zone. Zero-byte prefix is safe: CKRecordZone
/// names are alphanumeric + `-` + `_`; a NUL char is illegal.
const String _kFakeDefaultZoneKey = '\u0000__default__';

/// Stubbed [CloudKitSource] that returns whatever was handed to it.
///
/// Ctor takes the initial [CloudKitAccountStatus] the fake will report
/// from [getAccountStatus]. Call-counting accessor is provided for tests
/// that care about "was the native side consulted?" without wiring a
/// full mock framework.
class FakeCloudKitSource implements CloudKitSource {
  FakeCloudKitSource({
    CloudKitAccountStatus initialStatus =
        CloudKitAccountStatus.couldNotDetermine,
    Object? error,
  }) : _status = initialStatus,
       _error = error;

  CloudKitAccountStatus _status;
  final Object? _error;

  /// How many times [getAccountStatus] has been invoked on this fake.
  /// Useful for "did the controller re-poll?" tests.
  int getAccountStatusCallCount = 0;

  /// How many times [saveRecord] has been invoked.
  int saveRecordCallCount = 0;

  /// How many times [getRecord] has been invoked.
  int getRecordCallCount = 0;

  /// How many times [ensureZoneExists] has been invoked.
  int ensureZoneExistsCallCount = 0;

  /// In-memory record store keyed by `(zoneKey, recordType, recordName)`.
  /// `zoneKey` is [_kFakeDefaultZoneKey] for null (default zone) or the
  /// zoneName string for a custom zone. Records in different zones do
  /// not collide — mirrors `CKRecord.ID(zoneID:)` semantics on the real
  /// CloudKit side. Before S7.3 this was two-part (type + name) only.
  final Map<String, CloudKitRecord> _store = {};

  /// Zones created via [ensureZoneExists]. Tracked so tests can assert
  /// idempotency. Real CloudKit state survives process restart; this
  /// fake only tracks within the current object lifetime, which is
  /// fine because tests always instantiate a fresh fake.
  final Set<String> _zones = {};

  String _key(String? zoneName, String recordType, String recordName) {
    final zoneKey = zoneName ?? _kFakeDefaultZoneKey;
    return '$zoneKey\u0000$recordType\u0000$recordName';
  }

  /// Exposes the set of created zones for test assertions. Returns an
  /// unmodifiable view so callers can't mutate internal state.
  Set<String> get createdZones => Set.unmodifiable(_zones);

  /// Swap the account status the fake will return on subsequent calls.
  /// Not called by production code — test-only seam.
  // ignore: use_setters_to_change_properties
  void setStatus(CloudKitAccountStatus next) => _status = next;

  @override
  Future<CloudKitAccountStatus> getAccountStatus() async {
    getAccountStatusCallCount += 1;
    if (_error != null) throw _error;
    return _status;
  }

  @override
  Future<void> ensureZoneExists({required String zoneName}) async {
    ensureZoneExistsCallCount += 1;
    if (_error != null) throw _error;
    // Idempotent — a second call for the same name is a no-op. Matches
    // CloudKit's `CKModifyRecordZonesOperation` upsert semantics.
    _zones.add(zoneName);
  }

  @override
  Future<void> saveRecord(CloudKitRecord record, {String? zoneName}) async {
    saveRecordCallCount += 1;
    if (_error != null) throw _error;
    // Upsert — matches the real CloudKit default `save` semantics
    // (S7.2 scope: no conflict detection, S7.4 adds batch + policy).
    _store[_key(zoneName, record.recordType, record.recordName)] = record;
  }

  @override
  Future<CloudKitRecord?> getRecord({
    required String recordType,
    required String recordName,
    String? zoneName,
  }) async {
    getRecordCallCount += 1;
    if (_error != null) throw _error;
    return _store[_key(zoneName, recordType, recordName)];
  }
}
