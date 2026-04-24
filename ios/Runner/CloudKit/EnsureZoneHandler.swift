// Handler for `ensureZoneExists` — issue #71 (S7.3).
//
// Creates the named `CKRecordZone` in the default container's private
// database if it does not already exist. Wraps
// `CKModifyRecordZonesOperation` with `modifyRecordZonesResultBlock`
// (iOS 16+). Apple's server upserts zones by zoneID, so modifying with
// an already-existing zone naturally succeeds — this is inherently
// idempotent, no "already exists" special case required.
//
// Trust-rule notes:
// * No silent fallback. If the operation errors, surface a typed
//   `FlutterError` so the Dart side re-raises as
//   `CloudKitChannelError`. The Dart callers treat zone creation as a
//   precondition for any write into a custom zone — a failure must
//   halt the flow, not "try anyway".
// * `qualityOfService = .userInitiated`: zone creation is blocking for
//   the UI flow that depends on it (first-run sync bootstrap); we
//   don't want background-priority starvation.
// * Single-user, private DB only (S7.3 scope — CLAUDE.md: no
//   multi-user shared zones in v2.0). Zone owner is
//   `CKCurrentUserDefaultName`.

import CloudKit
import Flutter
import Foundation

public final class EnsureZoneHandler {

    public init() {}

    public func handle(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(
                code: "CK_BAD_ARGS",
                message: "ensureZoneExists arguments must be a Map",
                details: nil
            ))
            return
        }
        guard let zoneName = args["zoneName"] as? String else {
            result(FlutterError(
                code: "CK_BAD_ARGS",
                message: "ensureZoneExists arguments missing 'zoneName' String",
                details: nil
            ))
            return
        }

        let zoneID = CKRecordZone.ID(
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName
        )
        let zone = CKRecordZone(zoneID: zoneID)

        let op = CKModifyRecordZonesOperation(
            recordZonesToSave: [zone],
            recordZoneIDsToDelete: nil
        )
        op.qualityOfService = .userInitiated
        // `modifyRecordZonesResultBlock` is the iOS 16+ completion API.
        // We surface success as Flutter `null`; any error surfaces as
        // `FlutterError(code: "CK_ENSURE_ZONE_FAILED")`.
        op.modifyRecordZonesResultBlock = { opResult in
            switch opResult {
            case .success:
                result(nil)
            case .failure(let error):
                result(FlutterError(
                    code: "CK_ENSURE_ZONE_FAILED",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
            }
        }

        CKContainer.default().privateCloudDatabase.add(op)
    }
}
