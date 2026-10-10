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
  static let accentGroupBorder = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.38, darkOpacity: 0.38)
  static let accentPrompt = Color(
    lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.6, darkOpacity: 0.6)
  static let warmPrompt = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.6, darkOpacity: 0.6)
  static let labelSheen = Color(
    lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.34, darkOpacity: 0.34)
  static let labelShade = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.12, darkOpacity: 0.12)
  static let labelEdge = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.48, darkOpacity: 0.48)
  static let labelDash = Color(
    lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.54, darkOpacity: 0.54)
  static let markRing = Color(lightHex: "#82AD98", darkHex: "#82AD98")
  static let photoBackdrop = Color(lightHex: "#000000", darkHex: "#000000")

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
    MTColorToken(
      name: "accentGroupBorder", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.38,
      darkOpacity: 0.38, color: accentGroupBorder),
    MTColorToken(
      name: "accentPrompt", lightHex: "#315E4F", darkHex: "#82AD98", lightOpacity: 0.6,
      darkOpacity: 0.6, color: accentPrompt),
    MTColorToken(
      name: "warmPrompt", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.6,
      darkOpacity: 0.6, color: warmPrompt),
    MTColorToken(
      name: "labelSheen", lightHex: "#FFFFFF", darkHex: "#262824", lightOpacity: 0.34,
      darkOpacity: 0.34, color: labelSheen),
    MTColorToken(
      name: "labelShade", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.12,
      darkOpacity: 0.12, color: labelShade),
    MTColorToken(
      name: "labelEdge", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.48,
      darkOpacity: 0.48, color: labelEdge),
    MTColorToken(
      name: "labelDash", lightHex: "#A76346", darkHex: "#D49373", lightOpacity: 0.54,
      darkOpacity: 0.54, color: labelDash),
    MTColorToken(name: "markRing", lightHex: "#82AD98", darkHex: "#82AD98", color: markRing),
    MTColorToken(
      name: "photoBackdrop", lightHex: "#000000", darkHex: "#000000", color: photoBackdrop),
  ]
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
  /// The role's static MTFont, or nil when it scales a custom size with its text style.
  let font: Font?

  static let hero = MTTextRole(
    name: "hero", size: 50, weight: .medium, design: .serif, lineHeight: 1.02, tracking: -2.25,
    isUppercase: false, textStyle: .largeTitle, font: nil)
  static let display = MTTextRole(
    name: "display", size: 34, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .largeTitle, font: MTFont.display)
  static let title = MTTextRole(
    name: "title", size: 28, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title, font: MTFont.title)
  static let sheetTitle = MTTextRole(
    name: "sheetTitle", size: 22, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title2, font: MTFont.sheetTitle)
  static let recordTitle = MTTextRole(
    name: "recordTitle", size: 26, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil, font: MTFont.recordTitle)
  static let wordmarkLarge = MTTextRole(
    name: "wordmarkLarge", size: 32, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil, font: MTFont.wordmarkLarge)
  static let titleSmall = MTTextRole(
    name: "titleSmall", size: 20, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .title3, font: MTFont.titleSmall)
  static let cardTitle = MTTextRole(
    name: "cardTitle", size: 20, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title3, font: MTFont.cardTitle)
  static let wordmark = MTTextRole(
    name: "wordmark", size: 19, weight: .medium, design: .serif, lineHeight: 1.15, tracking: -0.4,
    isUppercase: false, textStyle: nil, font: MTFont.wordmark)
  static let heading = MTTextRole(
    name: "heading", size: 17, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .headline, font: MTFont.heading)
  static let bodyLarge = MTTextRole(
    name: "bodyLarge", size: 17, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .body, font: MTFont.bodyLarge)
  static let body = MTTextRole(
    name: "body", size: 15, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .subheadline, font: MTFont.body)
  static let label = MTTextRole(
    name: "label", size: 13, weight: .medium, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .footnote, font: MTFont.label)
  static let listHeading = MTTextRole(
    name: "listHeading", size: 13, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0.5, isUppercase: true, textStyle: .footnote, font: MTFont.listHeading)
  static let caption = MTTextRole(
    name: "caption", size: 12, weight: .medium, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .caption, font: MTFont.caption)
  static let pageEyebrow = MTTextRole(
    name: "pageEyebrow", size: 12, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 1, isUppercase: true, textStyle: .caption, font: MTFont.pageEyebrow)
  static let micro = MTTextRole(
    name: "micro", size: 11, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .caption2, font: MTFont.micro)
  static let code = MTTextRole(
    name: "code", size: 11, weight: .regular, design: .monospaced, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil, font: MTFont.code)
  static let eyebrow = MTTextRole(
    name: "eyebrow", size: 10, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 1,
    isUppercase: true, textStyle: nil, font: MTFont.eyebrow)
  static let factLabel = MTTextRole(
    name: "factLabel", size: 11, weight: .regular, design: .default, lineHeight: 1.15,
    tracking: 0.6, isUppercase: true, textStyle: .caption2, font: MTFont.factLabel)
  static let fine = MTTextRole(
    name: "fine", size: 10, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: nil, font: MTFont.fine)
  static let stamp = MTTextRole(
    name: "stamp", size: 10, weight: .regular, design: .monospaced, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: nil, font: MTFont.stamp)
  static let dateStamp = MTTextRole(
    name: "dateStamp", size: 11, weight: .regular, design: .monospaced, lineHeight: 1.15,
    tracking: 0.25, isUppercase: true, textStyle: .caption2, font: MTFont.dateStamp)
  static let firstTimeDate = MTTextRole(
    name: "firstTimeDate", size: 11, weight: .regular, design: .monospaced, lineHeight: 1.15,
    tracking: 0.35, isUppercase: true, textStyle: .caption2, font: MTFont.firstTimeDate)
  static let badgeMicro = MTTextRole(
    name: "badgeMicro", size: 11, weight: .regular, design: .default, lineHeight: 1.2, tracking: 0,
    isUppercase: false, textStyle: .caption2, font: MTFont.badgeMicro)
  static let badgeSmall = MTTextRole(
    name: "badgeSmall", size: 11, weight: .regular, design: .default, lineHeight: 1.2, tracking: 0,
    isUppercase: false, textStyle: .caption2, font: MTFont.badgeSmall)
  static let badgeMedium = MTTextRole(
    name: "badgeMedium", size: 12, weight: .regular, design: .default, lineHeight: 1.2, tracking: 0,
    isUppercase: false, textStyle: .caption, font: MTFont.badgeMedium)
  static let badgeMicroCaps = MTTextRole(
    name: "badgeMicroCaps", size: 11, weight: .semibold, design: .default, lineHeight: 1.2,
    tracking: 0.66, isUppercase: true, textStyle: .caption2, font: MTFont.badgeMicroCaps)
  static let badgeSmallCaps = MTTextRole(
    name: "badgeSmallCaps", size: 11, weight: .semibold, design: .default, lineHeight: 1.2,
    tracking: 0.66, isUppercase: true, textStyle: .caption2, font: MTFont.badgeSmallCaps)
  static let badgeMediumCaps = MTTextRole(
    name: "badgeMediumCaps", size: 12, weight: .semibold, design: .default, lineHeight: 1.2,
    tracking: 0.72, isUppercase: true, textStyle: .caption, font: MTFont.badgeMediumCaps)
  static let note = MTTextRole(
    name: "note", size: 11, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .caption2, font: MTFont.note)
  static let detail = MTTextRole(
    name: "detail", size: 12, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .caption, font: MTFont.detail)
  static let supporting = MTTextRole(
    name: "supporting", size: 13, weight: .regular, design: .default, lineHeight: 1.55, tracking: 0,
    isUppercase: false, textStyle: .footnote, font: MTFont.supporting)
  static let bodyStrong = MTTextRole(
    name: "bodyStrong", size: 15, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .subheadline, font: MTFont.bodyStrong)
  static let bodyEmphasis = MTTextRole(
    name: "bodyEmphasis", size: 15, weight: .medium, design: .default, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .subheadline, font: MTFont.bodyEmphasis)
  static let itemTitle = MTTextRole(
    name: "itemTitle", size: 17, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .body, font: MTFont.itemTitle)
  static let noteStrong = MTTextRole(
    name: "noteStrong", size: 11, weight: .medium, design: .default, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .caption2, font: MTFont.noteStrong)
  static let identifier = MTTextRole(
    name: "identifier", size: 12, weight: .medium, design: .monospaced, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .caption, font: MTFont.identifier)
  static let timestamp = MTTextRole(
    name: "timestamp", size: 11, weight: .regular, design: .monospaced, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .caption2, font: MTFont.timestamp)
  static let cardEyebrow = MTTextRole(
    name: "cardEyebrow", size: 11, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0.8, isUppercase: true, textStyle: .caption2, font: MTFont.cardEyebrow)
  static let archiveHeading = MTTextRole(
    name: "archiveHeading", size: 13, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0.8, isUppercase: true, textStyle: .footnote, font: MTFont.archiveHeading)
  static let settingsHeading = MTTextRole(
    name: "settingsHeading", size: 13, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 0.6, isUppercase: true, textStyle: .footnote, font: MTFont.settingsHeading)
  static let legend = MTTextRole(
    name: "legend", size: 12, weight: .semibold, design: .default, lineHeight: 1.15, tracking: 0.7,
    isUppercase: true, textStyle: .caption, font: MTFont.legend)
  static let groupLabel = MTTextRole(
    name: "groupLabel", size: 11, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 1.1, isUppercase: true, textStyle: .caption2, font: MTFont.groupLabel)
  static let storyEyebrow = MTTextRole(
    name: "storyEyebrow", size: 11, weight: .semibold, design: .default, lineHeight: 1.15,
    tracking: 1.3, isUppercase: true, textStyle: .caption2, font: MTFont.storyEyebrow)
  static let welcomeTitle = MTTextRole(
    name: "welcomeTitle", size: 28, weight: .medium, design: .serif, lineHeight: 1.15,
    tracking: -0.6, isUppercase: false, textStyle: .title, font: MTFont.welcomeTitle)
  static let recordName = MTTextRole(
    name: "recordName", size: 22, weight: .medium, design: .serif, lineHeight: 1.15, tracking: -0.4,
    isUppercase: false, textStyle: .title2, font: MTFont.recordName)
  static let recordNameCompact = MTTextRole(
    name: "recordNameCompact", size: 20, weight: .medium, design: .serif, lineHeight: 1.15,
    tracking: -0.4, isUppercase: false, textStyle: .title3, font: MTFont.recordNameCompact)
  static let goalName = MTTextRole(
    name: "goalName", size: 22, weight: .medium, design: .serif, lineHeight: 1.15, tracking: -0.5,
    isUppercase: false, textStyle: .title2, font: MTFont.goalName)
  static let goalNameCompact = MTTextRole(
    name: "goalNameCompact", size: 20, weight: .medium, design: .serif, lineHeight: 1.15,
    tracking: -0.5, isUppercase: false, textStyle: .title3, font: MTFont.goalNameCompact)
  static let avatarInitial = MTTextRole(
    name: "avatarInitial", size: 22, weight: .regular, design: .serif, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .title2, font: MTFont.avatarInitial)
  static let quietTitle = MTTextRole(
    name: "quietTitle", size: 20, weight: .regular, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .title3, font: MTFont.quietTitle)
  static let listIndex = MTTextRole(
    name: "listIndex", size: 20, weight: .regular, design: .monospaced, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .title3, font: MTFont.listIndex)
  static let tagMark = MTTextRole(
    name: "tagMark", size: 13, weight: .regular, design: .monospaced, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .footnote, font: MTFont.tagMark)
  static let quietTitleSmall = MTTextRole(
    name: "quietTitleSmall", size: 15, weight: .regular, design: .serif, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .subheadline, font: MTFont.quietTitleSmall)
  static let panelTitle = MTTextRole(
    name: "panelTitle", size: 17, weight: .medium, design: .serif, lineHeight: 1.15, tracking: 0,
    isUppercase: false, textStyle: .headline, font: MTFont.panelTitle)
  static let panelTitleSmall = MTTextRole(
    name: "panelTitleSmall", size: 16, weight: .medium, design: .serif, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .callout, font: MTFont.panelTitleSmall)
  static let collectionName = MTTextRole(
    name: "collectionName", size: 13, weight: .regular, design: .serif, lineHeight: 1.15,
    tracking: 0, isUppercase: false, textStyle: .footnote, font: MTFont.collectionName)

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
    listHeading,
    caption,
    pageEyebrow,
    micro,
    code,
    eyebrow,
    factLabel,
    fine,
    stamp,
    dateStamp,
    firstTimeDate,
    badgeMicro,
    badgeSmall,
    badgeMedium,
    badgeMicroCaps,
    badgeSmallCaps,
    badgeMediumCaps,
    note,
    detail,
    supporting,
    bodyStrong,
    bodyEmphasis,
    itemTitle,
    noteStrong,
    identifier,
    timestamp,
    cardEyebrow,
    archiveHeading,
    settingsHeading,
    legend,
    groupLabel,
    storyEyebrow,
    welcomeTitle,
    recordName,
    recordNameCompact,
    goalName,
    goalNameCompact,
    avatarInitial,
    quietTitle,
    listIndex,
    tagMark,
    quietTitleSmall,
    panelTitle,
    panelTitleSmall,
    collectionName,
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
  /// Small uppercase headings above lists.
  static let listHeading = Font.footnote.weight(.semibold)
  /// Metadata and helper text.
  static let caption = Font.caption.weight(.medium)
  /// The uppercase context above a page title, such as a date or area name.
  static let pageEyebrow = Font.caption.weight(.semibold)
  /// Dense badges and tooltips.
  static let micro = Font.caption2.weight(.semibold)
  /// Inline values in history diffs.
  static let code = Font.system(size: 11, design: .monospaced)
  /// Uppercase eyebrows above titles.
  static let eyebrow = Font.system(size: 10, weight: .semibold)
  /// The uppercase label above a fact in record details. iOS draws it at its 11 pt caption2 minimum.
  static let factLabel = Font.caption2
  /// The smallest readable text, such as map attribution and inline actions.
  static let fine = Font.system(size: 10)
  /// Monospaced counts and dates.
  static let stamp = Font.system(size: 10, design: .monospaced)
  /// Uppercase monospaced dates on record cards, archive rows, and Goal targets. iOS draws them at its 11 pt caption2 minimum.
  static let dateStamp = Font.system(.caption2, design: .monospaced)
  /// The uppercase date above a First Time card title. iOS draws it at its 11 pt caption2 minimum.
  static let firstTimeDate = Font.system(.caption2, design: .monospaced)
  /// Micro badge labels, such as tags in record card footers. iOS draws them at its 11 pt caption2 minimum.
  static let badgeMicro = Font.caption2
  /// Small badge labels, the default size for statuses and tags. iOS draws them at its 11 pt caption2 minimum.
  static let badgeSmall = Font.caption2
  /// Medium badge labels, such as Dashboard tags.
  static let badgeMedium = Font.caption
  /// Uppercase micro badge labels, such as record kinds over photos. Tracking is 0.06 em on both platforms.
  static let badgeMicroCaps = Font.caption2.weight(.semibold)
  /// Uppercase small badge labels. Tracking is 0.06 em on both platforms.
  static let badgeSmallCaps = Font.caption2.weight(.semibold)
  /// Uppercase medium badge labels. Tracking is 0.06 em on both platforms.
  static let badgeMediumCaps = Font.caption.weight(.semibold)
  /// Small notes, timestamps, and counts beside other text.
  static let note = Font.caption2
  /// Quiet counts, dates, and secondary lines at regular weight.
  static let detail = Font.caption
  /// Sentences that explain a heading, such as empty-state and card messages.
  static let supporting = Font.footnote
  /// Interface text that names the row or option it starts.
  static let bodyStrong = Font.subheadline.weight(.semibold)
  /// Interface text that stands out from the text beside it, such as large button labels.
  static let bodyEmphasis = Font.subheadline.weight(.medium)
  /// Serif titles of Entries and items inside lists and cards.
  static let itemTitle = Font.system(.body, design: .serif).weight(.medium)
  /// Small notes that need slightly more weight, such as counts in a ribbon.
  static let noteStrong = Font.caption2.weight(.medium)
  /// Token names, symbol names, and other identifiers shown as code.
  static let identifier = Font.system(.caption, design: .monospaced).weight(.medium)
  /// Monospaced dates and counts that scale with small text.
  static let timestamp = Font.system(.caption2, design: .monospaced)
  /// The uppercase kind above a Collection card title.
  static let cardEyebrow = Font.caption2.weight(.semibold)
  /// The uppercase heading above a record archive list.
  static let archiveHeading = Font.footnote.weight(.semibold)
  /// The uppercase title of a Settings section.
  static let settingsHeading = Font.footnote.weight(.semibold)
  /// The uppercase legend above a record detail group.
  static let legend = Font.caption.weight(.semibold)
  /// The uppercase label above a group of More destinations.
  static let groupLabel = Font.caption2.weight(.semibold)
  /// The uppercase line above the sign-in story headline.
  static let storyEyebrow = Font.caption2.weight(.semibold)
  /// The sign-in welcome title.
  static let welcomeTitle = Font.system(.title, design: .serif).weight(.medium)
  /// Serif names on archive, First Time, and Person cards in regular width.
  static let recordName = Font.system(.title2, design: .serif).weight(.medium)
  /// Serif names on archive, First Time, and Person cards on phones.
  static let recordNameCompact = Font.system(.title3, design: .serif).weight(.medium)
  /// Goal card titles in regular width.
  static let goalName = Font.system(.title2, design: .serif).weight(.medium)
  /// Goal card titles on phones.
  static let goalNameCompact = Font.system(.title3, design: .serif).weight(.medium)
  /// A Person's initial inside their avatar.
  static let avatarInitial = Font.system(.title2, design: .serif)
  /// Regular-weight serif titles and counts, such as Dashboard ribbon counts.
  static let quietTitle = Font.system(.title3, design: .serif)
  /// The two-digit number beside a First Time in a list.
  static let listIndex = Font.system(.title3, design: .monospaced)
  /// The # before a tag name.
  static let tagMark = Font.system(.footnote, design: .monospaced)
  /// Regular-weight serif record detail headings on phones.
  static let quietTitleSmall = Font.system(.subheadline, design: .serif)
  /// Serif titles of panels on the Export page.
  static let panelTitle = Font.system(.headline, design: .serif).weight(.medium)
  /// Serif titles of nested panels on the Export page.
  static let panelTitleSmall = Font.system(.callout, design: .serif).weight(.medium)
  /// A Collection's name on its ledger chip.
  static let collectionName = Font.system(.footnote, design: .serif)
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
  static let lineGap: CGFloat = 2
  static let headingGap: CGFloat = 3
  static let detailGap: CGFloat = 5
  static let chipGap: CGFloat = 6
  static let actionGap: CGFloat = 10
  static let badgeGap: CGFloat = 5
  static let panelGap: CGFloat = 14

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
    ("lineGap", lineGap),
    ("headingGap", headingGap),
    ("detailGap", detailGap),
    ("chipGap", chipGap),
    ("actionGap", actionGap),
    ("badgeGap", badgeGap),
    ("panelGap", panelGap),
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
  static let shimmer = Double(1250) / 1_000
  static let photoPage = Double(200) / 1_000
  static let markRing = Double(580) / 1_000
  static let markTrail = Double(340) / 1_000
  static let markTrailDelay = Double(220) / 1_000
  static let markInnerRing = Double(500) / 1_000
  static let markTurn = Double(320) / 1_000
  static let splashFade = Double(300) / 1_000
  static let wordmarkReveal = Double(400) / 1_000
  static let wordmarkDelay = Double(420) / 1_000

  static let catalog: [(name: String, seconds: Double)] = [
    ("quick", quick),
    ("standard", standard),
    ("deliberate", deliberate),
    ("shimmer", shimmer),
    ("photoPage", photoPage),
    ("markRing", markRing),
    ("markTrail", markTrail),
    ("markTrailDelay", markTrailDelay),
    ("markInnerRing", markInnerRing),
    ("markTurn", markTurn),
    ("splashFade", splashFade),
    ("wordmarkReveal", wordmarkReveal),
    ("wordmarkDelay", wordmarkDelay),
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

  enum Badge {
    static let paddingBlock: CGFloat = 3
    static let minHeight: CGFloat = 22
  }
}

