@preconcurrency import Supabase
import SwiftUI

struct SearchView: View {
  @State private var controller: SearchController
  @State private var isShowingFilters = false
  private let embedded: Bool
  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID, embedded: Bool = false) {
    self.embedded = embedded
    self.client = client
    self.ownerID = ownerID
    _controller = State(
      initialValue: SearchController(client: client, ownerID: ownerID)
    )
  }

  @ViewBuilder
  var body: some View {
    if embedded {
      searchWorkspace
    } else {
      NavigationStack {
        searchWorkspace
      }
    }
  }

  private var searchWorkspace: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s6) {
        header
        criteriaSummary
        if controller.isAskingAI {
          ProgressView("Finding sources and composing…")
          Text("This can take up to a minute. Your original records stay unchanged.")
            .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
        } else if let answer = controller.aiAnswer {
          aiResults(answer)
        } else {
          results
        }
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s6)
      .padding(.bottom, MTSpacing.s12)
    }
    .background(MTColor.canvas)
    .navigationTitle("Search")
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $controller.query,
      placement: .navigationBarDrawer(displayMode: .always),
      prompt: "A phrase, date, or question about your life"
    )
    .onSubmit(of: .search) {
      Task { await controller.search() }
    }
    .onChange(of: controller.query) {
      if controller.query.count > EntrySearchRequest.queryLimit {
        controller.query = String(controller.query.prefix(EntrySearchRequest.queryLimit))
      }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          isShowingFilters = true
        } label: {
          Image(
            systemName: controller.activeFilterCount > 0
              ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel(filterButtonLabel)
        .disabled(controller.isAskingAI)
      }
    }
    .toolbarBackground(MTColor.surface, for: .navigationBar)
    .toolbarBackground(.visible, for: .navigationBar)
    .sheet(isPresented: $isShowingFilters) {
      SearchFiltersSheet(controller: controller)
    }
    .navigationDestination(for: SearchEntry.self) { entry in
      searchDestination(entry)
    }
    .task {
      await controller.loadFilterOptions()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("YOUR PERSONAL ARCHIVE")
        .font(MTTypography.caption)
        .tracking(1.1)
        .foregroundStyle(MTColor.inkFaint)

      Text("Search your trail")
        .font(MTTypography.display)
        .foregroundStyle(MTColor.ink)

      Text("Find any Writing, Entity, Event, Story, or Goal by what you remember.")
        .font(MTTypography.body)
        .foregroundStyle(MTColor.inkMuted)
        .lineSpacing(2)
    }
  }

  private var criteriaSummary: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(spacing: MTSpacing.s2) {
        Text("Keyword search")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.accent)
          .padding(.horizontal, MTSpacing.s2)
          .padding(.vertical, 5)
          .background(MTColor.accentSubtle, in: Capsule())

        Text("Titles, notes, local dates, organization, and details")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
      }

      if !activeFilterLabels.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: MTSpacing.s2) {
            ForEach(activeFilterLabels, id: \.self) { label in
              Text(label)
                .font(MTTypography.caption)
                .foregroundStyle(MTColor.inkMuted)
                .padding(.horizontal, MTSpacing.s2)
                .padding(.vertical, 5)
                .background(MTColor.surfaceSubtle, in: Capsule())
            }
          }
        }
      }

      Button {
        Task { await controller.search() }
      } label: {
        if controller.isLoading && controller.entries.isEmpty {
          ProgressView()
            .tint(MTColor.accentInk)
            .frame(maxWidth: .infinity)
        } else {
          Label("Search", systemImage: "magnifyingglass")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(MTColor.accent)
      .controlSize(.large)
      .disabled(!controller.hasCriteria || controller.isLoading || controller.isAskingAI)
      .accessibilityIdentifier("search-entries")

      Button("Ask AI", systemImage: "sparkles") { Task { await controller.askAI() } }
        .buttonStyle(.bordered).tint(MTColor.accent)
        .disabled(controller.isAskingAI || controller.isLoading || controller.query.trimmed.isEmpty)
        .accessibilityIdentifier("ask-ai-search")
      Text(
        "Uses this search field and its filters. Sends the question and relevant text to Anthropic only when you ask."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      NavigationLink("AI settings") { AISettingsView(client: client, ownerID: ownerID) }
      if let error = controller.aiError {
        Text(error).font(MTTypography.caption).foregroundStyle(MTColor.warm)
      }

      if let filterErrorMessage = controller.filterErrorMessage {
        Label(filterErrorMessage, systemImage: "exclamationmark.circle")
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.warm)
      }
    }
    .padding(MTSpacing.s4)
    .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.borderStrong, lineWidth: 1)
    }
  }

  @ViewBuilder
  private var results: some View {
    if let searchErrorMessage = controller.searchErrorMessage {
      searchMessage(
        title: "Search unavailable",
        message: searchErrorMessage,
        systemImage: "exclamationmark.triangle"
      )
    } else if !controller.hasSearched {
      searchMessage(
        title: "Start with anything you remember",
        message:
          "A word from the writing, a year, a Collection, or even part of a Chinese phrase can bring a Wiki Item back.",
        systemImage: "sparkles"
      )
    } else if controller.isLoading && controller.entries.isEmpty {
      HStack(spacing: MTSpacing.s3) {
        ProgressView()
        Text("Searching your Life Wiki...")
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 150)
    } else if controller.entries.isEmpty {
      searchMessage(
        title: "No matching items",
        message: "Try fewer words, remove a filter, or search for a broader date.",
        systemImage: "magnifyingglass"
      )
    } else {
      resultsList
    }
  }

  private func aiResults(_ answer: AISearchAnswer) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("AI-ASSISTED SEARCH · CHECK THE SOURCES").font(MTTypography.caption).foregroundStyle(
        MTColor.warm)
      Text(answer.question).font(MTTypography.titleSmall)
      if answer.insufficientEvidence {
        Text(
          answer.findings.isEmpty
            ? "Not enough evidence in the retrieved records to answer this question. Try different words or filters."
            : "The retrieved records only partly answer this question."
        )
        .foregroundStyle(MTColor.inkMuted)
      }
      ForEach(Array(answer.findings.enumerated()), id: \.offset) { _, finding in
        VStack(alignment: .leading, spacing: MTSpacing.s3) {
          Text(finding.text).textSelection(.enabled)
          ForEach(Array(finding.citations.enumerated()), id: \.offset) { _, citation in
            if let source = answer.sources.first(where: { $0.id == citation.sourceID }) {
              if citation.quote.hasPrefix("Recorded facts:") {
                DisclosureGroup("Recorded facts") {
                  Text(citation.quote).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
                    .textSelection(.enabled)
                }
              } else {
                Text(citation.quote).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
                  .textSelection(.enabled)
              }
              NavigationLink(source.title) { sourceView(source) }
            }
          }
        }.padding(MTSpacing.s4).frame(maxWidth: .infinity, alignment: .leading)
          .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
      }
      ForEach(answer.notices, id: \.self) {
        Text($0).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      }
      DisclosureGroup("Retrieved sources (\(answer.sources.count))") {
        ForEach(answer.sources) { source in
          NavigationLink(source.title) { sourceView(source) }.padding(.vertical, 6)
        }
      }
      Text(
        "AI interpretations can be wrong. Retrieval uses query expansion and bounded text matching, not a complete vector index. Nothing is saved as an Entry."
      )
      .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
    }
  }

  private func sourceView(_ source: AISearchSource) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        Text(source.title).font(MTTypography.title)
        Text("\(source.kind) · retrieved evidence\(source.truncated ? " · excerpt" : "")")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
        Text(source.text).font(MTTypography.body).textSelection(.enabled)
        if source.kind == "entry" {
          NavigationLink("Open original record") {
            EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: source.recordID)
          }
        } else if source.kind == "habit" {
          NavigationLink("Open original Habit") {
            HabitsView(
              client: client, ownerID: ownerID, focusedHabitID: source.recordID, embedded: true)
          }
        } else if source.kind == "place" {
          NavigationLink("Open original Place") {
            PlacesView(
              client: client, ownerID: ownerID, embedded: true, focusedPlaceID: source.recordID)
          }
        } else if source.kind == "person" {
          NavigationLink("Open original Person") {
            PeopleView(client: client, ownerID: ownerID, focusedPersonID: source.recordID)
          }
        }
      }.padding(MTSpacing.s4)
    }.background(MTColor.canvas).navigationTitle("Source record")
  }

  private var resultsList: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline) {
        Text("RESULTS")
          .font(MTTypography.label)
          .tracking(0.7)
          .foregroundStyle(MTColor.ink)

        Text(resultCountLabel)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)

        Spacer()

        if controller.isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }

      LazyVStack(spacing: 0) {
        ForEach(controller.entries) { entry in
          NavigationLink(value: entry) {
            SearchResultCard(entry: entry)
          }
          .buttonStyle(.plain)

          if entry.id != controller.entries.last?.id {
            Divider()
              .overlay(MTColor.border)
          }
        }
      }
      .background(MTColor.surface)
      .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large)
          .stroke(MTColor.border, lineWidth: 1)
      }

      if controller.canLoadMore {
        Button("Load more", systemImage: "arrow.down") {
          Task { await controller.loadMore() }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("load-more-search-results")
      }
    }
  }

  private func searchMessage(title: String, message: String, systemImage: String) -> some View {
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(MTColor.accent)

      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(title)
          .font(MTTypography.titleSmall)
          .foregroundStyle(MTColor.ink)

        Text(message)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(MTColor.surfaceSubtle.opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .stroke(MTColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
    }
  }

  private var activeFilterLabels: [String] {
    var labels: [String] = []

    if let selectedItemKind = controller.selectedItemKind {
      labels.append(selectedItemKind.displayName)
    }
    if let selectedCollectionName = controller.selectedCollectionName {
      labels.append(selectedCollectionName)
    }
    if let selectedTagName = controller.selectedTagName {
      labels.append("#\(selectedTagName)")
    }
    if controller.dateFrom != nil {
      labels.append("Start date")
    }
    if controller.dateTo != nil {
      labels.append("End date")
    }

    return labels
  }

  private var resultCountLabel: String {
    "\(controller.totalCount) \(controller.totalCount == 1 ? "item" : "items")"
  }

  @ViewBuilder
  private func searchDestination(_ entry: SearchEntry) -> some View {
    switch entry.recordSource {
    case .person:
      PeopleView(client: client, ownerID: ownerID, focusedPersonID: entry.recordID)
    case .place:
      PlacesView(client: client, ownerID: ownerID, embedded: true, focusedPlaceID: entry.recordID)
    case .entry:
      switch (entry.itemKind, entry.itemSubtype) {
      case (.entity, "home"):
        HomesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: entry.id)
      case (.entity, "vehicle"):
        VehiclesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: entry.id)
      case (.goal, _):
        GoalsView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: entry.id)
      case (.event, "first_time"):
        FirstTimesView(client: client, ownerID: ownerID, embedded: true, focusedEntryID: entry.id)
      default:
        EntryHistoryDetailView(client: client, ownerID: ownerID, entryID: entry.id)
      }
    }
  }

  private var filterButtonLabel: String {
    if controller.activeFilterCount == 0 {
      return "Refine search"
    }

    return "Refine search, \(controller.activeFilterCount) active filters"
  }
}

