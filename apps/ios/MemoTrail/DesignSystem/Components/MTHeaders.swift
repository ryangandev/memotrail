import SwiftUI

/// Uppercase warm context above a title, such as a date or area name.
struct MTEyebrow: View {
  let text: String
  var tone: Color = MTColor.warm

  var body: some View {
    Text(text.uppercased())
      .font(MTFont.caption.weight(.semibold))
      .tracking(1)
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
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: MTSpacing.s5) {
        copy
        Spacer(minLength: 0)
        actionRow
      }
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        copy
        actionRow
      }
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
          .frame(maxWidth: 640, alignment: .leading)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var actionRow: some View {
    HStack(spacing: MTSpacing.s2) { actions }
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
      VStack(alignment: .leading, spacing: 2) {
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
          .font(MTFont.label.weight(.semibold))
          .tracking(0.5)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        if alignsDetailTrailing { Spacer(minLength: MTSpacing.s2) }
        if let detail {
          Text(detail)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      if !alignsDetailTrailing { Spacer(minLength: MTSpacing.s2) }
      trailing
    }
    .frame(minHeight: 34)
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
        Image(.chevron).font(.system(size: 11, weight: .semibold))
      }
      .font(MTFont.caption)
      .foregroundStyle(MTColor.accent)
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
