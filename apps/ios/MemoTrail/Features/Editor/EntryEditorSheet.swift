@preconcurrency import Supabase
import SwiftUI

// P3: the full Entry editor (photos, date model, tag suggestions, Location preview).

/// What the editor opens with, like Web `NewEntryDialog` and `EntryEditorDialog`.
enum EntryEditorMode: Equatable {
  /// A new Entry that starts with these marks, such as a Chapter added from Timeline.
  case new(EntryMarks)
  /// The current version of a saved Entry, from `EntryAPI.editable(_:)`.
  case edit(EditableEntry)
}

/// What changed when the editor closed after a save or Move to Trash.
enum EntryEditorResult: Equatable {
  case saved(SavedEntry)
  case movedToTrash(UUID)
}

/// Web `EntryEditorDialog`: title, Chapter and First Time marks, note, date, tags, photo
/// suggestions, and the Entry's Location, saved with `save_entry`.
struct EntryEditorSheet: View {
  let client: SupabaseClient
  let ownerID: UUID
  let mode: EntryEditorMode
  let onSaved: @MainActor (EntryEditorResult) -> Void

  @Environment(\.dismiss) private var dismiss
  /// Drafted once, so a retried save of a new Entry cannot add it twice.
  @State private var entryID: UUID
  @State private var title: String
  @State private var note: NSAttributedString
  @State private var isChapter: Bool
  @State private var isFirstTime: Bool
  @State private var occurrence: OccurrenceDraft
  @State private var tagNames: [String]
  @State private var tagOptions: [String] = []
  @State private var keepsLocation = true
  @State private var photoLocation: PhotoLocationDraft?
  @State private var isSaving = false
  @State private var isTrashing = false
  @State private var isConfirmingTrash = false
  @State private var errorMessage: String?
  /// The note as it opened, to tell an untouched note from an edited one.
  private let openingNote: NSAttributedString
  /// Web writing with quotes, lists, code, or links that the native editor cannot keep.
  private let hasWebOnlyFormatting: Bool

  init(
    client: SupabaseClient, ownerID: UUID, mode: EntryEditorMode,
    onSaved: @escaping @MainActor (EntryEditorResult) -> Void = { _ in }
  ) {
    self.client = client
    self.ownerID = ownerID
    self.mode = mode
    self.onSaved = onSaved
    let timezone = TimeZone.current.identifier
    switch mode {
    case .new(let marks):
      _entryID = State(initialValue: UUID())
      _title = State(initialValue: "")
      openingNote = NSAttributedString()
      hasWebOnlyFormatting = false
      _isChapter = State(initialValue: marks.isChapter)
      _isFirstTime = State(initialValue: marks.isFirstTime)
      _occurrence = State(
        initialValue: OccurrenceDraft(
          EntryOccurrence(
            precision: .unknown, start: nil, end: nil, label: nil, timezone: timezone)))
      _tagNames = State(initialValue: [])
    case .edit(let entry):
      _entryID = State(initialValue: entry.id)
      _title = State(initialValue: entry.title ?? "")
      let editable = entry.richText.flatMap(EntryEmphasisContent.init)
      openingNote = editable?.attributedText() ?? NSAttributedString(string: entry.body)
      hasWebOnlyFormatting = entry.richText != nil && editable == nil
      _isChapter = State(initialValue: entry.marks.isChapter)
      _isFirstTime = State(initialValue: entry.marks.isFirstTime)
      _occurrence = State(
        initialValue: OccurrenceDraft(
          entry.occurrence(fallbackTimezone: timezone), undatedTimezone: timezone))
      _tagNames = State(initialValue: entry.tagNames)
    }
    _note = State(initialValue: openingNote)
  }

  private var editing: EditableEntry? {
    if case .edit(let entry) = mode { entry } else { nil }
  }

  private var isBusy: Bool { isSaving || isTrashing }

  private var heading: String {
    guard editing == nil else { return "Edit Entry" }
    return isChapter ? "Add a Chapter" : isFirstTime ? "Add a First Time" : "Add an Entry"
  }

