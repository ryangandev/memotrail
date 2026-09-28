import SwiftUI

// Native text styles keep the shared hierarchy and follow Dynamic Type.
enum MTFont {
  static let display = Font.system(.largeTitle, design: .serif).weight(.medium)
  static let title = Font.system(.title, design: .serif).weight(.medium)
  static let heading = Font.headline
  static let body = Font.body
  static let label = Font.subheadline.weight(.medium)
  static let caption = Font.caption
}

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

struct MTBadge: View {
  let title: String
  var tone: MTTone = .neutral

  var body: some View {
    Text(title)
      .font(MTFont.caption.weight(.medium))
      .foregroundStyle(tone.foreground)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, MTSpacing.s1)
      .background(tone.background, in: Capsule())
  }
}

struct MTCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MTSpacing.s4)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border, lineWidth: 1)
      }
  }
}

struct MTPageHeader: View {
  let eyebrow: String
  let title: String
  let description: String

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text(eyebrow.uppercased())
        .font(MTFont.caption.weight(.medium))
        .tracking(1)
        .foregroundStyle(MTColor.warm)
      Text(title)
        .font(MTFont.display)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      Text(description)
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct MTActionStyle: ButtonStyle {
  enum Emphasis { case primary, secondary }
  var emphasis: Emphasis = .primary
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(MTFont.label)
      .foregroundStyle(
        isEnabled ? (emphasis == .primary ? MTColor.accentInk : MTColor.accent) : MTColor.inkFaint
      )
      .padding(.horizontal, MTSpacing.s4)
      .padding(.vertical, MTSpacing.s3)
      .frame(minHeight: 44)
      .background(
        isEnabled
          ? (emphasis == .primary ? MTColor.accent : MTColor.accentSubtle) : MTColor.surfaceSubtle,
        in: RoundedRectangle(cornerRadius: MTRadius.medium)
      )
      .opacity(configuration.isPressed && isEnabled ? 0.78 : 1)
  }
}

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

struct MTSearchField: View {
  let prompt: String
  @Binding var text: String

  var body: some View {
    HStack(spacing: MTSpacing.s2) {
      Image(systemName: "magnifyingglass").foregroundStyle(MTColor.inkMuted)
      TextField(prompt, text: $text)
        .font(MTFont.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .accessibilityLabel(prompt)
      if !text.isEmpty {
        Button("Clear search", systemImage: "xmark.circle.fill") { text = "" }
          .labelStyle(.iconOnly)
          .frame(minWidth: 44, minHeight: 44)
          .foregroundStyle(MTColor.inkMuted)
      }
    }
    .padding(.leading, MTSpacing.s3)
    .padding(.trailing, text.isEmpty ? MTSpacing.s3 : 0)
    .frame(minHeight: 48)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.medium).stroke(MTColor.border) }
  }
}

struct MTFeedback: View {
  let title: String
  let message: String
  var tone: MTTone = .neutral
  var systemImage = "info.circle"

  var body: some View {
    HStack(alignment: .top, spacing: MTSpacing.s3) {
      Image(systemName: systemImage).foregroundStyle(tone.foreground).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        Text(title).font(MTFont.heading).foregroundStyle(MTColor.ink)
        Text(message).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s3)
    .background(tone.background, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .accessibilityElement(children: .combine)
  }
}

struct MTEmptyState: View {
  let title: String
  let message: String
  let systemImage: String

  var body: some View {
    ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
      .foregroundStyle(MTColor.inkMuted)
  }
}

struct MTRecordSummary: View {
  let title: String
  let subtitle: String
  let kind: String
  var status: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      ViewThatFits(in: .horizontal) {
        badges
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          MTBadge(title: kind, tone: .accent)
          if let status { MTBadge(title: status, tone: .warm) }
        }
      }
      Text(title).font(MTFont.heading).foregroundStyle(MTColor.ink)
      Text(subtitle).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var badges: some View {
    HStack(spacing: MTSpacing.s2) {
      MTBadge(title: kind, tone: .accent)
      if let status { MTBadge(title: status, tone: .warm) }
    }
  }
}

struct MTMediaPlaceholder: View {
  enum State { case empty, loading, failed }
  let state: State
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: MTRadius.medium).fill(MTColor.surfaceSubtle)
      switch state {
      case .empty: Label("No photo", systemImage: "photo")
      case .loading: ProgressView("Loading photo...")
      case .failed: Label("Photo unavailable", systemImage: "photo.badge.exclamationmark")
      }
    }
    .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
    .accessibilityElement(children: .combine)
  }
}
