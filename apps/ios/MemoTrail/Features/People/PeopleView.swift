import Foundation
import Observation
@preconcurrency import Supabase
import SwiftUI

struct PersonLinkedEntry: Codable, Identifiable, Sendable {
  let id: UUID
  let title: String?
  let body: String
  let itemKind: WikiItemKind
  let itemSubtype: String
  let is_deleted: Bool?

  enum CodingKeys: String, CodingKey {
    case id, title, body
    case itemKind = "item_kind"
    case itemSubtype = "item_subtype"
    case is_deleted
  }

  var displayTitle: String {
    title?.trimmed.nonEmpty ?? body.trimmed.nonEmpty.map { String($0.prefix(80)) }
      ?? "Untitled Entry"
  }
}

struct PersonRecord: Decodable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let relationship_label: String?
  let notes: String?
  let revision: Int
  let linked_entries: [PersonLinkedEntry]
  let total_count: Int
}

struct PersonSaveInput: Encodable, Sendable {
  let p_person_id: UUID?
  let p_expected_revision: Int?
  let p_name: String
  let p_relationship_label: String
  let p_notes: String
  let p_related_entry_ids: [UUID]

  var isValid: Bool {
    !p_name.trimmed.isEmpty && p_name.trimmed.count <= 200
      && p_relationship_label.count <= 200 && p_notes.count <= 10_000
      && p_related_entry_ids.count <= 100
      && ((p_person_id == nil && p_expected_revision == nil)
        || (p_person_id != nil && (p_expected_revision ?? 0) > 0))
  }

  enum CodingKeys: String, CodingKey {
    case p_person_id, p_expected_revision, p_name, p_relationship_label, p_notes,
      p_related_entry_ids
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(p_person_id, forKey: .p_person_id)
    try values.encode(p_expected_revision, forKey: .p_expected_revision)
    try values.encode(p_name.trimmed, forKey: .p_name)
    try values.encode(p_relationship_label.trimmed, forKey: .p_relationship_label)
    try values.encode(p_notes.trimmed, forKey: .p_notes)
    try values.encode(p_related_entry_ids, forKey: .p_related_entry_ids)
  }
}

@MainActor @Observable
final class PeopleController {
  private(set) var people: [PersonRecord] = []
  private(set) var entries: [PersonLinkedEntry] = []
  private(set) var loading = false
  private(set) var saving = false
  private(set) var error: String?
  private(set) var hasMore = false
  private let client: SupabaseClient
  private let ownerID: UUID
  private let focusedPersonID: UUID?

  init(client: SupabaseClient, ownerID: UUID, focusedPersonID: UUID? = nil) {
    self.client = client
    self.ownerID = ownerID
    self.focusedPersonID = focusedPersonID
  }

  func load(more: Bool = false) async {
    guard !loading else { return }
    loading = true
    error = nil
    defer { loading = false }
    do {
      try await checkOwner()
      let offset = more ? people.count : 0
      let rows: [PersonRecord]
      if let focusedPersonID {
        rows = try await client.rpc(
          "person_record", params: ["p_person_id": focusedPersonID.uuidString]
        ).execute().value
      } else {
        rows = try await client.rpc(
          "people_workspace", params: ["p_limit": 100, "p_offset": offset]
        ).execute().value
      }
      let options: [PersonLinkedEntry] = try await client.from("entries")
        .select("id,title,body,item_kind,item_subtype").eq("owner_id", value: ownerID.uuidString)
        .is("deleted_at", value: nil).order("updated_at", ascending: false).limit(200)
        .execute().value
      if more { people.append(contentsOf: rows) } else { people = rows }
      entries = options
      hasMore = people.count < (rows.first?.total_count ?? people.count)
      if focusedPersonID != nil && rows.isEmpty {
        error = "This Person is unavailable or in Trash."
      }
    } catch {
      self.error = "Could not load People. Pull to refresh or try again."
    }
  }

  func save(_ input: PersonSaveInput) async -> String? {
    guard input.isValid else {
      return
        "Add a name up to 200 characters, a relationship up to 200, notes up to 10,000, and at most 100 links."
    }
    guard !saving else { return "Another change is saving." }
    saving = true
    defer { saving = false }
    do {
      try await checkOwner()
      let rows: [PersonMutation] = try await client.rpc("save_person", params: input).execute()
        .value
      guard !rows.isEmpty else {
        return "This Person changed on another device. Close and refresh before editing again."
      }
      await load()
      return nil
    } catch { return "Could not save this Person. Your edits are still here; try again." }
  }

  func trash(_ person: PersonRecord) async -> String? {
    guard !saving else { return "Another change is saving." }
    saving = true
    defer { saving = false }
    do {
      try await checkOwner()
      let rows: [PersonMutation] = try await client.rpc(
        "trash_person",
        params: PersonTrashInput(p_person_id: person.id, p_expected_revision: person.revision)
      ).execute().value
      guard !rows.isEmpty else {
        return "This Person changed or still has Entry links. Unlink, save, and try again."
      }
      await load()
      return nil
    } catch { return "Could not move this Person to Trash. Try again." }
  }

  private func checkOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

private struct PersonMutation: Decodable {
  let person_id: UUID
  let revision: Int
}
private struct PersonTrashInput: Encodable {
  let p_person_id: UUID
  let p_expected_revision: Int
}
private struct PersonSelection: Identifiable {
  let id = UUID()
  let person: PersonRecord?
}

struct PeopleView: View {
  @State private var controller: PeopleController
  @State private var selection: PersonSelection?

