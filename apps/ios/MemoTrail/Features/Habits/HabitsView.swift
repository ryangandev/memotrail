@preconcurrency import Supabase
import SwiftUI

struct HabitsView: View {
  @State private var controller: HabitsController
  @State private var selectedDate = Date()
  @State private var editorSelection: HabitEditorSelection?
  @State private var checkInSelection: HabitCheckInSelection?
  @State private var message: String?
  private let focusedHabitID: UUID?
  private let embedded: Bool

  init(client: SupabaseClient, ownerID: UUID, focusedHabitID: UUID? = nil, embedded: Bool = false) {
    self.focusedHabitID = focusedHabitID
    self.embedded = embedded
    _controller = State(initialValue: HabitsController(client: client, ownerID: ownerID))
  }

  @ViewBuilder
  var body: some View {
    if embedded { workspace } else { NavigationStack { workspace } }
  }

  private var workspace: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s6) {
        header
        dateCard

        if let message {
          Label(message, systemImage: "checkmark.circle.fill")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MTSpacing.s4)
            .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }

        habitContent
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle("Habits")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          editorSelection = HabitEditorSelection(habit: nil)
        } label: {
          Label("New Habit", systemImage: "plus")
        }
        .disabled(controller.isSaving)
      }
    }
    .refreshable {
      await controller.load(date: selectedDate)
    }
    .task {
      if !controller.hasLoaded {
        await controller.load(date: selectedDate)
        if let focusedHabitID, controller.habits.contains(where: { $0.id == focusedHabitID }) {
          await controller.selectHabit(focusedHabitID)
        }
      }
    }
    .onChange(of: selectedDate) {
      message = nil
      Task { await controller.load(date: selectedDate) }
    }
    .sheet(item: $editorSelection) { selection in
      HabitEditorSheet(controller: controller, habit: selection.habit) { result in
        handle(result)
      }
    }
    .sheet(item: $checkInSelection) { selection in
      HabitCheckInSheet(
        controller: controller,
        habit: selection.habit,
        day: selection.day
      ) { result in
        handle(result)
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("SMALL ACTIONS, KEPT HONESTLY")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.warm)

      Text("Habits")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Build a rhythm without hiding the days that went differently.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var dateCard: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(selectedDate.formatted(date: .complete, time: .omitted))
            .font(MTTypography.title)
            .foregroundStyle(MTColor.ink)
          Text("\(controller.completedCount) complete · \(controller.openCount) open")
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
        }

        Spacer()

        if controller.isLoading, controller.hasLoaded {
          ProgressView()
            .controlSize(.small)
        }
      }

      DatePicker(
        "Check-in date",
        selection: $selectedDate,
        in: ...Date(),
        displayedComponents: .date
      )
      .datePickerStyle(.compact)
      .tint(MTColor.accent)
    }
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var habitContent: some View {
    if controller.isLoading, !controller.hasLoaded {
      habitMessage("Loading your Habits...", systemImage: "hourglass")
    } else if let loadErrorMessage = controller.loadErrorMessage {
      habitMessage(loadErrorMessage, systemImage: "exclamationmark.triangle")
    } else if let focusedHabitID, !controller.habits.contains(where: { $0.id == focusedHabitID }) {
      habitMessage(
        "This Habit is no longer available in your active workspace.", systemImage: "archivebox")
    } else if controller.habits.isEmpty {
      habitMessage(
        "Create your first Habit. Check something off or measure a number over time.",
        systemImage: "checkmark.circle"
      )
    } else {
      habitList
      yearArchive
    }
  }

  private var habitList: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      sectionHeader("CHECK IN", title: "Your Habits", detail: "\(controller.habits.count) active")

      ForEach(controller.habits.filter { focusedHabitID == nil || $0.id == focusedHabitID }) {
        habit in
        HabitCard(
          habit: habit,
          isSelected: controller.selectedHabitID == habit.id,
          onSelect: { Task { await controller.selectHabit(habit.id) } },
          onEdit: { editorSelection = HabitEditorSelection(habit: habit) },
          onCheckIn: { checkInSelection = HabitCheckInSelection(habit: habit, day: nil) },
          onComplete: { Task { await quickComplete(habit) } }
        )
      }
    }
  }

  @ViewBuilder
  private var yearArchive: some View {
    if let habit = controller.selectedHabit {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        HStack(alignment: .bottom) {
          VStack(alignment: .leading, spacing: 3) {
            Text("YEAR IN VIEW")
              .font(MTTypography.caption)
              .tracking(1.1)
              .foregroundStyle(MTColor.warm)
            Text(habit.name)
              .font(MTTypography.title)
              .foregroundStyle(MTColor.ink)
            Text(habit.schedule.displayLabel)
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkFaint)
          }

          Spacer()

          HStack(spacing: MTSpacing.s2) {
            yearButton(controller.selectedYear - 1, systemImage: "chevron.left")
            Text(String(controller.selectedYear))
              .font(.system(size: 12, weight: .semibold, design: .monospaced))
              .foregroundStyle(MTColor.ink)
              .frame(minWidth: 42)
            yearButton(controller.selectedYear + 1, systemImage: "chevron.right")
          }
        }

        if controller.isCalendarLoading || controller.isLoading {
          ProgressView("Loading Habit history…")
        } else if let calendarErrorMessage = controller.calendarErrorMessage {
          habitMessage(calendarErrorMessage, systemImage: "exclamationmark.triangle")
        } else {
          statsGrid
          HabitYearCalendar(
            days: controller.calendar,
            habit: habit,
            referenceDate: controller.referenceDate
          ) { day in
            checkInSelection = HabitCheckInSelection(habit: habit, day: day)
          }
          HabitBreakdownView(
            summary: HabitBreakdown.calculate(
              days: controller.calendar, asOfDate: controller.referenceDate,
              year: controller.selectedYear),
            year: controller.selectedYear,
            referenceDate: controller.referenceDate,
            schedule: habit.schedule
          )
        }
      }
      .padding(.top, MTSpacing.s4)
    }
  }

  private var statsGrid: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: MTSpacing.s2), count: 2),
      spacing: MTSpacing.s2
    ) {
      HabitStatCard(
        label: "Current streak", value: "\(controller.stats.currentStreak)", detail: "checks")
      HabitStatCard(
        label: "Longest streak", value: "\(controller.stats.longestStreak)", detail: "checks")
      HabitStatCard(
        label: "Completion",
        value: controller.stats.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "-",
        detail: "\(controller.stats.completed) done"
      )
      HabitStatCard(
        label: "Missed",
        value: "\(controller.stats.missed)",
        detail: "\(controller.stats.skipped) skipped"
      )
    }
  }

  private func sectionHeader(_ eyebrow: String, title: String, detail: String) -> some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 3) {
        Text(eyebrow)
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.warm)
        Text(title)
          .font(MTTypography.title)
          .foregroundStyle(MTColor.ink)
      }
      Spacer()
      Text(detail)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkFaint)
    }
  }

  private func yearButton(_ year: Int, systemImage: String) -> some View {
    Button {
      Task { await controller.showYear(year) }
    } label: {
      Image(systemName: systemImage)
        .font(.system(size: 11, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.small))
    }
    .buttonStyle(.plain)
    .foregroundStyle(MTColor.inkMuted)
    .disabled(!(1900...2200).contains(year) || controller.isLoading)
  }

  private func habitMessage(_ message: String, systemImage: String) -> some View {
    Label(message, systemImage: systemImage)
      .font(MTTypography.body)
      .foregroundStyle(MTColor.inkMuted)
      .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
      .multilineTextAlignment(.center)
      .padding(MTSpacing.s5)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
  }

  @MainActor
  private func quickComplete(_ habit: Habit) async {
    let result = await controller.record(
      habit: habit,
      day: nil,
      status: .completed,
      measuredValue: nil,
      note: ""
    )
    handle(result)
  }

  private func handle(_ result: HabitsController.MutationResult) {
    if result.status == .saved || result.status == .trashed {
      message = result.message
    }
  }
}

