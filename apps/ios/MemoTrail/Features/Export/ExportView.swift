import Foundation
@preconcurrency import Supabase
import SwiftUI
import UIKit

struct ExportSnapshot: Decodable, Identifiable, Sendable {
  enum CodingKeys: String, CodingKey {
    case id, datasets
    case schemaVersion = "schema_version"
    case capturedAt = "captured_at"
    case expiresAt = "expires_at"
    case rowCount = "row_count"
    case jsonBytes = "json_bytes"
  }
  let id: UUID
  let schemaVersion: Int
  let capturedAt: String
  let expiresAt: String
  let rowCount: Int
  let jsonBytes: Int
  let datasets: [String: Int]

  var filename: String {
    "MemoTrail-\(capturedAt.prefix(10))-\(id.uuidString.lowercased().prefix(8)).zip"
  }
  static func dateLabel(_ value: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = parser.date(from: value)
    if date == nil {
      parser.formatOptions = [.withInternetDateTime]
      date = parser.date(from: value)
    }
    return date?.formatted(date: .abbreviated, time: .shortened) ?? value
  }
}
struct ExportInput: Encodable, Sendable {
  enum CodingKeys: String, CodingKey { case action, id }
  let action: String
  var id: UUID?

  /// Sends the canonical lowercase UUID that Web and Postgres return, not Foundation's uppercase.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(action, forKey: .action)
    try container.encodeIfPresent(id?.uuidString.lowercased(), forKey: .id)
  }
}
struct ExportWorkspace: Decodable, Sendable { let snapshots: [ExportSnapshot] }
struct ExportMutation: Decodable, Sendable {
  let snapshot: ExportSnapshot?
  let discarded: Bool?
}
enum ExportAPI {
  static let completion = "MEMOTRAIL_EXPORT_V1_COMPLETE"
  static var tailSize: Int { 22 + completion.utf8.count }
  static func isComplete(_ data: Data) -> Bool {
    guard data.count >= tailSize else { return false }
    let tail = Array(data.suffix(tailSize))
    return Array(tail.prefix(4)) == [0x50, 0x4b, 0x05, 0x06]
      && tail[20] == completion.utf8.count && tail[21] == 0
      && String(bytes: tail.dropFirst(22), encoding: .utf8) == completion
  }
  static func request(_ input: ExportInput, client: SupabaseClient, ownerID: UUID) async throws
    -> URLRequest
  {
    let session = try await client.auth.session
    guard session.user.id == ownerID else { throw URLError(.userAuthenticationRequired) }
    guard let base = AppConfiguration.apiURL else { throw URLError(.badURL) }
    var request = URLRequest(url: base.appendingPathComponent("api/export"))
    request.httpMethod = "POST"
    request.timeoutInterval = 300
    request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(input)
    return request
  }
  static func post<T: Decodable & Sendable>(
    _ input: ExportInput, client: SupabaseClient, ownerID: UUID
  ) async throws -> T {
    let request = try await request(input, client: client, ownerID: ownerID)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      let failure = try? JSONDecoder().decode(AIAPI.Failure.self, from: data)
      throw NSError(
        domain: "MemoTrail.Export", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: failure?.error
            ?? "Could not reach the export server. Your records are unchanged.",
          "serverCode": failure?.code ?? "",
        ])
    }
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
    return try JSONDecoder().decode(T.self, from: data)
  }
  static func download(_ snapshot: ExportSnapshot, client: SupabaseClient, ownerID: UUID)
    async throws -> URL
  {
    let request = try await request(
      ExportInput(action: "download", id: snapshot.id), client: client, ownerID: ownerID)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 300
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let (temporary, response) = try await session.download(for: request)
    defer { try? FileManager.default.removeItem(at: temporary) }
    guard let http = response as? HTTPURLResponse, http.statusCode == 200,
      http.mimeType == "application/zip"
    else { throw URLError(.badServerResponse) }
    let handle = try FileHandle(forReadingFrom: temporary)
    defer { try? handle.close() }
    let size = try handle.seekToEnd()
    guard size >= tailSize else { throw URLError(.cannotDecodeContentData) }
    try handle.seek(toOffset: size - UInt64(tailSize))
    guard let tail = try handle.read(upToCount: tailSize), isComplete(tail) else {
      throw URLError(.cannotDecodeContentData)
    }
    try Task.checkCancellation()
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MemoTrailExport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: folder, withIntermediateDirectories: false,
      attributes: [.protectionKey: FileProtectionType.complete])
    let target = folder.appendingPathComponent(snapshot.filename)
    do {
      try FileManager.default.moveItem(at: temporary, to: target)
      try FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
      var excluded = folder
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try excluded.setResourceValues(values)
      return target
    } catch {
      try? FileManager.default.removeItem(at: folder)
      throw error
    }
  }
  static func removeDownload(_ url: URL) {
    let folder = url.deletingLastPathComponent()
    guard folder.lastPathComponent.hasPrefix("MemoTrailExport-"),
      folder.deletingLastPathComponent().standardizedFileURL
        == FileManager.default.temporaryDirectory.standardizedFileURL
    else { return }
    try? FileManager.default.removeItem(at: folder)
  }
  static func purgeAbandonedDownloads() {
    let manager = FileManager.default
    guard
      let folders = try? manager.contentsOfDirectory(
        at: manager.temporaryDirectory,
        includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey])
    else { return }
    for folder in folders where folder.lastPathComponent.hasPrefix("MemoTrailExport-") {
      guard
        UUID(uuidString: String(folder.lastPathComponent.dropFirst("MemoTrailExport-".count)))
          != nil,
        let values = try? folder.resourceValues(forKeys: [.creationDateKey, .isDirectoryKey]),
        values.isDirectory == true, let created = values.creationDate,
        created < Date().addingTimeInterval(-86400)
      else { continue }
      try? manager.removeItem(at: folder)
    }
  }
}

