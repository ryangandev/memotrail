@preconcurrency import Supabase
import SwiftUI

/// Web `/library`: browse everything saved, or search it by keyword.
struct LibraryView: View {
  private let client: SupabaseClient
  private let user: AuthenticatedUser
  private let isAuthenticationBusy: Bool
  private let signOut: @MainActor () async -> Void
  private var ownerID: UUID { user.id }
  @State private var controller: LibraryController
  @State private var path: [ItemLink] = []
  @State private var showsFilters = false
  @State private var searchFocus = 0
  @State private var pendingSearch: Task<Void, Never>?
  @Environment(AppNavigator.self) private var navigator

  init(
    client: SupabaseClient, user: AuthenticatedUser, isAuthenticationBusy: Bool,
    signOut: @escaping @MainActor () async -> Void
  ) {
    self.client = client
    self.user = user
    self.isAuthenticationBusy = isAuthenticationBusy
    self.signOut = signOut
    _controller = State(initialValue: LibraryController(client: client, ownerID: user.id))
  }

  var body: some View {
    NavigationStack(path: $path) {
      MTPage(width: .standard) {
        MTPageHeader(
          eyebrow: "Your trail", title: "Library",
          description: "Every Entry you write or import, newest first by the date it happened.")
        searchSurface
        // The next-page trigger is its own page row, so the lazy page creates it only when the
        // end of the list scrolls near.
        if controller.isShowingResults {
          LibraryResults(controller: controller, open: open)
          if !controller.results.isEmpty,
            controller.hasMoreResults || controller.moreResultsErrorMessage != nil
          {
            MTLoadMore(
              isLoading: controller.isLoadingMoreResults,
              message: controller.moreResultsErrorMessage
            ) { await controller.loadMoreResults() }
          }
        } else {
          LibraryBrowse(controller: controller, open: open)
          if !controller.items.isEmpty,
            controller.hasMoreItems || controller.moreItemsErrorMessage != nil
          {
            MTLoadMore(
              isLoading: controller.isLoadingMoreItems,
              message: controller.moreItemsErrorMessage
            ) { await controller.loadMoreItems() }
          }
        }
      }
      .scrollDismissesKeyboard(.immediately)
      .refreshable { await controller.load() }
      .navigationTitle("Library")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .itemDestination(client: client, ownerID: ownerID)
      .task {
        if !controller.hasLoaded { await controller.load() }
      }
      .onChange(of: navigator.entriesRevision) { Task { await controller.load() } }
      .task(id: navigator.librarySearchRequested) {
        guard navigator.librarySearchRequested else { return }
        navigator.librarySearchRequested = false
        path = []
        // Let the tab finish appearing before the keyboard rises.
        try? await Task.sleep(for: .milliseconds(250))
        searchFocus += 1
      }
      .task(id: navigator.libraryFilterRequest) {
        guard let request = navigator.libraryFilterRequest else { return }
        navigator.libraryFilterRequest = nil
        path = []
        // Like Web `/library?tag=`, the one filter replaces any search in progress.
        controller.clearAll()
        switch request {
        case .tag(let name): controller.tagName = name
        case .record(let record): controller.record = record
        }
      }
      .onChange(of: controller.filterIdentity) {
        if controller.activeFilterCount > 0 { showsFilters = true }
        searchSoon()
      }
      .onChange(of: controller.query) {
        // Emptying the phrase with no filters returns to browsing, like "Clear all"; any other
        // change searches once typing pauses.
        if controller.hasCriteria {
          searchSoon(after: LibraryView.typingPause)
        } else if controller.isShowingResults {
          pendingSearch?.cancel()
          controller.clearAll()
        }
      }
    }
  }

