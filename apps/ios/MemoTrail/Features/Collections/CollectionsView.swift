@preconcurrency import Supabase
import SwiftUI

/// Web `/collections`: each Collection as a card with its Entry and Inbox counts, New
/// Collection, and each card's own editor. A card opens the Collection's Entries.
struct CollectionsView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: CollectionsController
  @State private var editing: Editing?
  @State private var opened: MemoCollection?

  /// The Collection editor: a new Collection, or a saved one.
  private struct Editing: Identifiable {
    let item: OrganizationItem?
    var id: UUID? { item?.id }
  }

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: CollectionsController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Browse by meaning", title: "Collections",
        description:
          "Open a theme to revisit the Entries, moments, and firsts you filed together."
      ) {
        Button {
          editing = Editing(item: nil)
        } label: {
          Label("New Collection", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("new-collection")
      }
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("Collections")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) { editing in
      OrganizationEditorSheet(
        actions: controller.actions, kind: .collection, item: editing.item,
        changed: { await controller.load() })
    }
    .navigationDestination(item: $opened) { collection in
      CollectionDetailView(client: client, ownerID: ownerID, collection: collection) {
        await controller.load()
      }
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  @ViewBuilder private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Collections...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "Collections unavailable", message: message, icon: .archive) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
    } else if controller.collections.isEmpty {
      MTEmptyState(
        title: "No Collections yet",
        message:
          "Add a Collection while organizing an Inbox Entry or saving a First Time. It will appear here automatically.",
        icon: .archive
      ) {
        OpenInboxButton()
      }
    } else {
      Text(
        "\(countLabel(controller.collections.count, "Collection")) · \(countLabel(controller.entryPlacementCount, "Entry placement"))"
      )
      .font(MTFont.caption.weight(.regular))
      .foregroundStyle(MTColor.inkFaint)
      // Web's grid: one column on phones, up to four on wide screens.
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 200), spacing: MTSpacing.s3)],
        spacing: MTSpacing.s3
      ) {
        ForEach(controller.collections) { collection in
          card(collection)
        }
      }
    }
  }

  private func card(_ collection: MemoCollection) -> some View {
    MTCollectionCard(
      name: collection.name, entryCount: collection.entryCount,
      inboxCount: collection.unreviewedCount,
      updatedLabel: collection.latestEntryAt.map { _ in collection.latestEntryLabel }
    ) {
      opened = collection
    } manage: {
      if let item = controller.item(for: collection) {
        MTIconButton(label: "Edit \(collection.name)", icon: .more) {
          editing = Editing(item: item)
        }
      }
    }
  }
}