enum MTLayout {
  enum PageGutter {
    static let regular: CGFloat = 32
    static let compact: CGFloat = 16
    static let narrow: CGFloat = 12
  }

  enum PageHeader {
    static let descriptionWidth: CGFloat = 640
    static let copyBasis: CGFloat = 260
  }

  enum Field {
    static let textareaInset: CGFloat = 11
    static let accessory: CGFloat = 28
  }

  enum FieldGrid {
    static let minimumColumnWidth: CGFloat = 240
  }

  enum Checkbox {
    static let box: CGFloat = 20
    static let radius: CGFloat = 5
    static let baselineOffset: CGFloat = 5
  }

  enum Loading {
    static let page: CGFloat = 180
    static let dashboard: CGFloat = 150
    static let list: CGFloat = 140
    static let section: CGFloat = 120
  }

  enum InlineAction {
    static let height: CGFloat = 32
    static let disclosureHeight: CGFloat = 36
  }

  enum RecordCard {
    static let visualHeight: CGFloat = 190
    static let entryVisualHeight: CGFloat = 210
    static let collectionMinHeight: CGFloat = 138
    static let footerHeight: CGFloat = 31
    static let goalMinHeight: CGFloat = 220
    static let goalVisualHeight: CGFloat = 125
    static let goalVisualHeightRegular: CGFloat = 138
    static let goalMinHeightRegular: CGFloat = 245
    static let personMinHeight: CGFloat = 260
    static let trashVisualWidth: CGFloat = 88
    static let trashMinHeight: CGFloat = 112
  }

