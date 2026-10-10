// Generated from packages/design-system. Do not edit directly.

import SwiftUI
import UIKit

struct MTColorToken: Sendable {
  let name: String
  let lightHex: String
  let darkHex: String
  var lightOpacity = 1.0
  var darkOpacity = 1.0
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
  static let danger = Color(lightHex: "#A76346", darkHex: "#D49373")
  static let dangerSubtle = Color(lightHex: "#F1E2D8", darkHex: "#432E25")
  static let dangerBorder = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.34, darkOpacity: 0.34)
  static let dangerTint = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.1, darkOpacity: 0.1)
  static let info = Color(lightHex: "#315E4F", darkHex: "#82AD98")
  static let infoSubtle = Color(lightHex: "#DDE8E1", darkHex: "#273C33")
  static let successSubtle = Color(lightHex: "#DDE8E1", darkHex: "#273C33")
  static let warningSubtle = Color(lightHex: "#F1E2D8", darkHex: "#432E25")
  static let warningBorder = Color(
    lightHex: "#9B6A2F", darkHex: "#D3A360", lightOpacity: 0.35, darkOpacity: 0.35)
  static let inverseSurface = Color(
    lightHex: "#181814", darkHex: "#181814", lightOpacity: 0.72, darkOpacity: 0.72)
  static let inverseInk = Color(lightHex: "#FFFFFF", darkHex: "#FFFFFF")
  static let accentWash = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.07, darkOpacity: 0.07)
  static let accentTint = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.1, darkOpacity: 0.1)
  static let accentBorderFaint = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.15, darkOpacity: 0.15)
  static let accentBorder = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.34, darkOpacity: 0.34)
  static let accentBorderStrong = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.42, darkOpacity: 0.42)
  static let accentStripe = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.62, darkOpacity: 0.62)
  static let accentHalo = Color(
    lightHex: "#DDE8E1", darkHex: "#273C33", lightOpacity: 0.55, darkOpacity: 0.55)
  static let accentNotice = Color(
    lightHex: "#DDE8E1", darkHex: "#273C33", lightOpacity: 0.42, darkOpacity: 0.42)
  static let accentPanel = Color(lightHex: "#EEF2EB", darkHex: "#222C26")
  static let accentPanelBorder = Color(lightHex: "#9BA89B", darkHex: "#55665B")
  static let warmNotice = Color(
    lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.42, darkOpacity: 0.42)
  static let warmGlow = Color(
    lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.78, darkOpacity: 0.78)
  static let warmGlowFade = Color(
    lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0, darkOpacity: 0)
  static let warmWash = Color(
    lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.65, darkOpacity: 0.65)
  static let captureQueued = Color(lightHex: "#F4F5EF", darkHex: "#202722")
  static let captureRefused = Color(
    lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.32, darkOpacity: 0.32)
  static let chipSurface = Color(lightHex: "#FCFBF6", darkHex: "#20221F")
  static let laneSurface = Color(lightHex: "#FDFEFD", darkHex: "#262925")
  static let surfaceWash = Color(
    lightHex: "#ECE7DC", darkHex: "#2C2E29", lightOpacity: 0.42, darkOpacity: 0.42)
  static let surfaceRaisedTranslucent = Color(
    lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.94, darkOpacity: 0.94)
  static let skeletonHighlight = Color(
    lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.72, darkOpacity: 0.72)
  static let borderFaint = Color(
    lightHex: "#DCD6C9", darkHex: "#393B35", lightOpacity: 0.7, darkOpacity: 0.7)
  static let inkUnderline = Color(
    lightHex: "#26251F", darkHex: "#EEEADF", lightOpacity: 0.7, darkOpacity: 0.7)
  static let scrimFaint = Color(
    lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.12, darkOpacity: 0.12)
  static let scrimMedium = Color(
    lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.34, darkOpacity: 0.34)
  static let scrimStrong = Color(
    lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.48, darkOpacity: 0.48)

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
    MTColorToken(name: "danger", lightHex: "#A76346", darkHex: "#D49373", color: danger),
    MTColorToken(
      name: "dangerSubtle", lightHex: "#F1E2D8", darkHex: "#432E25", color: dangerSubtle),
    MTColorToken(
      name: "dangerBorder", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.34,
      darkOpacity: 0.34, color: dangerBorder),
    MTColorToken(
      name: "dangerTint", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.1,
      darkOpacity: 0.1, color: dangerTint),
    MTColorToken(name: "info", lightHex: "#315E4F", darkHex: "#82AD98", color: info),
    MTColorToken(name: "infoSubtle", lightHex: "#DDE8E1", darkHex: "#273C33", color: infoSubtle),
    MTColorToken(
      name: "successSubtle", lightHex: "#DDE8E1", darkHex: "#273C33", color: successSubtle),
    MTColorToken(
      name: "warningSubtle", lightHex: "#F1E2D8", darkHex: "#432E25", color: warningSubtle),
    MTColorToken(
      name: "warningBorder", lightHex: "#9B6A2F", darkHex: "#D3A360", lightOpacity: 0.35,
      darkOpacity: 0.35, color: warningBorder),
    MTColorToken(
      name: "inverseSurface", lightHex: "#181814", darkHex: "#181814", lightOpacity: 0.72,
      darkOpacity: 0.72, color: inverseSurface),
    MTColorToken(name: "inverseInk", lightHex: "#FFFFFF", darkHex: "#FFFFFF", color: inverseInk),
    MTColorToken(
      name: "accentWash", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.07,
      darkOpacity: 0.07, color: accentWash),
    MTColorToken(
      name: "accentTint", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.1,
      darkOpacity: 0.1, color: accentTint),
    MTColorToken(
      name: "accentBorderFaint", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.15,
      darkOpacity: 0.15, color: accentBorderFaint),
    MTColorToken(
      name: "accentBorder", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.34,
      darkOpacity: 0.34, color: accentBorder),
    MTColorToken(
      name: "accentBorderStrong", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.42,
      darkOpacity: 0.42, color: accentBorderStrong),
    MTColorToken(
      name: "accentStripe", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.62,
      darkOpacity: 0.62, color: accentStripe),
    MTColorToken(
      name: "accentHalo", lightHex: "#DDE8E1", darkHex: "#273C33", lightOpacity: 0.55,
      darkOpacity: 0.55, color: accentHalo),
    MTColorToken(
      name: "accentNotice", lightHex: "#DDE8E1", darkHex: "#273C33", lightOpacity: 0.42,
      darkOpacity: 0.42, color: accentNotice),
    MTColorToken(name: "accentPanel", lightHex: "#EEF2EB", darkHex: "#222C26", color: accentPanel),
    MTColorToken(
      name: "accentPanelBorder", lightHex: "#9BA89B", darkHex: "#55665B", color: accentPanelBorder),
    MTColorToken(
      name: "warmNotice", lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.42,
      darkOpacity: 0.42, color: warmNotice),
    MTColorToken(
      name: "warmGlow", lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.78,
      darkOpacity: 0.78, color: warmGlow),
    MTColorToken(
      name: "warmGlowFade", lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0,
      darkOpacity: 0, color: warmGlowFade),
    MTColorToken(
      name: "warmWash", lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.65,
      darkOpacity: 0.65, color: warmWash),
    MTColorToken(
      name: "captureQueued", lightHex: "#F4F5EF", darkHex: "#202722", color: captureQueued),
    MTColorToken(
      name: "captureRefused", lightHex: "#F1E2D8", darkHex: "#432E25", lightOpacity: 0.32,
      darkOpacity: 0.32, color: captureRefused),
    MTColorToken(name: "chipSurface", lightHex: "#FCFBF6", darkHex: "#20221F", color: chipSurface),
    MTColorToken(name: "laneSurface", lightHex: "#FDFEFD", darkHex: "#262925", color: laneSurface),
    MTColorToken(
      name: "surfaceWash", lightHex: "#ECE7DC", darkHex: "#2C2E29", lightOpacity: 0.42,
      darkOpacity: 0.42, color: surfaceWash),
    MTColorToken(
      name: "surfaceRaisedTranslucent", lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.94,
      darkOpacity: 0.94, color: surfaceRaisedTranslucent),
    MTColorToken(
      name: "skeletonHighlight", lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.72,
      darkOpacity: 0.72, color: skeletonHighlight),
    MTColorToken(
      name: "borderFaint", lightHex: "#DCD6C9", darkHex: "#393B35", lightOpacity: 0.7,
      darkOpacity: 0.7, color: borderFaint),
    MTColorToken(
      name: "inkUnderline", lightHex: "#26251F", darkHex: "#EEEADF", lightOpacity: 0.7,
      darkOpacity: 0.7, color: inkUnderline),
    MTColorToken(
      name: "scrimFaint", lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.12,
      darkOpacity: 0.12, color: scrimFaint),
    MTColorToken(
      name: "scrimMedium", lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.34,
      darkOpacity: 0.34, color: scrimMedium),
    MTColorToken(
      name: "scrimStrong", lightHex: "#26251F", darkHex: "#000000", lightOpacity: 0.48,
      darkOpacity: 0.48, color: scrimStrong),
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

