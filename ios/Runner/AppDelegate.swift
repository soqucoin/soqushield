import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // The capture channel, matching Android's. On iOS the only capture
    // surface an app can control is the app-switcher snapshot — there is no
    // way to block a screenshot — so "allow" here governs the blur in
    // SceneDelegate and nothing more.
    // applicationRegistrar is the documented route to the engine's binary
    // messenger for an APPLICATION-level channel (as opposed to a plugin's).
    let channel = FlutterMethodChannel(
      name: "org.soqu.soqushield/capture",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setAllowed":
        let args = call.arguments as? [String: Any]
        SceneDelegate.captureAllowed = (args?["allow"] as? Bool) ?? false
        result(true)
      case "allowCapture":
        // Android lifts FLAG_SECURE for store screenshots on a debuggable
        // build. iOS never blocked screenshots, so there is nothing to lift.
        result(false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // The app-switcher blur lives in SceneDelegate: under the scene lifecycle
  // the app delegate's resign and activate callbacks are never called.
}