  /// Web's search form: the phrase, the Search action, its scope, and the Filters disclosure.
  private var searchSurface: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSearchField(
        "Search Library", text: $controller.query,
        prompt: "Search by words, a name, or a date", size: .large, hidesLabel: true,
        maxLength: EntrySearchRequest.queryLimit, focusRequest: searchFocus
      )
      .onSubmit(searchNow)
      Button("Search", action: searchNow)
        .mtButtonStyle(fillsWidth: true)
        .accessibilityIdentifier("library-search")
      VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
        MTBadge(title: "Keyword search", size: .medium)
        Text("Titles, notes, local dates, tags, and structured details")
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkFaint)
        if controller.hasCriteria || controller.isShowingResults {
          Button("Clear all") {
            pendingSearch?.cancel()
            controller.clearAll()
            showsFilters = false
          }
          .buttonStyle(.plain)
          .font(MTFont.detail)
          .underline()
          .foregroundStyle(MTColor.accent)
          .frame(minHeight: MTLayout.InlineAction.height)
          .contentShape(Rectangle())
          .accessibilityIdentifier("library-clear-search")
        }
      }
      .padding(.top, MTSpacing.s1)
      filters
    }
    .padding(.top, MTSpacing.s2)
  }

  private var filters: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Button {
        withAnimation(MTEasing.enter.animation(duration: MTMotion.quick)) { showsFilters.toggle() }
      } label: {
        HStack(spacing: MTSpacing.s1_5) {
          Image(systemName: "arrowtriangle.right.fill")
            .font(.mtIcon(MTSize.Icon.s8))
            .rotationEffect(.degrees(showsFilters ? 90 : 0))
          Text(
            controller.activeFilterCount > 0
              ? "Filters · \(controller.activeFilterCount) active" : "Filters")
        }
        .font(MTFont.caption)
        .foregroundStyle(MTColor.accent)
        .frame(minHeight: MTLayout.InlineAction.disclosureHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(showsFilters ? "Expanded" : "Collapsed")
      .accessibilityIdentifier("library-filters")
      if showsFilters {
        MTFieldGrid(minimumColumnWidth: 220, spacing: MTSpacing.s3) {
          MTSelectField(
            label: "Record", selection: $controller.record,
            options: [nil] + EntryRecordFilter.allCases.map(Optional.some),
            title: { $0?.title ?? "All records" }, size: .small)
          MTSelectField(
            label: "Tag", selection: $controller.tagName,
            options: [nil] + controller.tagOptions.map(Optional.some),
            title: { $0 ?? "All tags" }, size: .small
          )
          .disabled(controller.tagOptions.isEmpty)
          MTDateField(label: "From", value: $controller.dateFrom, size: .small)
          MTDateField(label: "To", value: $controller.dateTo, size: .small)
        }
        .transition(.opacity)
      }
      if let message = controller.filtersErrorMessage {
        Text(message)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.warm)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, MTSpacing.s1)
    .overlay(alignment: .top) { MTListDivider() }
  }

  private func searchNow() {
    pendingSearch?.cancel()
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    pendingSearch = Task { await controller.search() }
  }

  /// How long typing pauses before the phrase searches by itself; Search and Return search at once.
  private static let typingPause = Duration.milliseconds(400)

  /// Filters apply as they change; a short pause lets date pickers settle first.
  private func searchSoon(after delay: Duration = .milliseconds(300)) {
    pendingSearch?.cancel()
    pendingSearch = Task {
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      await controller.search()
    }
  }

  /// Web `wikiEntryHref`: every row opens its Item page.
  private func open(_ link: ItemLink) {
    path.append(link)
  }
}

