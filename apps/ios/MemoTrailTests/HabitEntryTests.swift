import XCTest

@testable import MemoTrail

final class HabitEntryTests: XCTestCase {
  func testWorkspaceDecodesCheckAndMeasureHabits() throws {
    let json = """
      [
        {
          "habit_id": "10000000-0000-4000-8000-000000000001",
          "name": "Take supplements",
          "tracking_mode": "check",
          "measurement_unit": null,
          "target_value": null,
          "schedule": {"kind": "daily"},
          "starts_on": "2026-09-01",
          "ends_on": null,
          "habit_revision": 2,
          "occurrence_id": "20000000-0000-4000-8000-000000000001",
          "occurrence_revision": 3,
          "local_status": "skipped",
          "measured_value": null,
          "note": "Travel day",
          "created_at": "2026-09-01T10:00:00Z",
          "updated_at": "2026-09-02T10:00:00Z"
        },
        {
          "habit_id": "10000000-0000-4000-8000-000000000002",
          "name": "Read pages",
          "tracking_mode": "measure",
          "measurement_unit": "pages",
          "target_value": 20,
          "schedule": {"kind": "weekdays", "weekdays": [1, 3, 5]},
          "starts_on": "2026-09-01",
          "ends_on": "2027-09-01",
          "habit_revision": 1,
          "occurrence_id": null,
          "occurrence_revision": null,
          "local_status": "pending",
          "measured_value": null,
          "note": null,
          "created_at": "2026-09-01T10:00:00Z",
          "updated_at": "2026-09-01T10:00:00Z"
        }
      ]
      """
    let rows = try decoder.decode([HabitWorkspaceRow].self, from: Data(json.utf8))
    let habits = HabitsWorkspace.habits(from: rows)

    XCTAssertEqual(habits.map(\.name), ["Read pages", "Take supplements"])
    XCTAssertEqual(habits[0].measurementLabel, "20 pages")
    XCTAssertEqual(habits[0].schedule, .weekdays([1, 3, 5]))
    XCTAssertEqual(habits[1].occurrence?.revision, 3)
    XCTAssertEqual(habits[1].occurrence?.status, .skipped)
  }

  func testAllSchedulesRoundTripThroughJSON() throws {
    let schedules: [HabitSchedule] = [
      .daily,
      .weekdays([1, 4, 7]),
      .weeklyTarget(4),
      .interval(12),
    ]

    for schedule in schedules {
      let data = try JSONEncoder().encode(schedule)
      XCTAssertEqual(try JSONDecoder().decode(HabitSchedule.self, from: data), schedule)
    }
  }

  func testScheduleLabelsAreHumanReadable() {
    XCTAssertEqual(HabitSchedule.daily.displayLabel, "Every day")
    XCTAssertEqual(HabitSchedule.weekdays([1, 3, 7]).displayLabel, "Mon, Wed, Sun")
    XCTAssertEqual(HabitSchedule.weeklyTarget(4).displayLabel, "4 times per week")
    XCTAssertEqual(HabitSchedule.interval(2).displayLabel, "Every 2 days")
  }

  func testDefinitionValidationNormalizesMeasureHabit() throws {
    let input = try makeDefinition(
      name: "  Drink water  ",
      trackingMode: .measure,
      measurementUnit: "  glasses  ",
      targetValue: 8,
      schedule: .weeklyTarget(5)
    )

    XCTAssertEqual(input.name, "Drink water")
    XCTAssertEqual(input.measurementUnit, "glasses")
    XCTAssertEqual(input.targetValue, 8)
    XCTAssertEqual(input.schedule, .weeklyTarget(5))
  }

  func testDefinitionValidationRejectsInvalidMeasurementAndSchedule() {
    XCTAssertThrowsError(
      try makeDefinition(
        trackingMode: .measure,
        measurementUnit: "",
        targetValue: 0
      )
    ) { error in
      XCTAssertEqual(error as? HabitInputError, .invalidMeasurement)
    }
    XCTAssertThrowsError(try makeDefinition(schedule: .weekdays([]))) { error in
      XCTAssertEqual(error as? HabitInputError, .invalidSchedule)
    }
    XCTAssertThrowsError(try makeDefinition(schedule: .interval(366))) { error in
      XCTAssertEqual(error as? HabitInputError, .invalidSchedule)
    }
  }