private struct HabitBreakdownView: View {
  let summary: HabitBreakdown
  let year: Int
  let referenceDate: String
  let schedule: HabitSchedule

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text(
        "\(String(year)) through \(referenceDate). Rate is Done ÷ (Done + Missed). Skipped, pending, unscheduled, and future days do not lower it."
      )
      .font(MTTypography.caption)
      .foregroundStyle(MTColor.inkMuted)
      if case .weeklyTarget = schedule {
        Text(
          "Weekly targets use recorded check-ins only; unrecorded days are not assigned missed weekdays."
        )
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkMuted)
      }
      panel("Monthly summary", rows: summary.months)
      panel(
        "Weekday patterns", rows: summary.weekdays,
        detail: summary.mostMisses == 0
          ? "No missed days in this view."
          : "Most misses: \(summary.mostMissedWeekdays.joined(separator: ", ")) (\(summary.mostMisses) each)."
      )
    }
  }

  private func panel(_ title: String, rows: [HabitBreakdownRow], detail: String? = nil) -> some View
  {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text(title)
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      if let detail {
        Text(detail).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      }
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: 3) {
          HStack(alignment: .firstTextBaseline) {
            Text(row.label).foregroundStyle(MTColor.ink)
            Spacer(minLength: MTSpacing.s2)
            Text(row.completionRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "-")
              .monospacedDigit()
              .foregroundStyle(MTColor.ink)
              .accessibilityLabel(
                row.completionRate.map { "Completion rate \(Int(($0 * 100).rounded())) percent" }
                  ?? "No completion rate")
          }
          Text("\(row.completed) done · \(row.missed) missed · \(row.skipped) skipped")
            .foregroundStyle(MTColor.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(MTTypography.caption)
        .accessibilityElement(children: .combine)
        if row.id != rows.last?.id { Divider().overlay(MTColor.border) }
      }
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay(RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border, lineWidth: 1))
  }
}

