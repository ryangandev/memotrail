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
/// Specified in packages/design-system/components/page-header.yaml.
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
          .frame(maxWidth: MTSize.PageHeader.descriptionWidth, alignment: .leading)
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
/// move below the copy, the same 20 pt gap away.
private struct MTPageHeaderLayout: Layout {
  private static let copyBasis = MTSize.PageHeader.copyBasis
  private let spacing = MTSpacing.s5

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
      CGRect(origin: CGPoint(x: 0, y: copySize.height + spacing), size: wrapped),
    ]
  }
}

extension MTPageHeader where Actions == EmptyView {
  init(eyebrow: String? = nil, title: String, description: String? = nil) {
    self.init(eyebrow: eyebrow, title: title, description: description) { EmptyView() }
  }
}

/// Web `SectionHeader`: the heading of a region of a page, with an optional quiet detail beside
/// the title or at the far edge, a description under it, and a trailing action. The section
/// variant is a serif title; the list variant is the small uppercase heading above a list.
/// Specified in packages/design-system/components/section-header.yaml.
struct MTSectionHeader<Trailing: View>: View {
  let title: String
  var variant = MTSectionHeaderDefaults.variant
  var detail: String?
  var detailAlign = MTSectionHeaderDefaults.detailAlign
  var description: String?
  private let trailing: Trailing
  @Environment(\.dynamicTypeSize) private var typeSize

  init(
    _ title: String, variant: MTSectionHeaderVariant = MTSectionHeaderDefaults.variant,
    detail: String? = nil, detailAlign: MTSectionHeaderDetailAlign = MTSectionHeaderDefaults.detailAlign,
    description: String? = nil, @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.variant = variant
    self.detail = detail
    self.detailAlign = detailAlign
    self.description = description
    self.trailing = trailing()
  }

  var body: some View {
    if typeSize.isAccessibilitySize {
      // At accessibility text sizes the detail and trailing content wrap under the title, like
      // Web when the row is too narrow, so the title keeps the full width.
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        titleText
        if let detail { detailText(detail) }
        descriptionText
        trailing
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      HStack(alignment: rowAlignment, spacing: MTSpacing.s2) {
        VStack(alignment: .leading, spacing: MTSpacing.s0_75) {
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
            titleText
            if detailAlign == .start, let detail { detailText(detail) }
          }
          descriptionText
        }
        Spacer(minLength: MTSpacing.s2)
        if detailAlign == .end, let detail { detailText(detail) }
        trailing
      }
      .frame(minHeight: variant == .list ? MTSize.Control.small : nil)
    }
  }

  @ViewBuilder private var descriptionText: some View {
    if let description {
      Text(description)
        .font(MTFont.detail)
        .foregroundStyle(variant == .list ? MTColor.inkFaint : MTColor.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// A list header centers its row in the reserved height, and a description centers the
  /// trailing content on the whole block, like Web; otherwise the row shares the title's baseline.
  private var rowAlignment: VerticalAlignment {
    variant == .list || description != nil ? .center : .firstTextBaseline
  }

  @ViewBuilder private var titleText: some View {
    switch variant {
    case .section:
      Text(title)
        .font(MTFont.cardTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
    case .list:
      Text(title.uppercased())
        .mtTextRole(.listHeading)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private func detailText(_ detail: String) -> some View {
    Text(detail)
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkFaint)
  }
}

extension MTSectionHeader where Trailing == EmptyView {
  init(
    _ title: String, variant: MTSectionHeaderVariant = MTSectionHeaderDefaults.variant,
    detail: String? = nil, detailAlign: MTSectionHeaderDetailAlign = MTSectionHeaderDefaults.detailAlign,
    description: String? = nil
  ) {
    self.init(
      title, variant: variant, detail: detail, detailAlign: detailAlign, description: description
    ) { EmptyView() }
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