  func testDefinitionValidationRequiresMatchingIdentityAndRevision() {
    XCTAssertThrowsError(try makeDefinition(expectedRevision: 2)) { error in
      XCTAssertEqual(error as? HabitInputError, .invalidRevision)
    }
    XCTAssertNoThrow(
      try makeDefinition(
        habitID: UUID(uuidString: "10000000-0000-4000-8000-000000000001"),
        expectedRevision: 2
      )
    )
  }

  func testDefinitionValidationRejectsReversedDates() {
    XCTAssertThrowsError(try makeDefinition(startsOn: "2026-09-02", endsOn: "2026-09-01")) {
      error in
      XCTAssertEqual(error as? HabitInputError, .reversedDates)
    }
  }

  func testOccurrenceValidationCoversCheckAndMeasureRules() throws {
    let check = makeHabit(trackingMode: .check)
    let checked = try HabitOccurrenceInput.validate(
      habit: check,
      localDate: "2026-09-02",
      status: .completed,
      measuredValue: nil,
      note: "  With breakfast  ",
      expectedRevision: nil
    )
    XCTAssertEqual(checked.note, "With breakfast")

    let measure = makeHabit(trackingMode: .measure)
    XCTAssertThrowsError(
      try HabitOccurrenceInput.validate(
        habit: measure,
        localDate: "2026-09-02",
        status: .completed,
        measuredValue: nil,
        note: "",
        expectedRevision: nil
      )
    ) { error in
      XCTAssertEqual(error as? HabitInputError, .measurementRequired)
    }
    XCTAssertThrowsError(
      try HabitOccurrenceInput.validate(
        habit: measure,
        localDate: "2026-09-02",
        status: .skipped,
        measuredValue: 5,
        note: "",
        expectedRevision: nil
      )
    ) { error in
      XCTAssertEqual(error as? HabitInputError, .inactiveCannotMeasure)
    }
  }

