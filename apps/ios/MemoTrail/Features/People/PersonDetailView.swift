@preconcurrency import Supabase
import SwiftUI

/// Web `/people/<id>`: one Person's relationship, notes, and connected Items, with Edit. Like
/// Web, a Person has no version history. Moving them to Trash from the editor returns to where
/// the page was opened from.
struct PersonDetailView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let personID: UUID

  @State private var controller: PeopleController
  @State private var loadState: PeopleController.PersonLoad?
  @State private var isEditing = false
  @State private var openedItem: ConnectedItemsSection.Item?
  @State private var wasTrashed = false
  /// Keeps the page steady under the closing editor after the Person moves to Trash.
  @State private var lastPerson: PersonRecord?
  @Environment(\.dismiss) private var dismiss

  /// Opens a Person on their own, such as from Library, the Map, or a Collection.
  init(client: SupabaseClient, ownerID: UUID, personID: UUID) {
    self.init(
      controller: PeopleController(client: client, ownerID: ownerID), client: client,
      ownerID: ownerID, personID: personID)
  }

  /// Opens a Person from a list that has already loaded them.
  init(controller: PeopleController, client: SupabaseClient, ownerID: UUID, personID: UUID) {
    self.client = client
    self.ownerID = ownerID
    self.personID = personID
    _controller = State(initialValue: controller)
  }

  var body: some View {
    Group {
      if let person = controller.person(id: personID) ?? (wasTrashed ? lastPerson : nil) {
        detail(person)
      } else if loadState == nil {
        MTPage(width: .compact) {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            Text("Loading this Person...").font(MTFont.body).foregroundStyle(MTColor.inkMuted)
          }
          .frame(maxWidth: .infinity, minHeight: 180)
        }
      } else if loadState == .failed {
        MTPage(width: .compact) {
          MTEmptyState(
            title: "Person unavailable",
            message: "Could not load this Person. Check your connection and try again.",
            icon: .person
          ) {
            Button("Try again") { Task { await load() } }
              .mtButtonStyle(.secondary)
          }
        }
      } else {
        MTFocusedRecordUnavailable(kind: "Person", backTitle: "Back to people") { dismiss() }
      }
    }
    .refreshable { await load() }
    .navigationTitle("Person")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isEditing) {
      if wasTrashed { dismiss() }
    } content: {
      if let person = controller.person(id: personID) {
        PersonEditorSheet(controller: controller, person: person, onTrashed: { wasTrashed = true })
      }
    }
    .onChange(of: controller.person(id: personID), initial: true) { _, person in
      if let person { lastPerson = person }
    }
    .connectedItemDestination($openedItem, client: client, ownerID: ownerID)
    .task {
      if controller.person(id: personID) == nil { await load() }
    }
  }

  private func load() async {
    loadState = await controller.loadPerson(id: personID)
  }

  private func detail(_ person: PersonRecord) -> some View {
    MTFocusedRecordPage(
      kind: "Person", title: person.name,
      facts: [("Relationship", person.relationshipLabel)],
      story: person.notes, storyTitle: "Notes",
      edit: { isEditing = true },
      extra: {
        if !person.linkedEntries.isEmpty {
          ConnectedItemsSection(
            items: person.linkedEntries.map {
              ConnectedItemsSection.Item(
                id: $0.id, title: $0.isDeleted ? "\($0.displayTitle) (in Trash)" : $0.displayTitle,
                kind: $0.itemKind, subtype: $0.itemSubtype)
            },
            opened: $openedItem)
        }
      })
  }
}