/// Web `/settings/export`: what the ZIP holds, preparing a snapshot, and each snapshot's download
/// and discard. Downloads stream to disk, then save or share through the system sheet.
struct ExportView: View {
  let client: SupabaseClient
  let ownerID: UUID
  @State private var snapshots: [ExportSnapshot] = []
  @State private var busy = false
  @State private var downloading = false
  @State private var message: String?
  @State private var pendingCreate: UUID?
  @State private var discard: ExportSnapshot?
  @State private var file: URL?
  @State private var sharing = false
  @State private var operation: Task<Void, Never>?

  var body: some View {
    MTPage(width: .compact, spacing: MTSpacing.s5) {
      MTPageHeader(
        eyebrow: "Your archive, to keep", title: "Export archive",
        description: "A portable copy of your story. No AI processing.")
      ExportCard(title: "Everything, in one ZIP") {
        paragraph(
          "Complete JSON, readable Entry Markdown, structured CSV tables, and original photos. Includes Trash, edit history, relationships, and AI conversations."
        )
        paragraph(
          "The ZIP is not encrypted. Anyone you share it with can read it. Unsynced offline changes are not included; sync every device first."
        )
      }
      ExportCard(title: "Prepare a snapshot") {
        paragraph(
          "Capture one consistent moment across your devices. Temporary copies retain that content for 24 hours, even if you later edit or delete the originals. Discard a snapshot to remove its copied content sooner."
        )
        paragraph(
          "Keep up to two snapshots. Original media is verified during download; changed or missing files stop the export."
        )
        MTFlowLayout(spacing: MTSpacing.actionGap) {
          Button("Prepare snapshot") { run { await change("create") } }
            .mtButtonStyle(isLoading: busy && !downloading && pendingCreate != nil)
            .disabled(busy || snapshots.count >= 2)
          Button("Refresh") { run { await load() } }
            .mtButtonStyle(.secondary)
            .disabled(busy)
        }
      }
      if let message {
        ExportNotice {
          paragraph(message)
        }
        .accessibilityIdentifier("export-message")
      }
      if downloading {
        ExportNotice {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            paragraph("Downloading to disk…")
          }
          Button("Cancel download") { operation?.cancel() }
            .mtButtonStyle(.secondary)
        }
      }
      if file != nil {
        ExportCard(title: "Complete ZIP ready") {
          paragraph(
            "This temporary download is removed when you leave this screen. Files you save or share are yours to manage."
          )
          MTFlowLayout(spacing: MTSpacing.actionGap) {
            Button("Save or share ZIP") { sharing = true }
              .mtButtonStyle()
            Button("Remove local copy") { clearFile() }
              .mtButtonStyle(.secondary)
          }
        }
      }
      snapshotList
      Text(
        "Downloads stream to disk. If the connection or server time limit interrupts the ZIP, it is not offered as a complete backup. Retry the same snapshot or prepare a new one."
      )
      .font(MTFont.detail)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(MTLineHeight.relaxed, textStyle: .caption1)
    }
    .navigationTitle("Export archive")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .onDisappear {
      operation?.cancel()
      clearFile()
    }
    .sheet(isPresented: $sharing) { if let file { ExportShareSheet(url: file) } }
  }

  private var snapshotList: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s4) {
      Text("Available snapshots")
        .font(MTFont.panelTitle)
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      if snapshots.isEmpty {
        paragraph("No snapshots yet. Your archive is unchanged.")
      }
      ForEach(snapshots) { snapshot in
        ExportCard(title: ExportSnapshot.dateLabel(snapshot.capturedAt), level: .item) {
          MTWordFlow(.subheadline) {
            Text("\(snapshot.rowCount.formatted()) records")
            MTFlowSeparator()
            Text("\(snapshot.datasets["entries"] ?? 0) Entries")
            MTFlowSeparator()
            Text("\(snapshot.datasets["media_objects"] ?? 0) media files")
          }
          .font(MTFont.body)
          .foregroundStyle(MTColor.inkMuted)
          .mtLineSpacing(1.65)
          paragraph("Expires \(ExportSnapshot.dateLabel(snapshot.expiresAt))")
          MTFlowLayout(spacing: MTSpacing.actionGap) {
            Button("Download ZIP") { run { await download(snapshot) } }
              .mtButtonStyle(.secondary)
              .disabled(busy)
            Button("Discard snapshot") { discard = snapshot }
              .mtButtonStyle(.danger)
              .disabled(busy)
          }
          if discard?.id == snapshot.id {
            // Web's inline confirmation, which keeps the choice beside its snapshot.
            ExportNotice {
              paragraph(
                "Discard this temporary copy? Your original records and downloaded ZIPs will stay unchanged."
              )
              MTFlowLayout(spacing: MTSpacing.actionGap) {
                Button("Confirm discard") {
                  run { await change("discard", id: snapshot.id) }
                }
                .mtButtonStyle(.danger)
                .disabled(busy)
                Button("Keep snapshot") { discard = nil }
                  .mtButtonStyle(.secondary)
                  .disabled(busy)
              }
            }
          }
        }
      }
    }
  }

  private func paragraph(_ text: String) -> some View {
    Text(text)
      .font(MTFont.body)
      .foregroundStyle(MTColor.inkMuted)
      .mtLineSpacing(1.65)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func run(_ action: @escaping @MainActor () async -> Void) {
    guard !busy else { return }
    busy = true
    operation = Task {
      await action()
      busy = false
      operation = nil
    }
  }
  private func load() async {
    ExportAPI.purgeAbandonedDownloads()
    do {
      let result: ExportWorkspace = try await ExportAPI.post(
        ExportInput(action: "list"), client: client, ownerID: ownerID)
      try Task.checkCancellation()
      snapshots = result.snapshots
    } catch { if !Task.isCancelled { message = error.localizedDescription } }
  }
  private func change(_ action: String, id: UUID? = nil) async {
    message = nil
    do {
      if action == "create" { if pendingCreate == nil { pendingCreate = UUID() } }
      let _: ExportMutation = try await ExportAPI.post(
        ExportInput(action: action, id: action == "create" ? pendingCreate : id), client: client,
        ownerID: ownerID)
      if action == "create" { pendingCreate = nil }
      try Task.checkCancellation()
      if action == "discard" { discard = nil }
      MTToastCenter.shared.success(
        action == "create"
          ? "Snapshot prepared. Download it on either device within 24 hours."
          : "Temporary copy discarded. Your records and downloaded files are unchanged.")
      await load()
    } catch {
      if let code = (error as NSError).userInfo["serverCode"] as? String,
        ["expired", "request_unavailable"].contains(code)
      {
        pendingCreate = nil
      }
      if !Task.isCancelled { message = error.localizedDescription }
    }
  }
  private func download(_ snapshot: ExportSnapshot) async {
    clearFile()
    downloading = true
    message = nil
    defer { downloading = false }
    do {
      let url = try await ExportAPI.download(snapshot, client: client, ownerID: ownerID)
      if Task.isCancelled {
        ExportAPI.removeDownload(url)
        return
      }
      file = url
      MTToastCenter.shared.success(
        "Complete ZIP downloaded. Save or share it before leaving this screen.")
    } catch {
      message =
        Task.isCancelled
        ? "Download cancelled. The snapshot is still available."
        : "Download did not complete. An original may be missing or changed, or the connection was interrupted. Retry or prepare a new snapshot. No complete ZIP was saved."
    }
  }
  private func clearFile() {
    if let file { ExportAPI.removeDownload(file) }
    file = nil
  }
}
/// Web `export-settings` card: a serif heading over its paragraphs and actions.
private struct ExportCard<Content: View>: View {
  enum Level { case section, item }

  let title: String
  var level: Level = .section
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.panelGap) {
      Text(title)
        .font(
          level == .section
            ? MTFont.panelTitle
            : MTFont.panelTitleSmall
        )
        .foregroundStyle(MTColor.ink)
        .accessibilityAddTraits(.isHeader)
      content
    }
    .padding(MTLayout.ExportPanel.padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MTColor.surface, in: RoundedRectangle(cornerRadius: MTRadius.large))
    .overlay {
      RoundedRectangle(cornerRadius: MTRadius.large).strokeBorder(MTColor.border)
    }
  }
}

/// Web `export-settings` notice: status, progress, or a confirmation on a subtle surface.
private struct ExportNotice<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: MTSpacing.s3) { content }
      .padding(MTSpacing.s4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(MTColor.surfaceSubtle, in: RoundedRectangle(cornerRadius: MTRadius.medium))
      .overlay {
        RoundedRectangle(cornerRadius: MTRadius.medium).strokeBorder(MTColor.border)
      }
  }
}

private struct ExportShareSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
