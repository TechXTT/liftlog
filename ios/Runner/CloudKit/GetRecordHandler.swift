// Handler for `getRecord` — issue #70 (S7.2), extended #71 (S7.3).
//
// Fetches a single record by name from the default container's private
// database. Uses `CKDatabase.fetch(withRecordID: completionHandler:)`.
// S7.3 adds optional `zoneName` on the args map — when absent/nil the
// fetch targets the default zone (S7.2 back-compat); when set, the
// record ID is scoped to `CKRecordZone.ID(zoneName: ..., ownerName:
// CKCurrentUserDefaultName)` via
// `CloudKitRecordCodec.recordID(forRecordName:zoneName:)`. Encodes the
// resulting `CKRecord` via `CloudKitRecordCodec` and returns it as a
// `[String: Any]` map to Flutter.
//
// Trust-rule notes:
// * Record-not-found → `nil` result (Dart-side null). Get-by-id
//   semantics: "not found" is a value, not an error. Only maps to nil
//   when the underlying CKError is `.unknownItem`; every other error
//   surfaces as `FlutterError`.
// * No silent fallback on encode failure — if `encodeRecord` throws,
//   that surfaces as `FlutterError(code: "CK_ENCODE_FAILED")`.

import CloudKit
import Flutter
import Foundation

public final class GetRecordHandler {

    public init() {}

    public func handle(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        // Arg extraction — `recordType` isn't strictly needed for the
        // CKDatabase.fetch call (record IDs disambiguate on CloudKit's
        // side), but we take it for API symmetry with saveRecord and
        // to ease future validation when zones land in S7.3.
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(
                code: "CK_BAD_ARGS",
                message: "getRecord arguments must be a Map",
                details: nil
            ))
            return
        }
        guard let recordName = args["recordName"] as? String else {
            result(FlutterError(
                code: "CK_BAD_ARGS",
                message: "getRecord arguments missing 'recordName' String",
                details: nil
            ))
            return
        }
        // `recordType` is read + validated for shape even though we
        // don't consume it in the fetch call — if Dart forgets to send
        // it the contract is broken.
        guard args["recordType"] is String else {
            result(FlutterError(
                code: "CK_BAD_ARGS",
                message: "getRecord arguments missing 'recordType' String",
                details: nil
            ))
            return
        }
        // S7.3: optional zoneName. Missing → default zone (back-compat
        // with S7.2 probe records). Present → scope the record ID to
        // the named custom zone under the current user.
        let zoneName = args["zoneName"] as? String

        let db = CKContainer.default().privateCloudDatabase
        let recordID = CloudKitRecordCodec.recordID(forRecordName: recordName, zoneName: zoneName)
        db.fetch(withRecordID: recordID) { record, error in
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                // Record-not-found — Dart sees this as `null`.
                result(nil)
                return
            }
            if let error = error {
                result(FlutterError(
                    code: "CK_GET_RECORD_FAILED",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
                return
            }
            guard let record = record else {
                // Belt-and-braces: CKDatabase.fetch shouldn't return
                // nil-nil, but surface it clearly if it does.
                result(FlutterError(
                    code: "CK_GET_RECORD_FAILED",
                    message: "CKDatabase.fetch returned nil record + nil error",
                    details: nil
                ))
                return
            }
            do {
                let encoded = try CloudKitRecordCodec.encodeRecord(record)
                result(encoded)
            } catch {
                result(FlutterError(
                    code: "CK_ENCODE_FAILED",
                    message: "failed to encode CKRecord for Dart",
                    details: String(describing: error)
                ))
            }
        }
    }
}
