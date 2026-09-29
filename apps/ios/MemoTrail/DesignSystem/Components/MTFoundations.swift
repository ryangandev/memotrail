import SwiftUI
import UIKit

// Native text roles mirror the Web token roles and follow Dynamic Type.
// Each role maps to the iOS text style whose default size matches the Web token.
enum MTFont {
  static let display = Font.system(.largeTitle, design: .serif).weight(.medium)
  static let title = Font.system(.title, design: .serif).weight(.medium)
  static let titleSmall = Font.title3.weight(.semibold)
  static let bodyLarge = Font.body
  static let body = Font.subheadline
  static let label = Font.footnote.weight(.medium)
  static let caption = Font.caption.weight(.medium)
  /// Compact list and card headings.
  static let heading = Font.headline
  /// Serif record, Collection, and empty-state titles at the title-small size.
  static let cardTitle = Font.system(.title3, design: .serif).weight(.medium)
  /// Uppercase eyebrows, metadata, and dense badges.
  static let micro = Font.caption2.weight(.semibold)
}

// Semantic icons share the Web icon vocabulary and resolve to SF Symbols.
enum MTIcon: String, CaseIterable, Sendable {
  case archive = "archivebox"
  case arrowLeft = "arrow.left"
  case arrowRight = "arrow.right"
  case bold = "bold"
  case bulletList = "list.bullet"
  case calendar = "calendar"
  case car = "car"
  case check = "checkmark"
  case chevron = "chevron.right"
  case close = "xmark"
  case clock = "clock"
  case code = "chevron.left.forwardslash.chevron.right"
  case codeBlock = "curlybraces.square"
  case collection = "square.stack"
  case dashboard = "square.grid.2x2"
  case edit = "square.and.pencil"
  case export = "square.and.arrow.up"
  case history = "clock.arrow.circlepath"
  case home = "house"
  case inbox = "tray"
  case italic = "italic"
  case link = "link"
  case library = "books.vertical"
  case map = "map"
  case mic = "mic"
  case more = "ellipsis"
  case orderedList = "list.number"
  case people = "person.2"
  case person = "person"
  case photo = "photo"
  case plus = "plus"
  case quote = "text.quote"
  case refresh = "arrow.clockwise"
  case search = "magnifyingglass"
  case settings = "gearshape"
  case sparkle = "sparkles"
  case star = "star"
  case stop = "stop.fill"
  case strike = "strikethrough"
  case tag = "tag"
  case target = "target"
  case timeline = "point.bottomleft.forward.to.point.topright.scurvepath"
  case trash = "trash"
  case underline = "underline"
  case warning = "exclamationmark.triangle"

  var systemName: String { rawValue }
}

extension Image {
  init(_ icon: MTIcon) { self.init(systemName: icon.systemName) }
}

extension Label where Title == Text, Icon == Image {
  init(_ title: String, icon: MTIcon) { self.init(title, systemImage: icon.systemName) }
}

// Page widths match the Web PageFrame variants; phones use the full width with 16 pt gutters.
enum MTPageWidth: CGFloat, CaseIterable, Sendable {
  case compact = 880
  case standard = 960
  case wide = 1080
  case canvas = 1180

  var title: String {
    switch self {
    case .compact: "Compact"
    case .standard: "Standard"
    case .wide: "Wide"
    case .canvas: "Canvas"
    }
  }

  var purpose: String {
    switch self {
    case .compact: "Forms and focused reading"
    case .standard: "Lists and search"
    case .wide: "Dashboards and card grids"
    case .canvas: "Dense spatial views"
    }
  }
}

/// The canonical scrolling page: canvas background, responsive gutters, and a readable width.
struct MTPage<Content: View>: View {
  private let width: MTPageWidth
  private let spacing: CGFloat
  private let content: Content

  init(
    width: MTPageWidth = .standard, spacing: CGFloat = MTSpacing.s8,
    @ViewBuilder content: () -> Content
  ) {
    self.width = width
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: spacing) { content }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
        .frame(maxWidth: width.rawValue, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
    .background(MTColor.canvas)
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
  /// Applies a generated multi-layer shadow token such as `MTShadow.raised`.
  func mtShadow(_ layers: [MTShadowLayer]) -> some View {
    modifier(MTShadowModifier(layers: layers))
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
