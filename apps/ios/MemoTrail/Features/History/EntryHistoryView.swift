import Foundation
@preconcurrency import Supabase
import SwiftUI

indirect enum HistoryJSON: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: HistoryJSON])
  case array([HistoryJSON])
  case null
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if value.decodeNil() {
      self = .null
    } else if let v = try? value.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? value.decode(Double.self) {
      self = .number(v)
    } else if let v = try? value.decode(String.self) {
      self = .string(v)
    } else if let v = try? value.decode([String: HistoryJSON].self) {
      self = .object(v)
    } else {
      self = .array(try value.decode([HistoryJSON].self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .null: try value.encodeNil()
    case .string(let v): try value.encode(v)
    case .number(let v): try value.encode(v)
    case .bool(let v): try value.encode(v)
    case .object(let v): try value.encode(v)
    case .array(let v): try value.encode(v)
    }
  }
  var text: String? {
    if case .string(let v) = self { return v }
    return nil
  }
  var number: Int? {
    if case .number(let v) = self, v.isFinite, v >= 0, v < Double(Int.max) { return Int(v) }
    return nil
  }
  var object: [String: HistoryJSON]? {
    if case .object(let v) = self { return v }
    return nil
  }
  var array: [HistoryJSON]? {
    if case .array(let v) = self { return v }
    return nil
  }
  var isNull: Bool { self == .null }
  var display: String {
    if let text { return text }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return (try? String(data: encoder.encode(self), encoding: .utf8)) ?? ""
  }
}

struct HistoryIndexEntry: Decodable, Identifiable, Sendable {
  let entryID: UUID
  let title: String?
  let excerpt: String
  let entryType: String
  let revision: Int
  let isDeleted: Bool
  let versionCount: Int
  let lastChanged: String
  let totalCount: Int
  var id: UUID { entryID }
  var displayTitle: String {
    title?.trimmed.nonEmpty ?? String(excerpt.prefix(80)).nonEmpty ?? "Untitled Entry"
  }
  enum CodingKeys: String, CodingKey {
    case title, excerpt, revision
    case entryID = "entry_id"
    case entryType = "entry_type"
    case isDeleted = "is_deleted"
    case versionCount = "version_count"
    case lastChanged = "last_changed"
    case totalCount = "total_count"
  }
}

struct EntryHistoryVersion: Decodable, Identifiable, Sendable {
  let version: Int
  let operation: String
  let createdAt: String
  let snapshot: [String: HistoryJSON]
  var id: Int { version }
  enum CodingKeys: String, CodingKey {
    case version, operation, snapshot
    case createdAt = "created_at"
  }
}

struct EntryHistoryRecord: Decodable, Sendable {
  let current: [String: HistoryJSON]
  let versions: [EntryHistoryVersion]
  let totalCount: Int
  enum CodingKeys: String, CodingKey {
    case current, versions
    case totalCount = "total_count"
  }
  var revision: Int { current["revision"]?.number ?? 0 }
  var isDeleted: Bool { current["deleted_at"]?.isNull == false }
}

enum HistoryPresentation {
  static func date(_ snapshot: [String: HistoryJSON]) -> String {
    if let label = snapshot["occurred_label"]?.text?.trimmed.nonEmpty { return label }
    guard let raw = snapshot["occurred_start"]?.text else { return "Unknown" }
    let parser = ISO8601DateFormatter()
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone =
      TimeZone(identifier: snapshot["occurred_timezone"]?.text ?? "UTC")
      ?? TimeZone(secondsFromGMT: 0)
    switch snapshot["date_precision"]?.text {
    case "year": formatter.dateFormat = "yyyy"
    case "month": formatter.dateFormat = "MMM yyyy"
    case "exact": formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
    default: formatter.dateFormat = "MMM d, yyyy"
    }
    func format(_ raw: String) -> String {
      parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      var date = parser.date(from: raw)
      if date == nil {
        parser.formatOptions = [.withInternetDateTime]
        date = parser.date(from: raw)
      }
      return date.map { formatter.string(from: $0) } ?? "Unknown"
    }
    return format(raw) + (snapshot["occurred_end"]?.text.map { " to \(format($0))" } ?? "")
  }
  static let fields = [
    "title", "body", "entry_type", "inbox_status", "occurred_start", "occurred_end",
    "date_precision", "occurred_label", "occurred_timezone", "collections", "tags", "people",
    "places", "timeline_items", "home", "vehicle", "goal", "links", "attachments", "metadata",
    "source_language",
  ]
  static func title(_ snapshot: [String: HistoryJSON]) -> String {
    snapshot["title"]?.text?.trimmed.nonEmpty ?? String((snapshot["body"]?.text ?? "").prefix(80))
      .nonEmpty ?? "Untitled Entry"
  }
  static func differences(current: [String: HistoryJSON], previous: [String: HistoryJSON])
    -> [String]
  {
    fields.filter { previous[$0] != nil && current[$0] != previous[$0] }.map {
      $0.replacingOccurrences(of: "_", with: " ")
    }
  }
}

