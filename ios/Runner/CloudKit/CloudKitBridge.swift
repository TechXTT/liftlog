// CloudKit MethodChannel bridge — issue #69 (S7.1 walking skeleton).
//
// Binds `FlutterMethodChannel("dev.techxtt.liftlog/cloudkit")` against
// the Flutter engine attached to the root `FlutterViewController` and
// dispatches incoming method calls to dedicated handlers.
//
// Scope discipline: this file owns ONLY the dispatch. Each method has a
// tiny handler file (e.g. `CloudKitAccountStatusHandler.swift`) that
// wraps the corresponding CloudKit call and surfaces errors as
// `FlutterError`. Adding a new method is: (a) drop a new handler file,
// (b) add one case to the `switch` below, (c) extend the Dart façade.
//
// Trust-rule notes mirroring `cloud_kit_source.dart`:
// * No silent fallback. Errors surface as `FlutterError` with a typed
//   code string the Dart side can match.
// * S7.1 shipped `getAccountStatus`; S7.2 (this file) adds
//   `saveRecord` + `getRecord` for the typed-record round-trip. Zones
//   remain S7.3 (#71).

import Flutter
import Foundation

/// Canonical channel name. Must match `kCloudKitChannelName` in
/// `lib/sources/cloudkit/method_channel_cloud_kit_source.dart`.
public let CloudKitChannelName = "dev.techxtt.liftlog/cloudkit"

/// Owns the CloudKit `FlutterMethodChannel`. Instantiated from
/// `AppDelegate.application(_:didFinishLaunchingWithOptions:)` after the
/// root Flutter engine is available (see `AppDelegate.swift`).
public final class CloudKitBridge {

    /// Strong reference to the channel so it stays alive for the life of
    /// the app. `FlutterMethodChannel` does not retain its owner, and
    /// releasing this instance would silently drop incoming Dart calls.
    private let channel: FlutterMethodChannel

    /// Handlers — one per method name. Kept as lets so each is lazily
    /// final and the dispatch switch stays tiny.
    private let accountStatusHandler = CloudKitAccountStatusHandler()
    private let saveRecordHandler = SaveRecordHandler()
    private let getRecordHandler = GetRecordHandler()

    /// Binds the CloudKit channel against [binaryMessenger]. Typically
    /// the root `FlutterViewController`'s messenger.
    public init(binaryMessenger: FlutterBinaryMessenger) {
        self.channel = FlutterMethodChannel(
            name: CloudKitChannelName,
            binaryMessenger: binaryMessenger
        )
        // `weak self` — channel retains the closure; we don't want a
        // retain cycle back through the bridge.
        self.channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(
                    code: "CK_BRIDGE_DEALLOCATED",
                    message: "CloudKitBridge was released before call dispatch",
                    details: nil
                ))
                return
            }
            self.handle(call: call, result: result)
        }
    }

    // MARK: - Dispatch

    /// Dispatches `call.method` to the matching handler. Unknown methods
    /// return `FlutterMethodNotImplemented` — Flutter's standard idiom
    /// for "this channel doesn't know that name." Do NOT add a `default`
    /// that silently succeeds.
    private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getAccountStatus":
            accountStatusHandler.handle(arguments: call.arguments, result: result)
        case "saveRecord":
            saveRecordHandler.handle(arguments: call.arguments, result: result)
        case "getRecord":
            getRecordHandler.handle(arguments: call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
