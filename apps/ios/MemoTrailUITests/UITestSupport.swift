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

  /// Scrolls until the whole element sits clear of the screen's top and bottom bars, or, when
  /// it is taller than that, until its top does. For checks that read its pixels.
  @MainActor @discardableResult
  func revealWhole(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
    let visible = clearArea(of: app)
    // Each drag moves at most 300 points, and long gallery sections at accessibility text sizes
    // put some elements more than 20 drags down.
    for _ in 0..<48 {
      let frame = element.frame
      // How far the content should move up; negative moves it down.
      let distance: CGFloat
      if !element.exists {
        distance = 300
      } else if frame.height > visible.height {
        guard abs(frame.minY - visible.minY - 24) > 24 else { break }
        distance = frame.minY - visible.minY - 24
      } else if frame.maxY > visible.maxY {
        distance = frame.maxY - visible.maxY + 24
      } else if frame.minY < visible.minY {
        distance = frame.minY - visible.minY - 24
      } else {
        break
      }
      let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      center.press(
        forDuration: 0.05,
        thenDragTo: center.withOffset(CGVector(dx: 0, dy: -max(-300, min(300, distance)))))
    }
    var frame = element.frame
    for _ in 0..<10 {
      Thread.sleep(forTimeInterval: 0.15)
      guard element.frame != frame else { break }
      frame = element.frame
    }
    return element
  }

  /// The part of the screen that no header, tab bar, or home indicator covers.
  @MainActor
  func clearArea(of app: XCUIApplication) -> CGRect {
    let screen = app.frame
    return CGRect(
      x: screen.minX, y: screen.minY + 120, width: screen.width, height: screen.height - 220)
  }

  @MainActor
  func attach(_ app: XCUIApplication, _ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}

extension XCTestCase {
  /// Asserts a dot-separated row as it is drawn: every line starts at the row's leading edge,
  /// nothing is drawn after a line's last item, and a separator shows between two facts (static
  /// texts) on one line. Returns the lines, each as its items' labels, to check that it wraps.
  @MainActor @discardableResult
  func assertSeparatorsBetweenFacts(
    _ row: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath,
    line: UInt = #line
  ) -> [[String]] {
    // Read the row on both sides of the screenshot, so the pixels match a settled layout.
    var items = rowItems(row)
    var screenshot = app.screenshot()
    for _ in 0..<10 {
      let settled = rowItems(row)
      if settled == items { break }
      Thread.sleep(forTimeInterval: 0.3)
      items = rowItems(row)
      screenshot = app.screenshot()
    }
    let pixels = ScreenshotPixels(screenshot, screen: app.frame)
    var lines: [[RowItem]] = []
    for item in items.sorted(by: { $0.frame.midY < $1.frame.midY }) {
      if let first = lines.last?.first, item.frame.midY > first.frame.minY,
        item.frame.midY < first.frame.maxY
      {
        lines[lines.count - 1].append(item)
      } else {
        lines.append([item])
      }
    }
    lines = lines.map { $0.sorted { $0.frame.minX < $1.frame.minX } }
    let rendered = lines.map { $0.map(\.label) }
    let context = "\(row.label): \(rendered)"
    XCTAssertFalse(lines.isEmpty, context, file: file, line: line)
    let visible = clearArea(of: app)
    var drawn = 0
    for items in lines {
      let top = items.map(\.frame.minY).min() ?? 0
      let bottom = items.map(\.frame.maxY).max() ?? 0
      XCTAssertNotEqual(
        items.first?.label, "·", "A line starts with a separator. \(context)", file: file,
        line: line)
      XCTAssertNotEqual(
        items.last?.label, "·", "A line ends with a separator. \(context)", file: file,
        line: line)
      // A separator before the first item would push it off the leading edge.
      XCTAssertEqual(
        items[0].frame.minX, row.frame.minX, accuracy: 1, "A line starts late. \(context)",
        file: file, line: line)
      // Only a line in clear view can be read from the screenshot.
      guard top >= visible.minY, bottom <= visible.maxY else { continue }
      drawn += 1
      if let last = items.last, row.frame.maxX - last.frame.maxX > 4 {
        let after = CGRect(
          x: last.frame.maxX + 1, y: top, width: row.frame.maxX - last.frame.maxX - 2,
          height: bottom - top)
        XCTAssertFalse(
          pixels.inks(after), "Something is drawn after \(last.label). \(context)", file: file,
          line: line)
      }
      for (before, next) in zip(items, items.dropFirst())
      where before.type == .staticText && next.type == .staticText && before.label != "·"
        && next.label != "·"
      {
        let gap = CGRect(
          x: before.frame.maxX + 1, y: top, width: next.frame.minX - before.frame.maxX - 2,
          height: bottom - top)
        XCTAssertTrue(
          pixels.inks(gap), "No separator between \(before.label) and \(next.label). \(context)",
          file: file, line: line)
      }
    }
    XCTAssertGreaterThan(drawn, 0, "No line is in clear view. \(context)", file: file, line: line)
    return rendered
  }

  @MainActor
  private func rowItems(_ row: XCUIElement) -> [RowItem] {
    let candidates = row.descendants(matching: .any).allElementsBoundByIndex
      .filter { [.staticText, .button, .activityIndicator].contains($0.elementType) }
      .map { RowItem(label: $0.label, type: $0.elementType, frame: $0.frame) }
      .filter { !$0.frame.isEmpty }
    // A button can expose its title as a nested text; keep only the outermost items.
    return candidates.filter { item in
      !candidates.contains { $0.frame != item.frame && $0.frame.contains(item.frame) }
    }
  }
}

private struct RowItem: Equatable {
  let label: String
  let type: XCUIElement.ElementType
  let frame: CGRect
}

/// A screenshot's pixels, addressed in screen points.
private struct ScreenshotPixels {
  private var bytes: [UInt8]
  private let width: Int
  private let height: Int
  private let scale: CGFloat

  @MainActor
  init(_ screenshot: XCUIScreenshot, screen: CGRect) {
    let image = screenshot.image.cgImage!
    width = image.width
    height = image.height
    scale = CGFloat(image.width) / screen.width
    bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
      let context = CGContext(
        data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
  }

  /// Whether anything is drawn in `rect`: its pixels vary by more than a flat fill does.
  func inks(_ rect: CGRect) -> Bool {
    let minX = max(0, Int((rect.minX * scale).rounded(.up)))
    let maxX = min(width, Int((rect.maxX * scale).rounded(.down)))
    let minY = max(0, Int((rect.minY * scale).rounded(.up)))
    let maxY = min(height, Int((rect.maxY * scale).rounded(.down)))
    guard minX < maxX, minY < maxY else { return false }
    var low: [UInt8] = [255, 255, 255]
    var high: [UInt8] = [0, 0, 0]
    for y in minY..<maxY {
      for x in minX..<maxX {
        let offset = (y * width + x) * 4
        for channel in 0..<3 {
          low[channel] = min(low[channel], bytes[offset + channel])
          high[channel] = max(high[channel], bytes[offset + channel])
        }
      }
    }
    return (0..<3).contains { high[$0] - low[$0] > 24 }
  }
}
