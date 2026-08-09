import CryptoKit
import Foundation

enum EchoNativeMetadataService {
  struct Candidate: Identifiable, Sendable {
    let artist: String?
    let artworkUrl: String?
    let id: String
    let lyrics: String
    let source: String
    let sourceLabel: String
    let title: String
  }

  struct Result: Sendable {
    let artist: String?
    let artworkUrl: String?
    let lyrics: String
  }

  struct Sources: Sendable {
    let lrcApi: Bool
    let lrclib: Bool
    let netease: Bool
  }

  struct LyricLine: Sendable {
    let milliseconds: Double
    let text: String
  }

  static func candidates(
    for track: EchoNativeCoreTrack,
    sources: Sources,
    includeNeteaseLyrics: Bool = true,
    neteaseClient: EchoNativeNeteaseClient? = nil
  ) async throws -> [Candidate] {
    let values = await withTaskGroup(of: [Candidate].self) { group in
      if sources.lrcApi { group.addTask { (try? await lrcApiCandidates(for: track)) ?? [] } }
      if sources.lrclib { group.addTask { (try? await lrclibCandidates(for: track)) ?? [] } }
      if sources.netease {
        group.addTask {
          (try? await neteaseCandidates(for: track, includeLyrics: includeNeteaseLyrics, client: neteaseClient)) ?? []
        }
      }
      var result: [Candidate] = []
      for await candidates in group { result.append(contentsOf: candidates) }
      return result
    }
    guard !values.isEmpty else { throw EchoNativeNetworkError.invalidResponse }
    let order = ["lrcapi": 0, "lrclib": 1, "netease": 2]
    return Array(values.sorted { order[$0.source, default: 9] < order[$1.source, default: 9] }.prefix(6))
  }

  static func metadata(for track: EchoNativeCoreTrack) async throws -> Result {
    automaticResult(from: try await candidates(
      for: track,
      sources: Sources(lrcApi: true, lrclib: true, netease: true)
    ))
  }

  static func automaticResult(from candidates: [Candidate]) -> Result {
    func first(_ sources: [String], matching: (Candidate) -> Bool) -> Candidate? {
      for source in sources {
        if let candidate = candidates.first(where: { $0.source == source && matching($0) }) { return candidate }
      }
      return candidates.first(where: matching)
    }
    return Result(
      artist: first(["lrcapi", "netease", "lrclib"], matching: { $0.artist?.isEmpty == false })?.artist,
      artworkUrl: first(["netease", "lrcapi"], matching: { $0.artworkUrl?.isEmpty == false })?.artworkUrl,
      lyrics: first(["lrclib", "lrcapi", "netease"], matching: { !$0.lyrics.isEmpty })?.lyrics ?? ""
    )
  }

  static func lyrics(for track: EchoNativeCoreTrack) async throws -> String {
    guard let lyrics = try await lrclibCandidates(for: track).first?.lyrics, !lyrics.isEmpty else {
      throw EchoNativeNetworkError.invalidResponse
    }
    return lyrics
  }

  static func artworkData(from rawUrl: String) async throws -> Data {
    guard let url = secureMediaUrl(rawUrl) else { throw EchoNativeNetworkError.invalidResponse }
    if url.isFileURL {
      return try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
    }
    var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
    request.setValue("image/*", forHTTPHeaderField: "Accept")
    return try await responseData(for: request, maximumBytes: 12 * 1_024 * 1_024)
  }

