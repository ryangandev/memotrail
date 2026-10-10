// Generated from packages/design-system/components. Do not edit directly.

// Badge, from packages/design-system/components/badge.yaml.

/// The badge's color treatment. Glass and inverse tones are for photos and maps; success and danger
/// are for outcomes.
enum MTBadgeTone: String, CaseIterable, Sendable {
  case accent
  case neutral
  case warm
  case success
  case danger
  case outline
  case inverse
  case solidAccent
  case glassAccent
  case glassNeutral
}

/// The badge's text size. Micro fits dense cards, small is the default, and medium sits beside 22
/// px controls.
enum MTBadgeSize: String, CaseIterable, Sendable {
  case micro
  case small
  case medium
}

/// Badge parameter defaults.
enum MTBadgeDefaults {
  static let tone = MTBadgeTone.accent
  static let size = MTBadgeSize.small
  static let uppercase = false
}

// Button, from packages/design-system/components/button.yaml.

/// The action's emphasis. Primary is the main action, secondary an alternative, ghost a quiet one,
/// and danger a destructive one.
enum MTButtonVariant: String, CaseIterable, Sendable {
  case primary
  case secondary
  case ghost
  case danger
}

/// The control's height, padding, and text size. Small fits dense rows and toolbars, and large
/// stands alone.
enum MTButtonSize: String, CaseIterable, Sendable {
  case small
  case medium
  case large
}

/// Button parameter defaults.
enum MTButtonDefaults {
  static let variant = MTButtonVariant.primary
  static let size = MTButtonSize.medium
  static let isLoading = false
  static let fillsWidth = false
}

/// A gallery specimen from a component spec. The Web gallery marks it with data-specimen and
/// the iOS gallery with `accessibilityIdentifier`, so UI tests find every specimen on both.
enum MTComponentSpecimen: String, CaseIterable, Sendable {
  case badgeTones = "badge-tones"
  case badgeSizes = "badge-sizes"
  case badgeTags = "badge-tags"
  case badgeTruncation = "badge-truncation"
  case badgePhotoOverlay = "badge-photo-overlay"
  case buttonVariants = "button-variants"
  case buttonDisabled = "button-disabled"
  case buttonLoading = "button-loading"
  case buttonSizes = "button-sizes"
  case buttonLink = "button-link"

  /// The component the specimen shows.
  var component: String {
    switch self {
    case .badgeTones: "Badge"
    case .badgeSizes: "Badge"
    case .badgeTags: "Badge"
    case .badgeTruncation: "Badge"
    case .badgePhotoOverlay: "Badge"
    case .buttonVariants: "Button"
    case .buttonDisabled: "Button"
    case .buttonLoading: "Button"
    case .buttonSizes: "Button"
    case .buttonLink: "Button"
    }
  }

  /// What the specimen shows, from its spec's description.
  var summary: String {
    switch self {
    case .badgeTones: "Every tone at the default small size."
    case .badgeSizes:
      "Every size in the default accent tone, beside the uppercase treatment at each size."
    case .badgeTags:
      "Tags written with a leading # in Latin and CJK scripts, at the medium size Dashboard uses."
    case .badgeTruncation:
      """
      A long label and a long tag stay on one line and truncate at the tail inside a narrow \
      container.
      """
    case .badgePhotoOverlay:
      "Uppercase micro glass and inverse tones over a photo, where record cards place them."
    case .buttonVariants: "Every variant at the default medium size."
    case .buttonDisabled: "Every variant disabled, faded to the disabled opacity."
    case .buttonLoading: "Every variant loading, with the spinner before the label."
    case .buttonSizes: "Every size in the secondary variant, each with a leading icon."
    case .buttonLink: "Navigation drawn as a button, with Web ButtonLink and an iOS NavigationLink."
    }
  }

  var accessibilityIdentifier: String { "specimen-\(rawValue)" }
}
