@preconcurrency import Supabase
import SwiftUI

/// Web `EntryReviewDialog`: review an Inbox capture, or edit an organized Entry, with the same
/// fields, footer actions, and toasts.
struct EntryReviewSheet: View {
  typealias Save =
    @MainActor (EntryReviewDraft, InboxController.ReviewIntent) async ->
    InboxController.ReviewResult

  let client: SupabaseClient
  let ownerID: UUID
  let entry: InboxEntry
  let collectionOptions: [String]
  let tagOptions: [String]
  /// Inbox captures offer Move to Trash; it returns whether the capture moved.
  let moveToTrash: (@MainActor () async -> Bool)?
  let showsVersionHistory: Bool
  let save: Save

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var note: NSAttributedString
  @State private var collectionNames: [String]
  @State private var tagNames: [String]
  @State private var occurrence: OccurrenceDraft
  @State private var photoPlace: PhotoPlaceDraft?
  @State private var savingIntent: InboxController.ReviewIntent?
  @State private var isTrashing = false
  @State private var isConfirmingTrash = false
  @State private var isShowingHistory = false
  @State private var errorMessage: String?
  /// The note as it opened, to tell an untouched note from an edited one.
  private let openingNote: NSAttributedString
  /// Web writing with quotes, lists, code, or links that the native editor cannot keep.
  private let hasWebOnlyFormatting: Bool

  init(
    client: SupabaseClient,
    ownerID: UUID,
    entry: InboxEntry,
    collectionOptions: [String],
    tagOptions: [String],
    moveToTrash: (@MainActor () async -> Bool)? = nil,
    showsVersionHistory: Bool = true,
    save: @escaping Save
  ) {
    self.client = client
    self.ownerID = ownerID
    self.entry = entry
    self.collectionOptions = collectionOptions
    self.tagOptions = tagOptions
    self.moveToTrash = moveToTrash
    self.showsVersionHistory = showsVersionHistory
    self.save = save
    let editable = entry.bodyRich.flatMap(EntryEmphasisContent.init)
    let note = editable?.attributedText() ?? NSAttributedString(string: entry.body)
    openingNote = note
    hasWebOnlyFormatting = entry.bodyRich != nil && editable == nil
    _title = State(initialValue: entry.title ?? "")
    _note = State(initialValue: note)
    _collectionNames = State(initialValue: entry.collectionNames)
    _tagNames = State(initialValue: entry.tagNames)
    _occurrence = State(initialValue: OccurrenceDraft(entry.occurrence))
  }

  private var isOrganized: Bool { entry.inboxStatus == "organized" }
  private var isBusy: Bool { savingIntent != nil || isTrashing }

  var body: some View {
    MTSheet(
      eyebrow: isOrganized ? "Life Wiki editor" : "Inbox review",
      title: isOrganized ? "Edit Entry" : "Review Entry",
      description: isOrganized
        ? "This Entry is already part of your Life Wiki."
        : "Review what you captured, then save it to your Library.",
      closeLabel: isOrganized ? "Close item editor" : "Close Inbox review",
      closeIdentifier: "close-entry-review", isBusy: isBusy, message: errorMessage
    ) {
      MTTextField(
        label: "Title", text: $title, prompt: "Add a title",
        maxLength: InboxCapture.titleLimit
      )
      .accessibilityIdentifier("review-title")
      noteField
      OccurrenceEditor(value: $occurrence)
      MTOrganizationEditor(
        kind: .collection, names: $collectionNames, options: collectionOptions)
      MTOrganizationEditor(kind: .tag, names: $tagNames, options: tagOptions)
      EntryPhotoDatesView(
        client: client, ownerID: ownerID, entryID: entry.id, occurrence: $occurrence,
        photoPlace: $photoPlace)
    } accessory: {
      if showsVersionHistory {
        Button {
          isShowingHistory = true
        } label: {
          Label("Version history", icon: .history)
            .font(MTFont.caption)
            .foregroundStyle(MTColor.accent)
            .frame(minHeight: MTLayout.InlineAction.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("review-version-history")
        .navigationDestination(isPresented: $isShowingHistory) {
          EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entry.id)
        }
      }
    } footer: {
      footer
    }
  }

  private var noteField: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Note")
      MTRichTextEditor(
        text: $note, placeholder: "Write what you want to remember",
        accessibilityIdentifier: "review-body", minimumHeight: MTLayout.RichText.reviewMinHeight)
      if hasWebOnlyFormatting {
        Text(
          "Lists, quotes, links, and code from the web stay as they are unless you edit this note here."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkFaint)
      }
    }
  }

  /// Web's dialog footer: the save actions, then Move to Trash for Inbox captures.
  @ViewBuilder private var footer: some View {
    HStack(spacing: MTSpacing.s2) {
      if isOrganized {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary, fillsWidth: true)
        Button("Save changes") { Task { await submit(.save) } }
          .mtButtonStyle(isLoading: savingIntent == .save, fillsWidth: true)
          .accessibilityIdentifier("save-entry-review")
      } else {
        Button("Save changes") { Task { await submit(.save) } }
          .mtButtonStyle(.secondary, isLoading: savingIntent == .save, fillsWidth: true)
          .accessibilityIdentifier("save-entry-review")
        Button {
          Task { await submit(.done) }
        } label: {
          Label("Save to Library", icon: .check)
        }
        .mtButtonStyle(isLoading: savingIntent == .done, fillsWidth: true)
        .accessibilityIdentifier("organize-entry")
      }
    }
    if moveToTrash != nil, !isOrganized {
      Button {
        isConfirmingTrash = true
      } label: {
        Label("Move to Trash", icon: .trash)
      }
      .mtButtonStyle(.ghost, isLoading: isTrashing)
      .accessibilityIdentifier("trash-entry-review")
      .captureTrashConfirmation(entry.displayTitle, isPresented: $isConfirmingTrash) {
        Task { await trash() }
      }
    }
  }

  /// The saved note: an untouched note keeps its original document, including Web-only
  /// structure; an edited note saves the editor's formatting.
  private func noteDraft() -> (body: String, rich: EntryRichText?) {
    let current = EntryEmphasisContent.capture(note)
    if current == EntryEmphasisContent.capture(openingNote) {
      return (entry.body, entry.bodyRich)
    }
    return (current.body, current.rich.flatMap(EntryRichText.init))
  }

  @MainActor
  private func submit(_ intent: InboxController.ReviewIntent) async {
    let resolved: EntryOccurrence
    do {
      resolved = try occurrence.resolve(original: entry.occurrence)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    let note = noteDraft()
    savingIntent = intent
    errorMessage = nil
    let result = await save(
      EntryReviewDraft(
        title: title, body: note.body, bodyRich: note.rich, collectionNames: collectionNames,
        tagNames: tagNames, occurrence: resolved, photoPlace: photoPlace),
      intent)
    savingIntent = nil

    switch result.status {
    case .done, .saved:
      MTToastCenter.shared.success(result.message)
      dismiss()
    case .conflict, .error:
      errorMessage = result.message
    }
  }

  @MainActor
  private func trash() async {
    guard let moveToTrash else { return }
    isTrashing = true
    let moved = await moveToTrash()
    isTrashing = false
    if moved { dismiss() }
  }
}
