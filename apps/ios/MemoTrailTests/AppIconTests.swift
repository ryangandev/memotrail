import ImageIO
import XCTest

/// `apps/ios/scripts/render-app-icon.swift` writes these icons from the brand SVGs.
/// An export with the wrong alpha layout fails App Store validation or flattens the tinted icon.
final class AppIconTests: XCTestCase {
  private static let size = 1024
  private static let iconSet = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appending(path: "MemoTrail/Resources/Assets.xcassets/AppIcon.appiconset")

  func testLightAndDarkIconsAreOpaqueWithoutAnAlphaChannel() throws {
    for name in ["AppIcon.png", "AppIcon-Dark.png"] {
      let image = try Self.icon(name)
      XCTAssertTrue(
        [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo),
        "\(name) has an alpha channel; run apps/ios/scripts/render-app-icon.swift")
    }
  }

  func testTintedIconIsGrayscaleArtOnATransparentField() throws {
    // iOS tints by brightness, so an opaque field becomes a solid tile that hides the white ring.
    let pixels = try Self.premultipliedRGBA(Self.icon("AppIcon-Tinted.png"))
    let last = Self.size - 1
    for (x, y) in [(0, 0), (last, 0), (0, last), (last, last)] {
      XCTAssertEqual(
        pixels[(y * Self.size + x) * 4 + 3], 0,
        "AppIcon-Tinted.png is opaque at (\(x), \(y)); run apps/ios/scripts/render-app-icon.swift")
    }
    let tintedPixels = stride(from: 0, to: pixels.count, by: 4).filter {
      pixels[$0] != pixels[$0 + 1] || pixels[$0] != pixels[$0 + 2]
    }
    XCTAssertEqual(tintedPixels.count, 0, "AppIcon-Tinted.png must be grayscale")
  }

  private static func icon(_ name: String) throws -> CGImage {
    let url = iconSet.appending(path: name)
    let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), "missing \(name)")
    let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    XCTAssertEqual(image.width, size, name)
    XCTAssertEqual(image.height, size, name)
    return image
  }

  /// Decodes into sRGB, the space the brand SVGs define their colors in.
  private static func premultipliedRGBA(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try XCTUnwrap(
        CGContext(
          data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
          bytesPerRow: size * 4, space: space,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return pixels
  }
}
