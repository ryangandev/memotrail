@preconcurrency import Supabase
import SwiftUI

/// Web `/items/<entry>`: one Entry's identity and title, Edit and Move to Trash, its writing,
/// photos, and facts. A dated Chapter also lists its saved review, the Entries inside it, and
/// the Chapters during the same time.
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
      ItemCurrentCard(entry: entry) {
        photos(entry)
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
      .itemTrashConfirmation(entry.displayTitle, isPresented: $isConfirmingTrash) {
        Task { await moveToTrash() }
      }
    }
  }

  // MARK: Photos

  /// Web: the photos below the writing, or a notice when they could not load. An Entry in Trash
  /// shows none; they are restored from Trash with it.
  @ViewBuilder
  private func photos(_ entry: EntryDetail) -> some View {
    if entry.isInTrash {
      EmptyView()
    } else if controller.photosFailed {
      Text("Photos could not load. Pull down to refresh and try again.")
        .font(MTFont.supporting)
        .foregroundStyle(MTColor.warm)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("item-photos-error")
    } else if !controller.photos.isEmpty {
      ItemPhotosView(photos: controller.photos, hasMore: controller.photosHaveMore)
    }
  }

  // MARK: A Chapter

  /// Web `ChapterSections`: the review when there is one, the Entries dated inside the Chapter,
  /// and the Chapters during the same time.
  @ViewBuilder
  private func chapterSections(_ entry: EntryDetail) -> some View {
    if let review = controller.review {
      ItemReviewView(
        review: review, facts: controller.reviewFacts,
        spanLabel: entry.chapterDateFacts().span)
    }
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader(
        "In this Chapter",
        detail: entry.occurredStart != nil && controller.chapterErrorMessage == nil
          && controller.hasLoaded ? countLabel(controller.chapterEntryCount, "Entry") : nil)
      chapterEntries(entry)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("item-chapter-entries")
    if !controller.chapterOverlaps.isEmpty {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        MTSectionHeader("Chapters during this time")
        ItemOverlapList(overlaps: controller.chapterOverlaps)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("item-chapter-overlaps")
    }
  }

  @ViewBuilder
  private func chapterEntries(_ entry: EntryDetail) -> some View {
    if entry.occurredStart == nil {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        Text("Add a rough start date to see the Entries from this time.")
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.inkMuted)
        Button("Add a start date") { Task { await openEditor() } }
          .mtButtonStyle(.secondary)
          .disabled(isOpeningEditor || isTrashing)
          .accessibilityIdentifier("item-add-start-date")
      }
    } else if let message = controller.chapterErrorMessage {
      Text(message)
        .font(MTFont.supporting)
        .foregroundStyle(MTColor.warm)
        .accessibilityAddTraits(.updatesFrequently)
    } else if controller.chapterEntries.isEmpty {
      if controller.hasLoaded {
        Text("No Entries are dated inside this Chapter yet.")
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.inkMuted)
      }
    } else {
      ItemEntryList(
        rows: controller.chapterEntries.map { $0.row(coverURL: controller.coverURLs[$0.id]) })
      if controller.hasMoreEntries || controller.moreEntriesErrorMessage != nil {
        // The trigger is its own row, so the lazy page creates it only near the end of the list.
        MTLoadMore(
          isLoading: controller.isLoadingMoreEntries,
          message: controller.moreEntriesErrorMessage
        ) { await controller.loadMoreEntries() }
      }
    }
  }

  // MARK: Actions

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

extension View {
  /// Web `moveToTrash`'s confirmation: the title in quotes, and that Trash can restore it.
  fileprivate func itemTrashConfirmation(
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
