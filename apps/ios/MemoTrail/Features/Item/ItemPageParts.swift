import Foundation
import Observation
@preconcurrency import Supabase
import SwiftUI

/// Web `/items/<entry>`: loads one Entry through `entry_detail`, and for a dated Chapter its
/// first page of Entries and the Chapters overlapping it. Only the newest load applies.
@MainActor
@Observable
final class ItemPageController {
  private(set) var entry: EntryDetail?
  private(set) var chapterEntries: [ChapterEntry] = []
  private(set) var chapterEntryCount = 0
  private(set) var chapterOverlaps: [ChapterOverlap] = []
  private(set) var chapterErrorMessage: String?
  private(set) var hasLoaded = false
  private(set) var loadFailed = false

  let entryID: UUID
  private let api: EntryAPI
  private var loadGeneration = UUID()

  init(client: SupabaseClient, ownerID: UUID, entryID: UUID) {
    self.entryID = entryID
    api = EntryAPI(client: client, ownerID: ownerID)
  }

  func load() async {
    let generation = UUID()
    loadGeneration = generation
    let detail: EntryDetail?
    do {
      detail = try await api.detail(entryID)
    } catch {
      guard loadGeneration == generation, !(error is CancellationError) else { return }
      loadFailed = true
      hasLoaded = true
      return
    }

    // Like Web, a Chapter lists the Entries dated inside it; one with no calendar date has no
    // days to hold any.
    var entries: [ChapterEntry] = []
    var overlaps: [ChapterOverlap] = []
    var chapterError: String?
    if let detail, !detail.isInTrash, detail.subtype == .chapter, detail.occurredStart != nil {
      do {
        entries = try await api.chapterEntries(id: entryID, offset: 0)
        overlaps = try await api.chapterOverlaps(id: entryID)
      } catch {
        guard !(error is CancellationError) else { return }
        chapterError = "The Entries in this Chapter could not load. Refresh to try again."
      }
    }

    guard loadGeneration == generation else { return }
    entry = detail
    chapterEntries = entries
    chapterEntryCount = entries.first?.totalCount ?? 0
    chapterOverlaps = overlaps
    chapterErrorMessage = chapterError
    loadFailed = false
    hasLoaded = true
  }

  /// Web `loadEditableEntry`: the Entry as the editor opens it, or nil when it cannot.
  func editableEntry() async -> EditableEntry? {
    try? await api.editable(entryID)
  }

  /// Web `trashWikiItem`: nil when the Entry moved to Trash, otherwise why it did not.
  func moveToTrash() async -> String? {
    guard let entry else { return EntryTrashError.invalid.errorDescription }
    do {
      try await api.moveToTrash(id: entry.id, revision: entry.revision)
      return nil
    } catch let error as EntryTrashError {
      return error.errorDescription
    } catch {
      return "Could not confirm the move to Trash. Refresh before trying again."
    }
  }
}

/// Web `CurrentItem`: the writing, then the Date, tags, and locations facts.
struct ItemCurrentCard: View {
  let entry: EntryDetail
  var now = Date()

  private var facts: [(label: String, value: String?)] {
    var facts: [(label: String, value: String?)] = []
    if entry.subtype == .chapter {
      let date = entry.chapterDateFacts(now: now)
      facts.append(("Date", [date.span, date.duration].compactMap(\.self).joined(separator: " · ")))
    } else if entry.dateAddsToTitle {
      facts.append(("Date", entry.dateLabel))
    }
    if !entry.tags.isEmpty {
      facts.append(("tags", entry.tags.map(\.name).joined(separator: ", ")))
    }
    if !entry.locations.isEmpty {
      facts.append(("locations", entry.locations.map(\.label).joined(separator: ", ")))
    }
    return facts
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      if entry.body.isEmpty {
        Text("No writing has been added yet.")
          .font(MTFont.bodyLarge)
          .foregroundStyle(MTColor.inkMuted)
      } else {
        MTRichTextContent(text: entry.body, richText: entry.richText)
      }
      if !facts.isEmpty {
        MTFactList(facts: facts)
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Current item")
  }
}

/// A plain list of rows that each open an Item page.
struct ItemLinkList: View {
  struct Row: Identifiable {
    let id: UUID
    let title: String
    let detail: String
  }

  let title: String
  let rows: [Row]
  var identifierPrefix = "item-link"

  var body: some View {
    MTDetailSection(title) {
      VStack(spacing: 0) {
        ForEach(rows) { row in
          NavigationLink(value: ItemLink(entryID: row.id)) {
            HStack(spacing: MTSpacing.s3) {
              VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
                Text(row.title)
                  .font(MTFont.listHeading)
                  .foregroundStyle(MTColor.ink)
                Text(row.detail)
                  .font(MTFont.detail)
                  .foregroundStyle(MTColor.inkMuted)
              }
              Spacer(minLength: 0)
              Image(.chevron)
                .font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
                .foregroundStyle(MTColor.inkFaint)
            }
            .padding(.vertical, MTSpacing.s2_5)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("\(identifierPrefix)-\(row.id.uuidString.lowercased())")
          if row.id != rows.last?.id {
            MTListDivider()
          }
        }
      }
    }
  }
}
