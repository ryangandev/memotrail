import Foundation

enum HabitTrackingMode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case check
  case measure

  var displayName: String {
    switch self {
    case .check: "Check"
    case .measure: "Measure"
    }
  }
}

enum HabitOccurrenceStatus: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
  case completed
  case skipped
  case missed

  var displayName: String { rawValue.capitalized }
}

enum HabitCalendarStatus: String, Codable, Equatable, Hashable, Sendable {
  case completed
  case skipped
  case missed
  case pending
  case upcoming
  case notScheduled = "not_scheduled"

  var displayName: String {
    switch self {
    case .notScheduled: "Not scheduled"
    default: rawValue.capitalized
    }
  }
}

enum HabitSchedule: Codable, Equatable, Hashable, Sendable {
  case daily
  case weekdays([Int])
  case weeklyTarget(Int)
  case interval(Int)

  enum Kind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case daily
    case weekdays
    case weeklyTarget = "weekly_target"
    case interval

    var displayName: String {
      switch self {
      case .daily: "Every day"
      case .weekdays: "Selected weekdays"
      case .weeklyTarget: "Times per week"
      case .interval: "Custom interval"
      }
    }
  }

  var kind: Kind {
    switch self {
    case .daily: .daily
    case .weekdays: .weekdays
    case .weeklyTarget: .weeklyTarget
    case .interval: .interval
    }
  }

  var displayLabel: String {
    switch self {
    case .daily:
      "Every day"
    case .weekdays(let weekdays):
      weekdays.sorted().compactMap(HabitWeekday.shortName).joined(separator: ", ")
    case .weeklyTarget(let target):
      "\(target) times per week"
    case .interval(let days):
      days == 1 ? "Every day" : "Every \(days) days"
    }
  }

  private enum CodingKeys: String, CodingKey {
    case everyDays = "every_days"
    case kind
    case target
    case weekdays
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let kind = try values.decode(Kind.self, forKey: .kind)

    switch kind {
    case .daily:
      self = .daily
    case .weekdays:
      self = .weekdays(try values.decode([Int].self, forKey: .weekdays))
    case .weeklyTarget:
      self = .weeklyTarget(try values.decode(Int.self, forKey: .target))
    case .interval:
      self = .interval(try values.decode(Int.self, forKey: .everyDays))
    }
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(kind, forKey: .kind)

    switch self {
    case .daily:
      break
    case .weekdays(let weekdays):
      try values.encode(weekdays.sorted(), forKey: .weekdays)
    case .weeklyTarget(let target):
      try values.encode(target, forKey: .target)
    case .interval(let days):
      try values.encode(days, forKey: .everyDays)
    }
  }
}

enum HabitWeekday {
  static let all = Array(1...7)
  private static let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

  static func shortName(_ weekday: Int) -> String? {
    guard all.contains(weekday) else { return nil }
    return names[weekday % 7]
  }
}

struct HabitOccurrence: Equatable, Hashable, Sendable {
  let id: UUID
  let revision: Int
  let status: HabitOccurrenceStatus
  let measuredValue: Double?
  let note: String?
}

struct Habit: Equatable, Hashable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let trackingMode: HabitTrackingMode
  let measurementUnit: String?
  let targetValue: Double?
  let schedule: HabitSchedule
  let startsOn: String
  let endsOn: String?
  let revision: Int
  let status: HabitCalendarStatus
  let occurrence: HabitOccurrence?
  let createdAt: Date
  let updatedAt: Date

  var measurementLabel: String? {
    guard trackingMode == .measure, let targetValue, let measurementUnit else { return nil }
    return "\(HabitNumber.format(targetValue)) \(measurementUnit)"
  }
}