private struct SearchResultCard: View {
  let entry: SearchEntry

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        metadataBadge(entry.displayType)

        if entry.isInInbox {
          metadataBadge("In Inbox", isWarm: true)
        }

        Spacer()

        Text(entry.displayDate)
          .font(MTTypography.caption)
          .foregroundStyle(MTColor.inkFaint)
      }

      Text(entry.displayTitle)
        .font(.system(size: 19, weight: .medium, design: .serif))
        .foregroundStyle(MTColor.ink)

      if let excerpt = entry.displayExcerpt {
        Text(excerpt)
          .font(MTTypography.body)
          .foregroundStyle(MTColor.inkMuted)
          .lineSpacing(2)
          .lineLimit(4)
      }

      if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            ForEach(entry.collectionNames, id: \.self) { name in
              organizationBadge(name)
            }

            ForEach(entry.tagNames, id: \.self) { name in
              organizationBadge("#\(name)")
            }
          }
        }
      }

      HStack(alignment: .center, spacing: MTSpacing.s2) {
        Text("Matched in")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(MTColor.inkFaint)

        ForEach(entry.matchReasons, id: \.self) { reason in
          Text(reason)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(MTColor.accent)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(MTColor.inkFaint)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(MTSpacing.s4)
    .contentShape(Rectangle())
  }

  private func metadataBadge(_ title: String, isWarm: Bool = false) -> some View {
    Text(title)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(isWarm ? MTColor.warm : MTColor.inkMuted)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, 4)
      .background(isWarm ? MTColor.warmSubtle : MTColor.surfaceSubtle, in: Capsule())
  }

  private func organizationBadge(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(MTColor.inkMuted)
      .padding(.horizontal, MTSpacing.s2)
      .padding(.vertical, 4)
      .background(MTColor.surfaceSubtle, in: Capsule())
  }
}

