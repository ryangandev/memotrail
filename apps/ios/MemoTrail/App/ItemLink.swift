@preconcurrency import Supabase
import SwiftUI

/// A link to an Entry's Item page, like Web `wikiEntryHref`: every Entry, Chapter, and First Time
/// opens `/items/<id>`.
struct ItemLink: Hashable, Identifiable {
  let entryID: UUID

  init(entryID: UUID) {
    self.entryID = entryID
  }

  var id: UUID { entryID }
}

extension View {
  /// Pushes the Item page for an `ItemLink` value. Apply it outside lazy containers such as
  /// `MTPage`, which ignore navigation destinations.
  func itemDestination(client: SupabaseClient, ownerID: UUID) -> some View {
    navigationDestination(for: ItemLink.self) { link in
      ItemPageView(client: client, ownerID: ownerID, entryID: link.entryID)
    }
  }
}