struct HabitWorkspaceRow: Decodable, Equatable, Sendable {
  let habitID: UUID
  let name: String
  let trackingMode: HabitTrackingMode
  let measurementUnit: String?
  let targetValue: Double?
  let schedule: HabitSchedule
  let startsOn: String
  let endsOn: String?
  let habitRevision: Int
  let occurrenceID: UUID?
  let occurrenceRevision: Int?
  let localStatus: HabitCalendarStatus
  let measuredValue: Double?
  let note: String?
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case habitID = "habit_id"
    case name
    case trackingMode = "tracking_mode"
    case measurementUnit = "measurement_unit"
    case targetValue = "target_value"
    case schedule
    case startsOn = "starts_on"
    case endsOn = "ends_on"
    case habitRevision = "habit_revision"
    case occurrenceID = "occurrence_id"
    case occurrenceRevision = "occurrence_revision"
    case localStatus = "local_status"
    case measuredValue = "measured_value"
    case note
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }

  var habit: Habit? {
    guard !name.trimmed.isEmpty, habitRevision > 0 else { return nil }
    let occurrence: HabitOccurrence?

    if let occurrenceID, let occurrenceRevision, occurrenceRevision > 0,
      let status = HabitOccurrenceStatus(rawValue: localStatus.rawValue)
    {
      occurrence = HabitOccurrence(
        id: occurrenceID,
        revision: occurrenceRevision,
        status: status,
        measuredValue: measuredValue,
        note: note?.trimmed.nonEmpty
      )
    } else {
      occurrence = nil
    }

    return Habit(
      id: habitID,
      name: name.trimmed,
      trackingMode: trackingMode,
      measurementUnit: measurementUnit?.trimmed.nonEmpty,
      targetValue: targetValue,
      schedule: schedule,
      startsOn: startsOn,
      endsOn: endsOn,
      revision: habitRevision,
      status: localStatus,
      occurrence: occurrence,
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}

enum HabitsWorkspace {
  static func habits(from rows: [HabitWorkspaceRow]) -> [Habit] {
    rows.compactMap(\.habit).sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }
}

struct HabitCalendarDay: Decodable, Equatable, Hashable, Identifiable, Sendable {
  let localDate: String
  let isScheduled: Bool
  let status: HabitCalendarStatus
  let measuredValue: Double?
  let note: String?
  let occurrenceID: UUID?
  let occurrenceRevision: Int?

  var id: String { localDate }

  enum CodingKeys: String, CodingKey {
    case localDate = "local_date"
    case isScheduled = "is_scheduled"
    case status
    case measuredValue = "measured_value"
    case note
    case occurrenceID = "occurrence_id"
    case occurrenceRevision = "occurrence_revision"
  }
}

struct HabitYearStats: Equatable, Sendable {
  let completed: Int
  let completionRate: Double?
  let currentStreak: Int
  let longestStreak: Int
  let missed: Int
  let skipped: Int

  static func calculate(days: [HabitCalendarDay], asOfDate: String) -> HabitYearStats {
    let observed = days.filter { $0.localDate <= asOfDate }.sorted { $0.localDate < $1.localDate }
    var completed = 0
    var currentStreak = 0
    var longestStreak = 0
    var missed = 0
    var skipped = 0

    for day in observed {
      switch day.status {
      case .completed:
        completed += 1
        currentStreak += 1
        longestStreak = max(longestStreak, currentStreak)
      case .missed:
        missed += 1
        currentStreak = 0
      case .skipped:
        skipped += 1
      case .pending, .upcoming, .notScheduled:
        break
      }
    }

    return HabitYearStats(
      completed: completed,
      completionRate: completed + missed == 0
        ? nil : Double(completed) / Double(completed + missed),
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      missed: missed,
      skipped: skipped
    )
  }
}

struct HabitDefinitionInput: Equatable, Sendable {
  static let nameLimit = 120
  static let unitLimit = 40

  let habitID: UUID?
  let expectedRevision: Int?
  let name: String
  let trackingMode: HabitTrackingMode
  let measurementUnit: String?
  let targetValue: Double?
  let schedule: HabitSchedule
  let startsOn: String
  let endsOn: String?

  static func validate(
    habitID: UUID?,
    expectedRevision: Int?,
    name: String,
    trackingMode: HabitTrackingMode,
    measurementUnit: String,
    targetValue: Double?,
    schedule: HabitSchedule,
    startsOn: String,
    endsOn: String?
  ) throws -> HabitDefinitionInput {
    let name = name.trimmed
    let measurementUnit = measurementUnit.trimmed.nonEmpty
    let endsOn = endsOn?.trimmed.nonEmpty

    guard !name.isEmpty else { throw HabitInputError.nameRequired }
    guard name.count <= nameLimit else { throw HabitInputError.nameTooLong }
    guard HabitLocalDate.isValid(startsOn), endsOn.map(HabitLocalDate.isValid) ?? true else {
      throw HabitInputError.invalidDate
    }
    guard endsOn.map({ $0 >= startsOn }) ?? true else { throw HabitInputError.reversedDates }
    guard schedule.isValid else { throw HabitInputError.invalidSchedule }
    guard
      (habitID == nil && expectedRevision == nil)
        || (habitID != nil && (expectedRevision ?? 0) > 0)
    else {
      throw HabitInputError.invalidRevision
    }

    switch trackingMode {
    case .check:
      guard measurementUnit == nil, targetValue == nil else {
        throw HabitInputError.checkCannotMeasure
      }
    case .measure:
      guard let measurementUnit, measurementUnit.count <= unitLimit,
        let targetValue, targetValue.isFinite, targetValue > 0
      else {
        throw HabitInputError.invalidMeasurement
      }
    }

    return HabitDefinitionInput(
      habitID: habitID,
      expectedRevision: expectedRevision,
      name: name,
      trackingMode: trackingMode,
      measurementUnit: trackingMode == .measure ? measurementUnit : nil,
      targetValue: trackingMode == .measure ? targetValue : nil,
      schedule: schedule,
      startsOn: startsOn,
      endsOn: endsOn
    )
  }
}

struct HabitOccurrenceInput: Equatable, Sendable {
  static let noteLimit = 2_000

  let habitID: UUID
  let localDate: String
  let status: HabitOccurrenceStatus
  let measuredValue: Double?
  let note: String?
  let expectedRevision: Int?

  static func validate(
    habit: Habit,
    localDate: String,
    status: HabitOccurrenceStatus,
    measuredValue: Double?,
    note: String,
    expectedRevision: Int?
  ) throws -> HabitOccurrenceInput {
    let note = note.trimmed.nonEmpty

    guard HabitLocalDate.isValid(localDate) else { throw HabitInputError.invalidDate }
    guard localDate >= habit.startsOn, habit.endsOn.map({ localDate <= $0 }) ?? true else {
      throw HabitInputError.occurrenceOutsideDates
    }
    guard note?.count ?? 0 <= noteLimit else { throw HabitInputError.noteTooLong }
    guard expectedRevision.map({ $0 > 0 }) ?? true else { throw HabitInputError.invalidRevision }

    if habit.trackingMode == .check, measuredValue != nil {
      throw HabitInputError.checkCannotMeasure
    }
    if habit.trackingMode == .measure, status == .completed {
      guard let measuredValue, measuredValue.isFinite, measuredValue >= 0 else {
        throw HabitInputError.measurementRequired
      }
    } else if measuredValue != nil {
      throw HabitInputError.inactiveCannotMeasure
    }

    return HabitOccurrenceInput(
      habitID: habit.id,
      localDate: localDate,
      status: status,
      measuredValue: measuredValue,
      note: note,
      expectedRevision: expectedRevision
    )
  }
}

extension HabitSchedule {
  var isValid: Bool {
    switch self {
    case .daily:
      true
    case .weekdays(let weekdays):
      !weekdays.isEmpty && Set(weekdays).count == weekdays.count
        && weekdays.allSatisfy((1...7).contains)
    case .weeklyTarget(let target):
      (1...7).contains(target)
    case .interval(let days):
      (1...365).contains(days)
    }
  }
}

struct SaveHabitParameters: Encodable, Equatable, Sendable {
  let input: HabitDefinitionInput

  private enum CodingKeys: String, CodingKey {
    case endsOn = "p_ends_on"
    case expectedRevision = "p_expected_revision"
    case habitID = "p_habit_id"
    case measurementUnit = "p_measurement_unit"
    case name = "p_name"
    case schedule = "p_schedule"
    case startsOn = "p_starts_on"
    case targetValue = "p_target_value"
    case trackingMode = "p_tracking_mode"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.name, forKey: .name)
    try values.encode(input.trackingMode, forKey: .trackingMode)
    try values.encode(input.schedule, forKey: .schedule)
    try values.encode(input.startsOn, forKey: .startsOn)
    try values.encodeIfPresent(input.habitID, forKey: .habitID)
    if input.habitID == nil { try values.encodeNil(forKey: .habitID) }
    try values.encodeIfPresent(input.expectedRevision, forKey: .expectedRevision)
    if input.expectedRevision == nil { try values.encodeNil(forKey: .expectedRevision) }
    try values.encodeIfPresent(input.measurementUnit, forKey: .measurementUnit)
    if input.measurementUnit == nil { try values.encodeNil(forKey: .measurementUnit) }
    try values.encodeIfPresent(input.targetValue, forKey: .targetValue)
    if input.targetValue == nil { try values.encodeNil(forKey: .targetValue) }
    try values.encodeIfPresent(input.endsOn, forKey: .endsOn)
    if input.endsOn == nil { try values.encodeNil(forKey: .endsOn) }
  }
}

