import SwiftUI

/// A Web record workspace section, such as Current or Vehicle archive: an uppercase heading,
/// its description beside it on wider screens, then a grid of record cards.
struct MTRecordSection<Content: View>: View {
  let title: String
  let detail: String
  private let content: Content
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(_ title: String, detail: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.detail = detail
    self.content = content()
  }

  var body: some View {
    let isRegular = horizontalSizeClass == .regular
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
        Text(title.uppercased())
          .mtTextRole(.archiveHeading)
          .foregroundStyle(MTColor.inkMuted)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        if isRegular {
          Text(detail).font(MTFont.detail).foregroundStyle(MTColor.inkFaint)
        }
      }
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: MTLayout.Grid.record), spacing: MTSpacing.s5)],
        spacing: isRegular ? MTSpacing.s5 : MTSpacing.s3
      ) {
        content
      }
    }
    .padding(.top, isRegular ? MTSpacing.s8 : MTSpacing.s6)
  }
}

/// Web Home and Vehicle `RecordCard`: a cover photo, else a map of the record's Location, else
/// its mark, under a Current or Earlier badge; then the dates, name, facts, a short memory, and
/// up to two Collections and tags.
struct MTEntityCard: View {
  struct Fact: Hashable {
    let icon: MTIcon
    let text: String
  }

  let title: String
  let range: String
  let duration: String
  let isCurrent: Bool
  var coverURL: URL?
  var photoCount = 0
  var latitude: Double?
  var longitude: Double?
  let markIcon: MTIcon
  let markTitle: String
  let facts: [Fact]
  var memory: String?
  var collectionNames: [String] = []
  var tagNames: [String] = []
  let action: () -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    MTRecordCard(accessibilityLabel: "\(title), \(range)", action: action) {
      MTRecordCardVisual { visual }
        .overlay(alignment: .topLeading) {
          MTBadge(
            title: isCurrent ? "Current" : "Earlier",
            tone: isCurrent ? .glassAccent : .glassNeutral, size: .micro, uppercase: true
          )
          .padding(horizontalSizeClass == .regular ? MTSpacing.s3 : MTSpacing.s2)
        }
        .overlay(alignment: .bottomTrailing) {
          if photoCount > 1 {
            MTBadge(title: "\(photoCount) photos", tone: .inverse, size: .micro, uppercase: true)
              .padding(MTSpacing.s3)
          }
        }
      MTRecordCardBody {
        dates
        Text(title)
          .mtTextRole(horizontalSizeClass == .regular ? .recordCardTitle : .recordCardTitleCompact)
          .foregroundStyle(MTColor.ink)
          .multilineTextAlignment(.leading)
        ForEach(facts, id: \.self) { fact in
          Label(fact.text, icon: fact.icon)
            .labelStyle(MTInlineIconLabelStyle())
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
            .multilineTextAlignment(.leading)
        }
        if let memory = memory?.trimmed.nonEmpty {
          Text(memory)
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s1)
        }
        MTRecordCardFooter(collectionNames: collectionNames, tagNames: tagNames)
      }
    }
  }

  @ViewBuilder private var visual: some View {
    if let coverURL {
      MTRemoteImage(url: coverURL)
    } else {
      MTLocationSnapshot(latitude: latitude, longitude: longitude) {
        MTRecordMark(icon: markIcon, title: markTitle)
      }
    }
  }

  /// The range in accent and how long it lasted, stacked on phones like Web below 780 px.
  private var dates: some View {
    let range = Text(range.uppercased()).foregroundStyle(MTColor.accent)
    let duration = Text(duration.uppercased()).foregroundStyle(MTColor.inkFaint)
    return Group {
      if horizontalSizeClass == .regular {
        HStack(spacing: MTSpacing.s3) {
          range
          Spacer(minLength: 0)
          duration
        }
      } else {
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          range
          duration
        }
      }
    }
    .mtTextRole(.dateStamp)
  }
}

/// Web `RecordCard` footer: any status badges, then up to two Collections and two tags, and
/// the chevron. Phones show the first two badges, like Web below 480 px.
struct MTRecordCardFooter: View {
  var status: [(title: String, tone: MTBadgeTone)] = []
  let collectionNames: [String]
  let tagNames: [String]
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let badges =
      status + collectionNames.prefix(2).map { ($0, MTBadgeTone.neutral) }
      + tagNames.prefix(2).map { ("#\($0)", MTBadgeTone.neutral) }
    HStack(alignment: .bottom, spacing: MTSpacing.s3) {
      MTFlowLayout(spacing: MTSpacing.s1_25) {
        ForEach(
          Array(badges.prefix(horizontalSizeClass == .regular ? badges.count : 2).enumerated()),
          id: \.offset
        ) { _, badge in
          MTBadge(title: badge.title, tone: badge.tone, size: .micro)
        }
      }
      Spacer(minLength: 0)
      Image(.chevron)
        .font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(minHeight: MTSize.RecordCard.footerHeight - MTSpacing.s3, alignment: .bottom)
    .padding(.top, MTSpacing.s3)
    .overlay(alignment: .top) { MTListDivider() }
    .padding(.top, MTSpacing.s2)
  }
}
