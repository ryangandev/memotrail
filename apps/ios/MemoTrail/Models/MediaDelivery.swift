import Foundation
@preconcurrency import Supabase

/// Uploads a photo original and registers it on its Entry. Registering never changes the Entry's
/// revision, so an editor keeps the revision it read. The draft keeps its identity, and an
/// uncertain answer never authorizes deleting its original.
@MainActor
enum EntryPhotoUpload {
  static func confirm(
    upload: () async throws -> Void, register: () async throws -> Bool
  ) async throws -> Bool {
    try Task.checkCancellation()
    // A failed upload may still have stored the original, so registering decides.
    do { try await upload() } catch { try Task.checkCancellation() }
    try Task.checkCancellation()
    return try await register()
  }

  static func attach(
    _ draft: PhotoDraft, entryID: UUID, ownerID: UUID, client: SupabaseClient
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
      let rows: [RegisteredEntryAttachment] = try await client.rpc(
        "register_entry_attachment",
        params: RegisterEntryAttachmentParameters(
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
  /// A signed-in `POST` to one of MemoTrail's own Web API routes, such as
  /// `api/media/photos?entryId=` or `api/media/metadata?attachmentId=`. The session must still
  /// belong to `ownerID` before and after the request.
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
