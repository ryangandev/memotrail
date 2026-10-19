import SwiftUI
import UIKit

/// Web `RichTextEditor`: the native writing surface with its emphasis, undo, and keyboard
/// actions. The binding contains formatting as well as readable plaintext. The form variant is
/// a bordered field; the embedded variant sits inside a host card that already draws the
/// surface. Specified in packages/design-system/components/rich-text.yaml.
struct MTRichTextEditor: View {
  @Binding var text: NSAttributedString
  var placeholder = "Write a note..."
  var accessibilityIdentifier = "rich-editor"
  var variant = MTRichTextDefaults.variant
  var minimumHeight = MTLayout.RichText.minHeight
  /// Each increase moves keyboard focus into the editor; a positive start focuses on appear.
  var focusRequest = 0
  /// Runs on Command-Return from a hardware keyboard, like Web's form shortcut.
  var onSubmit: (@MainActor () -> Void)? = nil
  @State private var session = NativeRichTextSession()
  @State private var showsFormatting = false
  @ScaledMetric private var scale = 1.0
  private var editorHeight: Double { minimumHeight * scale }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        NativeAttributedTextView(
          text: $text, session: session, identifier: accessibilityIdentifier,
          focusRequest: focusRequest, onSubmit: onSubmit
        )
        .frame(height: min(editorHeight, MTLayout.RichText.maxHeight))
        if text.length == 0 {
          Text(placeholder).font(MTFont.bodyLarge).foregroundStyle(MTColor.inkMuted)
            .padding(.horizontal, MTLayout.RichText.placeholderInset)
            .padding(.top, MTLayout.RichText.verticalInset).allowsHitTesting(false)
        }
      }
      if showsFormatting {
        Divider().overlay(MTColor.border)
        ScrollView(.horizontal) {
          HStack(spacing: MTSpacing.s1) {
            ForEach(EmphasisStyle.allCases, id: \.self) { style in
              Button {
                session.toggle(style)
              } label: {
                Image(systemName: style.symbol).font(.mtIcon(MTSize.Icon.s18, weight: .medium))
                  .frame(width: MTSize.hitTarget, height: MTSize.hitTarget)
                  .background(
                    session.styles.contains(style) ? MTColor.accentSubtle : .clear,
                    in: RoundedRectangle(cornerRadius: MTRadius.small))
              }
              .buttonStyle(.plain).foregroundStyle(MTColor.ink)
              .accessibilityLabel(style.title)
              .accessibilityValue(session.styles.contains(style) ? "On" : "Off")
              .accessibilityAddTraits(session.styles.contains(style) ? .isSelected : [])
              .accessibilityIdentifier("rich-format-\(style.rawValue)")
              .disabled(session.isComposing)
            }
            Divider().frame(height: MTLayout.RichText.toolbarDivider).padding(
              .horizontal, MTSpacing.s1)
            Button {
              session.clearFormatting()
            } label: {
              Image(systemName: "eraser").frame(width: MTSize.hitTarget, height: MTSize.hitTarget)
            }
            .buttonStyle(.plain).foregroundStyle(MTColor.inkMuted)
            .accessibilityLabel("Clear formatting").accessibilityIdentifier("rich-format-clear")
            .help("Clear formatting")
            .disabled(session.isComposing)
          }.font(.mtIcon(MTSize.Icon.s18)).padding(.horizontal, MTSpacing.s2)
            .padding(.vertical, MTSpacing.s1)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("rich-format-toolbar")
      }
      Divider().overlay(MTColor.border)
      HStack(spacing: MTSpacing.s1) {
        Button {
          showsFormatting.toggle()
        } label: {
          Text("Aa").font(.mtIcon(MTSize.Icon.s18, weight: .semibold)).frame(
            width: MTSize.hitTarget, height: MTSize.hitTarget
          )
          .background(
            showsFormatting ? MTColor.accentSubtle : .clear,
            in: RoundedRectangle(cornerRadius: MTRadius.small))
        }
        .accessibilityLabel(showsFormatting ? "Hide formatting" : "Show formatting")
        .accessibilityValue(showsFormatting ? "Expanded" : "Collapsed")
        .accessibilityIdentifier("rich-format-toggle")
        Spacer(minLength: 0)
        Button {
          session.undo()
        } label: {
          Image(systemName: "arrow.uturn.backward").frame(
            width: MTSize.hitTarget, height: MTSize.hitTarget)
        }
        .disabled(!session.canUndo).accessibilityLabel("Undo").accessibilityIdentifier("rich-undo")
        Button {
          session.redo()
        } label: {
          Image(systemName: "arrow.uturn.forward").frame(
            width: MTSize.hitTarget, height: MTSize.hitTarget)
        }
        .disabled(!session.canRedo).accessibilityLabel("Redo").accessibilityIdentifier("rich-redo")
        Button {
          session.dismissKeyboard()
        } label: {
          Image(systemName: "keyboard.chevron.compact.down").frame(
            width: MTSize.hitTarget, height: MTSize.hitTarget)
        }
        .accessibilityLabel("Dismiss keyboard").accessibilityIdentifier("rich-dismiss-keyboard")
      }
      .font(.mtIcon(MTSize.Icon.s18)).buttonStyle(.plain).foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, MTSpacing.s2)
    }
    .background(variant == .form ? MTColor.surface : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: variant == .form ? MTRadius.medium : 0))
    .overlay {
      switch variant {
      case .form:
        RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
          MTColor.borderStrong, lineWidth: MTSize.Stroke.thin)
      case .embedded: EmptyView()
      }
    }
  }
}

