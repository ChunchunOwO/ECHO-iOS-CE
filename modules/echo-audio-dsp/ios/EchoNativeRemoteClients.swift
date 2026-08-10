import Foundation

enum EchoNativeRemoteKind: Sendable {
  case echo
  case poweramp

  var headerName: String {
    self == .echo ? "x-echo-link-version" : "x-poweramp-remote-version"
  }

  var pathPrefix: String {
    self == .echo ? "/echo-link/v1" : "/poweramp-remote/v1"
  }

  var source: EchoNativeTrackSource {
    self == .echo ? .echo : .remote
  }
}

enum EchoNativeNetworkError: LocalizedError {
  case invalidConnection
  case invalidResponse
  case server(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidConnection: return "连接地址、端口或 Token 无效。"
    case .invalidResponse: return "远程服务返回了无法识别的数据。"
    case let .server(code, message): return "\(code) \(message)"
    }
  }
}

final class EchoNativeRemoteClient: @unchecked Sendable {
  private struct TracksResponse: Decodable { let tracks: [EchoNativeCoreTrack]; let totalCount: Int }
  private struct AlbumsResponse: Decodable { let albums: [EchoNativeCoreAlbum]; let totalCount: Int }
  private struct LyricsResponse: Decodable { let lyrics: String }

  let baseUrl: URL
  let connection: EchoNativeConnection
  let kind: EchoNativeRemoteKind
  private let session: URLSession

