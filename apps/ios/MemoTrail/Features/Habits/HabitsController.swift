import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class HabitsController {
  private(set) var habits: [Habit] = []
  private(set) var calendar: [HabitCalendarDay] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var loadErrorMessage: String?
  private(set) var calendarErrorMessage: String?
  private(set) var referenceDate = HabitLocalDate.string(from: Date())
  private(set) var selectedHabitID: UUID?
  private(set) var selectedYear = Calendar.current.component(.year, from: Date())

  private let client: SupabaseClient
  private let ownerID: UUID
  private var pendingLocalDate: String?

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  var selectedHabit: Habit? {
    habits.first { $0.id == selectedHabitID }
  }

  var stats: HabitYearStats {
    HabitYearStats.calculate(days: calendar, asOfDate: referenceDate)
  }

  var completedCount: Int {
    habits.count { $0.status == .completed }
  }

  var openCount: Int {
    habits.count { $0.status == .pending }
  }

  func load(date: Date) async {
    await load(localDate: HabitLocalDate.string(from: date))
  }

  func load(localDate: String) async {
    guard !isLoading else {
      pendingLocalDate = localDate
      return
    }

    isLoading = true
    loadErrorMessage = nil
    referenceDate = localDate

    do {
      try await validateSessionOwner()
      let rows: [HabitWorkspaceRow] =
        try await client
        .rpc("habits_workspace", params: HabitsWorkspaceParameters(localDate: localDate))
        .execute()
        .value

      habits = HabitsWorkspace.habits(from: rows)
      if !habits.contains(where: { $0.id == selectedHabitID }) {
        selectedHabitID = habits.first?.id
      }
      await loadCalendar()
    } catch {
      habits = []
      calendar = []
      loadErrorMessage = "MemoTrail could not load your Habits. Pull to refresh or try again."
    }

    isLoading = false
    hasLoaded = true

    if let pendingLocalDate, pendingLocalDate != referenceDate {
      self.pendingLocalDate = nil
      await load(localDate: pendingLocalDate)
    } else {
      pendingLocalDate = nil
    }
  }

  func selectHabit(_ habitID: UUID) async {
    guard selectedHabitID != habitID else { return }
    selectedHabitID = habitID
    await loadCalendar()
  }

  func showYear(_ year: Int) async {
    guard (1900...2200).contains(year), selectedYear != year else { return }
    selectedYear = year
    await loadCalendar()
  }

  func save(
    habit: Habit?,
    name: String,
    trackingMode: HabitTrackingMode,
    measurementUnit: String,
    targetValue: Double?,
    schedule: HabitSchedule,
    startsOn: Date,
    endsOn: Date?
  ) async -> MutationResult {
    let input: HabitDefinitionInput

    do {
      input = try HabitDefinitionInput.validate(
        habitID: habit?.id,
        expectedRevision: habit?.revision,
        name: name,
        trackingMode: trackingMode,
        measurementUnit: trackingMode == .measure ? measurementUnit : "",
        targetValue: trackingMode == .measure ? targetValue : nil,
        schedule: schedule,
        startsOn: HabitLocalDate.string(from: startsOn),
        endsOn: endsOn.map { HabitLocalDate.string(from: $0) }
      )
    } catch {
      return MutationResult(message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(message: "A Habit change is already saving.", status: .error)
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedHabit] =
        try await client
        .rpc("save_habit", params: SaveHabitParameters(input: input))
        .execute()
        .value

      guard let saved = results.first else {
        return MutationResult(
          message: habit == nil
            ? "MemoTrail could not create this Habit. Refresh and try again."
            : "This Habit changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      selectedHabitID = saved.habitID
      await reloadAfterMutation()
      return MutationResult(
        message: habit == nil ? "Habit added." : "Habit saved.",
        status: .saved
      )
    } catch {
      return MutationResult(
        message: "MemoTrail could not save this Habit. Try again.", status: .error)
    }
  }

  func record(
    habit: Habit,
    day: HabitCalendarDay?,
    status: HabitOccurrenceStatus,
    measuredValue: Double?,
    note: String
  ) async -> MutationResult {
    let existingRevision = day?.occurrenceRevision ?? habit.occurrence?.revision
    let input: HabitOccurrenceInput

    do {
      input = try HabitOccurrenceInput.validate(
        habit: habit,
        localDate: day?.localDate ?? referenceDate,
        status: status,
        measuredValue: status == .completed ? measuredValue : nil,
        note: note,
        expectedRevision: existingRevision
      )
    } catch {
      return MutationResult(message: error.localizedDescription, status: .error)
    }

    guard !isSaving else {
      return MutationResult(message: "A check-in is already saving.", status: .error)
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedHabitOccurrence] =
        try await client
        .rpc(
          "record_habit_occurrence",
          params: RecordHabitOccurrenceParameters(input: input)
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          message: "This check-in changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      await reloadAfterMutation()
      return MutationResult(
        message: existingRevision == nil ? "Check-in saved." : "Check-in updated.",
        status: .saved
      )
    } catch {
      return MutationResult(
        message: "MemoTrail could not save this check-in. Try again.", status: .error)
    }
  }

  func moveToTrash(_ habit: Habit) async -> MutationResult {
    guard !isSaving else {
      return MutationResult(message: "A Habit change is already saving.", status: .error)
    }

    isSaving = true
    defer { isSaving = false }

    do {
      try await validateSessionOwner()
      let results: [SavedHabit] =
        try await client
        .rpc(
          "trash_habit",
          params: TrashHabitParameters(
            habitID: habit.id,
            expectedRevision: habit.revision
          )
        )
        .execute()
        .value

      guard results.first != nil else {
        return MutationResult(
          message: "This Habit changed on another device. Close it, refresh, and try again.",
          status: .conflict
        )
      }

      selectedHabitID = nil
      await reloadAfterMutation()
      return MutationResult(message: "Habit moved to Trash.", status: .trashed)
    } catch {
      return MutationResult(
        message: "MemoTrail could not move this Habit to Trash. Try again.",
        status: .error
      )
    }
  }

  private func loadCalendar() async {
    guard let selectedHabitID else {
      calendar = []
      calendarErrorMessage = nil
      return
    }

    calendarErrorMessage = nil
    do {
      let rows: [HabitCalendarDay] =
        try await client
        .rpc(
          "habit_year_calendar",
          params: HabitYearCalendarParameters(
            habitID: selectedHabitID,
            year: selectedYear,
            asOfDate: referenceDate
          )
        )
        .execute()
        .value
      calendar = rows.sorted { $0.localDate < $1.localDate }
    } catch {
      calendar = []
      calendarErrorMessage = "MemoTrail could not load this Habit year. Pull to refresh."
    }
  }

  private func reloadAfterMutation() async {
    isLoading = false
    await load(localDate: referenceDate)
  }

  private func validateSessionOwner() async throws {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw HabitsControllerError.ownerChanged }
  }
}

extension HabitsController {
  struct MutationResult: Equatable, Sendable {
    enum Status: Equatable, Sendable {
      case conflict
      case error
      case saved
      case trashed
    }

    let message: String
    let status: Status
  }
}

private enum HabitsControllerError: Error {
  case ownerChanged
}
