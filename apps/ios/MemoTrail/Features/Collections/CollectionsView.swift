@preconcurrency import Supabase
import SwiftUI

struct CollectionsView: View {
  @State private var managing = false
  @State private var controller: CollectionsController

  private let client: SupabaseClient
  private let embedded: Bool
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false) {
    self.client = client
    self.embedded = embedded
    self.ownerID = ownerID
    _controller = State(
      initialValue: CollectionsController(client: client, ownerID: ownerID)
    )
  }

  @ViewBuilder
  var body: some View {
    if embedded {
      archiveView
    } else {
      NavigationStack {
        archiveView
      }
    }
  }

  private var archiveView: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s6) {
        header
        summary
        content
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle("Collections")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button("Manage", systemImage: "slider.horizontal.3") { managing = true }
      }
    }
    .sheet(isPresented: $managing, onDismiss: { Task { await controller.load() } }) {
      NavigationStack {
        OrganizationView(client: client, ownerID: ownerID)
          .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { managing = false } }
          }
      }
    }
    .refreshable {
      await controller.load()
    }
    .navigationDestination(for: MemoCollection.self) { collection in
      CollectionDetailView(client: client, ownerID: ownerID, collection: collection)
    }
    .navigationDestination(for: CollectionEntry.self) { entry in
      collectionEntryDestination(entry)
    }
    .task {
      if !controller.hasLoaded {
        await controller.load()
      }
    }
  }

  @ViewBuilder
  private func collectionEntryDestination(_ entry: CollectionEntry) -> some View {
    switch (entry.itemKind, entry.itemSubtype, entry.recordSource) {
    case (.entity, "person", .person):
      PeopleView(client: client, ownerID: ownerID, focusedPersonID: entry.recordID)
    case (.entity, "home", _):
      HomeDetailView(client: client, ownerID: ownerID, entryID: entry.id)
    case (.entity, "vehicle", _):
      VehicleDetailView(client: client, ownerID: ownerID, entryID: entry.id)
    case (.goal, _, _):
      GoalsView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: entry.id)
    case (.entry, "first_time", _):
      FirstTimeDetailView(client: client, ownerID: ownerID, entryID: entry.id)
    default:
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entry.id)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("BROWSE BY MEANING")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)

      Text("Collections")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Revisit the Entries, moments, and firsts you filed together.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var summary: some View {
    HStack(spacing: MTSpacing.s2) {
      Text(countLabel(controller.collections.count, singular: "Collection"))
      Text("·")
      Text(countLabel(controller.entryPlacementCount, singular: "Entry placement"))

      Spacer()

      if controller.isLoading, controller.hasLoaded {
        ProgressView()
          .controlSize(.small)
      }
    }
    .font(MTTypography.caption)
    .foregroundStyle(MTColor.inkFaint)
  }

  @ViewBuilder
  private var content: some View {
    if controller.isLoading, !controller.hasLoaded {
      loadingView("Loading your Collections...")
    } else if let loadErrorMessage = controller.loadErrorMessage {
      archiveMessage(
        title: "Collections unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.collections.isEmpty {
      archiveMessage(
        title: "No Collections yet",
        message: "Add a Collection while organizing an Inbox Entry or First Time.",
        systemImage: "archivebox"
      )
    } else {
      LazyVStack(spacing: MTSpacing.s4) {
        ForEach(Array(controller.collections.enumerated()), id: \.element.id) { index, collection in
          NavigationLink(value: collection) {
            CollectionArchiveCard(collection: collection, index: index + 1)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(collection.name), \(countLabel(collection.entryCount, singular: "Entry"))"
          )
        }
      }
    }
  }
}

private struct CollectionArchiveCard: View {
  let collection: MemoCollection
  let index: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(String(format: "%02d", index))
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .tracking(0.8)
        Spacer()
        Image(systemName: "archivebox")
          .font(.system(size: 18))
      }
      .foregroundStyle(MTColor.warm)

      Text(collection.name)
        .font(MTTypography.title)
        .foregroundStyle(MTColor.ink)
        .padding(.top, MTSpacing.s8)

      Text(
        collection.entryCount == 0
          ? "Ready for its first Entry."
          : "\(countLabel(collection.entryCount, singular: "Entry")) filed here."
      )
      .font(MTTypography.body)
      .foregroundStyle(MTColor.inkMuted)
      .padding(.top, MTSpacing.s2)

      Spacer(minLength: MTSpacing.s8)

      Divider()
        .overlay(MTColor.border)

      HStack(spacing: MTSpacing.s2) {
        Text(collection.latestEntryLabel)
          .font(.system(size: 10))
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        if collection.unreviewedCount > 0 {
          Text("\(collection.unreviewedCount) in Inbox")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.warm)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MTColor.warmSubtle, in: Capsule())
        } else {
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      .padding(.top, MTSpacing.s3)
    }
    .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
    .padding(MTSpacing.s5)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}

private struct CollectionDetailView: View {
  @State private var controller: CollectionDetailController

  let collection: MemoCollection