struct HistoryIndexRequest: Encodable {
  let query: String
  let limit: Int
  let offset: Int
  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}
struct HistoryReadRequest: Encodable {
  let entryID: UUID
  let limit: Int
  let offset: Int
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case limit = "p_limit"
    case offset = "p_offset"
  }
}
struct HistoryRestoreRequest: Encodable {
  let entryID: UUID
  let version: Int
  let expectedRevision: Int
  enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case version = "p_version"
    case expectedRevision = "p_expected_revision"
  }
}

struct EntryHistoryIndexView: View {
  let client: SupabaseClient
  let ownerID: UUID
  @State private var rows: [HistoryIndexEntry] = []
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var busy = false
  @State private var message: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Revisit earlier words and metadata. Restoring saves your current version first.")
          .foregroundStyle(MTColor.inkMuted)
        HStack {
          TextField("Find an Entry", text: $query).textFieldStyle(.roundedBorder).onSubmit {
            Task { await load() }
          }
          Button("Search") { Task { await load() } }.disabled(busy || query.count > 200)
        }
        if let message {
          Text(message).foregroundStyle(MTColor.warm)
          Button("Retry") { Task { await load() } }
        }
        if rows.isEmpty && !busy {
          Text("No matching history yet. Earlier versions appear after an Entry is edited.")
            .foregroundStyle(MTColor.inkMuted)
        }
        ForEach(rows) { row in
          NavigationLink {
            EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: row.entryID)
          } label: {
            VStack(alignment: .leading, spacing: 8) {
              Text(row.displayTitle).font(MTTypography.titleSmall).foregroundStyle(MTColor.ink)
              Text(
                "\(row.entryType) · \(row.versionCount) earlier versions\(row.isDeleted ? " · In Trash" : "")"
              ).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
              Text(row.excerpt).lineLimit(3).font(MTTypography.caption).foregroundStyle(
                MTColor.inkMuted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
              MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
          }.buttonStyle(.plain)
        }
        if rows.count < (rows.first?.totalCount ?? 0) {
          Button("Older Entries") { Task { await load(more: true) } }.disabled(busy)
        }
        if busy { ProgressView() }
      }.padding()
    }.background(MTColor.canvas).navigationTitle("Entry history").task { await load() }.refreshable
    { await load() }
  }
  private func load(more: Bool = false) async {
    guard !busy, query.count <= 200 else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let search = more ? appliedQuery : query.trimmed
      let next: [HistoryIndexEntry] = try await client.rpc(
        "entry_history_index",
        params: HistoryIndexRequest(query: search, limit: 50, offset: more ? rows.count : 0)
      ).execute().value
      if more {
        rows.append(contentsOf: next)
      } else {
        rows = next
        appliedQuery = search
      }
    } catch { message = "Could not load history. Try again." }
  }
}