/// Web `LibraryBrowse`: every Entry, newest change first.
private struct LibraryBrowse: View {
  let controller: LibraryController
  let open: (ItemLink) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSectionHeader(
        "All Entries", variant: .list,
        detail: controller.hasLoaded
          ? countLabel(controller.totalCount, "Entry") : nil,
        detailAlign: .end)
      if !controller.hasLoaded {
        ProgressView("Loading Library...")
          .font(MTFont.caption)
          .tint(MTColor.accent)
          .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.list)
      } else if let message = controller.errorMessage, controller.items.isEmpty {
        LibraryMessage(title: "Library could not load", message: message) {
          Button("Try again") { Task { await controller.loadItems() } }
            .mtButtonStyle(.secondary, size: .small)
        }
      } else if controller.items.isEmpty {
        VStack(spacing: MTSpacing.s2) {
          Text("No Entries match")
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
          Text("Try another filter or a wider range of dates.")
            .font(MTFont.body)
            .foregroundStyle(MTColor.inkMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(MTSpacing.s8)
        .overlay {
          RoundedRectangle(cornerRadius: MTRadius.large)
            .strokeBorder(
              MTColor.borderStrong,
              style: StrokeStyle(
                lineWidth: MTSize.Stroke.thin,
                dash: [MTLayout.DashedBorder.dash, MTLayout.DashedBorder.gap]))
        }
      } else {
        VStack(spacing: 0) {
          ForEach(controller.items) { item in
            LibraryItemRow(item: item) { open(item.link) }
            MTListDivider()
          }
        }
        .overlay(alignment: .top) { MTListDivider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-items")
      }
    }
  }
}

/// One Web `EntryList` row: a Chapter and First Time badge where they apply and the date, then
/// the serif title and a one-line excerpt. An ordinary Entry carries no badge.
private struct LibraryItemRow: View {
  let item: LibraryRow
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        if item.hasMeta {
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
            if item.marks.isChapter || item.marks.isFirstTime {
              HStack(spacing: MTSpacing.s1_5) {
                if item.marks.isChapter {
                  MTBadge(title: "Chapter", size: .micro, uppercase: true)
                }
                if item.marks.isFirstTime {
                  MTBadge(title: "First Time", tone: .neutral, size: .micro, uppercase: true)
                }
              }
            }
            if let dateLabel = item.dateLabel {
              Text(dateLabel)
                .font(MTFont.detail)
                .foregroundStyle(MTColor.inkFaint)
                .lineLimit(1)
            }
          }
        }
        Text(item.displayTitle)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
          .padding(.top, MTSpacing.s0_5)
        if !item.excerpt.trimmed.isEmpty {
          Text(item.excerpt)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, MTSpacing.s3)
      .padding(.vertical, MTSpacing.s4)
    }
    .buttonStyle(MTListRowButtonStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.accessibilityLabel)
    .accessibilityHint("Opens this Entry")
    .accessibilityAddTraits(.isButton)
  }
}

/// Web `SearchResults`: why a search could not run, no matches, or the matching records.
private struct LibraryResults: View {
  let controller: LibraryController
  let open: (ItemLink) -> Void