struct RecordHabitOccurrenceParameters: Encodable, Equatable, Sendable {
  let input: HabitOccurrenceInput

  private enum CodingKeys: String, CodingKey {
    case entryID = "p_entry_id"
    case expectedRevision = "p_expected_revision"
    case habitID = "p_habit_id"
    case localDate = "p_local_date"
    case measuredValue = "p_measured_value"
    case note = "p_note"
    case status = "p_status"
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(input.habitID, forKey: .habitID)
    try values.encode(input.localDate, forKey: .localDate)
    try values.encode(input.status, forKey: .status)
    try values.encodeNil(forKey: .entryID)
    try values.encodeIfPresent(input.measuredValue, forKey: .measuredValue)
    if input.measuredValue == nil { try values.encodeNil(forKey: .measuredValue) }
    try values.encodeIfPresent(input.note, forKey: .note)
    if input.note == nil { try values.encodeNil(forKey: .note) }
    try values.encodeIfPresent(input.expectedRevision, forKey: .expectedRevision)
    if input.expectedRevision == nil { try values.encodeNil(forKey: .expectedRevision) }
  }
}

struct HabitsWorkspaceParameters: Encodable, Sendable {
  let localDate: String

  enum CodingKeys: String, CodingKey {
    case localDate = "p_local_date"
  }
}

