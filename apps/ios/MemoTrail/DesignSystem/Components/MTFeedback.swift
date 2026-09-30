import SwiftUI

/// An inline status message with a tone, used for validation, drafts, and connection notes.
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

/// A calm empty or filtered state. Supply actions, or `onTap` to make the whole state one action.
struct MTEmptyState<Actions: View>: View {
  let title: String
  var message: String?
  var systemImage: String?
  var onTap: (() -> Void)?
  private let actions: Actions

  init(
    title: String, message: String? = nil, icon: MTIcon? = nil, onTap: (() -> Void)? = nil,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.message = message
    systemImage = icon?.systemName
    self.onTap = onTap
    self.actions = actions()
  }

  var body: some View {
    if let onTap {
      Button(action: onTap) { content }
        .buttonStyle(MTEmptyStateButtonStyle())
    } else {
      content.overlay { shape.stroke(MTColor.border, lineWidth: 1) }
    }
  }

  private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: MTRadius.large) }

  private var content: some View {
    VStack(spacing: MTSpacing.s3) {
      if let systemImage {
        Image(systemName: systemImage)
          .font(.system(size: 22, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 48, height: 48)
          .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
          .accessibilityHidden(true)
      }
      Text(title)
        .font(MTFont.cardTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(onTap == nil ? .isHeader : [])
      if let message {
        Text(message)
          .font(MTFont.label.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body, textStyle: .footnote)
          .frame(maxWidth: 480)
      }
      HStack(spacing: MTSpacing.s2) { actions }
        .padding(.top, MTSpacing.s1)
    }
    .multilineTextAlignment(.center)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s6)
    .background(MTColor.surface, in: shape)
    .accessibilityElement(children: .contain)
  }
}

extension MTEmptyState where Actions == EmptyView {
  init(title: String, message: String? = nil, icon: MTIcon? = nil, onTap: (() -> Void)? = nil) {
    self.init(title: title, message: message, icon: icon, onTap: onTap) { EmptyView() }
  }

  init(title: String, message: String, systemImage: String) {
    self.init(title: title, message: message) { EmptyView() }
    self.systemImage = systemImage
  }
}

private struct MTEmptyStateButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(configuration.isPressed ? MTColor.accent : MTColor.border, lineWidth: 1)
      }
      .animation(.easeOut(duration: MTMotion.quick), value: configuration.isPressed)
  }
}

/// Loads the next page when the end of a list comes into view, or offers a retry.
struct MTLoadMore: View {
  let isLoading: Bool
  let message: String?
  let load: @MainActor () async -> Void

  var body: some View {
    if let message, !isLoading {
      HStack(spacing: MTSpacing.s3) {
        Label(message, icon: .warning)
          .font(MTFont.caption)
          .foregroundStyle(MTColor.warm)
        Spacer(minLength: 0)
        Button("Try again") { Task { await load() } }
          .mtButtonStyle(.secondary, size: .small)
      }
    } else {
      ProgressView()
        .tint(MTColor.accent)
        .frame(maxWidth: .infinity, minHeight: 44)
        .onAppear { Task { await load() } }
        .accessibilityLabel("Loading more")
    }
  }
}
