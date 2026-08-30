// Generated from packages/design-tokens/tokens.json. Do not edit directly.

import SwiftUI
import UIKit

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
}

enum MTRadius {
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let large: CGFloat = 18
  static let xlarge: CGFloat = 24
  static let pill: CGFloat = 999
}

enum MTMotion {
  static let quick = Double(120) / 1_000
  static let standard = Double(180) / 1_000
  static let deliberate = Double(280) / 1_000
}

private extension Color {
  init(lightHex: String, darkHex: String) {
    self.init(
      uiColor: UIColor { traits in
        UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
      }
    )
  }
}

private extension UIColor {
  convenience init(hex: String) {
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
