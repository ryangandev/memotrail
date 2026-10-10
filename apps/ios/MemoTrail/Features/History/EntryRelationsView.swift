import Foundation
@preconcurrency import Supabase
import SwiftUI

/// Web `relationModes`: this Item's links, the Items that link here, and Items to link.
enum EntryRelationMode: String, CaseIterable, Sendable {
  case outgoing, incoming, candidates
  var title: String {
    switch self {
    case .outgoing: "Linked Items"
    case .incoming: "Linked from"
    case .candidates: "Find Items"
    }
  }
}
struct RelatedEntry: Decodable, Identifiable, Sendable {
  let entryID: UUID
  let title: String?
  let excerpt: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let isDeleted: Bool
  var id: UUID { entryID }
  var displayTitle: String {
    HistoryPresentation.title(title: title, body: excerpt)
  }
  enum CodingKeys: String, CodingKey {
    case title, excerpt
    case entryID = "entry_id"
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case isDeleted = "is_deleted"
  }
}
struct EntryRelationsResult: Decodable, Sendable {
  let revision: Int
  let items: [RelatedEntry]
  let totalCount: Int
  enum CodingKeys: String, CodingKey {
    case revision, items
    case totalCount = "total_count"
  }
}
struct EntryRelationsRequest: Encodable {
  let entryID: UUID
  let mode: EntryRelationMode
  let query: String
  let page: Int
  var isValid: Bool { query.count <= 200 && (0...5000).contains(page) }
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case mode = "p_mode"
    case query = "p_query"
    case limit = "p_limit"
    case offset = "p_offset"
  }
  func encode(to encoder: Encoder) throws {
    guard isValid else { throw URLError(.badURL) }
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(entryID, forKey: .entryID)
    try values.encode(mode.rawValue, forKey: .mode)
    try values.encode(query.trimmed, forKey: .query)
    try values.encode(20, forKey: .limit)
    try values.encode(page * 20, forKey: .offset)
  }
}
struct EntryRelationChange: Encodable {
  let entryID: UUID
  let targetID: UUID
  let expectedRevision: Int
  let linked: Bool
  var isValid: Bool { entryID != targetID && expectedRevision > 0 }
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case targetID = "p_target_id"
    case expectedRevision = "p_expected_revision"
    case linked = "p_linked"
  }
}