private struct SearchFiltersSheet: View {
  let controller: SearchController

  @Environment(\.dismiss) private var dismiss
  @State private var itemKind: WikiItemKind?
  @State private var collectionName: String?
  @State private var tagName: String?
  @State private var dateFrom: Date?
  @State private var dateTo: Date?

  init(controller: SearchController) {
    self.controller = controller
    _itemKind = State(initialValue: controller.selectedItemKind)
    _collectionName = State(initialValue: controller.selectedCollectionName)
    _tagName = State(initialValue: controller.selectedTagName)
    _dateFrom = State(initialValue: controller.dateFrom)
    _dateTo = State(initialValue: controller.dateTo)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Organization") {
          Picker("Kind", selection: $itemKind) {
            Text("All Kinds").tag(nil as WikiItemKind?)
            ForEach(WikiItemKind.allCases, id: \.self) { kind in
              Text(kind.displayName).tag(kind as WikiItemKind?)
            }
          }

          Picker("Collection", selection: $collectionName) {
            Text("All Collections").tag(nil as String?)
            ForEach(controller.collectionOptions, id: \.self) { name in
              Text(name).tag(name as String?)
            }
          }
          .disabled(controller.collectionOptions.isEmpty)

          Picker("Tag", selection: $tagName) {
            Text("All tags").tag(nil as String?)
            ForEach(controller.tagOptions, id: \.self) { name in
              Text(name).tag(name as String?)
            }
          }
          .disabled(controller.tagOptions.isEmpty)
        }

