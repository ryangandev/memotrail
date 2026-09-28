#if DEBUG
  import SwiftUI
  import UIKit

  struct NativeWritingSpecimens: View {
    @State private var text = NSAttributedString(string: "")
    @State private var savedData: Data?
    @State private var savedText: NSAttributedString?
    @State private var message: String?
    @State private var saveFailed = false
    @State private var showsSheet = false

    var body: some View {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("A little emphasis").font(MTFont.heading)
            Text("Tap Aa to show formatting. Select words, or choose a style before typing.")
              .font(MTFont.body).foregroundStyle(MTColor.inkMuted)
            MTRichTextEditor(text: $text)
            Button("Save preview", systemImage: "checkmark") { save() }
              .buttonStyle(MTActionStyle()).accessibilityIdentifier("design-save-writing")
          }
        }
        if let savedText {
          MTCard {
            VStack(alignment: .leading, spacing: MTSpacing.s3) {
              MTBadge(title: "Saved preview", tone: .success)
              MTRichTextPreview(text: savedText).accessibilityIdentifier("design-saved-writing")
              Button("Reopen saved note", systemImage: "square.and.pencil") { reopen() }
                .buttonStyle(MTActionStyle(emphasis: .secondary))
                .accessibilityIdentifier("design-reopen-writing")
            }
          }
        }
        if let message {
          MTFeedback(
            title: "Writing preview", message: message, tone: saveFailed ? .warm : .success,
            systemImage: saveFailed ? "exclamationmark.triangle" : "checkmark.circle"
          )
          .accessibilityIdentifier("design-writing-feedback")
        }
        MTCard {
          VStack(alignment: .leading, spacing: MTSpacing.s3) {
            Text("In a native sheet").font(MTFont.heading)
            Text("The same editor keeps its selection and formatting inside a form.")
              .font(MTFont.body).foregroundStyle(MTColor.inkMuted)
            Button("Open writing sheet", systemImage: "rectangle.and.pencil.and.ellipsis") {
              showsSheet = true
            }
            .buttonStyle(MTActionStyle(emphasis: .secondary))
            .accessibilityIdentifier("design-open-writing-sheet")
          }
        }
        Text("This gallery saves a local preview for this visit. It does not create an Entry.")
          .font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
      }
      .sheet(isPresented: $showsSheet) {
        NativeWritingSheet(initialText: text) { value in
          text = value
          save()
        }
      }
    }

    private func save() {
      let payload = EntryEmphasisContent(attributedText: text)
      guard payload.isValid(), let data = try? JSONEncoder().encode(payload),
        let restored = try? JSONDecoder().decode(EntryEmphasisContent.self, from: data),
        let preview = restored.attributedText()
      else {
        saveFailed = true
        message = "This note is too large to preview. Shorten it and try again."
        return
      }
      savedData = data
      saveFailed = false
      savedText = preview
      message = "Formatting saved. Reopen the note to keep writing."
    }

    private func reopen() {
      guard let savedData,
        let payload = try? JSONDecoder().decode(EntryEmphasisContent.self, from: savedData),
        let value = payload.attributedText()
      else { return }
      text = value
      message = "Saved note reopened with its formatting."
    }
  }

  private struct NativeWritingSheet: View {
    @State private var text: NSAttributedString
    let save: (NSAttributedString) -> Void
    @Environment(\.dismiss) private var dismiss

    init(initialText: NSAttributedString, save: @escaping (NSAttributedString) -> Void) {
      _text = State(initialValue: NSAttributedString(attributedString: initialText))
      self.save = save
    }

    var body: some View {
      NavigationStack {
        Form {
          Section("Entry writing") {
            MTRichTextEditor(text: $text, accessibilityIdentifier: "rich-sheet-editor")
          }
          Section {
            MTRichTextPreview(text: text)
          } header: {
            Text("Preview")
          }
        }
        .scrollContentBackground(.hidden).background(MTColor.canvas)
        .navigationTitle("Writing").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
              save(text)
              dismiss()
            }
            .disabled(!EntryEmphasisContent(attributedText: text).isValid())
          }
        }
      }
    }
  }
#endif
