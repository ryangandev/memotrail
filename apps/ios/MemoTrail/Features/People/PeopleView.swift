@preconcurrency import Supabase
import SwiftUI

/// Web `/people` at phone width: People as record cards that open each Person's own page, and
/// Add Person.
struct PeopleView: View {
  let client: SupabaseClient
  let ownerID: UUID

  @State private var controller: PeopleController
  @State private var isAdding = false
  @State private var openedPersonID: UUID?

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
    _controller = State(initialValue: PeopleController(client: client, ownerID: ownerID))
  }

  var body: some View {
    MTPage(width: .wide, spacing: MTSpacing.s4) {
      MTPageHeader(
        eyebrow: "The people in your story", title: "People",
        description: "Keep a little context for the people who shaped each chapter."
      ) {
        Button {
          isAdding = true
        } label: {
          Label("Add Person", icon: .plus)
        }
        .mtButtonStyle()
        .accessibilityIdentifier("add-person")
      }
      summary
      content
    }
    .refreshable { await controller.load() }
    .navigationTitle("People")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $isAdding) {
      PersonEditorSheet(controller: controller, person: nil)
    }
    .navigationDestination(item: $openedPersonID) { id in
      PersonDetailView(controller: controller, client: client, ownerID: ownerID, personID: id)
    }
    .task {
      if !controller.hasLoaded { await controller.load() }
    }
  }

  private var summary: some View {
    let people = controller.people
    let connections = people.reduce(0) { $0 + $1.linkedEntries.count }
    return MTFlowLayout(spacing: MTSpacing.s2) {
      Text("\(people.count) \(people.count == 1 ? "person" : "people")")
      Text("·").accessibilityHidden(true)
      Text("\(connections) connected \(connections == 1 ? "Item" : "Items")")
      if controller.isLoading, controller.hasLoaded {
        ProgressView().controlSize(.small).tint(MTColor.accent)
      }
    }
    .font(MTFont.caption.weight(.regular))
    .foregroundStyle(MTColor.inkFaint)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("People summary")
  }

  @ViewBuilder
  private var content: some View {
    if !controller.hasLoaded {
      HStack(spacing: MTSpacing.s3) {
        ProgressView().tint(MTColor.accent)
        Text("Loading People...")
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
      }
      .frame(maxWidth: .infinity, minHeight: 180)
    } else if let message = controller.loadErrorMessage {
      MTEmptyState(title: "People unavailable", message: message, icon: .person) {
        Button("Try again") { Task { await controller.load() } }
          .mtButtonStyle(.secondary)
      }
      .padding(.top, MTSpacing.s4)
    } else if controller.people.isEmpty {
      MTEmptyState(
        title: "Remember the first person in your story",
        message:
          "Start with a name. Relationship context, notes, and connected Items can be added whenever they become useful.",
        icon: .person
      ) {
        isAdding = true
      }
      .padding(.top, MTSpacing.s4)
    } else {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: 300), spacing: MTSpacing.s4)],
        spacing: MTSpacing.s4
      ) {
        ForEach(controller.people) { person in
          PersonCard(person: person) { openedPersonID = person.id }
        }
      }
      .padding(.top, MTSpacing.s2)
      if controller.hasMore || controller.moreErrorMessage != nil {
        MTLoadMore(isLoading: controller.isLoadingMore, message: controller.moreErrorMessage) {
          await controller.loadMore()
        }
      }
    }
  }
}

/// Web People card: the name's initial, the name, relationship, a short note, and how many
/// Items are connected.
private struct PersonCard: View {
  let person: PersonRecord
  let open: () -> Void

  var body: some View {
    let relationship = person.relationshipLabel?.trimmed.nonEmpty ?? "A person in your story"
    let connections = person.linkedEntries.count
    MTRecordCard(accessibilityLabel: "\(person.name), \(relationship)", action: open) {
      MTRecordCardBody {
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text(person.name.first.map { String($0).uppercased() } ?? "")
            .font(.system(.title2, design: .serif))
            .foregroundStyle(MTColor.accent)
            .frame(width: 48, height: 48)
            .background(MTColor.accentSubtle, in: Circle())
            .accessibilityHidden(true)
          Text(person.name)
            .font(MTFont.cardTitle)
            .tracking(-0.4)
            .foregroundStyle(MTColor.ink)
            .multilineTextAlignment(.leading)
            .padding(.top, MTSpacing.s2)
          Text(relationship)
            .font(MTFont.caption.weight(.regular))
            .foregroundStyle(MTColor.inkMuted)
            .multilineTextAlignment(.leading)
          if let notes = person.notes?.trimmed.nonEmpty {
            Text(notes)
              .font(MTFont.caption.weight(.regular))
              .foregroundStyle(MTColor.inkMuted)
              .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
              .lineLimit(3)
              .multilineTextAlignment(.leading)
          }
          Spacer(minLength: 0)
          Text("\(connections) connected \(connections == 1 ? "Item" : "Items")")
            .font(.caption2)
            .foregroundStyle(MTColor.inkFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, MTSpacing.s4)
            .overlay(alignment: .top) { MTListDivider() }
            .padding(.top, MTSpacing.s2)
        }
        // Web keeps short Person cards the same height, with the count at the bottom.
        .frame(minHeight: 260 - 2 * MTSpacing.s5, alignment: .top)
      }
    }
  }
}
