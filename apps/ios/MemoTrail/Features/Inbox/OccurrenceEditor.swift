import SwiftUI

struct OccurrenceEditor: View {
  @Binding var value: OccurrenceDraft
  var span = false
  var point = false
  var chapterGuidance: String? = nil
  @State private var showCalendar = false
  @State private var choosingEnd = false
  @State private var calendarDate = Date()

  var body: some View {
    Section {
      Picker("Date precision", selection: $value.precision) {
        ForEach(TimelineDatePrecision.allCases, id: \.self) { precision in
          Text(
            precision == .exact
              ? "Exact date & time" : precision == .day ? "Day" : precision.displayName
          ).tag(precision)
        }
      }
      .onChange(of: value.precision) {
        // A precision change is an explicit replacement of the draft's calendar
        // interpretation. AI acceptance sets its description separately.
        value.start = ""
        value.end = ""
      }
      TextField("Time zone", text: $value.timezone)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
      if value.precision != .unknown {
        HStack {
          TextField(datePlaceholder, text: $value.start)
            .accessibilityLabel("Occurred")
            .textInputAutocapitalization(.never).autocorrectionDisabled()
          if ![.month, .year].contains(value.precision) {
            Button {
              chooseCalendar(end: false)
            } label: {
              Image(systemName: "calendar")
            }
            .accessibilityLabel("Choose start date")
            .buttonStyle(.borderless)
          }
        }
        if !point && (span || [.range, .approximate, .age].contains(value.precision)) {
          HStack {
            TextField(
              "End date \(datePlaceholder.replacingOccurrences(of: "Start date ", with: "")) (optional)",
              text: $value.end
            )
            .accessibilityLabel("End date (optional)")
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            if ![.month, .year].contains(value.precision) {
              Button {
                chooseCalendar(end: true)
              } label: {
                Image(systemName: "calendar")
              }
              .accessibilityLabel("Choose end date")
              .buttonStyle(.borderless)
            }
          }
        }
      }
      TextField("Date description", text: $value.label, axis: .vertical)
    } header: {
      Text("When it happened")
    } footer: {
      Text(guidance)
      if let chapterGuidance { Text(chapterGuidance) }
    }
    .sheet(isPresented: $showCalendar) {
      NavigationStack {
        DatePicker(
          "Occurred", selection: $calendarDate,
          displayedComponents: value.precision == .exact
            ? [.date, .hourAndMinute] : [.date]
        )
        .datePickerStyle(.graphical)
        .environment(\.timeZone, TimeZone(identifier: value.timezone) ?? .gmt)
        .environment(\.calendar, Calendar(identifier: .gregorian))
        .padding()
        .navigationTitle(choosingEnd ? "End date" : "Start date")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { showCalendar = false }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Use date") {
              let selected = OccurrenceDraft(
                EntryOccurrence(
                  precision: value.precision, start: calendarDate, end: nil,
                  label: nil, timezone: value.timezone)
              ).start
              if choosingEnd { value.end = selected } else { value.start = selected }
              showCalendar = false
            }
          }
        }
      }
      .presentationDetents([.large])
    }
  }

  private func chooseCalendar(end: Bool) {
    choosingEnd = end
    let text = end ? value.end : value.start
    let local = value.precision == .exact ? text : "\(text)T12:00:00"
    calendarDate = OccurrenceDraft.wallTimeToDate(local, timezone: value.timezone) ?? Date()
    showCalendar = true
  }

  private var datePlaceholder: String {
    switch value.precision {
    case .exact: "YYYY-MM-DDTHH:MM (24-hour time)"
    case .year: "YYYY"
    case .month: "YYYY-MM"
    default: "Start date YYYY-MM-DD"
    }
  }

  private var guidance: String {
    switch value.precision {
    case .exact:
      "Times use the recorded time zone. A repeated daylight-saving hour uses its earlier occurrence when edited."
    case .age, .approximate:
      "A description is enough. Calendar dates are optional; no birth date is inferred."
    case .range: "Leave the end date empty when the period continues."
    case .unknown: "No occurred date will be stored. Creation time is kept separately."
    default:
      "Only the selected precision is shown. Unknown days or months are not presented as facts."
    }
  }
}
