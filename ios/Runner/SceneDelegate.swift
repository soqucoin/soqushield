import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  // SECURITY: a blur over the window while the app is inactive, so the
  // snapshot the system takes for the app switcher shows no seed words,
  // balance or address. The app runs under the scene lifecycle (the
  // UIApplicationSceneManifest in Info.plist), so these scene events are
  // the ones the system sends; the app delegate's resign and activate
  // callbacks are not called under it.
  private var blurEffectView: UIVisualEffectView?

  // Called before the system takes the snapshot.
  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window = self.window ?? (scene as? UIWindowScene)?.keyWindow else { return }
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.tag = 0xB10E
    window.addSubview(blurView)
    blurEffectView = blurView
  }

  // Called when the app is active again: the blur comes off.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    blurEffectView?.removeFromSuperview()
    blurEffectView = nil
  }
}
