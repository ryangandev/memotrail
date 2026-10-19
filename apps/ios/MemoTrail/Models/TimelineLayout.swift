import Foundation

// A pure port of Web `createTimelineLayout` in `apps/web/src/lib/data/timeline-layout.ts`. It
// works in the same numbers as Web: dates are UTC midnights in milliseconds, and pixel
// measures are the Timeline's own, so the same Chapters and First Times land in the same places.

enum TimelineBand: String, CaseIterable, Hashable, Sendable {
  case chapters
  case firstTimes = "first-times"
}

enum TimelineShape: Sendable {
  case bar
  case point
}

/// A Chapter is a bar from its window start to its window end, and a First Time is a point. The
/// window is the whole days the item covers, read in its own time zone: the start is the first
/// day and the end is the day after the last, or nil while the stretch is still going on.
struct TimelineLayoutSource: Equatable, Sendable {
  var band: TimelineBand
  var id: String
  /// The title's rendered width at the band item font.
  var labelWidthPixels: Double
  var shape: TimelineShape
  /// An exclusive `yyyy-MM-dd` date. A bar with none runs to the reference date.
  var windowEnd: String?
  /// A `yyyy-MM-dd` date. Items without a calendar date never reach the layout.
  var windowStart: String
}

/// Where a title sits: inside a bar wide enough to hold it, or beside a point's dot or a short
/// bar, before it only when it would run past the end of the Timeline.
enum TimelineLabelPlacement: Sendable {
  case after
  case before
  case inside
}

/// Overlapping items in one band stack on separate rows. An item is drawn from its anchor at
/// `leftPercent`, shifted by `offsetPixels`, and is `widthPixels` wide including any outside label.
struct TimelinePosition: Equatable, Sendable {
  var barWidthPixels: Double
  var id: String
  var labelPlacement: TimelineLabelPlacement
  var labelWidthPixels: Double
  var leftPercent: Double
  var offsetPixels: Double
  var row: Int
  var widthPixels: Double
}

struct TimelineYearMarker: Equatable, Sendable {
  var label: String
  var leftPercent: Double
  var year: Int
}

struct TimelineLayout: Equatable, Sendable {
  var canvasWidth: Double
  /// The end of the range as an ISO 8601 UTC time with milliseconds, like Web `toISOString`.
  var end: String
  var positions: [TimelinePosition]
  var rowCountByBand: [TimelineBand: Int]
  /// The start of the range as an ISO 8601 UTC time with milliseconds.
  var start: String
  var todayPercent: Double
  var yearMarkers: [TimelineYearMarker]

  /// The calendar year the range starts in.
  var startYear: Int { TimelineCalendar.year(isoString: start) }
  /// The calendar year the range ends in.
  var endYear: Int { TimelineCalendar.year(isoString: end) }
}

/// The Timeline's measures. Each mirrors a constant in Web `timeline-layout.ts` or the band
/// geometry in `timeline-workspace.module.css`; they are the algorithm's own inputs, not
/// design tokens. Names end in `Pixels` and every value is in points on iOS.
enum TimelineMetrics {
  static let minimumRangeMilliseconds = 365.0 * 24 * 60 * 60 * 1_000
  static let minimumCanvasWidthPixels = 840.0
  static let yearWidthPixels = 112.0
  /// A bar's title sits inside when the bar holds it with its padding and borders.
  static let barLabelInsetPixels = 22.0
  static let minimumBarPixels = 10.0
  static let pointDotPixels = 12.0
  static let outsideLabelGapPixels = 7.0
  /// Longer titles beside a dot or bar end in an ellipsis and show in full on hover.
  static let maximumOutsideLabelPixels = 180.0
  /// A Chapter that is also a First Time draws a star before its title, which the title's
  /// measured width does not include.
  static let starAllowancePixels = 18.0
  /// The top of the first row, and the distance from one row to the next.
  static let rowTopPixels = 16.0
  static let rowPitchPixels = 49.0
  static let itemHeightPixels = 34.0
  static let minimumBandPixels = 70.0
  static let bandPaddingPixels = 20.0
  static let axisPixels = 48.0
}

/// Web `estimateLabelWidth`: a title's width before it has been measured.
func estimateLabelWidth(_ text: String) -> Double {
  (Double(text.utf16.count) * 6.2).rounded(.up)
}