  enum Grid {
    static let collection: CGFloat = 200
    static let record: CGFloat = 300
    static let detail: CGFloat = 220
    static let photo: CGFloat = 104
  }

  enum PhotoDate {
    static let thumbWidth: CGFloat = 80
    static let thumbHeight: CGFloat = 100
  }

  enum Timeline {
    static let rowHeight: CGFloat = 62
    static let stageWidth: CGFloat = 14
    static let stageHeight: CGFloat = 7
    static let moment: CGFloat = 10
    static let orderField: CGFloat = 118
  }

  enum Avatar {
    static let size: CGFloat = 48
    static let toolbar: CGFloat = 32
  }

  enum IconTile {
    static let small: CGFloat = 36
    static let medium: CGFloat = 42
    static let large: CGFloat = 44
    static let emptyState: CGFloat = 48
    static let compact: CGFloat = 34
    static let compactRadius: CGFloat = 10
  }

  enum OptionRow {
    static let minHeight: CGFloat = 76
  }

  enum Dashboard {
    static let rowHeight: CGFloat = 56
    static let dateColumn: CGFloat = 46
    static let coverHeight: CGFloat = 230
    static let thumbWidth: CGFloat = 64
    static let thumbHeight: CGFloat = 72
  }

  enum FactList {
    static let labelWidth: CGFloat = 80
  }

