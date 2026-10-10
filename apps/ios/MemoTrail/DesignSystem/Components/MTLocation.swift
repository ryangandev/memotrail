import MapKit
import SwiftUI

/// A private coordinate pair that is valid on Earth, or nil.
func mtCoordinate(latitude: Double?, longitude: Double?) -> CLLocationCoordinate2D? {
  guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
    (-90...90).contains(latitude), (-180...180).contains(longitude)
  else { return nil }
  return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
}

/// Web `RecordCardMap`: a still map of a record's position with a pin, or the fallback when
/// the record has no valid position or the map cannot load.
struct MTLocationSnapshot<Fallback: View>: View {
  let latitude: Double?
  let longitude: Double?
  /// Meters shown across the shorter side, around the pin.
  var span: CLLocationDistance = 1_600
  private let fallback: Fallback
  @Environment(\.colorScheme) private var colorScheme
  /// Each snapshot and failure belongs to one position, so a moved or removed Location never
  /// keeps showing the previous map.
  @State private var rendered: (image: UIImage, position: Position)?
  @State private var failedPosition: Position?

  init(
    latitude: Double?, longitude: Double?, span: CLLocationDistance = 1_600,
    @ViewBuilder fallback: () -> Fallback
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.span = span
    self.fallback = fallback()
  }

  private var position: Position? {
    mtCoordinate(latitude: latitude, longitude: longitude).map {
      Position(latitude: $0.latitude, longitude: $0.longitude)
    }
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        if let position, let rendered, rendered.position == position {
          Image(uiImage: rendered.image).resizable().scaledToFill()
          Image(systemName: "mappin.circle.fill")
            .font(.mtIcon(MTSize.Icon.s30))
            .symbolRenderingMode(.palette)
            .foregroundStyle(MTColor.surfaceRaised, MTColor.accent)
            .mtShadow(MTShadow.snapshotPin)
        } else if position == nil || failedPosition == position {
          fallback
        } else {
          MTLoadingSkeleton(shape: .fill)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
      .task(id: SnapshotKey(size: proxy.size, scheme: colorScheme, latitude, longitude)) {
        await render(size: proxy.size)
      }
    }
    .accessibilityHidden(true)
  }

  private func render(size: CGSize) async {
    guard let position, size.width > 0, size.height > 0 else { return }
    let options = MKMapSnapshotter.Options()
    options.region = MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: position.latitude, longitude: position.longitude),
      latitudinalMeters: span, longitudinalMeters: span)
    options.size = size
    options.pointOfInterestFilter = .excludingAll
    options.traitCollection = UITraitCollection(
      userInterfaceStyle: colorScheme == .dark ? .dark : .light)
    do {
      let snapshot = try await MKMapSnapshotter(options: options).start()
      guard !Task.isCancelled else { return }
      rendered = (snapshot.image, position)
      failedPosition = nil
    } catch {
      guard !Task.isCancelled else { return }
      failedPosition = position
    }
  }

  private struct Position: Equatable {
    let latitude: Double
    let longitude: Double
  }

  private struct SnapshotKey: Equatable {
    let width: CGFloat
    let height: CGFloat
    let scheme: ColorScheme
    let latitude: Double?
    let longitude: Double?

    init(size: CGSize, scheme: ColorScheme, _ latitude: Double?, _ longitude: Double?) {
      width = size.width
      height = size.height
      self.scheme = scheme
      self.latitude = latitude
      self.longitude = longitude
    }
  }
}

/// Web `LocationPicker`'s panel: the Location heading and its note above the saved Location.
/// Native editors keep or remove a saved Location; address search stays on Web for now.
struct MTLocationPanel<Content: View>: View {
  let message: String
  private let content: Content

