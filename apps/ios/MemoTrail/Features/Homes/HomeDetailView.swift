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
        unavailable
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
    .navigationDestination(isPresented: $showsHistory) {
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entryID)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private func detail(_ entry: ResidenceEntry) -> some View {
    MTPage(width: .compact, spacing: MTSpacing.s6) {
      MTPageHeader(eyebrow: "Home", title: entry.title) {
        Button {
          isEditing = true
        } label: {
          Label("Edit", icon: .edit)
        }
        .mtButtonStyle(.ghost, size: .small)
        .accessibilityLabel("Edit Home")
        .accessibilityIdentifier("edit-home")
      }
      VStack(alignment: .leading, spacing: MTSpacing.s8) {
        let photos = entry.attachments.map {
          MTPhotoField.SavedPhoto(id: $0.id, url: $0.signedURL, name: $0.originalFilename)
        }
        if !photos.isEmpty {
          MTRecordPhotos(recordLabel: "Home", photos: photos)
        }
        MTFactList(facts: [
          ("When", entry.displayRange),
          ("Location", entry.displayLocation),
          ("Address", entry.address),
          ("Why you moved in", entry.moveInReason),
          ("Why you left", entry.moveOutReason),
          ("Place notes", entry.placeNotes),
        ])
        if let story = entry.body.trimmed.nonEmpty {
          MTDetailSection("Story") {
            Text(story)
              .font(MTFont.bodyLarge)
              .foregroundStyle(MTColor.ink)
              .mtLineSpacing(MTLineHeight.relaxed)
              .textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
          MTDetailSection("Organize") {
            MTFlowLayout(spacing: MTSpacing.s2) {
              ForEach(entry.collectionNames, id: \.self) { MTBadge(title: $0, tone: .neutral) }
              ForEach(entry.tagNames, id: \.self) { MTBadge(title: "#\($0)", tone: .neutral) }
            }
          }
        }
      }
      Button("Version history") { showsHistory = true }
        .mtButtonStyle(.secondary)
        .accessibilityIdentifier("home-version-history")
    }
  }

  /// Web `FocusedDetailUnavailable`.
  private var unavailable: some View {
    MTPage(width: .compact, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Home", title: "Home unavailable",
        description: "This record may have moved to Trash or no longer be accessible.")
      Button("Back to homes") { dismiss() }
        .mtButtonStyle()
    }
  }
}
