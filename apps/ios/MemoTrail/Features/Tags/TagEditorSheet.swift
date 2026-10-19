import SwiftUI

// P8: Tags polish.

/// Web `TagControl`'s dialog: names a tag. A saved tag shows its Entries and merges into another
/// tag, or, once unused, is deleted.
struct TagEditorSheet: View {
  let actions: OrganizationActions
  let item: TagItem?
  /// The other loaded tags, which a used tag can merge into.
  var mergeTargets: [TagItem] = []
  /// Runs after a change saves, before the sheet closes.
  let changed: @MainActor () async -> Void
  /// Asks to open a tag's Entry, or all of its Entries in Library. The sheet closes first, so the
  /// presenter should go there from its `onDismiss`.
  var openEntry: ((SearchEntry) -> Void)? = nil
  var openAllEntries: ((String) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var targetID: UUID?
  @State private var preview: Result<[SearchEntry], OrganizationFailure>?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingRemoval = false
  @State private var isConfirmingMerge = false

  init(
    actions: OrganizationActions, item: TagItem?,
    mergeTargets: [TagItem] = [], changed: @escaping @MainActor () async -> Void,
    openEntry: ((SearchEntry) -> Void)? = nil, openAllEntries: ((String) -> Void)? = nil
  ) {
    self.actions = actions
    self.item = item
    self.mergeTargets = mergeTargets.filter { $0.id != item?.id }
    self.changed = changed
    self.openEntry = openEntry
    self.openAllEntries = openAllEntries
    _name = State(initialValue: item?.name ?? "")
  }

  private var input: TagSaveRequest {
    TagSaveRequest(name: name, id: item?.id, expectedRevision: item?.revision)
  }

  private var mergeTarget: TagItem? { mergeTargets.first { $0.id == targetID } }

  var body: some View {
    MTSheet(
      eyebrow: item == nil ? "New Tag" : "Edit Tag",
      title: item?.name ?? "Create a Tag", closeLabel: "Close tag editor",
      closeIdentifier: "close-organization-editor",
      // Only a saved tag lists its Entries; a new one fits its name field.
      size: item != nil ? .form : .fitted, isBusy: isWorking,
      message: errorMessage
    ) {
      MTFormSection("Tag details") {
        MTTextField(
          label: "Name", text: $name, isRequired: true, maxLength: EntryLimits.tagName
        )
        .textInputAutocapitalization(.never)
        .accessibilityIdentifier("organization-name")
      }
      if let item {
        if item.entryCount > 0 { mergePanel(item) }
        entryPanel(item)
      }
    } accessory: {
      if let item {
        Text("Used by \(countLabel(item.entryCount, "Entry"))")
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkMuted)
      }
    } footer: {
      MTSheetFooter {
        removeButton
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(item == nil ? "Create Tag" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .disabled(!input.isValid)
          .accessibilityIdentifier("save-organization")
      }
    }
    .task {
      if let item, item.entryCount > 0, preview == nil {
        preview = await actions.tagEntryPreviews(item.name)
      }
    }
  }

  /// Delete unused tag, for a tag no Entry uses.
  @ViewBuilder private var removeButton: some View {
    if let item, item.entryCount == 0 {
      Button("Delete unused tag") {
        isConfirmingRemoval = true
      }
      .mtButtonStyle(.danger)
      .accessibilityIdentifier("remove-organization")
      .confirmationDialog(
        "Delete the unused tag “\(item.name)”?",
        isPresented: $isConfirmingRemoval, titleVisibility: .visible
      ) {
        Button("Delete tag", role: .destructive) {
          Task { await remove(item) }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("This tag is unused and will be removed permanently.")
      }
    }
  }

  /// Web's merge panel: a used tag moves every assignment to another tag.
  private func mergePanel(_ item: TagItem) -> some View {
    MTFormSection("Merge this tag", tone: .accent) {
      MTFormNote(
        "This tag is used by \(countLabel(item.entryCount, "Entry")). Merge it to preserve every assignment."
      )
      MTSelectField(
        label: "Destination tag", selection: $targetID,
        options: [nil] + mergeTargets.map(\.id),
        title: { id in
          guard let target = mergeTargets.first(where: { $0.id == id }) else {
            return "Choose a tag"
          }
          return "#\(target.name) (\(target.entryCount))"
        }
      )
      .disabled(mergeTargets.isEmpty)
      .accessibilityIdentifier("merge-tag-target")
      Button("Merge tag") { isConfirmingMerge = true }
        .mtButtonStyle(.secondary)
        .disabled(mergeTarget == nil)
        .accessibilityIdentifier("merge-tag")
        .confirmationDialog(
          "Merge “\(item.name)” into “\(mergeTarget?.name ?? "")”?",
          isPresented: $isConfirmingMerge, titleVisibility: .visible, presenting: mergeTarget
        ) { target in
          Button("Merge tags", role: .destructive) { Task { await merge(item, into: target) } }
          Button("Cancel", role: .cancel) {}
        } message: { target in
          Text("Every Entry will use “\(target.name)” and “\(item.name)” will be removed.")
        }
    }
  }

  /// Web `TagEntryList`: up to five Entries using the tag, and a link to all of them.
  private func entryPanel(_ item: TagItem) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
        Text("Entries using this tag")
          .font(MTFont.listHeading)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Text(countLabel(item.entryCount, "Entry"))
          .font(MTFont.detail)
          .foregroundStyle(MTColor.inkMuted)
        Spacer(minLength: 0)
        if item.entryCount > 5 {
          Text("Showing 5")
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      if item.entryCount == 0 {
        Text("No Entries use this tag yet.")
          .font(MTFont.supporting)
          .foregroundStyle(MTColor.inkMuted)
      } else {
        switch preview {
        case nil:
          VStack(spacing: MTSpacing.s2) {
            ForEach(0..<3, id: \.self) { _ in
              MTLoadingSkeleton(shape: .fill).frame(height: MTSize.Control.medium)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
            }
          }
          .accessibilityElement()
          .accessibilityLabel("Loading tagged Entries")
        case .failure(let failure):
          Text(failure.message)
            .font(MTFont.supporting)
            .foregroundStyle(MTColor.warm)
        case .success(let entries):
          VStack(spacing: 0) {
            ForEach(entries) { entry in
              Button {
                dismiss()
                openEntry?(entry)
              } label: {
                VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
                  Text(entry.displayTitle)
                    .font(MTFont.listHeading)
                    .foregroundStyle(MTColor.ink)
                  Text(
                    entry.displayDate.isEmpty
                      ? entry.identityLabel : "\(entry.identityLabel) · \(entry.displayDate)")
                    .font(MTFont.detail)
                    .foregroundStyle(MTColor.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, MTSpacing.s2)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .overlay(alignment: .bottom) { MTListDivider() }
              .accessibilityElement(children: .combine)
            }
          }
        }
        Button {
          dismiss()
          openAllEntries?(item.name)
        } label: {
          HStack(spacing: MTSpacing.s2) {
            Text("View all Entries for this tag")
            Spacer(minLength: 0)
            Image(.chevron).font(.mtIcon(MTSize.Icon.s13, weight: .semibold))
          }
        }
        .buttonStyle(.plain)
        .font(MTFont.label)
        .foregroundStyle(MTColor.accent)
        .accessibilityIdentifier("view-tag-entries")
      }
    }
    .padding(MTSpacing.s4)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.border)
    }
  }

  private func save() async {
    await run("Tag \(item == nil ? "created" : "saved").") {
      await actions.save(input)
    }
  }

  private func remove(_ item: TagItem) async {
    await run("Tag deleted.") { await actions.deleteUnusedTag(item) }
  }

  private func merge(_ item: TagItem, into target: TagItem) async {
    await run("Tags merged.") { await actions.mergeTags(item, into: target) }
  }

  /// Like Web `run`: the sheet closes with a toast once the change saves, or keeps the edits
  /// with the reason it did not.
  private func run(_ success: String, _ change: () async -> String?) async {
    guard !isWorking else { return }
    isWorking = true
    errorMessage = nil
    let failure = await change()
    if let failure {
      errorMessage = failure
      isWorking = false
      return
    }
    await changed()
    isWorking = false
    MTToastCenter.shared.success(success)
    dismiss()
  }
}
