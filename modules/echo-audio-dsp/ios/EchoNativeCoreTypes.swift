import Foundation

enum EchoNativeOutputMode: String, Codable {
  case local
  case pc
  case phone
  case remoteControl
  case remoteStream
  case streaming
}

enum EchoNativeTrackSource: String, Codable {
  case echo
  case local
  case remote
  case streaming
}

struct EchoNativeCoreTrack: Codable, Hashable, Identifiable, Sendable {
  var album: String
  var albumArtist: String
  var artist: String
  var artworkUrl: String?
  var bitDepth: Int?
  var bitrate: Int?
  var canPlayOnPhone: Bool
  var codec: String?
  var discNo: Int?
  var durationMs: Double
  var fileName: String?
  var fileSize: Int64
  var hasLyrics: Bool
  var id: String
  var lyricsUrl: String?
  var localUrl: String?
  var sampleRate: Double?
  var source: EchoNativeTrackSource
  var sourceLabel: String
  var title: String
  var trackNo: Int?

  init(
    album: String = "",
    albumArtist: String = "",
    artist: String = "",
    artworkUrl: String? = nil,
    bitDepth: Int? = nil,
    bitrate: Int? = nil,
    canPlayOnPhone: Bool = false,
    codec: String? = nil,
    discNo: Int? = nil,
    durationMs: Double = 0,
    fileName: String? = nil,
    fileSize: Int64 = 0,
    hasLyrics: Bool = false,
    id: String,
    lyricsUrl: String? = nil,
    localUrl: String? = nil,
    sampleRate: Double? = nil,
    source: EchoNativeTrackSource,
    sourceLabel: String = "",
    title: String,
    trackNo: Int? = nil
  ) {
    self.album = album
    self.albumArtist = albumArtist
    self.artist = artist
    self.artworkUrl = artworkUrl
    self.bitDepth = bitDepth
    self.bitrate = bitrate
    self.canPlayOnPhone = canPlayOnPhone
    self.codec = codec
    self.discNo = discNo
    self.durationMs = durationMs
    self.fileName = fileName
    self.fileSize = fileSize
    self.hasLyrics = hasLyrics
    self.id = id
    self.lyricsUrl = lyricsUrl
    self.localUrl = localUrl
    self.sampleRate = sampleRate
    self.source = source
    self.sourceLabel = sourceLabel
    self.title = title
    self.trackNo = trackNo
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    enum LegacyCodingKeys: String, CodingKey {
      case lyricsUri
      case uri
    }
    let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
    album = try values.decodeIfPresent(String.self, forKey: .album) ?? ""
    albumArtist = try values.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
    artist = try values.decodeIfPresent(String.self, forKey: .artist) ?? ""
    artworkUrl = try values.decodeIfPresent(String.self, forKey: .artworkUrl)
    bitDepth = try values.decodeIfPresent(Int.self, forKey: .bitDepth)
    bitrate = try values.decodeIfPresent(Int.self, forKey: .bitrate)
    canPlayOnPhone = try values.decodeIfPresent(Bool.self, forKey: .canPlayOnPhone) ?? false
    codec = try values.decodeIfPresent(String.self, forKey: .codec)
    discNo = try values.decodeIfPresent(Int.self, forKey: .discNo)
    durationMs = try values.decodeIfPresent(Double.self, forKey: .durationMs) ?? 0
    fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
    fileSize = try values.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
    hasLyrics = try values.decodeIfPresent(Bool.self, forKey: .hasLyrics) ?? false
    id = try values.decode(String.self, forKey: .id)
    lyricsUrl = try values.decodeIfPresent(String.self, forKey: .lyricsUrl)
      ?? legacy.decodeIfPresent(String.self, forKey: .lyricsUri)
    localUrl = try values.decodeIfPresent(String.self, forKey: .localUrl)
      ?? legacy.decodeIfPresent(String.self, forKey: .uri)
    sampleRate = try values.decodeIfPresent(Double.self, forKey: .sampleRate)
    source = try values.decodeIfPresent(EchoNativeTrackSource.self, forKey: .source) ?? .echo
    sourceLabel = try values.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? id
    trackNo = try values.decodeIfPresent(Int.self, forKey: .trackNo)
  }
}

struct EchoNativeCoreAlbum: Codable, Hashable, Identifiable, Sendable {
  var albumArtist: String
  var artworkUrl: String?
  var durationMs: Double
  var id: String
  var source: EchoNativeTrackSource
  var sourceLabel: String
  var title: String
  var trackCount: Int
  var year: Int?

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    albumArtist = try values.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
    artworkUrl = try values.decodeIfPresent(String.self, forKey: .artworkUrl)
    durationMs = try values.decodeIfPresent(Double.self, forKey: .durationMs) ?? 0
    id = try values.decode(String.self, forKey: .id)
    source = try values.decodeIfPresent(EchoNativeTrackSource.self, forKey: .source) ?? .echo
    sourceLabel = try values.decodeIfPresent(String.self, forKey: .sourceLabel) ?? ""
    title = try values.decodeIfPresent(String.self, forKey: .title) ?? id
    trackCount = try values.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    year = try values.decodeIfPresent(Int.self, forKey: .year)
  }
}

