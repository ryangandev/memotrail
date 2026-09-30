import SwiftUI

/// Web `PersonEditor` as a form sheet: the Person's details and connected Items, with Move to
/// Trash beside Cancel and Save. Like Web, a Person moves to Trash only once every Item link has
/// been removed and saved.
struct PersonEditorSheet: View {
  let controller: PeopleController
  let person: PersonRecord?
  let onTrashed: (@MainActor () -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var name: String
  @State private var relationship: String
  @State private var notes: String
  @State private var entryIDs: [UUID]
  @State private var selection: UUID?
  @State private var expandedIDs: Set<UUID> = []
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingTrash = false

  init(
    controller: PeopleController, person: PersonRecord?,
    onTrashed: (@MainActor () -> Void)? = nil
  ) {
    self.controller = controller
    self.person = person
    self.onTrashed = onTrashed
    _name = State(initialValue: person?.name ?? "")
    _relationship = State(initialValue: person?.relationshipLabel ?? "")
    _notes = State(initialValue: person?.notes ?? "")
    _entryIDs = State(initialValue: person?.linkedEntries.map(\.id) ?? [])
  }

  var body: some View {
    MTSheet(
      eyebrow: person == nil ? "New Person" : "Edit Person",
      title: person?.name ?? "Keep someone in your story",
      closeLabel: "Close Person editor", closeIdentifier: "close-person-editor",
      isBusy: isWorking, message: errorMessage
    ) {
      MTFormSection("Person details") {
        MTTextField(
          label: "Name", text: $name, isRequired: true, maxLength: PersonSaveInput.nameLimit
        )
        .textInputAutocapitalization(.words)
        .accessibilityIdentifier("person-name")
        MTTextField(
          label: "Relationship", text: $relationship, prompt: "Friend, family, mentor...",
          maxLength: PersonSaveInput.relationshipLimit
        )
        .accessibilityIdentifier("person-relationship")
        MTTextField(
          label: "Notes", text: $notes, maxLength: PersonSaveInput.notesLimit, axis: .vertical,
          lines: 4...12
        )
        .accessibilityIdentifier("person-notes")
      }
      connectionsSection
    } footer: {
      MTSheetFooter {
        trashButton
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(person == nil ? "Add Person" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .accessibilityIdentifier("save-person")
      }
    }
  }

  private var connectionsSection: some View {
    MTFormSection("Connected Items") {
      ForEach(entryIDs, id: \.self) { id in
        linkRow(id)
      }
      // Web sets the picker beside Link Item, and stacks them on phones.
      if horizontalSizeClass == .regular {
        HStack(alignment: .bottom, spacing: MTSpacing.s2) {
          linkPicker
          linkButton
        }
      } else {
        linkPicker
        linkButton
      }
      if let person, !person.linkedEntries.isEmpty {
        MTFormNote(
          "Unlink every Item and save before removing this Person.", color: MTColor.inkFaint)
      }
    }
  }

  /// Web's linked Item `details`: the title opens the Item's text, beside Unlink.
  private func linkRow(_ id: UUID) -> some View {
    let entry = entriesByID[id]
    let title = entry.map { $0.isDeleted ? "\($0.displayTitle) (in Trash)" : $0.displayTitle }
    let isExpanded = expandedIDs.contains(id)
    return HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        Button {
          if isExpanded { expandedIDs.remove(id) } else { expandedIDs.insert(id) }
        } label: {
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
            Image(.chevron)
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(MTColor.inkMuted)
              .rotationEffect(.degrees(isExpanded ? 90 : 0))
            Text(title ?? "Linked Item")
              .font(MTFont.body)
              .foregroundStyle(MTColor.ink)
              .multilineTextAlignment(.leading)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entry?.body.trimmed.nonEmpty == nil)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        if isExpanded, let body = entry?.body.trimmed.nonEmpty {
          Text(body)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 19)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Button("Unlink") {
        entryIDs.removeAll { $0 == id }
        expandedIDs.remove(id)
      }
      .mtButtonStyle(.secondary, size: .small)
      .accessibilityLabel("Unlink \(title ?? "Item")")
    }
    .animation(.snappy(duration: MTMotion.quick), value: isExpanded)
  }

  private var linkPicker: some View {
    let options = availableOptions
    return MTSelectField(
      label: "Link an Item", selection: $selection,
      options: [nil] + options.map { Optional($0.id) },
      title: { id in
        guard let id, let option = options.first(where: { $0.id == id }) else {
          return options.isEmpty ? "No more recent Items" : "Choose from recent Items"
        }
        return option.displayTitle
      }
    )
    .disabled(options.isEmpty)
    .accessibilityIdentifier("person-link-item")
  }

  private var linkButton: some View {
    Button("Link Item") {
      guard let selection else { return }
      entryIDs.append(selection)
      self.selection = nil
    }
    .mtButtonStyle(.secondary, fillsWidth: horizontalSizeClass != .regular)
    .disabled(selection == nil || entryIDs.count >= PersonSaveInput.linkLimit)
    .accessibilityIdentifier("person-link-item-add")
  }

  @ViewBuilder private var trashButton: some View {
    if let person {
      Button("Move to Trash") { isConfirmingTrash = true }
        .mtButtonStyle(.danger)
        .disabled(!person.linkedEntries.isEmpty)
        .accessibilityIdentifier("trash-person")
        .confirmationDialog(
          "Move “\(person.name)” to Trash?", isPresented: $isConfirmingTrash,
          titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await moveToTrash(person) } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("You can restore it later from Trash.")
        }
    }
  }

  /// Like Web, a linked Item's saved details win over the recent Items list.
  private var entriesByID: [UUID: PersonLinkedEntry] {
    var entries = Dictionary(
      controller.linkOptions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    for entry in person?.linkedEntries ?? [] { entries[entry.id] = entry }
    return entries
  }

  private var availableOptions: [PersonLinkedEntry] {
    controller.linkOptions.filter { !entryIDs.contains($0.id) }
  }

  private func save() async {
    isWorking = true
    errorMessage = nil
    defer { isWorking = false }
    let result = await controller.save(
      PersonSaveInput(
        personID: person?.id, expectedRevision: person?.revision, name: name,
        relationshipLabel: relationship, notes: notes, relatedEntryIDs: entryIDs))
    guard result.succeeded else {
      errorMessage = result.message
      return
    }
    MTToastCenter.shared.success(result.message)
    dismiss()
  }

  private func moveToTrash(_ person: PersonRecord) async {
    isWorking = true
    errorMessage = nil
    let result = await controller.moveToTrash(person)
    isWorking = false
    guard result.succeeded else {
      errorMessage = result.message
      return
    }
    MTToastCenter.shared.info(result.message)
    dismiss()
    onTrashed?()
  }
}