  init(connection: EchoNativeConnection, kind: EchoNativeRemoteKind) throws {
    let rawHost = connection.host.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = rawHost.range(of: #"^https?://"#, options: .regularExpression) == nil
      ? "\(connection.scheme)://\(rawHost)"
      : rawHost
    let parsed = URLComponents(string: candidate)
    let scheme = parsed?.scheme?.lowercased() ?? connection.scheme
    let host = parsed?.host ?? ""
    let port = parsed?.port ?? connection.port
    var baseComponents = URLComponents()
    baseComponents.scheme = scheme
    baseComponents.host = host
    baseComponents.port = port
    guard connection.enabled, !host.isEmpty, !connection.token.isEmpty,
      scheme == "http" || scheme == "https",
      (1...65535).contains(port),
      let url = baseComponents.url
    else {
      throw EchoNativeNetworkError.invalidConnection
    }
    self.baseUrl = url
    self.connection = connection
    self.kind = kind
    let configuration = URLSessionConfiguration.ephemeral
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 60
    session = URLSession(configuration: configuration)
  }

  func status() async throws -> EchoNativePlaybackStatus {
    try await request(path: "status", timeout: 6)
  }

  func allTracks(query: String = "") async throws -> [EchoNativeCoreTrack] {
    try await paginatedTracks(path: "library/tracks", query: ["q": query])
  }

  func albumTracks(albumId: String) async throws -> [EchoNativeCoreTrack] {
    try await paginatedTracks(path: "library/albums/\(encodedPathComponent(albumId))/tracks")
  }

  private func paginatedTracks(path: String, query baseQuery: [String: String] = [:]) async throws -> [EchoNativeCoreTrack] {
    var values: [EchoNativeCoreTrack] = []
    var seenIds = Set<String>()
    var page = 1
    var pageSize = 200
    while page <= 500 {
      var query = baseQuery
      query["page"] = String(page)
      query["pageSize"] = String(pageSize)
      let response: TracksResponse = try await request(
        path: path,
        query: query
      )
      if page == 1, !response.tracks.isEmpty, response.tracks.count < pageSize { pageSize = response.tracks.count }
      let pageTracks = response.tracks.map { track in
        var value = track
        value.source = kind.source
        if value.sourceLabel.isEmpty { value.sourceLabel = kind == .echo ? "ECHO" : "Poweramp" }
        value.artworkUrl = absoluteUrl(value.artworkUrl)
        return value
      }
      let newTracks = pageTracks.filter { seenIds.insert($0.id).inserted }
      values.append(contentsOf: newTracks)
      if response.tracks.isEmpty || newTracks.isEmpty { break }
      page += 1
    }
    return echoDeduplicatedTracks(values)
  }

  func allAlbums(query: String = "") async throws -> [EchoNativeCoreAlbum] {
    var values: [EchoNativeCoreAlbum] = []
    var seenIds = Set<String>()
    var page = 1
    var pageSize = 200
    while page <= 500 {
      let response: AlbumsResponse = try await request(
        path: "library/albums",
        query: ["page": String(page), "pageSize": String(pageSize), "q": query]
      )
      if page == 1, !response.albums.isEmpty, response.albums.count < pageSize { pageSize = response.albums.count }
      let pageAlbums = response.albums.map { album in
        var value = album
        value.source = kind.source
        if value.sourceLabel.isEmpty { value.sourceLabel = kind == .echo ? "ECHO" : "Poweramp" }
        value.artworkUrl = absoluteUrl(value.artworkUrl)
        return value
      }
      let newAlbums = pageAlbums.filter { seenIds.insert($0.id).inserted }
      values.append(contentsOf: newAlbums)
      if response.albums.isEmpty || newAlbums.isEmpty { break }
      page += 1
    }
    return values
  }

  func command(_ payload: [String: Any]) async throws -> EchoNativePlaybackStatus {
    try await request(path: "playback/command", method: "POST", body: payload)
  }

  func stream(trackId: String) async throws -> EchoNativeStreamResponse {
    let response: EchoNativeStreamResponse = try await request(
      path: "library/tracks/\(encodedPathComponent(trackId))/stream",
      method: "POST",
      body: ["target": kind == .echo ? "phone" : "ios"]
    )
    var track = response.track
    track.source = kind.source
    if track.sourceLabel.isEmpty { track.sourceLabel = kind == .echo ? "ECHO" : "Poweramp" }
    track.artworkUrl = absoluteUrl(track.artworkUrl)
    return EchoNativeStreamResponse(
      expiresAtEpochMs: response.expiresAtEpochMs,
      streamUrl: absoluteUrl(response.streamUrl) ?? response.streamUrl,
      track: track
    )
  }

  func lyrics(trackId: String) async throws -> String {
    let response: LyricsResponse = try await request(
      path: "library/tracks/\(encodedPathComponent(trackId))/lyrics"
    )
    return response.lyrics
  }

  private func request<T: Decodable>(
    path: String,
    method: String = "GET",
    query: [String: String] = [:],
    body: [String: Any]? = nil,
    timeout: TimeInterval = 15
  ) async throws -> T {
    var components = URLComponents(
      url: baseUrl,
      resolvingAgainstBaseURL: false
    )
    components?.percentEncodedPath = "\(kind.pathPrefix)/\(path)"
    components?.queryItems = query
      .filter { !$0.value.isEmpty }
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let url = components?.url else { throw EchoNativeNetworkError.invalidConnection }
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
    request.setValue("1", forHTTPHeaderField: kind.headerName)
    if let body {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw EchoNativeNetworkError.invalidResponse }
    guard (200..<300).contains(http.statusCode) else {
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      throw EchoNativeNetworkError.server(http.statusCode, object?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
    }
    return try JSONDecoder().decode(T.self, from: data)
  }

  private func absoluteUrl(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return URL(string: value, relativeTo: baseUrl)?.absoluteURL.absoluteString
  }

  private func encodedPathComponent(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
  }

}

final class EchoNativeNeteaseClient: @unchecked Sendable {
  struct Profile: Sendable { let avatarUrl: String; let name: String; let userId: Int64 }
  struct Playlist: Identifiable, Sendable { let artworkUrl: String; let id: String; let name: String; let trackCount: Int }
  struct QrLogin: Sendable { let key: String; let url: String }
  struct QrStatus: Sendable { let code: Int?; let cookie: String?; let message: String? }

  private let baseUrl: URL
  private let cookie: String
  private let direct: Bool
  private let session: URLSession

  init(baseUrl rawBaseUrl: String = "https://music.163.com", cookie: String) {
    let normalized = rawBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    baseUrl = URL(string: normalized)?.absoluteURL ?? URL(string: "https://music.163.com")!
    direct = baseUrl.host?.lowercased() == "music.163.com"
    self.cookie = cookie
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 40
    configuration.waitsForConnectivity = true
    session = URLSession(configuration: configuration)
  }

  func profile() async throws -> Profile {
    struct Response: Decodable {
      struct Value: Decodable { let avatarUrl: String?; let nickname: String?; let userId: Int64? }
      let profile: Value?
    }
    let response: Response = try await request(path: direct ? "/api/nuser/account/get" : "/user/account")
    guard let value = response.profile, let userId = value.userId else {
      throw EchoNativeNetworkError.server(401, "网易云登录状态已失效。")
    }
    return Profile(avatarUrl: Self.secureMediaUrl(value.avatarUrl), name: value.nickname ?? "网易云用户", userId: userId)
  }

  func playlists(userId: Int64) async throws -> [Playlist] {
    struct Response: Decodable {
      struct Value: Decodable { let coverImgUrl: String?; let id: Int64?; let name: String?; let trackCount: Int? }
      let more: Bool?
      let playlist: [Value]?
    }
    var playlists: [Playlist] = []
    var seen = Set<String>()
    var offset = 0
    while true {
      var values = ["uid": String(userId), "limit": "100", "offset": String(offset)]
      if direct { values["includeVideo"] = "true" }
      let response: Response = try await request(path: direct ? "/api/user/playlist" : "/user/playlist", values: values)
      let page = response.playlist ?? []
      let additions = page.compactMap { value -> Playlist? in
        guard let id = value.id, let name = value.name, seen.insert(String(id)).inserted else { return nil }
        return Playlist(artworkUrl: Self.secureMediaUrl(value.coverImgUrl), id: String(id), name: name, trackCount: value.trackCount ?? 0)
      }
      playlists.append(contentsOf: additions)
      guard response.more == true, !page.isEmpty, !additions.isEmpty else { break }
      offset += page.count
    }
    return playlists
  }

  func search(_ keywords: String, limit: Int = 50) async throws -> [EchoNativeCoreTrack] {
    struct Response: Decodable { struct Result: Decodable { let songs: [Song]? }; let result: Result? }
    let response: Response = try await request(path: direct ? "/api/cloudsearch/pc" : "/cloudsearch", values: [
      direct ? "s" : "keywords": keywords, "limit": String(max(1, min(50, limit))), "offset": "0", "type": "1",
    ])
    return (response.result?.songs ?? []).compactMap(\.track)
  }

  func dailyRecommendations() async throws -> [EchoNativeCoreTrack] {
    struct Response: Decodable {
      struct Value: Decodable { let dailySongs: [Song]? }
      let data: Value?
      let recommend: [Song]?
    }
    let response: Response = try await request(
      path: direct ? "/api/v3/discovery/recommend/songs" : "/recommend/songs",
      values: direct ? ["total": "true"] : [:]
    )
    return (response.data?.dailySongs ?? response.recommend ?? []).compactMap(\.track)
  }

  func playlistTracks(id: String) async throws -> [EchoNativeCoreTrack] {
    if direct {
      struct Detail: Decodable {
        struct Value: Decodable {
          struct TrackId: Decodable { let id: Int64? }
          let trackIds: [TrackId]?
          let tracks: [Song]?
        }
        let playlist: Value?
      }
      struct Songs: Decodable { let songs: [Song]? }
      let detail: Detail = try await request(path: "/api/v6/playlist/detail", values: ["id": id, "n": "100000", "s": "8"])
      let inlineTracks = (detail.playlist?.tracks ?? []).compactMap(\.track)
      let ids = detail.playlist?.trackIds?.compactMap(\.id) ?? []
      guard !ids.isEmpty else { return inlineTracks }
      var tracks = inlineTracks
      var seen = Set(tracks.map(\.id))
      for start in stride(from: 0, to: ids.count, by: 500) {
        let chunk = Array(ids[start..<min(start + 500, ids.count)])
        let data = try JSONSerialization.data(withJSONObject: chunk.map { ["id": $0] })
        let value = String(data: data, encoding: .utf8) ?? "[]"
        do {
          let response: Songs = try await request(path: "/api/v3/song/detail", values: ["c": value])
          tracks.append(contentsOf: (response.songs ?? []).compactMap(\.track).filter { seen.insert($0.id).inserted })
        } catch {
          if tracks.isEmpty { throw error }
          break
        }
      }
      return tracks
    }
    struct Response: Decodable { let songs: [Song]? }
    var tracks: [EchoNativeCoreTrack] = []
    var seen = Set<String>()
    var offset = 0
    while true {
      let response: Response = try await request(path: "/playlist/track/all", values: ["id": id, "limit": "500", "offset": String(offset)])
      let songs = response.songs ?? []
      let page = songs.compactMap(\.track)
      let additions = page.filter { seen.insert($0.id).inserted }
      tracks.append(contentsOf: additions)
      if songs.count < 500 || additions.isEmpty { break }
      offset += songs.count
    }
    return tracks
  }

  func trackDetail(trackId: String) async throws -> EchoNativeCoreTrack {
    struct Response: Decodable { let songs: [Song]? }
    let response: Response
    if direct {
      guard let id = Int64(trackId) else { throw EchoNativeNetworkError.invalidResponse }
      let data = try JSONSerialization.data(withJSONObject: [["id": id]])
      response = try await request(
        path: "/api/v3/song/detail",
        values: ["c": String(data: data, encoding: .utf8) ?? "[]"]
      )
    } else {
      response = try await request(path: "/song/detail", values: ["ids": trackId])
    }
    guard let track = response.songs?.first?.track else { throw EchoNativeNetworkError.invalidResponse }
    return track
  }

  func lyrics(trackId: String) async throws -> String {
    struct Response: Decodable {
      struct Lyrics: Decodable { let lyric: String? }
      let lrc: Lyrics?
      let tlyric: Lyrics?
    }
    let response: Response = try await request(
      path: direct ? "/api/song/lyric" : "/lyric",
      values: direct
        ? ["id": trackId, "lv": "-1", "kv": "-1", "tv": "-1"]
        : ["id": trackId]
    )
    return [response.lrc?.lyric, response.tlyric?.lyric]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
  }

  func playbackUrl(trackId: String) async throws -> URL {
    struct Response: Decodable { struct Value: Decodable { let url: String? }; let data: [Value]? }
    let response: Response
    if direct {
      response = try await request(path: "/api/song/enhance/player/url", values: ["ids": "[\(trackId)]", "br": "999000"])
    } else {
      response = try await request(path: "/song/url/v1", values: ["id": trackId, "level": "exhigh"])
    }
    guard let raw = response.data?.first?.url, let url = URL(string: Self.secureMediaUrl(raw)) else {
      throw EchoNativeNetworkError.server(404, "该歌曲当前不可播放。")
    }
    return url
  }

  func createQrLogin() async throws -> QrLogin {
    guard !direct else { throw EchoNativeNetworkError.invalidResponse }
    struct KeyResponse: Decodable {
      struct Value: Decodable { let unikey: String? }
      let data: Value?
    }
    struct CodeResponse: Decodable {
      struct Value: Decodable { let qrurl: String? }
      let data: Value?
    }
    let keyResponse: KeyResponse = try await request(path: "/login/qr/key")
    guard let key = keyResponse.data?.unikey, !key.isEmpty else {
      throw EchoNativeNetworkError.invalidResponse
    }
    let codeResponse: CodeResponse = try await request(path: "/login/qr/create", values: ["key": key])
    guard let url = codeResponse.data?.qrurl, !url.isEmpty else {
      throw EchoNativeNetworkError.invalidResponse
    }
    return QrLogin(key: key, url: url)
  }

  func checkQrLogin(key: String) async throws -> QrStatus {
    guard !direct, !key.isEmpty else { throw EchoNativeNetworkError.invalidResponse }
    struct Response: Decodable {
      let code: Int?
      let cookie: String?
      let message: String?
    }
    let response: Response = try await request(
      path: "/login/qr/check",
      values: ["key": key, "noCookie": "true"]
    )
    return QrStatus(code: response.code, cookie: response.cookie, message: response.message)
  }

  private struct Song: Decodable {
    struct Album: Decodable { let name: String?; let picUrl: String? }
    struct Artist: Decodable { let name: String? }
    let al: Album?
    let album: Album?
    let ar: [Artist]?
    let artists: [Artist]?
    let dt: Double?
    let duration: Double?
    let id: Int64?
    let name: String?

    var track: EchoNativeCoreTrack? {
      guard let id, let name else { return nil }
      let albumValue = al ?? album
      return EchoNativeCoreTrack(
        album: albumValue?.name ?? "",
        albumArtist: "",
        artist: (ar ?? artists ?? []).compactMap(\.name).joined(separator: ", "),
        artworkUrl: EchoNativeNeteaseClient.secureMediaUrl(albumValue?.picUrl),
        canPlayOnPhone: true,
        durationMs: dt ?? duration ?? 0,
        id: String(id),
        source: .streaming,
        sourceLabel: "网易云",
        title: name
      )
    }
  }

  private struct ApiStatus: Decodable {
    let code: Int?
    let message: String?
    let msg: String?
  }

  private static func secureMediaUrl(_ value: String?) -> String {
    guard let value, var components = URLComponents(string: value), components.scheme == "http",
      let host = components.host?.lowercased(),
      host == "music.126.net" || host.hasSuffix(".music.126.net")
        || host == "music.163.com" || host.hasSuffix(".music.163.com")
    else { return value ?? "" }
    components.scheme = "https"
    return components.string ?? value
  }

  private func request<T: Decodable>(path: String, values: [String: String] = [:]) async throws -> T {
    guard var components = URLComponents(url: baseUrl.appendingPathComponent(String(path.dropFirst())), resolvingAgainstBaseURL: false) else {
      throw EchoNativeNetworkError.invalidConnection
    }
    var requestValues = values
    requestValues["timestamp"] = String(Int(Date().timeIntervalSince1970 * 1000))
    if !direct { components.queryItems = requestValues.map { URLQueryItem(name: $0.key, value: $0.value) } }
    guard let url = components.url else { throw EchoNativeNetworkError.invalidConnection }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = direct ? "POST" : "GET"
    request.setValue("application/json,text/plain,*/*", forHTTPHeaderField: "Accept")
    request.setValue(cookie, forHTTPHeaderField: "Cookie")
    request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    if direct {
      var formValues = requestValues
      if let csrf = cookie.split(separator: ";").lazy.compactMap({ part -> String? in
        let pieces = part.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        return pieces.count == 2 && pieces[0] == "__csrf" ? pieces[1] : nil
      }).first, !csrf.isEmpty {
        formValues["csrf_token"] = csrf
      }
      var body = URLComponents()
      body.queryItems = formValues.map { URLQueryItem(name: $0.key, value: $0.value) }
      request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
    }
    let data = try await responseData(for: request)
    let decoder = JSONDecoder()
    if let status = try? decoder.decode(ApiStatus.self, from: data), let code = status.code,
      code != 200, ![800, 801, 802, 803].contains(code) {
      throw EchoNativeNetworkError.server(code, status.message ?? status.msg ?? "网易云接口请求失败。")
    }
    do { return try decoder.decode(T.self, from: data) }
    catch { throw EchoNativeNetworkError.invalidResponse }
  }

  private enum RetryableResponse: Error { case status }

  private func responseData(for request: URLRequest) async throws -> Data {
    for attempt in 0..<2 {
      do {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EchoNativeNetworkError.invalidResponse }
        if http.statusCode == 429 || (500...599).contains(http.statusCode) { throw RetryableResponse.status }
        guard (200..<300).contains(http.statusCode), data.count <= 12 * 1_024 * 1_024 else {
          throw EchoNativeNetworkError.invalidResponse
        }
        return data
      } catch is RetryableResponse {
        guard attempt == 0 else { throw EchoNativeNetworkError.invalidResponse }
      } catch let error as URLError {
        let transient: Set<URLError.Code> = [
          .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost, .notConnectedToInternet,
          .resourceUnavailable, .timedOut,
        ]
        guard attempt == 0, transient.contains(error.code) else { throw error }
      }
      try await Task.sleep(nanoseconds: 400_000_000)
    }
    throw EchoNativeNetworkError.invalidResponse
  }
}