struct EchoNativeConnection: Codable, Equatable, Sendable {
  var enabled: Bool
  var host: String
  var name: String
  var port: Int
  var scheme: String
  var token: String

  static let echoDefault = EchoNativeConnection(
    enabled: false,
    host: "",
    name: "PC ECHO",
    port: 26789,
    scheme: "http",
    token: ""
  )

  static let powerampDefault = EchoNativeConnection(
    enabled: false,
    host: "",
    name: "Poweramp",
    port: 27806,
    scheme: "http",
    token: ""
  )
}

struct EchoNativeSavedPlaylist: Codable, Identifiable, Sendable {
  var createdAt: Double
  var favorite: Bool
  var id: String
  var name: String
  var pinned: Bool
  var tracks: [EchoNativeCoreTrack]
}

enum EchoNativePlaybackMode: String, Codable, Sendable {
  case normal
  case repeatAll
  case repeatOne
  case shuffle

  var next: EchoNativePlaybackMode {
    switch self {
    case .normal: return .repeatAll
    case .repeatAll: return .repeatOne
    case .repeatOne: return .shuffle
    case .shuffle: return .normal
    }
  }
}

struct EchoNativeCoreSettings: Codable, Sendable {
  var artworkBackgroundEnabled = true
  var autoOpenLyricsForLocalTracks = true
  var autoQueueImportedLocalTracks = false
  var audioTagVisibility: [String: Bool] = [
    "bitDepth": true,
    "bitrate": true,
    "codec": true,
    "duration": true,
    "output": true,
    "sampleRate": true,
    "source": true,
    "streamable": true,
  ]
  var darkModeEnabled = false
  var desktopLyricsAnimation = "flow"
  var desktopLyricsBackground = "theme"
  var desktopLyricsEnabled = false
  var desktopLyricsFontSize = 26.0
  var desktopLyricsHeightScale = 0.36
  var desktopLyricsOnlyWhilePlaying = true
  var desktopLyricsPosition = "bottom"
  var desktopLyricsShowMetadata = true
  var desktopLyricsSize = "medium"
  var desktopLyricsStyle = "glass"
  var desktopLyricsTimedReveal = false
  var desktopLyricsTransitionAnimation = false
  var desktopLyricsWidthScale = 1.0
  var defaultLibrarySource = "local"
  var defaultLocalLibraryView = "songs"
  var defaultPage = "control"
  var eqGains = Array(repeating: 0.0, count: 10)
  var eqPreset = "flat"
  var externalDataSelectionMode = "ask"
  var externalMetadataEnabled = false
  var externalMetadataSkipExisting = true
  var followSystemAppearance = true
  var language = "zh"
  var lrcApiExternalDataEnabled = false
  var lrclibExternalDataEnabled = true
  var loudnessEnabled = false
  var neteaseAccessMode = "direct"
  var neteaseApiBaseUrl = "https://music.163.com"
  var neteaseExternalDataEnabled = true
  var playbackMode = EchoNativePlaybackMode.normal
  var confirmBeforeDeletingLocalTracks = true
  var showArtworkGlow = true
  var showPlayerOutputInMenu = true
  var showPowerampRemote = false

