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

/// Web `AIPausedSettings`: AI stays off and cannot be enabled while its next version is
/// designed; manual features and previous AI data remain.
struct AISettingsView: View {
  var body: some View {
    MTPage(width: .compact) {
      MTPageHeader(
        eyebrow: "Beta · Paused", title: "AI capabilities",
        description:
          "AI capabilities are paused while we rethink how they can help. Manual features remain available."
      )
      VStack(alignment: .leading, spacing: MTSpacing.s5) {
        HStack(alignment: .top, spacing: MTSpacing.s3) {
          Image(.sparkle)
            .font(.mtIcon(MTSize.Icon.s19, weight: .medium))
            .foregroundStyle(MTColor.accent)
            .frame(width: MTLayout.IconTile.large, height: MTLayout.IconTile.large)
            .background(MTColor.accentSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
            .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: MTSpacing.s1) {
            Text("AI capabilities")
              .font(MTFont.cardTitle)
              .foregroundStyle(MTColor.ink)
              .accessibilityAddTraits(.isHeader)
            Text("Currently off and unavailable to enable.")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
          }
          Spacer(minLength: 0)
          MTBadge(title: "Beta", tone: .neutral)
        }
        Toggle(isOn: .constant(false)) {
          VStack(alignment: .leading, spacing: MTSpacing.s0_5) {
            Text("AI capabilities")
              .font(MTFont.label)
              .foregroundStyle(MTColor.ink)
            Text("Capture, organize, and search your archive manually.")
              .font(MTFont.detail)
              .foregroundStyle(MTColor.inkMuted)
          }
        }
        .tint(MTColor.accent)
        .disabled(true)
        .padding(MTSpacing.s4)
        .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
        .overlay {
          RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
            MTColor.border, lineWidth: MTSize.Stroke.thin)
        }
        Text(
          "No new AI requests will run while this beta is paused. Your Entries and previous AI data are preserved."
        )
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkMuted)
        .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(MTSpacing.s5)
      .background(MTColor.surfaceRaised, in: RoundedRectangle(cornerRadius: MTRadius.large))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(
          MTColor.border, lineWidth: MTSize.Stroke.thin)
      }
      .accessibilityElement(children: .contain)
      .accessibilityLabel("AI availability")
    }
    .navigationTitle("AI capabilities")
    .navigationBarTitleDisplayMode(.inline)
  }
}
