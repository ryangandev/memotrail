import Foundation
@preconcurrency import Supabase
import SwiftUI

struct PhotoPlaceDraft: Encodable, Equatable, Sendable {
  var kind: String = "new"
  let attachmentId: UUID
  var placeId: UUID?
  var revision: Int?
  var name: String = ""
  var latitude: Double?
  var longitude: Double?
  func validate() throws {
    if kind == "existing" {
      guard placeId != nil, let revision, revision > 0, revision < 1_000_000_000 else {
        throw PlaceEntryError.invalidRevision
      }
    } else {
      guard kind == "new", let latitude, let longitude else {
        throw PlaceEntryError.invalidCoordinates
      }
      _ = try PlaceInput.validate(
        placeID: nil, expectedRevision: nil, name: name, address: "", city: "", region: "",
        country: "", latitude: latitude, longitude: longitude, notes: "", relatedEntryIDs: [])
    }
  }
}
struct PhotoPlaceOption: Decodable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let revision: Int
  let latitude: Double?
  let longitude: Double?
}
struct PhotoPlaceOptions: Decodable, Sendable {
  let places: [PhotoPlaceOption]
  let hasMore: Bool
}

struct EntryPhotoInfo: Decodable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let imageUrl: String?

  func displayURL(base: URL?) -> URL? {
    guard let base, let imageUrl else { return nil }
    return MediaDelivery.validatedURLs(
      [id.uuidString: imageUrl], paths: [id.uuidString], base: base)[id.uuidString]
  }
}
struct EntryPhotosResponse: Decodable, Sendable {
  let photos: [EntryPhotoInfo]
  let hasMore: Bool
}
struct PhotoCameraMetadata: Decodable, Sendable {
  let attachmentId: UUID
  let sourceVersion: String
  let capturedLocal: String?
  let calendarDate: String?
  let offset: String?
  let latitude: Double?
  let longitude: Double?

  func calendarDraft(previous: OccurrenceDraft) throws -> OccurrenceDraft {
    guard let calendarDate,
      calendarDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    else { throw OccurrenceError.invalidDate }
    var result = previous
    result.precision = .day
    result.start = calendarDate
    result.end = ""
    result.label = ""
    _ = try result.resolve()
    return result
  }
}

struct EntryPhotoDatesView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  @Binding var occurrence: OccurrenceDraft
  @Binding var photoPlace: PhotoPlaceDraft?
  @State private var photos: [EntryPhotoInfo]?
  @State private var metadata: [UUID: PhotoCameraMetadata] = [:]
  @State private var busy = false
  @State private var message: String?

  var body: some View {
    Section("Photos & camera dates") {
      Text("Read the original photo's camera metadata. No AI, no automatic changes.")
        .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      Button(photos == nil ? "Show photos" : "Refresh photos") { Task { await load() } }
        .disabled(busy)
      if photos?.isEmpty == true {
        Text("No saved photos on this Entry.").foregroundStyle(MTColor.inkMuted)
      }
      ForEach(photos ?? []) { photo in
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          if let url = validImageURL(photo) {
            AsyncImage(url: url) { image in
              image.resizable().scaledToFill()
            } placeholder: {
              Color.clear
            }
            .frame(height: 160).clipped().clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
            .accessibilityLabel(photo.name)
          }
          Text(photo.name).font(MTTypography.body).textSelection(.enabled)
          Button(metadata[photo.id] == nil ? "Read camera date" : "Read metadata again") {
            Task { await load(photo) }
          }
          .disabled(busy)
          if let info = metadata[photo.id] {
            if let local = info.capturedLocal {
              Text(
                "Camera time: \(local.replacingOccurrences(of: "T", with: " "))\(info.offset.map { " (UTC\($0))" } ?? " (time zone not recorded)")"
              )
              .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            } else {
              Text("No valid capture date in this photo.").font(MTTypography.caption)
            }
            if let date = info.calendarDate {
              Button("Use calendar date \(date)") {
                do {
                  occurrence = try info.calendarDraft(previous: occurrence)
                  message =
                    "Calendar date added to the draft. Review it below, then Save changes or Done."
                } catch { message = "This camera date is invalid. Edit the date manually." }
              }.disabled(busy)
              Text(
                "Uses Day precision and replaces the draft's date range. It does not infer a time zone or save until you confirm."
              )
              .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
            }
            if let latitude = info.latitude, let longitude = info.longitude {
              Text(
                "Private GPS metadata is available. No Location is linked automatically."
              )
              .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted).textSelection(.enabled)
              Button("Use GPS for a Location") {
                photoPlace = PhotoPlaceDraft(
                  attachmentId: photo.id, latitude: latitude, longitude: longitude)
              }.disabled(
                busy || (photoPlace?.attachmentId == photo.id && photoPlace?.kind == "new"))
            }
          }
        }.padding(.vertical, MTSpacing.s2)
      }
      if busy { ProgressView() }
      if photoPlace != nil {
        PhotoPlaceDraftEditor(client: client, ownerID: ownerID, value: $photoPlace)
          .id("\(photoPlace?.attachmentId.uuidString ?? ""):\(photoPlace?.kind ?? "")")
      }
      if let message { Text(message).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted) }
    }
  }

  private func validImageURL(_ photo: EntryPhotoInfo) -> URL? {
    guard let raw = photo.imageUrl, let base = AppConfiguration.apiURL else { return nil }
    return MediaDelivery.validatedURLs(
      [photo.id.uuidString: raw], paths: [photo.id.uuidString], base: base)[photo.id.uuidString]
  }

  @MainActor
  private func load(_ photo: EntryPhotoInfo? = nil) async {
    guard !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      if let photo {
        let result: PhotoCameraMetadata = try await MediaDelivery.metadataRequest(
          path: "api/media/metadata",
          query: URLQueryItem(name: "attachmentId", value: photo.id.uuidString), client: client,
          ownerID: ownerID)
        guard result.attachmentId == photo.id else { throw OccurrenceError.invalidDate }
        metadata[photo.id] = result
      } else {
        let result: EntryPhotosResponse = try await MediaDelivery.metadataRequest(
          path: "api/media/photos", query: URLQueryItem(name: "entryId", value: entryID.uuidString),
          client: client, ownerID: ownerID)
        photos = result.photos
        metadata = [:]
        if result.hasMore { message = "Showing the first 100 photos." }
      }
    } catch {
      message = "Photos or camera metadata are unavailable. Try again. The originals are unchanged."
    }
  }
}

