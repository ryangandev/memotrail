// Generated from packages/design-tokens/tokens.json. Do not edit directly.

import SwiftUI
import UIKit

struct MTColorToken: Sendable {
  let name: String
  let lightHex: String
  let darkHex: String
  let color: Color
}

enum MTColor {
  static let canvas = Color(lightHex: "#F4F1E9", darkHex: "#171816")
  static let surface = Color(lightHex: "#FBF9F3", darkHex: "#1E201D")
  static let surfaceRaised = Color(lightHex: "#FFFFFF", darkHex: "#262824")
  static let surfaceSubtle = Color(lightHex: "#ECE7DC", darkHex: "#2C2E29")
  static let ink = Color(lightHex: "#26251F", darkHex: "#EEEADF")
  static let inkMuted = Color(lightHex: "#716D63", darkHex: "#B4AFA3")
  static let inkFaint = Color(lightHex: "#9A9589", darkHex: "#817D74")
  static let border = Color(lightHex: "#DCD6C9", darkHex: "#393B35")
  static let borderStrong = Color(lightHex: "#C7BFAF", darkHex: "#4B4E46")
  static let accent = Color(lightHex: "#315E4F", darkHex: "#82AD98")
  static let accentHover = Color(lightHex: "#254A3E", darkHex: "#96BEAA")
  static let accentSubtle = Color(lightHex: "#DDE8E1", darkHex: "#273C33")
  static let accentInk = Color(lightHex: "#F8FBF9", darkHex: "#142019")
  static let warm = Color(lightHex: "#A76346", darkHex: "#D49373")
  static let warmSubtle = Color(lightHex: "#F1E2D8", darkHex: "#432E25")
  static let success = Color(lightHex: "#49705B", darkHex: "#82AD98")
  static let warning = Color(lightHex: "#9B6A2F", darkHex: "#D3A360")
  static let scrim = Color(lightHex: "#26251F", darkHex: "#000000")

  static let catalog = [
    MTColorToken(name: "canvas", lightHex: "#F4F1E9", darkHex: "#171816", color: canvas),
    MTColorToken(name: "surface", lightHex: "#FBF9F3", darkHex: "#1E201D", color: surface),
    MTColorToken(
      name: "surfaceRaised", lightHex: "#FFFFFF", darkHex: "#262824", color: surfaceRaised),
    MTColorToken(
      name: "surfaceSubtle", lightHex: "#ECE7DC", darkHex: "#2C2E29", color: surfaceSubtle),
    MTColorToken(name: "ink", lightHex: "#26251F", darkHex: "#EEEADF", color: ink),
    MTColorToken(name: "inkMuted", lightHex: "#716D63", darkHex: "#B4AFA3", color: inkMuted),
    MTColorToken(name: "inkFaint", lightHex: "#9A9589", darkHex: "#817D74", color: inkFaint),
    MTColorToken(name: "border", lightHex: "#DCD6C9", darkHex: "#393B35", color: border),
    MTColorToken(
      name: "borderStrong", lightHex: "#C7BFAF", darkHex: "#4B4E46", color: borderStrong),
    MTColorToken(name: "accent", lightHex: "#315E4F", darkHex: "#82AD98", color: accent),
    MTColorToken(name: "accentHover", lightHex: "#254A3E", darkHex: "#96BEAA", color: accentHover),
    MTColorToken(
      name: "accentSubtle", lightHex: "#DDE8E1", darkHex: "#273C33", color: accentSubtle),
    MTColorToken(name: "accentInk", lightHex: "#F8FBF9", darkHex: "#142019", color: accentInk),
    MTColorToken(name: "warm", lightHex: "#A76346", darkHex: "#D49373", color: warm),
    MTColorToken(name: "warmSubtle", lightHex: "#F1E2D8", darkHex: "#432E25", color: warmSubtle),
    MTColorToken(name: "success", lightHex: "#49705B", darkHex: "#82AD98", color: success),
    MTColorToken(name: "warning", lightHex: "#9B6A2F", darkHex: "#D3A360", color: warning),
    MTColorToken(name: "scrim", lightHex: "#26251F", darkHex: "#000000", color: scrim),
  ]
}

enum MTTypography {
  static let display = Font.system(size: 42, weight: .medium, design: .serif)
  static let title = Font.system(size: 28, weight: .medium, design: .serif)
  static let titleSmall = Font.system(size: 20, weight: .semibold)
  static let bodyLarge = Font.system(size: 17)
  static let body = Font.system(size: 15)
  static let label = Font.system(size: 13, weight: .medium)
  static let caption = Font.system(size: 12, weight: .medium)
}

enum MTSpacing {
  static let s1: CGFloat = 4
  static let s2: CGFloat = 8
  static let s3: CGFloat = 12
  static let s4: CGFloat = 16
  static let s5: CGFloat = 20
  static let s6: CGFloat = 24
  static let s8: CGFloat = 32
  static let s10: CGFloat = 40
  static let s12: CGFloat = 48
  static let s16: CGFloat = 64

  static let catalog: [(name: String, value: CGFloat)] = [
    ("1", s1),
    ("2", s2),
    ("3", s3),
    ("4", s4),
    ("5", s5),
    ("6", s6),
    ("8", s8),
    ("10", s10),
    ("12", s12),
    ("16", s16),
  ]
}

enum MTRadius {
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let large: CGFloat = 18
  static let xlarge: CGFloat = 24
  static let pill: CGFloat = 999

  static let catalog: [(name: String, value: CGFloat)] = [
    ("small", small),
    ("medium", medium),
    ("large", large),
    ("xlarge", xlarge),
    ("pill", pill),
  ]
}

enum MTMotion {
  static let quick = Double(120) / 1_000
  static let standard = Double(180) / 1_000
  static let deliberate = Double(280) / 1_000

  static let catalog: [(name: String, seconds: Double)] = [
    ("quick", quick),
    ("standard", standard),
    ("deliberate", deliberate),
  ]
}

enum MTLineHeight {
  static let tight: CGFloat = 1.15
  static let body: CGFloat = 1.55
  static let relaxed: CGFloat = 1.7
}

struct MTShadowLayer: Sendable {
  let color: Color
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat

  init(
    red: Double, green: Double, blue: Double, opacity: Double, radius: CGFloat, x: CGFloat,
    y: CGFloat
  ) {
    color = Color(red: red / 255, green: green / 255, blue: blue / 255).opacity(opacity)
    self.radius = radius
    self.x = x
    self.y = y
  }
}

struct MTShadowToken: Sendable {
  let name: String
  let css: String
  let layers: [MTShadowLayer]
}

// CSS blur is twice the equivalent SwiftUI shadow radius.
enum MTShadow {
  static let raised = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.06, radius: 1, x: 0, y: 1),
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.06, radius: 14, x: 0, y: 8),
  ]
  static let floating = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.14, radius: 24, x: 0, y: 16)
  ]

  static let catalog = [
    MTShadowToken(
      name: "raised", css: "0 1px 2px rgb(38 37 31 / 0.06), 0 8px 28px rgb(38 37 31 / 0.06)",
      layers: raised),
    MTShadowToken(name: "floating", css: "0 16px 48px rgb(38 37 31 / 0.14)", layers: floating),
  ]
}

extension Color {
  fileprivate init(lightHex: String, darkHex: String) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
      }
    )
  }
}

extension UIColor {
  fileprivate convenience init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}
