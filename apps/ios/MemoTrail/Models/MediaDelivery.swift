import Foundation
@preconcurrency import Supabase

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
