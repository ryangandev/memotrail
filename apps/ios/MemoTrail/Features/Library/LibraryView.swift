@preconcurrency import Supabase
import SwiftUI

struct LibraryView: View {
  private let client: SupabaseClient
  private let ownerID: UUID
  @State private var controller: LibraryController

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: LibraryController(client: client, ownerID: ownerID))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          allItemsSection
          availableSection
          toolsSection
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .background(MTColor.canvas)
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .navigationDestination(for: WikiItemSummary.self) { item in
        wikiItemDestination(item)
      }
      .refreshable { await controller.load() }
      .task(id: controller.filterIdentity) {
        if controller.hasLoaded {
          try? await Task.sleep(for: .milliseconds(280))
        }
        guard !Task.isCancelled else { return }
        await controller.load()
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("YOUR PERSONAL ARCHIVE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)

      Text("Library")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Browse your Entries, focused records, and Goals.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var allItemsSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      sectionTitle(
        "ALL ITEMS",
        subtitle: "\(controller.totalCount) \(controller.totalCount == 1 ? "item" : "items")"
      )

      searchField
      kindFilters
      wikiItemsContent
    }
  }

  private var searchField: some View {
    HStack(spacing: MTSpacing.s3) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(MTColor.inkFaint)
      TextField("Find in your Life Wiki", text: $controller.query)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .onChange(of: controller.query) { _, value in
          if value.count > 200 { controller.query = String(value.prefix(200)) }
        }
      if !controller.query.isEmpty {
        Button {
          controller.query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(MTColor.inkFaint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear Life Wiki search")
      }
    }
    .padding(.horizontal, MTSpacing.s4)
    .frame(minHeight: 48)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  private var kindFilters: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: MTSpacing.s2) {
        kindButton(title: "All", kind: nil)
        ForEach(WikiItemKind.allCases, id: \.self) { kind in
          kindButton(title: kindFilterTitle(kind), kind: kind)
        }
      }
    }
  }

  @ViewBuilder
  private var wikiItemsContent: some View {
    if controller.isLoading, !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView()
        Text("Loading your Life Wiki...")
          .foregroundStyle(MTColor.inkMuted)
      }
      .font(MTTypography.body)
      .frame(maxWidth: .infinity, minHeight: 160)
    } else if let errorMessage = controller.errorMessage, controller.items.isEmpty {
      libraryMessage(
        title: "Life Wiki unavailable",
        message: errorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if controller.items.isEmpty {
      libraryMessage(
        title: "No matching items",
        message: "Try another phrase or Kind, or capture something new.",
        systemImage: "books.vertical"
      )
    } else {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 260), spacing: MTSpacing.s3)],
        alignment: .leading,
        spacing: MTSpacing.s3
      ) {
        ForEach(controller.items) { item in
          NavigationLink(value: item) {
            WikiItemCard(item: item)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Open \(item.identityLabel), \(item.title)")
        }
      }

      if let errorMessage = controller.errorMessage {
        Text(errorMessage)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }

      if controller.canLoadMore {
        Button("Load older items") {
          Task { await controller.loadMore() }
        }
        .frame(maxWidth: .infinity)
      } else if controller.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var availableSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionTitle("BROWSE BY STRUCTURE", subtitle: "Focused records")

      ForEach(LibraryDestination.available) { destination in
        NavigationLink {
          availableDestination(destination)
        } label: {
          LibraryDestinationCard(destination: destination)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-\(destination.rawValue)")
      }
    }
  }

  private var toolsSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      sectionTitle("LIBRARY TOOLS", subtitle: "Organize, recover, and export")

      libraryTool(title: "Organization", systemImage: "tag") {
        OrganizationView(client: client, ownerID: ownerID)
      }
      libraryTool(title: "Entry history", systemImage: "clock.arrow.circlepath") {
        EntryHistoryIndexView(client: client, ownerID: ownerID)
      }
      libraryTool(title: "Export archive", systemImage: "square.and.arrow.up") {
        ExportView(client: client, ownerID: ownerID)
      }
      libraryTool(title: "AI settings", systemImage: "sparkles") {
        AISettingsView(client: client, ownerID: ownerID)
      }
    }
  }

  private func kindButton(title: String, kind: WikiItemKind?) -> some View {
    let isSelected = controller.selectedKind == kind
    return Button {
      controller.selectedKind = kind
    } label: {
      Text(title)
        .font(MTTypography.caption)
        .foregroundStyle(isSelected ? MTColor.accentInk : MTColor.inkMuted)
        .padding(.horizontal, MTSpacing.s3)
        .padding(.vertical, MTSpacing.s2)
        .background(isSelected ? MTColor.accent : MTColor.surfaceSubtle, in: Capsule())
    }
    .buttonStyle(.plain)
  }

  private func sectionTitle(_ title: String, subtitle: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .font(MTTypography.label)
        .tracking(0.7)
        .foregroundStyle(MTColor.ink)

      Spacer()

      Text(subtitle)
        .font(.system(size: 10))
        .foregroundStyle(MTColor.inkFaint)
        .multilineTextAlignment(.trailing)
    }
  }

  private func libraryMessage(title: String, message: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(MTColor.accent)
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(title).font(MTTypography.titleSmall).foregroundStyle(MTColor.ink)
        Text(message).font(MTTypography.body).foregroundStyle(MTColor.inkMuted)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(MTColor.surfaceSubtle.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
  }

  private func kindFilterTitle(_ kind: WikiItemKind) -> String {
    switch kind {
    case .entry: "Entries"
    case .entity: "Entities"
    case .goal: "Goals"
    }
  }

  @ViewBuilder
  private func libraryTool<Destination: View>(
    title: String,
    systemImage: String,
    @ViewBuilder destination: () -> Destination
  ) -> some View {
    NavigationLink(destination: destination()) {
      HStack(spacing: MTSpacing.s3) {
        Image(systemName: systemImage)
          .foregroundStyle(MTColor.accent)
          .frame(width: 24)
        Text(title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MTColor.inkFaint)
      }
      .padding(MTSpacing.s4)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func availableDestination(_ destination: LibraryDestination) -> some View {
    switch destination {
    case .collections:
      CollectionsView(client: client, ownerID: ownerID, embedded: true)
    case .firstTimes:
      FirstTimesView(client: client, ownerID: ownerID, embedded: true)
    case .homes:
      HomesView(client: client, ownerID: ownerID, embedded: true)
    case .vehicles:
      VehiclesView(client: client, ownerID: ownerID, embedded: true)
    case .goals:
      GoalsView(client: client, ownerID: ownerID, embedded: true)
    case .trash:
      TrashView(client: client, ownerID: ownerID, embedded: true)
    case .people:
      PeopleView(client: client, ownerID: ownerID)
    }
  }

  @ViewBuilder
  private func wikiItemDestination(_ item: WikiItemSummary) -> some View {
    switch (item.itemKind, item.itemSubtype, item.recordSource) {
    case (.entity, "person", .person):
      PeopleView(client: client, ownerID: ownerID, focusedPersonID: item.recordID)
    case (.entity, "home", _):
      HomesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: item.id)
    case (.entity, "vehicle", _):
      VehiclesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: item.id)
    case (.goal, _, _):
      GoalsView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: item.id)
    case (.entry, "first_time", _):
      FirstTimesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: item.id)
    default:
      EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: item.id)
    }
  }
}

