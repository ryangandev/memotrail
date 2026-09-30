@preconcurrency import Supabase
import SwiftUI

/// Web `/items/<id>`: an Item without a focused page of its own, such as a plain Entry or a
/// person Entry. It shows the current writing and facts, the actions for its Kind, Related
/// Items, and current photos, with version history one step away.
struct WikiItemDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: EntryHistoryController
  @State private var destination: Destination?
  @State private var editingEntry: InboxEntry?
  @State private var isCreatingGoal = false
  @State private var isConfirmingTrash = false
  @State private var errorMessage: String?
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.dismiss) private var dismiss

  private enum Destination: Hashable {
    case history, firstTime
    case goal(UUID)
    case item(UUID)
  }

  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.entryID = entryID
    _controller = State(
      initialValue: EntryHistoryController(client: client, ownerID: ownerID, entryID: entryID))
  }

  var body: some View {
    Group {
      if let record = controller.record {
        page(record)
      } else if !controller.hasLoaded {
        MTPage(width: .compact) {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            Text("Loading this item...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: 180)
        }
      } else if controller.loadFailed {
        MTPage(width: .compact) {
          MTEmptyState(
            title: "Item unavailable", message: "This item could not load. Refresh to try again.",
            icon: .warning
          ) {
            Button("Try again") { Task { await controller.reload() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTPage(width: .compact, spacing: MTSpacing.s6) {
          MTPageHeader(
            eyebrow: "Life Wiki", title: "Item unavailable",
            description: "It may have moved to Trash or no longer be accessible.")
          Button("Back") { dismiss() }
            .mtButtonStyle()
        }
      }
    }
    .refreshable { await controller.reload() }
    .navigationTitle(controller.record?.identityLabel ?? "Item")
    .navigationBarTitleDisplayMode(.inline)
    .reloadOnReturn(from: destination != nil) { await controller.reload() }
    .navigationDestination(item: $destination) { destination in
      switch destination {
      case .history:
        EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
      case .firstTime:
        FirstTimeDetailView(client: client, ownerID: ownerID, entryID: entryID)
      case .goal(let id):
        GoalDetailView(client: client, ownerID: ownerID, entryID: id)
      case .item(let id):
        WikiItemDetailView(client: client, ownerID: ownerID, entryID: id)
      }
    }
    .sheet(isPresented: $isCreatingGoal) {
      LinkedGoalSheet(controller: controller) { destination = .goal($0) }
    }
    .sheet(item: $editingEntry) { entry in
      EntryReviewSheet(
        client: client, ownerID: ownerID, entry: entry,
        collectionOptions: entry.collectionNames, tagOptions: entry.tagNames,
        showsVersionHistory: false
      ) { draft, intent in
        await controller.saveEditedEntry(entry, draft: draft, intent: intent)
      }
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private func page(_ record: EntryHistoryRecord) -> some View {
    MTPage(width: .compact, spacing: MTSpacing.s5) {
      MTPageHeader(eyebrow: nil, title: record.title)
      WikiItemActions(record: record, isItemPage: true, isBusy: controller.isWorking) {
        perform($0, record: record)
      }
      .confirmationDialog(
        "Move “\(record.title)” to Trash?", isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) { Task { await moveToTrash() } }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("You can restore it later from Trash.")
      }
      if let errorMessage {
        Text(errorMessage)
          .font(MTFont.body)
          .foregroundStyle(MTColor.warm)
          .accessibilityAddTraits(.updatesFrequently)
      }
      WikiItemProvenanceLinks(record: record) { destination = .item($0) }
      if record.isDeleted {
        Text("This item is in Trash. Restore it there before changing its history.")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      WikiItemCurrentCard(snapshot: record.current)
      if !record.isDeleted {
        EntryRelationsView(
          client: client, ownerID: ownerID, entryID: entryID, open: { destination = .item($0) }
        ) {
          await controller.reload()
        }
        .id("relations:\(entryID):\(record.revision)")
        EntryPhotoGalleryView(client: client, ownerID: ownerID, entryID: entryID) {
          await controller.reload()
        }
        .id("photos:\(entryID)")
      }
    }
  }

  private func perform(_ action: WikiItemActions.Action, record: EntryHistoryRecord) {
    errorMessage = nil
    switch action {
    case .edit: Task { await openEditor() }
    case .openFirstTime: destination = .firstTime
    case .openOnTimeline: navigator.openTimelineEntry(entryID)
    case .history: destination = .history
    case .createGoal: isCreatingGoal = true
    case .openGoal: destination = .goal(entryID)
    case .trash: isConfirmingTrash = true
    }
  }

  private func openEditor() async {
    if let entry = await controller.editableEntry() {
      editingEntry = entry
    } else {
      errorMessage = "This item cannot be edited right now. Refresh and try again."
    }
  }

  private func moveToTrash() async {
    if let message = await controller.moveToTrash() {
      errorMessage = message
      return
    }
    MTToastCenter.shared.info("Entry moved to Trash.")
    dismiss()
  }
}
