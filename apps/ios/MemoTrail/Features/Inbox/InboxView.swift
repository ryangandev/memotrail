@preconcurrency import Supabase
import SwiftUI

struct InboxView: View {
  let client: SupabaseClient
  let user: AuthenticatedUser
  let isAuthenticationBusy: Bool
  let signOut: @MainActor () async -> Void

  @Bindable private var controller: InboxController
  @Binding private var captureTitle: String
  @Binding private var captureBody: String
  @Binding private var captureOccurredAt: Date?
  @Binding private var capturePhotos: [FirstTimePhotoDraft]
  private let addCapturePhoto: @MainActor (FirstTimePhotoDraft) async throws -> Void
  private let removeCapturePhoto: @MainActor (UUID) async throws -> Void
  @Binding private var hasLocalDraft: Bool
  @State private var isShowingAccount = false
  @State private var selectedEntry: InboxEntry?
  @FocusState private var isTitleFocused: Bool
  @Environment(\.scenePhase) private var scenePhase

  init(
    client: SupabaseClient,
    user: AuthenticatedUser,
    isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void,
    controller: InboxController,
    captureTitle: Binding<String>,
    captureBody: Binding<String>,
    captureOccurredAt: Binding<Date?>,
    capturePhotos: Binding<[FirstTimePhotoDraft]>,
    addCapturePhoto: @escaping @MainActor (FirstTimePhotoDraft) async throws -> Void,
    removeCapturePhoto: @escaping @MainActor (UUID) async throws -> Void,
    hasLocalDraft: Binding<Bool>
  ) {
    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    self.controller = controller
    _captureTitle = captureTitle
    _captureBody = captureBody
    _captureOccurredAt = captureOccurredAt
    _capturePhotos = capturePhotos
    self.addCapturePhoto = addCapturePhoto
    self.removeCapturePhoto = removeCapturePhoto
    _hasLocalDraft = hasLocalDraft
    _selectedEntry = State(initialValue: nil)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: MTSpacing.s8) {
          header
          CaptureCard(
            title: $captureTitle,
            note: $captureBody,
            occurredAt: $captureOccurredAt,
            photos: $capturePhotos,
            isSaving: controller.isSaving,
            hasLocalDraft: hasLocalDraft,
            message: controller.captureMessage,
            titleFocus: $isTitleFocused,
            addPhoto: addCapturePhoto,
            removePhoto: removeCapturePhoto,
            save: saveCapture
          )
          if !controller.pendingEntries.isEmpty {
            pendingSection
          }
          entrySection
        }
        .padding(.horizontal, MTSpacing.s4)
        .padding(.top, MTSpacing.s6)
        .padding(.bottom, MTSpacing.s12)
      }
      .refreshable {
        await controller.refresh()
      }
      .background(MTColor.canvas)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          HStack(spacing: MTSpacing.s2) {
            Text("M")
              .font(.system(size: 14, weight: .semibold, design: .serif))
              .foregroundStyle(MTColor.accentInk)
              .frame(width: 28, height: 28)
              .background(
                MTColor.accent,
                in: UnevenRoundedRectangle(
                  cornerRadii: .init(
                    topLeading: 8,
                    bottomLeading: 3,
                    bottomTrailing: 8,
                    topTrailing: 8
                  )
                )
              )

            Text("MemoTrail")
              .font(.system(size: 18, weight: .medium, design: .serif))
              .foregroundStyle(MTColor.ink)
          }
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button("Profile", systemImage: "person.crop.circle.fill") {
            isShowingAccount = true
          }
          .accessibilityLabel("Open account for \(user.name)")
        }
      }
      .toolbarBackground(MTColor.surface, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $isShowingAccount) {
        AccountView(
          user: user,
          isBusy: isAuthenticationBusy,
          signOut: signOut
        )
      }
      .sheet(item: $selectedEntry) { entry in
        InboxReviewSheet(
          client: client,
          ownerID: user.id,
          entry: entry,
          requestSuggestions: { retry in
            try await controller.aiSuggestions(
              entryID: entry.id, revision: entry.revision, retry: retry)
          },
          dismissSuggestion: { id in try await controller.dismissAISuggestion(id) },
          collectionOptions: controller.collectionOptions,
          tagOptions: controller.tagOptions
        ) {
          title,
          body,
          collectionNames,
          entryType,
          occurrence,
          tagNames,
          intent in
          await controller.review(
            entry: entry,
            title: title,
            body: body,
            collectionNames: collectionNames,
            entryType: entryType,
            occurredAt: occurrence.start,
            occurredTimezone: occurrence.timezone,
            tagNames: tagNames,
            intent: intent,
            datePrecision: occurrence.precision,
            occurredEnd: occurrence.end,
            occurredLabel: occurrence.label
          )
        }
      }
      .task {
        if !controller.hasLoaded {
          await controller.refresh()
        }
      }
      .onChange(of: scenePhase) { _, newPhase in
        guard newPhase == .active, controller.hasLoaded else { return }
        Task { await controller.refresh() }
      }
    }
  }

  private var pendingSection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Text("PENDING SYNC")
            .font(MTTypography.label)
            .tracking(0.7)
            .foregroundStyle(MTColor.ink)

          Text(pendingCountLabel)
            .font(MTTypography.caption)
            .foregroundStyle(MTColor.inkFaint)
        }

        Spacer()

        Button {
          Task { await controller.refresh() }
        } label: {
          if controller.isSyncing {
            ProgressView()
              .controlSize(.small)
          } else {
            Label("Retry now", systemImage: "arrow.clockwise")
          }
        }
        .font(MTTypography.caption)
        .buttonStyle(.bordered)
        .disabled(controller.isSyncing)
        .accessibilityIdentifier("retry-pending-entries")
      }

      LazyVStack(spacing: 0) {
        ForEach(controller.pendingEntries) { entry in
          PendingEntryCard(entry: entry)

          if entry.id != controller.pendingEntries.last?.id {
            Divider()
              .overlay(MTColor.border)
          }
        }
      }
      .background(MTColor.accentSubtle.opacity(0.22))
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
          .font(MTTypography.caption)
          .tracking(1.1)
          .foregroundStyle(MTColor.inkFaint)

        Text("Inbox")
          .font(MTTypography.display)
          .foregroundStyle(MTColor.ink)
      }

      Spacer()

      Button("New entry", systemImage: "plus") {
        isTitleFocused = true
      }
      .labelStyle(.iconOnly)
      .font(.system(size: 18, weight: .medium))
      .foregroundStyle(MTColor.accentInk)
      .frame(width: 42, height: 42)
      .background(MTColor.accent, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .accessibilityLabel("New entry")
    }
  }

  private var entrySection: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        Text("UNSORTED")
          .font(MTTypography.label)
          .tracking(0.7)
          .foregroundStyle(MTColor.ink)

        Text(entryCountLabel)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        if controller.isLoading, controller.hasLoaded {
          ProgressView()
            .controlSize(.small)
        }
      }

      Group {
        if !controller.hasLoaded, controller.isLoading {
          loadingState
        } else if let loadErrorMessage = controller.loadErrorMessage,
          controller.entries.isEmpty
        {
          errorState(loadErrorMessage)
        } else if controller.entries.isEmpty {
          emptyState
        } else {
          entryList
        }
      }
      .background(MTColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }

      if let loadErrorMessage = controller.loadErrorMessage,
        !controller.entries.isEmpty
      {
        Label(loadErrorMessage, systemImage: "exclamationmark.circle.fill")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }
    }
  }

  private var entryList: some View {
    LazyVStack(spacing: 0) {
      ForEach(controller.entries) { entry in
        EntryCard(entry: entry) {
          selectedEntry = entry
        }

        if entry.id != controller.entries.last?.id {
          Divider()
            .overlay(MTColor.border)
        }
      }
    }
  }

  private var loadingState: some View {
    HStack(spacing: MTSpacing.s3) {
      ProgressView()
      Text("Loading your Inbox...")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
    }
    .frame(maxWidth: .infinity, minHeight: 112)
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: MTSpacing.s3) {
      Label("Inbox unavailable", systemImage: "exclamationmark.triangle")
        .font(MTTypography.titleSmall)
        .foregroundStyle(MTColor.ink)

      Text(message)
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .multilineTextAlignment(.center)

      Button("Try again") {
        Task { await controller.load() }
      }
      .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, minHeight: 180)
    .padding(MTSpacing.s4)
  }

  private var emptyState: some View {
    ContentUnavailableView(
      controller.pendingEntries.isEmpty ? "Your Inbox is ready" : "Waiting to sync",
      systemImage: "tray",
      description: Text(
        controller.pendingEntries.isEmpty
          ? "Save a thought above and it will appear here."
          : "Pending Entries will appear here after MemoTrail reconnects."
      )
    )
    .foregroundStyle(MTColor.inkMuted)
    .frame(maxWidth: .infinity, minHeight: 190)
  }

  private var entryCountLabel: String {
    let count = controller.entries.count
    return "\(count) \(count == 1 ? "entry" : "entries")"
  }

  private var pendingCountLabel: String {
    let count = controller.pendingEntries.count
    return "\(count) \(count == 1 ? "Entry" : "Entries") on this iPhone"
  }

  @MainActor
  private func saveCapture() async {
    let didSave = await controller.save(
      title: captureTitle,
      body: captureBody,
      occurredAt: captureOccurredAt,
      photos: capturePhotos
    )

    if didSave {
      captureTitle = ""
      captureBody = ""
      captureOccurredAt = nil
      capturePhotos = []
      hasLocalDraft = false
    }
  }
}

