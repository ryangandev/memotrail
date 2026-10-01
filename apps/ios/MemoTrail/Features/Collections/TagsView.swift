@preconcurrency import Supabase
import SwiftUI

/// Web `/tags`: every tag as a badge with how many Entries use it, a name search, and New Tag.
/// Each badge opens the tag's editor, which lists its Entries and merges or deletes it.
struct TagsView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var tags: [OrganizationItem] = []
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var totalCount = 0
  @State private var hasLoaded = false
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var moreErrorMessage: String?
  @State private var editing: Editing?
  @State private var opened: WikiItemLink?
  /// Where to go once the editor has closed, since switching tabs or pushing a page while it
  /// closes would cancel the dismissal.
  @State private var afterEditing: (@MainActor () -> Void)?
  @Environment(AppNavigator.self) private var navigator

  /// The tag editor: a new tag, or a saved one.
  private struct Editing: Identifiable {
    let item: OrganizationItem?
    var id: UUID? { item?.id }
  }

  private var actions: OrganizationActions { OrganizationActions(client: client, ownerID: ownerID) }

  var body: some View {
    MTPage(width: .standard, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Filter across your archive", title: "Tags",
        description:
          "Tags are lightweight descriptors such as travel, family, or funny. Use them across Entry types when you want a flexible filter, not a curated chapter."
      ) {
        Button {
          editing = Editing(item: nil)
        } label: {
          Label("New Tag", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("new-tag")
      }
      search
      content
    }
    .refreshable { await load() }
    .navigationTitle("Tags")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $editing) {
      afterEditing?()
      afterEditing = nil
    } content: { editing in
      OrganizationEditorSheet(
        actions: actions, kind: .tag, item: editing.item, mergeTargets: tags,
        changed: { await load(query: appliedQuery) },
        openEntry: { entry in afterEditing = { open(WikiItemLink(entry)) } },
        openAllEntries: { name in afterEditing = { navigator.openLibrary(tag: name) } })
    }
    .wikiItemDestination($opened, client: client, ownerID: ownerID)
    .task {
      if !hasLoaded { await load() }
    }
  }

  /// Web's tag search: a large field beside Search.
  private var search: some View {
    HStack(alignment: .center, spacing: MTSpacing.s3) {
      MTSearchField(
        "Find a tag", text: $query, prompt: "Search tag names", size: .large, hidesLabel: true,
        maxLength: 200
      )
      .onSubmit { Task { await load(query: query) } }
      .accessibilityIdentifier("tag-search")
      Button {
        Task { await load(query: query) }
      } label: {
        Label("Search", icon: .search)
      }
      .mtButtonStyle(size: .large)
      .disabled(isLoading)
    }
  }

  @ViewBuilder private var content: some View {
    if !hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your tags...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let errorMessage {
      MTEmptyState(title: "Tags unavailable", message: errorMessage, icon: .tag) {
        Button("Try again") { Task { await load(query: appliedQuery) } }
          .mtButtonStyle(.secondary)
      }
    } else if tags.isEmpty {
      MTEmptyState(
        title: appliedQuery.isEmpty ? "No tags yet" : "No matching tags",
        message: appliedQuery.isEmpty
          ? "Add a tag here or while editing any Entry. It will become available everywhere."
          : "Try a different name or clear your search.",
        icon: .tag)
    } else {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        Text(countLabel(totalCount, "tag"))
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
        MTFlowLayout(spacing: MTSpacing.s3) {
          ForEach(tags) { tag in
            TagBadge(tag: tag) { editing = Editing(item: tag) }
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tags")
        if tags.count < totalCount || moreErrorMessage != nil {
          MTLoadMore(isLoading: isLoadingMore, message: moreErrorMessage) { await loadMore() }
        }
      }
    }
  }

  private func open(_ link: WikiItemLink) {
    navigator.open(link) { opened = $0 }
  }

  private func load(query search: String? = nil) async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    let search = String((search ?? appliedQuery).trimmed.prefix(200))
    do {
      tags = try await actions.load(.tag, query: search)
      totalCount = tags.first?.totalCount ?? 0
      appliedQuery = search
      errorMessage = nil
      moreErrorMessage = nil
    } catch {
      errorMessage = "MemoTrail could not load your tags. Refresh to try again."
    }
  }

  private func loadMore() async {
    guard !isLoading, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let next = try await actions.load(.tag, query: appliedQuery, offset: tags.count)
      let known = Set(tags.map(\.id))
      tags += next.filter { !known.contains($0.id) }
      moreErrorMessage = next.isEmpty && tags.count < totalCount ? "Could not load more tags." : nil
    } catch {
      moreErrorMessage = "Could not load more tags."
    }
  }
}

/// Web `tagBadge`: the tag's mark, name, and Entry count in one pill that opens its editor.
private struct TagBadge: View {
  let tag: OrganizationItem
  let edit: () -> Void

  var body: some View {
    Button(action: edit) {
      HStack(spacing: 6) {
        Text("#")
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(MTColor.accent)
        Text(tag.name)
          .font(MTFont.label.weight(.medium))
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
          .truncationMode(.tail)
        Text("\(tag.entryCount)")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(MTColor.inkMuted)
          .padding(.horizontal, 6)
          .frame(minWidth: 22, minHeight: 22)
          .background(MTColor.surfaceSubtle, in: Capsule())
      }
      .padding(.horizontal, MTSpacing.s3)
      .frame(minHeight: 42)
      .background(MTColor.surface, in: Capsule())
      .overlay { Capsule().strokeBorder(MTColor.border) }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Manage tag \(tag.name), used by \(countLabel(tag.entryCount, "Entry"))")
  }
}
