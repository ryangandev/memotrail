import SwiftUI

/// A plain raised surface for grouped content that is not itself interactive.
struct MTCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MTSpacing.s4)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).stroke(
          MTColor.border, lineWidth: MTSize.Stroke.thin)
      }
  }
}

/// The bordered surface that holds list rows, like the Web search result lists.
/// Separate rows with `MTListDivider`.
struct MTListSurface<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) { self.content = content() }

  var body: some View {
    VStack(spacing: 0) { content }
      .frame(maxWidth: .infinity)
      .background(MTColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
          MTColor.border, lineWidth: MTSize.Stroke.thin)
      }
  }
}

/// The hairline between list rows.
struct MTListDivider: View {
  var body: some View {
    Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin).accessibilityHidden(true)
  }
}

/// A whole-row link in a list, which shows the Web hover surface while pressed.
struct MTListRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        configuration.isPressed ? MTColor.surfaceRaised : .clear,
        in: RoundedRectangle(cornerRadius: MTRadius.medium)
      )
      .contentShape(Rectangle())
      .animation(MTEasing.enter.animation(duration: MTMotion.quick), value: configuration.isPressed)
  }
}

/// The interactive record surface shared by record cards. It works with `Button` and
/// `NavigationLink`, and presses with the stronger border and raised shadow that
/// the Web card shows on hover.
struct MTCardButtonStyle: ButtonStyle {
  var radius: CGFloat = MTRadius.large

  func makeBody(configuration: Configuration) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius)
    configuration.label
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.surfaceRaised)
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(
          configuration.isPressed ? MTColor.borderStrong : MTColor.border,
          lineWidth: MTSize.Stroke.thin)
      }
      .mtShadow(
        configuration.isPressed
          ? MTShadow.raised
          : MTShadow.hairline
      )
      .scaleEffect(configuration.isPressed ? MTState.Pressed.cardScale : 1)
      .contentShape(shape)
      .animation(MTEasing.enter.animation(duration: MTMotion.quick), value: configuration.isPressed)
  }
}

/// The Web RecordCard: one action over an optional `MTRecordCardVisual` and an `MTRecordCardBody`.
/// Specified in packages/design-system/components/record-card.yaml.
struct MTRecordCard<Content: View>: View {
  var accessibilityLabel: String?
  let action: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    let button = Button(action: action) {
      VStack(alignment: .leading, spacing: 0) { content }
    }
    .buttonStyle(MTCardButtonStyle())
    if let accessibilityLabel {
      button.accessibilityLabel(accessibilityLabel)
    } else {
      button
    }
  }
}

/// The media band at the top of a record card.
struct MTRecordCardVisual<Content: View>: View {
  var height: CGFloat = MTSize.RecordCard.visualHeight
  @ViewBuilder var content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(MTColor.surfaceSubtle)
      .clipped()
      .contentShape(Rectangle())
      .overlay(alignment: .bottom) {
        Rectangle().fill(MTColor.border).frame(height: MTSize.Stroke.thin)
      }
  }
}

/// The padded text area of a record card.
struct MTRecordCardBody<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MTSpacing.s5)
  }
}

/// Web `RecordCard` footer: any status badges, then up to two tags, and the chevron. Phones
/// show the first two badges, like Web below 480 px.
struct MTRecordCardFooter: View {
  var status: [(title: String, tone: MTBadgeTone)] = []
  let tagNames: [String]
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let badges = status + tagNames.prefix(2).map { ("#\($0)", MTBadgeTone.neutral) }
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

/// A record's Kind, title, and context line, used where a full record card is too large.
struct MTRecordSummary: View {
  let title: String
  let subtitle: String
  let kind: String
  var status: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      ViewThatFits(in: .horizontal) {
        badges
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          MTBadge(title: kind, tone: .accent)
          if let status { MTBadge(title: status, tone: .warm) }
        }
      }
      Text(title).font(MTFont.heading).foregroundStyle(MTColor.ink)
      Text(subtitle).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var badges: some View {
    HStack(spacing: MTSpacing.s2) {
      MTBadge(title: kind, tone: .accent)
      if let status { MTBadge(title: status, tone: .warm) }
    }
  }
}
