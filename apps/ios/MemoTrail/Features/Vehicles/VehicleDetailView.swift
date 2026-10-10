@preconcurrency import Supabase
import SwiftUI

/// Web `/vehicles/<id>`: one Vehicle's photos, facts, Story, and organization, with Edit and
/// Version history. Moving the Vehicle to Trash from its editor returns to where it was opened
/// from.
struct VehicleDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: VehicleController
  @State private var isEditing = false
  @State private var showsHistory = false
  @State private var wasTrashed = false
  /// Keeps the page steady under the closing editor after the Vehicle moves to Trash.
  @State private var lastEntry: VehicleEntry?
  @Environment(\.dismiss) private var dismiss

  /// Opens a Vehicle on its own, such as from Library, the Map, or a Collection.
  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.init(
      controller: VehicleController(client: client, ownerID: ownerID), client: client,
      ownerID: ownerID, entryID: entryID)
  }

  /// Opens a Vehicle from a list that has already loaded it.
  init(controller: VehicleController, client: SupabaseClient, ownerID: UUID, entryID: UUID) {
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
            Text("Loading this Vehicle...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
        }
      } else if let message = controller.loadErrorMessage {
        MTPage(width: .compact) {
          MTEmptyState(title: "Vehicles unavailable", message: message, icon: .car) {
            Button("Try again") { Task { await controller.load() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTFocusedRecordUnavailable(kind: "Vehicle", backTitle: "Back to vehicles") { dismiss() }
      }
    }
    .refreshable { await controller.load() }
    .navigationTitle("Vehicle")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      if wasTrashed { dismiss() }
    } content: {
      if let entry = controller.entry(id: entryID) {
        VehicleEditorSheet(
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

  private func detail(_ entry: VehicleEntry) -> some View {
    MTFocusedRecordPage(
      kind: "Vehicle", title: entry.title,
      photos: entry.attachments.map {
        MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
      },
      facts: [
        ("When", entry.displayRange),
        ("Vehicle", entry.factsLabel),
        ("Location", entry.location?.name),
      ],
      story: entry.body, collectionNames: entry.collectionNames, tagNames: entry.tagNames,
      edit: { isEditing = true }, history: { showsHistory = true })
  }
}
