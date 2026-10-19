import SwiftUI

// MTButtonVariant, MTButtonSize, and MTButtonDefaults are generated from
// packages/design-system/components/button.yaml, which also lists each size's tokens.
extension MTButtonSize {
  // Heights keep the Web proportions while meeting native touch-target guidance.
  fileprivate var height: CGFloat {
    switch self {
    case .small: MTSize.Control.small
    case .medium: MTSize.Control.medium
    case .large: MTSize.Control.large
    }
  }

  fileprivate var horizontalPadding: CGFloat {
    switch self {
    case .small: MTSpacing.s3
    case .medium: MTSpacing.s4
    case .large: MTSpacing.s5
    }
  }

  fileprivate var radius: CGFloat { self == .small ? MTRadius.small : MTRadius.medium }

  fileprivate var font: Font {
    switch self {
    case .small: MTFont.caption
    case .medium: MTFont.label
    case .large: MTFont.bodyEmphasis
    }
  }
}

/// The shared action style: primary, secondary, ghost, and danger variants in three sizes.
/// Pair `isLoading` with `.mtButtonStyle(_:size:isLoading:)` so the button is also disabled.
/// Specified in packages/design-system/components/button.yaml.
struct MTButtonStyle: ButtonStyle {
  var variant: MTButtonVariant = MTButtonDefaults.variant
  var size: MTButtonSize = MTButtonDefaults.size
  var isLoading = MTButtonDefaults.isLoading
  var isIconOnly = false
  var fillsWidth = MTButtonDefaults.fillsWidth
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.dynamicTypeSize) private var typeSize

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed && isEnabled
    // At accessibility text sizes a label wraps instead of truncating, like Web.
    let wraps = typeSize.isAccessibilitySize && !isIconOnly
    HStack(spacing: MTSpacing.s2) {
      if isLoading {
        ProgressView().controlSize(.small).tint(colors(pressed: pressed).foreground)
      }
      if !(isLoading && isIconOnly) {
        configuration.label
      }
    }
    .font(size.font)
    .lineLimit(wraps ? nil : 1)
    .multilineTextAlignment(.center)
    .foregroundStyle(colors(pressed: pressed).foreground)
    .padding(.horizontal, isIconOnly ? 0 : size.horizontalPadding)
    .padding(.vertical, wraps ? MTSpacing.s2 : 0)
    .frame(minWidth: isIconOnly ? size.height : nil, minHeight: size.height)
    .frame(maxWidth: fillsWidth ? .infinity : nil)
    .background(
      colors(pressed: pressed).background, in: RoundedRectangle(cornerRadius: size.radius)
    )
    .overlay {
      if let border = colors(pressed: pressed).border {
        RoundedRectangle(cornerRadius: size.radius)
          .strokeBorder(border, lineWidth: MTSize.Stroke.thin)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: size.radius))
    .opacity(isEnabled ? 1 : MTState.Disabled.Opacity.button)
    .animation(MTEasing.standard.animation(duration: MTMotion.quick), value: pressed)
  }

  private func colors(pressed: Bool) -> (foreground: Color, background: Color, border: Color?) {
    switch variant {
    case .primary:
      (MTColor.accentInk, pressed ? MTState.Hover.primary : MTColor.accent, nil)
    case .secondary:
      pressed
        ? (MTColor.accent, MTState.Hover.accentSurface, MTColor.accent)
        : (MTColor.inkMuted, MTColor.surfaceRaised, MTColor.borderStrong)
    case .ghost:
      pressed
        ? (MTState.Hover.ink, MTState.Hover.surface, nil)
        : (MTColor.inkMuted, .clear, nil)
    case .danger:
      (MTColor.danger, MTColor.dangerSubtle, pressed ? MTColor.danger : MTColor.dangerBorder)
    }
  }
}

extension View {
  /// Applies `MTButtonStyle`, disabling the button and announcing progress while loading.
  func mtButtonStyle(
    _ variant: MTButtonVariant = MTButtonDefaults.variant,
    size: MTButtonSize = MTButtonDefaults.size,
    isLoading: Bool = MTButtonDefaults.isLoading,
    fillsWidth: Bool = MTButtonDefaults.fillsWidth
  ) -> some View {
    buttonStyle(
      MTButtonStyle(variant: variant, size: size, isLoading: isLoading, fillsWidth: fillsWidth)
    )
    .disabled(isLoading)
    .accessibilityValue(isLoading ? Text("In progress") : Text(""))
  }
}

// MTIconButtonVariant, MTIconButtonSize, and MTIconButtonDefaults are generated from
// packages/design-system/components/icon-button.yaml. Each draws as the Button value it names.
extension MTButtonVariant {
  fileprivate init(_ variant: MTIconButtonVariant) {
    switch variant {
    case .primary: self = .primary
    case .secondary: self = .secondary
    case .ghost: self = .ghost
    case .danger: self = .danger
    }
  }
}

extension MTButtonSize {
  fileprivate init(_ size: MTIconButtonSize) {
    switch size {
    case .small: self = .small
    case .medium: self = .medium
    case .large: self = .large
    }
  }
}

/// A square icon action with a required accessibility label, ghost unless a variant is given.
/// Specified in packages/design-system/components/icon-button.yaml.
struct MTIconButton: View {
  let label: String
  let icon: MTIcon
  var variant: MTIconButtonVariant = MTIconButtonDefaults.variant
  var size: MTIconButtonSize = MTIconButtonDefaults.size
  var isLoading = MTIconButtonDefaults.isLoading
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(icon).font(.mtIcon(size == .small ? MTSize.Icon.s14 : MTSize.Icon.s17, weight: .medium))
    }
    .buttonStyle(
      MTButtonStyle(
        variant: MTButtonVariant(variant), size: MTButtonSize(size), isLoading: isLoading,
        isIconOnly: true)
    )
    .disabled(isLoading)
    .accessibilityLabel(label)
  }
}

/// A selectable filter pill used for Kind, year, and other single-choice filters.
struct MTFilterChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(MTFont.label)
        .foregroundStyle(isSelected ? MTColor.accentInk : MTColor.inkMuted)
        .padding(.horizontal, MTSpacing.s3)
        .padding(.vertical, MTSpacing.s2)
        .frame(minHeight: MTSize.hitTarget)
        .background(isSelected ? MTColor.accent : MTColor.surfaceSubtle, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
