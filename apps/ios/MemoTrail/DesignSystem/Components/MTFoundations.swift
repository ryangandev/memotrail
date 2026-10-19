import SwiftUI
import UIKit

// MTFont, MTTextRole, MTIcon, and MTPageWidth are generated in DesignTokens.swift.

extension Image {
  init(_ icon: MTIcon) { self.init(systemName: icon.systemName) }
}

extension Label where Title == Text, Icon == Image {
  init(_ title: String, icon: MTIcon) { self.init(title, systemImage: icon.systemName) }
}

/// Applies a text role's font, tracking, and case. A role with a static `MTFont` uses it, so
/// `mtTextRole(.listHeading)` draws exactly like `.font(MTFont.listHeading)` plus its tracking and
/// case. Roles that scale a custom size with a Dynamic Type style, such as `MTTextRole.hero`,
/// scale that size and its tracking together.
private struct MTTextRoleModifier: ViewModifier {
  let role: MTTextRole
  @ScaledMetric private var scaledSize: CGFloat

  init(role: MTTextRole) {
    self.role = role
    _scaledSize = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle ?? .body)
  }

  func body(content: Content) -> some View {
    let size = role.textStyle == nil ? role.size : scaledSize
    let styled =
      content
      .font(role.font ?? .system(size: size, weight: role.weight, design: role.design))
      .tracking(role.font == nil ? role.tracking * size / role.size : role.tracking)
    if role.isUppercase {
      styled.textCase(.uppercase)
    } else {
      styled
    }
  }
}

extension Font {
  /// An SF Symbol glyph at a generated icon size, such as `.mtIcon(MTSize.Icon.s12)`.
  static func mtIcon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight)
  }
}

/// The canonical scrolling page: canvas background, responsive gutters, and a readable width.
struct MTPage<Content: View>: View {
  private let width: MTPageFrameWidth
  private let spacing: CGFloat
  private let content: Content

  init(
    width: MTPageFrameWidth = MTPageFrameDefaults.width, spacing: CGFloat = MTSpacing.s8,
    @ViewBuilder content: () -> Content
  ) {
    self.width = width
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: spacing) { content }
        .padding(.horizontal, MTLayout.PageGutter.compact)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
        .frame(maxWidth: width.maxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
    .background(MTColor.canvas)
  }
}

extension MTPageFrameWidth {
  /// The widest the page gets, from the shared `layout.pageWidth` tokens.
  var pageWidth: MTPageWidth {
    switch self {
    case .compact: .compact
    case .standard: .standard
    case .wide: .wide
    case .canvas: .canvas
    }
  }

  var maxWidth: CGFloat { pageWidth.rawValue }
}

/// Wraps children onto new lines like Web `flex-wrap`, for badges, chips, and compact actions.
/// An `MTFlowSeparator` child shows only between two items on one line, like Web `SeparatedList`.
/// Lines share the leading edge, or the trailing edge with `align: .end`. Children of one line
/// share their vertical centers, or their first text baselines with
/// `rowAlignment: .firstTextBaseline`.
/// Specified in packages/design-system/components/separated-list.yaml.
struct MTFlowLayout: Layout {
  var spacing: CGFloat = MTSpacing.s2
  var lineSpacing: CGFloat?
  var align = MTSeparatedListDefaults.align
  var rowAlignment = MTSeparatedListDefaults.rowAlignment

  /// A child as line breaking sees it.
  struct Item: Equatable {
    var size: CGSize
    var isSeparator = false
    /// The first text baseline, measured from the child's top.
    var baseline: CGFloat = 0
  }

  /// A line's shown children, from its leading edge, and its size.
  struct Line: Equatable {
    var indices: [Int]
    var width: CGFloat
    var height: CGFloat
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let items = items(subviews, width: width)
    let lines = Self.lines(for: items, width: width, spacing: spacing)
    let height =
      lines.map { Self.rowOffsets(of: $0, items: items, alignment: rowAlignment).height }
      .reduce(0, +) + CGFloat(max(lines.count - 1, 0)) * rowGap
    return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    let items = items(subviews, width: bounds.width)
    var collapsed = Set(subviews.indices)
    var y = bounds.minY
    for line in Self.lines(for: items, width: bounds.width, spacing: spacing) {
      let row = Self.rowOffsets(of: line, items: items, alignment: rowAlignment)
      var x =
        switch align {
        case .start: bounds.minX
        case .end: bounds.maxX - line.width
        }
      for (index, offset) in zip(line.indices, row.offsets) {
        let size = CGSize(
          width: min(items[index].size.width, bounds.width), height: items[index].size.height)
        subviews[index].place(at: CGPoint(x: x, y: y + offset), proposal: ProposedViewSize(size))
        collapsed.remove(index)
        x += size.width + spacing
      }
      y += row.height + rowGap
    }
    // A separator left out of every line gets no width, so it draws nothing.
    for index in collapsed { subviews[index].place(at: bounds.origin, proposal: .zero) }
  }

  /// Breaks children into lines like `flex-wrap`, fitting each one to `width`. A separator
  /// belongs to the item after it and shows only when that item joins a line behind another
  /// item, so no line starts or ends with one. A run of separators shows at most its first.
  static func lines(for items: [Item], width: CGFloat, spacing: CGFloat) -> [Line] {
    var lines: [Line] = []
    var separator: Int?
    for (index, item) in items.enumerated() {
      if item.isSeparator {
        if separator == nil, !lines.isEmpty { separator = index }
        continue
      }
      let joining = (separator.map { [$0] } ?? []) + [index]
      separator = nil
      let added = joining.reduce(0) { $0 + spacing + min(items[$1].size.width, width) }
      if var line = lines.last, line.width + added <= width {
        line.indices += joining
        line.width += added
        line.height = joining.reduce(line.height) { max($0, items[$1].size.height) }
        lines[lines.count - 1] = line
      } else {
        lines.append(
          Line(indices: [index], width: min(item.size.width, width), height: item.size.height))
      }
    }
    return lines
  }

