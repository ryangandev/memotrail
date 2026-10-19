@preconcurrency import Supabase
import SwiftUI

// P4: the full Item page (photos in the current card, Chapter contents with pages, Chapters
// during this time, and an existing Chapter review shown read-only).

/// Web `/items/<entry>`: one Entry's identity and title, Edit and Move to Trash, its writing and
/// facts, and current photos. A dated Chapter also lists the Entries inside it and the Chapters
/// during the same time.
struct ItemPageView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: ItemPageController
  @State private var editing: EditableEntry?
  @State private var leavesAfterEditing = false
  @State private var isOpeningEditor = false
  @State private var isConfirmingTrash = false
  @State private var isTrashing = false
  @State private var errorMessage: String?
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.dismiss) private var dismiss

  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.entryID = entryID
    _controller = State(
      initialValue: ItemPageController(client: client, ownerID: ownerID, entryID: entryID))
  }

  var body: some View {
    Group {
      if let entry = controller.entry {
        page(entry)
      } else if !controller.hasLoaded {
        MTPage(width: .compact) {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            Text("Loading this item...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
        }
      } else if controller.loadFailed {
        MTPage(width: .compact) {
          MTEmptyState(
            title: "Item unavailable", message: "This item could not load. Refresh to try again.",
            icon: .warning
          ) {
            Button("Try again") { Task { await controller.load() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTPage(width: .compact, spacing: MTSpacing.s6) {
          MTPageHeader(
            eyebrow: "Life Wiki", title: "Item unavailable",
            description: "It may have moved to Trash or no longer be accessible.")
          Button("Back") { dismiss() }
            .mtButtonStyle(.secondary)
        }
      }
    }
    .refreshable { await controller.load() }
    .navigationTitle(controller.entry?.marks.identityLabel ?? "Item")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) {
      // Leave only once the editor has closed, since popping while it closes cancels both.
      if leavesAfterEditing { dismiss() }
    } content: { entry in
      EntryEditorSheet(client: client, ownerID: ownerID, mode: .edit(entry)) { result in
        if case .movedToTrash = result { leavesAfterEditing = true }
        navigator.entriesChanged()
      }
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
    .onChange(of: navigator.entriesRevision) { Task { await controller.load() } }
  }

  private func page(_ entry: EntryDetail) -> some View {
    MTPage(width: .compact, spacing: MTSpacing.s5) {
      MTPageHeader(eyebrow: entry.marks.identityLabel, title: entry.displayTitle)
      if !entry.isInTrash {
        actions(entry)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(MTFont.body)
          .foregroundStyle(MTColor.warm)
          .accessibilityAddTraits(.updatesFrequently)
      }
      if entry.isInTrash {
        Text("This item is in Trash. Restore it there to change it.")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      ItemCurrentCard(entry: entry)
      if !entry.isInTrash {
        EntryPhotoGalleryView(client: client, ownerID: ownerID, entryID: entryID) {
          await controller.load()
        }
        .id("photos:\(entryID)")
      }
      if !entry.isInTrash, entry.subtype == .chapter {
        chapterSections(entry)
      }
    }
  }

  private func actions(_ entry: EntryDetail) -> some View {
    MTFlowLayout(spacing: MTSpacing.s2) {
      Button("Edit \(entry.subtype == .chapter ? "Chapter" : "Entry")") {
        Task { await openEditor() }
      }
      .mtButtonStyle(.secondary, isLoading: isOpeningEditor)
      .disabled(isOpeningEditor || isTrashing)
      .accessibilityIdentifier("item-edit")
      Button {
        isConfirmingTrash = true
      } label: {
        Label("Move to Trash", icon: .trash)
      }
      .mtButtonStyle(.danger, isLoading: isTrashing)
      .disabled(isOpeningEditor || isTrashing)
      .accessibilityIdentifier("item-trash")
      .entryTrashConfirmation(entry.displayTitle, isPresented: $isConfirmingTrash) {
        Task { await moveToTrash() }
      }
    }
  }

  /// A plain version of Web `ChapterSections`.
  @ViewBuilder
  private func chapterSections(_ entry: EntryDetail) -> some View {
    if entry.occurredStart == nil {
      MTDetailSection("In this Chapter") {
        Text("Add a rough start date to see the Entries from this time.")
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.inkMuted)
      }
    } else if let message = controller.chapterErrorMessage {
      MTDetailSection("In this Chapter") {
        Text(message)
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.warm)
      }
    } else {
      if controller.chapterEntries.isEmpty {
        MTDetailSection("In this Chapter") {
          Text("No Entries from this time yet.")
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
        }
      } else {
        ItemLinkList(
          title: "In this Chapter · \(countLabel(controller.chapterEntryCount, "Entry"))",
          rows: controller.chapterEntries.map {
            ItemLinkList.Row(
              id: $0.id, title: $0.displayTitle, detail: $0.occurrence.displayLabel)
          },
          identifierPrefix: "item-chapter-entry")
      }
      if !controller.chapterOverlaps.isEmpty {
        ItemLinkList(
          title: "Chapters during this time",
          rows: controller.chapterOverlaps.map {
            ItemLinkList.Row(id: $0.id, title: $0.displayTitle, detail: $0.occurrence.spanLabel)
          },
          identifierPrefix: "item-chapter-overlap")
      }
    }
  }

  private func openEditor() async {
    isOpeningEditor = true
    errorMessage = nil
    defer { isOpeningEditor = false }
    if let entry = await controller.editableEntry() {
      leavesAfterEditing = false
      editing = entry
    } else {
      errorMessage = "This item cannot be edited right now. Refresh and try again."
    }
  }

  private func moveToTrash() async {
    isTrashing = true
    errorMessage = nil
    defer { isTrashing = false }
    if let message = await controller.moveToTrash() {
      errorMessage = message
      return
    }
    MTToastCenter.shared.info("Entry moved to Trash.")
    navigator.entriesChanged()
    dismiss()
  }
}
