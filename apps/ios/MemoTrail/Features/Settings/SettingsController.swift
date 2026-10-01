import Foundation
import Observation
@preconcurrency import Supabase

/// Web `/settings` profile actions: the preferred name, birth date, and default time zone.
@MainActor
@Observable
final class SettingsController {
  enum Field: Sendable { case preferredName, birthDate, timezone }

  struct SaveResult: Equatable, Sendable {
    let isSaved: Bool
    let message: String
  }

  private(set) var profile: ProfileSettings?
  private(set) var isLoading = false
  private(set) var loadErrorMessage: String?
  private(set) var savingField: Field?

  private let client: SupabaseClient
  private let ownerID: UUID

  init(client: SupabaseClient, ownerID: UUID) {
    self.client = client
    self.ownerID = ownerID
  }

  func load() async {
    isLoading = true
    defer { isLoading = false }
    do {
      try await validateSessionOwner()
      let loaded: ProfileSettings = try await client.from("profiles")
        .select("display_name,birth_date,timezone").eq("user_id", value: ownerID.uuidString)
        .single().execute().value
      try await validateSessionOwner()
      profile = loaded
      loadErrorMessage = nil
    } catch {
      guard !(error is CancellationError) else { return }
      loadErrorMessage = "Your profile settings could not load. Pull to refresh or try again."
    }
  }

  func savePreferredName(_ value: String) async -> SaveResult {
    let name: String?
    do { name = try ProfileSettings.parsePreferredName(value) } catch {
      return SaveResult(isSaved: false, message: error.localizedDescription)
    }
    let failure = "MemoTrail could not save your preferred name. Try again."
    guard let saved = await update(.preferredName, "display_name", to: name) else {
      return SaveResult(isSaved: false, message: failure)
    }
    guard saved.preferredName == name else { return SaveResult(isSaved: false, message: failure) }
    profile?.preferredName = name
    return SaveResult(
      isSaved: true, message: name == nil ? "Preferred name cleared." : "Preferred name saved.")
  }

  func saveBirthDate(_ value: String) async -> SaveResult {
    let date: String?
    do { date = try ProfileSettings.parseBirthDate(value) } catch {
      return SaveResult(isSaved: false, message: error.localizedDescription)
    }
    let failure = "MemoTrail could not save your birth date. Try again."
    guard let saved = await update(.birthDate, "birth_date", to: date), saved.birthDate == date
    else { return SaveResult(isSaved: false, message: failure) }
    profile?.birthDate = date
    return SaveResult(
      isSaved: true, message: date == nil ? "Birth date removed." : "Birth date saved.")
  }

  func saveTimezone(_ value: String) async -> SaveResult {
    let timezone: String
    do { timezone = try ProfileSettings.parseTimezone(value) } catch {
      return SaveResult(isSaved: false, message: error.localizedDescription)
    }
    guard let saved = await update(.timezone, "timezone", to: timezone),
      saved.timezone == timezone
    else {
      return SaveResult(
        isSaved: false, message: "MemoTrail could not save your default time zone. Try again.")
    }
    profile?.timezone = timezone
    return SaveResult(isSaved: true, message: "Default time zone saved.")
  }

  /// Writes one profile column and reads it back, like the Web actions.
  private func update(_ field: Field, _ column: String, to value: String?) async
    -> ProfileSettings?
  {
    savingField = field
    defer { savingField = nil }
    do {
      try await validateSessionOwner()
      let saved: ProfileSettings = try await client.from("profiles")
        .update(ProfileColumnUpdate(column: column, value: value))
        .eq("user_id", value: ownerID.uuidString)
        .select("display_name,birth_date,timezone").single().execute().value
      return saved
    } catch {
      return nil
    }
  }

  private func validateSessionOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }
}

/// One profile column, with an explicit null to clear it.
private struct ProfileColumnUpdate: Encodable, Sendable {
  let column: String
  let value: String?

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: ColumnKey.self)
    try values.encode(value, forKey: ColumnKey(stringValue: column))
  }

  private struct ColumnKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }
}
