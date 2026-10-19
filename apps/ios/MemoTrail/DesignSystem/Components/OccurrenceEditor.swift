import SwiftUI

/// Edits when something happened like the Web OccurrenceEditor: how precisely the date is known
/// (Day, Month, Year, or Not sure), the date itself, and toggles to add a time, an end date, or
/// a description. A Chapter (`span`) always has an end date or Present. With `defaultTimezone`
/// from Settings, an exact time in that zone names it as text with a Change action; a date
/// without a time has no zone to choose. A `point` date never ends, as in a capture.
struct OccurrenceEditor: View {
  @Binding var value: OccurrenceDraft
  var span = false
  var point = false
  var defaultTimezone: String?
  @State private var showsDescription: Bool
  /// Not sure keeps an age as an age, like the Web editor's first precision.
  @State private var unsurePrecision: DatePrecision
  @State private var isChangingTimezone = false
  /// Change opens the time zone list at once, once.
  @State private var opensTimezoneList = false

  init(
    value: Binding<OccurrenceDraft>, span: Bool = false, point: Bool = false,
    defaultTimezone: String? = nil
  ) {
    _value = value
    self.span = span
    self.point = point
    self.defaultTimezone = defaultTimezone
    _showsDescription = State(initialValue: !value.wrappedValue.label.isEmpty)
    _unsurePrecision = State(
      initialValue: value.wrappedValue.precision == .age ? .age : .approximate)
  }

  private var precision: DatePrecision { value.shownPrecision }
  private var segment: DateSegment { value.segment }
  private var exact: Bool { precision == .exact }
  private var unsure: Bool { segment == .unsure }
  private var endAdded: Bool { !point && value.endAdded(span: span) }
  private var presentShown: Bool { !point && value.presentShown(span: span) }
  private var endMode: OccurrenceDraft.EndMode { value.shownEndMode(span: span) }
  private var timeToggleShown: Bool { value.timeToggleShown(span: span) }
  private var endToggleShown: Bool { !point && value.endToggleShown(span: span) }
  private var timezoneIsDefault: Bool { value.timezone == defaultTimezone }
  private var timezoneQuiet: Bool { exact && timezoneIsDefault && !isChangingTimezone }
  private var timezoneShown: Bool { defaultTimezone == nil || (exact && !timezoneQuiet) }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        MTFieldLabel(title: "Date")
        Picker("Date", selection: segmentSelection) {
          ForEach(DateSegment.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("occurrence-precision")
      }
      MTFieldGrid {
        MTDateField(
          label: startLabel, value: field(\.start), granularity: granularity,
          includesTime: exact, timeZone: timeZone
        )
        .id("start-\(segment.rawValue)-\(exact)")
        if endAdded, endMode != .present {
          MTDateField(
            label: "End date", value: field(\.end), granularity: granularity,
            includesTime: exact, timeZone: timeZone
          )
          .id("end-\(segment.rawValue)-\(exact)")
        }
        if timezoneShown {
          MTTimeZoneField(
            label: "Time zone", selection: field(\.timezone), referenceDate: value.start,
            note: defaultTimezone == nil
              ? nil : timezoneIsDefault ? "Default from Settings" : "Entry override",
            startsChoosing: opensTimezoneList
          )
          .onAppear { opensTimezoneList = false }
        }
        if timezoneQuiet { timezoneSummary }
      }
      toggles
      if unsure || showsDescription || !value.label.isEmpty {
        MTTextField(
          label: "Date description", text: field(\.label), prompt: descriptionPrompt,
          isRequired: unsure, maxLength: 200)
      }
      Text(helpText)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  @ViewBuilder private var toggles: some View {
    VStack(alignment: .leading, spacing: 0) {
      if timeToggleShown {
        MTCheckbox(
          title: "Add time",
          isOn: Binding(get: { exact }, set: { value.toggleTime($0, span: span) }), size: .small)
      }
      if endToggleShown {
        MTCheckbox(
          title: "Add end date",
          isOn: Binding(get: { endAdded }, set: { value.toggleEnd($0) }), size: .small)
      }
      if presentShown {
        MTCheckbox(
          title: "Present", detail: "Still going on",
          isOn: Binding(get: { endMode == .present }, set: { value.setPresent($0) }), size: .small)
      }
      if !unsure {
        MTCheckbox(
          title: "Add date description",
          isOn: Binding(
            get: { showsDescription || !value.label.isEmpty },
            set: { isOn in
              showsDescription = isOn
              if !isOn { value.edit { $0.label = "" } }
            }), size: .small)
      }
    }
  }

  /// An exact time in the Settings time zone, named as text so most edits never meet the
  /// time zone list.
  private var timezoneSummary: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: "Time zone", note: "Default from Settings")
      HStack(spacing: MTSpacing.s3) {
        Text(TimeZoneOptions.optionLabel(value.timezone, reference: value.start))
          .font(MTFont.body)
          .foregroundStyle(MTColor.ink)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        Button("Change") {
          isChangingTimezone = true
          opensTimezoneList = true
        }
          .mtButtonStyle(.secondary, size: .small)
          .accessibilityLabel("Change time zone")
      }
      .frame(minHeight: MTSize.Field.medium)
    }
    .accessibilityElement(children: .contain)
  }

  private var segmentSelection: Binding<DateSegment> {
    Binding(
      get: { segment },
      set: { value.changeSegment(to: $0, span: span, unsurePrecision: unsurePrecision) })
  }

  /// A field of the draft; every edit stores the shown precision, like Web's `change`.
  private func field(_ keyPath: WritableKeyPath<OccurrenceDraft, String>) -> Binding<String> {
    Binding(
      get: { value[keyPath: keyPath] },
      set: { text in
        guard text != value[keyPath: keyPath] else { return }
        value.edit { $0[keyPath: keyPath] = text }
      })
  }

  private var granularity: MTDateFieldGranularity {
    switch segment {
    case .year: .year
    case .month: .month
    case .day, .unsure: .day
    }
  }

  private var timeZone: TimeZone { TimeZone(identifier: value.timezone) ?? .current }

  private var startLabel: String {
    if endAdded { return "Start date" }
    return unsure ? "Roughly when" : "Occurred"
  }

  private var helpText: String {
    switch precision {
    case .exact: "Daylight-saving changes use the selected time zone."
    case .age, .approximate:
      "Describe what you remember. A rough date is optional, and no birth date is inferred."
    default: "Leave the date empty if you don't know it."
    }
  }

  private var descriptionPrompt: String {
    switch precision {
    case .exact: "Context, e.g. just before sunrise"
    case .month: "Context, e.g. early September"
    case .year: "Context, e.g. the year I moved away"
    case .approximate: "e.g. summer before college"
    case .age: "e.g. age 17 or ages 17 to 19"
    case .range: "Context, e.g. my years in Philadelphia"
    default: "Context, e.g. my first day at the new job"
    }
  }
}