private struct WikiItemCard: View {
  let item: WikiItemSummary

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(spacing: MTSpacing.s2) {
        Text(item.itemKind.displayName)
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(MTColor.accent)
          .padding(.horizontal, MTSpacing.s2)
          .padding(.vertical, 4)
          .background(MTColor.accentSubtle, in: Capsule())

        if item.subtypeLabel != item.itemKind.displayName {
          Text(item.subtypeLabel)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.inkMuted)
        }

        if item.isInInbox {
          Text("IN INBOX")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(MTColor.warm)
        }

        Spacer(minLength: 0)
      }

      Text(item.title)
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)
        .lineLimit(2)

      if !item.excerpt.trimmed.isEmpty {
        Text(item.excerpt)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkMuted)
          .lineLimit(3)
      }

      HStack {
        Text(item.dateLabel)
          .font(.system(size: 10))
          .foregroundStyle(MTColor.inkFaint)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MTColor.inkFaint)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay { RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border) }
  }
}

private struct LibraryDestinationCard: View {
  let destination: LibraryDestination

  var body: some View {
    HStack(spacing: MTSpacing.s4) {
      Image(systemName: destination.systemImage)
        .font(.system(size: 19, weight: .medium))
        .foregroundStyle(MTColor.accent)
        .frame(width: 44, height: 44)
        .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))

      VStack(alignment: .leading, spacing: 4) {
        Text(destination.title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)

        Text(destination.summary)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
          .lineLimit(2)
      }

      Spacer(minLength: MTSpacing.s2)

      Image(systemName: "chevron.right")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
    .padding(.horizontal, MTSpacing.s4)
    .padding(.vertical, MTSpacing.s3)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}
