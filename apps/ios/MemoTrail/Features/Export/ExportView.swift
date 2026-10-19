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
  /// Web `exportTime`: en-US "MMM d, yyyy, h:mm a" in the profile time zone, UTC when it is not
  /// valid.
  static func timeLabel(_ value: String, timezone: String) -> String {
    guard let date = EntryTimestamp.date(from: value) else { return value }
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone =
      EntryOccurrence.validTimezone(timezone).flatMap(TimeZone.init(identifier:)) ?? .gmt
    formatter.dateFormat = "MMM d, yyyy, h:mm a"
    return formatter.string(from: date)
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
  /// The JSON error body the export route returns.
  struct Failure: Decodable {
    let error: String
    let code: String?
  }

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
      let failure = try? JSONDecoder().decode(Failure.self, from: data)
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

/// Web `/settings/export`: one Export everything action that prepares a consistent copy and
/// downloads it, then the recent exports that can be downloaded again or discarded. Downloads
/// stream to disk, then save or share through the system sheet.
struct ExportView: View {
  /// Keep in step with the server's limit on unexpired exports.
  nonisolated static let exportLimit = 2

  private enum Phase { case preparing, downloading }

  let client: SupabaseClient
  let ownerID: UUID
  @State private var snapshots: [ExportSnapshot] = []
  @State private var timezone = "UTC"
  @State private var busy = false
  @State private var phase: Phase?
  @State private var message: String?
  @State private var pendingCreate: UUID?
  @State private var discard: ExportSnapshot?
  @State private var file: URL?
  @State private var sharing = false
  @State private var operation: Task<Void, Never>?

  private var isFull: Bool { snapshots.count >= Self.exportLimit }

  var body: some View {
    MTPage(width: .compact, spacing: MTSpacing.s5) {
      MTPageHeader(eyebrow: "Your data", title: "Export")
      ExportCard(title: "Export everything") {
        paragraph(
          "One ZIP with complete JSON, readable Entry Markdown, CSV tables, and your original photos. It includes Trash and AI conversations."
        )
        paragraph(
          "The ZIP is not encrypted, so anyone you share it with can read it. Sync every device first; changes still waiting offline are not included."
        )
        Button(phase == .preparing ? "Preparing export…" : "Export everything") {
          exportEverything()
        }
        .mtButtonStyle(isLoading: phase == .preparing)
        .disabled(busy || isFull)
        .accessibilityIdentifier("export-everything")
        if isFull {
          Text("Discard a recent export below to make a new one.")
            .font(MTFont.detail)
            .foregroundStyle(MTColor.inkMuted)
        }
      }
      if let phase {
        ExportNotice {
          HStack(spacing: MTSpacing.s3) {
            ProgressView().tint(MTColor.accent)
            paragraph(
              phase == .preparing
                ? "Preparing a consistent copy of everything…" : "Downloading to disk…")
          }
          if phase == .downloading {
            Button("Cancel download") { operation?.cancel() }
              .mtButtonStyle(.secondary)
          }
        }
      }
      if let message {
        ExportNotice {
          paragraph(message)
        }
        .accessibilityIdentifier("export-message")
      }
      if file != nil {
        ExportCard(title: "Complete ZIP ready") {
          paragraph(
            "This temporary download is removed when you leave this screen. Files you save or share are yours to manage."
          )
          MTFlowLayout(spacing: MTSpacing.s2_5) {
            Button("Save or share ZIP") { sharing = true }
              .mtButtonStyle()
            Button("Remove local copy") { clearFile() }
              .mtButtonStyle(.secondary)
          }
        }
      }
      recentExports
    }
    .refreshable { await load() }
    .navigationTitle("Export")
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .onDisappear {
      operation?.cancel()
      clearFile()
    }
    .sheet(isPresented: $sharing) { if let file { ExportShareSheet(url: file) } }
  }

  /// Web's Recent exports: shown only while an export can still be downloaded again.
  @ViewBuilder private var recentExports: some View {
    if !snapshots.isEmpty {
      VStack(alignment: .leading, spacing: MTSpacing.s4) {
        VStack(alignment: .leading, spacing: MTSpacing.s2) {
          Text("Recent exports")
            .font(MTFont.panelTitle)
            .foregroundStyle(MTColor.ink)
            .accessibilityAddTraits(.isHeader)
          paragraph(
            "Each export can be downloaded again for 24 hours and keeps the copy it made, even if you later edit or delete records. Discard one to delete its copy sooner."
          )
        }
        ForEach(snapshots) { snapshot in
          ExportCard(
            title: ExportSnapshot.timeLabel(snapshot.capturedAt, timezone: timezone),
            level: .item
          ) {
            MTWordFlow(.subheadline) {
              Text(countLabel(snapshot.rowCount, "record"))
              MTFlowSeparator()
              Text(countLabel(snapshot.datasets["entries"] ?? 0, "Entry"))
              MTFlowSeparator()
              Text(countLabel(snapshot.datasets["media_objects"] ?? 0, "media file"))
            }
            .font(MTFont.body)
            .foregroundStyle(MTColor.inkMuted)
            .mtLineSpacing(1.65)
            paragraph(
              "Available until \(ExportSnapshot.timeLabel(snapshot.expiresAt, timezone: timezone))"
            )
            MTFlowLayout(spacing: MTSpacing.s2_5) {
              Button("Download again") { downloadAgain(snapshot) }
                .mtButtonStyle(.secondary)
                .disabled(busy)
              Button("Discard") { discard = snapshot }
                .mtButtonStyle(.danger)
                .disabled(busy)
            }
            if discard?.id == snapshot.id {
              // Web's inline confirmation, which keeps the choice beside its export.
              ExportNotice {
                paragraph(
                  "Discard this export? Your records and any ZIP you already downloaded stay unchanged."
                )
                MTFlowLayout(spacing: MTSpacing.s2_5) {
                  Button("Confirm discard") { discardSnapshot(snapshot) }
                    .mtButtonStyle(.danger)
                    .disabled(busy)
                  Button("Keep export") { discard = nil }
                    .mtButtonStyle(.secondary)
                    .disabled(busy)
                }
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

  /// Runs one action at a time, like Web `run`, and clears its progress when it ends.
  private func run(_ action: @escaping @MainActor () async -> Void) {
    guard !busy else { return }
    busy = true
    message = nil
    operation = Task {
      await action()
      busy = false
      phase = nil
      operation = nil
    }
  }

  /// Prepares a consistent copy of everything, then saves it as one ZIP. A retried export reuses
  /// its id, so a lost answer cannot make a second copy.
  private func exportEverything() {
    run {
      clearFile()
      let id = pendingCreate ?? UUID()
      pendingCreate = id
      phase = .preparing
      let snapshot: ExportSnapshot
      do {
        let result: ExportMutation = try await ExportAPI.post(
          ExportInput(action: "create", id: id), client: client, ownerID: ownerID)
        guard let created = result.snapshot else { throw URLError(.badServerResponse) }
        snapshot = created
        pendingCreate = nil
        try Task.checkCancellation()
        await load()
      } catch {
        if let code = (error as NSError).userInfo["serverCode"] as? String,
          ["expired", "request_unavailable"].contains(code)
        {
          pendingCreate = nil
        }
        if !Task.isCancelled {
          message =
            (error as NSError).domain == "MemoTrail.Export"
            ? error.localizedDescription : "Could not prepare the export. Try again."
        }
        return
      }
      await save(snapshot)
    }
  }

  private func downloadAgain(_ snapshot: ExportSnapshot) {
    run {
      clearFile()
      await save(snapshot)
    }
  }

  private func discardSnapshot(_ snapshot: ExportSnapshot) {
    run {
      do {
        let _: ExportMutation = try await ExportAPI.post(
          ExportInput(action: "discard", id: snapshot.id), client: client, ownerID: ownerID)
        try Task.checkCancellation()
        discard = nil
        MTToastCenter.shared.success(
          "Export discarded. Your records and downloaded files are unchanged.")
        await load()
      } catch {
        if !Task.isCancelled {
          message =
            (error as NSError).domain == "MemoTrail.Export"
            ? error.localizedDescription : "Could not discard the export. Try again."
        }
      }
    }
  }

  private func load() async {
    ExportAPI.purgeAbandonedDownloads()
    do {
      let result: ExportWorkspace = try await ExportAPI.post(
        ExportInput(action: "list"), client: client, ownerID: ownerID)
      try Task.checkCancellation()
      snapshots = result.snapshots
      let profile: ProfileSettings? = try? await client.from("profiles").select("timezone")
        .eq("user_id", value: ownerID.uuidString).single().execute().value
      timezone = profile?.timezone ?? "UTC"
    } catch {
      if !Task.isCancelled { message = "Could not load recent exports. Refresh to retry." }
    }
  }

  /// Streams the ZIP to disk, then offers it to save or share.
  private func save(_ snapshot: ExportSnapshot) async {
    phase = .downloading
    do {
      let url = try await ExportAPI.download(snapshot, client: client, ownerID: ownerID)
      if Task.isCancelled {
        ExportAPI.removeDownload(url)
        message = "Download cancelled. You can download this export again below."
        return
      }
      file = url
      MTToastCenter.shared.success("Export ready. Save or share it before leaving this screen.")
    } catch {
      message =
        Task.isCancelled
        ? "Download cancelled. You can download this export again below."
        : "The download did not complete, so no ZIP was saved. An original photo may be missing or changed, or the connection was interrupted. Download it again below, or export again."
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
    VStack(alignment: .leading, spacing: MTSpacing.s3_5) {
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