private struct PhotoPlaceDraftEditor: View {
  let client: SupabaseClient
  let ownerID: UUID
  @Binding var value: PhotoPlaceDraft?
  @State private var query = ""
  @State private var options: [PhotoPlaceOption] = []
  @State private var message: String?
  @State private var busy = false
  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text("Location to add when you save").font(MTTypography.body).bold()
      Text(
        "No Location is created or linked until Save changes or Done. Existing links stay unchanged."
      ).font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      if value?.kind == "new" {
        TextField(
          "New Location name", text: Binding(get: { value?.name ?? "" }, set: { value?.name = $0 }))
        Text("Geographic coordinates came from this photo and stay private. No address is inferred.")
          .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      } else {
        Text(
          "Link existing Location: \(value?.name ?? ""). Its name, coordinates, and other facts will not change."
        ).font(MTTypography.caption)
      }
      TextField("Find an existing Location", text: $query)
      Button("Search Locations") { Task { await search() } }.disabled(busy)
      if !options.isEmpty {
        Picker(
          "Existing Location",
          selection: Binding(
            get: { value?.placeId?.uuidString ?? "" },
            set: { raw in
              guard let place = options.first(where: { $0.id.uuidString == raw }),
                let attachment = value?.attachmentId
              else { return }
              value = PhotoPlaceDraft(
                kind: "existing", attachmentId: attachment, placeId: place.id,
                revision: place.revision, name: place.name)
            })
        ) {
          Text("Choose a Location").tag("")
          ForEach(options) { p in
            Text(p.name).tag(p.id.uuidString)
          }
        }
      }
      if let message { Text(message).font(MTTypography.caption) }
      Button("Remove Location from draft") { value = nil }
    }
  }
  @MainActor private func search() async {
    guard !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      let result: PhotoPlaceOptions = try await MediaDelivery.metadataRequest(
        path: "api/media/place-options", query: URLQueryItem(name: "query", value: query),
        client: client, ownerID: ownerID)
      options = result.places
      message =
        result.hasMore
        ? "First 100 Locations shown. Refine your search."
        : result.places.isEmpty ? "No matching Locations." : nil
    } catch { message = "Locations could not be loaded. Try again." }
  }
}

extension MediaDelivery {
  static func metadataRequest<T: Decodable>(
    path: String, query: URLQueryItem, client: SupabaseClient, ownerID: UUID
  ) async throws -> T {
    guard let base = AppConfiguration.apiURL,
      var components = URLComponents(
        url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
    else { throw URLError(.badURL) }
    components.queryItems = [query]
    guard let url = components.url else { throw URLError(.badURL) }
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw URLError(.userAuthenticationRequired) }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      try await client.auth.session.user.id == ownerID
    else { throw URLError(.badServerResponse) }
    return try JSONDecoder().decode(T.self, from: data)
  }
}