  private enum LegacyCodingKeys: String, CodingKey {
    case repeatOne
  }

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
    artworkBackgroundEnabled = try values.decodeIfPresent(Bool.self, forKey: .artworkBackgroundEnabled) ?? true
    autoOpenLyricsForLocalTracks = try values.decodeIfPresent(Bool.self, forKey: .autoOpenLyricsForLocalTracks) ?? true
    autoQueueImportedLocalTracks = try values.decodeIfPresent(Bool.self, forKey: .autoQueueImportedLocalTracks) ?? false
    audioTagVisibility = try values.decodeIfPresent([String: Bool].self, forKey: .audioTagVisibility) ?? [
      "bitDepth": true,
      "bitrate": true,
      "codec": true,
      "duration": true,
      "output": true,
      "sampleRate": true,
      "source": true,
      "streamable": true,
    ]
    darkModeEnabled = try values.decodeIfPresent(Bool.self, forKey: .darkModeEnabled) ?? false
    desktopLyricsAnimation = try values.decodeIfPresent(String.self, forKey: .desktopLyricsAnimation) ?? "flow"
    desktopLyricsBackground = try values.decodeIfPresent(String.self, forKey: .desktopLyricsBackground) ?? "theme"
    desktopLyricsEnabled = try values.decodeIfPresent(Bool.self, forKey: .desktopLyricsEnabled) ?? false
    let decodedHeightScale = try values.decodeIfPresent(Double.self, forKey: .desktopLyricsHeightScale)
    desktopLyricsHeightScale = max(0.33, min(1.0, decodedHeightScale ?? 0.36))
    desktopLyricsOnlyWhilePlaying = try values.decodeIfPresent(Bool.self, forKey: .desktopLyricsOnlyWhilePlaying) ?? true
    desktopLyricsPosition = try values.decodeIfPresent(String.self, forKey: .desktopLyricsPosition) ?? "bottom"
    desktopLyricsShowMetadata = try values.decodeIfPresent(Bool.self, forKey: .desktopLyricsShowMetadata) ?? true
    desktopLyricsSize = try values.decodeIfPresent(String.self, forKey: .desktopLyricsSize) ?? "medium"
    let legacySize = desktopLyricsSize
    let decodedFontSize = try values.decodeIfPresent(Double.self, forKey: .desktopLyricsFontSize)
      ?? (legacySize == "small" ? 20 : legacySize == "large" ? 32 : 26)
    desktopLyricsFontSize = max(18, min(34, decodedFontSize))
    desktopLyricsStyle = try values.decodeIfPresent(String.self, forKey: .desktopLyricsStyle) ?? "glass"
    desktopLyricsTimedReveal = try values.decodeIfPresent(Bool.self, forKey: .desktopLyricsTimedReveal) ?? false
    desktopLyricsTransitionAnimation = try values.decodeIfPresent(Bool.self, forKey: .desktopLyricsTransitionAnimation) ?? false
    let decodedWidthScale = try values.decodeIfPresent(Double.self, forKey: .desktopLyricsWidthScale)
    desktopLyricsWidthScale = max(0.2, min(1.0, decodedHeightScale == nil ? 1.0 : decodedWidthScale ?? 1.0))
    defaultLibrarySource = try values.decodeIfPresent(String.self, forKey: .defaultLibrarySource) ?? "local"
    defaultLocalLibraryView = try values.decodeIfPresent(String.self, forKey: .defaultLocalLibraryView) ?? "songs"
    defaultPage = try values.decodeIfPresent(String.self, forKey: .defaultPage) ?? "control"
    eqGains = try values.decodeIfPresent([Double].self, forKey: .eqGains) ?? Array(repeating: 0, count: 10)
    eqPreset = try values.decodeIfPresent(String.self, forKey: .eqPreset) ?? "flat"
    externalDataSelectionMode = try values.decodeIfPresent(String.self, forKey: .externalDataSelectionMode) ?? "ask"
    externalMetadataEnabled = try values.decodeIfPresent(Bool.self, forKey: .externalMetadataEnabled) ?? false
    externalMetadataSkipExisting = try values.decodeIfPresent(Bool.self, forKey: .externalMetadataSkipExisting) ?? true
    followSystemAppearance = try values.decodeIfPresent(Bool.self, forKey: .followSystemAppearance) ?? true
    language = try values.decodeIfPresent(String.self, forKey: .language) ?? "zh"
    lrcApiExternalDataEnabled = try values.decodeIfPresent(Bool.self, forKey: .lrcApiExternalDataEnabled) ?? false
    lrclibExternalDataEnabled = try values.decodeIfPresent(Bool.self, forKey: .lrclibExternalDataEnabled) ?? true
    loudnessEnabled = try values.decodeIfPresent(Bool.self, forKey: .loudnessEnabled) ?? false
    neteaseAccessMode = try values.decodeIfPresent(String.self, forKey: .neteaseAccessMode) ?? "direct"
    neteaseApiBaseUrl = try values.decodeIfPresent(String.self, forKey: .neteaseApiBaseUrl) ?? "https://music.163.com"
    neteaseExternalDataEnabled = try values.decodeIfPresent(Bool.self, forKey: .neteaseExternalDataEnabled) ?? true
    let rawPlaybackMode = try values.decodeIfPresent(String.self, forKey: .playbackMode)
    let legacyRepeatOne = try legacyValues.decodeIfPresent(Bool.self, forKey: .repeatOne) ?? false
    playbackMode = rawPlaybackMode.flatMap(EchoNativePlaybackMode.init(rawValue:))
      ?? (legacyRepeatOne ? .repeatOne : .normal)
    confirmBeforeDeletingLocalTracks = try values.decodeIfPresent(Bool.self, forKey: .confirmBeforeDeletingLocalTracks) ?? true
    showArtworkGlow = try values.decodeIfPresent(Bool.self, forKey: .showArtworkGlow) ?? true
    showPlayerOutputInMenu = try values.decodeIfPresent(Bool.self, forKey: .showPlayerOutputInMenu) ?? true
    showPowerampRemote = try values.decodeIfPresent(Bool.self, forKey: .showPowerampRemote) ?? false
  }
}