private struct InboxReviewSheet: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entry: InboxEntry
  let requestSuggestions: @MainActor (Bool) async throws -> EntryAISuggestionResponse
  let dismissSuggestion: @MainActor (UUID) async throws -> Void
  let collectionOptions: [String]
  let tagOptions: [String]
  let review:
    @MainActor (
      String,
      String,
      [String],
      InboxEntryType,
      EntryOccurrence,
      [String],
      InboxController.ReviewIntent
    ) async -> InboxController.ReviewResult

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var note: String
  @State private var collectionNames: [String]
  @State private var collectionInput = ""
  @State private var entryType: InboxEntryType
  @State private var occurrence: OccurrenceDraft
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var tagNames: [String]
  @State private var tagInput = ""

  init(
    client: SupabaseClient,
    ownerID: UUID,
    entry: InboxEntry,
    requestSuggestions: @escaping @MainActor (Bool) async throws -> EntryAISuggestionResponse,
    dismissSuggestion: @escaping @MainActor (UUID) async throws -> Void,
    collectionOptions: [String],
    tagOptions: [String],
    review:
      @escaping @MainActor (
        String,
        String,
        [String],
        InboxEntryType,
        EntryOccurrence,
        [String],
        InboxController.ReviewIntent
      ) async -> InboxController.ReviewResult
  ) {
    self.client = client
    self.ownerID = ownerID
    self.entry = entry
    self.requestSuggestions = requestSuggestions
    self.dismissSuggestion = dismissSuggestion
    self.collectionOptions = collectionOptions
    self.tagOptions = tagOptions
    self.review = review
    _title = State(initialValue: entry.title ?? "")
    _note = State(initialValue: entry.body)
    _collectionNames = State(initialValue: entry.collectionNames)
    _entryType = State(initialValue: entry.entryType)
    _occurrence = State(initialValue: OccurrenceDraft(entry.occurrence))
    _tagNames = State(initialValue: entry.tagNames)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          NavigationLink("Explore with AI") {
            ExplorationView(client: client, ownerID: ownerID, entryID: entry.id)
          }
          Text("Uses the saved version. Save your edits first.")
            .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
        }
        EntryAISuggestionsView(
          request: requestSuggestions, dismiss: dismissSuggestion,
          applyTitle: { title = $0 },
          applyType: { if let type = InboxEntryType(rawValue: $0) { entryType = type } },
          applyDate: { occurrence.useDateSuggestion($0) },
          addCollection: { name in
            if collectionNames.count < 20
              && !collectionNames.contains(where: { $0.lowercased() == name.lowercased() })
            {
              collectionNames.append(name)
            }
          },
          addTag: { name in
            if tagNames.count < 50
              && !tagNames.contains(where: { $0.lowercased() == name.lowercased() })
            {
              tagNames.append(name)
            }
          })
        Section("Content") {
          TextField("Title", text: $title, axis: .vertical)
            .textInputAutocapitalization(.sentences)
            .accessibilityIdentifier("review-title")

          TextEditor(text: $note)
            .frame(minHeight: 180)
            .accessibilityLabel("Note")
            .accessibilityIdentifier("review-body")
        }

        Section {
          Picker("Type", selection: $entryType) {
            ForEach(InboxEntryType.allCases, id: \.self) { type in
              Text(type.displayName).tag(type)
            }
          }

        } header: {
          Text("Organization")
        } footer: {
          Text("Save changes keeps this Entry in Inbox. Done marks it organized.")
        }
        EntryPhotoDatesView(
          client: client, ownerID: ownerID, entryID: entry.id, occurrence: $occurrence)
        OccurrenceEditor(value: $occurrence)

        Section {
          OrganizationNameEditor(
            names: $collectionNames,
            input: $collectionInput,
            options: collectionOptions,
            placeholder: "Add a Collection",
            maximumCount: 20,
            maximumNameLength: 80
          )
        } header: {
          Text("Collections")
        } footer: {
          Text("\(collectionNames.count) of 20")
        }

        Section {
          OrganizationNameEditor(
            names: $tagNames,
            input: $tagInput,
            options: tagOptions,
            placeholder: "Add a tag",
            maximumCount: 50,
            maximumNameLength: 60
          )
        } header: {
          Text("Tags")
        } footer: {
          Text("\(tagNames.count) of 50")
        }

        if let errorMessage {
          Section {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(MTTypography.caption)
              .foregroundStyle(MTColor.warm)
              .accessibilityIdentifier("review-error")
          }
        }

        Section {
          Button("Save changes") {
            Task { await submit(.save) }
          }
          .frame(maxWidth: .infinity)
          .disabled(isWorking)
          .accessibilityIdentifier("save-entry-review")
        }
      }
      .navigationTitle("Organize Entry")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(isWorking)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
          .disabled(isWorking)
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            Task { await submit(.done) }
          }
          .fontWeight(.semibold)
          .disabled(isWorking)
          .accessibilityIdentifier("organize-entry")
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
    .presentationDetents([.large])
    .interactiveDismissDisabled(isWorking)
  }

  @MainActor
  private func submit(_ intent: InboxController.ReviewIntent) async {
    let resolved: EntryOccurrence
    do {
      resolved = try occurrence.resolve(original: entry.occurrence)
    } catch {
      errorMessage = error.localizedDescription
      return
    }
    isWorking = true
    errorMessage = nil

    let result = await review(
      title,
      note,
      namesIncludingDraft(collectionNames, collectionInput),
      entryType,
      resolved,
      namesIncludingDraft(tagNames, tagInput),
      intent
    )

    isWorking = false

    switch result.status {
    case .done, .saved:
      dismiss()
    case .conflict, .error:
      errorMessage = result.message
    }
  }

  private func namesIncludingDraft(_ names: [String], _ draft: String) -> [String] {
    let name = draft.trimmed
    return name.isEmpty ? names : names + [name]
  }
}