/// A text role: the font, tracking, and case shared with the Web --mt-type-* variables.
struct MTTextRole: Sendable {
  let name: String
  let size: CGFloat
  let weight: Font.Weight
  let design: Font.Design
  let lineHeight: CGFloat
  let tracking: CGFloat
  let isUppercase: Bool
  /// The Dynamic Type style the size scales with, or nil for a fixed size.
  let textStyle: Font.TextStyle?

  static let hero = MTTextRole(
    name: "hero", size: 50, weight: .medium, design: .serif, lineHeight: 1.02, tracking: -2.25,
    isUppercase: false, textStyle: .largeTitle)
  static let display = MTTextRole(
    name: "display", size: 34, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .largeTitle)
  static let title = MTTextRole(
    name: "title", size: 28, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title)
  static let sheetTitle = MTTextRole(
    name: "sheetTitle", size: 22, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title2)
  static let recordTitle = MTTextRole(
    name: "recordTitle", size: 26, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil)
  static let wordmarkLarge = MTTextRole(
    name: "wordmarkLarge", size: 32, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil)
  static let titleSmall = MTTextRole(
    name: "titleSmall", size: 20, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .title3)
  static let cardTitle = MTTextRole(
    name: "cardTitle", size: 20, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title3)
  static let wordmark = MTTextRole(
    name: "wordmark", size: 19, weight: .medium, design: .serif, lineHeight: 1.15, tracking: -0.4,
    isUppercase: false, textStyle: nil)
  static let heading = MTTextRole(
    name: "heading", size: 17, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .headline)
  static let bodyLarge = MTTextRole(
    name: "bodyLarge", size: 17, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .body)
  static let body = MTTextRole(
    name: "body", size: 15, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .subheadline)
  static let label = MTTextRole(
    name: "label", size: 13, weight: .medium, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .footnote)
  static let caption = MTTextRole(
    name: "caption", size: 12, weight: .medium, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .caption)
  static let micro = MTTextRole(
    name: "micro", size: 11, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .caption2)
  static let code = MTTextRole(
    name: "code", size: 11, weight: .regular, design: .monospaced, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil)
  static let eyebrow = MTTextRole(
    name: "eyebrow", size: 10, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 1,
    isUppercase: true, textStyle: nil)
  static let fine = MTTextRole(
    name: "fine", size: 10, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: nil)
  static let stamp = MTTextRole(
    name: "stamp", size: 10, weight: .regular, design: .monospaced, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil)