struct MTRichTextPreview: View {
  let text: NSAttributedString
  var body: some View {
    Text(content).font(MTFont.bodyLarge).foregroundStyle(MTColor.ink)
      .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
  }

  private var content: AttributedString {
    var result = AttributedString()
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) {
      attributes, range, _ in
      var run = AttributedString(text.attributedSubstring(from: range))
      var font = MTFont.bodyLarge
      if EmphasisStyle.bold.isApplied(to: attributes) { font = font.bold() }
      if EmphasisStyle.italic.isApplied(to: attributes) { font = font.italic() }
      run.font = font
      result.append(run)
    }
    return result
  }
}

@Observable @MainActor
final class NativeRichTextSession {
  private(set) var styles: Set<EmphasisStyle> = []
  private(set) var canUndo = false
  private(set) var canRedo = false
  private(set) var isComposing = false
  @ObservationIgnored weak var view: UITextView?
  @ObservationIgnored var onChange: (NSAttributedString) -> Void = { _ in }

  func refresh() {
    guard let view else { return }
    isComposing = view.markedTextRange != nil
    let range = view.selectedRange
    styles = Set(
      EmphasisStyle.allCases.filter { style in
        if range.length == 0 { return style.isApplied(to: view.typingAttributes) }
        var all = true
        view.attributedText.enumerateAttributes(in: range) { attributes, _, _ in
          if !style.isApplied(to: attributes) { all = false }
        }
        return all
      })
    canUndo = view.undoManager?.canUndo ?? false
    canRedo = view.undoManager?.canRedo ?? false
  }

  func toggle(_ style: EmphasisStyle) {
    refresh()
    let enabled = !styles.contains(style)
    format { attributes, font in style.apply(enabled, to: &attributes, baseFont: font) }
  }

  func clearFormatting() {
    format { attributes, font in
      for style in EmphasisStyle.allCases { style.apply(false, to: &attributes, baseFont: font) }
    }
  }

  func undo() {
    view?.undoManager?.undo()
    publish()
  }
  func redo() {
    view?.undoManager?.redo()
    publish()
  }
  func dismissKeyboard() { view?.resignFirstResponder() }

  func publish() {
    guard let view, view.markedTextRange == nil else {
      refresh()
      return
    }
    onChange(NSAttributedString(attributedString: view.attributedText))
    refresh()
  }

