import SwiftUI

// The pieces of the Item page: the writing and facts of the current Entry, and the rows of a
// Chapter's Entries and overlapping Chapters. Web `components/entry-detail-view.tsx`.

// MARK: - Presentation

/// One labeled fact under an Item's writing, like a Web `currentFacts` row.
struct ItemFact: Equatable, Identifiable {
  let label: String
  let value: String
  /// Tags and locations print each word capitalized, like Web's `text-transform: capitalize`;
  /// the Date prints as written.
  let capitalizesWords: Bool

  var id: String { label }

  var displayValue: String { capitalizesWords ? value.capitalizingFirstLetters : value }
}

extension EntryDetail {
  /// Web `CurrentItem` facts: the Date, then the tags and locations. A Chapter's Date is the
  /// span it covers and how long that is. An Entry's Date shows only when it says more than the
  /// heading already does.
  func facts(now: Date = Date()) -> [ItemFact] {
    var facts: [ItemFact] = []
    if subtype == .chapter {
      let date = chapterDateFacts(now: now)
      facts.append(
        ItemFact(
          label: "Date",
          value: [date.span, date.duration].compactMap(\.self).joined(separator: " · "),
          capitalizesWords: false))
    } else if dateAddsToTitle {
      facts.append(ItemFact(label: "Date", value: dateLabel, capitalizesWords: false))
    }
    if !tags.isEmpty {
      facts.append(
        ItemFact(
          label: "Tags", value: tags.map(\.name).joined(separator: ", "), capitalizesWords: true))
    }
    if !locations.isEmpty {
      facts.append(
        ItemFact(
          label: "Locations", value: locations.map(\.label).joined(separator: ", "),
          capitalizesWords: true))
    }
    return facts
  }
}

extension String {
  /// Web `text-transform: capitalize`: the first letter of each word in capitals and every
  /// other letter as written, so "road trip" reads "Road Trip" and "NASA" stays "NASA".
  var capitalizingFirstLetters: String {
    var result = ""
    var startsWord = true
    for character in self {
      if startsWord, character.isLetter {
        result += character.uppercased()
      } else {
        result.append(character)
      }
      startsWord = character.isWhitespace || "-/(".contains(character)
    }
    return result
  }
}

/// A row in a Chapter's list of Entries, like the Web `EntryList` row a Chapter's page draws.
struct ItemEntryRow: Identifiable, Equatable {
  let id: UUID
  let isFirstTime: Bool
  /// The date beside the title, or nil when the title already is the date.
  let date: String?
  let title: String
  let excerpt: String
  let coverURL: URL?
}

extension ChapterEntry {
  func row(coverURL: URL?) -> ItemEntryRow {
    ItemEntryRow(
      id: id, isFirstTime: isFirstTime,
      // An untitled Entry is already named by its date.
      date: title.trimmed.isEmpty ? nil : occurrence.displayLabel,
      title: displayTitle, excerpt: excerpt, coverURL: coverURL)
  }
}

// MARK: - The current Entry

/// Web `CurrentItem`: the writing, the photos, then the facts, on a raised card.
struct ItemCurrentCard<Photos: View>: View {
  let entry: EntryDetail
  var now = Date()
  private let photos: Photos
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(entry: EntryDetail, now: Date = Date(), @ViewBuilder photos: () -> Photos) {
    self.entry = entry
    self.now = now
    self.photos = photos()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.large)
    VStack(alignment: .leading, spacing: MTSpacing.s8) {
      if entry.body.isEmpty {
        Text("No writing has been added yet.")
          .font(MTFont.bodyLarge)
          .foregroundStyle(MTColor.inkMuted)
      } else {
        MTRichTextContent(text: entry.body, richText: entry.richText)
      }
      photos
      ItemFacts(facts: entry.facts(now: now))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(
      horizontalSizeClass == .regular ? MTLayout.ItemPanel.paddingRegular : MTLayout.ItemPanel.padding)
    .background(MTColor.surfaceRaised, in: shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Current item")
  }
}

/// Web `currentFacts`: labeled values under a rule, two columns when there is room.
struct ItemFacts: View {
  let facts: [ItemFact]
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    if !facts.isEmpty {
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: MTSpacing.s4, alignment: .topLeading),
          count: horizontalSizeClass == .regular ? 2 : 1),
        alignment: .leading, spacing: MTSpacing.s4
      ) {
        ForEach(facts) { fact in
          VStack(alignment: .leading, spacing: MTSpacing.s1) {
            Text(fact.label)
              .mtTextRole(.factLabel)
              .foregroundStyle(MTColor.inkFaint)
            Text(fact.displayValue)
              .font(MTFont.caption)
              .foregroundStyle(MTColor.inkMuted)
              .fixedSize(horizontal: false, vertical: true)
              .textSelection(.enabled)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.top, MTSpacing.s5)
      .overlay(alignment: .top) { MTListDivider() }
    }
  }
}