  static let catalog = [
    hero,
    display,
    title,
    sheetTitle,
    recordTitle,
    wordmarkLarge,
    titleSmall,
    cardTitle,
    wordmark,
    heading,
    bodyLarge,
    body,
    label,
    caption,
    micro,
    code,
    eyebrow,
    fine,
    stamp,
  ]
}

// Text role fonts. Roles mapped to a Dynamic Type style follow it; the others keep a fixed size.
enum MTFont {
  // Sign-in story headline.
  // hero scales a custom 50 pt size with largeTitle, so it has no
  // static font; apply it with mtTextRole(.hero).
  /// Page titles.
  static let display = Font.system(.largeTitle, design: .serif).weight(.medium)
  /// Section and onboarding titles.
  static let title = Font.system(.title, design: .serif).weight(.medium)
  /// Sheet and dialog titles.
  static let sheetTitle = Font.system(.title2, design: .serif).weight(.medium)
  /// Record detail titles.
  static let recordTitle = Font.system(size: 26, weight: .medium, design: .serif)
  /// The splash screen wordmark.
  static let wordmarkLarge = Font.system(size: 32, weight: .medium, design: .serif)
  /// Card and panel titles.
  static let titleSmall = Font.title3.weight(.semibold)
  /// Serif record, Collection, and empty-state titles.
  static let cardTitle = Font.system(.title3, design: .serif).weight(.medium)
  /// The MemoTrail wordmark beside the brand mark.
  static let wordmark = Font.system(size: 19, weight: .medium, design: .serif)
  /// Compact list and card headings.
  static let heading = Font.headline
  /// Reading text and primary inputs.
  static let bodyLarge = Font.body
  /// Default interface text.
  static let body = Font.subheadline
  /// Field labels, buttons, and navigation.
  static let label = Font.footnote.weight(.medium)
  /// Metadata and helper text.
  static let caption = Font.caption.weight(.medium)
  /// Dense badges and tooltips.
  static let micro = Font.caption2.weight(.semibold)
  /// Inline values in history diffs.
  static let code = Font.system(size: 11, design: .monospaced)
  /// Uppercase eyebrows above titles.
  static let eyebrow = Font.system(size: 10, weight: .semibold)
  /// The smallest readable text, such as map attribution and inline actions.
  static let fine = Font.system(size: 10)
  /// Monospaced counts and dates.
  static let stamp = Font.system(size: 10, design: .monospaced)
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

struct MTEasingCurve: Sendable {
  let name: String
  let x1: Double
  let y1: Double
  let x2: Double
  let y2: Double