  static func cacheLyrics(_ lyrics: String, for track: EchoNativeCoreTrack) -> URL? {
    guard !lyrics.isEmpty, let data = lyrics.data(using: .utf8) else { return nil }
    let key = "\(track.source.rawValue):\(track.id)"
    let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("external-lyrics", isDirectory: true)
    let url = directory.appendingPathComponent(digest).appendingPathExtension("lrc")
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      return url
    } catch {
      return nil
    }
  }

  static func text(from url: URL) async -> String {
    if url.isFileURL {
      return await Task.detached(priority: .utility) {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
      }.value
    }
    var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
    request.setValue("text/plain,*/*", forHTTPHeaderField: "Accept")
    guard let data = try? await responseData(for: request, maximumBytes: 2 * 1_024 * 1_024) else { return "" }
    return String(data: data, encoding: .utf8) ?? ""
  }

  static func parseLyrics(_ value: String) -> [LyricLine] {
    let expression = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
    var result: [LyricLine] = []
    var plainResult: [LyricLine] = []
    for rawLine in value.components(separatedBy: .newlines) {
      let range = NSRange(rawLine.startIndex..<rawLine.endIndex, in: rawLine)
      let matches = expression?.matches(in: rawLine, range: range) ?? []
      let text = expression?.stringByReplacingMatches(in: rawLine, range: range, withTemplate: "")
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawLine
      guard !text.isEmpty else { continue }
      if matches.isEmpty {
        plainResult.append(LyricLine(milliseconds: -1, text: text))
        continue
      }
      for match in matches {
        guard
          let minuteRange = Range(match.range(at: 1), in: rawLine),
          let secondRange = Range(match.range(at: 2), in: rawLine),
          let minutes = Double(rawLine[minuteRange]),
          let seconds = Double(rawLine[secondRange])
        else { continue }
        var fraction = 0.0
        if let fractionRange = Range(match.range(at: 3), in: rawLine) {
          let rawFraction = String(rawLine[fractionRange])
          fraction = (Double(rawFraction) ?? 0) / pow(10, Double(rawFraction.count))
        }
        result.append(LyricLine(milliseconds: (minutes * 60 + seconds + fraction) * 1000, text: text))
      }
    }
    if !result.isEmpty {
      let grouped = Dictionary(grouping: result) { Int($0.milliseconds.rounded()) }
      return grouped.keys.sorted().compactMap { milliseconds in
        guard let lines = grouped[milliseconds] else { return nil }
        var seen = Set<String>()
        let text = lines.compactMap { seen.insert($0.text).inserted ? $0.text : nil }
          .joined(separator: "\n")
        return LyricLine(milliseconds: Double(milliseconds), text: text)
      }
    }
    return plainResult
  }

  private static func lrclibCandidates(for track: EchoNativeCoreTrack) async throws -> [Candidate] {
    struct Item: Decodable {
      let artistName: String?
      let id: Int?
      let name: String?
      let plainLyrics: String?
      let syncedLyrics: String?
      let trackName: String?
    }
    var components = URLComponents(string: "https://lrclib.net/api/search")!
    components.queryItems = [
      URLQueryItem(name: "track_name", value: track.title),
      URLQueryItem(name: "artist_name", value: track.artist),
      URLQueryItem(name: "album_name", value: track.album),
    ]
    let values: [Item] = try await get(components.url!)
    return values
      .filter { $0.syncedLyrics?.isEmpty == false || $0.plainLyrics?.isEmpty == false }
      .filter { score($0.trackName ?? $0.name ?? "", artist: $0.artistName ?? "", track: track) > 0 }
      .sorted {
        let left = score($0.trackName ?? $0.name ?? "", artist: $0.artistName ?? "", track: track)
        let right = score($1.trackName ?? $1.name ?? "", artist: $1.artistName ?? "", track: track)
        return left > right
      }
      .prefix(2)
      .enumerated()
      .map { index, item in
        Candidate(
          artist: item.artistName,
          artworkUrl: nil,
          id: "lrclib:\(item.id ?? index)",
          lyrics: item.syncedLyrics ?? item.plainLyrics ?? "",
          source: "lrclib",
          sourceLabel: "LRCLIB",
          title: item.trackName ?? item.name ?? track.title
        )
      }
  }

  private static func lrcApiCandidates(for track: EchoNativeCoreTrack) async throws -> [Candidate] {
    struct Item: Decodable {
      let artist: String?
      let cover: String?
      let cover_format: String?
      let lrc: String?
      let lyrics: String?
      let title: String?
    }
    var components = URLComponents(string: "https://api.lrc.cx/jsonapi")!
    components.queryItems = [
      URLQueryItem(name: "title", value: track.title),
      URLQueryItem(name: "artist", value: track.artist),
      URLQueryItem(name: "album", value: track.album),
    ]
    let values: [Item] = try await get(components.url!)
    return values
      .filter { $0.cover?.isEmpty == false || $0.cover_format?.isEmpty == false || $0.lrc?.isEmpty == false || $0.lyrics?.isEmpty == false }
      .filter { score($0.title ?? "", artist: $0.artist ?? "", track: track) > 0 }
      .sorted { score($0.title ?? "", artist: $0.artist ?? "", track: track) > score($1.title ?? "", artist: $1.artist ?? "", track: track) }
      .prefix(2)
      .enumerated()
      .map { index, item in
        Candidate(
          artist: item.artist,
          artworkUrl: item.cover ?? item.cover_format?.replacingOccurrences(of: "{w}", with: "1200")
            .replacingOccurrences(of: "{h}", with: "1200"),
          id: "lrcapi:\(index):\(normalized(item.title ?? track.title))",
          lyrics: item.lrc?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? item.lyrics?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "",
          source: "lrcapi",
          sourceLabel: "LrcAPI",
          title: item.title ?? track.title
        )
      }
  }

  private static func neteaseCandidates(
    for track: EchoNativeCoreTrack,
    includeLyrics: Bool,
    client: EchoNativeNeteaseClient?
  ) async throws -> [Candidate] {
    if let client {
      let songs = try await client.search("\(track.title) \(track.artist)", limit: 8)
        .filter { score($0.title, artist: $0.artist, track: track) > 0 }
        .sorted { score($0.title, artist: $0.artist, track: track) > score($1.title, artist: $1.artist, track: track) }
        .prefix(2)
      return await withTaskGroup(of: Candidate?.self) { group in
        for song in songs {
          group.addTask {
            let lyrics = includeLyrics ? ((try? await client.lyrics(trackId: song.id)) ?? "") : ""
            guard song.artworkUrl?.isEmpty == false || !song.artist.isEmpty || !lyrics.isEmpty else { return nil }
            return Candidate(
              artist: song.artist,
              artworkUrl: song.artworkUrl,
              id: "netease:\(song.id)",
              lyrics: lyrics,
              source: "netease",
              sourceLabel: "NetEase Cloud Music",
              title: song.title
            )
          }
        }
        var result: [Candidate] = []
        for await candidate in group { if let candidate { result.append(candidate) } }
        return result
      }
    }
    struct Search: Decodable {
      struct SearchResult: Decodable { let songs: [Song]? }
      struct Song: Decodable {
        struct Artist: Decodable { let name: String? }
        let artists: [Artist]?
        let id: Int64?
        let name: String?
      }
      let result: SearchResult?
    }
    struct Detail: Decodable {
      struct Song: Decodable { struct Album: Decodable { let picUrl: String? }; let album: Album? }
      let songs: [Song]?
    }
    struct Lyric: Decodable {
      struct Value: Decodable { let lyric: String? }
      let lrc: Value?
      let tlyric: Value?
    }

    var searchComponents = URLComponents(string: "https://music.163.com/api/search/get/web")!
    searchComponents.queryItems = [
      URLQueryItem(name: "s", value: "\(track.title) \(track.artist)"),
      URLQueryItem(name: "type", value: "1"),
      URLQueryItem(name: "limit", value: "8"),
      URLQueryItem(name: "offset", value: "0"),
    ]
    let search: Search = try await get(searchComponents.url!, netease: true)
    let songs = (search.result?.songs ?? [])
      .filter { $0.id != nil }
      .filter { score($0.name ?? "", artist: $0.artists?.compactMap(\.name).joined(separator: " ") ?? "", track: track) > 0 }
      .sorted {
        let left = score($0.name ?? "", artist: $0.artists?.compactMap(\.name).joined(separator: " ") ?? "", track: track)
        let right = score($1.name ?? "", artist: $1.artists?.compactMap(\.name).joined(separator: " ") ?? "", track: track)
        return left > right
      }
      .prefix(2)
    var result: [Candidate] = []
    for song in songs {
      guard let id = song.id else { continue }
      let detailUrl = URL(string: "https://music.163.com/api/song/detail/?id=\(id)&ids=%5B\(id)%5D")!
      let lyricUrl = URL(string: "https://music.163.com/api/song/lyric?id=\(id)&lv=1&kv=1&tv=-1")!
      let detail: Detail? = try? await get(detailUrl, netease: true)
      let lyric: Lyric?
      if includeLyrics {
        lyric = try? await get(lyricUrl, netease: true)
      } else {
        lyric = nil
      }
      let artist = song.artists?.compactMap(\.name).joined(separator: ", ")
      let artwork = detail?.songs?.first?.album?.picUrl.flatMap { secureMediaUrl($0)?.absoluteString }
      let lyrics = [lyric?.lrc?.lyric, lyric?.tlyric?.lyric]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
      if artwork?.isEmpty == false || artist?.isEmpty == false || !lyrics.isEmpty {
        result.append(Candidate(
          artist: artist,
          artworkUrl: artwork,
          id: "netease:\(id)",
          lyrics: lyrics,
          source: "netease",
          sourceLabel: "NetEase Cloud Music",
          title: song.name ?? track.title
        ))
      }
    }
    return result
  }

  private static func get<T: Decodable>(_ url: URL, netease: Bool = false) async throws -> T {
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue("ECHO-iPhone/0.5", forHTTPHeaderField: "User-Agent")
    if netease { request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer") }
    let data = try await responseData(for: request, maximumBytes: 6 * 1_024 * 1_024)
    return try JSONDecoder().decode(T.self, from: data)
  }

  private enum RetryableResponse: Error { case status }

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 30
    configuration.waitsForConnectivity = true
    configuration.urlCache = URLCache(
      memoryCapacity: 8 * 1_024 * 1_024,
      diskCapacity: 64 * 1_024 * 1_024,
      diskPath: "echo-native-metadata"
    )
    return URLSession(configuration: configuration)
  }()

  private static func responseData(for request: URLRequest, maximumBytes: Int) async throws -> Data {
    for attempt in 0..<2 {
      do {
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw EchoNativeNetworkError.invalidResponse }
        if http.statusCode == 429 || (500...599).contains(http.statusCode) { throw RetryableResponse.status }
        guard (200..<300).contains(http.statusCode), data.count <= maximumBytes else {
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

  private static func secureMediaUrl(_ rawValue: String) -> URL? {
    guard var components = URLComponents(string: rawValue) else { return nil }
    if components.scheme == "http", let host = components.host?.lowercased(),
      host == "music.126.net" || host.hasSuffix(".music.126.net")
        || host == "music.163.com" || host.hasSuffix(".music.163.com") {
      components.scheme = "https"
    }
    return components.url
  }

  private static func score(_ title: String, artist: String, track: EchoNativeCoreTrack) -> Int {
    let leftTitle = normalized(title)
    let rightTitle = normalized(track.title)
    let leftArtist = normalized(artist)
    let rightArtist = normalized(track.artist)
    return (leftTitle == rightTitle ? 20 : leftTitle.contains(rightTitle) || rightTitle.contains(leftTitle) ? 8 : 0)
      + (!rightArtist.isEmpty && (leftArtist == rightArtist || leftArtist.contains(rightArtist) || rightArtist.contains(leftArtist)) ? 10 : 0)
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