private struct OrganizationNameEditor: View {
  @Binding var names: [String]
  @Binding var input: String

  let options: [String]
  let placeholder: String
  let maximumCount: Int
  let maximumNameLength: Int

  private var selectedNames: Set<String> {
    Set(names.map { $0.lowercased() })
  }

  private var suggestions: [String] {
    options.filter { !selectedNames.contains($0.lowercased()) }
  }

  var body: some View {
    if !names.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: MTSpacing.s2) {
          ForEach(names, id: \.self) { name in
            Button {
              names.removeAll { $0 == name }
            } label: {
              Label(name, systemImage: "xmark")
                .font(MTTypography.caption)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Remove \(name)")
          }
        }
      }
    }

    HStack {
      TextField(placeholder, text: $input)
        .textInputAutocapitalization(.words)
        .submitLabel(.done)
        .onSubmit(addInput)
        .onChange(of: input) {
          if input.count > maximumNameLength {
            input = String(input.prefix(maximumNameLength))
          }
        }

      Button("Add", systemImage: "plus") {
        addInput()
      }
      .labelStyle(.iconOnly)
      .disabled(input.trimmed.isEmpty || names.count >= maximumCount)
    }

    if !suggestions.isEmpty, names.count < maximumCount {
      Menu("Add existing", systemImage: "tag") {
        ForEach(suggestions, id: \.self) { suggestion in
          Button(suggestion) {
            add(suggestion)
          }
        }
      }
      .font(MTTypography.caption)
    }
  }

  private func addInput() {
    add(input)
    input = ""
  }

  private func add(_ value: String) {
    let name = value.trimmed

    guard !name.isEmpty,
      name.count <= maximumNameLength,
      names.count < maximumCount,
      !selectedNames.contains(name.lowercased())
    else { return }

    names.append(name)
  }
}