  init(message: String, @ViewBuilder content: () -> Content) {
    self.message = message
    self.content = content()
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.large)
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      HStack(alignment: .top, spacing: MTSpacing.s3) {
        Image(.map)
          .font(.mtIcon(MTSize.Icon.s17, weight: .medium))
          .foregroundStyle(MTColor.accent)
          .frame(width: MTLayout.IconTile.compact, height: MTLayout.IconTile.compact)
          .background(
            MTColor.accentTint,
            in: RoundedRectangle(cornerRadius: MTRadius.notice)
          )
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: MTSpacing.s0_75) {
          Text("Location")
            .font(MTFont.cardTitle)
            .foregroundStyle(MTColor.ink)
            .accessibilityAddTraits(.isHeader)
          Text(message)
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkFaint)
            .mtLineSpacing(MTLineHeight.body, textStyle: .caption1)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      content
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surfaceSubtle, in: shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
  }
}

/// Web `SelectedLocation`: a saved Location's map, formatted address, and coordinates, with an
/// optional Remove action. Coordinates stay private to the record; Open map hands them to Maps.
struct MTLocationPreview: View {
  let label: String
  let latitude: Double?
  let longitude: Double?
  var remove: (() -> Void)?

  private var coordinate: CLLocationCoordinate2D? {
    mtCoordinate(latitude: latitude, longitude: longitude)
  }

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: MTRadius.medium)
    VStack(alignment: .leading, spacing: 0) {
      MTLocationSnapshot(latitude: latitude, longitude: longitude) { unavailable }
        .frame(height: MTLayout.LocationMap.height)
        .overlay(alignment: .bottom) { MTListDivider() }
        .accessibilityLabel("Map showing \(label)")

      HStack(spacing: MTSpacing.s3) {
        Text(label)
          .font(MTFont.listHeading)
          .foregroundStyle(MTColor.ink)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
        if let remove {
          Button("Remove", action: remove)
            .mtButtonStyle(.secondary, size: .small)
            .accessibilityLabel("Remove Location")
        }
      }
      .padding(.horizontal, MTSpacing.s4)
      .padding(.top, MTSpacing.s3)
      .padding(.bottom, MTSpacing.s2)

      if let coordinate {
        HStack(spacing: MTSpacing.s3) {
          Text(
            "\(coordinate.latitude.formatted(Self.coordinateFormat)), \(coordinate.longitude.formatted(Self.coordinateFormat))"
          )
          .textSelection(.enabled)
          Spacer(minLength: 0)
          if let url = mapsURL(coordinate) {
            Link("Open map", destination: url)
              .foregroundStyle(MTColor.accent)
              .underline()
          }
        }
        .font(MTFont.detail)
        .foregroundStyle(MTColor.inkFaint)
        .padding(.horizontal, MTSpacing.s4)
        .padding(.bottom, MTSpacing.s3)
      }
    }
    .background(MTColor.surface, in: shape)
    .clipShape(shape)
    .overlay { shape.strokeBorder(MTColor.border, lineWidth: MTSize.Stroke.thin) }
  }

  private var unavailable: some View {
    VStack(spacing: MTSpacing.s2) {
      Image(.map).font(.mtIcon(MTSize.Icon.s22))
      if coordinate == nil {
        Text("This Location does not have coordinates yet.")
          .font(MTFont.detail)
          .multilineTextAlignment(.center)
      }
    }
    .foregroundStyle(MTColor.inkFaint)
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [MTColor.surfaceSubtle, MTColor.surface], startPoint: .topLeading,
        endPoint: .bottomTrailing))
  }

  private static let coordinateFormat = FloatingPointFormatStyle<Double>.number
    .precision(.fractionLength(5)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))

  private func mapsURL(_ coordinate: CLLocationCoordinate2D) -> URL? {
    var components = URLComponents(string: "https://maps.apple.com/")
    components?.queryItems = [
      URLQueryItem(name: "ll", value: "\(coordinate.latitude),\(coordinate.longitude)"),
      URLQueryItem(name: "q", value: label),
    ]
    return components?.url
  }
}
