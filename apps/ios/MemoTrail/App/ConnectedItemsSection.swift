@preconcurrency import Supabase
import SwiftUI

/// Web focused-record "Connected Items": a link to each related record. Like Web
/// `wikiEntryHref`, Moments and Periods open on the Timeline, and other records set `opened`
/// so `connectedItemDestination` pushes their own page.
struct ConnectedItemsSection: View {
  struct Item: Identifiable, Hashable {
    let id: UUID
    let title: String
    let kind: WikiItemKind
    let subtype: String
  }

  let items: [Item]
  @Binding var opened: Item?
  @Environment(AppNavigator.self) private var navigator

  var body: some View {
    MTDetailSection("Connected Items") {
      VStack(alignment: .leading, spacing: MTSpacing.s2) {
        ForEach(items) { item in
          HStack(alignment: .firstTextBaseline, spacing: MTSpacing.s3) {
            Text("•")
              .foregroundStyle(MTColor.inkMuted)
              .accessibilityHidden(true)
            Button(item.title) { open(item) }
              .buttonStyle(.plain)
              .underline()
              .foregroundStyle(MTColor.accent)
              .multilineTextAlignment(.leading)
              .accessibilityHint(item.kind.displayName(subtype: item.subtype))
          }
          .font(MTFont.bodyLarge)
        }
      }
    }
  }

  private func open(_ item: Item) {
    navigator.open(WikiItemLink(entryID: item.id, kind: item.kind, subtype: item.subtype)) { _ in
      opened = item
    }
  }
}

extension View {
  /// Pushes the Connected Item that `item` holds. Apply it outside lazy containers such as
  /// `MTPage`, which ignore navigation destinations.
  func connectedItemDestination(
    _ item: Binding<ConnectedItemsSection.Item?>, client: SupabaseClient, ownerID: UUID
  ) -> some View {
    navigationDestination(item: item) { item in
      WikiItemDestinationView(
        client: client, ownerID: ownerID, entryID: item.id, kind: item.kind,
        subtype: item.subtype)
    }
  }
}
