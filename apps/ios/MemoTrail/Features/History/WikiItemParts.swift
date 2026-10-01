import SwiftUI

/// Web `EntryHistoryView` item actions: edit or open the Item where it lives, its version
/// history, a linked Goal, and Move to Trash. Which appear depends on the Item's Kind.
struct WikiItemActions: View {
  enum Action { case edit, openFirstTime, openOnTimeline, history, createGoal, openGoal, trash }

  let record: EntryHistoryRecord
  /// The Item page links to version history and can move the Item to Trash.
  let isItemPage: Bool
  let isBusy: Bool
  let perform: (Action) -> Void

  var body: some View {
    let kind = record.itemKind
    let subtype = record.itemSubtype
    let isActive = !record.isDeleted
    MTFlowLayout(spacing: MTSpacing.s2) {
      if isActive, kind == .entry, ["entry", "source_capture"].contains(subtype) {
        button("Edit Entry", .edit)
          .accessibilityIdentifier("edit-item")
      }
      if isActive, kind == .entry, subtype == "first_time" {
        button("Open First Time", .openFirstTime)
      }
      if isActive, kind == .entry, ["moment", "period"].contains(subtype) {
        button("Edit \(subtype == "period" ? "Period" : "Moment")", .openOnTimeline)
      }
      if isItemPage, !record.versions.isEmpty {
        button("View version history (\(record.totalCount))", .history)
          .accessibilityIdentifier("item-version-history")
      }
      if isActive, kind != .goal {
        Button("Create linked Goal") { perform(.createGoal) }
          .mtButtonStyle()
          .disabled(isBusy)
          .accessibilityIdentifier("create-linked-goal")
      }
      if isActive, kind == .goal {
        button("Open Goal", .openGoal)
      }
      if isItemPage, isActive {
        Button {
          perform(.trash)
        } label: {
          Label("Move to Trash", icon: .trash)
        }
        .mtButtonStyle(.danger)
        .disabled(isBusy)
        .accessibilityIdentifier("trash-item")
      }
    }
  }

  private func button(_ title: String, _ action: Action) -> some View {
    Button(title) { perform(action) }
      .mtButtonStyle(.secondary)
      .disabled(isBusy)
  }
}

/// Web's provenance links: an extracted Item's source, what it produced, or an exploration's
/// saved conclusion.
struct WikiItemProvenanceLinks: View {
  let record: EntryHistoryRecord
  let open: (UUID) -> Void

  var body: some View {
    ForEach(Array(record.provenanceLinks.enumerated()), id: \.offset) { _, link in
      Button(link.title) { open(link.targetID) }
        .buttonStyle(.plain)
        .font(MTFont.body)
        .foregroundStyle(MTColor.accent)
    }
  }
}