struct EntryHistoryDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  @State private var record: EntryHistoryRecord?
  @State private var selected = 0
  @State private var page = 0
  @State private var busy = false
  @State private var message: String?
  @State private var confirmRestore = false
  var selectedVersion: EntryHistoryVersion? { record?.versions.first { $0.version == selected } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if let record {
          Text(HistoryPresentation.title(record.current)).font(MTTypography.title)
          if !record.isDeleted {
            NavigationLink("Explore with AI") {
              ExplorationView(client: client, ownerID: ownerID, entryID: entryID)
            }
          }
          ForEach(Array((record.current["links"]?.array ?? []).enumerated()), id: \.offset) {
            _, value in
            if let link = value.object, let rawID = link["target_entry_id"]?.text,
              let linkedID = UUID(uuidString: rawID), let relationship = link["relationship"]?.text,
              ["exploration_source", "exploration_conclusion"].contains(relationship)
            {
              NavigationLink(
                relationship == "exploration_source" ? "Open source Entry" : "Open saved conclusion"
              ) { EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: linkedID) }
            }
          }
          if !record.versions.isEmpty {
            Picker("Earlier version", selection: $selected) {
              ForEach(record.versions) { version in
                Text("Version \(version.version)").tag(version.version)
              }
            }
          }
          if let version = selectedVersion {
            Text("Saved before \(version.createdAt)").font(MTTypography.caption).foregroundStyle(
              MTColor.inkMuted)
            Text(
              "Differences from current version: \(HistoryPresentation.differences(current: record.current, previous: version.snapshot).joined(separator: ", ")). Current version \(record.revision) stays in history."
            )
            if version.snapshot["history_schema"]?.number != 2 {
              Text(
                "This early snapshot has incomplete relationship history. Unrecorded relationships stay as they are now."
              ).foregroundStyle(MTColor.warm)
            }
            Text(
              "Shared People, Place, Collection, and track definitions stay current. Missing linked items or photo originals stop restoration safely. Photo files are not deleted."
            ).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            if record.isDeleted {
              Text("Restore this Entry from Trash first.").foregroundStyle(MTColor.warm)
            }
            Button("Restore selected version") { confirmRestore = true }.buttonStyle(
              .borderedProminent
            ).tint(MTColor.accent).disabled(busy || record.isDeleted)
            HistorySnapshotView(title: "Version \(version.version)", snapshot: version.snapshot)
            HistorySnapshotView(
              title: "Current · version \(record.revision)", snapshot: record.current)
          } else {
            Text("No earlier versions on this page.")
            HistorySnapshotView(
              title: "Current · version \(record.revision)", snapshot: record.current)
          }
          HStack {
            if page > 0 { Button("Newer versions") { Task { await load(nextPage: page - 1) } } }
            Spacer()
            if record.totalCount > (page + 1) * 20 {
              Button("Older versions") { Task { await load(nextPage: page + 1) } }
            }
          }.disabled(busy)
        }
        if let message { Text(message).foregroundStyle(MTColor.warm) }
        if busy { ProgressView() }
        Button("Refresh") { Task { await load(nextPage: 0) } }.disabled(busy)
      }.padding()
    }.background(MTColor.canvas).navigationTitle("Version history").task { await load(nextPage: 0) }
      .confirmationDialog(
        "Restore version \(selected)?", isPresented: $confirmRestore, titleVisibility: .visible
      ) {
        Button("Restore version") { Task { await restore() } }
      } message: {
        Text(
          "Your current version is preserved. Recorded links and photo membership will also be restored; shared names and definitions, including Collections and tags, stay current."
        )
      }
  }
  private func load(nextPage: Int) async {
    guard !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let next: EntryHistoryRecord? = try await client.rpc(
        "entry_history",
        params: HistoryReadRequest(entryID: entryID, limit: 20, offset: nextPage * 20)
      ).execute().value
      record = next
      page = nextPage
      selected = next?.versions.first?.version ?? 0
      if next == nil { message = "This Entry is no longer available." }
    } catch { message = "Could not load this Entry's history. Try again." }
  }
  private func restore() async {
    guard !busy, let record, selected > 0 else { return }
    busy = true
    message = nil
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let revision: Int? = try await client.rpc(
        "restore_entry_version",
        params: HistoryRestoreRequest(
          entryID: entryID, version: selected, expectedRevision: record.revision)
      ).execute().value
      if revision == nil {
        message = "This Entry changed or is in Trash. Refresh or restore it from Trash first."
        busy = false
        return
      }
      busy = false
      await load(nextPage: 0)
      message = "Version restored. Your previous current version remains in history."
    } catch {
      busy = false
      let code = (error as? PostgrestError)?.message
      if code == "history_reference_unavailable" {
        message =
          "A linked item is missing or in Trash. Restore it first; this Entry was not changed."
      } else if code == "history_attachment_unavailable" {
        message = "An original photo is no longer available. Nothing was restored."
      } else if code == "history_details_unavailable" {
        message =
          "This early version did not record the specialized details required for a safe restore."
      } else {
        message =
          "Could not confirm restoration. Refresh to check the latest version before trying again."
      }
    }
  }
}

private struct HistorySnapshotView: View {
  let title: String
  let snapshot: [String: HistoryJSON]
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(title).font(MTTypography.caption).foregroundStyle(MTColor.warm)
      Text(HistoryPresentation.title(snapshot)).font(MTTypography.titleSmall)
      Text(snapshot["body"]?.text ?? "").textSelection(.enabled)
      LabeledContent("Date", value: HistoryPresentation.date(snapshot)).font(MTTypography.caption)
      ForEach(
        [
          "entry_type", "inbox_status", "occurred_timezone",
        ], id: \.self
      ) { key in
        if let value = snapshot[key]?.text {
          LabeledContent(key.replacingOccurrences(of: "_", with: " "), value: value).font(
            MTTypography.caption)
        }
      }
      ForEach(
        ["collections", "tags", "people", "places", "timeline_items", "attachments"], id: \.self
      ) { key in
        if let values = snapshot[key]?.array {
          VStack(alignment: .leading) {
            Text(key.replacingOccurrences(of: "_", with: " ")).fontWeight(.medium)
            Text(
              values.isEmpty
                ? "None"
                : values.map { item in
                  let v = item.object ?? [:]
                  return v["name"]?.text ?? v["track_name"]?.text ?? v["original_filename"]?.text
                    ?? v["id"]?.text ?? "Recorded link"
                }.joined(separator: ", "))
          }.font(MTTypography.caption)
        }
      }
      ForEach(["home", "vehicle", "goal", "metadata", "links"], id: \.self) { key in
        if let value = snapshot[key], !value.isNull, value != .object([:]), value != .array([]) {
          DisclosureGroup("\(key.capitalized) details") {
            Text(value.display).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
          }
        }
      }
    }.frame(maxWidth: .infinity, alignment: .leading).padding().background(
      MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
  }
}