/// Web `createTimelineLayout`. The canvas fills the visible width, given as `fillWidthPixels`,
/// and grows past it to keep each year legible.
func createTimelineLayout(
  _ items: [TimelineLayoutSource], referenceDate: Date = Date(), birthDate: String? = nil,
  fillWidthPixels: Double = 0
) -> TimelineLayout {
  let referenceTime = (referenceDate.timeIntervalSince1970 * 1_000).rounded(.down)
  let validReference = referenceTime.isFinite ? referenceTime : Date().timeIntervalSince1970 * 1_000
  let birthTime = TimelineCalendar.time(of: birthDate)
  let normalized: [NormalizedItem] = items.compactMap { item in
    guard let start = TimelineCalendar.time(ofDate: item.windowStart) else { return nil }
    let explicitEnd = item.windowEnd.flatMap { TimelineCalendar.time(ofDate: $0) }
    let end =
      item.shape == .bar ? max(start, explicitEnd ?? validReference) : start
    return NormalizedItem(source: item, start: start, end: end)
  }

  let currentYear = TimelineCalendar.year(milliseconds: validReference)
  var earliest = TimelineCalendar.milliseconds(year: currentYear, month: 1, day: 1)
  var latest = TimelineCalendar.milliseconds(year: currentYear + 1, month: 1, day: 1)

  if !normalized.isEmpty || birthTime != nil {
    earliest = birthTime ?? normalized.map(\.start).min() ?? earliest
    latest = max(validReference, normalized.map(\.end).max() ?? validReference)
    let rawRange = max(latest - earliest, TimelineMetrics.minimumRangeMilliseconds)
    let padding = max(rawRange * 0.025, 30.0 * 24 * 60 * 60 * 1_000)
    if birthTime == nil { earliest -= padding }
    latest += padding

    if latest - earliest < TimelineMetrics.minimumRangeMilliseconds {
      let difference = TimelineMetrics.minimumRangeMilliseconds - (latest - earliest)
      if birthTime == nil { earliest -= difference / 2 }
      latest += difference / 2
    }
  }

  let range = latest - earliest
  var yearMarkers: [TimelineYearMarker] = []
  let firstYear = TimelineCalendar.year(milliseconds: earliest)
  let lastYear = TimelineCalendar.year(milliseconds: latest)

  if birthTime != nil {
    yearMarkers.append(
      TimelineYearMarker(label: String(firstYear), leftPercent: 0, year: firstYear))
  }

  var year = birthTime == nil ? firstYear : firstYear + 1
  while year <= lastYear {
    let position = TimelineCalendar.milliseconds(year: year, month: 1, day: 1)
    if position >= earliest && position <= latest {
      yearMarkers.append(
        TimelineYearMarker(
          label: String(year), leftPercent: clamp((position - earliest) / range * 100), year: year))
    }
    year += 1
  }

  let canvasWidth = max(
    TimelineMetrics.minimumCanvasWidthPixels,
    fillWidthPixels.isFinite ? fillWidthPixels.rounded(.down) : 0,
    Double(yearMarkers.count) * TimelineMetrics.yearWidthPixels)

  let rendered: [RenderedItem] = normalized.map { item in
    let leftPercent = clamp((item.start - earliest) / range * 100)
    let anchor = leftPercent / 100 * canvasWidth
    let spanPixels =
      item.source.shape == .point
      ? 0 : clamp((item.end - item.start) / range * 100) / 100 * canvasWidth

    if item.source.shape == .bar
      && spanPixels >= item.source.labelWidthPixels + TimelineMetrics.barLabelInsetPixels
    {
      return RenderedItem(
        item: item, barWidthPixels: spanPixels, labelPlacement: .inside,
        labelWidthPixels: item.source.labelWidthPixels, leftPercent: leftPercent,
        offsetPixels: 0, visualStart: anchor, visualEnd: anchor + spanPixels,
        widthPixels: spanPixels)
    }

    // A point's dot centers on its date. A short bar covers its dates, and an ongoing one still
    // ends at today.
    let barWidthPixels =
      item.source.shape == .point
      ? TimelineMetrics.pointDotPixels : max(spanPixels, TimelineMetrics.minimumBarPixels)
    let barStart: Double
    if item.source.shape == .point {
      barStart = anchor - TimelineMetrics.pointDotPixels / 2
    } else if item.source.windowEnd == nil {
      barStart = anchor + spanPixels - barWidthPixels
    } else {
      barStart = anchor
    }
    let barEnd = barStart + barWidthPixels
    let labelWidthPixels = min(
      item.source.labelWidthPixels, TimelineMetrics.maximumOutsideLabelPixels)
    let outsideWidth = TimelineMetrics.outsideLabelGapPixels + labelWidthPixels
    let labelPlacement: TimelineLabelPlacement =
      barEnd + outsideWidth <= canvasWidth ? .after : .before
    let visualStart = labelPlacement == .after ? barStart : barStart - outsideWidth
    let visualEnd = labelPlacement == .after ? barEnd + outsideWidth : barEnd

    return RenderedItem(
      item: item, barWidthPixels: barWidthPixels, labelPlacement: labelPlacement,
      labelWidthPixels: labelWidthPixels, leftPercent: leftPercent,
      offsetPixels: visualStart - anchor, visualStart: visualStart, visualEnd: visualEnd,
      widthPixels: visualEnd - visualStart)
  }

  // Bands keep the order their first item appears in; inside a band the items sort by where
  // they are drawn, and equal ones keep their input order (Web relies on a stable sort).
  var bandOrder: [TimelineBand] = []
  var itemsByBand: [TimelineBand: [RenderedItem]] = [:]
  for item in rendered {
    let band = item.item.source.band
    if itemsByBand[band] == nil { bandOrder.append(band) }
    itemsByBand[band, default: []].append(item)
  }

  var positions: [TimelinePosition] = []
  var rowCountByBand: [TimelineBand: Int] = [:]

  for band in bandOrder {
    let bandItems = (itemsByBand[band] ?? []).enumerated().sorted { left, right in
      let a = left.element
      let b = right.element
      if a.visualStart != b.visualStart { return a.visualStart < b.visualStart }
      if a.visualEnd != b.visualEnd { return a.visualEnd < b.visualEnd }
      if a.item.start != b.item.start { return a.item.start < b.item.start }
      return left.offset < right.offset
    }.map(\.element)
    var rowEnds: [Double] = []

    for item in bandItems {
      let row = rowEnds.firstIndex { $0 <= item.visualStart } ?? rowEnds.count
      if row == rowEnds.count {
        rowEnds.append(item.visualEnd)
      } else {
        rowEnds[row] = item.visualEnd
      }
      positions.append(
        TimelinePosition(
          barWidthPixels: item.barWidthPixels, id: item.item.source.id,
          labelPlacement: item.labelPlacement, labelWidthPixels: item.labelWidthPixels,
          leftPercent: item.leftPercent, offsetPixels: item.offsetPixels, row: row,
          widthPixels: item.widthPixels))
    }

    rowCountByBand[band] = max(1, rowEnds.count)
  }

  return TimelineLayout(
    canvasWidth: canvasWidth, end: TimelineCalendar.isoString(milliseconds: latest),
    positions: positions, rowCountByBand: rowCountByBand,
    start: TimelineCalendar.isoString(milliseconds: earliest),
    todayPercent: clamp((validReference - earliest) / range * 100), yearMarkers: yearMarkers)
}