  var body: some View {
    MTSheet(
      eyebrow: editing == nil ? "New Entry" : "Entry", title: heading,
      closeLabel: "Close Entry editor", closeIdentifier: "editor-close", isBusy: isBusy,
      message: errorMessage
    ) {
      MTTextField(
        label: "Title", text: $title, prompt: isChapter ? "Name this Chapter" : "Add a title",
        isRequired: isChapter, maxLength: EntryLimits.title
      )
      .accessibilityIdentifier("editor-title")
      VStack(alignment: .leading, spacing: 0) {
        MTCheckbox(
          title: "Chapter",
          detail: "A stretch of your life, like a home, a job, or a school year.",
          isOn: $isChapter
        )
        .accessibilityIdentifier("editor-chapter")
        MTCheckbox(
          title: "First Time", detail: "The first time you did something.", isOn: $isFirstTime
        )
        .accessibilityIdentifier("editor-first-time")
      }
      noteField
      OccurrenceEditor(value: $occurrence, span: isChapter)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: tagOptions)
      if let location = editing?.primaryLocation, keepsLocation {
        locationField(location)
      }
      if let editing {
        EntryPhotoDatesView(
          client: client, ownerID: ownerID, entryID: editing.id, occurrence: $occurrence,
          photoLocation: $photoLocation)
      }
    } footer: {
      footer
    }
    .task { await loadTagOptions() }
  }

  private var noteField: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Note")
      MTRichTextEditor(
        text: $note, placeholder: "Write what you want to remember",
        accessibilityIdentifier: "editor-body", minimumHeight: MTLayout.RichText.reviewMinHeight)
      if hasWebOnlyFormatting {
        Text(
          "Lists, quotes, links, and code from the web stay as they are unless you edit this note here."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkFaint)
      }
    }
  }

  private func locationField(_ location: EntryLocation) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Location")
      HStack(spacing: MTSpacing.s3) {
        Label(location.label, icon: .map)
          .font(MTFont.body)
          .foregroundStyle(MTColor.ink)
        Spacer(minLength: 0)
        Button("Remove") { keepsLocation = false }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityIdentifier("editor-remove-location")
      }
    }
  }

  @ViewBuilder private var footer: some View {
    HStack(spacing: MTSpacing.s2) {
      if editing != nil {
        Button {
          isConfirmingTrash = true
        } label: {
          Label("Move to Trash", icon: .trash)
        }
        .mtButtonStyle(.ghost, isLoading: isTrashing)
        .accessibilityIdentifier("editor-trash")
        .entryTrashConfirmation(editing?.displayTitle ?? "", isPresented: $isConfirmingTrash) {
          Task { await trash() }
        }
      }
      Spacer(minLength: 0)
      Button("Cancel") { dismiss() }
        .mtButtonStyle(.secondary)
      Button(isSaving ? "Saving…" : editing == nil ? "Add" : "Save changes") {
        Task { await save() }
      }
      .mtButtonStyle(isLoading: isSaving)
      .accessibilityIdentifier("editor-save")
    }
  }

  /// The saved note: an untouched note keeps its original document, including Web-only
  /// structure; an edited note saves the editor's formatting.
  private func noteDraft() -> (body: String, rich: EntryRichText?) {
    let current = EntryEmphasisContent.capture(note)
    if let editing, current == EntryEmphasisContent.capture(openingNote) {
      return (editing.body, editing.richText)
    }
    return (current.body, current.rich.flatMap(EntryRichText.init))
  }

  private func loadTagOptions() async {
    tagOptions = (try? await EntryAPI(client: client, ownerID: ownerID).tagOptions()) ?? []
  }

  @MainActor
  private func save() async {
    guard !isBusy else { return }
    let marks = EntryMarks(isChapter: isChapter, isFirstTime: isFirstTime)
    let parameters: SaveEntryParameters
    do {
      let resolved = try occurrence.resolve(
        original: editing?.occurrence(fallbackTimezone: occurrence.timezone), span: isChapter)
      let note = noteDraft()
      parameters = try SaveEntryParameters(
        entryID: entryID, expectedRevision: editing?.revision, title: title, body: note.body,
        richText: note.rich, occurrence: resolved,
        tagNames: tagNames.map { existingTagName($0, options: tagOptions) },
        location: keepsLocation ? editing?.primaryLocation : nil,
        photoLocation: editing == nil ? nil : photoLocation, marks: marks)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    do {
      let saved = try await EntryAPI(client: client, ownerID: ownerID).save(parameters)
      MTToastCenter.shared.success(
        editing != nil
          ? "Entry saved."
          : isChapter ? "Chapter added." : isFirstTime ? "First Time added." : "Entry added.")
      onSaved(.saved(saved))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func trash() async {
    guard let editing, !isBusy else { return }
    isTrashing = true
    errorMessage = nil
    defer { isTrashing = false }
    do {
      try await EntryAPI(client: client, ownerID: ownerID).moveToTrash(
        id: editing.id, revision: editing.revision)
      MTToastCenter.shared.info("Entry moved to Trash.")
      onSaved(.movedToTrash(editing.id))
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

extension View {
  /// Web's recoverable Move to Trash confirmation for one Entry, anchored to its button.
  func entryTrashConfirmation(
    _ title: String, isPresented: Binding<Bool>, confirm: @escaping () -> Void
  ) -> some View {
    confirmationDialog(
      "Move “\(title)” to Trash?", isPresented: isPresented, titleVisibility: .visible
    ) {
      Button("Move to Trash", role: .destructive, action: confirm)
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You can restore it later from Trash.")
    }
  }
}
