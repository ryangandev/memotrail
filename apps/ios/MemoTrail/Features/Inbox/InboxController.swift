import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class InboxController {
  private(set) var entries: [InboxEntry] = []
  private(set) var hasLoaded = false
  private(set) var isLoading = false
  private(set) var isSaving = false
  private(set) var loadErrorMessage: String?
  private(set) var captureMessage: CaptureMessage?

  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func load() async {
    guard !isLoading else { return }

    isLoading = true
    loadErrorMessage = nil
    defer {
      isLoading = false
      hasLoaded = true
    }

    do {
      let session = try await client.auth.session
      let loadedEntries: [InboxEntry] =
        try await client
        .from("entries")
        .select("id,title,body,created_at,occurred_start")
        .eq("owner_id", value: session.user.id.uuidString)
        .eq("inbox_status", value: "unreviewed")
        .is("deleted_at", value: nil)
        .order("created_at", ascending: false)
        .limit(50)
        .execute()
        .value

      entries = loadedEntries
    } catch {
      loadErrorMessage = "MemoTrail could not load your Inbox. Pull to refresh or try again."
    }
  }

  func save(title: String, body: String) async -> Bool {
    guard !isSaving else { return false }

    let capture: InboxCapture
    do {
      capture = try InboxCapture.validate(title: title, body: body)
    } catch {
      captureMessage = CaptureMessage(
        text: error.localizedDescription,
        style: .error
      )
      return false
    }

    isSaving = true
    captureMessage = nil
    defer { isSaving = false }

    do {
      let session = try await client.auth.session
      let payload = InboxEntryInsert(
        ownerID: session.user.id,
        title: capture.title,
        body: capture.body,
        occurredStart: Date()
      )

      try await client
        .from("entries")
        .insert(payload)
        .execute()

      captureMessage = CaptureMessage(text: "Saved to Inbox.", style: .success)
      await load()
      return true
    } catch {
      captureMessage = CaptureMessage(
        text: "MemoTrail could not save this Entry. Your text is still here.",
        style: .error
      )
      return false
    }
  }
}

extension InboxController {
  struct CaptureMessage: Equatable, Sendable {
    enum Style: Sendable {
      case error
      case success
    }

    let text: String
    let style: Style
  }
}

private struct InboxEntryInsert: Encodable, Sendable {
  let ownerID: UUID
  let title: String?
  let body: String
  let entryType = "standard"
  let inboxStatus = "unreviewed"
  let occurredStart: Date
  let occurredTimezone = "UTC"
  let datePrecision = "exact"

  enum CodingKeys: String, CodingKey {
    case ownerID = "owner_id"
    case title
    case body
    case entryType = "entry_type"
    case inboxStatus = "inbox_status"
    case occurredStart = "occurred_start"
    case occurredTimezone = "occurred_timezone"
    case datePrecision = "date_precision"
  }
}
