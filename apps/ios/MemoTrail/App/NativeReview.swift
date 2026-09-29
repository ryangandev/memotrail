#if DEBUG
  import SwiftUI
  @preconcurrency import Supabase

  struct NativeReviewAppearancePreference: PreferenceKey {
    static let defaultValue: NativeAppearance? = nil
    static func reduce(value: inout NativeAppearance?, nextValue: () -> NativeAppearance?) {
      value = nextValue() ?? value
    }
  }

  // Explicit Debug-only review modes use synthetic data and never sign in with a real account.
  enum NativeReviewMode: String {
    case designSystem = "--review-design-system"
    case map = "--review-map"
    case navigation = "--review-navigation"
    case localSession = "--review-local-session"

    static var current: Self? {
      [Self.designSystem, .map, .navigation, .localSession].first {
        ProcessInfo.processInfo.arguments.contains($0.rawValue)
      }
    }
  }

  /// A disposable account on the local Supabase stack, created and seeded by
  /// `apps/ios/scripts/review-local-session.py`. Only 127.0.0.1 endpoints are accepted.
  struct NativeReviewSession: Decodable, Sendable {
    let supabaseURL: URL
    let publishableKey: String
    let accessToken: String
    let refreshToken: String
    let ownerID: UUID
    let email: String
    let name: String
    let apiURL: URL?

    static let current: Self? = {
      guard NativeReviewMode.current == .localSession,
        let path = ProcessInfo.processInfo.environment["MEMOTRAIL_REVIEW_SESSION"],
        let data = FileManager.default.contents(atPath: path),
        let session = try? JSONDecoder().decode(Self.self, from: data),
        session.supabaseURL.host == "127.0.0.1",
        session.apiURL.map({ $0.host == "127.0.0.1" }) ?? true
      else { return nil }
      return session
    }()
  }

  // Keeps the disposable session out of the Keychain.
  private final class NativeReviewSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
  }

  private struct NativeLocalSessionView: View {
    private enum Phase {
      case connecting
      case ready(SupabaseClient, AuthenticatedUser)
      case failed(String)
    }

    @State private var phase = Phase.connecting

    var body: some View {
      switch phase {
      case .connecting:
        ProgressView("Opening local session")
          .task { await connect() }
      case .ready(let client, let user):
        RootTabView(client: client, user: user, isAuthenticationBusy: false, signOut: {})
      case .failed(let message):
        ContentUnavailableView(
          "Local session unavailable", systemImage: "exclamationmark.triangle",
          description: Text(message))
      }
    }

    private func connect() async {
      guard let session = NativeReviewSession.current else {
        phase = .failed(
          "Run apps/ios/scripts/review-local-session.py with the local Supabase stack.")
        return
      }
      let client = SupabaseClient(
        supabaseURL: session.supabaseURL, supabaseKey: session.publishableKey,
        options: .init(
          auth: .init(
            storage: NativeReviewSessionStorage(), storageKey: "native-review-\(session.ownerID)",
            emitLocalSessionAsInitialSession: true)))
      do {
        let restored = try await client.auth.setSession(
          accessToken: session.accessToken, refreshToken: session.refreshToken)
        guard restored.user.id == session.ownerID else {
          phase = .failed("The local session belongs to a different account.")
          return
        }
        phase = .ready(
          client, AuthenticatedUser(id: session.ownerID, email: session.email, name: session.name))
      } catch {
        phase = .failed(error.localizedDescription)
      }
    }
  }

  struct NativeReviewView: View {
    let mode: NativeReviewMode
    private let ownerID = UUID(uuidString: "99000000-0000-4000-8000-000000000001")!
    private let client = SupabaseClient(
      supabaseURL: URL(string: "http://127.0.0.1:1")!, supabaseKey: "synthetic-review",
      options: .init(
        auth: .init(
          storageKey: "native-ui-review", autoRefreshToken: false,
          emitLocalSessionAsInitialSession: true)))

    // `--review-design-section <name>` opens one gallery section directly for screenshot review.
    @State private var galleryPath: [DesignSystemSection] = {
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "--review-design-section"),
        arguments.indices.contains(index + 1),
        let section = DesignSystemSection(rawValue: arguments[index + 1])
      else { return [] }
      return [section]
    }()

    var body: some View {
      switch mode {
      case .designSystem: NavigationStack(path: $galleryPath) { DesignSystemGallery() }
      case .map: NavigationStack { LocationMapView(preview: Self.mapSnapshot) }
      case .navigation:
        RootTabView(
          client: client,
          user: AuthenticatedUser(id: ownerID, email: "preview@example.invalid", name: "Preview"),
          isAuthenticationBusy: false, signOut: {})
      case .localSession: NativeLocalSessionView()
      }
    }

    static var mapSnapshot: LocationMapSnapshot {
      func item(
        _ index: Int, _ title: String, _ kind: WikiItemKind, _ subtype: String, _ year: Int?,
        _ latitude: Double, _ longitude: Double, _ city: String, _ region: String
      ) -> LocationMapItem {
        LocationMapItem(
          entryID: UUID(uuidString: String(format: "99000000-0000-4000-8000-%012d", index))!,
          locationID: UUID(uuidString: String(format: "99100000-0000-4000-8000-%012d", index))!,
          title: title, kind: kind, subtype: subtype,
          inboxStatus: index == 4 ? "unreviewed" : "organized",
          occurredAt: year.flatMap { ISO8601DateFormatter().date(from: "\($0)-06-01T12:00:00Z") },
          latitude: latitude, longitude: longitude, address: "\(city), \(region)", city: city,
          region: region, country: "United States"
        )
      }
      return LocationMapSnapshot(
        items: [
          item(1, "Our first home", .entity, "home", 2021, 30.2672, -97.7431, "Austin", "Texas"),
          item(
            2, "A new beginning", .entry, "first_time", 2022, 30.2672, -97.7431, "Austin", "Texas"),
          item(
            3, "A quiet afternoon by the coast", .entry, "entry", 2025, 37.7749, -122.4194,
            "San Francisco", "California"),
          item(
            4, "A thought worth keeping", .entry, "entry", nil, 37.78, -122.42, "San Francisco",
            "California"),
          item(
            5, "Return to the coast", .goal, "goal", 2026, 37.78, -122.42, "San Francisco",
            "California"),
        ], truncated: false)
    }
  }
#endif
