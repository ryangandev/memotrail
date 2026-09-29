import SwiftUI

enum MTButtonVariant: CaseIterable, Sendable {
  case primary, secondary, ghost, danger

  var title: String {
    switch self {
    case .primary: "primary"
    case .secondary: "secondary"
    case .ghost: "ghost"
    case .danger: "danger"
    }
  }
}

enum MTButtonSize: CaseIterable, Sendable {
  case small, medium, large

  var title: String {
    switch self {
    case .small: "small"
    case .medium: "medium"
    case .large: "large"
    }
  }

  // Heights keep the Web proportions while meeting native touch-target guidance.
  fileprivate var height: CGFloat {
    switch self {
    case .small: 34
    case .medium: 44
    case .large: 52
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
    case .large: MTFont.body.weight(.medium)
    }
  }
}

/// The shared action style: primary, secondary, ghost, and danger variants in three sizes.
/// Pair `isLoading` with `.mtButtonStyle(_:size:isLoading:)` so the button is also disabled.
struct MTButtonStyle: ButtonStyle {
  var variant: MTButtonVariant = .primary
  var size: MTButtonSize = .medium
  var isLoading = false
  var isIconOnly = false
  var fillsWidth = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed && isEnabled
    HStack(spacing: MTSpacing.s2) {
      if isLoading {
        ProgressView().controlSize(.small).tint(colors(pressed: pressed).foreground)
      }
      if !(isLoading && isIconOnly) {
        configuration.label
      }
    }
    .font(size.font)
    .lineLimit(1)
    .foregroundStyle(colors(pressed: pressed).foreground)
    .padding(.horizontal, isIconOnly ? 0 : size.horizontalPadding)
    .frame(minWidth: isIconOnly ? size.height : nil, minHeight: size.height)
    .frame(maxWidth: fillsWidth ? .infinity : nil)
    .background(
      colors(pressed: pressed).background, in: RoundedRectangle(cornerRadius: size.radius)
    )
    .overlay {
      if let border = colors(pressed: pressed).border {
        RoundedRectangle(cornerRadius: size.radius).stroke(border, lineWidth: 1)
      }
    }
    .contentShape(RoundedRectangle(cornerRadius: size.radius))
    .opacity(isEnabled ? 1 : 0.5)
    .animation(.easeOut(duration: MTMotion.quick), value: pressed)
  }

  private func colors(pressed: Bool) -> (foreground: Color, background: Color, border: Color?) {
    switch variant {
    case .primary:
      (MTColor.accentInk, pressed ? MTColor.accentHover : MTColor.accent, nil)
    case .secondary:
      pressed
        ? (MTColor.accent, MTColor.accentSubtle, MTColor.accent)
        : (MTColor.inkMuted, MTColor.surfaceRaised, MTColor.borderStrong)
    case .ghost:
      (pressed ? MTColor.ink : MTColor.inkMuted, pressed ? MTColor.surfaceSubtle : .clear, nil)
    case .danger:
      (MTColor.warm, MTColor.warmSubtle, pressed ? MTColor.warm : MTColor.warm.opacity(0.34))
    }
  }
}

extension View {
  /// Applies `MTButtonStyle`, disabling the button and announcing progress while loading.
  func mtButtonStyle(
    _ variant: MTButtonVariant = .primary, size: MTButtonSize = .medium, isLoading: Bool = false,
    fillsWidth: Bool = false
  ) -> some View {
    buttonStyle(
      MTButtonStyle(variant: variant, size: size, isLoading: isLoading, fillsWidth: fillsWidth)
    )
    .disabled(isLoading)
    .accessibilityValue(isLoading ? Text("In progress") : Text(""))
  }
}

/// A square icon action with a required accessibility label.
struct MTIconButton: View {
  let label: String
  let icon: MTIcon
  var variant: MTButtonVariant = .ghost
  var size: MTButtonSize = .medium
  var isLoading = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(icon).font(.system(size: size == .small ? 14 : 17, weight: .medium))
    }
    .buttonStyle(
      MTButtonStyle(variant: variant, size: size, isLoading: isLoading, isIconOnly: true)
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
        .frame(minHeight: 44)
        .background(isSelected ? MTColor.accent : MTColor.surfaceSubtle, in: Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
