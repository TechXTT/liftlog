// Handler for `getAccountStatus` — issue #69 (S7.1 walking skeleton).
//
// Wraps `CKContainer.default().accountStatus(completionHandler:)` and
// sends the raw `CKAccountStatus.rawValue` (Int) back across the Flutter
// channel. The Dart side (`method_channel_cloud_kit_source.dart`) maps
// the index into `CloudKitAccountStatus`; any mapping logic stays on the
// Dart side so Swift can remain a thin passthrough.
//
// Trust-rule notes:
// * No silent fallback. Any `Error` surfaces as `FlutterError` with a
//   typed code the Dart side re-raises as `CloudKitChannelError`.
// * `CKAccountStatus` indices are Apple's; they match the Dart enum's
//   declaration order. If Apple ever inserts a new value, the
//   out-of-range bounds check on the Dart side catches it as
//   `CloudKitUnknownError`.

import CloudKit
import Flutter
import Foundation

/// Handles one method: `getAccountStatus`. Stateless — safe to reuse
/// across calls; instantiated once on the bridge.
public final class CloudKitAccountStatusHandler {

    public init() {}

    /// Dispatched by `CloudKitBridge` on `getAccountStatus`. Ignores
    /// `arguments` — the walking skeleton call takes none.
    public func handle(
        arguments: Any?,
        result: @escaping FlutterResult
    ) {
        // `CKContainer.default()` returns the app's default container
        // based on the `com.apple.developer.icloud-container-identifiers`
        // entitlement. On a build without the entitlement, CloudKit
        // will surface an error through `completionHandler` — we pass
        // that through unchanged.
        CKContainer.default().accountStatus { status, error in
            if let error = error {
                // Surface the NSError on the Flutter side as a typed
                // channel error. The Dart side re-raises it as
                // `CloudKitChannelError`.
                result(FlutterError(
                    code: "CK_ACCOUNT_STATUS_FAILED",
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
                return
            }
            // `CKAccountStatus.rawValue` is an `Int`. Passed across the
            // channel as a NSNumber → Dart `int`. The Dart side does
            // the index → enum mapping with an out-of-range guard.
            result(status.rawValue)
        }
    }
}
