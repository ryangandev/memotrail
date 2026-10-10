@preconcurrency import Supabase
import SwiftUI

/// Web `/goals` at phone width: Goals grouped by reflective state as record cards that open each
/// Goal's own page, and Add Goal.
struct GoalsView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: GoalController
  @State private var isAdding = false
  @State private var openedGoalID: UUID?

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: GoalController(client: client, ownerID: ownerID))
  }

  /// Web `goalSections`: each reflective state, with achieved and released Goals together.
  private static let sections: [(title: String, detail: String, statuses: Set<GoalStatus>)] = [
    ("In motion", "Intentions you are actively carrying", [.active]),
    ("Considering", "Possibilities worth keeping near", [.considering]),
    ("Paused", "Ideas resting without pressure", [.paused]),
    ("Closed chapters", "What was achieved or consciously released", [.achieved, .letGo]),
  ]

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "Intentions without pressure", title: "Goals",
        description:
          "Keep near-term plans, distant hopes, and someday ideas together as part of your personal archive."
      ) {
        Button {
          isAdding = true
        } label: {
          Label("Add Goal", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("add-goal")
      }
      summary
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("Goals")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      GoalEditorSheet(controller: controller, entry: nil)
    }
    .navigationDestination(item: $openedGoalID) { id in
      GoalDetailView(controller: controller, client: client, ownerID: ownerID, entryID: id)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var summary: some View {
    let open = controller.entries.filter { ![.achieved, .letGo].contains($0.status) }.count
    return MTFlowLayout(spacing: MTSpacing.s2) {
      Text(countLabel(controller.entries.count, "goal"))
      MTFlowSeparator()
      Text("\(open) open")
      MTFlowSeparator()
      Text("\(controller.entries.filter(\.isBucketList).count) in Bucket List")
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.detail)
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Goals summary")
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading your Goals...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.page)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "Goals unavailable", message: message, icon: .sparkle) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
      .padding(.top, MTSpacing.s4)
    } else if controller.entries.isEmpty {
      MTEmptyState(
        title: "Keep one possibility close",
        message: "Give it a name now. Its horizon, context, and meaning can evolve with you.",
        icon: .sparkle
      ) {
        isAdding = true
      }
      .padding(.top, MTSpacing.s4)
    } else {
      ForEach(Self.sections, id: \.title) { section in
        let entries = GoalWorkspace.entries(controller.entries, matching: section.statuses)
        if !entries.isEmpty {
          MTRecordSection(section.title, detail: section.detail) {
            ForEach(entries) { entry in
              GoalCard(entry: entry) { openedGoalID = entry.id }
            }
          }
        }
      }
    }
  }
}

/// Web `GoalCard`: an optional cover photo, the state and horizon, the title, target, a short
/// reflection, its Bucket List and linked context, and organization.
private struct GoalCard: View {
  let entry: GoalEntry
  let open: () -> Void
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  var body: some View {
    let isRegular = horizontalSizeClass == .regular
    MTRecordCard(
      accessibilityLabel: "\(entry.title), \(entry.status.displayName)", action: open
    ) {
      if let cover = entry.attachments.first {
        MTRecordCardVisual(
          height: isRegular
            ? MTLayout.RecordCard.goalVisualHeightRegular : MTLayout.RecordCard.goalVisualHeight
        ) {
          MTRemoteImage(url: cover.signedURL)
        }
        .overlay(alignment: .bottomTrailing) {
          if entry.attachments.count > 1 {
            MTBadge(
              title: "\(entry.attachments.count) photos", tone: .inverse, size: .micro,
              uppercase: true
            )
            .padding(MTSpacing.s3)
          }
        }
      }
      MTRecordCardBody {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: MTSpacing.s1_5) {
            MTBadge(
              title: entry.status.displayName,
              tone: [.active, .achieved].contains(entry.status) ? .accent : .neutral,
              size: .micro, uppercase: true)
            MTBadge(title: entry.horizon.displayName, tone: .neutral, size: .micro, uppercase: true)
          }
          Text(entry.title)
            .mtTextRole(isRegular ? .goalCardTitle : .goalCardTitleCompact)
            .foregroundStyle(MTColor.ink)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s3)
          Text(entry.targetLabel.uppercased())
            .mtTextRole(.dateStamp)
            .foregroundStyle(MTColor.accent)
            .padding(.top, MTSpacing.s2)
          if let reflection = entry.body.trimmed.nonEmpty {
            // Web shortens the reflection to 180 characters before clamping it.
            Text(
              reflection.count > 180
                ? "\(reflection.prefix(180).trimmingCharacters(in: .whitespaces))..." : reflection
            )
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s3)
          }
          Spacer(minLength: 0)
          context
          MTRecordCardFooter(
            collectionNames: entry.collectionNames.filter {
              $0.trimmed.lowercased() != "bucket list"
            }, tagNames: entry.tagNames)
        }
        // Web keeps short Goal cards the same height, with their context at the bottom.
        .frame(
          minHeight: (isRegular
            ? MTLayout.RecordCard.goalMinHeightRegular : MTLayout.RecordCard.goalMinHeight)
            - 2 * MTSpacing.s5,
          alignment: .top)
      }
    }
  }

  /// Web `contextLine`: Bucket List membership, related Items, and a linked First Time.
  @ViewBuilder private var context: some View {
    let related = entry.editableRelatedEntries.count
    let hasAchievement = !entry.achievementEntries.isEmpty
    if entry.isBucketList || related > 0 || hasAchievement {
      MTFlowLayout(spacing: MTSpacing.s2) {
        if entry.isBucketList {
          Label("Bucket List", icon: .star).labelStyle(MTInlineIconLabelStyle())
        }
        if related > 0 {
          Text(countLabel(related, "related Item"))
        }
        if hasAchievement {
          Text("First Time linked")
        }
      }
      .font(MTFont.note)
      .foregroundStyle(MTColor.inkFaint)
      .padding(.top, MTSpacing.s4)
    }
  }
}
