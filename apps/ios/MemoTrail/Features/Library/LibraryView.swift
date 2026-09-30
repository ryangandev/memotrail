@preconcurrency import Supabase
import SwiftUI

/// Web `/library`: browse organized records, or search across the Life Wiki and Inbox.
struct LibraryView: View {
  private let client: SupabaseClient
  private let user: AuthenticatedUser
  private let isAuthenticationBusy: Bool
  private let signOut: @MainActor () async -> Void
  private var ownerID: UUID { user.id }
  @State private var controller: LibraryController
  @State private var path: [LibraryRoute] = []
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
          eyebrow: "Your Life Wiki", title: "Library",
          description:
            "Browse your organized records, or search across your Life Wiki and Inbox.")
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
        footer
      }
      .scrollDismissesKeyboard(.immediately)
      .refreshable { await controller.load() }
      .navigationTitle("Library")
      .workspaceToolbar(
        client: client, user: user, isAuthenticationBusy: isAuthenticationBusy, signOut: signOut
      )
      .navigationDestination(for: LibraryRoute.self) { route in
        switch route {
        case .item(let link):
          WikiItemDestinationView(client: client, ownerID: ownerID, link: link)
        case .history:
          EntryHistoryIndexView(client: client, ownerID: ownerID)
        }
      }
      .task {
        if !controller.hasLoaded { await controller.load() }
      }
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
        case .collection(let name): controller.collectionName = name
        case .tag(let name): controller.tagName = name
        }
      }
      .onChange(of: controller.filterIdentity) {
        if controller.activeFilterCount > 0 { showsFilters = true }
        searchSoon()
      }
      .onChange(of: controller.query) {
        // Emptying the phrase with no filters returns to browsing, like "Clear all".
        if !controller.hasCriteria, controller.isShowingResults { controller.clearAll() }
      }
    }
  }

  /// Web's search form: the phrase, the Search action, its scope, and the Filters disclosure.
  private var searchSurface: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTSearchField(
        "Search your Life Wiki", text: $controller.query,
        prompt: "A phrase, date, or question about your life...", size: .large, hidesLabel: true,
        maxLength: EntrySearchRequest.queryLimit, focusRequest: searchFocus
      )
      .onSubmit(searchNow)
      Button("Search", action: searchNow)
        .mtButtonStyle(fillsWidth: true)
        .accessibilityIdentifier("library-search")
      VStack(alignment: .leading, spacing: 6) {
        MTBadge(title: "Keyword search", size: .medium)
        Text("Titles, notes, local dates, Collections, tags, and structured details")
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkFaint)
        if controller.hasCriteria || controller.isShowingResults {
          Button("Clear all") {
            pendingSearch?.cancel()
            controller.clearAll()
            showsFilters = false
          }
          .buttonStyle(.plain)
          .font(MTFont.caption.weight(.regular))
          .underline()
          .foregroundStyle(MTColor.accent)
          .frame(minHeight: 32)
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
        withAnimation(.easeOut(duration: MTMotion.quick)) { showsFilters.toggle() }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: 8))
            .rotationEffect(.degrees(showsFilters ? 90 : 0))
          Text(
            controller.activeFilterCount > 0
              ? "Filters · \(controller.activeFilterCount) active" : "Filters")
        }
        .font(MTFont.caption)
        .foregroundStyle(MTColor.accent)
        .frame(minHeight: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(showsFilters ? "Expanded" : "Collapsed")
      .accessibilityIdentifier("library-filters")
      if showsFilters {
        MTFieldGrid(minimumColumnWidth: 220, spacing: MTSpacing.s3) {
          MTSelectField(
            label: "Record", selection: $controller.classification,
            groups: [MTSelectGroup(options: [nil])]
              + WikiItemClassification.groups.map {
                MTSelectGroup(title: $0.title, options: $0.options.map(Optional.some))
              },
            title: { $0?.title ?? "All records" }, size: .small)
          MTSelectField(
            label: "Collection", selection: $controller.collectionName,
            options: [nil] + controller.collectionOptions.map(Optional.some),
            title: { $0 ?? "All Collections" }, size: .small
          )
          .disabled(controller.collectionOptions.isEmpty)
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
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.warm)
      }
    }
    .padding(.top, MTSpacing.s1)
    .overlay(alignment: .top) { MTListDivider() }
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button {
        path.append(.history)
      } label: {
        HStack(spacing: MTSpacing.s2) {
          Image(.clock).font(.system(size: 15))
          Text("Version history")
          Image(.chevron).font(.system(size: 12, weight: .semibold))
        }
        .font(MTFont.caption)
        .foregroundStyle(MTColor.accent)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("library-version-history")
    }
    .padding(.top, MTSpacing.s2)
    .overlay(alignment: .top) { MTListDivider() }
  }

  private func searchNow() {
    pendingSearch?.cancel()
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    pendingSearch = Task { await controller.search() }
  }

  /// Filters apply as they change; a short pause lets date pickers settle first.
  private func searchSoon() {
    pendingSearch?.cancel()
    pendingSearch = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await controller.search()
    }
  }

  /// Web `wikiEntryHref`: Inbox captures open their review, Moments and Periods open on the
  /// Timeline, and other records open their focused page.
  private func open(_ link: WikiItemLink) {
    navigator.open(link) { path.append(.item($0)) }
  }
}

