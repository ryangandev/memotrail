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

/// Web `EntryPhotoDates`: reads saved photos' camera metadata on request, then offers the
/// calendar date or GPS position as explicit draft changes.
struct EntryPhotoDatesView: View {
  let client: SupabaseClient
  let ownerID: UUID
  let entryID: UUID
  @Binding var occurrence: OccurrenceDraft
  @Binding var photoPlace: PhotoPlaceDraft?
  @State private var photos: [EntryPhotoInfo]?
  @State private var metadata: [UUID: PhotoCameraMetadata] = [:]
  @State private var busy = false
  @State private var errorMessage: String?
  @State private var notice: String?

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      HStack(alignment: .center, spacing: MTSpacing.s3) {
        Text("Photos & camera dates")
          .font(MTFont.listHeading)
          .foregroundStyle(MTColor.ink)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 0)
        Button(
          busy && photos == nil ? "Loading…" : photos == nil ? "Show photos" : "Refresh photos"
        ) {
          Task { await load() }
        }
        .mtButtonStyle(.secondary, size: .small)
        .disabled(busy)
        .accessibilityIdentifier("review-show-photos")
      }
      caption("Read the original photo’s camera metadata. No AI, no automatic changes.")
      if photos?.isEmpty == true {
        caption("No saved photos on this Entry.")
      }
      ForEach(photos ?? []) { photo in
        Divider().overlay(MTColor.border)
        HStack(alignment: .top, spacing: MTSpacing.s3) {
          if let url = validImageURL(photo) {
            MTRemoteImage(url: url, accessibilityLabel: photo.name)
              .frame(width: MTLayout.PhotoDate.thumbWidth, height: MTLayout.PhotoDate.thumbHeight)
              .clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
          }
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            Text(photo.name)
              .font(MTFont.label)
              .foregroundStyle(MTColor.ink)
              .textSelection(.enabled)
            Button(metadata[photo.id] == nil ? "Read camera date" : "Read metadata again") {
              Task { await load(photo) }
            }
            .mtButtonStyle(.secondary, size: .small)
            .disabled(busy)
            if let info = metadata[photo.id] {
              details(info, photo: photo)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, MTSpacing.s1)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(MTFont.detail)
          .foregroundStyle(MTColor.warm)
      }
      if photoPlace != nil {
        PhotoPlaceDraftEditor(value: $photoPlace)
          .disabled(busy)
      }
      if let notice { caption(notice) }
    }
    .padding(MTSpacing.s4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.medium))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Photo date suggestions")
  }

  @ViewBuilder
  private func details(_ info: PhotoCameraMetadata, photo: EntryPhotoInfo) -> some View {
    if let local = info.capturedLocal {
      caption(
        "Camera time: \(local.replacingOccurrences(of: "T", with: " "))\(info.offset.map { " (UTC\($0))" } ?? " (time zone not recorded)")"
      )
    } else {
      caption("No valid capture date in this photo.")
    }
    if let date = info.calendarDate {
      Button("Use calendar date \(date)") {
        do {
          occurrence = try info.calendarDraft(previous: occurrence)
          errorMessage = nil
          notice = "Calendar date added to the draft. Review the date, then save your changes."
        } catch {
          errorMessage = "This camera date is invalid. Edit the date manually."
        }
      }
      .mtButtonStyle(.secondary, size: .small)
      .disabled(busy)
      caption(
        "Uses Day precision and replaces the draft’s date range. It does not infer a time zone or save until you confirm."
      )
    }
    if let latitude = info.latitude, let longitude = info.longitude {
      caption("Private GPS metadata is available. No Location is linked automatically.")
        .textSelection(.enabled)
      Button("Use GPS for a Location") {
        photoPlace = PhotoPlaceDraft(
          attachmentId: photo.id, name: "Photo GPS location", latitude: latitude,
          longitude: longitude)
      }
      .mtButtonStyle(.secondary, size: .small)
      .disabled(busy || (photoPlace?.attachmentId == photo.id && photoPlace?.kind == "new"))
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
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
    errorMessage = nil
    notice = nil
    defer { busy = false }
    do {
      if let photo {
        let result: PhotoCameraMetadata = try await MediaDelivery.apiRequest(
          path: "api/media/metadata",
          query: URLQueryItem(name: "attachmentId", value: photo.id.uuidString), client: client,
          ownerID: ownerID)
        guard result.attachmentId == photo.id else { throw OccurrenceError.invalidDate }
        metadata[photo.id] = result
      } else {
        let result: EntryPhotosResponse = try await MediaDelivery.apiRequest(
          path: "api/media/photos", query: URLQueryItem(name: "entryId", value: entryID.uuidString),
          client: client, ownerID: ownerID)
        photos = result.photos
        metadata = [:]
        if result.hasMore { notice = "Showing the first 100 photos." }
      }
    } catch {
      errorMessage =
        photo == nil
        ? "Photos could not be loaded. Try again."
        : "Photo metadata is unavailable. The original is unchanged."
    }
  }
}

/// Web `PhotoPlaceEditor`: the photo's GPS position waiting to be saved as this Entry's Location.
private struct PhotoPlaceDraftEditor: View {
  @Binding var value: PhotoPlaceDraft?

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("Photo Location to add when you save")
        .font(MTFont.listHeading)
        .foregroundStyle(MTColor.ink)
      Text(
        "The photo’s GPS position will be saved for this Entry after you confirm. No address or personal Location name is inferred."
      )
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .fixedSize(horizontal: false, vertical: true)
      if let latitude = value?.latitude, let longitude = value?.longitude {
        Text(String(format: "%.5f, %.5f", latitude, longitude))
          .font(MTFont.detail.monospacedDigit())
          .foregroundStyle(MTColor.inkMuted)
          .textSelection(.enabled)
      }
      Button("Remove Location from draft") { value = nil }
        .mtButtonStyle(.secondary, size: .small)
    }
    .padding(MTSpacing.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.small).strokeBorder(
        MTColor.border, lineWidth: MTSize.Stroke.thin)
    }
    .padding(.top, MTSpacing.s1)
  }
}

extension MediaDelivery {
  static func apiRequest<T: Decodable>(
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
