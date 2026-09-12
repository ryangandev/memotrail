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
  let action: String
  var id: UUID?
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
    Form {
      Section("Everything, in one ZIP") {
        Text(
          "Complete JSON, readable Entry Markdown, structured CSV tables, and original photos. Includes Trash, edit history, relationships, and AI conversations."
        )
        Text(
          "No AI processing. This ZIP is not encrypted; anyone you share it with can read it. Sync every device first: unsynced offline changes are not included."
        )
        .foregroundStyle(MTColor.inkMuted)
      }
      Section {
        Button("Prepare snapshot") { run { await change("create") } }.disabled(
          busy || snapshots.count >= 2)
        Button("Refresh") { run { await load() } }.disabled(busy)
      } header: {
        Text("Prepare a snapshot")
      } footer: {
        Text(
          "Capture one consistent moment across your devices. Keep up to two snapshots for 24 hours. Copies retain that content even after later edits or deletions. Discard a snapshot to remove its copied content sooner. Changed or missing original media stops the download."
        )
      }
      if let message { Section { Text(message).accessibilityIdentifier("export-message") } }
      if downloading {
        Section {
          ProgressView("Downloading to disk…")
          Button("Cancel download") { operation?.cancel() }
        }
      } else if busy {
        Section { ProgressView() }
      }
      if file != nil {
        Section("Complete ZIP ready") {
          Button("Save or share ZIP") { sharing = true }
          Button("Remove local copy") { clearFile() }
          Text(
            "This temporary download is removed when you leave this screen. Files you save or share are yours to manage."
          ).foregroundStyle(MTColor.inkMuted)
        }
      }
      Section("Available snapshots") {
        if snapshots.isEmpty { Text("No snapshots yet. Your archive is unchanged.") }
        ForEach(snapshots) { snapshot in
          VStack(alignment: .leading, spacing: 10) {
            Text(ExportSnapshot.dateLabel(snapshot.capturedAt)).font(.headline)
            Text(
              "\(snapshot.rowCount) records · \(snapshot.datasets["entries"] ?? 0) Entries · \(snapshot.datasets["media_objects"] ?? 0) media files"
            )
            .font(.caption).foregroundStyle(MTColor.inkMuted)
            Text("Expires \(ExportSnapshot.dateLabel(snapshot.expiresAt))").font(.caption)
            Button("Download ZIP") { run { await download(snapshot) } }.disabled(busy)
            Button("Discard snapshot", role: .destructive) { discard = snapshot }.disabled(busy)
          }.padding(.vertical, 8)
        }
      }
      Section {
        Text(
          "Downloads stream to disk. If the connection or server time limit interrupts the ZIP, it is not offered as a complete backup. Retry the same snapshot or prepare a new one."
        ).foregroundStyle(MTColor.inkMuted)
      }
    }
    .navigationTitle("Export archive")
    .task { await load() }
    .onDisappear {
      operation?.cancel()
      clearFile()
    }
    .confirmationDialog(
      "Discard this temporary copy? Your records and downloaded files stay unchanged.",
      isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } }),
      titleVisibility: .visible
    ) {
      if let discard {
        Button("Discard snapshot", role: .destructive) {
          run { await change("discard", id: discard.id) }
          self.discard = nil
        }
      }
      Button("Keep snapshot", role: .cancel) { discard = nil }
    }
    .sheet(isPresented: $sharing) { if let file { ExportShareSheet(url: file) } }
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
      message =
        action == "create"
        ? "Snapshot prepared. Download it on either device within 24 hours."
        : "Temporary copy discarded. Your records are unchanged."
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
      message = "Complete ZIP downloaded. Save or share it before leaving this screen."
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
private struct ExportShareSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