  func animation(duration: Double) -> Animation {
    .timingCurve(x1, y1, x2, y2, duration: duration)
  }
}

enum MTEasing {
  static let standard = MTEasingCurve(name: "standard", x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
  static let enter = MTEasingCurve(name: "enter", x1: 0, y1: 0, x2: 0.58, y2: 1)
  static let exit = MTEasingCurve(name: "exit", x1: 0.42, y1: 0, x2: 1, y2: 1)
  static let emphasized = MTEasingCurve(name: "emphasized", x1: 0.22, y1: 1, x2: 0.36, y2: 1)
  static let inOut = MTEasingCurve(name: "inOut", x1: 0.42, y1: 0, x2: 0.58, y2: 1)
  static let linear = MTEasingCurve(name: "linear", x1: 0, y1: 0, x2: 1, y2: 1)

  static let catalog = [
    standard,
    enter,
    exit,
    emphasized,
    inOut,
    linear,
  ]
}

enum MTLineHeight {
  static let tight: CGFloat = 1.15
  static let body: CGFloat = 1.55
  static let relaxed: CGFloat = 1.7
}

enum MTSize {
  enum Control {
    static let small: CGFloat = 34
    static let medium: CGFloat = 44
    static let large: CGFloat = 52
  }

  enum Field {
    static let small: CGFloat = 36
    static let medium: CGFloat = 44
    static let large: CGFloat = 50
  }

  static let hitTarget: CGFloat = 44

  enum Icon {
    static let s7: CGFloat = 7
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s11: CGFloat = 11
    static let s12: CGFloat = 12
    static let s13: CGFloat = 13
    static let s14: CGFloat = 14
    static let s15: CGFloat = 15
    static let s16: CGFloat = 16
    static let s17: CGFloat = 17
    static let s18: CGFloat = 18
    static let s19: CGFloat = 19
    static let s20: CGFloat = 20
    static let s21: CGFloat = 21
    static let s22: CGFloat = 22
    static let s23: CGFloat = 23
    static let s24: CGFloat = 24
    static let s25: CGFloat = 25
    static let s30: CGFloat = 30
  }

  enum Stroke {
    static let thin: CGFloat = 1
    static let medium: CGFloat = 2
    static let thick: CGFloat = 3
    static let icon: CGFloat = 1.7
  }
}

enum MTLayout {
  enum PageGutter {
    static let regular: CGFloat = 32
    static let compact: CGFloat = 16
    static let narrow: CGFloat = 12
  }
}

// Page widths match the Web PageFrame variants; phones use the full width with page gutters.
enum MTPageWidth: CGFloat, CaseIterable, Sendable {
  case compact = 880
  case standard = 960
  case wide = 1080
  case canvas = 1180