struct HabitYearCalendarParameters: Encodable, Sendable {
  let habitID: UUID
  let year: Int
  let asOfDate: String

  enum CodingKeys: String, CodingKey {
    case habitID = "p_habit_id"
    case year = "p_year"
    case asOfDate = "p_as_of_date"
  }
}

struct TrashHabitParameters: Encodable, Sendable {
  let habitID: UUID
  let expectedRevision: Int

  enum CodingKeys: String, CodingKey {
    case habitID = "p_habit_id"
    case expectedRevision = "p_expected_revision"
  }
}

struct SavedHabit: Decodable, Sendable {
  let habitID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case habitID = "habit_id"
    case revision
  }
}

struct SavedHabitOccurrence: Decodable, Sendable {
  let occurrenceID: UUID
  let revision: Int

  enum CodingKeys: String, CodingKey {
    case occurrenceID = "occurrence_id"
    case revision
  }
}

enum HabitInputError: LocalizedError, Equatable {
  case checkCannotMeasure
  case inactiveCannotMeasure
  case invalidDate
  case invalidMeasurement
  case invalidRevision
  case invalidSchedule
  case measurementRequired
  case nameRequired
  case nameTooLong
  case noteTooLong
  case occurrenceOutsideDates
  case reversedDates

  var errorDescription: String? {
    switch self {
    case .checkCannotMeasure: "Check Habits cannot include a measurement."
    case .inactiveCannotMeasure: "Only completed check-ins can include a measurement."
    case .invalidDate: "Choose a valid date."
    case .invalidMeasurement: "Add a positive target and a unit up to 40 characters."
    case .invalidRevision: "This Habit version is invalid. Refresh and try again."
    case .invalidSchedule: "Choose a valid Habit schedule."
    case .measurementRequired: "Add a non-negative measurement for this completion."
    case .nameRequired: "Add a name for this Habit."
    case .nameTooLong: "Habit names can be up to \(HabitDefinitionInput.nameLimit) characters."
    case .noteTooLong: "Check-in notes can be up to \(HabitOccurrenceInput.noteLimit) characters."
    case .occurrenceOutsideDates: "This date is outside the Habit's active range."
    case .reversedDates: "The end date must be on or after the start date."
    }
  }
}

enum HabitLocalDate {
  private static let expression = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")

  static func string(from date: Date, timeZone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  static func date(from value: String, timeZone: TimeZone = .current) -> Date? {
    guard isValid(value) else { return nil }
    let values = value.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2]))
  }

  static func isValid(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..., in: value)
    guard expression.firstMatch(in: value, range: range) != nil else { return false }
    let values = value.split(separator: "-").compactMap { Int($0) }
    guard values.count == 3 else { return false }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    guard
      let date = calendar.date(
        from: DateComponents(year: values[0], month: values[1], day: values[2]))
    else {
      return false
    }
    let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
    return roundTrip.year == values[0] && roundTrip.month == values[1] && roundTrip.day == values[2]
  }
}

enum HabitNumber {
  static func format(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value).trimmedZeros
  }
}

extension String {
  fileprivate var trimmedZeros: String {
    var value = self
    while value.last == "0" { value.removeLast() }
    if value.last == "." { value.removeLast() }
    return value
  }
}
