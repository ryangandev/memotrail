import SwiftUI

enum MTDateGranularity: CaseIterable, Sendable {
  case day, month, year

  var title: String {
    switch self {
    case .day: "day"
    case .month: "month"
    case .year: "year"
    }
  }
}

/// Converts the wall-time text used by drafts ("yyyy", "yyyy-MM", "yyyy-MM-dd", or
/// "yyyy-MM-dd'T'HH:mm:ss") to and from dates read in UTC, so no time zone shifts the value.
enum MTDateText {
  static func date(_ text: String, granularity: MTDateGranularity, includesTime: Bool) -> Date? {
    let formats =
      switch granularity {
      case .year: ["yyyy"]
      case .month: ["yyyy-MM"]
      case .day:
        includesTime ? ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] : ["yyyy-MM-dd"]
      }
    for format in formats {
      let formatter = formatter(format)
      if let date = formatter.date(from: text), formatter.string(from: date) == text,
        !text.hasPrefix("0000")
      {
        return date
      }
    }
    return nil
  }

  static func text(_ date: Date, granularity: MTDateGranularity, includesTime: Bool) -> String {
    let format =
      switch granularity {
      case .year: "yyyy"
      case .month: "yyyy-MM"
      case .day: includesTime ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd"
      }
    return formatter(format).string(from: date)
  }

  /// Today's wall time in `timeZone`, read back as a UTC date.
  static func now(in timeZone: TimeZone, now: Date = Date()) -> Date {
    now.addingTimeInterval(Double(timeZone.secondsFromGMT(for: now)))
  }

  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
  }

  static func display(_ date: Date, granularity: MTDateGranularity) -> String {
    let style = Date.FormatStyle(calendar: calendar, timeZone: .gmt)
    return switch granularity {
    case .day: date.formatted(style.month(.abbreviated).day().year())
    case .month: date.formatted(style.month(.wide).year())
    case .year: date.formatted(style.year())
    }
  }

  static func displayTime(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(calendar: calendar, timeZone: .gmt).hour().minute())
  }

  private static func formatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .gmt
    formatter.dateFormat = format
    formatter.isLenient = false
    return formatter
  }
}

/// A labeled, optional calendar value at day, month, or year granularity, with an optional time.
/// The picker commits each change immediately, like the native compact date picker.
struct MTDateField: View {
  let label: String
  @Binding var value: String
  var granularity: MTDateGranularity = .day
  var includesTime = false
  var size: MTFieldSize = .medium
  var isRequired = false
  var note: String?
  var timeZone: TimeZone = .current
  @State private var isPicking = false
  @Environment(\.isEnabled) private var isEnabled

