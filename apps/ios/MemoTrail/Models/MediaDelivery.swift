import Foundation
@preconcurrency import Supabase

/// Retain the draft's identity; an uncertain response never authorizes deleting its original.
@MainActor
enum EntryPhotoUpload {
  struct WritingRevision: Encodable {
    let entryID: UUID
    let expectedRevision: Int

    enum CodingKeys: String, CodingKey {
      case entryID = "p_entry_id"
      case expectedRevision = "p_expected_revision"
    }
  }

  /// Photo-only changes commute with writing. Never adopt an unseen writing revision.
  static func writingRevision(client: SupabaseClient, entryID: UUID?, revision: Int?) async throws
    -> Int?
  {
    guard let entryID, let revision else { return revision }
    return try await confirmedWritingRevision(revision: revision) {
      try await client.rpc(
        "entry_writing_revision",
        params: WritingRevision(entryID: entryID, expectedRevision: revision)
      ).execute().value
    }
  }

  static func confirmedWritingRevision(revision: Int, request: () async throws -> Int) async throws
    -> Int
  {
    try Task.checkCancellation()
    let confirmed = try await request()
    try Task.checkCancellation()
    guard confirmed >= revision else { throw URLError(.badServerResponse) }
    return confirmed
  }

  static func confirm(
    upload: () async throws -> Void, register: () async throws -> Bool
  ) async throws -> Bool {
    try Task.checkCancellation()
    do { try await upload() } catch { try Task.checkCancellation() }
    try Task.checkCancellation()
    return try await register()
  }

  static func attach(
    _ draft: FirstTimePhotoDraft, entryID: UUID, ownerID: UUID, client: SupabaseClient,
    registration: String = "register_entry_attachment"
  ) async throws -> Bool {
    guard try await client.auth.session.user.id == ownerID else {
      throw URLError(.userAuthenticationRequired)
    }
    let path = draft.objectPath(ownerID: ownerID, entryID: entryID)
    return try await confirm {
      try await client.storage.from("entry-media").upload(
        path, data: draft.data,
        options: FileOptions(
          cacheControl: "3600", contentType: draft.mimeType.rawValue, upsert: false))
    } register: {
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      let rows: [RegisteredFirstTimeAttachment] = try await client.rpc(
        registration,
        params: RegisterFirstTimeAttachmentParameters(
          entryID: entryID, draft: draft, objectPath: path)
      ).execute().value
      guard try await client.auth.session.user.id == ownerID else {
        throw URLError(.userAuthenticationRequired)
      }
      return rows.first?.attachmentID == draft.id
    }
  }
}

enum MediaDelivery {
  struct RequestBody: Encodable {
    let paths: [String]
    let trash: Bool
  }
  struct ResponseBody: Decodable { let urls: [String: String] }

  static func displayURLs(
    paths: [String], client: SupabaseClient, ownerID: UUID, trash: Bool = false
  ) async -> [String: URL] {
    guard !paths.isEmpty, let base = AppConfiguration.apiURL else { return [:] }
    do {
      let session = try await client.auth.session
      guard session.user.id == ownerID else { return [:] }
      let unique = Array(Set(paths))
      var result: [String: URL] = [:]
      for index in stride(from: 0, to: unique.count, by: 100) {
        var request = URLRequest(url: base.appendingPathComponent("api/media/urls"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let chunk = Array(unique[index..<min(index + 100, unique.count)])
        request.httpBody = try JSONEncoder().encode(RequestBody(paths: chunk, trash: trash))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
        let body = try JSONDecoder().decode(ResponseBody.self, from: data)
        result.merge(validatedURLs(body.urls, paths: chunk, base: base)) { _, new in new }
      }
      guard try await client.auth.session.user.id == ownerID else { return [:] }
      return result
    } catch { return [:] }
  }

  static func validatedURLs(_ values: [String: String], paths: [String], base: URL) -> [String: URL]
  {
    var result: [String: URL] = [:]
    let allowed = Set(paths)
    for (path, raw) in values {
      guard allowed.contains(path), let url = URL(string: raw), url.scheme == base.scheme,
        url.host == base.host, url.port == base.port, url.user == nil, url.password == nil,
        url.path == "/api/media/image",
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: {
          $0.name == "token" && !($0.value ?? "").isEmpty
        }) == true
      else { continue }
      result[path] = url
    }
    return result
  }
}