  /// Where each child of `line` sits below the line's top, in the line's order, and the
  /// line's height once they are aligned.
  static func rowOffsets(
    of line: Line, items: [Item], alignment: MTSeparatedListRowAlignment
  ) -> (offsets: [CGFloat], height: CGFloat) {
    switch alignment {
    case .center:
      return (line.indices.map { (line.height - items[$0].size.height) / 2 }, line.height)
    case .firstTextBaseline:
      let baseline = line.indices.map { items[$0].baseline }.max() ?? 0
      let offsets = line.indices.map { baseline - items[$0].baseline }
      let height =
        zip(line.indices, offsets).map { $1 + items[$0].size.height }.max() ?? 0
      return (offsets, height)
    }
  }

  private var rowGap: CGFloat { lineSpacing ?? spacing }

  private func items(_ subviews: Subviews, width: CGFloat) -> [Item] {
    let proposal = ProposedViewSize(width: width, height: nil)
    return subviews.map { subview in
      let isSeparator = subview[MTFlowSeparatorKey.self]
      switch rowAlignment {
      case .center:
        return Item(size: subview.sizeThatFits(proposal), isSeparator: isSeparator)
      case .firstTextBaseline:
        let dimensions = subview.dimensions(in: proposal)
        return Item(
          size: CGSize(width: dimensions.width, height: dimensions.height),
          isSeparator: isSeparator,
          baseline: dimensions[VerticalAlignment.firstTextBaseline])
      }
    }
  }
}

private struct MTFlowSeparatorKey: LayoutValueKey {
  static let defaultValue = false
}

/// The quiet "·" between facts in an `MTFlowLayout`, like Web `SeparatedList`. It shows only
/// between two items on one line, and assistive technology skips it.
struct MTFlowSeparator: View {
  var body: some View {
    // At a line's edge the layout proposes no width, which only the empty choice fits.
    ViewThatFits(in: .horizontal) {
      Text("·")
      Color.clear.frame(width: 0, height: 0)
    }
    .accessibilityHidden(true)
    .layoutValue(key: MTFlowSeparatorKey.self, value: true)
  }
}

/// An `MTFlowLayout` for plain facts that read like a sentence, like Web `SeparatedList` with
/// word spacing: one word space apart at `textStyle`, with wrapped lines as close as the text's.
struct MTWordFlow<Content: View>: View {
  private let textStyle: UIFont.TextStyle
  private let align: MTSeparatedListAlign
  private let content: Content
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.lineSpacing) private var lineSpacing

  init(
    _ textStyle: UIFont.TextStyle, align: MTSeparatedListAlign = MTSeparatedListDefaults.align,
    @ViewBuilder content: () -> Content
  ) {
    self.textStyle = textStyle
    self.align = align
    self.content = content()
  }

  var body: some View {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    let font = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits)
    MTFlowLayout(
      spacing: (" " as NSString).size(withAttributes: [.font: font]).width,
      lineSpacing: lineSpacing, align: align
    ) { content }
  }
}

// SwiftUI line spacing is additive, so derive it from the Web multiplier and the current text size.
private struct MTLineSpacingModifier: ViewModifier {
  let multiplier: CGFloat
  let textStyle: UIFont.TextStyle
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  func body(content: Content) -> some View {
    let traits = UITraitCollection(
      preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
    let size = UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: traits).pointSize
    content.lineSpacing(max(0, (multiplier - 1.2) * size))
  }
}

private struct MTShadowModifier: ViewModifier {
  let layers: [MTShadowLayer]

  func body(content: Content) -> some View {
    content
      .shadow(layer(0))
      .shadow(layer(1))
      .shadow(layer(2))
  }

  private func layer(_ index: Int) -> MTShadowLayer? {
    index < layers.count ? layers[index] : nil
  }
}

extension View {
  /// Applies a generated text role such as `MTTextRole.hero`.
  func mtTextRole(_ role: MTTextRole) -> some View {
    modifier(MTTextRoleModifier(role: role))
  }

  /// Applies a generated multi-layer shadow token such as `MTShadow.raised`.
  func mtShadow(_ layers: [MTShadowLayer]) -> some View {
    modifier(MTShadowModifier(layers: layers))
  }

  /// Fills the background with a material token such as `MTMaterial.glassPanel`: its tint over
  /// its system material, in `shape`. Callers that want the token's border draw it themselves.
  func mtMaterial<S: Shape>(_ material: MTMaterialToken, in shape: S) -> some View {
    background(material.tint, in: shape)
      .background {
        if let system = material.systemMaterial { shape.fill(system.material) }
      }
  }

  /// Fills the rectangular background with a material token such as `MTMaterial.glassPanel`.
  func mtMaterial(_ material: MTMaterialToken) -> some View {
    mtMaterial(material, in: Rectangle())
  }

  /// Approximates a Web line-height token, such as `MTLineHeight.body`, for the given text style.
  func mtLineSpacing(_ multiplier: CGFloat, textStyle: UIFont.TextStyle = .subheadline)
    -> some View
  {
    modifier(MTLineSpacingModifier(multiplier: multiplier, textStyle: textStyle))
  }

  fileprivate func shadow(_ layer: MTShadowLayer?) -> some View {
    shadow(
      color: layer?.color ?? .clear, radius: layer?.radius ?? 0, x: layer?.x ?? 0,
      y: layer?.y ?? 0)
  }
}
