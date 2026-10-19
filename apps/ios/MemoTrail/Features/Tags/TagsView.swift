@preconcurrency import Supabase
import SwiftUI

/// Web `/tags`: every tag as a badge with how many Entries use it, a name search, and New Tag.
/// Each badge opens the tag's editor, which lists its Entries and merges or deletes it.
struct TagsView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var tags: [TagItem] = []
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var totalCount = 0
  @State private var hasLoaded = false
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var errorMessage: String?
  @State private var moreErrorMessage: String?
  @State private var editing: Editing?
  /// Where to go once the editor has closed, since switching tabs or pushing a page while it
  /// closes would cancel the dismissal.
  @State private var afterEditing: (@MainActor () -> Void)?
  /// The Entries revision this page last reacted to, so its own changes reload it only once.
  @State private var seenRevision = 0
  @Environment(AppNavigator.self) private var navigator

  /// The tag editor: a new tag, or a saved one.
  private struct Editing: Identifiable {
    let item: TagItem?
    var id: UUID? { item?.id }
  }

  private var actions: OrganizationActions { OrganizationActions(client: client, ownerID: ownerID) }

  var body: some View {
    MTPage(width: .standard, spacing: MTSpacing.s6) {
      MTPageHeader(
        eyebrow: "Your data", title: "Tags",
        description:
          "Tags group related Entries, such as travel, family, or a trip you want to keep together. Use them across Entry types and filter by them anywhere."
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
      TagEditorSheet(
        actions: actions, item: editing.item, mergeTargets: tags,
        changed: {
          await load(query: appliedQuery)
          navigator.entriesChanged()
          seenRevision = navigator.entriesRevision
        },
        openEntry: { entry in
          // Tags is a page in the More tab, so its Entries open on that stack.
          afterEditing = { navigator.morePath.append(ItemLink(entryID: entry.id)) }
        },
        openAllEntries: { name in afterEditing = { navigator.openLibrary(tag: name) } })
    }
    .task {
      if !hasLoaded { await load() }
    }
    .onChange(of: navigator.entriesRevision) { _, revision in
      // An Entry saved, trashed, restored, or synced elsewhere changes the tag counts.
      guard revision != seenRevision, hasLoaded else { return }
      seenRevision = revision
      Task { await load(query: appliedQuery) }
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
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
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
          .font(MTFont.detail)
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

  private func load(query search: String? = nil) async {
    guard !isLoading else { return }
    isLoading = true
    defer {
      isLoading = false
      hasLoaded = true
    }
    let search = String((search ?? appliedQuery).trimmed.prefix(200))
    do {
      tags = try await actions.load(query: search)
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
      let next = try await actions.load(query: appliedQuery, offset: tags.count)
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
  let tag: TagItem
  let edit: () -> Void

  var body: some View {
    Button(action: edit) {
      HStack(spacing: MTSpacing.s1_5) {
        Text("#")
          .font(MTFont.tagMark)
          .foregroundStyle(MTColor.accent)
        Text(tag.name)
          .font(MTFont.label)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
          .truncationMode(.tail)
        Text("\(tag.entryCount)")
          .font(MTFont.stamp)
          .foregroundStyle(MTColor.inkMuted)
          .padding(.horizontal, MTSpacing.s1_5)
          .frame(minWidth: MTLayout.TagChip.count, minHeight: MTLayout.TagChip.count)
          .background(MTColor.surfaceSubtle, in: Capsule())
      }
      .padding(.horizontal, MTSpacing.s3)
      .frame(minHeight: MTLayout.TagChip.height)
      .background(MTColor.surface, in: Capsule())
      .overlay { Capsule().strokeBorder(MTColor.border) }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Manage tag \(tag.name), used by \(countLabel(tag.entryCount, "Entry"))")
  }
}