  private struct Snapshot {
    let text: NSAttributedString
    let selection: NSRange
    let typing: [NSAttributedString.Key: Any]
  }

  private func snapshot(_ view: UITextView) -> Snapshot {
    Snapshot(
      text: NSAttributedString(attributedString: view.attributedText),
      selection: view.selectedRange, typing: view.typingAttributes)
  }

  private func registerUndo(_ value: Snapshot) {
    view?.undoManager?.registerUndo(withTarget: self) { session in
      MainActor.assumeIsolated { session.restore(value) }
    }
    view?.undoManager?.setActionName("Formatting")
  }

  private func restore(_ value: Snapshot) {
    guard let view else { return }
    registerUndo(snapshot(view))
    view.textStorage.setAttributedString(value.text)
    view.selectedRange = value.selection
    view.typingAttributes = value.typing
    publish()
  }

  private func format(_ change: (inout [NSAttributedString.Key: Any], UIFont) -> Void) {
    guard let view, view.markedTextRange == nil else { return }
    let before = snapshot(view)
    let range = view.selectedRange
    let font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: view.traitCollection)
    registerUndo(before)
    if range.length > 0 {
      let result = NSMutableAttributedString(attributedString: view.attributedText)
      result.enumerateAttributes(in: range) { value, run, _ in
        var attributes = value
        change(&attributes, font)
        result.setAttributes(attributes, range: run)
      }
      view.textStorage.setAttributedString(result)
      view.selectedRange = range
    } else {
      var attributes = view.typingAttributes
      change(&attributes, font)
      view.typingAttributes = attributes
    }
    // SwiftUI toolbar buttons do not take first responder or change the selected text.
    view.becomeFirstResponder()
    publish()
  }
}

private struct NativeAttributedTextView: UIViewRepresentable {
  @Binding var text: NSAttributedString
  let session: NativeRichTextSession
  let identifier: String
  let focusRequest: Int
  let onSubmit: (@MainActor () -> Void)?
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func makeUIView(context: Context) -> NativeRichTextView {
    let view = NativeRichTextView()
    view.backgroundColor = .clear
    view.textContainerInset = UIEdgeInsets(
      top: MTLayout.RichText.verticalInset, left: MTLayout.RichText.horizontalInset,
      bottom: MTLayout.RichText.verticalInset, right: MTLayout.RichText.horizontalInset)
    view.font = context.coordinator.font(for: dynamicTypeSize)
    view.adjustsFontForContentSizeCategory = true
    view.allowsEditingTextAttributes = true
    view.attributedText = context.coordinator.resized(text, font: view.font!)
    view.typingAttributes = [.font: view.font!, .foregroundColor: UIColor.label]
    view.accessibilityLabel = "Note"
    view.accessibilityIdentifier = identifier
    view.delegate = context.coordinator
    session.view = view
    context.coordinator.parent = self
    session.onChange = { text = $0 }
    context.coordinator.focusRequest = focusRequest
    view.submit = { [weak coordinator = context.coordinator] in coordinator?.parent.onSubmit?() }
    // A view made for a presentation is not in a window yet, so it takes focus once it is.
    view.focusesInWindow = focusRequest > 0
    return view
  }

