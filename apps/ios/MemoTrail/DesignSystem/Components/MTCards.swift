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

/// The bordered surface that holds list rows, like the Web Inbox and search result lists.
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

/// The interactive record surface shared by record cards and Collection cards. It works with
/// `Button` and `NavigationLink`, and presses with the stronger border and raised shadow that
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
  var height: CGFloat = MTLayout.RecordCard.visualHeight
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

/// The compact Web Collection card: Entry and Inbox counts, the latest update, and an optional
/// separate management action in the corner.
struct MTCollectionCard<Manage: View>: View {
  let name: String
  let entryCount: Int
  var inboxCount = 0
  var updatedLabel: String?
  let action: () -> Void
  @ViewBuilder var manage: Manage

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        Label("Collection", icon: .archive)
          .labelStyle(MTInlineIconLabelStyle())
          .mtTextRole(.cardEyebrow)
          .foregroundStyle(MTColor.warm)
          .padding(.trailing, MTSpacing.s8)
        Text(name)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .padding(.top, MTSpacing.s3)
        Spacer(minLength: MTSpacing.s3)
        HStack(spacing: MTSpacing.s2) {
          Text(countSummary).lineLimit(1)
          Spacer(minLength: 0)
          Image(.chevron).font(.mtIcon(MTSize.Icon.s12, weight: .semibold))
        }
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        Text(updatedLabel ?? "Ready for its first Entry")
          .font(MTFont.note)
          .foregroundStyle(MTColor.inkFaint)
          .lineLimit(1)
          .padding(.top, MTSpacing.lineGap)
      }
      .frame(
        maxWidth: .infinity, minHeight: MTLayout.RecordCard.collectionMinHeight,
        alignment: .topLeading
      )
      .padding(MTSpacing.s4)
    }
    .buttonStyle(MTCardButtonStyle(radius: MTRadius.medium))
    .accessibilityElement(children: .combine)
    .overlay(alignment: .topTrailing) { manage.padding(MTSpacing.s2) }
  }

  private var countSummary: String {
    let entries = countLabel(entryCount, "Entry")
    return inboxCount > 0 ? "\(entries) · \(inboxCount) in Inbox" : entries
  }
}

extension MTCollectionCard where Manage == EmptyView {
  init(
    name: String, entryCount: Int, inboxCount: Int = 0, updatedLabel: String? = nil,
    action: @escaping () -> Void
  ) {
    self.init(
      name: name, entryCount: entryCount, inboxCount: inboxCount, updatedLabel: updatedLabel,
      action: action
    ) { EmptyView() }
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