private struct HabitCard: View {
  let habit: Habit
  let isSelected: Bool
  let onSelect: () -> Void
  let onEdit: () -> Void
  let onCheckIn: () -> Void
  let onComplete: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Button(action: onSelect) {
        HStack(spacing: MTSpacing.s3) {
          Circle()
            .fill(statusColor)
            .frame(width: 36, height: 36)
            .overlay {
              if habit.status == .completed {
                Image(systemName: "checkmark")
                  .font(.system(size: 12, weight: .bold))
                  .foregroundStyle(MTColor.canvas)
              }
            }

          VStack(alignment: .leading, spacing: 3) {
            Text(habit.name)
              .font(MTTypography.label)
              .foregroundStyle(MTColor.ink)
            Text(
              [habit.schedule.displayLabel, habit.measurementLabel].compactMap { $0 }.joined(
                separator: " · ")
            )
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
            .lineLimit(1)
          }

          Spacer()

          VStack(alignment: .trailing, spacing: 3) {
            Text(habit.status.displayName)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(MTColor.ink)
            if let occurrence = habit.occurrence {
              Text(occurrenceDetail(occurrence))
                .font(.system(size: 10))
                .foregroundStyle(MTColor.inkFaint)
                .lineLimit(1)
            }
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      Divider().overlay(MTColor.border)

      HStack(spacing: MTSpacing.s2) {
        Button("Edit", action: onEdit)
          .buttonStyle(HabitSecondaryButtonStyle())

        Button(habit.occurrence == nil ? "Details" : "Edit check-in", action: onCheckIn)
          .buttonStyle(HabitSecondaryButtonStyle())
          .disabled(habit.status == .notScheduled && habit.schedule.kind != .weeklyTarget)

        if habit.trackingMode == .check, habit.status == .pending, habit.occurrence == nil {
          Button("Complete", action: onComplete)
            .buttonStyle(HabitPrimaryButtonStyle())
        } else if habit.trackingMode == .measure, habit.occurrence == nil,
          habit.status == .pending
        {
          Button("Add value", action: onCheckIn)
            .buttonStyle(HabitPrimaryButtonStyle())
        } else {
          Text(habit.status == .completed ? "Completed" : "Check in")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MTColor.inkFaint)
            .frame(maxWidth: .infinity)
        }
      }
    }
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised)
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(isSelected ? MTColor.accent : MTColor.border, lineWidth: isSelected ? 1.5 : 1)
    }
  }

  private var statusColor: Color {
    switch habit.status {
    case .completed: MTColor.accent
    case .missed: MTColor.warning
    case .skipped: MTColor.warm
    case .pending: MTColor.accentSubtle
    case .upcoming, .notScheduled: MTColor.border
    }
  }

  private func occurrenceDetail(_ occurrence: HabitOccurrence) -> String {
    if let value = occurrence.measuredValue, let unit = habit.measurementUnit {
      return "\(HabitNumber.format(value)) \(unit)"
    }
    return occurrence.note ?? occurrence.status.displayName
  }
}

