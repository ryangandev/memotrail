import SwiftUI

/// A Dashboard link to a record's canonical destination, like Web `wikiEntryHref`.
struct DashboardRecord: Hashable {
  let id: UUID
  let kind: WikiItemKind
  let subtype: String

  init(_ entry: HomeEntry) {
    id = entry.id
    kind = entry.itemKind
    subtype = entry.itemSubtype
  }
}

/// The Web Data Ribbon: five archive counts that each open their area.
struct DashboardRibbon: View {
  let snapshot: HomeSnapshot
  let navigator: AppNavigator

  private struct Item {
    let value: Int
    let label: String
    let icon: MTIcon
    let open: () -> Void
  }

  var body: some View {
    let items = [
      Item(
        value: snapshot.currentStageCount, label: "Life in progress", icon: .timeline,
        open: { navigator.show(.timeline) }),
      Item(
        value: snapshot.entryCount, label: "Entries kept", icon: .archive,
        open: { navigator.show(.library) }),
      Item(
        value: snapshot.firstTimeCount, label: "First Times", icon: .star,
        open: { navigator.show(.firstTimes) }),
      Item(
        value: snapshot.collectionCount, label: "Collections", icon: .bulletList,
        open: { navigator.show(.collections) }),
      Item(
        value: snapshot.inboxCount, label: "To organize", icon: .inbox,
        open: { navigator.show(.inbox) }),
    ]
    VStack(spacing: 0) {
      row(items[0], items[1])
      Divider().overlay(MTColor.border)
      row(items[2], items[3])
      Divider().overlay(MTColor.border)
      cell(items[4])
    }
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Your archive at a glance")
    .accessibilityIdentifier("home-data-ribbon")
  }

  private func row(_ leading: Item, _ trailing: Item) -> some View {
    HStack(spacing: 0) {
      cell(leading)
      Rectangle().fill(MTColor.border).frame(width: 1).frame(maxHeight: .infinity)
      cell(trailing)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func cell(_ item: Item) -> some View {
    Button(action: item.open) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: MTSpacing.s2) { cellContent(item) }
        VStack(spacing: MTSpacing.s1) { cellContent(item) }
      }
      .foregroundStyle(MTColor.ink)
      .multilineTextAlignment(.center)
      .padding(.horizontal, MTSpacing.s3)
      .padding(.vertical, MTSpacing.s3)
      .frame(maxWidth: .infinity, minHeight: 56)
      .contentShape(Rectangle())
    }
    .buttonStyle(DashboardRibbonButtonStyle())
    .accessibilityLabel("\(item.value) \(item.label)")
  }

  @ViewBuilder
  private func cellContent(_ item: Item) -> some View {
    Image(item.icon)
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(MTColor.accent)
      .accessibilityHidden(true)
    Text("\(item.value)")
      .font(.system(.title3, design: .serif))
      .monospacedDigit()
    Text(item.label).font(MTFont.caption.weight(.regular))
  }
}

private struct DashboardRibbonButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? MTColor.surfaceSubtle : .clear)
  }
}

/// A Ready to organize row: capture day, title, optional note line, and a chevron.
struct DashboardInboxRow: View {
  let entry: HomeInboxPreview
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
        Text(entry.createdAt.formatted(.dateTime.month(.abbreviated).day()))
          .font(.caption2)
          .foregroundStyle(MTColor.inkFaint)
          .frame(width: 46, alignment: .leading)
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          Text(entry.displayTitle)
            .font(MTFont.label)
            .foregroundStyle(MTColor.ink)
            .lineLimit(entry.excerpt == nil ? 2 : 1)
          if let excerpt = entry.excerpt {
            Text(excerpt)
              .font(MTFont.caption.weight(.regular))
              .foregroundStyle(MTColor.inkMuted)
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(.chevron)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(MTColor.inkFaint)
      }
      .padding(.vertical, MTSpacing.s4)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Organize \(entry.displayTitle)")
  }
}

/// A resurfaced dated Entry with its photo, identity, date, note, and organization.
struct DashboardMemoryCard: View {
  let entry: HomeEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let cover = entry.coverAttachment, cover.signedURL != nil {
        MTRemoteImage(url: cover.signedURL, accessibilityLabel: cover.originalFilename)
          .frame(height: 230)
      }
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        HStack(spacing: MTSpacing.s2) {
          Text(entry.displayType)
          Text(entry.occurrence.displayLabel)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(MTColor.warm)
        Text(entry.cardTitle)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let body = entry.body.trimmed.nonEmpty {
          Text(body.truncated(to: 260))
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body, textStyle: .footnote)
            .lineLimit(3)
        }
        if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
          MTFlowLayout(spacing: MTSpacing.s1) {
            ForEach(entry.collectionNames.prefix(2), id: \.self) { MTBadge(title: $0) }
            ForEach(entry.tagNames.prefix(3), id: \.self) {
              MTBadge(title: "#\($0)", size: .medium)
            }
          }
          .padding(.top, MTSpacing.s1)
        }
      }
      .padding(MTSpacing.s6)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border, lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
  }
}

/// A current Timeline chapter: track, title, and the span so far.
struct DashboardChapterCard: View {
  let stage: HomeStage
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .center, spacing: MTSpacing.s3) {
          heading
          Spacer(minLength: 0)
          span
        }
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          heading
          span
        }
      }
      .padding(.vertical, MTSpacing.s4)
      .padding(.horizontal, MTSpacing.s5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.border, lineWidth: 1)
      }
    }
    .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
    .accessibilityElement(children: .combine)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s1) {
      Text(stage.trackName.uppercased())
        .font(.system(size: 10, weight: .semibold))
        .tracking(1)
        .foregroundStyle(MTColor.warm)
      Text(stage.title)
        .font(.system(.body, design: .serif).weight(.medium))
        .foregroundStyle(MTColor.ink)
        .multilineTextAlignment(.leading)
    }
  }

  private var span: some View {
    Text(stage.occurrence.spanLabel)
      .font(MTFont.caption.weight(.regular))
      .foregroundStyle(MTColor.inkMuted)
  }
}

/// A Recent Entries row: date and identity, Collection prefix and title, note, tags, and photo.
struct DashboardEntryRow: View {
  let entry: HomeEntry

  var body: some View {
    HStack(alignment: .center, spacing: MTSpacing.s3) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: MTSpacing.s2) {
          Text(entry.occurrence.displayLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(MTColor.warm)
            .lineLimit(1)
          MTBadge(title: entry.displayType, tone: .outline)
            .fixedSize()
        }
        title
          .font(.system(.body, design: .serif).weight(.medium))
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
        if let body = entry.body.trimmed.nonEmpty {
          Text(body.replacingOccurrences(of: "\n", with: " "))
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(1)
        }
        if !entry.tagNames.isEmpty {
          HStack(spacing: MTSpacing.s1) {
            ForEach(entry.tagNames.prefix(3), id: \.self) {
              MTBadge(title: "#\($0)", size: .medium)
            }
          }
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .clipped()
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let cover = entry.coverAttachment, cover.signedURL != nil {
        MTRemoteImage(url: cover.signedURL, accessibilityLabel: cover.originalFilename)
          .frame(width: 64, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
      }
    }
    .padding(.vertical, MTSpacing.s3)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var title: Text {
    guard !entry.collectionNames.isEmpty else { return Text(entry.cardTitle) }
    let prefix = entry.collectionNames.map { "[\($0)]" }.joined(separator: " ")
    return Text("\(Text(prefix).foregroundStyle(MTColor.inkMuted)) \(entry.cardTitle)")
  }
}
