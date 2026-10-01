import XCTest

extension XCTestCase {
  // Scrolls the current screen until the element can receive taps, independent of text size.
  // `footer` names a sticky bar the content scrolls under, which `isHittable` does not notice.
  @MainActor @discardableResult
  func reveal(
    _ element: XCUIElement, in app: XCUIApplication, above footer: XCUIElement? = nil
  ) -> XCUIElement {
    func isClear() -> Bool {
      guard element.exists, element.isHittable else { return false }
      guard let footer, footer.exists else { return true }
      return element.frame.maxY < footer.frame.minY
    }
    // Long gallery sections at accessibility text sizes can take many screens to reach.
    for _ in 0..<24 where !isClear() { app.swipeUp() }
    // Let scroll momentum settle, or the next tap only stops the scroll.
    var frame = element.frame
    for _ in 0..<10 {
      Thread.sleep(forTimeInterval: 0.15)
      guard element.frame != frame else { break }
      frame = element.frame
    }
    return element
  }

  @MainActor
  func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
