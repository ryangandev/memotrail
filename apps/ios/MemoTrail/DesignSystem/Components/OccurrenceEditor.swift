import SwiftUI

/// Edits when something happened with the same Date types, fields, and guidance as the Web
/// OccurrenceEditor. With `defaultTimezone` from Settings, the time zone appears only for
/// exact times and says whether the Entry overrides the default.
struct OccurrenceEditor: View {
  @Binding var value: OccurrenceDraft
  var span = false
  var point = false
  var defaultTimezone: String?
  @State private var showsDescription: Bool

  init(
    value: Binding<OccurrenceDraft>, span: Bool = false, point: Bool = false,
    defaultTimezone: String? = nil
  ) {
    _value = value
    self.span = span
    self.point = point
    self.defaultTimezone = defaultTimezone
    _showsDescription = State(initialValue: !value.wrappedValue.label.isEmpty)
  }

  private var precision: TimelineDatePrecision { value.precision }
  private var bounded: Bool {
    !point && (span || [.range, .approximate, .age].contains(precision))
  }
  private var descriptionRequired: Bool { [.age, .approximate].contains(precision) }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      MTFieldGrid {
        MTSelectField(
          label: "Date type",
          selection: Binding(get: { value.precision }, set: { value.changePrecision(to: $0) }),
          options: precisionOptions, title: \.displayName, isRequired: true)
        if let defaultTimezone {
          if precision == .exact {
            MTTimeZoneField(
              label: "Time zone", selection: $value.timezone, referenceDate: value.start,
              note: value.timezone == defaultTimezone ? "Default from Settings" : "Entry override")
          }
        } else {
          MTTimeZoneField(
            label: "Time zone", selection: $value.timezone, referenceDate: value.start)
        }
      }
      if precision != .unknown {
        VStack(alignment: .leading, spacing: MTSpacing.s1) {
          MTFieldGrid {
            MTDateField(
              label: startLabel, value: $value.start, granularity: granularity,
              includesTime: precision == .exact,
              isRequired: !descriptionRequired, timeZone: timeZone
            )
            .id("start-\(precision.rawValue)")
            if bounded, value.endMode != .present {
              MTDateField(
                label: "End date", value: $value.end, granularity: granularity,
                includesTime: precision == .exact, timeZone: timeZone
              )
              .id("end-\(precision.rawValue)")
            }
          }
          if bounded {
            MTCheckbox(
              title: "Present", detail: "This period is still ongoing",
              isOn: Binding(
                get: { value.endMode == .present },
                set: { isOn in
                  value.endMode = isOn ? .present : .date
                  if isOn { value.end = "" }
                }))
          }
        }
      }
      if !descriptionRequired {
        MTCheckbox(
          title: "Add date description",
          isOn: Binding(
            get: { showsDescription || !value.label.isEmpty },
            set: { isOn in
              showsDescription = isOn
              if !isOn { value.label = "" }
            }))
      }
      if descriptionRequired || showsDescription || !value.label.isEmpty {
        MTTextField(
          label: "Date description", text: $value.label, prompt: descriptionPrompt,
          isRequired: descriptionRequired, maxLength: 200)
      }
      if let help = helpText {
        Text(help)
          .font(MTFont.caption)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var precisionOptions: [TimelineDatePrecision] {
    point && precision != .range
      ? TimelineDatePrecision.allCases.filter { $0 != .range } : TimelineDatePrecision.allCases
  }

  private var granularity: MTDateFieldGranularity {
    switch precision {
    case .year: .year
    case .month: .month
    default: .day
    }
  }

  private var timeZone: TimeZone { TimeZone(identifier: value.timezone) ?? .current }

  private var startLabel: String {
    descriptionRequired || bounded ? "Start date" : "Occurred"
  }

  private var helpText: String? {
    switch precision {
    case .exact:
      "Choose both a calendar date and a local time. Daylight-saving changes use the selected time zone."
    case .age, .approximate:
      "Describe what you remember. A start date can add calendar context, and no birth date is inferred."
    case .range: nil
    case .unknown: "No occurred date will be stored. Creation time is kept separately."
    default:
      "Only the selected date type is shown. Unknown days or months are not presented as facts."
    }
  }

  private var descriptionPrompt: String {
    switch precision {
    case .exact: "Context, e.g. just before sunrise"
    case .day: "Context, e.g. my first day at the new job"
    case .month: "Context, e.g. early September"
    case .year: "Context, e.g. the year I moved away"
    case .approximate: "e.g. summer before college"
    case .age: "e.g. age 17 or ages 17 to 19"
    case .range: "Context, e.g. my years in Philadelphia"
    case .unknown: "Anything you remember, e.g. sometime in childhood"
    }
  }
}