        Section {
          OptionalDateFilter(title: "From", date: $dateFrom)
          OptionalDateFilter(title: "To", date: $dateTo)
        } header: {
          Text("Occurrence date")
        } footer: {
          Text(
            "Date filters include overlapping recorded periods in each Entry's time zone. Partial dates may overlap; unanchored dates remain searchable without date filters."
          )
        }

        Section {
          Button("Clear filters", role: .destructive) {
            itemKind = nil
            collectionName = nil
            tagName = nil
            dateFrom = nil
            dateTo = nil
          }
          .disabled(
            itemKind == nil && collectionName == nil && tagName == nil && dateFrom == nil
              && dateTo == nil
          )
        }
      }
      .navigationTitle("Refine Search")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }

        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            controller.selectedItemKind = itemKind
            controller.selectedCollectionName = collectionName
            controller.selectedTagName = tagName
            controller.dateFrom = dateFrom
            controller.dateTo = dateTo
            dismiss()
            Task { await controller.search() }
          }
          .fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

private struct OptionalDateFilter: View {
  let title: String
  @Binding var date: Date?

  var body: some View {
    Toggle(title, isOn: hasDate)

    if date != nil {
      DatePicker(title, selection: selectedDate, displayedComponents: .date)
        .labelsHidden()
    }
  }

  private var hasDate: Binding<Bool> {
    Binding(
      get: { date != nil },
      set: { isEnabled in
        date = isEnabled ? (date ?? Date()) : nil
      }
    )
  }

  private var selectedDate: Binding<Date> {
    Binding(
      get: { date ?? Date() },
      set: { date = $0 }
    )
  }
}
