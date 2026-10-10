@preconcurrency import Supabase
import SwiftUI

/// Web `/history`: every Item with earlier versions, newest change first, with a search over
/// titles and current words. Each opens its version history.
struct EntryHistoryIndexView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var rows: [HistoryIndexEntry] = []
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var hasLoaded = false
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var moreErrorMessage: String?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private static let pageSize = 50

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s5) {
      HistoryPageHeader()
      search
      if !hasLoaded {
        HStack(spacing: MTSpacing.s3) {
          ProgressView().tint(MTColor.accent)
          Text("Loading version history...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
      } else if let errorMessage {
        MTEmptyState(title: "History unavailable", message: errorMessage, icon: .history) {
          Button("Try again") { Task { await load() } }
            .mtButtonStyle(.secondary)
        }
      } else if rows.isEmpty {
        HistoryNotice(
          text: "No matching history yet. Earlier versions appear after an item is edited.")
      } else {
        VStack(spacing: MTSpacing.s3) {
          ForEach(rows) { row in
            NavigationLink {
              EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: row.entryID)
            } label: {
              HistoryIndexRow(row: row)
            }
            .buttonStyle(MTCardButtonStyle())
          }
        }
        if rows.count < (rows.first?.totalCount ?? 0) || moreErrorMessage != nil {
          MTLoadMore(isLoading: isLoadingMore, message: moreErrorMessage) { await loadMore() }
        }
      }
    }
    .refreshable { await load() }
    .navigationTitle("Version history")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if !hasLoaded { await load() }
    }
  }

  /// Web's history search: stacked on phones, side by side on wider screens.
  private var search: some View {
    let layout =
      horizontalSizeClass == .regular
      ? AnyLayout(HStackLayout(alignment: .bottom, spacing: MTSpacing.actionGap))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: MTSpacing.s2))
    return layout {
      MTSearchField(
        "Find an item", text: $query, prompt: "Title or words in the current item",
        maxLength: 200
      )
      .onSubmit { Task { await load() } }
      .accessibilityIdentifier("history-search")
      Button("Search history") { Task { await load() } }
        .mtButtonStyle(fillsWidth: horizontalSizeClass != .regular)
        .disabled(isLoading)
    }
  }

  private func load() async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    let search = String(query.trimmed.prefix(200))
    do {
      rows = try await page(query: search, offset: 0)
      appliedQuery = search
      errorMessage = nil
      moreErrorMessage = nil
    } catch {
      errorMessage = "History could not load. Refresh to try again."
    }
  }

  private func loadMore() async {
    guard !isLoading, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await page(query: appliedQuery, offset: rows.count)
      let known = Set(rows.map(\.id))
      rows += next.filter { !known.contains($0.id) }
      moreErrorMessage = nil
      if next.isEmpty, let total = rows.first?.totalCount, rows.count < total {
        moreErrorMessage = "Could not load more history."
      }
    } catch {
      moreErrorMessage = "Could not load more history."
    }
  }

  private func page(query: String, offset: Int) async throws -> [HistoryIndexEntry] {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
    return try await client.rpc(
      "entry_history_index",
      params: HistoryIndexRequest(query: query, limit: Self.pageSize, offset: offset)
    ).execute().value
  }
}

/// Web History list link: the title, its Kind and number of earlier versions, and an excerpt.
private struct HistoryIndexRow: View {
  let row: HistoryIndexEntry

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text(row.displayTitle)
        .font(MTFont.bodyStrong)
        .foregroundStyle(MTColor.ink)
        .multilineTextAlignment(.leading)
      MTWordFlow(.caption1) {
        Text(row.itemKind.displayName(subtype: row.itemSubtype))
        MTFlowSeparator()
        Text(countLabel(row.versionCount, "earlier version"))
        if row.isDeleted {
          MTFlowSeparator()
          Text("In Trash")
        }
      }
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      if let excerpt = row.excerpt.trimmed.nonEmpty {
        Text(excerpt)
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.ink)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s5)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Web `/history` page header, shared by the list and an Item's versions.
private struct HistoryPageHeader: View {
  var body: some View {
    MTPageHeader(
      eyebrow: "Nothing good has to be lost", title: "Version history",
      description:
        "Revisit earlier versions of anything in your Life Wiki. Restoring always keeps the current version first."
    )
  }
}