// MARK: - A Chapter's lists

/// A Chapter's Entries: First Time badge, date, serif title, one-line excerpt, and a photo
/// beside them when the Entry has one. Each row opens its Item page.
struct ItemEntryList: View {
  let rows: [ItemEntryRow]
  var identifierPrefix = "item-chapter-entry"

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows) { row in
        NavigationLink(value: ItemLink(entryID: row.id)) {
          ItemEntryRowView(row: row)
        }
        .buttonStyle(MTListRowButtonStyle())
        .accessibilityIdentifier("\(identifierPrefix)-\(row.id.uuidString.lowercased())")
        MTListDivider()
      }
    }
    .overlay(alignment: .top) { MTListDivider() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Entries in this Chapter")
  }
}

private struct ItemEntryRowView: View {
  let row: ItemEntryRow

  var body: some View {
    HStack(alignment: .center, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        if row.isFirstTime || row.date != nil {
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
            if row.isFirstTime {
              MTBadge(title: "First Time", tone: .neutral, size: .micro, uppercase: true)
            }
            Spacer(minLength: 0)
            if let date = row.date {
              Text(date)
                .font(MTFont.detail)
                .foregroundStyle(MTColor.inkFaint)
                .lineLimit(1)
            }
          }
        }
        Text(row.title)
          .font(MTFont.itemTitle)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
        if !row.excerpt.trimmed.isEmpty {
          Text(row.excerpt)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(1)
        }
      }
      if let coverURL = row.coverURL {
        MTRemoteImage(url: coverURL)
          .frame(width: MTSpacing.s16, height: MTSpacing.s16)
          .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
          .accessibilityHidden(true)
      }
    }
    .padding(.horizontal, MTSpacing.s3)
    .padding(.vertical, MTSpacing.s4)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      [row.isFirstTime ? "First Time" : nil, row.title, row.date].compactMap(\.self).joined(
        separator: ", ")
    )
    .accessibilityHint("Opens this Entry")
    .accessibilityAddTraits(.isButton)
  }
}

/// Web `overlaps`: the Chapters that run during this one, each with the span it covers.
struct ItemOverlapList: View {
  let overlaps: [ChapterOverlap]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(overlaps) { overlap in
        NavigationLink(value: ItemLink(entryID: overlap.id)) {
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
            Text(overlap.displayTitle)
              .font(MTFont.body)
              .foregroundStyle(MTColor.accent)
              .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Text(overlap.occurrence.spanLabel)
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkFaint)
              .multilineTextAlignment(.trailing)
          }
          .padding(MTSpacing.s3)
          .contentShape(Rectangle())
        }
        .buttonStyle(MTListRowButtonStyle())
        .accessibilityIdentifier("item-chapter-overlap-\(overlap.id.uuidString.lowercased())")
        .accessibilityLabel("\(overlap.displayTitle), \(overlap.occurrence.spanLabel)")
        .accessibilityHint("Opens this Chapter")
        MTListDivider()
      }
    }
    .overlay(alignment: .top) { MTListDivider() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Chapters during this time")
  }
}