/// Web `EntryRelationsPanel`: links between existing Items, saved as soon as they change and kept
/// in this Item's history. The page that holds it opens a linked Item through `open`, since
/// lazy pages ignore navigation destinations.
struct EntryRelationsView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  let open: (UUID) -> Void
  let onChanged: @MainActor () async -> Void

  @State private var mode: EntryRelationMode = .outgoing
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var page = 0
  @State private var result: EntryRelationsResult?
  @State private var isBusy = true
  @State private var message: String?
  @State private var unlinkTarget: RelatedEntry?
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3_5) {
      Text("Related Items")
        .font(MTFont.heading)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      note(
        "Connect existing Entries without copying them. Link changes save immediately and stay in this Item's history."
      )
      MTFlowLayout(spacing: MTSpacing.s2) {
        ForEach(EntryRelationMode.allCases, id: \.self) { value in
          MTFilterChip(title: value.title, isSelected: mode == value) {
            query = ""
            Task { await load(value, query: "", page: 0) }
          }
          .disabled(isBusy)
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Relationship views")
      HStack(alignment: .bottom, spacing: MTSpacing.s2) {
        MTSearchField(
          "Search related Items", text: $query, prompt: "Title or words, including Chinese",
          maxLength: 200
        )
        .onSubmit { Task { await load(mode, query: query, page: 0) } }
        Button("Search") { Task { await load(mode, query: query, page: 0) } }
          .mtButtonStyle()
      }
      .disabled(isBusy)
      if mode == .incoming {
        note("These Items link here. Open the source Item to change its link.")
      } else if mode == .candidates {
        note("Choose an active Item to link. Existing outgoing links are omitted.")
      }
      if isBusy {
        HStack(spacing: MTSpacing.s2) {
          ProgressView().controlSize(.small).tint(MTColor.accent)
          note("Loading links...")
        }
      } else if let result {
        if result.items.isEmpty {
          note(mode == .candidates ? "No matching Items to link." : "No matching linked Items.")
        }
        VStack(spacing: 0) {
          ForEach(result.items) { row in
            relationRow(row)
          }
        }
        pagination(result)
      }
      if let message {
        Text(message)
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.warm)
      }
      Button("Refresh links") { Task { await load(mode, query: appliedQuery, page: page) } }
        .mtButtonStyle(.secondary)
        .disabled(isBusy)
    }
    .padding(horizontalSizeClass == .regular ? MTSpacing.s5 : MTSpacing.s3_5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Related Items")
    .task { await load(.outgoing, query: "", page: 0, force: true) }
    .confirmationDialog(
      "Unlink “\(unlinkTarget?.displayTitle ?? "this Item")”?",
      isPresented: Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } }),
      titleVisibility: .visible, presenting: unlinkTarget
    ) { target in
      Button("Unlink Item", role: .destructive) { Task { await change(target, linked: false) } }
      Button("Cancel", role: .cancel) {}
    } message: { _ in
      Text("Neither Item is deleted. This change can be restored through this Item's history.")
    }
  }

  private func note(_ text: String) -> some View {
    Text(text)
      .font(MTFont.supporting)
      .foregroundStyle(MTColor.inkMuted)
      .fixedSize(horizontal: false, vertical: true)
  }

  /// Web's relation row: the Item, its Kind and excerpt, and Link Item or Unlink.
  private func relationRow(_ row: RelatedEntry) -> some View {
    let layout =
      horizontalSizeClass == .regular
      ? AnyLayout(HStackLayout(alignment: .center, spacing: MTSpacing.s3))
      : AnyLayout(VStackLayout(alignment: .leading, spacing: MTSpacing.s3))
    return layout {
      VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
        Button(row.displayTitle) { open(row.entryID) }
          .buttonStyle(.plain)
          .font(MTFont.body)
          .foregroundStyle(MTColor.accent)
          .multilineTextAlignment(.leading)
        Text(
          row.itemKind.displayName(subtype: row.itemSubtype) + (row.isDeleted ? " · In Trash" : "")
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        if let excerpt = row.excerpt.trimmed.nonEmpty {
          Text(excerpt)
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if mode != .incoming {
        Button(mode == .candidates ? "Link Item" : "Unlink") {
          if mode == .candidates {
            Task { await change(row, linked: true) }
          } else {
            unlinkTarget = row
          }
        }
        .mtButtonStyle(.secondary, size: .small)
        .accessibilityLabel("\(mode == .candidates ? "Link" : "Unlink") \(row.displayTitle)")
      }
    }
    .padding(.vertical, MTSpacing.s3)
    .overlay(alignment: .bottom) { MTListDivider() }
  }

  private func pagination(_ result: EntryRelationsResult) -> some View {
    HStack(spacing: MTSpacing.s2) {
      Button("Previous links") { Task { await load(mode, query: appliedQuery, page: page - 1) } }
        .mtButtonStyle(.secondary, size: .small)
        .disabled(page == 0)
      Spacer(minLength: 0)
      Text("Page \(page + 1) · \(countLabel(result.totalCount, "Item"))")
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
      Spacer(minLength: 0)
      Button("Next links") { Task { await load(mode, query: appliedQuery, page: page + 1) } }
        .mtButtonStyle(.secondary, size: .small)
        .disabled((page + 1) * 20 >= result.totalCount)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Relationship pages")
  }

  private func load(
    _ requestedMode: EntryRelationMode, query search: String, page requestedPage: Int,
    force: Bool = false
  ) async {
    let request = EntryRelationsRequest(
      entryID: entryID, mode: requestedMode, query: search, page: requestedPage)
    guard force || !isBusy, request.isValid else { return }
    isBusy = true
    message = nil
    defer { isBusy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let value: EntryRelationsResult? = try await client.rpc("entry_relations", params: request)
        .execute().value
      guard let value else { throw URLError(.badServerResponse) }
      mode = requestedMode
      page = requestedPage
      appliedQuery = search.trimmed
      result = value
    } catch {
      result = nil
      message = "Links could not load. Refresh to try again."
    }
  }

  private func change(_ row: RelatedEntry, linked: Bool) async {
    guard !isBusy, let result else { return }
    let input = EntryRelationChange(
      entryID: entryID, targetID: row.entryID, expectedRevision: result.revision, linked: linked)
    guard input.isValid else {
      message = "Choose a different valid Item."
      return
    }
    isBusy = true
    message = nil
    if let failure = await save(input) {
      message = failure
      isBusy = false
      return
    }
    query = ""
    MTToastCenter.shared.success(linked ? "Item linked." : "Item unlinked.")
    await load(.outgoing, query: "", page: 0, force: true)
    await onChanged()
  }

  /// Web `changeEntryRelation`; returns the failure message, if any.
  private func save(_ input: EntryRelationChange) async -> String? {
    guard (try? await client.auth.session.user.id) == ownerID else {
      return "Sign in again to change links."
    }
    do {
      let revision: Int? = try await client.rpc("set_entry_relation", params: input).execute()
        .value
      return revision == nil
        ? "This Item changed or a linked Item is unavailable. Refresh before retrying." : nil
    } catch let error as PostgrestError where error.message == "relation_limit" {
      return "This Item already has 100 links. Remove a link before adding another."
    } catch {
      return "Could not confirm this link change. Refresh before retrying."
    }
  }
}
