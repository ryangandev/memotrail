import SwiftUI

/// Web `Dialog` as a native sheet: an eyebrow, serif title, and optional description, a close
/// action, scrolling content, and a footer that keeps the dialog's actions in reach.
///
/// A `.form` sheet opens at full height with its close action in the navigation bar, so it can
/// push detail such as Version history. A `.fitted` sheet sizes itself to short content, like a
/// compact Web dialog, and scrolls only when the content outgrows the screen.
struct MTSheet<Content: View, Accessory: View, Footer: View>: View {
  enum Size: Sendable { case form, fitted }

  let eyebrow: String?
  let title: String
  let description: String?
  let closeLabel: String
  let closeIdentifier: String
  let size: Size
  let isBusy: Bool
  /// A failure shown above the footer actions, like Web's form alert.
  let message: String?
  private let content: Content
  private let accessory: Accessory
  private let footer: Footer

  @Environment(\.dismiss) private var dismiss
  @State private var contentHeight: CGFloat = 0
  @State private var footerHeight: CGFloat = 0

  init(
    eyebrow: String? = nil, title: String, description: String? = nil, closeLabel: String,
    closeIdentifier: String = "sheet-close", size: Size = .form, isBusy: Bool = false,
    message: String? = nil, @ViewBuilder content: () -> Content,
    @ViewBuilder accessory: () -> Accessory, @ViewBuilder footer: () -> Footer
  ) {
    self.eyebrow = eyebrow
    self.title = title
    self.description = description
    self.closeLabel = closeLabel
    self.closeIdentifier = closeIdentifier
    self.size = size
    self.isBusy = isBusy
    self.message = message
    self.content = content()
    self.accessory = accessory()
    self.footer = footer()
  }

  var body: some View {
    switch size {
    case .form: form
    case .fitted: fitted
    }
  }

  private var form: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: MTSpacing.s5) {
          header
          content
        }
        .padding(.horizontal, MTSpacing.s5)
        .padding(.bottom, MTSpacing.s6)
        .disabled(isBusy)
      }
      .scrollDismissesKeyboard(.interactively)
      .background(MTColor.surfaceRaised)
      .safeAreaInset(edge: .bottom, spacing: 0) { footerBar }
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(closeLabel, systemImage: MTIcon.close.systemName) { dismiss() }
            .disabled(isBusy)
            .accessibilityIdentifier(closeIdentifier)
        }
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isBusy)
  }

  private var fitted: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MTSpacing.s5) {
        HStack(alignment: .top, spacing: MTSpacing.s3) {
          header
          Spacer(minLength: 0)
          MTIconButton(label: closeLabel, icon: .close) { dismiss() }
            .disabled(isBusy)
            .accessibilityIdentifier(closeIdentifier)
            .padding(.trailing, -MTSpacing.s2)
        }
        content
          .disabled(isBusy)
      }
      .padding(MTSpacing.s5)
      .onGeometryChange(for: CGFloat.self) {
        $0.size.height
      } action: {
        contentHeight = $0
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollDismissesKeyboard(.interactively)
    .background(MTColor.surfaceRaised)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      footerBar
        .onGeometryChange(for: CGFloat.self) {
          $0.size.height
        } action: {
          footerHeight = $0
        }
    }
    .presentationDetents(
      contentHeight > 0 ? [.height((contentHeight + footerHeight).rounded(.up))] : [.medium]
    )
    .interactiveDismissDisabled(isBusy)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      if let eyebrow {
        Text(eyebrow)
          .font(MTFont.label.weight(.semibold))
          .foregroundStyle(MTColor.warm)
      }
      Text(title)
        .font(MTFont.sheetTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      if let description {
        Text(description)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
      }
      accessory
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  /// Web's sticky dialog footer, with any failure above the actions.
  @ViewBuilder private var footerBar: some View {
    if Footer.self != EmptyView.self || message != nil {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        if let message {
          Label(message, icon: .warning)
            .font(MTFont.caption)
            .foregroundStyle(MTColor.warm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MTSpacing.s3)
            .background(MTColor.warmSubtle, in: RoundedRectangle(cornerRadius: MTRadius.small))
            .accessibilityIdentifier("sheet-message")
        }
        footer
      }
      .disabled(isBusy)
      .padding(.horizontal, MTSpacing.s5)
      .padding(.vertical, MTSpacing.s3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.surfaceRaised)
      .overlay(alignment: .top) { Divider().overlay(MTColor.border) }
    }
  }
}

extension MTSheet where Accessory == EmptyView {
  init(
    eyebrow: String? = nil, title: String, description: String? = nil, closeLabel: String,
    closeIdentifier: String = "sheet-close", size: Size = .form, isBusy: Bool = false,
    message: String? = nil, @ViewBuilder content: () -> Content,
    @ViewBuilder footer: () -> Footer
  ) {
    self.init(
      eyebrow: eyebrow, title: title, description: description, closeLabel: closeLabel,
      closeIdentifier: closeIdentifier, size: size, isBusy: isBusy, message: message,
      content: content, accessory: { EmptyView() }, footer: footer)
  }
}

extension MTSheet where Accessory == EmptyView, Footer == EmptyView {
  init(
    eyebrow: String? = nil, title: String, description: String? = nil, closeLabel: String,
    closeIdentifier: String = "sheet-close", size: Size = .form,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      eyebrow: eyebrow, title: title, description: description, closeLabel: closeLabel,
      closeIdentifier: closeIdentifier, size: size, content: content, accessory: { EmptyView() },
      footer: { EmptyView() })
  }
}

/// A Web dialog choice: an icon tile, a title and description, and a chevron.
struct MTSheetOption: View {
  let icon: MTIcon
  let title: String
  let detail: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: MTSpacing.s4) {
        Image(icon)
          .font(.system(size: 18, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: 42, height: 42)
          .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(title)
            .font(MTFont.heading)
            .foregroundStyle(MTColor.ink)
          Text(detail)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Image(.chevron)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(MTColor.inkMuted)
          .accessibilityHidden(true)
      }
      .padding(MTSpacing.s4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(RoundedRectangle(cornerRadius: MTRadius.large))
    }
    .buttonStyle(MTSheetOptionButtonStyle())
    .accessibilityElement(children: .combine)
  }
}

private struct MTSheetOptionButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        configuration.isPressed ? MTColor.surfaceSubtle : MTColor.canvas,
        in: RoundedRectangle(cornerRadius: MTRadius.large)
      )
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
      }
  }
}