  private var date: Date? {
    MTDateText.date(value, granularity: granularity, includesTime: includesTime)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: label, isRequired: isRequired, note: note)
      HStack(spacing: MTSpacing.s1) {
        Button {
          isPicking = true
        } label: {
          HStack(spacing: MTSpacing.s2) {
            Image(.calendar).foregroundStyle(MTColor.inkFaint)
            Text(dateText ?? placeholder)
              .foregroundStyle(value.isEmpty ? MTColor.inkFaint : MTColor.ink)
              .lineLimit(1)
            Spacer(minLength: MTSpacing.s2)
            if includesTime, let date {
              Image(.clock).foregroundStyle(MTColor.inkMuted)
              Text(MTDateText.displayTime(date)).foregroundStyle(MTColor.ink)
            }
          }
          .frame(maxHeight: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRequired ? "\(label), required" : label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens a \(includesTime ? "date and time" : granularity.title) picker")
        if !value.isEmpty {
          Button {
            value = ""
          } label: {
            Image(.close).font(.system(size: 12, weight: .semibold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(MTColor.inkMuted)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
          .accessibilityLabel("Clear \(label.lowercased())")
        }
      }
      .font(MTFont.body)
      .mtFieldSurface(size: size, isFocused: isPicking)
      .popover(isPresented: $isPicking) {
        MTDatePicker(
          title: label, value: $value, granularity: granularity, includesTime: includesTime,
          timeZone: timeZone
        )
        .presentationCompactAdaptation(.popover)
      }
    }
  }

  private var dateText: String? {
    guard !value.isEmpty else { return nil }
    guard let date else { return value }
    return MTDateText.display(date, granularity: granularity)
  }

  private var placeholder: String {
    switch granularity {
    case .day: "Select date"
    case .month: "Select month"
    case .year: "Select year"
    }
  }

  private var accessibilityValue: String {
    guard let dateText else { return "Not set" }
    if includesTime, let date { return "\(dateText), \(MTDateText.displayTime(date))" }
    return dateText
  }
}

private struct MTDatePicker: View {
  let title: String
  @Binding var value: String
  let granularity: MTDateGranularity
  let includesTime: Bool
  let timeZone: TimeZone
  @State private var date: Date
  @Environment(\.dismiss) private var dismiss

  init(
    title: String, value: Binding<String>, granularity: MTDateGranularity, includesTime: Bool,
    timeZone: TimeZone
  ) {
    self.title = title
    _value = value
    self.granularity = granularity
    self.includesTime = includesTime
    self.timeZone = timeZone
    let initial =
      MTDateText.date(value.wrappedValue, granularity: granularity, includesTime: includesTime)
      ?? Self.today(in: timeZone, includesTime: includesTime)
    _date = State(initialValue: initial)
  }

  var body: some View {
    VStack(spacing: 0) {
      Group {
        switch granularity {
        case .day:
          DatePicker(
            title, selection: $date,
            displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
          )
          .datePickerStyle(.graphical)
          .frame(minWidth: 320)
        case .month:
          HStack(spacing: 0) {
            wheel("Month", component: .month, values: Array(1...12)) {
              MTDateText.calendar.monthSymbols[$0 - 1]
            }
            wheel("Year", component: .year, values: years) { String($0) }
          }
          .frame(width: 320)
        case .year:
          wheel("Year", component: .year, values: years) { String($0) }.frame(width: 240)
        }
      }
      .environment(\.timeZone, .gmt)
      .environment(\.calendar, MTDateText.calendar)
      .tint(MTColor.accent)
      .padding(.horizontal, MTSpacing.s3)
      .padding(.top, MTSpacing.s2)
      Divider().overlay(MTColor.border)
      HStack {
        Text(title).font(MTFont.caption).foregroundStyle(MTColor.inkMuted).lineLimit(1)
        Spacer()
        Button("Done") {
          commit()
          dismiss()
        }
        .mtButtonStyle(.primary, size: .small)
        .accessibilityIdentifier("date-picker-done")
      }
      .padding(MTSpacing.s3)
    }
    .background(MTColor.surfaceRaised)
    .onChange(of: date) { commit() }
  }

  private var years: [Int] {
    let current = MTDateText.calendar.component(.year, from: MTDateText.now(in: timeZone))
    let selected = MTDateText.calendar.component(.year, from: date)
    return Array(min(1800, selected)...max(current + 50, selected))
  }

  private func wheel(
    _ label: String, component: Calendar.Component, values: [Int],
    title: @escaping (Int) -> String
  ) -> some View {
    Picker(
      label,
      selection: Binding(
        get: { MTDateText.calendar.component(component, from: date) },
        set: { newValue in
          var parts = MTDateText.calendar.dateComponents([.year, .month], from: date)
          parts.setValue(newValue, for: component)
          parts.day = 1
          if let next = MTDateText.calendar.date(from: parts) { date = next }
        })
    ) {
      ForEach(values, id: \.self) { Text(title($0)).tag($0) }
    }
    .pickerStyle(.wheel)
    .frame(maxWidth: .infinity)
    .clipped()
  }

  private func commit() {
    value = MTDateText.text(date, granularity: granularity, includesTime: includesTime)
  }

  private static func today(in timeZone: TimeZone, includesTime: Bool) -> Date {
    let now = MTDateText.now(in: timeZone)
    let calendar = MTDateText.calendar
    let parts = calendar.dateComponents(
      includesTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day], from: now)
    return calendar.date(from: parts) ?? now
  }
}