  func updateUIView(_ view: NativeRichTextView, context: Context) {
    context.coordinator.parent = self
    view.hasSubmit = onSubmit != nil
    session.onChange = { text = $0 }
    if focusRequest != context.coordinator.focusRequest {
      context.coordinator.focusRequest = focusRequest
      view.becomeFirstResponder()
    }
    // Do not replace marked text while an input method is composing Chinese or another language.
    guard view.markedTextRange == nil else { return }
    let font = context.coordinator.font(for: dynamicTypeSize)
    let value = context.coordinator.resized(text, font: font)
    if !view.attributedText.isEqual(to: value) {
      context.coordinator.isUpdating = true
      defer { context.coordinator.isUpdating = false }
      let range = view.selectedRange
      let typing = view.typingAttributes
      view.textStorage.setAttributedString(value)
      view.selectedRange = NSRange(
        location: min(range.location, value.length),
        length: min(range.length, max(0, value.length - range.location)))
      var attributes = typing
      context.coordinator.resizeFont(&attributes, font: font)
      view.typingAttributes = attributes
      DispatchQueue.main.async { [weak session] in session?.refresh() }
    }
  }

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: NativeAttributedTextView
    var isUpdating = false
    var focusRequest = 0
    init(_ parent: NativeAttributedTextView) { self.parent = parent }
    func textViewDidChange(_ textView: UITextView) { parent.session.publish() }
    func textViewDidChangeSelection(_ textView: UITextView) {
      if !isUpdating { parent.session.refresh() }
    }

    func font(for size: DynamicTypeSize) -> UIFont {
      let category: UIContentSizeCategory
      switch size {
      case .xSmall: category = .extraSmall
      case .small: category = .small
      case .medium: category = .medium
      case .large: category = .large
      case .xLarge: category = .extraLarge
      case .xxLarge: category = .extraExtraLarge
      case .xxxLarge: category = .extraExtraExtraLarge
      case .accessibility1: category = .accessibilityMedium
      case .accessibility2: category = .accessibilityLarge
      case .accessibility3: category = .accessibilityExtraLarge
      case .accessibility4: category = .accessibilityExtraExtraLarge
      case .accessibility5: category = .accessibilityExtraExtraExtraLarge
      @unknown default: category = .large
      }
      return .preferredFont(
        forTextStyle: .body,
        compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    }

    func resizeFont(_ attributes: inout [NSAttributedString.Key: Any], font: UIFont) {
      let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
      attributes[.font] = UIFont(
        descriptor: font.fontDescriptor.withSymbolicTraits(traits)
          ?? font.fontDescriptor, size: font.pointSize)
      attributes[.foregroundColor] = UIColor.label
    }

    func resized(_ value: NSAttributedString, font: UIFont) -> NSAttributedString {
      let result = NSMutableAttributedString(attributedString: value)
      value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { value, range, _ in
        var attributes = value
        resizeFont(&attributes, font: font)
        result.setAttributes(attributes, range: range)
      }
      return result
    }
  }
}

/// The editor's text view: takes focus as soon as it reaches a window, and offers Command-Return
/// to the composer that hosts it.
final class NativeRichTextView: UITextView {
  /// Whether the view should take keyboard focus once it is in a window.
  var focusesInWindow = false
  var hasSubmit = false
  var submit: @MainActor () -> Void = {}
  private var focusAttempts = 0

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil, focusesInWindow else { return }
    focusAttempts = 0
    takeFocus()
  }

  /// A presentation still moving in can refuse first responder, so a refused focus tries again
  /// briefly, the way a person would tap the field once it settles.
  private func takeFocus() {
    guard focusesInWindow, window != nil else { return }
    if isFirstResponder || becomeFirstResponder() {
      focusesInWindow = false
      return
    }
    focusAttempts += 1
    guard focusAttempts < 10 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.takeFocus() }
  }

  override var keyCommands: [UIKeyCommand]? {
    guard hasSubmit else { return super.keyCommands }
    let save = UIKeyCommand(
      title: "Save", action: #selector(submitFromKeyboard), input: "\r", modifierFlags: .command)
    save.wantsPriorityOverSystemBehavior = true
    return (super.keyCommands ?? []) + [save]
  }

  /// Save is claimed explicitly, so Command-Return does not depend on how UITextView answers
  /// for an action that is not one of its own editing actions.
  override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    if action == #selector(submitFromKeyboard) { return hasSubmit }
    return super.canPerformAction(action, withSender: sender)
  }

  @objc func submitFromKeyboard() {
    // Like Web, a composition in progress is never saved half-typed.
    guard markedTextRange == nil else { return }
    submit()
  }
}
