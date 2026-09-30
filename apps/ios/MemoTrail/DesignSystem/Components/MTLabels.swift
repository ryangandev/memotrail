import SwiftUI

/// Semantic tone for inline feedback and status surfaces.
enum MTTone: CaseIterable {
  case neutral, accent, warm, success

  var foreground: Color {
    switch self {
    case .neutral: MTColor.inkMuted
    case .accent: MTColor.accent
    case .warm: MTColor.warm
    case .success: MTColor.success
    }
  }

  var background: Color {
    switch self {
    case .neutral: MTColor.surfaceSubtle
    case .accent, .success: MTColor.accentSubtle
    case .warm: MTColor.warmSubtle
    }
  }
}

enum MTBadgeTone: CaseIterable, Sendable {
  case accent, neutral, warm, success, outline, solidAccent, inverse, glassAccent, glassNeutral

  var title: String {
    switch self {
    case .accent: "accent"
    case .neutral: "neutral"
    case .warm: "warm"
    case .success: "success"
    case .outline: "outline"
    case .solidAccent: "solidAccent"
    case .inverse: "inverse"
    case .glassAccent: "glassAccent"
    case .glassNeutral: "glassNeutral"
    }
  }

  fileprivate var foreground: Color {
    switch self {
    case .accent, .glassAccent: MTColor.accent
    case .neutral, .outline, .glassNeutral: MTColor.inkMuted
    case .warm: MTColor.warm
    case .success: MTColor.success
    case .solidAccent: MTColor.accentInk
    case .inverse: .white
    }
  }

  fileprivate var background: Color {
    switch self {
    case .accent, .success: MTColor.accentSubtle
    case .neutral: MTColor.surfaceSubtle
    case .warm: MTColor.warmSubtle
    case .outline: MTColor.surface
    case .solidAccent: MTColor.accent
    case .inverse: Color(red: 24 / 255, green: 24 / 255, blue: 20 / 255).opacity(0.72)
    case .glassAccent, .glassNeutral: MTColor.surfaceRaised.opacity(0.86)
    }
  }

  /// Glass tones sit on photos and maps, so they blur what is behind them like Web.
  fileprivate var isGlass: Bool { self == .glassAccent || self == .glassNeutral }
}

enum MTBadgeSize: CaseIterable, Sendable {
  case micro, small, medium

  var title: String {
    switch self {
    case .micro: "micro"
    case .small: "small"
    case .medium: "medium"
    }
  }
}

/// A noninteractive, single-line label. Long text truncates within its container.
struct MTBadge: View {
  let title: String
  var tone: MTBadgeTone = .accent
  var size: MTBadgeSize = .small
  var uppercase = false

  var body: some View {
    Text(uppercase ? title.uppercased() : title)
      .font(font)
      .tracking(uppercase ? 0.6 : 0)
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(tone.foreground)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, 3)
      .frame(minHeight: size == .medium ? 22 : nil)
      .background(tone.background, in: Capsule())
      .background {
        if tone.isGlass { Capsule().fill(.ultraThinMaterial) }
      }
      .overlay {
        if tone == .outline { Capsule().stroke(MTColor.border, lineWidth: 1) }
      }
      .accessibilityLabel(title)
  }

  private var font: Font {
    switch size {
    case .micro: Font.caption2.weight(.semibold)
    case .small: Font.caption2.weight(uppercase ? .semibold : .medium)
    case .medium: Font.caption.weight(uppercase ? .semibold : .regular)
    }
  }
}

/// Badges for a record's Collections and tags, with an overflow count for tags.
struct MTOrganizationBadges: View {
  let collectionNames: [String]
  let tagNames: [String]
  var tagLimit = 3
  var tone: MTBadgeTone = .neutral

  var body: some View {
    if !collectionNames.isEmpty || !tagNames.isEmpty {
      ViewThatFits(in: .horizontal) {
        badges(tagLimit: tagLimit)
        badges(tagLimit: min(tagLimit, 1))
        badges(tagLimit: 0)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(accessibilityText)
    }
  }

  private func badges(tagLimit: Int) -> some View {
    HStack(spacing: MTSpacing.s1) {
      ForEach(collectionNames, id: \.self) { MTBadge(title: $0, tone: tone) }
      ForEach(tagNames.prefix(tagLimit), id: \.self) { MTBadge(title: "#\($0)", tone: tone) }
      if tagNames.count > tagLimit {
        MTBadge(title: "+\(tagNames.count - tagLimit)", tone: tone)
      }
    }
  }

  private var accessibilityText: String {
    (collectionNames + tagNames.map { "tag \($0)" }).joined(separator: ", ")
  }
}
