@preconcurrency import Supabase
import SwiftUI

/// Web `/goals/<id>`: one Goal's photos, state, horizon, and target, its reflection,
/// organization, and connected Items, with Edit and Version history. Moving it to Trash from
/// its editor returns to where it was opened from.
struct GoalDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: GoalController
  @State private var isEditing = false
  @State private var showsHistory = false
  @State private var openedItem: ConnectedItemsSection.Item?
  @State private var wasTrashed = false
  /// Keeps the page steady under the closing editor after the Goal moves to Trash.
  @State private var lastEntry: GoalEntry?
  @Environment(\.dismiss) private var dismiss

  /// Opens a Goal on its own, such as from Library, the Map, or a Collection.
  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.init(
      controller: GoalController(client: client, ownerID: ownerID), client: client,
      ownerID: ownerID, entryID: entryID)
  }

  /// Opens a Goal from a list that has already loaded it.
  init(controller: GoalController, client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.entryID = entryID
    _controller = State(initialValue: controller)
  }

  var body: some View {
    Group {
      if let entry = controller.entry(id: entryID) ?? (wasTrashed ? lastEntry : nil) {
        detail(entry)
      } else if !controller.hasLoaded {
        MTPage(width: .compact) {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            Text("Loading this Goal...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
        }
      } else if let message = controller.loadErrorMessage {
        MTPage(width: .compact) {
          MTEmptyState(title: "Goals unavailable", message: message, icon: .sparkle) {
            Button("Try again") { Task { await controller.load(including: entryID) } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTFocusedRecordUnavailable(kind: "Goal", backTitle: "Back to goals") { dismiss() }
      }
    }
    .refreshable { await controller.load(including: entryID) }
    .navigationTitle("Goal")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      if wasTrashed { dismiss() }
    } content: {
      if let entry = controller.entry(id: entryID) {
        GoalEditorSheet(controller: controller, entry: entry, onTrashed: { wasTrashed = true })
      }
    }
    .onChange(of: controller.entry(id: entryID), initial: true) { _, entry in
      if let entry { lastEntry = entry }
    }
    .reloadOnReturn(from: showsHistory) { await controller.load(including: entryID) }
    .navigationDestination(isPresented: $showsHistory) {
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
    }
    .connectedItemDestination($openedItem, client: client, ownerID: ownerID)
    .reloadOnReturn(from: openedItem != nil) { await controller.load(including: entryID) }
    .task {
      if controller.entry(id: entryID) == nil { await controller.load(including: entryID) }
    }
  }

  private func detail(_ entry: GoalEntry) -> some View {
    MTFocusedRecordPage(
      kind: "Goal", title: entry.title,
      photos: entry.attachments.map {
        MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
      },
      facts: [
        ("Status", entry.status.displayName),
        ("Horizon", entry.horizon.displayName),
        ("Target", entry.targetLabel),
      ],
      story: entry.body, collectionNames: entry.collectionNames, tagNames: entry.tagNames,
      edit: { isEditing = true }, history: { showsHistory = true },
      extra: {
        if !entry.relatedEntries.isEmpty {
          ConnectedItemsSection(
            items: entry.relatedEntries.map {
              ConnectedItemsSection.Item(
                id: $0.id, title: $0.displayTitle, kind: $0.itemKind, subtype: $0.itemSubtype)
            },
            opened: $openedItem)
        }
      })
  }
}
