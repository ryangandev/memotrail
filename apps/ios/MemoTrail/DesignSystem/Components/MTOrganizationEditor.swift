import SwiftUI

/// Shows a record's Collections or tags like the Web EntryOrganizationEditor: tag pills and
/// ledger-style Collection chips with remove buttons. Adding opens a picker sheet that finds
/// existing names or creates new ones, so suggestions stay visible above the keyboard.
struct MTOrganizationEditor: View {
  enum Kind: Sendable {
    case collection, tag

    var title: String { self == .collection ? "Collections" : "Tags" }
    var singular: String { self == .collection ? "Collection" : "tag" }
    var countLimit: Int { self == .collection ? 20 : 50 }
    var lengthLimit: Int { self == .collection ? 80 : 60 }
    fileprivate var icon: MTIcon { self == .collection ? .archive : .tag }
    fileprivate var identifier: String { self == .collection ? "collection" : "tag" }
  }

  let kind: Kind
  @Binding var names: [String]
  let options: [String]
  @State private var isPicking = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      MTFieldLabel(title: kind.title)
      MTFlowLayout(spacing: MTSpacing.s2, lineSpacing: MTSpacing.s3) {
        ForEach(names, id: \.self) { name in
          if kind == .tag { tagChip(name) } else { collectionChip(name) }
        }
        if names.count < kind.countLimit { addButton }
      }
      // Collection bookends and remove buttons extend above their chips.
      .padding(.top, kind == .collection ? MTSpacing.s2 : 0)
      Text("\(names.count) of \(kind.countLimit)")
        .font(.caption2)
        .foregroundStyle(MTColor.inkFaint)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("\(names.count) of \(kind.countLimit) \(kind.title)")
    }
    .opacity(isEnabled ? 1 : 0.56)
    .sheet(isPresented: $isPicking) {
      MTOrganizationPicker(kind: kind, names: $names, options: options)
    }
  }

  private func tagChip(_ name: String) -> some View {
    HStack(spacing: 3) {
      Text("#\(name)").lineLimit(1)
      Button {
        remove(name)
      } label: {
        Image(.close).font(.system(size: 10, weight: .semibold))
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(MTColor.inkFaint)
      .accessibilityLabel("Remove \(name) from \(kind.title)")
    }
    .font(MTFont.caption)
    .foregroundStyle(MTColor.accent)
    .padding(.leading, 10)
    .padding(.trailing, 3)
    .frame(minHeight: 32)
    .background(MTColor.accentSubtle, in: Capsule())
    .overlay { Capsule().strokeBorder(MTColor.accent.opacity(0.34), lineWidth: 1) }
  }

  private func collectionChip(_ name: String) -> some View {
    Text(name)
      .font(.system(.footnote, design: .serif))
      .foregroundStyle(MTColor.ink)
      .lineLimit(1)
      .padding(.vertical, 7)
      .padding(.horizontal, MTSpacing.s6)
      .frame(minHeight: 40)
      .background {
        ZStack {
          MTColor.warmSubtle
          LinearGradient(
            stops: [
              .init(color: MTColor.surfaceRaised.opacity(0.34), location: 0),
              .init(color: .clear, location: 0.44),
              .init(color: .clear, location: 0.58),
              .init(color: MTColor.warm.opacity(0.12), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .shadow(color: MTColor.warm.opacity(0.12), radius: 4, y: 3)
      }
      .overlay {
        VStack {
          Rectangle().fill(MTColor.warm.opacity(0.48)).frame(height: 1)
          Spacer()
          Rectangle().fill(MTColor.warm.opacity(0.48)).frame(height: 1)
        }
      }
      .overlay {
        HStack {
          bookend
          Spacer()
          bookend
        }
      }
      .overlay(alignment: .topTrailing) {
        Button {
          remove(name)
        } label: {
          Image(.close).font(.system(size: 10, weight: .semibold))
            .foregroundStyle(MTColor.inkMuted)
            .frame(width: 22, height: 22)
            .background(MTColor.surfaceRaised, in: Circle())
            .overlay { Circle().strokeBorder(MTColor.borderStrong, lineWidth: 1) }
            .mtShadow(MTShadow.raised)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: 13, y: -13)
        .accessibilityLabel("Remove \(name) from \(kind.title)")
      }
      .padding(.trailing, MTSpacing.s2)
      .accessibilityElement(children: .contain)
  }

  private var bookend: some View {
    Rectangle()
      .fill(MTColor.warmSubtle)
      .overlay { Rectangle().strokeBorder(MTColor.warm, lineWidth: 2) }
      .frame(width: 8)
      .padding(.vertical, -3)
  }

  private var addButton: some View {
    Button {
      isPicking = true
    } label: {
      Label("Add \(kind.singular)", icon: .plus)
        .labelStyle(MTInlineIconLabelStyle())
        .font(MTFont.caption)
        .foregroundStyle(MTColor.inkMuted)
        .padding(.leading, kind == .collection ? 11 : 8)
        .padding(.trailing, MTSpacing.s3)
        .frame(minHeight: kind == .collection ? 38 : 32)
        .background {
          if kind == .collection {
            Rectangle()
              .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
              .foregroundStyle(MTColor.warm.opacity(0.54))
          } else {
            Capsule()
              .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
              .foregroundStyle(MTColor.borderStrong)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("organization-add-\(kind.identifier)")
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
              Image(.plus).font(.system(size: 14, weight: .medium)).frame(width: 20)
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
  }

  private var searchField: some View {
    let tone = kind == .tag ? MTColor.accent : MTColor.warm
    let shape = RoundedRectangle(cornerRadius: kind == .tag ? 22 : 2)
    return HStack(spacing: MTSpacing.s2) {
      Image(.search).font(.system(size: 15, weight: .medium))
      TextField(
        "Search or create a \(kind.singular)", text: $query,
        prompt: Text("Find or create \(kind.singular.lowercased())").foregroundStyle(
          tone.opacity(0.6))
      )
      .font(MTFont.body)
      .foregroundStyle(MTColor.ink)
      .textInputAutocapitalization(kind == .tag ? .never : .words)
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
        if kind == .tag, query.hasSuffix(",") {
          query.removeLast()
          addText()
        }
      }
      .accessibilityIdentifier("organization-search-\(kind.identifier)")
    }
    .foregroundStyle(tone)
    .padding(.leading, kind == .collection ? MTSpacing.s4 : MTSpacing.s3)
    .padding(.trailing, MTSpacing.s3)
    .frame(height: 44)
    .background(MTColor.surfaceRaised, in: shape)
    .overlay {
      if kind == .collection {
        HStack {
          Rectangle().fill(tone).frame(width: 4)
          Spacer()
        }
        .clipShape(shape)
      }
    }
    .overlay { shape.strokeBorder(tone, lineWidth: 1) }
    .background {
      if kind == .tag {
        shape.stroke(MTColor.accentSubtle, lineWidth: 6)
      } else {
        shape.fill(MTColor.borderStrong).offset(x: 3, y: 3)
      }
    }
  }

  private func row(_ name: String) -> some View {
    let selected = isSelected(name)
    return Button {
      toggle(name)
    } label: {
      HStack(spacing: MTSpacing.s2) {
        Image(kind.icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
          .foregroundStyle(MTColor.inkMuted)
        Text(name).foregroundStyle(MTColor.ink).lineLimit(1)
        Spacer(minLength: MTSpacing.s2)
        if selected {
          Image(.check).font(.system(size: 14, weight: .semibold)).foregroundStyle(MTColor.accent)
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
      configuration.icon.font(.system(size: 13, weight: .medium))
      configuration.title
    }
  }
}
