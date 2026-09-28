import Foundation
@preconcurrency import Supabase
import SwiftUI

struct AIPreferences: Codable, Equatable, Sendable {
  enum CodingKeys: String, CodingKey {
    case enabled, classification, tagging, search, explore, resurfacing, revision
    case photoAnalysis = "photo_analysis"
    case monthlyBudgetMicros = "monthly_budget_micros"
  }
  var enabled = false
  var classification = true
  var tagging = true
  var search = true
  var explore = true
  var resurfacing = false
  var photoAnalysis = false
  var monthlyBudgetMicros = 1_000_000
  var revision = 0

  var isValid: Bool {
    revision >= 0 && (0...100_000_000).contains(monthlyBudgetMicros)
  }
}

struct AIUsageRecord: Decodable, Identifiable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, feature, status
    case chargedMicros = "charged_micros"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case createdAt = "created_at"
  }
  let id: UUID
  let feature: String
  let status: String
  let chargedMicros: Int
  let inputTokens: Int?
  let outputTokens: Int?
  let createdAt: String
}

struct AIWorkspace: Decodable, Sendable {
  enum CodingKeys: String, CodingKey {
    case preferences
    case monthChargedMicros = "month_charged_micros"
    case recentUsage = "recent_usage"
  }
  let preferences: AIPreferences
  let monthChargedMicros: Int
  let recentUsage: [AIUsageRecord]
}

struct AISettingsInput: Encodable, Sendable {
  enum CodingKeys: String, CodingKey {
    case preferences = "p_preferences"
    case expectedRevision = "p_expected_revision"
  }
  let preferences: AIPreferences
  let expectedRevision: Int
}

struct AIConnectionResponse: Decodable, Sendable {
  let message: String
  let model: String
}

enum AIAPI {
  struct Failure: Decodable {
    let error: String
    let code: String?
  }

  static func post<T: Decodable & Sendable, Body: Encodable & Sendable>(
    _ path: String, body: Body, client: SupabaseClient, ownerID: UUID,
    timeout: TimeInterval = 35
  ) async throws -> T {
    guard AppConfiguration.aiEnabled else {
      throw NSError(
        domain: "MemoTrail.AI", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "AI features are paused.", "serverCode": "ai_paused"])
    }
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw URLError(.userAuthenticationRequired) }
    guard let base = AppConfiguration.apiURL else { throw URLError(.badURL) }
    var request = URLRequest(url: base.appendingPathComponent("api/ai/\(path)"))
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(body)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let failure = try? JSONDecoder().decode(Failure.self, from: data)
      let message = failure?.error ?? "Could not reach the AI server. Your records are unchanged."
      throw NSError(
        domain: "MemoTrail.AI", code: 1,
        userInfo: [NSLocalizedDescriptionKey: message, "serverCode": failure?.code ?? ""])
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  static func cost(_ micros: Int) -> String {
    (Double(micros) / 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(2...6)))
  }
}

struct AISettingsView: View {
  let client: SupabaseClient
  let ownerID: UUID
  @State private var workspace: AIWorkspace?
  @State private var preferences = AIPreferences()
  @State private var budget = "1"
  @State private var busy = false
  @State private var message: String?

  var body: some View {
    Form {
      Section {
        Toggle("AI assistance (Beta)", isOn: .constant(false))
          .disabled(true)
      } footer: {
        Text(
          "AI features are paused while their next version is being designed. Your saved preferences and history are preserved."
        )
      }
    }
    .scrollContentBackground(.hidden)
    .background(MTColor.canvas)
    .navigationTitle("AI settings")
  }

  private func checkOwner() async throws {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
  }

  private func load() async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do {
      try await checkOwner()
      let data: AIWorkspace = try await client.rpc("ai_workspace").execute().value
      workspace = data
      preferences = data.preferences
      budget = String(Double(preferences.monthlyBudgetMicros) / 1_000_000)
      message = nil
    } catch { message = "Could not load AI settings. Try again." }
  }

  private func save() async {
    guard let amount = Double(budget), amount.isFinite, (0...100).contains(amount) else {
      message = "Enter a monthly budget between $0 and $100."
      return
    }
    preferences.monthlyBudgetMicros = Int((amount * 1_000_000).rounded())
    guard preferences.isValid else { return }
    busy = true
    defer { busy = false }
    do {
      try await checkOwner()
      let saved: AIWorkspace? = try await client.rpc(
        "save_ai_preferences",
        params: AISettingsInput(
          preferences: preferences, expectedRevision: preferences.revision
        )
      ).execute().value
      guard let saved else {
        message = "Settings changed on another device. Reopen this screen before saving again."
        return
      }
      workspace = saved
      preferences = saved.preferences
      message = "AI settings saved across your devices."
    } catch { message = "Could not save AI settings. Your edits are still here." }
  }

  private func test() async {
    busy = true
    defer { busy = false }
    do {
      let response: AIConnectionResponse = try await AIAPI.post(
        "connection", body: [String: String](), client: client, ownerID: ownerID)
      message = response.message
      workspace = try await client.rpc("ai_workspace").execute().value
    } catch { message = error.localizedDescription }
  }
}