/// Web `CurrentItem`: the Item's writing, then its Kind, date, and relationships.
struct WikiItemCurrentCard: View {
  let snapshot: [String: HistoryJSON]
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let body = snapshot["body"]?.text ?? ""
    VStack(alignment: .leading, spacing: MTSpacing.s8) {
      if body.trimmed.isEmpty {
        Text("No writing has been added yet.")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      } else {
        MTRichTextContent(
          text: body, richText: HistoryPresentation.richText(snapshot), font: MTFont.body,
          textStyle: .subheadline
        )
        .textSelection(.enabled)
      }
      LazyVGrid(
        columns: Array(
          repeating: GridItem(.flexible(), spacing: MTSpacing.s4, alignment: .topLeading),
          count: horizontalSizeClass == .regular ? 2 : 1),
        alignment: .leading, spacing: MTSpacing.s4
      ) {
        ForEach(facts, id: \.label) { fact in
          VStack(alignment: .leading, spacing: MTSpacing.s1) {
            Text(fact.label.uppercased())
              .font(.caption2)
              .tracking(0.6)
              .foregroundStyle(MTColor.inkFaint)
            Text(fact.value)
              .font(MTFont.caption.weight(.regular))
              .foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.top, MTSpacing.s5)
      .overlay(alignment: .top) { MTListDivider() }
    }
    .padding(horizontalSizeClass == .regular ? 44 : MTSpacing.s6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Current item")
  }

  private var facts: [(label: String, value: String)] {
    var facts: [(label: String, value: String)] = []
    let kind = snapshot["item_kind"]?.text.flatMap(WikiItemKind.init(rawValue:))
    let subtype = snapshot["item_subtype"]?.text ?? ""
    if let kind, kind != .entry || !["entry", "source_capture"].contains(subtype) {
      facts.append(("Record", kind.displayName(subtype: subtype)))
    }
    facts.append(("Date", HistoryPresentation.date(snapshot)))
    for key in HistoryPresentation.relationshipGroups {
      if let values = snapshot[key]?.array, !values.isEmpty {
        facts.append(
          (
            key.replacingOccurrences(of: "_", with: " ").capitalized,
            HistoryPresentation.names(values)
          ))
      }
    }
    return facts
  }
}

/// Web `Snapshot`: one version's title, writing, facts, relationships, and recorded details.
struct HistorySnapshotCard: View {
  let heading: String
  let snapshot: [String: HistoryJSON]

  var body: some View {
    let body = snapshot["body"]?.text ?? ""
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text(heading)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.warm)
        .accessibilityAddTraits(.isHeader)
      Text(HistoryPresentation.title(snapshot))
        .font(MTFont.titleSmall)
        .foregroundStyle(MTColor.ink)
      if body.isEmpty {
        Text("No writing in this version.")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      } else {
        MTRichTextContent(
          text: body, richText: HistoryPresentation.richText(snapshot), font: MTFont.body,
          textStyle: .subheadline
        )
        .textSelection(.enabled)
      }
      Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
        row("Type", identity)
        row("Inbox", snapshot["inbox_status"]?.text ?? "")
        row("Date", HistoryPresentation.date(snapshot))
        row("Time zone", snapshot["occurred_timezone"]?.text ?? "Unknown")
      }
      .font(MTFont.caption.weight(.regular))
      ForEach(HistoryPresentation.relationshipGroups + ["attachments"], id: \.self) { key in
        if let values = snapshot[key]?.array {
          VStack(alignment: .leading, spacing: MTSpacing.s1) {
            Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
              .font(MTFont.caption.weight(.semibold))
              .foregroundStyle(MTColor.ink)
            Text(HistoryPresentation.names(values).nonEmpty ?? "None")
              .font(MTFont.caption.weight(.regular))
              .foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.top, MTSpacing.s3)
          .overlay(alignment: .top) { MTListDivider() }
          .accessibilityElement(children: .combine)
        }
      }
      ForEach(["home", "vehicle", "goal", "metadata", "links"], id: \.self) { key in
        if let detail = detail(key) {
          DisclosureGroup("\(key.capitalized) details") {
            Text(detail)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(MTColor.inkMuted)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, MTSpacing.s2)
          }
          .font(MTFont.caption)
          .tint(MTColor.inkMuted)
          .padding(.vertical, MTSpacing.s1)
        }
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(heading)
  }

  private var identity: String {
    snapshot["item_kind"]?.text.flatMap(WikiItemKind.init(rawValue:))?
      .displayName(subtype: snapshot["item_subtype"]?.text ?? "") ?? ""
  }

  private func row(_ label: String, _ value: String) -> some View {
    GridRow(alignment: .firstTextBaseline) {
      Text(label)
        .foregroundStyle(MTColor.inkMuted)
        .frame(width: 80, alignment: .leading)
      Text(value)
        .foregroundStyle(MTColor.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  /// Web `snapshotDetail`, without internal keys or the formatting document.
  private func detail(_ key: String) -> String? {
    guard var value = snapshot[key], !value.isNull else { return nil }
    if key == "metadata", case .object(var values) = value {
      values[EntryRichText.metadataKey] = nil
      value = .object(values)
    }
    guard value != .object([:]), value != .array([]) else { return nil }
    return value.removingKeys(["owner_id", "entry_id", "created_at", "updated_at"]).display
  }
}

/// Web History `notice`: a quiet accent panel for what a restore will do.
struct HistoryNotice: View {
  /// Web `.notice` for information and `.cautionNotice` for what cannot happen.
  enum Tone { case info, caution }

  let text: String
  var tone: Tone = .info

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.medium)
    Text(text)
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MTSpacing.s5)
      .background(tone == .caution ? MTColor.warmSubtle : MTColor.accentSubtle, in: shape)
      .overlay {
        // Drawn inside the padding so both tones keep the same text alignment.
        if tone == .caution { shape.strokeBorder(MTColor.warning.opacity(0.35), lineWidth: 1) }
      }
  }
}
