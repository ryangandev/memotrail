#if DEBUG
  import SwiftUI
  @preconcurrency import Supabase

  struct NativeReviewAppearancePreference: PreferenceKey {
    static let defaultValue: NativeAppearance? = nil
    static func reduce(value: inout NativeAppearance?, nextValue: () -> NativeAppearance?) {
      value = nextValue() ?? value
    }
  }

  // Explicit Debug-only review modes use synthetic data and never sign in.
  enum NativeReviewMode: String {
    case designSystem = "--review-design-system"
    case map = "--review-map"
    case navigation = "--review-navigation"

    static var current: Self? {
      [Self.designSystem, .map, .navigation].first {
        ProcessInfo.processInfo.arguments.contains($0.rawValue)
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