  enum ItemPanel {
    static let padding: CGFloat = 22
    static let paddingRegular: CGFloat = 44
  }

  enum More {
    static let icon: CGFloat = 22
  }

  enum QuickCapture {
    static let barHeight: CGFloat = 64
  }

  enum Toolbar {
    static let mark: CGFloat = 28
  }

  enum Splash {
    static let mark: CGFloat = 132
    static let wordmarkRise: CGFloat = 7
  }

  enum Map {
    static let edgeTop: CGFloat = 64
    static let edgeSide: CGFloat = 72
    static let edgeBottom: CGFloat = 80
  }

  enum TagChip {
    static let height: CGFloat = 42
    static let count: CGFloat = 22
  }

  enum Organization {
    static let tagGap: CGFloat = 3
    static let tagLeading: CGFloat = 10
    static let tagTrailing: CGFloat = 3
    static let removeButton: CGFloat = 22
    static let removeOffset: CGFloat = 13
    static let labelInset: CGFloat = 7
    static let labelHeight: CGFloat = 40
    static let bookendWidth: CGFloat = 8
    static let bookendOverhang: CGFloat = 3
    static let glowRadius: CGFloat = 4
    static let glowOffset: CGFloat = 3
    static let addInset: CGFloat = 11
    static let addHeight: CGFloat = 38
    static let rowIcon: CGFloat = 20
    static let tagSearchRadius: CGFloat = 22
    static let labelSearchRadius: CGFloat = 2
    static let searchSpine: CGFloat = 4
    static let searchShadowOffset: CGFloat = 3
  }

