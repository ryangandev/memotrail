// Renders the iOS app icon PNGs in the asset catalog from the brand SVGs in assets/brand.
//
//     swift apps/ios/scripts/render-app-icon.swift
//
// Rerun it after changing assets/brand/memotrail-app-icon-*.svg.
// The light and dark icons are opaque without an alpha channel, as App Store validation requires.
// The tinted icon keeps its transparent field because iOS tints it by brightness over its own
// backdrop, and an opaque field would become a solid tile that hides the white ring.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(filePath: #filePath)
  .deletingLastPathComponent()
  .appending(path: "../../..")
  .standardizedFileURL
let brand = root.appending(path: "assets/brand")
let iconSet = root.appending(
  path: "apps/ios/MemoTrail/Resources/Assets.xcassets/AppIcon.appiconset")

func render(_ source: String, to output: String, opaque: Bool) throws {
  let svg = brand.appending(path: source)
  guard let image = NSImage(contentsOf: svg) else {
    throw RenderError("could not read \(svg.path)")
  }

  // Draw in sRGB, the space the SVG colors are defined in, so solid fills keep their exact values.
  let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast
  guard
    let space = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
      data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
      space: space, bitmapInfo: alpha.rawValue
    )
  else { throw RenderError("could not create a bitmap for \(output)") }

  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
  NSGraphicsContext.current = nil

  let url = iconSet.appending(path: output)
  guard
    let bitmap = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { throw RenderError("could not encode \(output)") }
  CGImageDestinationAddImage(destination, bitmap, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw RenderError("could not write \(url.path)")
  }
  print("wrote \(output) from \(source)")
}

struct RenderError: Error, CustomStringConvertible {
  let description: String
  init(_ description: String) { self.description = description }
}

try render("memotrail-app-icon-light.svg", to: "AppIcon.png", opaque: true)
try render("memotrail-app-icon-dark.svg", to: "AppIcon-Dark.png", opaque: true)
try render("memotrail-app-icon-tinted.svg", to: "AppIcon-Tinted.png", opaque: false)