private struct HabitStatCard: View {
  let label: String
  let value: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(MTTypography.caption)
        .foregroundStyle(MTColor.inkFaint)
      Text(value)
        .font(MTTypography.title)
        .foregroundStyle(MTColor.ink)
      Text(detail)
        .font(.system(size: 10))
        .foregroundStyle(MTColor.inkFaint)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium)
        .stroke(MTColor.border, lineWidth: 1)
    }
  }
}

private struct HabitYearCalendar: View {
  let days: [HabitCalendarDay]
  let habit: Habit
  let referenceDate: String
  let onSelect: (HabitCalendarDay) -> Void

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: MTSpacing.s3), count: 2),
        spacing: MTSpacing.s3
      ) {
        ForEach(months) { month in
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            Text(month.name)
              .font(.system(size: 10, weight: .semibold, design: .monospaced))
              .foregroundStyle(MTColor.inkFaint)

            LazyVGrid(columns: columns, spacing: 3) {
              ForEach(Array("SMTWTFS".enumerated()), id: \.offset) { _, letter in
                Text(String(letter))
                  .font(.system(size: 7, weight: .medium))
                  .foregroundStyle(MTColor.inkFaint)
                  .frame(maxWidth: .infinity)
              }

              ForEach(0..<month.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 12)
              }

              ForEach(month.days) { day in
                Button {
                  onSelect(day)
                } label: {
                  RoundedRectangle(cornerRadius: 2)
                    .fill(color(day.status))
                    .frame(height: 12)
                    .overlay {
                      if day.localDate == referenceDate {
                        RoundedRectangle(cornerRadius: 2)
                          .stroke(MTColor.ink, lineWidth: 1)
                      }
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSelect(day))
                .accessibilityLabel("\(day.localDate), \(day.status.displayName)")
              }
            }
          }
          .padding(MTSpacing.s3)
          .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.medium))
          .overlay {
            RoundedRectangle(cornerRadius: MTRadius.medium)
              .stroke(MTColor.border, lineWidth: 1)
          }
        }
      }

      HStack(spacing: MTSpacing.s3) {
        legend("Done", color: MTColor.accent)
        legend("Missed", color: MTColor.warning)
        legend("Skipped", color: MTColor.warm)
        legend("Pending", color: MTColor.accentSubtle)
      }
    }
  }

  private var months: [HabitCalendarMonth] {
    Dictionary(grouping: days) { String($0.localDate.prefix(7)) }
      .values
      .compactMap(HabitCalendarMonth.init)
      .sorted { $0.id < $1.id }
  }

  private func canSelect(_ day: HabitCalendarDay) -> Bool {
    guard day.localDate <= referenceDate, day.localDate >= habit.startsOn,
      habit.endsOn.map({ day.localDate <= $0 }) ?? true
    else {
      return false
    }
    return day.isScheduled || day.occurrenceID != nil || habit.schedule.kind == .weeklyTarget
  }

  private func color(_ status: HabitCalendarStatus) -> Color {
    switch status {
    case .completed: MTColor.accent
    case .missed: MTColor.warning
    case .skipped: MTColor.warm
    case .pending: MTColor.accentSubtle
    case .upcoming: MTColor.surface
    case .notScheduled: MTColor.border.opacity(0.45)
    }
  }

  private func legend(_ label: String, color: Color) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 2)
        .fill(color)
        .frame(width: 8, height: 8)
      Text(label)
        .font(.system(size: 8))
        .foregroundStyle(MTColor.inkFaint)
    }
  }
}

