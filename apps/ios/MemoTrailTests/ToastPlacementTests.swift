import XCTest

@testable import MemoTrail

@MainActor
final class ToastPlacementTests: XCTestCase {
  func testToastsSitAboveTheHomeIndicatorOrTheKeyboardWithRoomForActions() {
    // Without a keyboard, toasts clear the home indicator, the tab bar, and a sheet's actions.
    XCTAssertEqual(
      MTToastCenter.bottomInset(windowMaxY: 874, safeAreaBottom: 34, keyboardTop: nil), 110)
    // A software keyboard lifts them above its top edge.
    XCTAssertEqual(
      MTToastCenter.bottomInset(windowMaxY: 874, safeAreaBottom: 34, keyboardTop: 538), 412)
    // A hardware keyboard's shortcut bar is lower than the home indicator's inset.
    XCTAssertEqual(
      MTToastCenter.bottomInset(windowMaxY: 874, safeAreaBottom: 34, keyboardTop: 855), 110)
    // A keyboard reported below the window, as it slides away, does not move them.
    XCTAssertEqual(
      MTToastCenter.bottomInset(windowMaxY: 874, safeAreaBottom: 34, keyboardTop: 1_210), 110)
  }
}
