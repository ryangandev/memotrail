import SwiftUI

/// Web `OrganizationControl`'s dialog: names a Collection or tag and sets a Collection's display
/// order. A saved Collection moves to Trash from here; a saved tag shows its Entries and merges
/// into another tag, or, once unused, is deleted.
struct OrganizationEditorSheet: View {
  let actions: OrganizationActions
  let kind: OrganizationKind
  let item: OrganizationItem?
  /// The other loaded tags, which a used tag can merge into.
  var mergeTargets: [OrganizationItem] = []
  /// Runs after a change saves, before the sheet closes.
  let changed: @MainActor () async -> Void
  /// Asks to open a tag's Entry, or all of its Entries in Library. The sheet closes first, so the
  /// presenter should go there from its `onDismiss`.
  var openEntry: ((SearchEntry) -> Void)? = nil
  var openAllEntries: ((String) -> Void)? = nil

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var order: String
  @State private var targetID: UUID?
  @State private var preview: Result<[SearchEntry], OrganizationFailure>?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isConfirmingRemoval = false
  @State private var isConfirmingMerge = false

  init(
    actions: OrganizationActions, kind: OrganizationKind, item: OrganizationItem?,
    mergeTargets: [OrganizationItem] = [], changed: @escaping @MainActor () async -> Void,
    openEntry: ((SearchEntry) -> Void)? = nil, openAllEntries: ((String) -> Void)? = nil
  ) {
    self.actions = actions
    self.kind = kind
    self.item = item
    self.mergeTargets = mergeTargets.filter { $0.id != item?.id }
    self.changed = changed
    self.openEntry = openEntry
    self.openAllEntries = openAllEntries
    _name = State(initialValue: item?.name ?? "")
    _order = State(initialValue: String(item?.sortOrder ?? 0))
  }

  private var input: OrganizationSaveRequest {
    OrganizationSaveRequest(
      kind: kind, name: name, sortOrder: kind == .tag ? 0 : Int(order.trimmed) ?? .max,
      id: item?.id, expectedRevision: item?.revision)
  }

  private var mergeTarget: OrganizationItem? { mergeTargets.first { $0.id == targetID } }

  var body: some View {
    MTSheet(
      eyebrow: "\(item == nil ? "New" : "Edit") \(kind.label)",
      title: item?.name ?? "Create a \(kind.label)", closeLabel: "Close organization editor",
      closeIdentifier: "close-organization-editor",
      // Only a saved tag lists its Entries; the other forms fit their few fields.
      size: kind == .tag && item != nil ? .form : .fitted, isBusy: isWorking,
      message: errorMessage
    ) {
      MTFormSection("\(kind.label) details") {
        MTTextField(
          label: "Name", text: $name, isRequired: true, maxLength: kind.nameLimit
        )
        .textInputAutocapitalization(kind == .tag ? .never : .words)
        .accessibilityIdentifier("organization-name")
        if kind == .collection {
          MTTextField(label: "Display order", text: $order, isRequired: true, maxLength: 8)
            .keyboardType(.numbersAndPunctuation)
            .accessibilityIdentifier("organization-order")
        }
        if item?.isBucketList == true {
          MTFormNote(
            "This is your Bucket List Collection. Renaming it preserves Goal milestone behavior.")
        }
      }
      if let item, kind == .tag {
        if item.entryCount > 0 { mergePanel(item) }
        entryPanel(item)
      }
    } accessory: {
      if let item, kind == .tag {
        Text("Used by \(countLabel(item.entryCount, "Entry"))")
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
      }
    } footer: {
      MTSheetFooter {
        removeButton
      } cancel: {
        Button("Cancel") { dismiss() }
          .mtButtonStyle(.secondary)
      } primary: {
        Button(item == nil ? "Create \(kind.label)" : "Save changes") { Task { await save() } }
          .mtButtonStyle(isLoading: isWorking)
          .disabled(!input.isValid)
          .accessibilityIdentifier("save-organization")
      }
    }
    .task {
      if let item, kind == .tag, item.entryCount > 0, preview == nil {
        preview = await actions.tagEntryPreviews(item.name)
      }
    }
  }

  /// Move to Trash for a Collection, or Delete unused tag for a tag no Entry uses.
  @ViewBuilder private var removeButton: some View {
    if let item, kind == .collection || item.entryCount == 0 {
      Button(kind == .collection ? "Move to Trash" : "Delete unused tag") {
        isConfirmingRemoval = true
      }
      .mtButtonStyle(.danger)
      .accessibilityIdentifier("remove-organization")
      .confirmationDialog(
        kind == .collection
          ? "Move “\(item.name)” to Trash?" : "Delete the unused tag “\(item.name)”?",
        isPresented: $isConfirmingRemoval, titleVisibility: .visible
      ) {
        Button(kind == .collection ? "Move to Trash" : "Delete tag", role: .destructive) {
          Task { await remove(item) }
        }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(
          kind == .collection
            ? "Entries stay in your archive and the Collection can be restored."
            : "This tag is unused and will be removed permanently.")
      }
    }
  }

  /// Web's merge panel: a used tag moves every assignment to another tag.
  private func mergePanel(_ item: OrganizationItem) -> some View {
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
  private func entryPanel(_ item: OrganizationItem) -> some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s2) {
        Text("Entries using this tag")
          .font(MTFont.label.weight(.semibold))
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Text(countLabel(item.entryCount, "Entry"))
          .font(MTFont.caption.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
        Spacer(minLength: 0)
        if item.entryCount > 5 {
          Text("Showing 5")
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkFaint)
        }
      }
      if item.entryCount == 0 {
        Text("No Entries use this tag yet.")
          .font(MTFont.label.weight(.regular))
          .foregroundStyle(MTColor.inkMuted)
      } else {
        switch preview {
        case nil:
          VStack(spacing: MTSpacing.s2) {
            ForEach(0..<3, id: \.self) { _ in
              MTLoadingSkeleton().frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
            }
          }
          .accessibilityElement()
          .accessibilityLabel("Loading tagged Entries")
        case .failure(let failure):
          Text(failure.message)
            .font(MTFont.label.weight(.regular))
            .foregroundStyle(MTColor.warm)
        case .success(let entries):
          VStack(spacing: 0) {
            ForEach(entries) { entry in
              Button {
                dismiss()
                openEntry?(entry)
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(entry.displayTitle)
                    .font(MTFont.label.weight(.semibold))
                    .foregroundStyle(MTColor.ink)
                  Text("\(entry.identityLabel) · \(entry.displayDate)")
                    .font(MTFont.caption.weight(.regular))
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
            Image(.chevron).font(.system(size: 13, weight: .semibold))
          }
        }
        .buttonStyle(.plain)
        .font(MTFont.label.weight(.medium))
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
    await run("\(kind.label) \(item == nil ? "created" : "saved").") {
      await actions.save(input)
    }
  }

  private func remove(_ item: OrganizationItem) async {
    await run(kind == .collection ? "Collection moved to Trash." : "Tag deleted.") {
      kind == .collection
        ? await actions.trashCollection(item) : await actions.deleteUnusedTag(item)
    }
  }

  private func merge(_ item: OrganizationItem, into target: OrganizationItem) async {
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