private enum LibraryRoute: Hashable {
  case item(WikiItemLink)
  case history
}

/// Web `LibraryBrowse`: every organized record, newest change first.
private struct LibraryBrowse: View {
  let controller: LibraryController
  let open: (WikiItemLink) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      MTListHeader(
        "All items",
        detail: controller.hasLoaded
          ? "\(controller.totalCount) \(controller.totalCount == 1 ? "item" : "items")" : nil,
        alignsDetailTrailing: true)
      if !controller.hasLoaded {
        ProgressView("Loading your Life Wiki...")
          .font(MTFont.caption)
          .tint(MTColor.accent)
          .frame(maxWidth: .infinity, minHeight: 140)
      } else if let message = controller.errorMessage, controller.items.isEmpty {
        LibraryMessage(title: "Life Wiki unavailable", message: message) {
          Button("Try again") { Task { await controller.loadItems() } }
            .mtButtonStyle(.secondary, size: .small)
        }
      } else if controller.items.isEmpty {
        VStack(spacing: MTSpacing.s2) {
          Text("No matching items")
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
          Text("Try another phrase or category, or capture something new.")
            .font(MTFont.body)
            .foregroundStyle(MTColor.inkMuted)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(MTSpacing.s8)
        .overlay {
          RoundedRectangle(cornerRadius: MTRadius.large)
            .strokeBorder(MTColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
      } else {
        VStack(spacing: 0) {
          ForEach(controller.items) { item in
            LibraryItemRow(item: item) { open(WikiItemLink(item)) }
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

/// One Web `wikiList` row: Kind badges and date, then the serif title and a one-line excerpt.
private struct LibraryItemRow: View {
  let item: WikiItemSummary
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: MTSpacing.s1) {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s4) {
          MTFlowLayout(spacing: MTSpacing.s2) {
            MTBadge(title: item.itemKind.displayName, size: .micro, uppercase: true)
            if item.subtypeLabel != item.itemKind.displayName {
              MTBadge(title: item.subtypeLabel, tone: .neutral, size: .micro, uppercase: true)
            }
          }
          Text(item.dateLabel)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkFaint)
            .lineLimit(1)
            .fixedSize()
        }
        Text(item.title)
          .font(MTFont.cardTitle)
          .foregroundStyle(MTColor.ink)
          .lineLimit(1)
          .padding(.top, 2)
        if !item.excerpt.trimmed.isEmpty {
          Text(item.excerpt)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, MTSpacing.s3)
      .padding(.vertical, MTSpacing.s4)
    }
    .buttonStyle(MTListRowButtonStyle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(item.identityLabel), \(item.title), \(item.dateLabel)")
    .accessibilityHint("Opens this record")
    .accessibilityAddTraits(.isButton)
  }
}

/// Web `SearchResults`: why a search could not run, no matches, or the matching records.
private struct LibraryResults: View {
  let controller: LibraryController
  let open: (WikiItemLink) -> Void

  var body: some View {
    if let message = controller.searchErrorMessage, controller.results.isEmpty {
      LibraryMessage(title: "Search unavailable", message: message)
    } else if controller.results.isEmpty {
      if controller.isSearching {
        ProgressView("Searching your Life Wiki...")
          .font(MTFont.caption)
          .tint(MTColor.accent)
          .frame(maxWidth: .infinity, minHeight: 140)
      } else {
        LibraryMessage(
          title: "No matching items",
          message: "Try fewer words, remove a filter, or search for a broader date.")
      }
    } else {
      VStack(alignment: .leading, spacing: MTSpacing.s3) {
        MTListHeader(
          "Results",
          detail: "\(controller.resultCount) \(controller.resultCount == 1 ? "item" : "items")"
        ) {
          if controller.isSearching {
            ProgressView().controlSize(.small).tint(MTColor.accent)
          }
        }
        MTListSurface {
          ForEach(controller.results) { entry in
            LibraryResultCard(entry: entry) { open(WikiItemLink(entry)) }
            if entry.id != controller.results.last?.id { MTListDivider() }
          }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-results")
      }
    }
  }
}

/// A Web search result card: identity, Inbox state, and date; the title that opens the record;
/// the note clamped to four lines with "Read full note"; organization; and what matched.
private struct LibraryResultCard: View {
  let entry: SearchEntry
  let action: () -> Void
  @State private var showsFullNote = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: action) {
        VStack(alignment: .leading, spacing: 6) {
          MTFlowLayout(spacing: 6) {
            MTBadge(title: entry.identityLabel, tone: .neutral)
            if entry.isInInbox { MTBadge(title: "In Inbox", tone: .warm) }
          }
          Text(entry.displayDate)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkFaint)
          Text(entry.displayTitle)
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .underline(color: MTColor.ink.opacity(0.7))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(entry.identityLabel)\(entry.isInInbox ? ", In Inbox" : ""), \(entry.displayTitle), \(entry.displayDate)"
      )
      .accessibilityHint(entry.isInInbox ? "Opens its Inbox review" : "Opens this record")
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
          withAnimation(.easeOut(duration: MTMotion.quick)) { showsFullNote.toggle() }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "arrowtriangle.right.fill")
              .font(.system(size: 7))
              .rotationEffect(.degrees(showsFullNote ? 90 : 0))
            Text("Read full note")
          }
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.accent)
          .frame(minHeight: 32)
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
      if !entry.collectionNames.isEmpty || !entry.tagNames.isEmpty {
        MTFlowLayout(spacing: 6) {
          ForEach(entry.collectionNames, id: \.self) { MTBadge(title: $0, tone: .neutral) }
          ForEach(entry.tagNames, id: \.self) { MTBadge(title: "#\($0)", tone: .neutral) }
        }
        .padding(.top, MTSpacing.s4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
          "Organization: \((entry.collectionNames + entry.tagNames.map { "#\($0)" }).joined(separator: ", "))"
        )
      }
      if !entry.matchReasons.isEmpty {
        HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
          Text("MATCHED IN")
            .font(.caption2)
            .foregroundStyle(MTColor.inkFaint)
          Text(matchReasons)
            .font(MTFont.caption.weight(.regular))
        }
        .padding(.top, MTSpacing.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
          Rectangle().fill(MTColor.border.opacity(0.7)).frame(height: 1)
        }
        .padding(.top, MTSpacing.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Matched in \(entry.matchReasons.joined(separator: ", "))")
      }
    }
    .padding(MTSpacing.s4)
  }

  /// The reasons in accent, separated by quiet dots.
  private var matchReasons: AttributedString {
    entry.matchReasons.enumerated().reduce(into: AttributedString()) { result, reason in
      if reason.offset > 0 {
        var separator = AttributedString("  ·  ")
        separator.foregroundColor = MTColor.borderStrong
        result += separator
      }
      var text = AttributedString(reason.element)
      text.foregroundColor = MTColor.accent
      result += text
    }
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
        .font(.system(size: 21, weight: .medium))
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
    .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
    .padding(MTSpacing.s6)
    .background(
      MTColor.surfaceSubtle.opacity(0.42), in: RoundedRectangle(cornerRadius: MTRadius.large)
    )
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large)
        .strokeBorder(MTColor.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
    .accessibilityElement(children: .contain)
  }
}

extension LibraryMessage where Actions == EmptyView {
  init(title: String, message: String) {
    self.init(title: title, message: message) { EmptyView() }
  }
}
