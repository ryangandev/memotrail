import SwiftUI

/// Uppercase warm context above a title, such as a date or area name.
struct MTEyebrow: View {
  let text: String
  var tone: Color = MTColor.warm

  var body: some View {
    Text(text.uppercased())
      .mtTextRole(.pageEyebrow)
      .foregroundStyle(tone)
  }
}

/// The page title block: optional eyebrow, serif title, description, and actions.
/// Titles use the compact title size on phones, like the Web header below 560 px.
struct MTPageHeader<Actions: View>: View {
  let eyebrow: String?
  let title: String
  let description: String?
  private let actions: Actions
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  init(
    eyebrow: String? = nil, title: String, description: String? = nil,
    @ViewBuilder actions: () -> Actions
  ) {
    self.eyebrow = eyebrow
    self.title = title
    self.description = description
    self.actions = actions()
  }

  var body: some View {
    MTPageHeaderLayout {
      copy
      actionRow
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var copy: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      if let eyebrow { MTEyebrow(text: eyebrow) }
      Text(title)
        .font(horizontalSizeClass == .regular ? MTFont.display : MTFont.title)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      if let description {
        Text(description)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
          .frame(maxWidth: MTLayout.PageHeader.descriptionWidth, alignment: .leading)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var actionRow: some View {
    HStack(spacing: MTSpacing.s2) { actions }
  }
}

/// Web `PageHeader` wrapping: the copy keeps a 260 pt basis and its title wraps beside the
/// actions while both fit, so a small Edit stays beside a long title; otherwise the actions
/// move below the copy.
private struct MTPageHeaderLayout: Layout {
  private static let copyBasis = MTLayout.PageHeader.copyBasis
  private let spacing = MTSpacing.s5
  private let wrapSpacing = MTSpacing.s4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let frames = arrange(width: proposal.width, subviews: subviews)
    return CGSize(
      width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    for (subview, frame) in zip(subviews, arrange(width: bounds.width, subviews: subviews)) {
      subview.place(
        at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
        proposal: ProposedViewSize(frame.size))
    }
  }

  /// The copy's and the actions' frames for a width, or for their ideal sizes without one.
  private func arrange(width: CGFloat?, subviews: Subviews) -> [CGRect] {
    guard let copy = subviews.first else { return [] }
    let actions = subviews.count > 1 ? subviews[1].sizeThatFits(.unspecified) : .zero
    guard actions.width > 0 else {
      return [
        CGRect(origin: .zero, size: copy.sizeThatFits(ProposedViewSize(width: width, height: nil)))
      ]
    }
    guard let width else {
      let ideal = copy.sizeThatFits(.unspecified)
      return [
        CGRect(origin: .zero, size: ideal),
        CGRect(origin: CGPoint(x: ideal.width + spacing, y: 0), size: actions),
      ]
    }
    if Self.copyBasis + spacing + actions.width <= width {
      let copyWidth = width - spacing - actions.width
      let copySize = copy.sizeThatFits(ProposedViewSize(width: copyWidth, height: nil))
      return [
        CGRect(origin: .zero, size: CGSize(width: copyWidth, height: copySize.height)),
        CGRect(origin: CGPoint(x: width - actions.width, y: 0), size: actions),
      ]
    }
    let copySize = copy.sizeThatFits(ProposedViewSize(width: width, height: nil))
    let wrapped = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
    return [
      CGRect(origin: .zero, size: CGSize(width: width, height: copySize.height)),
      CGRect(origin: CGPoint(x: 0, y: copySize.height + wrapSpacing), size: wrapped),
    ]
  }
}

extension MTPageHeader where Actions == EmptyView {
  init(eyebrow: String? = nil, title: String, description: String? = nil) {
    self.init(eyebrow: eyebrow, title: title, description: description) { EmptyView() }
  }
}

/// A section title with an optional count or detail and a trailing action.
struct MTSectionHeader<Trailing: View>: View {
  let title: String
  var detail: String?
  private let trailing: Trailing

  init(_ title: String, detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.detail = detail
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
      VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
        Text(title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        if let detail {
          Text(detail).font(MTFont.caption).foregroundStyle(MTColor.inkMuted)
        }
      }
      Spacer(minLength: MTSpacing.s2)
      trailing
    }
  }
}

extension MTSectionHeader where Trailing == EmptyView {
  init(_ title: String, detail: String? = nil) {
    self.init(title, detail: detail) { EmptyView() }
  }
}

/// The small uppercase heading above a list, like the Web Inbox and Library headings: a title,
/// a quiet count beside it or at the far edge, and an optional trailing action.
struct MTListHeader<Trailing: View>: View {
  let title: String
  var detail: String?
  var alignsDetailTrailing = false
  private let trailing: Trailing

  init(
    _ title: String, detail: String? = nil, alignsDetailTrailing: Bool = false,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.detail = detail
    self.alignsDetailTrailing = alignsDetailTrailing
    self.trailing = trailing()
  }

  var body: some View {
    HStack(alignment: .center, spacing: MTSpacing.s2) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
        Text(title.uppercased())
          .mtTextRole(.listHeading)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        if alignsDetailTrailing { Spacer(minLength: MTSpacing.s2) }
        if let detail {
          Text(detail)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      if !alignsDetailTrailing { Spacer(minLength: MTSpacing.s2) }
      trailing
    }
    .frame(minHeight: MTSize.Control.small)
  }
}

extension MTListHeader where Trailing == EmptyView {
  init(_ title: String, detail: String? = nil, alignsDetailTrailing: Bool = false) {
    self.init(title, detail: detail, alignsDetailTrailing: alignsDetailTrailing) { EmptyView() }
  }
}

/// The accent "Open ›" link used by section headers and footers.
struct MTSectionLink: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: MTSpacing.s1) {
        Text(title)
        Image(.chevron).font(.mtIcon(MTSize.Icon.s11, weight: .semibold))
      }
      .font(MTFont.caption)
      .foregroundStyle(MTColor.accent)
      .frame(minHeight: MTSize.hitTarget)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
