import Foundation
import SwiftUI

struct EntryAISuggestions: Codable, Sendable {
  let title: String?
  let classification: EntryAISuggestionClassification?
  let collections: [String]
  let tags: [String]
  let dateText: String?
  let rationale: String
  let confidence: Double
}

struct EntryAISuggestionClassification: Codable, Sendable {
  let itemKind: WikiItemKind
  let itemSubtype: String
}

struct EntryAISuggestionRecord: Decodable, Sendable {
  let id: UUID
  let revision: Int
  let status: String
  let suggestions: EntryAISuggestions?
  enum CodingKeys: String, CodingKey {
    case id, status, suggestions
    case revision = "entry_revision"
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    revision = try values.decode(Int.self, forKey: .revision)
    status = try values.decode(String.self, forKey: .status)
    suggestions =
      status == "proposed" ? try values.decode(EntryAISuggestions.self, forKey: .suggestions) : nil
  }
}

struct EntryAISuggestionResponse: Decodable, Sendable {
  let suggestion: EntryAISuggestionRecord?
  let disabled: Bool?
  let photoCount: Int?
}

struct EntryAISuggestionInput: Encodable, Sendable {
  let entryID: UUID
  let revision: Int
  let retry: Bool
}

struct EntryAISuggestionsView: View {
  let request: @MainActor (Bool) async throws -> EntryAISuggestionResponse
  let dismiss: @MainActor (UUID) async throws -> Void
  let applyTitle: (String) -> Void
  let applyClassification: (EntryAISuggestionClassification) -> Void
  let applyDate: (String) -> Void
  let addCollection: (String) -> Void
  let addTag: (String) -> Void
  @State private var result: EntryAISuggestionResponse?
  @State private var busy = false
  @State private var message: String?
  @State private var dismissed = false

  var body: some View {
    Section("AI suggestions") {
      Text(
        "Optional, based on saved text (up to 16,000 characters). With Photo analysis enabled, up to 12 compact photo previews are included, without metadata. Choose what to copy, edit freely, then Save."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      if let count = result?.photoCount, count > 0 {
        Text("Photo previews included: \(count). Originals are not sent.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      }
      if busy {
        ProgressView("Checking suggestions…")
      } else if result?.disabled == true {
        Text(
          "AI is off or unavailable. Enable it in Library > AI settings. Manual organization stays available."
        )
      } else if dismissed || result?.suggestion?.status == "dismissed" {
        Text("Suggestions dismissed for this version.")
      } else if let suggestion = result?.suggestion?.suggestions {
        Text(suggestion.rationale).font(MTTypography.caption)
        if let title = suggestion.title {
          Button("Use title: \(title)") { applyTitle(title) }
        }
        if let classification = suggestion.classification {
          let label = classification.itemSubtype
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
          Button("Use type: \(label)") {
            applyClassification(classification)
          }
        }
        ForEach(suggestion.collections, id: \.self) { name in
          Button("Add Collection: \(name)") { addCollection(name) }
        }
        ForEach(suggestion.tags, id: \.self) { name in
          Button("Add tag: \(name)") { addTag(name) }
        }
        if let date = suggestion.dateText {
          Text(
            "Date idea: \(date). Copies the description only. Review the precision and calendar fields before saving."
          )
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
          Button("Use as approximate date") { applyDate(date) }
        }
        Button("Dismiss suggestions") {
          Task {
            guard let id = result?.suggestion?.id else { return }
            busy = true
            defer { busy = false }
            do {
              try await dismiss(id)
              dismissed = true
            } catch { message = "Could not dismiss suggestions. Try again." }
          }
        }
      } else {
        Text(
          result?.suggestion?.status == "generating"
            ? "Suggestions are being prepared. Check again shortly."
            : "No suggestions are ready yet.")
        Button(result?.suggestion?.status == "failed" ? "Retry suggestions" : "Check suggestions") {
          Task { await load(retry: true) }
        }
      }
      if let message { Text(message).foregroundStyle(MTColor.warm) }
    }
    .disabled(busy)
    .task { await load(retry: false) }
  }

  private func load(retry: Bool) async {
    guard !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      result = try await request(retry)
      for _ in 0..<15 {
        guard result?.suggestion?.status == "generating" else { break }
        try await Task.sleep(for: .seconds(2))
        result = try await request(false)
      }
    } catch is CancellationError {
      return
    } catch { message = error.localizedDescription }
  }
}
