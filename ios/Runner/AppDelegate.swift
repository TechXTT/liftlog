import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// CloudKit bridge (issue #69, S7.1 walking skeleton). Kept as a
  /// property so the `FlutterMethodChannel` it owns stays alive for
  /// the life of the app — the channel does not retain its bridge,
  /// so a local would deallocate and silently drop incoming calls.
  private var cloudKitBridge: CloudKitBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register the CloudKit method-channel bridge on the same binary
    // messenger the generated plugins use. Doing it here (rather than
    // inside `didFinishLaunchingWithOptions`) ensures the implicit
    // Flutter engine is fully initialized — matches the existing
    // GeneratedPluginRegistrant registration pattern in this app.
    if let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "CloudKitBridge")?
      .messenger()
    {
      cloudKitBridge = CloudKitBridge(binaryMessenger: messenger)
    }
  }
}
