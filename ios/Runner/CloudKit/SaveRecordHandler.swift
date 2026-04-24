// Handler for `saveRecord` — issue #70 (S7.2), extended #71 (S7.3).
//
// Wraps `CKDatabase.save(_:completionHandler:)` on the default
// container's private database. S7.3 adds optional `zoneName` on the
// args map — decoded by `CloudKitRecordCodec` and baked into the
// `CKRecord.ID` at construction time. When `zoneName` is absent/nil
// the record lands in the default zone (S7.2 back-compat); when set,
// the record targets `CKRecordZone.ID(zoneName: ..., ownerName:
// CKCurrentUserDefaultName)`. On completion, signals success via a
// Flutter `null` result; on failure, surfaces a typed `FlutterError`
// the Dart side re-raises as `CloudKitChannelError`.
//
// Trust-rule notes:
// * No silent fallback: if `CKDatabase.save` fails, the Dart side sees
//   a failure. Callers never observe a fire-and-forget save.
// * `CKDatabase.save` overwrites by default (no change-tag check) —
//   that's the S7.2 design. Conflict detection lands in Sprint 8 via
//   `CKModifyRecordsOperation` with `.ifServerRecordUnchanged`.

import CloudKit
import Flutter
import Foundation

public final class SaveRecordHandler {

    public init() {}

    public func handle(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        let record: CKRecord
        do {
            record = try CloudKitRecordCodec.decodeRecord(from: arguments)
        } catch {
            result(FlutterError(
                code: "CK_ENCODE_FAILED",
                message: "failed to decode CloudKitRecord from Dart args",
                details: String(describing: error)
            ))
            return
        }

        let db = CKContainer.default().privateCloudDatabase
        db.save(record) { _, error in
            if let error = error {
                result(FlutterError(
                    code: "CK_SAVE_RECORD_FAILED",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
                return
            }
            // Success — Dart-side `saveRecord` returns `Future<void>`.
            result(nil)
        }
    }
}