private struct HabitCalendarMonth: Identifiable {
  let id: String
  let name: String
  let days: [HabitCalendarDay]
  let leadingBlanks: Int

  init?(_ days: [HabitCalendarDay]) {
    guard let first = days.sorted(by: { $0.localDate < $1.localDate }).first,
      let firstDate = HabitLocalDate.date(from: first.localDate)
    else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US")
    formatter.timeZone = .gmt
    formatter.dateFormat = "MMM"

    self.id = String(first.localDate.prefix(7))
    self.name = formatter.string(from: firstDate)
    self.days = days.sorted { $0.localDate < $1.localDate }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    self.leadingBlanks = calendar.component(.weekday, from: firstDate) - 1
  }
}

private struct HabitEditorSelection: Identifiable {
  let id = UUID()
  let habit: Habit?
}

private struct HabitCheckInSelection: Identifiable {
  let id = UUID()
  let habit: Habit
  let day: HabitCalendarDay?
}

private struct HabitEditorSheet: View {
  let controller: HabitsController
  let habit: Habit?
  let onFinished: (HabitsController.MutationResult) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var trackingMode: HabitTrackingMode
  @State private var measurementUnit: String
  @State private var targetValue: String
  @State private var scheduleKind: HabitSchedule.Kind
  @State private var weekdays: Set<Int>
  @State private var weeklyTarget: Int
  @State private var intervalDays: Int
  @State private var startsOn: Date
  @State private var hasEndDate: Bool
  @State private var endsOn: Date
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false