  var title: String {
    switch self {
    case .compact: "Compact"
    case .standard: "Standard"
    case .wide: "Wide"
    case .canvas: "Canvas"
    }
  }

  var purpose: String {
    switch self {
    case .compact: "Forms and focused reading"
    case .standard: "Lists and search"
    case .wide: "Dashboards and card grids"
    case .canvas: "Dense spatial views"
    }
  }
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
  static let hairline = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.025, radius: 1, x: 0, y: 1)
  ]
  static let thumb = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.1, radius: 1.5, x: 0, y: 1)
  ]
  static let thumbStrong = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.12, radius: 1.5, x: 0, y: 1)
  ]
  static let lifted = [
    MTShadowLayer(red: 38, green: 37, blue: 31, opacity: 0.06, radius: 6, x: 0, y: 3)
  ]
  static let mediaControl = [
    MTShadowLayer(red: 0, green: 0, blue: 0, opacity: 0.24, radius: 9, x: 0, y: 4)
  ]
  static let snapshotPin = [
    MTShadowLayer(red: 0, green: 0, blue: 0, opacity: 0.18, radius: 3, x: 0, y: 1)
  ]

  static let catalog = [
    MTShadowToken(
      name: "raised", css: "0 1px 2px rgb(38 37 31 / 0.06), 0 8px 28px rgb(38 37 31 / 0.06)",
      layers: raised),
    MTShadowToken(name: "floating", css: "0 16px 48px rgb(38 37 31 / 0.14)", layers: floating),
    MTShadowToken(name: "hairline", css: "0 1px 2px rgb(38 37 31 / 0.025)", layers: hairline),
    MTShadowToken(name: "thumb", css: "0 1px 3px rgb(38 37 31 / 0.1)", layers: thumb),
    MTShadowToken(name: "thumbStrong", css: "0 1px 3px rgb(38 37 31 / 0.12)", layers: thumbStrong),
    MTShadowToken(name: "lifted", css: "0 3px 12px rgb(38 37 31 / 0.06)", layers: lifted),
    MTShadowToken(name: "mediaControl", css: "0 4px 18px rgb(0 0 0 / 0.24)", layers: mediaControl),
    MTShadowToken(name: "snapshotPin", css: "0 1px 6px rgb(0 0 0 / 0.18)", layers: snapshotPin),
  ]
}

enum MTState {
  enum Focus {
    static let ring = MTColor.accent
    static let halo = MTColor.accentSubtle
    static let ringWidth: CGFloat = 2
    static let ringOffset: CGFloat = 3
    static let haloWidth: CGFloat = 3
  }

  enum Hover {
    static let surface = MTColor.surfaceSubtle
    static let ink = MTColor.ink
    static let accentSurface = MTColor.accentSubtle
    static let primary = MTColor.accentHover
    static let chipBorder = Color(lightHex: "#889687", darkHex: "#627668")
    static let periodBar = Color(lightHex: "#ADC1B8", darkHex: "#405C4F")
  }

  enum Selected {
    static let surface = MTColor.surfaceRaised
    static let ink = MTColor.accent
    static let fill = MTColor.accent
    static let onFill = MTColor.accentInk
  }

  enum Disabled {
    enum Opacity {
      static let button: Double = 0.5
      static let field: Double = 0.65
      static let choice: Double = 0.56
      static let quiet: Double = 0.58
      static let navigation: Double = 0.45
      static let soft: Double = 0.7
      static let toolbar: Double = 0.38
      static let calendarDay: Double = 0.35
    }

    static let codeSurface = Color(lightHex: "#EEE9DF", darkHex: "#272924")
  }
}

enum MTSystemMaterial: Sendable {
  case ultraThin
  case thin
  case regular
  case thick
  case ultraThick
  case bar

  var material: Material {
    switch self {
    case .ultraThin: .ultraThinMaterial
    case .thin: .thinMaterial
    case .regular: .regularMaterial
    case .thick: .thickMaterial
    case .ultraThick: .ultraThickMaterial
    case .bar: .bar
    }
  }
}

