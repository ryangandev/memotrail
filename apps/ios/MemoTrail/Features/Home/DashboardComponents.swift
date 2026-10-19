import SwiftUI

/// Web `Stats`: four archive counts that each open their area.
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
        value: snapshot.nowCount, label: "Going on now", icon: .timeline,
        open: { navigator.show(.timeline) }),
      Item(
        value: snapshot.entryCount, label: "Entries kept", icon: .archive,
        open: { navigator.show(.library) }),
      Item(
        value: snapshot.firstTimeCount, label: "First Times", icon: .star,
        open: { navigator.show(.firstTimes) }),
      Item(
        value: snapshot.tagCount, label: "Tags", icon: .tag,
        open: { navigator.show(.tags) }),
    ]
    VStack(spacing: 0) {
      row(items[0], items[1])
      Divider().overlay(MTColor.border)
      row(items[2], items[3])
    }
    .background(MTColor.surface)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Your archive at a glance")
    .accessibilityIdentifier("dashboard-counts")
  }

  private func row(_ leading: Item, _ trailing: Item) -> some View {
    HStack(spacing: 0) {
      cell(leading)
      Rectangle().fill(MTColor.border).frame(width: MTSize.Stroke.thin).frame(maxHeight: .infinity)
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
      .frame(maxWidth: .infinity, minHeight: MTLayout.Dashboard.rowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(DashboardRibbonButtonStyle())
    .accessibilityLabel("\(item.value) \(item.label)")
  }

  @ViewBuilder
  private func cellContent(_ item: Item) -> some View {
    Image(item.icon)
      .font(.mtIcon(MTSize.Icon.s15, weight: .medium))
      .foregroundStyle(MTColor.accent)
      .accessibilityHidden(true)
    Text("\(item.value)")
      .font(MTFont.quietTitle)
      .monospacedDigit()
    Text(item.label).font(MTFont.detail)
  }
}

private struct DashboardRibbonButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(configuration.isPressed ? MTColor.surfaceSubtle : .clear)
  }
}

/// A resurfaced dated Entry with its photo, identity, date, note, and organization.
struct DashboardMemoryCard: View {
  let entry: HomeEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let cover = entry.coverAttachment, cover.signedURL != nil {
        MTRemoteImage(url: cover.signedURL, accessibilityLabel: cover.originalFilename)
          .frame(height: MTLayout.Dashboard.coverHeight)
      }
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        HStack(spacing: MTSpacing.s2) {
          Text(entry.identityLabel)
          if let date = entry.shownDate { Text(date) }
        }
        .font(MTFont.noteStrong)
        .foregroundStyle(MTColor.warm)
        Text(entry.displayTitle)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .fixedSize(horizontal: false, vertical: true)
        if let body = entry.summary(limit: 260) {
          Text(body)
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body, textStyle: .footnote)
            .lineLimit(3)
        }
        if !entry.tagNames.isEmpty {
          MTFlowLayout(spacing: MTSpacing.s1) {
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
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Web `Now` item: a Chapter that has started and not ended, with its span and duration so far.
struct DashboardNowCard: View {
  let item: HomeNowItem
  /// The day the snapshot describes, which durations are measured to.
  let asOf: Date

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: MTSpacing.s3) {
        title
        Spacer(minLength: 0)
        span
      }
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        title
        span
      }
    }
    .padding(.vertical, MTSpacing.s4)
    .padding(.horizontal, MTSpacing.s5)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .accessibilityElement(children: .combine)
  }

  private var title: some View {
    Text(item.displayTitle)
      .font(MTFont.itemTitle)
      .foregroundStyle(MTColor.ink)
      .multilineTextAlignment(.leading)
  }

  private var span: some View {
    let facts = item.facts(asOf: asOf)
    return MTFlowLayout(spacing: MTSpacing.s2) {
      Text(facts[0])
      MTFlowSeparator()
      Text(facts[1])
    }
    .font(MTFont.detail)
    .foregroundStyle(MTColor.inkMuted)
  }
}

/// A Recent Entries row: date and identity, title, note, tags, and photo.
struct DashboardEntryRow: View {
  let entry: HomeEntry

  var body: some View {
    HStack(alignment: .center, spacing: MTSpacing.s3) {
      VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
        HStack(spacing: MTSpacing.s2) {
          if let date = entry.shownDate {
            Text(date)
              .font(MTFont.noteStrong)
              .foregroundStyle(MTColor.warm)
              .lineLimit(1)
          }
          MTBadge(title: entry.identityLabel, tone: .outline)
            .fixedSize()
        }
        Text(entry.displayTitle)
          .font(MTFont.itemTitle)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
        if let body = entry.summary(limit: 170) {
          Text(body.replacingOccurrences(of: "\n", with: " "))
            .font(MTFont.supporting)
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
          .frame(width: MTLayout.Dashboard.thumbWidth, height: MTLayout.Dashboard.thumbHeight)
          .clipShape(RoundedRectangle(cornerRadius: MTRadius.medium))
      }
    }
    .padding(.vertical, MTSpacing.s3)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
