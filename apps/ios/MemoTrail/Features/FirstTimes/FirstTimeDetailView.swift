@preconcurrency import Supabase
import SwiftUI

/// Web `/first-times/<id>`: one First Time's photos, When and Location, Story, and organization,
/// with Edit and Version history. Moving it to Trash from its editor returns to where it was
/// opened from.
struct FirstTimeDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: FirstTimesController
  @State private var isEditing = false
  @State private var showsHistory = false
  @State private var wasTrashed = false
  /// Keeps the page steady under the closing editor after the First Time moves to Trash.
  @State private var lastEntry: FirstTimeEntry?
  @Environment(\.dismiss) private var dismiss

  /// Opens a First Time on its own, such as from Library, the Map, or a Collection.
  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.init(
      controller: FirstTimesController(client: client, ownerID: ownerID), client: client,
      ownerID: ownerID, entryID: entryID)
  }

  /// Opens a First Time from a list that has already loaded it.
  init(controller: FirstTimesController, client: SupabaseClient, ownerID: UUID, entryID: UUID) {
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
            Text("Loading this First Time...").font(MTFont.body).foregroundStyle(
              MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: 180)
        }
      } else if let message = controller.loadErrorMessage {
        MTPage(width: .compact) {
          MTEmptyState(title: "First Times unavailable", message: message, icon: .star) {
            Button("Try again") { Task { await controller.load() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTFocusedRecordUnavailable(kind: "First Time", backTitle: "Back to first times") {
          dismiss()
        }
      }
    }
    .refreshable { await controller.load() }
    .navigationTitle("First Time")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      if wasTrashed { dismiss() }
    } content: {
      if let entry = controller.entry(id: entryID) {
        FirstTimeEditorSheet(
          controller: controller, entry: entry, onTrashed: { wasTrashed = true })
      }
    }
    .onChange(of: controller.entry(id: entryID), initial: true) { _, entry in
      if let entry { lastEntry = entry }
    }
    .navigationDestination(isPresented: $showsHistory) {
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private func detail(_ entry: FirstTimeEntry) -> some View {
    MTFocusedRecordPage(
      kind: "First Time", title: entry.title,
      photos: entry.originalAttachments.map {
        MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
      },
      facts: [
        ("When", entry.displayDate),
        ("Location", entry.location?.name),
      ],
      story: entry.body, collectionNames: entry.collectionNames, tagNames: entry.tagNames,
      edit: { isEditing = true }, history: { showsHistory = true })
  }
}
