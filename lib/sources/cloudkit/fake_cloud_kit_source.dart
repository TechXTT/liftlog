// Test-only fake for the [CloudKitSource] façade.
//
// Injected via Riverpod provider override in unit / widget tests so
// nothing in the test tree opens the `dev.techxtt.liftlog/cloudkit`
// platform channel. Lives under `lib/sources/` (not `test/`) so that
// future production overrides can also import it when running in a
// simulator-without-CloudKit context — but those production overrides
// must be gated explicitly; nothing does that today.

import 'cloud_kit_source.dart';

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

  /// In-memory record store keyed by `(recordType, recordName)`. Keeps
  /// type-by-type namespacing honest — two records with the same name
  /// but different types don't collide (mirrors CKRecord.ID semantics).
  final Map<String, CloudKitRecord> _store = {};

  String _key(String recordType, String recordName) =>
      '$recordType\u0000$recordName';

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
  Future<void> saveRecord(CloudKitRecord record) async {
    saveRecordCallCount += 1;
    if (_error != null) throw _error;
    // Upsert — matches the real CloudKit default `save` semantics
    // (S7.2 scope: no conflict detection, S7.4 adds batch + policy).
    _store[_key(record.recordType, record.recordName)] = record;
  }

  @override
  Future<CloudKitRecord?> getRecord({
    required String recordType,
    required String recordName,
  }) async {
    getRecordCallCount += 1;
    if (_error != null) throw _error;
    return _store[_key(recordType, recordName)];
  }
}