  enum DashedBorder {
    static let dash: CGFloat = 4
    static let dot: CGFloat = 3
    static let gap: CGFloat = 3
  }

  enum RichText {
    static let maxHeight: CGFloat = 300
    static let verticalInset: CGFloat = 12
    static let horizontalInset: CGFloat = 8
    static let placeholderInset: CGFloat = 12
    static let toolbarDivider: CGFloat = 24
    static let blockGap: CGFloat = 11
    static let listMarker: CGFloat = 18
    static let minHeight: CGFloat = 180
    static let captureMinHeight: CGFloat = 120
    static let reviewMinHeight: CGFloat = 200
  }

  enum UploadRing {
    static let stroke: CGFloat = 5
    static let inset: CGFloat = 2.5
  }

  enum PhotoTile {
    static let removeButton: CGFloat = 26
    static let removeTarget: CGFloat = 38
    static let captureThumb: CGFloat = 76
    static let captureRemoveButton: CGFloat = 24
    static let captureRemoveTarget: CGFloat = 36
  }

  enum Capture {
    static let statusHeight: CGFloat = 42
    static let actionBarHeight: CGFloat = 58
    static let spark: CGFloat = 32
    static let quietIconWidth: CGFloat = 40
    static let quietIconHeight: CGFloat = 36
  }

