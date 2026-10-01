@preconcurrency import Supabase
import SwiftUI

/// Web `/homes/<id>`: one Home's photos, facts, Story, and organization, with Edit and Version
/// history. Moving the Home to Trash from its editor returns to where it was opened from.
struct HomeDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: ResidenceController
  @State private var isEditing = false
  @State private var showsHistory = false
  @State private var wasTrashed = false
  /// Keeps the page steady under the closing editor after the Home moves to Trash.
  @State private var lastEntry: ResidenceEntry?
  @Environment(\.dismiss) private var dismiss

  /// Opens a Home on its own, such as from Library, the Map, or a Collection.
  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.init(
      controller: ResidenceController(client: client, ownerID: ownerID), client: client,
      ownerID: ownerID, entryID: entryID)
  }

  /// Opens a Home from a list that has already loaded it.
  init(controller: ResidenceController, client: SupabaseClient, ownerID: UUID, entryID: UUID) {
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
            Text("Loading this Home...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: 180)
        }
      } else if let message = controller.loadErrorMessage {
        MTPage(width: .compact) {
          MTEmptyState(title: "Homes unavailable", message: message, icon: .home) {
            Button("Try again") { Task { await controller.load() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTFocusedRecordUnavailable(kind: "Home", backTitle: "Back to homes") { dismiss() }
      }
    }
    .refreshable { await controller.load() }
    .navigationTitle("Home")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      if wasTrashed { dismiss() }
    } content: {
      if let entry = controller.entry(id: entryID) {
        ResidenceEditorSheet(
          controller: controller, entry: entry, onTrashed: { wasTrashed = true })
      }
    }
    .onChange(of: controller.entry(id: entryID), initial: true) { _, entry in
      if let entry { lastEntry = entry }
    }
    .reloadOnReturn(from: showsHistory) { await controller.load() }
    .navigationDestination(isPresented: $showsHistory) {
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private func detail(_ entry: ResidenceEntry) -> some View {
    MTFocusedRecordPage(
      kind: "Home", title: entry.title,
      photos: entry.attachments.map {
        MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
      },
      facts: [
        ("When", entry.displayRange),
        ("Location", entry.displayLocation),
        ("Address", entry.address),
        ("Why you moved in", entry.moveInReason),
        ("Why you left", entry.moveOutReason),
        ("Place notes", entry.placeNotes),
      ],
      story: entry.body, collectionNames: entry.collectionNames, tagNames: entry.tagNames,
      edit: { isEditing = true }, history: { showsHistory = true })
  }
}
