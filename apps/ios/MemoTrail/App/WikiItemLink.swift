@preconcurrency import Supabase
import SwiftUI

/// Where a link to a Wiki Item leads, like Web `wikiEntryHref`: an Inbox capture opens its
/// review, a Moment or Period opens on the Timeline, and any other Item opens its own page,
/// with a Person from People on their Person page.
struct WikiItemLink: Hashable, Identifiable {
  let entryID: UUID
  let kind: WikiItemKind
  let subtype: String
  var personID: UUID? = nil
  var isInInbox = false

  var id: UUID { entryID }

  var opensOnTimeline: Bool { kind == .entry && ["moment", "period"].contains(subtype) }
}

extension WikiItemLink {
  init(_ item: WikiItemSummary) {
    self.init(
      entryID: item.id, kind: item.itemKind, subtype: item.itemSubtype,
      personID: item.recordSource == .person ? item.recordID : nil,
      isInInbox: item.isInInbox)
  }

  init(_ entry: SearchEntry) {
    self.init(
      entryID: entry.id, kind: entry.itemKind, subtype: entry.itemSubtype,
      personID: entry.recordSource == .person ? entry.recordID : nil,
      isInInbox: entry.isInInbox)
  }

  init(_ entry: CollectionEntry) {
    self.init(
      entryID: entry.id, kind: entry.itemKind, subtype: entry.itemSubtype,
      personID: entry.recordSource == .person ? entry.recordID : nil,
      isInInbox: entry.isInInbox)
  }
}

extension AppNavigator {
  /// Follows a Wiki Item link: Inbox review and the Timeline switch tabs, and `push` opens any
  /// other Item on the current stack.
  func open(_ link: WikiItemLink, push: (WikiItemLink) -> Void) {
    if link.isInInbox {
      reviewInboxEntry(link.entryID)
    } else if link.opensOnTimeline {
      openTimelineEntry(link.entryID)
    } else {
      push(link)
    }
  }
}

extension WikiItemDestinationView {
  init(client: SupabaseClient, ownerID: UUID, link: WikiItemLink) {
    self.init(
      client: client, ownerID: ownerID, entryID: link.entryID, kind: link.kind,
      subtype: link.subtype, personID: link.personID)
  }
}

extension View {
  /// Pushes the Item that `link` holds. Apply it outside lazy containers such as `MTPage`,
  /// which ignore navigation destinations.
  func wikiItemDestination(
    _ link: Binding<WikiItemLink?>, client: SupabaseClient, ownerID: UUID
  ) -> some View {
    navigationDestination(item: link) { link in
      WikiItemDestinationView(client: client, ownerID: ownerID, link: link)
    }
  }
}
