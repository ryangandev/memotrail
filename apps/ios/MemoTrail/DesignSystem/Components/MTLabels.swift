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

// MTBadgeTone, MTBadgeSize, and MTBadgeDefaults are generated from
// packages/design-system/components/badge.yaml, which also lists each tone's tokens.
extension MTBadgeTone {
  fileprivate var foreground: Color {
    switch self {
    case .accent, .glassAccent: MTColor.accent
    case .neutral, .outline, .glassNeutral: MTColor.inkMuted
    case .warm: MTColor.warm
    case .success: MTColor.success
    case .danger: MTColor.danger
    case .inverse: MTColor.inverseInk
    case .solidAccent: MTColor.accentInk
    }
  }

  fileprivate var fill: Color {
    switch self {
    case .accent: MTColor.accentSubtle
    case .neutral: MTColor.surfaceSubtle
    case .warm: MTColor.warmSubtle
    case .success: MTColor.successSubtle
    case .danger: MTColor.dangerSubtle
    case .outline: MTColor.surface
    case .inverse: MTColor.inverseSurface
    case .solidAccent: MTColor.accent
    case .glassAccent, .glassNeutral: MTMaterial.chip.tint
    }
  }

  /// Glass tones sit on photos and maps, so they blur what is behind them like Web.
  fileprivate var material: MTSystemMaterial? {
    switch self {
    case .glassAccent, .glassNeutral: MTMaterial.chip.systemMaterial
    default: nil
    }
  }

  fileprivate var border: Color? { self == .outline ? MTColor.border : nil }
}

extension MTBadgeSize {
  fileprivate func textRole(uppercase: Bool) -> MTTextRole {
    switch (self, uppercase) {
    case (.micro, false): .badgeMicro
    case (.micro, true): .badgeMicroCaps
    case (.small, false): .badgeSmall
    case (.small, true): .badgeSmallCaps
    case (.medium, false): .badgeMedium
    case (.medium, true): .badgeMediumCaps
    }
  }
}

/// A noninteractive, single-line label. Long text truncates within its container.
/// Specified in packages/design-system/components/badge.yaml.
struct MTBadge: View {
  let title: String
  var tone: MTBadgeTone = MTBadgeDefaults.tone
  var size: MTBadgeSize = MTBadgeDefaults.size
  var uppercase = MTBadgeDefaults.uppercase

  var body: some View {
    // Like a Web border, the outline sits inside the badge and adds to its size.
    let borderWidth = tone.border == nil ? 0 : MTSize.Stroke.thin
    Text(title)
      .mtTextRole(size.textRole(uppercase: uppercase))
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(tone.foreground)
      .padding(.horizontal, MTSpacing.s2 + borderWidth)
      .padding(.vertical, MTSize.Badge.paddingBlock + borderWidth)
      .frame(minHeight: size == .medium ? MTSize.Badge.minHeight : nil)
      .background(tone.fill, in: Capsule())
      .background {
        if let material = tone.material { Capsule().fill(material.material) }
      }
      .overlay {
        if let border = tone.border { Capsule().strokeBorder(border, lineWidth: borderWidth) }
      }
      .accessibilityLabel(title)
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