  func testSaveParametersEncodeExplicitNulls() throws {
    let input = try makeDefinition()
    let data = try JSONEncoder().encode(SaveHabitParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_habit_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_measurement_unit"] is NSNull)
    XCTAssertTrue(json["p_target_value"] is NSNull)
    XCTAssertTrue(json["p_ends_on"] is NSNull)
    XCTAssertEqual((json["p_schedule"] as? [String: Any])?["kind"] as? String, "daily")
  }

  func testOccurrenceParametersEncodeExplicitNulls() throws {
    let input = try HabitOccurrenceInput.validate(
      habit: makeHabit(trackingMode: .check),
      localDate: "2026-09-02",
      status: .completed,
      measuredValue: nil,
      note: "",
      expectedRevision: nil
    )
    let data = try JSONEncoder().encode(RecordHabitOccurrenceParameters(input: input))
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertTrue(json["p_entry_id"] is NSNull)
    XCTAssertTrue(json["p_expected_revision"] is NSNull)
    XCTAssertTrue(json["p_measured_value"] is NSNull)
    XCTAssertTrue(json["p_note"] is NSNull)
  }

  func testOccurrenceLinkRoundTripsAndSerializesExplicitSelection() throws {
    let entryID = UUID()
    let json = """
      {"local_date":"2026-09-02","is_scheduled":true,"status":"completed","entry_id":"\(entryID)","occurrence_revision":2}
      """
    let day = try JSONDecoder().decode(HabitCalendarDay.self, from: Data(json.utf8))
    XCTAssertEqual(day.entryID, entryID)
    let input = try HabitOccurrenceInput.validate(
      habit: makeHabit(trackingMode: .check), localDate: day.localDate, status: .completed,
      measuredValue: nil, note: "Linked", expectedRevision: 2, entryID: entryID)
    let data = try JSONEncoder().encode(RecordHabitOccurrenceParameters(input: input))
    let parameters = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(parameters["p_entry_id"] as? String, entryID.uuidString)
  }

  func testEmptyHistoricalDayDoesNotBorrowCurrentCheckInContext() {
    let current = HabitOccurrence(
      id: UUID(), revision: 8, status: .skipped, measuredValue: 5, note: "Today", entryID: UUID())
    let historical = HabitCheckInContext(
      day: calendarDay("2026-09-01", .missed), occurrence: current)
    XCTAssertNil(historical.revision)
    XCTAssertNil(historical.entryID)
    XCTAssertNil(historical.note)
    XCTAssertNil(historical.measuredValue)
    XCTAssertEqual(historical.status, .missed)
    let today = HabitCheckInContext(day: nil, occurrence: current)
    XCTAssertEqual(today.revision, 8)
    XCTAssertEqual(today.entryID, current.entryID)
    XCTAssertEqual(today.note, "Today")
  }

  func testHabitEntryChoicesDecodeTrashAndUnlabeledWriting() throws {
    let json = """
      {"items":[],"total_count":0,"selected":{"id":"10000000-0000-4000-8000-000000000001","title":null,"excerpt":"Journal context","is_deleted":true}}
      """
    let value = try JSONDecoder().decode(HabitEntryChoices.self, from: Data(json.utf8))
    XCTAssertEqual(value.selected?.displayTitle, "Journal context")
    XCTAssertEqual(value.selected?.isDeleted, true)
    XCTAssertTrue(value.items.isEmpty)
  }

  func testYearStatsKeepSkipsNeutralAndMissesBreakStreaks() {
    let days = [
      calendarDay("2026-09-01", .completed),
      calendarDay("2026-09-02", .skipped),
      calendarDay("2026-09-03", .completed),
      calendarDay("2026-09-04", .missed),
      calendarDay("2026-09-05", .completed),
      calendarDay("2026-09-06", .upcoming),
    ]

    XCTAssertEqual(
      HabitYearStats.calculate(days: days, asOfDate: "2026-09-05"),
      HabitYearStats(
        completed: 3,
        completionRate: 0.75,
        currentStreak: 1,
        longestStreak: 2,
        missed: 1,
        skipped: 1
      )
    )
  }

  func testBreakdownGroupsLeapDayAndAllTiedMissedWeekdays() {
    let summary = HabitBreakdown.calculate(
      days: [
        calendarDay("2024-02-26", .completed), calendarDay("2024-02-27", .skipped),
        calendarDay("2024-02-28", .missed), calendarDay("2024-02-29", .completed),
        calendarDay("2024-03-01", .missed), calendarDay("2024-03-02", .missed),
        calendarDay("2024-03-03", .pending),
      ], asOfDate: "2024-03-03", year: 2024)
    XCTAssertEqual(summary.months.count, 12)
    XCTAssertEqual(summary.weekdays.count, 7)
    XCTAssertEqual(
      summary.months[1], HabitBreakdownRow(label: "Feb", completed: 2, missed: 1, skipped: 1))
    XCTAssertEqual(summary.months[1].completionRate, 2.0 / 3.0)
    XCTAssertEqual(summary.months[2].missed, 2)
    XCTAssertEqual(summary.months[2].completionRate, 0)
    XCTAssertEqual(summary.weekdays[0].completed, 1)
    XCTAssertEqual(summary.weekdays[3].completed, 1)
    XCTAssertEqual(summary.mostMissedWeekdays, ["Wednesday", "Friday", "Saturday"])
    XCTAssertEqual(summary.mostMisses, 1)
  }

  func testBreakdownExcludesFutureOtherYearInvalidAndUnassignedDates() {
    let summary = HabitBreakdown.calculate(
      days: [
        calendarDay("2023-12-31", .missed), calendarDay("2024-01-01", .completed),
        calendarDay("2024-01-02", .completed), calendarDay("2024-02-30", .missed),
        calendarDay("invalid", .missed), calendarDay("2024-01-01", .notScheduled),
        calendarDay("2024-01-01", .pending), calendarDay("2024-01-01", .upcoming),
      ], asOfDate: "2024-01-01", year: 2024)
    XCTAssertEqual(summary.months[0], HabitBreakdownRow(label: "Jan", completed: 1))
    XCTAssertEqual(summary.months[0].completionRate, 1)
    XCTAssertNil(summary.months[1].completionRate)
    XCTAssertTrue(summary.mostMissedWeekdays.isEmpty)
  }

  func testBreakdownKeepsSkipOnlyAndEmptyPeriodsNeutral() {
    let summary = HabitBreakdown.calculate(
      days: [calendarDay("2024-03-03", .skipped)], asOfDate: "2024-03-03", year: 2024)
    XCTAssertEqual(summary.months[2].skipped, 1)
    XCTAssertNil(summary.months[2].completionRate)
    XCTAssertEqual(summary.weekdays[6].label, "Sunday")
    XCTAssertEqual(summary.weekdays[6].skipped, 1)
    XCTAssertNil(summary.weekdays[6].completionRate)
    XCTAssertEqual(summary.mostMisses, 0)
    XCTAssertTrue(
      HabitBreakdown.calculate(days: [], asOfDate: "2024-03-03", year: 2024).months.allSatisfy {
        $0.completionRate == nil
      })
  }

  func testBreakdownDoesNotInventWeeklyDeficitsOrAcceptInvalidCutoff() {
    let days = [calendarDay("2024-03-01", .notScheduled), calendarDay("2024-03-02", .missed)]
    XCTAssertEqual(
      HabitBreakdown.calculate(days: days, asOfDate: "2024-03-03", year: 2024).months[2].missed, 1)
    XCTAssertTrue(
      HabitBreakdown.calculate(days: days, asOfDate: "2024-02-30", year: 2024).months.allSatisfy {
        $0.missed == 0
      })
  }

  func testLocalDateRejectsCalendarOverflow() {
    XCTAssertTrue(HabitLocalDate.isValid("2026-02-28"))
    XCTAssertFalse(HabitLocalDate.isValid("2026-02-30"))
    XCTAssertFalse(HabitLocalDate.isValid("2026-13-01"))
    XCTAssertFalse(HabitLocalDate.isValid("not-a-date"))
  }

  func testLocalDateRoundTripsInTheChosenTimezone() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
    let date = try XCTUnwrap(HabitLocalDate.date(from: "2026-09-02", timeZone: timeZone))

    XCTAssertEqual(HabitLocalDate.string(from: date, timeZone: timeZone), "2026-09-02")
  }

