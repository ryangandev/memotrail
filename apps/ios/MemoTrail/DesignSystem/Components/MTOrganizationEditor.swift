import SwiftUI

/// Shows a record's tags like the Web EntryOrganizationEditor: tag pills with remove buttons,
/// the most used tags as one-tap suggestions while none is added, and the count only once it
/// nears the limit. Adding opens a picker sheet that finds existing names, reusing a tag that
/// differs only by case, or creates new ones, so suggestions stay visible above the keyboard.
struct MTOrganizationEditor: View {
  enum Kind: Sendable {
    case tag

    var title: String { "Tags" }
    var singular: String { "tag" }
    var countLimit: Int { EntryLimits.tagCount }
    var lengthLimit: Int { EntryLimits.tagName }
    fileprivate var icon: MTIcon { .tag }
    fileprivate var identifier: String { "tag" }
  }

  let kind: Kind
  @Binding var names: [String]
  /// The person's names, most used first.
  let options: [String]
  @State private var isPicking = false
  @Environment(\.isEnabled) private var isEnabled

  private var suggestions: [String] {
    names.isEmpty ? EntryTagField.suggestions(names, options: options) : []
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: kind.title)
      MTFlowLayout(spacing: MTSpacing.s2, lineSpacing: MTSpacing.s3) {
        ForEach(names, id: \.self) { name in tagChip(name) }
        if names.count < kind.countLimit { addButton }
      }
      if !suggestions.isEmpty {
        MTFlowLayout(spacing: MTSpacing.s2, lineSpacing: MTSpacing.s2) {
          Text("Most used")
            .font(MTFont.note)
            .foregroundStyle(MTColor.inkFaint)
            .frame(minHeight: MTLayout.InlineAction.height)
            .accessibilityHidden(true)
          ForEach(suggestions, id: \.self) { suggestion($0) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Most used tags")
      }
      if EntryTagField.showsLimit(names) {
        Text("\(names.count) of \(kind.countLimit) \(kind.title.lowercased())")
          .font(MTFont.note)
          .foregroundStyle(MTColor.inkFaint)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .opacity(isEnabled ? 1 : MTState.Disabled.Opacity.choice)
    .sheet(isPresented: $isPicking) {
      MTOrganizationPicker(kind: kind, names: $names, options: options)
    }
  }

  private func tagChip(_ name: String) -> some View {
    HStack(spacing: MTLayout.Organization.tagGap) {
      Text("#\(name)").lineLimit(1)
      Button {
        remove(name)
      } label: {
        Image(.close).font(.mtIcon(MTSize.Icon.s10, weight: .semibold))
          .frame(
            width: MTLayout.Organization.removeButton, height: MTLayout.Organization.removeButton
          )
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(MTColor.inkFaint)
      .accessibilityLabel("Remove \(name) from \(kind.title)")
    }
    .font(MTFont.caption)
    .foregroundStyle(MTColor.accent)
    .padding(.leading, MTLayout.Organization.tagLeading)
    .padding(.trailing, MTLayout.Organization.tagTrailing)
    .frame(minHeight: MTLayout.InlineAction.height)
    .background(MTColor.accentSubtle, in: Capsule())
    .overlay { Capsule().strokeBorder(MTColor.accentBorder, lineWidth: MTSize.Stroke.thin) }
  }

  private var addButton: some View {
    Button {
      isPicking = true
    } label: {
      Label("Add \(kind.singular)", icon: .plus)
        .labelStyle(MTInlineIconLabelStyle())
        .font(MTFont.caption)
        .foregroundStyle(MTColor.inkMuted)
        .padding(.leading, MTSpacing.s2)
        .padding(.trailing, MTSpacing.s3)
        .frame(minHeight: MTLayout.InlineAction.height)
        .background {
          Capsule()
            .strokeBorder(
              style: StrokeStyle(
                lineWidth: MTSize.Stroke.thin,
                dash: [MTLayout.DashedBorder.dot, MTLayout.DashedBorder.gap])
            )
            .foregroundStyle(MTColor.borderStrong)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("organization-add-\(kind.identifier)")
  }

  /// A most used name that one tap adds, written the way it already is.
  private func suggestion(_ name: String) -> some View {
    Button {
      if names.count < kind.countLimit,
        !names.contains(where: { $0.lowercased() == name.lowercased() })
      {
        names.append(name)
      }
    } label: {
      Label(name, icon: .plus)
        .labelStyle(MTInlineIconLabelStyle())
        .lineLimit(1)
        .font(MTFont.caption)
        .foregroundStyle(MTColor.inkMuted)
        .padding(.leading, MTSpacing.s2)
        .padding(.trailing, MTSpacing.s3)
        .frame(minHeight: MTLayout.InlineAction.height)
        .background(MTColor.surfaceSubtle, in: Capsule())
        .overlay { Capsule().strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Add \(kind.singular) \(name)")
  }

  private func remove(_ name: String) {
    names.removeAll { $0 == name }
  }
}

/// Finds existing names or creates a new one. Selections apply immediately; Done also adds
/// text still in the search field, like pending input on the Web review.
private struct MTOrganizationPicker: View {
  let kind: MTOrganizationEditor.Kind
  @Binding var names: [String]
  let options: [String]
  @State private var query = ""
  @FocusState private var isSearching: Bool
  @Environment(\.dismiss) private var dismiss

  private var text: String { query.trimmed }
  private var isFull: Bool { names.count >= kind.countLimit }

  private func isSelected(_ name: String) -> Bool {
    names.contains { $0.lowercased() == name.lowercased() }
  }

  /// Selected names first, then unused options, filtered by the search text.
  private var rows: [String] {
    var seen = Set<String>()
    return (names + options).filter { name in
      seen.insert(name.lowercased()).inserted
        && (text.isEmpty || name.localizedCaseInsensitiveContains(text))
    }
  }

  private var canCreate: Bool {
    !text.isEmpty && text.count <= kind.lengthLimit && !isFull
      && !(names + options).contains { $0.lowercased() == text.lowercased() }
  }

  var body: some View {
    NavigationStack {
      List {
        if canCreate {
          Button {
            addText()
          } label: {
            HStack(spacing: MTSpacing.s2) {
              Image(.plus).font(.mtIcon(MTSize.Icon.s14, weight: .medium)).frame(
                width: MTLayout.Organization.rowIcon)
              Text("Create \(kind.singular.lowercased())")
              Spacer(minLength: MTSpacing.s2)
              Text(text)
                .font(MTFont.caption)
                .foregroundStyle(MTColor.inkMuted)
                .lineLimit(1)
            }
            .font(MTFont.body)
            .foregroundStyle(MTColor.accent)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .listRowBackground(MTColor.accentSubtle)
          .accessibilityIdentifier("organization-create")
        }
        Section {
          ForEach(rows, id: \.self, content: row)
        } footer: {
          Text(
            isFull
              ? "You can add up to \(kind.countLimit) \(kind.title.lowercased())."
              : "\(names.count) of \(kind.countLimit)")
        }
      }
      .scrollContentBackground(.hidden)
      .background(MTColor.canvas)
      .safeAreaInset(edge: .top, spacing: 0) {
        searchField
          .padding(.horizontal, MTSpacing.s4)
          .padding(.vertical, MTSpacing.s3)
          .background(MTColor.canvas)
      }
      .overlay {
        if rows.isEmpty, !canCreate {
          ContentUnavailableView(
            text.isEmpty ? "No \(kind.title.lowercased()) yet" : "No matches",
            systemImage: kind.icon.systemName,
            description: Text(
              text.isEmpty
                ? "Type a name to create the first one."
                : "Names are limited to \(kind.lengthLimit) characters."))
        }
      }
      .navigationTitle(kind.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            addText()
            dismiss()
          }
          .accessibilityIdentifier("organization-done")
        }
      }
    }
    // Search takes focus at once, so the picker opens full height: a medium sheet would jump
    // above the keyboard and leave room for only one row.
    .presentationDetents([.large])
    .onAppear { isSearching = true }
    // A name left in the search field stays, as on Web, even when the sheet is swiped away.
    .onDisappear { addText() }
  }

  private var searchField: some View {
    let tone = MTColor.accent
    let shape = RoundedRectangle(cornerRadius: MTLayout.Organization.tagSearchRadius)
    return HStack(spacing: MTSpacing.s2) {
      Image(.search).font(.mtIcon(MTSize.Icon.s15, weight: .medium))
      TextField(
        "Search or create a \(kind.singular)", text: $query,
        prompt: Text("Find or create \(kind.singular.lowercased())").foregroundStyle(
          MTColor.accentPrompt)
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.ink)
      .textInputAutocapitalization(.never)
      .autocorrectionDisabled()
      .submitLabel(.done)
      .focused($isSearching)
      .onSubmit {
        addText()
        isSearching = true
      }
      .onChange(of: query) {
        if query.count > kind.lengthLimit { query = String(query.prefix(kind.lengthLimit)) }
        // Tags also add on a comma, as on the Web.
        if query.hasSuffix(",") {
          query.removeLast()
          addText()
        }
      }
      .accessibilityIdentifier("organization-search-\(kind.identifier)")
    }
    .foregroundStyle(tone)
    .padding(.horizontal, MTSpacing.s3)
    .frame(height: MTSize.Field.medium)
    .background(MTColor.surfaceRaised, in: shape)
    .overlay { shape.strokeBorder(tone, lineWidth: MTSize.Stroke.thin) }
    .background { shape.stroke(MTState.Focus.halo, lineWidth: MTState.Focus.haloStroke) }
  }

  private func row(_ name: String) -> some View {
    let selected = isSelected(name)
    return Button {
      toggle(name)
    } label: {
      HStack(spacing: MTSpacing.s2) {
        Image(kind.icon).font(.mtIcon(MTSize.Icon.s14, weight: .medium)).frame(
          width: MTLayout.Organization.rowIcon
        )
        .foregroundStyle(MTColor.inkMuted)
        Text(name).foregroundStyle(MTColor.ink).lineLimit(1)
        Spacer(minLength: MTSpacing.s2)
        if selected {
          Image(.check).font(.mtIcon(MTSize.Icon.s14, weight: .semibold)).foregroundStyle(
            MTColor.accent)
        }
      }
      .font(MTFont.body)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!selected && isFull)
    .listRowBackground(MTColor.surface)
    .accessibilityLabel(name)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func toggle(_ name: String) {
    if isSelected(name) {
      names.removeAll { $0.lowercased() == name.lowercased() }
    } else if !isFull {
      names.append(name)
      // A picked suggestion finishes the search, as on the Web.
      query = ""
    }
  }

  /// Adds the search text as a new name, or selects the existing option it names.
  private func addText() {
    guard !text.isEmpty, text.count <= kind.lengthLimit, !isFull else { return }
    if let existing = options.first(where: { $0.lowercased() == text.lowercased() }) {
      if !isSelected(existing) { names.append(existing) }
    } else if !isSelected(text) {
      names.append(text)
    }
    query = ""
  }
}

/// An icon and title with tight spacing, used inside compact controls.
struct MTInlineIconLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: MTSpacing.s1) {
      configuration.icon.font(.mtIcon(MTSize.Icon.s13, weight: .medium))
      configuration.title
    }
  }
}