  init(
    controller: HabitsController,
    habit: Habit?,
    onFinished: @escaping (HabitsController.MutationResult) -> Void
  ) {
    self.controller = controller
    self.habit = habit
    self.onFinished = onFinished
    _name = State(initialValue: habit?.name ?? "")
    _trackingMode = State(initialValue: habit?.trackingMode ?? .check)
    _measurementUnit = State(initialValue: habit?.measurementUnit ?? "")
    _targetValue = State(initialValue: habit?.targetValue.map(HabitNumber.format) ?? "")
    _scheduleKind = State(initialValue: habit?.schedule.kind ?? .daily)
    _weekdays = State(initialValue: Set(habit?.schedule.weekdays ?? [1, 2, 3, 4, 5]))
    _weeklyTarget = State(initialValue: habit?.schedule.weeklyTarget ?? 3)
    _intervalDays = State(initialValue: habit?.schedule.intervalDays ?? 2)
    let start = habit.flatMap { HabitLocalDate.date(from: $0.startsOn) } ?? Date()
    let end = habit?.endsOn.flatMap { HabitLocalDate.date(from: $0) } ?? start
    _startsOn = State(initialValue: start)
    _hasEndDate = State(initialValue: habit?.endsOn != nil)
    _endsOn = State(initialValue: end)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Habit") {
          TextField("Name", text: $name)
            .textInputAutocapitalization(.sentences)

          Picker("Tracking mode", selection: $trackingMode) {
            ForEach(HabitTrackingMode.allCases, id: \.self) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
          .pickerStyle(.segmented)

          if trackingMode == .measure {
            TextField("Target", text: $targetValue)
              .keyboardType(.decimalPad)
            TextField("Unit", text: $measurementUnit)
              .textInputAutocapitalization(.never)
          }
        }

        Section("Schedule") {
          Picker("Rhythm", selection: $scheduleKind) {
            ForEach(HabitSchedule.Kind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind)
            }
          }

          switch scheduleKind {
          case .daily:
            Text("Every calendar day.")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.inkFaint)
          case .weekdays:
            weekdayPicker
          case .weeklyTarget:
            Stepper("\(weeklyTarget) times each week", value: $weeklyTarget, in: 1...7)
          case .interval:
            Stepper("Every \(intervalDays) days", value: $intervalDays, in: 1...365)
          }
        }

        Section("Active dates") {
          DatePicker("Start date", selection: $startsOn, displayedComponents: .date)
          Toggle("Has end date", isOn: $hasEndDate)
          if hasEndDate {
            DatePicker("End date", selection: $endsOn, in: startsOn..., displayedComponents: .date)
          }
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
          }
        }

        if habit != nil {
          Section {
            Button("Move to Trash", role: .destructive) {
              isConfirmingTrash = true
            }
          } footer: {
            Text("Check-ins and version history stay preserved for future restoration.")
          }
        }
      }
      .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: name) {
        if name.count > HabitDefinitionInput.nameLimit {
          name = String(name.prefix(HabitDefinitionInput.nameLimit))
        }
      }
      .onChange(of: measurementUnit) {
        if measurementUnit.count > HabitDefinitionInput.unitLimit {
          measurementUnit = String(measurementUnit.prefix(HabitDefinitionInput.unitLimit))
        }
      }
      .onChange(of: startsOn) {
        if endsOn < startsOn { endsOn = startsOn }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(habit == nil ? "Add" : "Save") {
            Task { await save() }
          }
          .fontWeight(.semibold)
        }
      }
      .overlay {
        if isWorking {
          ProgressView()
            .padding(MTSpacing.s4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
      .confirmationDialog(
        "Move this Habit to Trash?",
        isPresented: $isConfirmingTrash,
        titleVisibility: .visible
      ) {
        Button("Move to Trash", role: .destructive) {
          Task { await moveToTrash() }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Its check-ins and edit history will be preserved.")
      }
    }
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  private var weekdayPicker: some View {
    HStack(spacing: 5) {
      ForEach(HabitWeekday.all, id: \.self) { weekday in
        Button {
          if weekdays.contains(weekday) {
            weekdays.remove(weekday)
          } else {
            weekdays.insert(weekday)
          }
        } label: {
          Text(HabitWeekday.shortName(weekday)?.prefix(1) ?? "?")
            .font(.system(size: 11, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(
              weekdays.contains(weekday) ? MTColor.accentSubtle : MTColor.surface,
              in: RoundedRectangle(cornerRadius: MTRadius.small)
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(weekdays.contains(weekday) ? MTColor.accent : MTColor.inkMuted)
        .accessibilityLabel(HabitWeekday.shortName(weekday) ?? "Weekday")
        .accessibilityAddTraits(weekdays.contains(weekday) ? .isSelected : [])
      }
    }
  }

  private var schedule: HabitSchedule {
    switch scheduleKind {
    case .daily: .daily
    case .weekdays: .weekdays(weekdays.sorted())
    case .weeklyTarget: .weeklyTarget(weeklyTarget)
    case .interval: .interval(intervalDays)
    }
  }

  @MainActor
  private func save() async {
    isWorking = true
    errorMessage = nil
    let result = await controller.save(
      habit: habit,
      name: name,
      trackingMode: trackingMode,
      measurementUnit: measurementUnit,
      targetValue: Double(targetValue.trimmed),
      schedule: schedule,
      startsOn: startsOn,
      endsOn: hasEndDate ? endsOn : nil
    )
    isWorking = false

    if result.status == .saved {
      onFinished(result)
      dismiss()
    } else {
      errorMessage = result.message
    }
  }

  @MainActor
  private func moveToTrash() async {
    guard let habit else { return }
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(habit)
    isWorking = false

    if result.status == .trashed {
      onFinished(result)
      dismiss()
    } else {
      errorMessage = result.message
    }
  }
}

private struct HabitCheckInSheet: View {
  let controller: HabitsController
  let habit: Habit
  let day: HabitCalendarDay?
  let onFinished: (HabitsController.MutationResult) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var status: HabitOccurrenceStatus
  @State private var measuredValue: String
  @State private var note: String
  @State private var isWorking = false
  @State private var errorMessage: String?

  init(
    controller: HabitsController,
    habit: Habit,
    day: HabitCalendarDay?,
    onFinished: @escaping (HabitsController.MutationResult) -> Void
  ) {
    self.controller = controller
    self.habit = habit
    self.day = day
    self.onFinished = onFinished
    let occurrenceStatus =
      day.flatMap { HabitOccurrenceStatus(rawValue: $0.status.rawValue) }
      ?? habit.occurrence?.status
      ?? .completed
    _status = State(initialValue: occurrenceStatus)
    let measurement = day?.measuredValue ?? habit.occurrence?.measuredValue
    _measuredValue = State(initialValue: measurement.map(HabitNumber.format) ?? "")
    _note = State(initialValue: day?.note ?? habit.occurrence?.note ?? "")
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(displayDate)
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)

          Picker("What happened?", selection: $status) {
            ForEach(HabitOccurrenceStatus.allCases, id: \.self) { status in
              Text(status.displayName).tag(status)
            }
          }
          .pickerStyle(.segmented)
        }

        if habit.trackingMode == .measure, status == .completed {
          Section("Measurement") {
            TextField("Amount in \(habit.measurementUnit ?? "units")", text: $measuredValue)
              .keyboardType(.decimalPad)
            if let target = habit.targetValue, let unit = habit.measurementUnit {
              Text("Target: \(HabitNumber.format(target)) \(unit)")
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkFaint)
            }
          }
        }

        Section("Note") {
          TextEditor(text: $note)
            .frame(minHeight: 130)
            .accessibilityLabel("Optional check-in note")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
          }
        }
      }
      .navigationTitle(habit.name)
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .onChange(of: note) {
        if note.count > HabitOccurrenceInput.noteLimit {
          note = String(note.prefix(HabitOccurrenceInput.noteLimit))
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(existingRevision == nil ? "Save" : "Update") {
            Task { await save() }
          }
          .fontWeight(.semibold)
        }
      }
      .overlay {
        if isWorking {
          ProgressView()
            .padding(MTSpacing.s4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        }
      }
    }
    .presentationDetents([.medium, .large])
    .interactiveDismissDisabled(isWorking)
  }

  private var existingRevision: Int? {
    day?.occurrenceRevision ?? habit.occurrence?.revision
  }

  private var displayDate: String {
    let value = day?.localDate ?? controller.referenceDate
    guard let date = HabitLocalDate.date(from: value) else { return value }
    return date.formatted(date: .complete, time: .omitted)
  }

  @MainActor
  private func save() async {
    isWorking = true
    errorMessage = nil
    let result = await controller.record(
      habit: habit,
      day: day,
      status: status,
      measuredValue: status == .completed ? Double(measuredValue.trimmed) : nil,
      note: note
    )
    isWorking = false

    if result.status == .saved {
      onFinished(result)
      dismiss()
    } else {
      errorMessage = result.message
    }
  }
}

private struct HabitSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(MTColor.inkMuted)
      .frame(maxWidth: .infinity, minHeight: 36)
      .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.small))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

private struct HabitPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 11, weight: .semibold))
      .foregroundStyle(MTColor.canvas)
      .frame(maxWidth: .infinity, minHeight: 36)
      .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.small))
      .opacity(configuration.isPressed ? 0.75 : 1)
  }
}

extension HabitSchedule {
  fileprivate var weekdays: [Int]? {
    if case .weekdays(let weekdays) = self { return weekdays }
    return nil
  }

  fileprivate var weeklyTarget: Int? {
    if case .weeklyTarget(let target) = self { return target }
    return nil
  }

  fileprivate var intervalDays: Int? {
    if case .interval(let days) = self { return days }
    return nil
  }
}