  init(client: SupabaseClient, ownerID: UUID, collection: MemoCollection) {
    self.collection = collection
    _controller = State(
      initialValue: CollectionDetailController(
        client: client,
        ownerID: ownerID,
        collectionID: collection.id
      )
    )
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s5) {
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text("COLLECTION ARCHIVE")
            .font(MTTypography.caption)
            .tracking(1.1)
            .foregroundStyle(MTColor.warm)

          Text(collection.name)
            .font(MTTypography.display)
            .foregroundStyle(MTColor.ink)

          HStack(spacing: MTSpacing.s2) {
            Text(countLabel(collection.entryCount, singular: "Entry"))
            if collection.unreviewedCount > 0 {
              Text("·")
              Text("\(collection.unreviewedCount) still in Inbox")
            }
            Spacer()
            if controller.isLoading, controller.hasLoaded {
              ProgressView()
                .controlSize(.small)
            }
          }
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
        }

        detailContent
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle(collection.name)
    .navigationBarTitleDisplayMode(.inline)
    .refreshable {
      await controller.load()
    }
    .task {
      if !controller.hasLoaded {
        await controller.load()
      }
    }
  }

  @ViewBuilder
  private var detailContent: some View {
    if controller.isLoading, !controller.hasLoaded {
      loadingView("Loading \(collection.name)...")
    } else if let loadErrorMessage = controller.loadErrorMessage,
      controller.entries.isEmpty
    {
      archiveMessage(
        title: "Collection unavailable",
        message: loadErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.entries.isEmpty {
      archiveMessage(
        title: "This Collection is empty",
        message: "Assign \"\(collection.name)\" while organizing an Entry and it will appear here.",
        systemImage: "archivebox"
      )
    } else {
      LazyVStack(spacing: MTSpacing.s4) {
        ForEach(controller.entries) { entry in
          NavigationLink(value: entry) {
            CollectionEntryCard(entry: entry)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open \(entry.displayTitle)")
        }
      }

      if let loadErrorMessage = controller.loadErrorMessage {
        Label(loadErrorMessage, systemImage: "exclamationmark.circle")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }

      if controller.canLoadMore {
        Button("Load more", systemImage: "arrow.down") {
          Task { await controller.loadMore() }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("load-more-collection-entries")
      }
    }
  }
}

private struct CollectionEntryCard: View {
  let entry: CollectionEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let attachment = entry.coverAttachment {
        MTRemoteImage(
          url: attachment.signedURL,
          accessibilityLabel: attachment.originalFilename ?? "Entry photo"
        )
        .frame(height: 185)
        .clipped()
      }

      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          metadataBadge(entry.displayType)
          if entry.isInInbox {
            metadataBadge("In Inbox", isWarm: true)
          }
          Spacer()
          Text(entry.displayDate)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(MTColor.inkFaint)
            .multilineTextAlignment(.trailing)
        }

        Text(entry.displayTitle)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
          .multilineTextAlignment(.leading)

        if let excerpt = entry.displayExcerpt {
          Text(excerpt)
            .font(MTTypography.body)
            .foregroundStyle(MTColor.inkMuted)
            .lineSpacing(2)
            .lineLimit(4)
            .multilineTextAlignment(.leading)
        }

        organizationPills(entry: entry)

        HStack {
          Spacer()
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      .padding(MTSpacing.s4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}

@MainActor
private func metadataBadge(_ title: String, isWarm: Bool = false) -> some View {
  Text(title)
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(isWarm ? MTColor.warm : MTColor.inkMuted)
    .padding(.horizontal, MTSpacing.s2)
    .padding(.vertical, 4)
    .background(isWarm ? MTColor.warmSubtle : MTColor.surfaceSubtle, in: Capsule())
}

@MainActor @ViewBuilder
private func organizationPills(entry: CollectionEntry) -> some View {
  if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(entry.collectionNames, id: \.self) { name in
          Label(name, systemImage: "archivebox")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkMuted)
            .padding(.horizontal, MTSpacing.s2)
            .padding(.vertical, 5)
            .background(MTColor.surfaceSubtle, in: Capsule())
        }
        ForEach(entry.tagNames, id: \.self) { name in
          Text("#\(name)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkMuted)
            .padding(.horizontal, MTSpacing.s2)
            .padding(.vertical, 5)
            .background(MTColor.surfaceSubtle, in: Capsule())
        }
      }
    }
  }
}

@MainActor
private func loadingView(_ message: String) -> some View {
  HStack(spacing: MTSpacing.s3) {
    ProgressView()
    Text(message)
      .font(MTTypography.body)
      .foregroundStyle(MTColor.inkMuted)
  }
  .frame(maxWidth: .infinity, minHeight: 180)
}

@MainActor
private func archiveMessage(
  title: String,
  message: String,
  systemImage: String
) -> some View {
  HStack(alignment: .top, spacing: MTSpacing.s4) {
    Image(systemName: systemImage)
      .font(.system(size: 22, weight: .medium))
      .foregroundStyle(MTColor.accent)

    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text(title)
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)

      Text(message)
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }

    Spacer(minLength: 0)
  }
  .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
  .padding(MTSpacing.s6)
  .background(MTColor.surfaceSubtle.opacity(0.45))
  .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
  .overlay {
    RoundedRectangle(cornerRadius: MTRadius.large)
      .stroke(MTColor.border, lineWidth: 1)
  }
}

private func countLabel(_ count: Int, singular: String) -> String {
  "\(count) \(count == 1 ? singular : "\(singular)s")"
}
