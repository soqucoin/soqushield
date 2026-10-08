import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // SECURITY: Blur overlay to hide sensitive wallet content in iOS app switcher.
  // Prevents seed phrases, balances, and addresses from being visible when the
  // user switches apps. The overlay uses UIBlurEffect which is iOS-native and
  // hardware-accelerated.
  private var blurEffectView: UIVisualEffectView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Called when app is about to move from active to inactive (e.g., incoming call,
  // app switcher, or home button). Apply blur BEFORE the system takes the snapshot.
  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    guard let window = self.window else { return }
    let blurEffect = UIBlurEffect(style: .dark)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = window.bounds
    blurView.tag = 0xB10E // Unique tag to find and remove later
    window.addSubview(blurView)
    self.blurEffectView = blurView
  }

  // Called when app returns to active. Remove the blur overlay.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    blurEffectView?.removeFromSuperview()
    blurEffectView = nil
  }
}
