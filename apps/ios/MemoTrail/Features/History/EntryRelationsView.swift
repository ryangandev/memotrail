import Foundation
@preconcurrency import Supabase
import SwiftUI

enum EntryRelationMode: String, CaseIterable, Sendable {
  case outgoing, incoming, candidates
  var title: String {
    switch self {
    case .outgoing: "Linked Entries"
    case .incoming: "Linked from"
    case .candidates: "Find Entries"
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
    title?.trimmed.nonEmpty ?? String(excerpt.prefix(80)).nonEmpty ?? "Untitled Entry"
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

struct EntryRelationsView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  let onChanged: @MainActor () async -> Void
  @State private var mode: EntryRelationMode = .outgoing
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var page = 0
  @State private var result: EntryRelationsResult?
  @State private var busy = false
  @State private var message: String?
  @State private var unlinkTarget: RelatedEntry?
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Related Entries").font(MTTypography.titleSmall)
      Text(
        "Connect existing writing without copying it. Link changes save immediately and stay in this Entry's history."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      ViewThatFits(in: .horizontal) {
        HStack { modeButtons }
        VStack(alignment: .leading) { modeButtons }
      }
      HStack {
        TextField("Search related Entries", text: $query).textFieldStyle(.roundedBorder)
          .onSubmit { Task { await load(mode, query: query, page: 0) } }
        Button("Search") { Task { await load(mode, query: query, page: 0) } }
          .disabled(query.count > 200)
      }
      if mode == .incoming {
        Text("These Entries link here. Open the source Entry to change its link.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      } else if mode == .candidates {
        Text("Choose an active Entry to link. Existing outgoing links are omitted.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      }
      if busy {
        ProgressView("Loading links...")
      } else if let result {
        if result.items.isEmpty {
          Text(mode == .candidates ? "No matching Entries to link." : "No matching linked Entries.")
            .foregroundStyle(MTColor.inkMuted)
        }
        ForEach(result.items) { row in
          VStack(alignment: .leading, spacing: 8) {
            NavigationLink(row.displayTitle) {
              EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: row.entryID)
            }
            Text(
              row.itemKind.displayName(subtype: row.itemSubtype)
                + (row.isDeleted ? " · In Trash" : "")
            )
            .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            Text(row.excerpt).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            if mode != .incoming {
              Button(mode == .candidates ? "Link Entry" : "Unlink") {
                if mode == .candidates {
                  Task { await change(row, linked: true) }
                } else {
                  unlinkTarget = row
                }
              }.accessibilityLabel("\(mode == .candidates ? "Link" : "Unlink") \(row.displayTitle)")
            }
            Divider()
          }
        }
        HStack {
          Button("Previous links") {
            Task { await load(mode, query: appliedQuery, page: page - 1) }
          }.disabled(page == 0)
          Spacer()
          Text(
            "Page \(page + 1) · \(result.totalCount) \(result.totalCount == 1 ? "Entry" : "Entries")"
          ).font(MTTypography.caption)
          Spacer()
          Button("Next links") { Task { await load(mode, query: appliedQuery, page: page + 1) } }
            .disabled((page + 1) * 20 >= result.totalCount)
        }
      }
      if let message { Text(message).foregroundStyle(MTColor.warm) }
      Button("Refresh links") { Task { await load(mode, query: appliedQuery, page: page) } }
    }.padding().background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .disabled(busy).task { await load(.outgoing, query: "", page: 0) }
      .confirmationDialog(
        "Unlink Entry?",
        isPresented: Binding(get: { unlinkTarget != nil }, set: { if !$0 { unlinkTarget = nil } })
      ) {
        if let target = unlinkTarget {
          Button("Unlink \(target.displayTitle)") { Task { await change(target, linked: false) } }
        }
      } message: {
        Text("Neither Entry is deleted. This change can be restored through this Entry's history.")
      }
  }
  private var modeButtons: some View {
    ForEach(EntryRelationMode.allCases, id: \.self) { value in
      Button(value.title) {
        query = ""
        Task { await load(value, query: "", page: 0) }
      }.buttonStyle(.bordered).tint(mode == value ? MTColor.accent : MTColor.inkMuted)
        .accessibilityAddTraits(mode == value ? [.isSelected] : [])
    }
  }
  private func load(
    _ requestedMode: EntryRelationMode, query search: String, page requestedPage: Int
  ) async {
    let request = EntryRelationsRequest(
      entryID: entryID, mode: requestedMode, query: search, page: requestedPage)
    guard !busy, request.isValid else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let value: EntryRelationsResult? = try await client.rpc("entry_relations", params: request)
        .execute().value
      guard let value, try await client.auth.session.user.id == ownerID else {
        throw URLError(.badServerResponse)
      }
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
    guard !busy, let result else { return }
    let input = EntryRelationChange(
      entryID: entryID, targetID: row.entryID, expectedRevision: result.revision, linked: linked)
    guard input.isValid else { return }
    busy = true
    message = nil
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let revision: Int? = try await client.rpc("set_entry_relation", params: input).execute().value
      guard revision != nil, try await client.auth.session.user.id == ownerID else {
        throw URLError(.badServerResponse)
      }
      busy = false
      query = ""
      await load(.outgoing, query: "", page: 0)
      await onChanged()
    } catch let error as PostgrestError where error.message == "relation_limit" {
      message = "This Entry already has 100 links. Remove a link before adding another."
    } catch {
      message = "This Entry changed or the link could not be confirmed. Refresh before retrying."
    }
    busy = false
  }
}