/// A translucent surface: a tint over an optional system material, with an optional border.
struct MTMaterialToken: Sendable {
  let name: String
  let tint: Color
  let border: Color?
  let systemMaterial: MTSystemMaterial?
}

enum MTMaterial {
  static let glassPanel = MTMaterialToken(
    name: "glassPanel",
    tint: Color(lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.94, darkOpacity: 0.94),
    border: Color(lightHex: "#C7BFAF", darkHex: "#4B4E46", lightOpacity: 0.8, darkOpacity: 0.8),
    systemMaterial: .ultraThin)
  static let chip = MTMaterialToken(
    name: "chip",
    tint: Color(lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.86, darkOpacity: 0.86),
    border: nil, systemMaterial: .ultraThin)

  static let catalog = [
    glassPanel,
    chip,
  ]
}

/// A surface and its shadow, with the scrim behind it for overlays.
struct MTElevationToken: Sendable {
  let name: String
  let surface: Color
  let shadow: [MTShadowLayer]
  let scrim: Color?
}

enum MTElevation {
  static let flat = MTElevationToken(
    name: "flat", surface: MTColor.surfaceRaised, shadow: [], scrim: nil)
  static let resting = MTElevationToken(
    name: "resting", surface: MTColor.surfaceRaised, shadow: MTShadow.hairline, scrim: nil)
  static let raised = MTElevationToken(
    name: "raised", surface: MTColor.surfaceRaised, shadow: MTShadow.raised, scrim: nil)
  static let floating = MTElevationToken(
    name: "floating", surface: MTColor.surfaceRaised, shadow: MTShadow.floating, scrim: nil)
  static let overlay = MTElevationToken(
    name: "overlay", surface: MTColor.surfaceRaised, shadow: MTShadow.floating,
    scrim: MTColor.scrimStrong)

  static let catalog = [
    flat,
    resting,
    raised,
    floating,
    overlay,
  ]
}

// Semantic icons share the Web icon vocabulary and resolve to SF Symbols.
enum MTIcon: String, CaseIterable, Sendable {
  case archive = "archivebox"
  case arrowLeft = "arrow.left"
  case arrowRight = "arrow.right"
  case bold = "bold"
  case bulletList = "list.bullet"
  case calendar = "calendar"
  case car = "car"
  case check = "checkmark"
  case chevron = "chevron.right"
  case clock = "clock"
  case close = "xmark"
  case code = "chevron.left.forwardslash.chevron.right"
  case codeBlock = "curlybraces.square"
  case collection = "square.stack"
  case copy = "doc.on.doc"
  case dashboard = "square.grid.2x2"
  case edit = "square.and.pencil"
  case export = "square.and.arrow.up"
  case history = "clock.arrow.circlepath"
  case home = "house"
  case inbox = "tray"
  case italic = "italic"
  case library = "books.vertical"
  case link = "link"
  case map = "map"
  case mic = "mic"
  case more = "ellipsis"
  case orderedList = "list.number"
  case people = "person.2"
  case person = "person"
  case photo = "photo"
  case plus = "plus"
  case quote = "text.quote"
  case refresh = "arrow.clockwise"
  case search = "magnifyingglass"
  case settings = "gearshape"
  case sparkle = "sparkles"
  case star = "star"
  case stop = "stop.fill"
  case strike = "strikethrough"
  case tag = "tag"
  case target = "target"
  case timeline = "point.bottomleft.forward.to.point.topright.scurvepath"
  case trash = "trash"
  case underline = "underline"
  case warning = "exclamationmark.triangle"

  var systemName: String { rawValue }

  /// Icons that only native iOS draws; Web has no glyph for them yet.
  static let iosOnly: Set<MTIcon> = [
    .collection,
    .export,
    .history,
    .library,
    .people,
    .person,
    .warning,
  ]
}

extension Color {
  fileprivate init(
    lightHex: String, darkHex: String, lightOpacity: Double = 1, darkOpacity: Double = 1
  ) {
    self.init(
      uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
          ? UIColor(hex: darkHex, alpha: darkOpacity) : UIColor(hex: lightHex, alpha: lightOpacity)
      }
    )
  }
}

extension UIColor {
  fileprivate convenience init(hex: String, alpha: Double) {
    var value: UInt64 = 0
    Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
    self.init(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: alpha
    )
  }
}
