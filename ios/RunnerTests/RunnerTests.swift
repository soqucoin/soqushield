import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  // The app-switcher blur is installed by the scene's resign-active event and
  // removed by its become-active event, on the scene's window. The scene
  // lifecycle is the one in force (Info.plist names SceneDelegate), so a
  // blur installed from the app delegate's callbacks would never appear.
  func testSceneResignActiveCoversTheWindowAndBecomeActiveUncoversIt() throws {
    let scene = try XCTUnwrap(
      UIApplication.shared.connectedScenes.first as? UIWindowScene,
      "the app runs in a window scene")
    let delegate = try XCTUnwrap(scene.delegate as? SceneDelegate,
      "the scene's delegate is the app's SceneDelegate")
    let window = try XCTUnwrap(delegate.window ?? scene.keyWindow,
      "the scene has a window")
    XCTAssertNil(window.viewWithTag(0xB10E), "no blur while active")

    delegate.sceneWillResignActive(scene)
    let blur = try XCTUnwrap(window.viewWithTag(0xB10E) as? UIVisualEffectView,
      "the blur is on the window before the snapshot")
    XCTAssertEqual(blur.frame, window.bounds, "the blur covers the window")
    XCTAssertTrue(window.subviews.last === blur, "the blur is on top")

    delegate.sceneDidBecomeActive(scene)
    XCTAssertNil(window.viewWithTag(0xB10E), "the blur is gone once active")
  }
}