struct EchoNativePersistentState: Codable, Sendable {
  var echoConnection = EchoNativeConnection.echoDefault
  var favoriteTrackKeys: Set<String> = []
  var playlists: [EchoNativeSavedPlaylist] = []
  var powerampConnection = EchoNativeConnection.powerampDefault
  var queueTrackKeys: [String] = []
  var recentTrackKeys: [String] = []
  var recentTracks: [EchoNativeCoreTrack] = []
  var settings = EchoNativeCoreSettings()
  var streamingFavoritePlaylistIds: Set<String> = []
  var streamingPinnedPlaylistIds: Set<String> = []
  var streamingQueueTracks: [EchoNativeCoreTrack] = []

  init() {}

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    echoConnection = try values.decodeIfPresent(EchoNativeConnection.self, forKey: .echoConnection) ?? .echoDefault
    favoriteTrackKeys = try values.decodeIfPresent(Set<String>.self, forKey: .favoriteTrackKeys) ?? []
    playlists = try values.decodeIfPresent([EchoNativeSavedPlaylist].self, forKey: .playlists) ?? []
    powerampConnection = try values.decodeIfPresent(EchoNativeConnection.self, forKey: .powerampConnection) ?? .powerampDefault
    queueTrackKeys = try values.decodeIfPresent([String].self, forKey: .queueTrackKeys) ?? []
    recentTrackKeys = try values.decodeIfPresent([String].self, forKey: .recentTrackKeys) ?? []
    recentTracks = try values.decodeIfPresent([EchoNativeCoreTrack].self, forKey: .recentTracks) ?? []
    settings = try values.decodeIfPresent(EchoNativeCoreSettings.self, forKey: .settings) ?? EchoNativeCoreSettings()
    streamingFavoritePlaylistIds = try values.decodeIfPresent(Set<String>.self, forKey: .streamingFavoritePlaylistIds) ?? []
    streamingPinnedPlaylistIds = try values.decodeIfPresent(Set<String>.self, forKey: .streamingPinnedPlaylistIds) ?? []
    streamingQueueTracks = try values.decodeIfPresent([EchoNativeCoreTrack].self, forKey: .streamingQueueTracks) ?? []
  }
}

struct EchoNativePlaybackStatus: Decodable, Sendable {
  struct AudioTelemetry: Decodable, Sendable {
    let bitDepth: Int?
    let channels: Int?
    let clipping: Bool?
    let exclusive: Bool?
    let lufsMomentary: Double?
    let outputDeviceId: String?
    let outputDeviceName: String?
    let outputDeviceType: String?
    let outputLatencyMs: Double?
    let peakDb: Double?
    let rmsDb: Double?
    let sampleRate: Double?
  }

  struct Device: Decodable, Sendable {
    let id: String
    let name: String
  }

  struct Playback: Decodable, Sendable {
    struct Queue: Decodable, Sendable {
      let currentTrackId: String?
      let items: [EchoNativeCoreTrack]
    }

    let durationMs: Double
    let outputMode: String
    let positionMs: Double
    let queue: Queue?
    let state: String
    let track: EchoNativeCoreTrack?
    let updatedAtEpochMs: Double
    let volume: Double
  }

  let audio: AudioTelemetry?
  let device: Device
  let playback: Playback
}

struct EchoNativeStreamResponse: Decodable, Sendable {
  let expiresAtEpochMs: Double
  let streamUrl: String
  let track: EchoNativeCoreTrack
}

func echoDeduplicatedTracks(_ tracks: [EchoNativeCoreTrack]) -> [EchoNativeCoreTrack] {
  func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  func score(_ track: EchoNativeCoreTrack) -> Int {
    (track.canPlayOnPhone ? 4 : 0) + (track.localUrl == nil ? 0 : 4) + (track.artworkUrl?.isEmpty == false ? 2 : 0) + (track.durationMs > 0 ? 1 : 0)
  }

  var indexes: [String: Int] = [:]
  var result: [EchoNativeCoreTrack] = []
  for track in tracks {
    let title = normalized(track.title)
    let key = title.isEmpty
      ? "\(track.source.rawValue):id:\(track.id)"
      : [
        track.source.rawValue,
        title,
        normalized(track.artist),
        normalized(track.album),
        String(Int((track.durationMs / 1000).rounded())),
        String(track.discNo ?? 0),
        String(track.trackNo ?? 0),
      ].joined(separator: "::")
    if let index = indexes[key] {
      if score(track) > score(result[index]) { result[index] = track }
    } else {
      indexes[key] = result.count
      result.append(track)
    }
  }
  return result
}
