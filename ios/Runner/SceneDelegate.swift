import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // SECURITY: a blur over the window while the app is inactive, so the
  // snapshot the system takes for the app switcher shows no seed words,
  // balance or address. The app runs under the scene lifecycle (the
  // UIApplicationSceneManifest in Info.plist), so these scene events are
  // the ones the system sends; the app delegate's resign and activate
  // callbacks are not called under it.
  //
  // ⛔ iOS CANNOT BLOCK A SCREENSHOT. There is no equivalent of Android's
  // FLAG_SECURE: an app can be notified one was taken, after the fact, and
  // nothing else. The app-switcher snapshot is the ONLY capture surface iOS
  // lets an app control, so that is all the owner's "allow screenshots"
  // setting governs here — and the Settings copy says so rather than
  // implying a protection the platform does not offer.
  private var blurEffectView: UIVisualEffectView?

  /// Whether the owner has allowed capture. Set from Dart (the capture
  /// channel, registered in AppDelegate). Starts protected: the frames right
  /// after a cold start are the ones most likely to be showing a balance.
  static var captureAllowed = false

  // Called before the system takes the snapshot.
  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard !SceneDelegate.captureAllowed else { return }
    guard let window = self.window ?? (scene as? UIWindowScene)?.keyWindow else { return }
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.tag = 0xB10E
    window.addSubview(blurView)
    blurEffectView = blurView
  }

  // Called when the app is active again: the blur comes off. Unconditional —
  // a blur added before the setting changed still has to be removed, or it
  // would sit over a live screen.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    blurEffectView?.removeFromSuperview()
    blurEffectView = nil
  }
}
