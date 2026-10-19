import Foundation
@preconcurrency import Supabase
import SwiftUI

struct PhotoCameraMetadata: Decodable, Sendable {
  let attachmentId: UUID
  let sourceVersion: String
  let capturedLocal: String?
  let calendarDate: String?
  let offset: String?
  let latitude: Double?
  let longitude: Double?

  /// Web `photoCalendarDateDraft`: the camera's calendar date as a Day in the draft's zone.
  func calendarDraft(previous: OccurrenceDraft) throws -> OccurrenceDraft {
    guard let calendarDate else {
      throw SaveEntryError.invalid("This camera date is invalid. Edit the date manually.")
    }
    var result = previous
    try result.useCalendarDate(calendarDate)
    return result
  }
}

/// Web `EntryPhotoDates`: reads a saved photo's camera date or GPS position on request, then
/// offers it as an explicit draft change. Nothing changes until the editor is saved.
struct EntryPhotoDatesView: View {
  let client: SupabaseClient
  let ownerID: UUID
  /// The Entry's saved photos.
  let photos: [EntryPhotoInfo]
  @Binding var occurrence: OccurrenceDraft
  @Binding var photoLocation: PhotoLocationDraft?
  @State private var metadata: [UUID: PhotoCameraMetadata] = [:]
  @State private var busy = false
  @State private var errorMessage: String?
  @State private var notice: String?

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s2) {
      Text("Camera dates")
        .font(MTFont.listHeading)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      caption("Read a saved photo’s camera date or GPS position. No AI, no automatic changes.")
      ForEach(photos) { photo in
        Divider().overlay(MTColor.border)
        HStack(alignment: .top, spacing: MTSpacing.s3) {
          if let url = photo.displayURL(base: AppConfiguration.apiURL) {
            MTRemoteImage(url: url, accessibilityLabel: photo.name)
              .frame(width: MTLayout.PhotoDate.thumbWidth, height: MTLayout.PhotoDate.thumbHeight)
              .clipShape(RoundedRectangle(cornerRadius: MTRadius.small))
          }
          VStack(alignment: .leading, spacing: MTSpacing.s2) {
            Text(photo.name)
              .font(MTFont.label)
              .foregroundStyle(MTColor.ink)
              .lineLimit(2)
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
          .fixedSize(horizontal: false, vertical: true)
      }
      if photoLocation != nil {
        PhotoLocationDraftEditor(value: $photoLocation)
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
          errorMessage = error.localizedDescription
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
      Button("Use GPS for a Location") {
        photoLocation = PhotoLocationDraft(
          attachmentId: photo.id, latitude: latitude, longitude: longitude)
      }
      .mtButtonStyle(.secondary, size: .small)
      .disabled(busy || photoLocation?.attachmentId == photo.id)
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.body)
      .fixedSize(horizontal: false, vertical: true)
  }

  @MainActor
  private func load(_ photo: EntryPhotoInfo) async {
    guard !busy else { return }
    busy = true
    errorMessage = nil
    notice = nil
    defer { busy = false }
    do {
      let result: PhotoCameraMetadata = try await MediaDelivery.apiRequest(
        path: "api/media/metadata",
        query: URLQueryItem(name: "attachmentId", value: photo.id.uuidString.lowercased()),
        client: client, ownerID: ownerID)
      guard result.attachmentId == photo.id else { throw URLError(.badServerResponse) }
      metadata[photo.id] = result
    } catch {
      errorMessage = "Photo metadata is unavailable. The original is unchanged."
    }
  }
}

/// Web `PhotoLocationEditor`: the photo's GPS position waiting to be saved as this Entry's
/// Location.
private struct PhotoLocationDraftEditor: View {
  @Binding var value: PhotoLocationDraft?

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