/// Web `/history?entry=<id>`: an Item's earlier versions beside its current one, with Restore,
/// the Item's actions, Related Items, and current photos.
struct EntryHistoryDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID

  @State private var controller: EntryHistoryController
  @State private var selectedVersion: Int?
  @State private var destination: Destination?
  @State private var editingEntry: InboxEntry?
  @State private var isCreatingGoal = false
  @State private var isConfirmingRestore = false
  @State private var errorMessage: String?
  @Environment(AppNavigator.self) private var navigator
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  private enum Destination: Hashable {
    case firstTime
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
    MTPage(width: .wide, spacing: MTSpacing.s5) {
      HistoryPageHeader()
      if let record = controller.record {
        content(record)
      } else if !controller.hasLoaded {
        HStack(spacing: MTSpacing.s3) {
          ProgressView().tint(MTColor.accent)
          Text("Loading version history...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
        }
        .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
      } else if controller.loadFailed {
        MTEmptyState(
          title: "History unavailable", message: "History could not load. Refresh to try again.",
          icon: .history
        ) {
          Button("Try again") { Task { await controller.reload() } }
            .mtButtonStyle(.secondary)
        }
      } else {
        HistoryNotice(text: "This item is no longer available.")
      }
    }
    .refreshable { await controller.load(page: controller.page) }
    .navigationTitle("Version history")
    .navigationBarTitleDisplayMode(.inline)
    .reloadOnReturn(from: destination != nil) { await controller.load(page: controller.page) }
    .navigationDestination(item: $destination) { destination in
      switch destination {
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
    .onChange(of: controller.record?.versions.map(\.version), initial: true) { _, versions in
      // Like Web, each loaded page starts on its newest earlier version.
      selectedVersion = versions?.first
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  @ViewBuilder
  private func content(_ record: EntryHistoryRecord) -> some View {
    Text(record.title)
      .font(MTFont.recordTitle)
      .foregroundStyle(MTColor.ink)
      .accessibilityAddTraits(.isHeader)
    WikiItemActions(record: record, isItemPage: false, isBusy: controller.isWorking) {
      perform($0)
    }
    if let errorMessage {
      Text(errorMessage)
        .font(MTFont.body)
        .foregroundStyle(MTColor.warm)
        .accessibilityAddTraits(.updatesFrequently)
    }
    WikiItemProvenanceLinks(record: record) { destination = .item($0) }
    if !record.versions.isEmpty {
      restoreControls(record)
    }
    if record.isDeleted {
      Text("This item is in Trash. Restore it there before changing its history.")
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
    }
    if let version = record.versions.first(where: { $0.version == selectedVersion }) {
      comparison(record, version)
    } else {
      Text("No earlier versions on this page.")
        .font(MTFont.body)
        .foregroundStyle(MTColor.inkMuted)
      HistorySnapshotCard(
        heading: "Current · version \(record.revision)", snapshot: record.current)
    }
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
    pagination(record)
  }

  /// Web's version picker beside Restore, stacked on phones.
  private func restoreControls(_ record: EntryHistoryRecord) -> some View {
    let layout =
      horizontalSizeClass == .regular
      ? AnyLayout(HStackLayout(alignment: .bottom, spacing: MTSpacing.s4))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: MTSpacing.s3))
    return layout {
      MTSelectField(
        label: "Earlier version", selection: $selectedVersion,
        options: record.versions.map { Optional($0.version) },
        title: { number in
          guard let version = record.versions.first(where: { $0.version == number }) else {
            return "Choose a version"
          }
          // Web's `toLocaleString()`, without seconds.
          let saved = version.savedAt?.formatted(date: .numeric, time: .shortened)
          return "Version \(version.version)" + (saved.map { " · saved before \($0)" } ?? "")
        }
      )
      .disabled(controller.isWorking)
      .accessibilityIdentifier("history-version")
      Button("Restore selected version") { isConfirmingRestore = true }
        .mtButtonStyle(
          .secondary, isLoading: controller.isWorking,
          fillsWidth: horizontalSizeClass != .regular
        )
        .disabled(!canRestoreSelected(record) || record.isDeleted)
        .accessibilityHint(
          canRestoreSelected(record) ? "" : HistoryPresentation.unsupportedRestoreMessage
        )
        .accessibilityIdentifier("restore-version")
        .confirmationDialog(
          "Restore version \(selectedVersion ?? 0)?", isPresented: $isConfirmingRestore,
          titleVisibility: .visible
        ) {
          Button("Restore version") { Task { await restore() } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text(
            "Your current version will remain in history. Recorded links and photo membership will also be restored, while shared Collection and tag definitions stay current."
          )
        }
    }
  }

  @ViewBuilder
  private func comparison(_ record: EntryHistoryRecord, _ version: EntryHistoryVersion)
    -> some View
  {
    let differences = HistoryPresentation.differences(
      current: record.current, previous: version.snapshot)
    let canRestore = HistoryPresentation.canRestore(version.snapshot)
    HistoryNotice(
      text:
        "Differences from current version: \(differences.joined(separator: ", ").nonEmpty ?? "No recorded content changes")."
        + (canRestore ? " Your current version \(record.revision) will stay in history." : "")
    )
    if canRestore {
      Text(
        "People, Collection, and track definitions stay current. Historical Location links return to their original snapshots. Photo files are not deleted. Missing historical links or originals stop the restore safely."
      )
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
      .fixedSize(horizontal: false, vertical: true)
    } else {
      HistoryNotice(text: HistoryPresentation.unsupportedRestoreMessage, tone: .caution)
        .accessibilityIdentifier("history-restore-unavailable")
    }
    let layout =
      horizontalSizeClass == .regular
      ? AnyLayout(HStackLayout(alignment: .top, spacing: MTSpacing.s5))
      : AnyLayout(VStackLayout(spacing: MTSpacing.s5))
    layout {
      HistorySnapshotCard(heading: "Version \(version.version)", snapshot: version.snapshot)
      HistorySnapshotCard(
        heading: "Current · version \(record.revision)", snapshot: record.current)
    }
  }

  /// Web's version pages: twenty earlier versions at a time.
  @ViewBuilder
  private func pagination(_ record: EntryHistoryRecord) -> some View {
    if controller.page > 0 || controller.hasOlderVersions {
      HStack(spacing: MTSpacing.panelGap) {
        if controller.page > 0 {
          Button("Newer versions") { Task { await controller.load(page: controller.page - 1) } }
            .mtButtonStyle(.ghost, size: .small)
        }
        Spacer(minLength: 0)
        Text("Page \(controller.page + 1)")
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.inkMuted)
        Spacer(minLength: 0)
        if controller.hasOlderVersions {
          Button("Older versions") { Task { await controller.load(page: controller.page + 1) } }
            .mtButtonStyle(.ghost, size: .small)
        }
      }
      .disabled(controller.isLoading)
    }
  }

  private func perform(_ action: WikiItemActions.Action) {
    errorMessage = nil
    switch action {
    case .edit: Task { await openEditor() }
    case .openFirstTime: destination = .firstTime
    case .openOnTimeline: navigator.openTimelineEntry(entryID)
    case .createGoal: isCreatingGoal = true
    case .openGoal: destination = .goal(entryID)
    case .history, .trash: break
    }
  }

  private func openEditor() async {
    if let entry = await controller.editableEntry() {
      editingEntry = entry
    } else {
      errorMessage = "This item cannot be edited right now. Refresh and try again."
    }
  }

  /// Web `canRestoreSelected`: a version is chosen and its snapshot uses the restorable schema.
  private func canRestoreSelected(_ record: EntryHistoryRecord) -> Bool {
    HistoryPresentation.canRestore(
      record.versions.first { $0.version == selectedVersion }?.snapshot)
  }

  private func restore() async {
    guard let selectedVersion, let record = controller.record, canRestoreSelected(record)
    else { return }
    errorMessage = nil
    if let message = await controller.restore(version: selectedVersion) {
      errorMessage = message
    } else {
      MTToastCenter.shared.success("Version restored.")
    }
  }
}