  var body: some View {
    if let message = controller.searchErrorMessage, controller.results.isEmpty {
      LibraryMessage(title: "Search unavailable", message: message)
    } else if controller.results.isEmpty {
      if controller.isSearching {
        ProgressView("Searching Library...")
          .font(MTFont.caption)
          .tint(MTColor.accent)
          .frame(maxWidth: .infinity, minHeight: MTLayout.Loading.list)
      } else {
        LibraryMessage(
          title: "No Entries match",
          message: "Try fewer words, another spelling, or remove a filter.")
      }
    } else {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        MTSectionHeader(
          "Results", variant: .list,
          detail: countLabel(controller.resultCount, "Entry")
        ) {
          if controller.isSearching {
            ProgressView().controlSize(.small).tint(MTColor.accent)
          }
        }
        MTListSurface {
          ForEach(controller.results) { entry in
            LibraryResultCard(entry: entry) { open(entry.link) }
            if entry.id != controller.results.last?.id { MTListDivider() }
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-results")
      }
    }
  }
}

/// A Web search result card: identity and date; the title that opens the Entry; the note
/// clamped to four lines with "Read full note"; tags; and what matched.
private struct LibraryResultCard: View {
  let entry: SearchEntry
  let action: () -> Void
  @State private var showsFullNote = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: action) {
        VStack(alignment: .leading, spacing: MTSpacing.s1_5) {
          MTBadge(title: entry.identityLabel, tone: .neutral)
          // An untitled Entry is already named by its date.
          if entry.title != nil {
            Text(entry.displayDate)
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkFaint)
          }
          Text(entry.displayTitle)
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .underline(color: MTColor.inkUnderline)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, MTSpacing.s1_5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(entry.accessibilityLabel)
      .accessibilityHint("Opens this Entry")
      .accessibilityAddTraits(.isButton)

      if !entry.note.isEmpty {
        MTRichTextContent(
          text: entry.note, richText: entry.bodyRich, font: MTFont.body, textStyle: .subheadline,
          color: MTColor.inkMuted, lineLimit: 4
        )
        .padding(.top, MTSpacing.s2)
      }
      if entry.hasLongNote {
        Button {
          withAnimation(MTEasing.enter.animation(duration: MTMotion.quick)) {
            showsFullNote.toggle()
          }
        } label: {
          HStack(spacing: MTSpacing.s1_5) {
            Image(systemName: "arrowtriangle.right.fill")
              .font(.mtIcon(MTSize.Icon.s7))
              .rotationEffect(.degrees(showsFullNote ? 90 : 0))
            Text("Read full note")
          }
          .font(MTFont.detail)
          .foregroundStyle(MTColor.accent)
          .frame(minHeight: MTLayout.InlineAction.height)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsFullNote ? "Expanded" : "Collapsed")
        .padding(.top, MTSpacing.s1)
        if showsFullNote {
          MTRichTextContent(
            text: entry.note, richText: entry.bodyRich, font: MTFont.body,
            textStyle: .subheadline, color: MTColor.inkMuted
          )
          .padding(MTSpacing.s4)
          .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
          .padding(.top, MTSpacing.s2)
        }
      }
      if !entry.tagNames.isEmpty {
        MTFlowLayout(spacing: MTSpacing.s1_5) {
          ForEach(entry.tagNames, id: \.self) { MTBadge(title: "#\($0)", tone: .neutral) }
        }
        .padding(.top, MTSpacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "Organization: \(entry.tagNames.map { "#\($0)" }.joined(separator: ", "))")
      }
      if !entry.matchReasons.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
          Text("MATCHED IN")
            .font(MTFont.note)
            .foregroundStyle(MTColor.inkFaint)
          // Web's reasons: 5 points apart, with quiet dots between neighbors on a line.
          MTFlowLayout(spacing: MTSpacing.s1_25) {
            ForEach(entry.matchReasons, id: \.self) { reason in
              MTFlowSeparator().foregroundStyle(MTColor.borderStrong)
              Text(reason).foregroundStyle(MTColor.accent)
            }
          }
          .font(MTFont.detail)
        }
        .padding(.top, MTSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
          Rectangle().fill(MTColor.borderFaint).frame(height: MTSize.Stroke.thin)
        }
        .padding(.top, MTSpacing.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Matched in \(entry.matchReasons.joined(separator: ", "))")
      }
    }
    .padding(MTSpacing.s4)
  }
}

/// Web's Library message: a dashed, quiet surface with the search icon.
private struct LibraryMessage<Actions: View>: View {
  let title: String
  let message: String
  private let actions: Actions

  init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
    self.title = title
    self.message = message
    self.actions = actions()
  }

  var body: some View {
    HStack(alignment: .top, spacing: MTSpacing.s4) {
      Image(.search)
        .font(.mtIcon(MTSize.Icon.s21, weight: .medium))
        .foregroundStyle(MTColor.accent)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Text(title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
        Text(message)
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(MTLineHeight.body)
        actions.padding(.top, MTSpacing.s1)
      }
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: MTLayout.Library.emptyHeight, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(
      MTColor.surfaceWash, in: RoundedRectangle(cornerRadius: MTRadius.large)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .strokeBorder(
          MTColor.borderStrong,
          style: StrokeStyle(
            lineWidth: MTSize.Stroke.thin,
            dash: [MTLayout.DashedBorder.dash, MTLayout.DashedBorder.gap]))
    }
    .accessibilityElement(children: .contain)
  }
}

extension LibraryMessage where Actions == EmptyView {
  init(title: String, message: String) {
    self.init(title: title, message: message) { EmptyView() }
  }
}