  private var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  private func makeDefinition(
    habitID: UUID? = nil,
    expectedRevision: Int? = nil,
    name: String = "Take supplements",
    trackingMode: HabitTrackingMode = .check,
    measurementUnit: String = "",
    targetValue: Double? = nil,
    schedule: HabitSchedule = .daily,
    startsOn: String = "2026-09-01",
    endsOn: String? = nil
  ) throws -> HabitDefinitionInput {
    try HabitDefinitionInput.validate(
      habitID: habitID,
      expectedRevision: expectedRevision,
      name: name,
      trackingMode: trackingMode,
      measurementUnit: measurementUnit,
      targetValue: targetValue,
      schedule: schedule,
      startsOn: startsOn,
      endsOn: endsOn
    )
  }

  private func makeHabit(trackingMode: HabitTrackingMode) -> Habit {
    Habit(
      id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
      name: trackingMode == .check ? "Take supplements" : "Read pages",
      trackingMode: trackingMode,
      measurementUnit: trackingMode == .measure ? "pages" : nil,
      targetValue: trackingMode == .measure ? 20 : nil,
      schedule: .daily,
      startsOn: "2026-09-01",
      endsOn: nil,
      revision: 1,
      status: .pending,
      occurrence: nil,
      createdAt: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: 100)
    )
  }

  private func calendarDay(_ date: String, _ status: HabitCalendarStatus) -> HabitCalendarDay {
    HabitCalendarDay(
      localDate: date,
      isScheduled: status != .notScheduled,
      status: status,
      measuredValue: nil,
      note: nil,
      occurrenceID: nil,
      occurrenceRevision: nil
    )
  }
}
