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
    guard kind == "new", placeId == nil, revision == nil,
      !name.trimmed.isEmpty, name.trimmed.count <= 200,
      let latitude, let longitude, latitude.isFinite, longitude.isFinite,
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else { throw PhotoLocationError.invalidDraft }
  }

}
enum PhotoLocationError: LocalizedError {
  case invalidDraft

  var errorDescription: String? {
    "Add a Location label and valid photo coordinates, or remove the Location from this draft."
  }
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
    result.endMode = .date
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
        PhotoPlaceDraftEditor(value: $photoPlace)
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
  @Binding var value: PhotoPlaceDraft?
  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) {
      Text("Location to add when you save").font(MTTypography.body).bold()
      Text("This creates a private Location snapshot for this Entry when you save.")
        .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      TextField(
        "Location label", text: Binding(get: { value?.name ?? "" }, set: { value?.name = $0 }))
      Text("Coordinates came from this photo. No address is inferred.")
        .font(MTTypography.caption).foregroundStyle(MTColor.inkMuted)
      Button("Remove Location from draft") { value = nil }
    }
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