  init(client: SupabaseClient, ownerID: UUID, focusedPersonID: UUID? = nil) {
    _controller = State(
      initialValue: PeopleController(
        client: client, ownerID: ownerID, focusedPersonID: focusedPersonID))
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: MTSpacing.s4) {
        Text("THE PEOPLE IN YOUR STORY").font(MTTypography.caption).foregroundStyle(MTColor.warm)
        Text("People").font(MTTypography.display).foregroundStyle(MTColor.ink)
        Text("Keep a little context for the people who shaped each chapter.")
          .font(MTTypography.body).foregroundStyle(MTColor.inkMuted)
        if let error = controller.error { Text(error).foregroundStyle(MTColor.warm) }
        if controller.loading { ProgressView() }
        if !controller.loading && controller.people.isEmpty && controller.error == nil {
          ContentUnavailableView(
            "No People yet", systemImage: "person.2",
            description: Text("Add a name, then connect the Entries you share."))
        }
        ForEach(controller.people) { person in
          Button {
            selection = PersonSelection(person: person)
          } label: {
            VStack(alignment: .leading, spacing: MTSpacing.s2) {
              Label(person.name, systemImage: "person.crop.circle").font(MTTypography.titleSmall)
              Text(person.relationship_label ?? "A person in your story").font(MTTypography.caption)
              if let notes = person.notes { Text(notes).font(MTTypography.body).lineLimit(3) }
              Text("\(person.linked_entries.count) connected Entries").font(MTTypography.caption)
            }
            .foregroundStyle(MTColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading).padding(MTSpacing.s4)
            .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
            .overlay(RoundedRectangle(cornerRadius: MTRadius.large).stroke(MTColor.border))
          }.buttonStyle(.plain)
        }
        if controller.hasMore {
          Button("Load more") { Task { await controller.load(more: true) } }.disabled(
            controller.loading)
        }
      }.padding(MTSpacing.s4)
    }
    .background(MTColor.canvas).navigationTitle("People").navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button("Add Person", systemImage: "plus") { selection = PersonSelection(person: nil) }
    }
    .task { await controller.load() }.refreshable { await controller.load() }
    .sheet(item: $selection) { value in PersonEditor(controller: controller, person: value.person) }
  }
}

private struct PersonEditor: View {
  @Environment(\.dismiss) private var dismiss
  let controller: PeopleController
  let person: PersonRecord?
  @State private var name: String
  @State private var relationship: String
  @State private var notes: String
  @State private var entryIDs: [UUID]
  @State private var message: String?
  @State private var confirmsTrash = false

  init(controller: PeopleController, person: PersonRecord?) {
    self.controller = controller
    self.person = person
    _name = State(initialValue: person?.name ?? "")
    _relationship = State(initialValue: person?.relationship_label ?? "")
    _notes = State(initialValue: person?.notes ?? "")
    _entryIDs = State(initialValue: person?.linked_entries.map(\.id) ?? [])
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Person") {
          TextField("Name", text: $name)
          TextField("Relationship (optional)", text: $relationship)
          TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(4...10)
        }
        Section("Connected Entries") {
          ForEach(entryIDs, id: \.self) { id in
            let entry =
              person?.linked_entries.first { $0.id == id }
              ?? controller.entries.first { $0.id == id }
            DisclosureGroup(
              entry.map { $0.displayTitle + ($0.is_deleted == true ? " (in Trash)" : "") }
                ?? "Linked Entry"
            ) {
              if let entry { Text(entry.body).font(MTTypography.body).textSelection(.enabled) }
              Button("Unlink", role: .destructive) { entryIDs.removeAll { $0 == id } }
            }
          }
          Menu("Link an Entry") {
            ForEach(controller.entries.filter { !entryIDs.contains($0.id) }) { entry in
              Button(entry.displayTitle) { entryIDs.append(entry.id) }
            }
          }.disabled(entryIDs.count >= 100)
        }
        if let message { Section { Text(message).foregroundStyle(MTColor.warm) } }
        if let person {
          Section {
            Button("Move to Trash", role: .destructive) { confirmsTrash = true }
              .disabled(!person.linked_entries.isEmpty)
            if !person.linked_entries.isEmpty {
              Text("Unlink every Entry and save before removing this Person.").font(.caption)
            }
          }
        }
      }
      .disabled(controller.saving).navigationTitle(person == nil ? "New Person" : "Edit Person")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }.disabled(controller.saving)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(controller.saving ? "Saving..." : "Save") {
            Task {
              message = await controller.save(
                PersonSaveInput(
                  p_person_id: person?.id,
                  p_expected_revision: person?.revision, p_name: name,
                  p_relationship_label: relationship,
                  p_notes: notes, p_related_entry_ids: entryIDs))
              if message == nil { dismiss() }
            }
          }.disabled(controller.saving || name.trimmed.isEmpty)
        }
      }
      .interactiveDismissDisabled(controller.saving)
      .confirmationDialog("Move this Person to Trash?", isPresented: $confirmsTrash) {
        Button("Move to Trash", role: .destructive) {
          if let person {
            Task {
              message = await controller.trash(person)
              if message == nil { dismiss() }
            }
          }
        }
      } message: {
        Text("You can restore this Person from Trash.")
      }
    }
  }
}