  enum SignIn {
    static let width: CGFloat = 460
    static let top: CGFloat = 44
    static let headerHeight: CGFloat = 68
    static let headerMark: CGFloat = 31
    static let markGap: CGFloat = 11
    static let cardMark: CGFloat = 42
    static let titleGap: CGFloat = 10
    static let controlHeight: CGFloat = 48
    static let googleMark: CGFloat = 18
  }

  enum Library {
    static let emptyHeight: CGFloat = 164
  }

  enum EmptyState {
    static let messageWidth: CGFloat = 480
  }

  enum Toast {
    static let width: CGFloat = 420
    static let minHeight: CGFloat = 52
    static let icon: CGFloat = 18
    static let stripe: CGFloat = 3
    static let bottomClearance: CGFloat = 76
  }

  enum ExportPanel {
    static let padding: CGFloat = 18
  }

  enum LocationMap {
    static let height: CGFloat = 160
  }

  enum DatePicker {
    static let width: CGFloat = 320
    static let yearWidth: CGFloat = 240
  }

  enum Gallery {
    static let mark: CGFloat = 40
    static let index: CGFloat = 22
    static let sampleVisual: CGFloat = 148
    static let sampleTile: CGFloat = 132
    static let photoSampleWidth: CGFloat = 240
    static let photoSampleHeight: CGFloat = 135
    static let truncationFrame: CGFloat = 160
    static let sampleGrid: CGFloat = 220
    static let artworkWidth: CGFloat = 640
    static let artworkHeight: CGFloat = 360
  }

  enum Exploration {
    static let questionHeight: CGFloat = 100
    static let conclusionHeight: CGFloat = 200
  }

  enum Disclosure {
    static let indent: CGFloat = 19
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
    static let haloStroke: CGFloat = 6
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

  enum Pressed {
    static let cardScale: Double = 0.99
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
