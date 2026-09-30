import Foundation
@preconcurrency import Supabase
import SwiftUI

struct OrganizationView: View {
  let client: SupabaseClient
  let ownerID: UUID
  @State private var kind: OrganizationKind = .collection
  @State private var query = ""
  @State private var appliedQuery = ""
  @State private var rows: [OrganizationItem] = []
  @State private var selected: OrganizationItem?
  @State private var adding = false
  @State private var busy = false
  @State private var message: String?
  init(client: SupabaseClient, ownerID: UUID, initialKind: OrganizationKind = .collection) {
    self.client = client
    self.ownerID = ownerID
    _kind = State(initialValue: initialKind)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text(
          "Shape the Collections and tags that connect your Entries. Names change everywhere, without duplicating your writing."
        ).foregroundStyle(MTColor.inkMuted)
        Picker("Organization kind", selection: $kind) {
          ForEach(OrganizationKind.allCases) { value in Text(value == .collection ? "Collections" : "Tags").tag(value) }
        }.pickerStyle(.segmented).disabled(busy)
          .onChange(of: kind) { _, _ in
            rows = []
            query = ""
            appliedQuery = ""
            Task { await load() }
          }
        HStack {
          TextField("Search names", text: $query).textFieldStyle(.roundedBorder)
            .onSubmit { Task { await load() } }
          Button("Search") { Task { await load() } }.disabled(busy || query.count > 200)
        }
        Button("Add \(kind.label)", systemImage: "plus") { adding = true }.buttonStyle(.bordered)
          .disabled(busy)
        Text(
          kind == .collection
            ? "Lower order numbers appear first. Removed Collections can be recovered from Library > Trash without losing Entries."
            : "Tags sort alphabetically. Remove a tag from an individual Entry in review."
        )
        .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
        if let message { Text(message).foregroundStyle(MTColor.warm) }
        ForEach(rows) { item in
          Button {
            selected = item
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 8) {
                Text(item.name).font(MTTypography.titleSmall).foregroundStyle(MTColor.ink)
                Text(
                  "\(item.entryCount) \(item.entryCount == 1 ? "Entry" : "Entries")\(kind == .collection ? " · Order \(item.sortOrder)" : "")"
                )
                .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
                if item.systemKey == "bucket_list" {
                  Text("Bucket List Collection").font(MTTypography.caption).foregroundStyle(
                    MTColor.warm)
                }
              }
              Spacer()
              Image(systemName: "chevron.right").foregroundStyle(MTColor.inkMuted)
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
              .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
          }.buttonStyle(.plain).disabled(busy)
        }
        if rows.isEmpty && !busy && message == nil {
          Text("No matching items. Add one or change your search.")
        }
        if rows.count < (rows.first?.totalCount ?? 0) {
          Button("More items") { Task { await load(more: true) } }.disabled(busy)
        }
        if busy { ProgressView() }
      }.padding()
    }.background(MTColor.canvas).navigationTitle(kind == .collection ? "Collections" : "Tags").navigationBarTitleDisplayMode(
      .inline
    )
    .task { await load() }.refreshable { await load() }
    .sheet(
      isPresented: $adding, onDismiss: { Task { await load() } },
      content: {
        OrganizationEditor(client: client, ownerID: ownerID, kind: kind, item: nil)
      }
    )
    .sheet(
      item: $selected, onDismiss: { Task { await load() } },
      content: { item in
        OrganizationEditor(client: client, ownerID: ownerID, kind: kind, item: item)
      })
  }
  private func load(more: Bool = false) async {
    guard !busy, query.count <= 200 else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let search = more ? appliedQuery : query.trimmed
      let next: [OrganizationItem] = try await client.rpc(
        "organization_workspace",
        params: OrganizationReadRequest(
          kind: kind, query: search, offset: more ? rows.count : 0)
      ).execute().value
      if more {
        rows.append(contentsOf: next)
      } else {
        rows = next
        appliedQuery = search
      }
    } catch { message = "Could not load organization settings. Pull to refresh and try again." }
  }
}

private struct OrganizationEditor: View {
  @Environment(\.dismiss) private var dismiss
  let client: SupabaseClient
  let ownerID: UUID
  let kind: OrganizationKind
  let item: OrganizationItem?
  @State private var name: String
  @State private var order: String
  @State private var busy = false
  @State private var message: String?
  @State private var confirmTrash = false
  init(client: SupabaseClient, ownerID: UUID, kind: OrganizationKind, item: OrganizationItem?) {
    self.client = client
    self.ownerID = ownerID
    self.kind = kind
    self.item = item
    _name = State(initialValue: item?.name ?? "")
    _order = State(initialValue: String(item?.sortOrder ?? 0))
  }
  private var input: OrganizationSaveRequest? {
    guard let value = Int(order.trimmed) else { return nil }
    let request = OrganizationSaveRequest(
      kind: kind, name: name, sortOrder: kind == .tag ? 0 : value, id: item?.id,
      expectedRevision: item?.revision)
    return request.isValid ? request : nil
  }
  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
          if kind == .collection { TextField("Order", text: $order).autocorrectionDisabled() }
        } footer: {
          Text(
            "Names can have up to 80 characters. Duplicate names are never silently merged. Collection order is a whole number from -1,000,000 to 1,000,000."
          )
        }
        if item?.systemKey == "bucket_list" {
          Section {
            Text("Bucket List Collection. Renaming preserves its Goal milestone behavior.")
          }
        }
        if item != nil && kind == .collection {
          Section {
            Button("Move to Trash", role: .destructive) { confirmTrash = true }
          } footer: {
            Text(
              "Your Entries and photos stay in the archive. Restore this Collection and its grouping from Library > Trash."
            )
          }
        }
        if let message { Section { Text(message).foregroundStyle(MTColor.warm) } }
      }.disabled(busy).scrollContentBackground(.hidden).background(MTColor.canvas)
        .navigationTitle(item == nil ? "New \(kind.label)" : "Edit \(kind.label)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }.disabled(busy)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(busy ? "Saving…" : "Save") { Task { await save() } }.disabled(
              busy || input == nil)
          }
        }
        .confirmationDialog(
          "Move Collection to Trash?", isPresented: $confirmTrash, titleVisibility: .visible
        ) {
          Button("Move to Trash", role: .destructive) { Task { await save(remove: true) } }
          Button("Cancel", role: .cancel) {}
        } message: {
          Text("Your Entries and photos remain. This grouping can be restored later.")
        }
    }.interactiveDismissDisabled(busy)
  }
  private func save(remove: Bool = false) async {
    guard !busy, remove ? item != nil : input != nil else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let saved: UUID?
      if remove, let item {
        saved = try await client.rpc(
          "trash_collection",
          params: CollectionTrashRequest(id: item.id, expectedRevision: item.revision)
        ).execute().value
      } else if let input {
        saved = try await client.rpc("save_organization", params: input).execute().value
      } else {
        return
      }
      if saved == nil {
        message =
          "This item changed on another device or moved to Trash. Cancel and refresh before editing again."
      } else {
        dismiss()
      }
    } catch let error as PostgrestError where error.code == "23505" {
      message =
        "This name already exists. Choose a different name; nothing was merged or overwritten."
    } catch { message = "Could not save. Your edits are still here to retry." }
  }
}
