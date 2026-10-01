import SwiftUI

/// Web `GoalExtraction` as a form sheet: creates a separate Goal linked back to this Item, then
/// opens it. The Goal's ID is chosen once, so a retry after a lost response cannot create two.
struct LinkedGoalSheet: View {
  let controller: EntryHistoryController
  let created: (UUID) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var goalID = UUID()
  @State private var title: String
  @State private var horizon: GoalHorizon = .someday
  @State private var status: GoalStatus = .considering
  @State private var targetDate = ""
  @State private var errorMessage: String?

  init(controller: EntryHistoryController, created: @escaping (UUID) -> Void) {
    self.controller = controller
    self.created = created
    _title = State(initialValue: controller.record?.current["title"]?.text ?? "")
  }

  var body: some View {
    MTSheet(
      eyebrow: "Create linked Goal", title: "Create a Goal from this item",
      closeLabel: "Close linked Goal", closeIdentifier: "close-linked-goal",
      isBusy: controller.isWorking, message: errorMessage
    ) {
      Text(
        "This creates a separate Goal and links it back to this source. The source keeps its writing, dates, photos, links, and history."
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
      MTFormSection("The Goal") {
        MTTextField(
          label: "Goal title", text: $title, isRequired: true, maxLength: GoalEntryInput.titleLimit
        )
        .textInputAutocapitalization(.sentences)
        .accessibilityIdentifier("linked-goal-title")
        MTSelectField(
          label: "Horizon", selection: $horizon, options: GoalHorizon.allCases,
          title: \.displayName)
        MTSelectField(
          label: "Status", selection: $status, options: GoalStatus.allCases,
          title: \.displayName)
        MTDateField(label: "Target date", value: $targetDate)
      }
    } footer: {
      MTSheetFooter {
        EmptyView()
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button("Create linked Goal") { Task { await create() } }
          .mtButtonStyle(isLoading: controller.isWorking)
          .accessibilityIdentifier("save-linked-goal")
      }
    }
  }

  private func create() async {
    errorMessage = nil
    switch await controller.extractGoal(
      goalID: goalID, title: title, horizon: horizon, status: status,
      targetDate: targetDate.trimmed.nonEmpty)
    {
    case .success(let goalID):
      MTToastCenter.shared.success("Goal created.")
      dismiss()
      created(goalID)
    case .failure(let failure):
      errorMessage = failure.message.nonEmpty
    }
  }
}
