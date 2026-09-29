import SwiftUI
import UIKit

/// Native writing surface. The binding contains formatting as well as readable plaintext.
struct MTRichTextEditor: View {
  @Binding var text: NSAttributedString
  var placeholder = "Write a note..."
  var accessibilityIdentifier = "rich-editor"
  /// Embedded editors sit inside a host card that already draws the surface and border.
  var isEmbedded = false
  var minimumHeight = 180.0
  /// Each increase moves keyboard focus into the editor; a positive start focuses on appear.
  var focusRequest = 0
  @State private var session = NativeRichTextSession()
  @State private var showsFormatting = false
  @ScaledMetric private var scale = 1.0
  private var editorHeight: Double { minimumHeight * scale }

  var body: some View {
    VStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        NativeAttributedTextView(
          text: $text, session: session, identifier: accessibilityIdentifier,
          focusRequest: focusRequest
        )
        .frame(height: min(editorHeight, 300))
        if text.length == 0 {
          Text(placeholder).font(MTFont.bodyLarge).foregroundStyle(MTColor.inkMuted)
            .padding(.horizontal, 12).padding(.top, 12).allowsHitTesting(false)
        }
      }
      if showsFormatting {
        Divider().overlay(MTColor.border)
        ScrollView(.horizontal) {
          HStack(spacing: 4) {
            ForEach(EmphasisStyle.allCases, id: \.self) { style in
              Button {
                session.toggle(style)
              } label: {
                Image(systemName: style.symbol).font(.system(size: 18, weight: .medium))
                  .frame(width: 44, height: 44)
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
            Divider().frame(height: 24).padding(.horizontal, 4)
            Button {
              session.clearFormatting()
            } label: {
              Image(systemName: "eraser").frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).foregroundStyle(MTColor.inkMuted)
            .accessibilityLabel("Clear formatting").accessibilityIdentifier("rich-format-clear")
            .help("Clear formatting")
            .disabled(session.isComposing)
          }.font(.system(size: 18)).padding(.horizontal, 8).padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("rich-format-toolbar")
      }
      Divider().overlay(MTColor.border)
      HStack(spacing: 4) {
        Button {
          showsFormatting.toggle()
        } label: {
          Text("Aa").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
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
          Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
        }
        .disabled(!session.canUndo).accessibilityLabel("Undo").accessibilityIdentifier("rich-undo")
        Button {
          session.redo()
        } label: {
          Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44)
        }
        .disabled(!session.canRedo).accessibilityLabel("Redo").accessibilityIdentifier("rich-redo")
        Button {
          session.dismissKeyboard()
        } label: {
          Image(systemName: "keyboard.chevron.compact.down").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Dismiss keyboard").accessibilityIdentifier("rich-dismiss-keyboard")
      }
      .font(.system(size: 18)).buttonStyle(.plain).foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, 8)
    }
    .background(isEmbedded ? Color.clear : MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: isEmbedded ? 0 : MTRadius.medium))
    .overlay {
      if !isEmbedded {
        RoundedRectangle(cornerRadius: MTRadius.medium).stroke(MTColor.border, lineWidth: 1)
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
      var font = Font.body
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
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func makeUIView(context: Context) -> UITextView {
    let view = UITextView()
    view.backgroundColor = .clear
    view.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
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
    if focusRequest > 0 { DispatchQueue.main.async { view.becomeFirstResponder() } }
    return view
  }

  func updateUIView(_ view: UITextView, context: Context) {
    context.coordinator.parent = self
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