private struct NormalizedItem {
  let source: TimelineLayoutSource
  let start: Double
  let end: Double
}

private struct RenderedItem {
  let item: NormalizedItem
  let barWidthPixels: Double
  let labelPlacement: TimelineLabelPlacement
  let labelWidthPixels: Double
  let leftPercent: Double
  let offsetPixels: Double
  let visualStart: Double
  let visualEnd: Double
  let widthPixels: Double
}

private func clamp(_ value: Double) -> Double {
  max(0, min(100, value))
}

/// The UTC calendar arithmetic the layout shares with JavaScript `Date`: whole days from a
/// civil date, milliseconds since 1970, and a date read as midnight UTC.
enum TimelineCalendar {
  private static let millisecondsPerDay = 86_400_000.0

  /// Web `dateTime`: a `yyyy-MM-dd` date placed at midnight UTC, so year markers sit on
  /// January 1 whatever the viewer's zone. Out-of-range parts roll over like `Date.UTC`.
  static func time(ofDate value: String?) -> Double? {
    guard let value, value.utf8.count == 10 else { return nil }
    let parts = value.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
      parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
      let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    return milliseconds(year: year, month: month, day: day)
  }

  /// Web `validTime` for a birth date: a plain date is midnight UTC, and a full ISO 8601 time is
  /// read as written. Anything else has no time.
  static func time(of value: String?) -> Double? {
    guard let value else { return nil }
    if let date = time(ofDate: value) { return date }
    for options: ISO8601DateFormatter.Options in [
      [.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime],
    ] {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = options
      if let date = formatter.date(from: value) {
        return (date.timeIntervalSince1970 * 1_000).rounded(.down)
      }
    }
    return nil
  }

  /// Web `Date.UTC(year, month - 1, day)`; `month` is 1-based and may overflow into later years.
  static func milliseconds(year: Int, month: Int, day: Int) -> Double {
    let zeroBasedMonth = month - 1
    let adjustedYear = year + Int((Double(zeroBasedMonth) / 12).rounded(.down))
    let normalizedMonth = zeroBasedMonth - Int((Double(zeroBasedMonth) / 12).rounded(.down)) * 12 + 1
    return Double(daysFromCivil(year: adjustedYear, month: normalizedMonth, day: day))
      * millisecondsPerDay
  }

  /// The calendar year a UTC time falls in, like `getUTCFullYear`.
  static func year(milliseconds value: Double) -> Int {
    let days = Int((value / millisecondsPerDay).rounded(.down))
    return civilFromDays(days).year
  }

  static func year(isoString: String) -> Int {
    Int(isoString.prefix(4)) ?? 0
  }

  /// Web `toISOString`: `yyyy-MM-ddTHH:mm:ss.SSSZ`, truncating to whole milliseconds.
  static func isoString(milliseconds value: Double) -> String {
    let whole = value.rounded(.towardZero)
    let days = Int((whole / millisecondsPerDay).rounded(.down))
    let remainder = Int(whole - Double(days) * millisecondsPerDay)
    let civil = civilFromDays(days)
    let hours = remainder / 3_600_000
    let minutes = remainder / 60_000 % 60
    let seconds = remainder / 1_000 % 60
    let millis = remainder % 1_000
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ", civil.year, civil.month, civil.day, hours,
      minutes, seconds, millis)
  }

  // Howard Hinnant's days-from-civil, proleptic Gregorian.
  private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let shifted = month <= 2 ? year - 1 : year
    let era = (shifted >= 0 ? shifted : shifted - 399) / 400
    let yearOfEra = shifted - era * 400
    let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
  }

  private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra =
      (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return (year, month, day)
  }
}
