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
  // The cover is keyed by its tag and handled idempotently. iOS can send
  // will-resign-active more than once before the next did-become-active (a
  // biometric prompt, the lock screen, Control Center over the app
  // switcher). A cover added twice and removed once stayed on the window as
  // a dark layer that swallowed every touch, which read as a black screen on
  // return until the app was relaunched. Every cover on every window of the
  // scene is removed on will-enter-foreground and on did-become-active.
  private static let coverTag = 0xB10E

  private func sceneWindows(_ scene: UIScene) -> [UIWindow] {
    var windows: [UIWindow] = []
    if let w = self.window { windows.append(w) }
    if let ws = scene as? UIWindowScene {
      for w in ws.windows where !windows.contains(w) { windows.append(w) }
    }
    return windows
  }

  private func addCover(_ scene: UIScene) {
    removeCover(scene)
    guard let window = self.window ?? (scene as? UIWindowScene)?.keyWindow else { return }
    let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    blurView.frame = window.bounds
    blurView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    blurView.tag = SceneDelegate.coverTag
    window.addSubview(blurView)
  }

  private func removeCover(_ scene: UIScene) {
    for window in sceneWindows(scene) {
      for view in window.subviews where view.tag == SceneDelegate.coverTag {
        view.removeFromSuperview()
      }
    }
  }

  // Called before the system takes the snapshot.
  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    addCover(scene)
  }

  // Called on the way back from the background, before the app is active.
  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    removeCover(scene)
  }

  // Called when the app is active again: the cover comes off.
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    removeCover(scene)
  }
}
