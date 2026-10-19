import SwiftUI

/// Web `timelineGrid`: the year axis, a band of Chapter bars and a band of First Time points
/// placed by `createTimelineLayout`, and the dashed Today line over both.
struct TimelineCanvas: View {
  let layout: TimelineLayout
  let chapters: [TimelineItem]
  let firstTimes: [TimelineItem]
  let addToTimeline: () -> Void

  @ScaledMetric(relativeTo: .caption2) private var scale = 1

  private var hasItems: Bool { !chapters.isEmpty || !firstTimes.isEmpty }

  private var positions: [String: TimelinePosition] {
    Dictionary(layout.positions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
  }

  var body: some View {
    VStack(spacing: 0) {
      TimelineAxis(layout: layout, scale: scale)
      if !hasItems {
        emptyBand
      }
      if !chapters.isEmpty {
        TimelineBandView(
          label: "Chapters", band: .chapters, items: chapters, layout: layout,
          positions: positions, scale: scale)
      }
      if !firstTimes.isEmpty {
        TimelineBandView(
          label: "First Times", band: .firstTimes, items: firstTimes, layout: layout,
          positions: positions, scale: scale)
      }
    }
    .frame(width: layout.canvasWidth, alignment: .leading)
    .overlay { TimelineTodayLine(layout: layout) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Timeline by year")
    .accessibilityIdentifier("timeline-canvas")
  }

  /// With nothing on it, the canvas offers to start the Timeline, like Web's empty band.
  private var emptyBand: some View {
    ZStack(alignment: .topLeading) {
      MTColor.laneSurface
      Button(action: addToTimeline) {
        Text("Add a Chapter or a First Time to start your Timeline.")
          .font(MTFont.micro)
          .foregroundStyle(MTColor.inkFaint)
          .padding(.horizontal, MTSpacing.s2_5)
          .padding(.vertical, MTSpacing.s1_75)
          .multilineTextAlignment(.leading)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .padding(.leading, MTSpacing.s4)
      .padding(.top, MTSpacing.s4_5)
      .frame(maxWidth: layout.canvasWidth, alignment: .leading)
      .accessibilityIdentifier("timeline-empty-add")
    }
    .frame(height: TimelineMetrics.minimumBandPixels * scale)
    .overlay(alignment: .bottom) { MTColor.border.frame(height: MTSize.Stroke.thin) }
  }
}

/// Web `.axis`: a year on each January 1, in the mono stamp face, with the edges kept clear.
private struct TimelineAxis: View {
  let layout: TimelineLayout
  let scale: CGFloat

  var body: some View {
    ZStack(alignment: .topLeading) {
      MTColor.surface
      ForEach(Array(layout.yearMarkers.enumerated()), id: \.element.year) { index, marker in
        label(marker, isFirst: index == 0, isLast: index == layout.yearMarkers.count - 1)
      }
    }
    .frame(width: layout.canvasWidth, height: TimelineMetrics.axisPixels * scale)
    .overlay(alignment: .bottom) { MTColor.border.frame(height: MTSize.Stroke.thin) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Years \(layout.startYear) to \(layout.endYear)")
    .accessibilityIdentifier("timeline-axis")
  }

  /// A year centers on its line. The first and last years hang off it toward the card, and a
  /// year on the very edge sits one step inside it.
  @ViewBuilder
  private func label(_ marker: TimelineYearMarker, isFirst: Bool, isLast: Bool) -> some View {
    let x = marker.leftPercent / 100 * layout.canvasWidth
    let text = Text(marker.label)
      .mtTextRole(.stamp)
      .foregroundStyle(MTColor.inkFaint)
      .fixedSize()
    let top = TimelineMetrics.axisLabelTopPixels * scale
    if marker.leftPercent == 0 {
      text.frame(width: 0, alignment: .leading).offset(x: x + MTSpacing.s2, y: top)
    } else if marker.leftPercent == 100 {
      text.frame(width: 0, alignment: .trailing).offset(x: x - MTSpacing.s2, y: top)
    } else if isFirst {
      text.frame(width: 0, alignment: .leading).offset(x: x, y: top)
    } else if isLast {
      text.frame(width: 0, alignment: .trailing).offset(x: x, y: top)
    } else {
      text.frame(width: 0).offset(x: x, y: top)
    }
  }
}

/// One band: the faint year lines, then each item at its row.
private struct TimelineBandView: View {
  let label: String
  let band: TimelineBand
  let items: [TimelineItem]
  let layout: TimelineLayout
  let positions: [String: TimelinePosition]
  let scale: CGFloat

  private var rowCount: Int { layout.rowCountByBand[band] ?? 1 }

  private var height: CGFloat { TimelineMetrics.bandHeightPixels(rows: rowCount) * scale }

  var body: some View {
    ZStack(alignment: .topLeading) {
      MTColor.laneSurface
      ForEach(layout.yearMarkers, id: \.year) { marker in
        MTColor.borderFaint
          .frame(width: MTSize.Stroke.thin, height: height)
          .offset(x: marker.leftPercent / 100 * layout.canvasWidth)
      }
      ForEach(items) { item in
        if let position = positions[item.id.uuidString.lowercased()] {
          TimelineItemView(
            item: item, position: position, canvasWidth: layout.canvasWidth, scale: scale)
        }
      }
    }
    .frame(width: layout.canvasWidth, height: height, alignment: .topLeading)
    .clipped()
    .overlay(alignment: .bottom) { MTColor.border.frame(height: MTSize.Stroke.thin) }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(label)
    .accessibilityIdentifier("timeline-band-\(band.rawValue)")
  }
}

/// A Chapter bar or a First Time point and its title, opening the Item page.
private struct TimelineItemView: View {
  let item: TimelineItem
  let position: TimelinePosition
  let canvasWidth: Double
  let scale: CGFloat

  private var isOngoing: Bool { item.isChapter && item.windowEnd == nil }
  private var showsStar: Bool { item.isChapter && item.isFirstTime }
  private var itemHeight: CGFloat { TimelineMetrics.itemHeightPixels * scale }

  var body: some View {
    NavigationLink(value: ItemLink(entryID: item.id)) {
      content
        .frame(width: position.widthPixels, height: itemHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(TimelineItemButtonStyle())
    .offset(
      x: position.leftPercent / 100 * canvasWidth + position.offsetPixels,
      y: (TimelineMetrics.rowTopPixels + Double(position.row) * TimelineMetrics.rowPitchPixels)
        * scale
    )
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.accessibleName)
    .accessibilityIdentifier("timeline-item-\(item.id.uuidString.lowercased())")
  }

  @ViewBuilder
  private var content: some View {
    switch position.labelPlacement {
    case .inside:
      title(width: nil)
        .padding(.horizontal, MTSpacing.s2_5)
        .frame(width: position.widthPixels, height: itemHeight, alignment: .leading)
        .background { TimelineBar(isOngoing: isOngoing) }
    case .after:
      HStack(spacing: TimelineMetrics.outsideLabelGapPixels) {
        marker
        title(width: position.labelWidthPixels).background(MTColor.laneSurface)
      }
    case .before:
      HStack(spacing: TimelineMetrics.outsideLabelGapPixels) {
        title(width: position.labelWidthPixels, alignment: .trailing)
          .background(MTColor.laneSurface)
        marker
      }
    }
  }

  /// The bar or dot beside an outside title.
  @ViewBuilder
  private var marker: some View {
    if item.isChapter {
      TimelineBar(isOngoing: isOngoing)
        .frame(width: position.barWidthPixels, height: itemHeight)
    } else {
      TimelineDot()
        .frame(width: position.barWidthPixels, height: position.barWidthPixels)
        .frame(height: itemHeight)
    }
  }

  private func title(width: Double?, alignment: Alignment = .leading) -> some View {
    HStack(spacing: MTSpacing.s1) {
      if showsStar {
        Image(.star)
          .font(.mtIcon(MTSize.Icon.s12))
          .foregroundStyle(MTColor.warm)
      }
      Text(item.displayTitle)
        .font(MTFont.micro)
        .foregroundStyle(MTColor.ink)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .frame(width: width.map { CGFloat($0) }, alignment: alignment)
    .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
  }
}

private struct TimelineItemButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .opacity(configuration.isPressed ? MTState.Disabled.Opacity.soft : 1)
  }
}

/// Web `.bar`: a Chapter's span. An open Chapter squares its end and rules it in the accent,
/// because it runs on to today.
private struct TimelineBar: View {
  let isOngoing: Bool

  private var shape: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: MTRadius.small, bottomLeadingRadius: MTRadius.small,
      bottomTrailingRadius: isOngoing ? 0 : MTRadius.small,
      topTrailingRadius: isOngoing ? 0 : MTRadius.small)
  }

  var body: some View {
    shape
      .fill(MTColor.accentSubtle)
      .overlay { shape.strokeBorder(MTColor.accentBorderStrong, lineWidth: MTSize.Stroke.thin) }
      .overlay(alignment: .trailing) {
        if isOngoing {
          MTColor.accent.frame(width: MTSize.Stroke.medium)
        }
      }
      .clipShape(shape)
  }
}

/// Web `.pointDot`: a First Time on its date.
private struct TimelineDot: View {
  var body: some View {
    Circle()
      .fill(MTColor.warm)
      .overlay { Circle().strokeBorder(MTColor.surfaceRaised, lineWidth: MTSize.Stroke.thick) }
      .overlay {
        Circle()
          .inset(by: -MTSize.Stroke.thin)
          .stroke(MTColor.warm, lineWidth: MTSize.Stroke.thin)
      }
  }
}

/// Web `.todayLine`: a dashed rule through both bands at today, tagged "Today" beside it.
private struct TimelineTodayLine: View {
  let layout: TimelineLayout

  var body: some View {
    let x = layout.todayPercent / 100 * layout.canvasWidth
    GeometryReader { proxy in
      Path { path in
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
      }
      .stroke(
        MTColor.accentStripe,
        style: StrokeStyle(
          lineWidth: MTSize.Stroke.thin,
          dash: [TimelineMetrics.todayDashPixels, TimelineMetrics.todayDashPixels]))
      Text("Today")
        .mtTextRole(.eyebrow)
        .foregroundStyle(MTColor.accent)
        .padding(.horizontal, MTSpacing.s1)
        .padding(.vertical, MTSpacing.s0_25)
        .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.xxsmall))
        .fixedSize()
        .frame(width: 0, alignment: .trailing)
        .offset(x: max(x - MTSpacing.s1_5, 0), y: MTSpacing.s1_75)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .accessibilityIdentifier("timeline-today")
  }
}
