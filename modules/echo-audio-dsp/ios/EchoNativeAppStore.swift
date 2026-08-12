import CoreText
import Foundation
import UIKit

struct EchoNativeLibraryCollectionsCacheKey: Equatable {
  let revision: Int
  let source: String
  let view: String
  let filter: String
  let query: String
  let sort: String
  let language: String
}

@MainActor
final class EchoNativeAppStore {
  let pagesModel = EchoNativePagesModel()
  let playerModel = EchoNativePlayerModel()

  var persistent = EchoNativePersistence.load()
  var echoTracks: [EchoNativeCoreTrack] = [] { didSet { libraryCollectionsRevision &+= 1 } }
  var echoAlbums: [EchoNativeCoreAlbum] = [] { didSet { libraryCollectionsRevision &+= 1 } }
  var localTracks: [EchoNativeCoreTrack] = [] { didSet { libraryCollectionsRevision &+= 1 } }
  var powerampTracks: [EchoNativeCoreTrack] = [] { didSet { libraryCollectionsRevision &+= 1 } }
  var powerampAlbums: [EchoNativeCoreAlbum] = [] { didSet { libraryCollectionsRevision &+= 1 } }
  var neteaseTracks: [EchoNativeCoreTrack] = []
  var neteaseSearchTracks: [EchoNativeCoreTrack] = []
  var neteasePlaylists: [EchoNativeNeteaseClient.Playlist] = []
  var neteaseProfile: EchoNativeNeteaseClient.Profile?
  var queue: [EchoNativeCoreTrack] = []
  var currentTrack: EchoNativeCoreTrack?
  var outputMode: EchoNativeOutputMode = .local
  var librarySource = "local"
  var libraryView = "songs"
  var libraryFilter = "all"
  var libraryQuery = ""
  var libraryPage = 0
  var libraryExpanded = false
  var librarySort = "default"
  var albumTrackSort = "default"
  var selectedCollectionId = ""
  var selectedPlaylistId = ""
  var activeQueuePlaylistId = ""
  var selectedStreamingPlaylistId = ""
  var connectMode = "echo"
  var echoBusy = false
  var echoAlbumBusy = false
  var powerampBusy = false
  var localBusy = false
  var streamingBusy = false
  var echoOnline = false
  var powerampOnline = false
  var echoError = ""
  var powerampError = ""
  var streamingStatus = ""
  var streamingSearchStatus = ""
  var pairingText = ""
  var streamingLibraryMode = "search"
  var streamingFavoritePlaylistIds: Set<String> {
    get { persistent.streamingFavoritePlaylistIds }
    set { persistent.streamingFavoritePlaylistIds = newValue }
  }
  var streamingPinnedPlaylistIds: Set<String> {
    get { persistent.streamingPinnedPlaylistIds }
    set { persistent.streamingPinnedPlaylistIds = newValue }
  }
  var collectionTrackKeys: [String: [String]] = [:]
  var libraryCollectionsRevision = 0
  var libraryCollectionsCacheKey: EchoNativeLibraryCollectionsCacheKey?
  var libraryCollectionsCache: [[String: Any]] = []
  var libraryCollectionsCacheTrackKeys: [String: [String]] = [:]
  var libraryTracksCacheKey: EchoNativeLibraryCollectionsCacheKey?
  var libraryTracksCache: [EchoNativeCoreTrack] = []
  var libraryIndexPayloadScope = ""
  var libraryIndexPayloadTitles: [String] = []
  let libraryTextSortKeyCache = NSCache<NSString, NSString>()
  weak var presenter: UIViewController?

  private let audioEngine = DspPlaybackEngine()
  private let desktopLyricsController = EchoNativeDesktopLyricsController()
  private var desktopLyricsBackgroundImage: UIImage?
  private var dacProfiles = EchoNativeDacObservation.load()
  private var lastDacObservationKey = ""
  private var signalPathVisible = false
  private var signalRouteEvents = EchoNativeSignalRouteEvent.load()
  private var lastSignalRouteKey = ""
  private lazy var nowPlayingController = NowPlayingController { [weak self] command, position in
    Task { @MainActor in self?.handleRemoteCommand(command, position: position) }
  }
  private var echoClient: EchoNativeRemoteClient?
  private var powerampClient: EchoNativeRemoteClient?
  private var neteaseClient: EchoNativeNeteaseClient?
  private var neteaseClientConfiguration = ""
  private var metadataNeteaseClient: EchoNativeNeteaseClient?
  private var metadataNeteaseClientConfiguration = ""
  private var echoStatus: EchoNativePlaybackStatus?
  private var powerampStatus: EchoNativePlaybackStatus?
  private var echoStatusReceivedAt = Date()
  private var powerampStatusReceivedAt = Date()
  private var progressTask: Task<Void, Never>?
  private var echoPollTask: Task<Void, Never>?
  private var powerampPollTask: Task<Void, Never>?
  private var searchTask: Task<Void, Never>?
  private var playbackLoadTask: Task<Void, Never>?
  private var lyricsTask: Task<Void, Never>?
  private var metadataTask: Task<Void, Never>?
  private var metadataRetryTask: Task<Void, Never>?
  private var libraryArtworkTask: Task<Void, Never>?
  private var localMetadataEmbeddingTask: Task<Void, Never>?
  private var streamingQrTask: Task<Void, Never>?
  private var handledFinishedTrackKey = ""
  private var playbackGeneration = 0
  private var lyricsGeneration = 0
  private var metadataGeneration = 0
  private var libraryArtworkGeneration = 0
  private var streamingQrGeneration = 0
  private var echoAlbumGeneration = 0
  private var streamingQrKey = ""
  var streamingQrUrl = ""
  private var audioLoading = false
  private var externalMetadataLoading = false
  private var externalMetadataCandidates: [EchoNativeMetadataService.Candidate] = []
  private var externalMetadataTrackKey = ""
  private var metadataRetryAttempts: [String: Int] = [:]
  private var pendingLocalMetadataEmbeddings: [String: EchoNativeCoreTrack] = [:]
  private var libraryArtworkLookupKeys = Set<String>()
  private var ignoredExternalMetadataTrackKeys = Set<String>()
  private var lastNowPlayingPosition = -1.0
  private var lastNowPlayingState = false
  private var lastNowPlayingTrackKey = ""
  private var powerampQueueManagedLocally = false
  private var started = false

  func start() {
    guard !started else { return }
    started = true
    desktopLyricsBackgroundImage = loadDesktopLyricsBackgroundImage()
    registerStoredAppearanceFont()
    applySettings()
    configureClients()
    startProgressClock()
    startPolling()
    renderPages()
    Task {
      await refreshLocalLibrary()
      await refreshEcho(loadLibrary: true)
      await refreshPoweramp(loadLibrary: true)
      await loadNeteaseAccount()
      restoreQueue()
    }
  }

  func attachDesktopLyrics(to view: UIView) {
    desktopLyricsController.attach(to: view)
  }

  func stop() {
    playbackGeneration &+= 1
    echoAlbumGeneration &+= 1
    echoAlbumBusy = false
    progressTask?.cancel()
    echoPollTask?.cancel()
    powerampPollTask?.cancel()
    searchTask?.cancel()
    playbackLoadTask?.cancel()
    lyricsTask?.cancel()
    metadataTask?.cancel()
    metadataRetryTask?.cancel()
    libraryArtworkTask?.cancel()
    localMetadataEmbeddingTask?.cancel()
    streamingQrTask?.cancel()
    playbackLoadTask = nil
    lyricsTask = nil
    metadataTask = nil
    metadataRetryTask = nil
    libraryArtworkTask = nil
    localMetadataEmbeddingTask = nil
    pendingLocalMetadataEmbeddings.removeAll()
    streamingQrTask = nil
    audioLoading = false
    externalMetadataLoading = false
    updateLoadingState()
    audioEngine.stop()
    desktopLyricsController.stop()
    nowPlayingController.clear()
    EchoNativeWidgetBridge.clear()
  }

  func migrateLegacy(payloadJSON: String) {
    struct Payload: Decodable {
      let neteaseCookie: String
      let state: EchoNativePersistentState
      let streamingFavoritePlaylistIds: [String]
      let streamingPinnedPlaylistIds: [String]
    }
    guard !payloadJSON.isEmpty, !EchoNativePersistence.didMigrateLegacy,
      let data = payloadJSON.data(using: .utf8),
      let payload = try? JSONDecoder().decode(Payload.self, from: data)
    else { return }
    persistent = payload.state
    streamingFavoritePlaylistIds = Set(payload.streamingFavoritePlaylistIds)
    streamingPinnedPlaylistIds = Set(payload.streamingPinnedPlaylistIds)
    if !hasNeteaseAccountCookie(EchoNativePersistence.neteaseCookie()),
      hasNeteaseAccountCookie(payload.neteaseCookie) {
      EchoNativePersistence.setNeteaseCookie(payload.neteaseCookie)
    }
    EchoNativePersistence.save(persistent)
    EchoNativePersistence.markLegacyMigrated()
    guard started else { return }
    applySettings()
    configureClients()
    startPolling()
    renderPages()
    Task {
      await refreshEcho(loadLibrary: true)
      await refreshPoweramp(loadLibrary: true)
      await loadNeteaseAccount()
      restoreQueue()
    }
  }

  func handle(_ payload: [String: Any]) {
    guard let action = payload["action"] as? String else { return }
    switch action {
    case "page":
      guard let page = payload["page"] as? String else { return }
      playerModel.activePage = page
      if persistent.settings.hapticsEnabled { UISelectionFeedbackGenerator().selectionChanged() }
      scheduleStreamingSearchIfNeeded()
      renderPages()
    case "playPause": togglePlayPause()
    case "previous": playAdjacent(-1)
    case "next": playNext()
    case "seek":
      if let value = number(payload["value"]) { seek(toMilliseconds: value) }
    case "volume":
      if let value = number(payload["value"]) {
        let volume = max(0, min(1, value))
        if (outputMode == .pc || outputMode == .remoteControl), payload["commit"] as? Bool == false {
          playerModel.volume = volume
        } else {
          setVolume(volume)
        }
      }
    case "playbackMode":
      persistent.settings.playbackMode = persistent.settings.playbackMode.next
      playerModel.playbackMode = persistent.settings.playbackMode
      persist()
    case "lyrics":
      playerModel.lyricsVisible = true
      loadLyricsForCurrentTrack()
    case "lyricsClose": playerModel.lyricsVisible = false
    case "eqChange":
      guard let index = payload["index"] as? Int, let value = number(payload["value"]), playerModel.equalizer.gains.indices.contains(index) else { return }
      playerModel.equalizer.gains[index] = min(12, max(-12, value))
      playerModel.equalizer.preset = "custom"
      pagesModel.equalizer.gains[index] = playerModel.equalizer.gains[index]
      pagesModel.equalizer.preset = "custom"
      persistent.settings.eqGains = playerModel.equalizer.gains
      persistent.settings.eqPreset = "custom"
      playerModel.eqEnabled = playerModel.equalizer.gains.contains { abs($0) > 0.01 }
      audioEngine.setEq(gains: playerModel.equalizer.gains)
      if payload["commit"] as? Bool != false { persist() }
    case "eqPreset":
      if let preset = payload["preset"] as? String { applyEqPreset(preset) }
    case "outputSource", "output":
      if let mode = payload["mode"] as? String { switchOutput(mode) }
    case "trackFavoriteCurrent":
      if let currentTrack { toggleFavorite(currentTrack) }
    case "externalMetadataRefresh": refreshExternalMetadata(manual: true)
    case "signalPathVisible":
      signalPathVisible = payload["visible"] as? Bool ?? false
      if usesLocalEngineOutput {
        refreshEngineSignalMetrics(audioEngine.playbackStatus(), includeLevels: signalPathVisible)
      }
      if !signalPathVisible {
        playerModel.signalMeter.clipping = false
        playerModel.signalMeter.lufsMomentary = nil
        playerModel.signalMeter.peakDb = -120
        playerModel.signalMeter.rmsDb = -120
      }
    case "externalFieldSourcesSelect": applyExternalMetadataSelection(payload)
    case "externalSourcePickerDismiss": clearExternalMetadataPicker()
    case "externalSourcePickerIgnore": ignoreExternalMetadataPicker()
    case "artworkError": break
    case "queuePlay", "trackPlay":
      guard let id = payload["id"] as? String else { return }
      let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:))
      if let playlistId = payload["playlistId"] as? String, !playlistId.isEmpty,
        let playlist = persistent.playlists.first(where: { $0.id == playlistId }) {
        queue = sortedPlaylistTracks(resolvedTracks(playlist.tracks), by: payload["sort"] as? String)
        activeQueuePlaylistId = playlistId
      } else if action == "trackPlay" {
        activeQueuePlaylistId = ""
      }
      if let track = track(id: id, source: source) {
        play(track)
        playerModel.activePage = "control"
        renderPages()
      }
    case "queueMove": moveQueueItem(payload)
    case "queueRemove": removeQueueItem(payload)
    case "queueClear": clearQueue(payload)
    case "librarySource":
      if let value = payload["selection"] as? String {
        librarySource = value
        resetLibraryPosition()
        scheduleStreamingSearchIfNeeded()
        refreshVisibleLibraryIfNeeded()
      }
    case "libraryView":
      if let value = payload["selection"] as? String { libraryView = value; resetLibraryPosition(); renderPages() }
    case "libraryFilter":
      if let value = payload["selection"] as? String { libraryFilter = value; resetLibraryPosition(); renderPages() }
    case "libraryQuery":
      libraryQuery = payload["text"] as? String ?? ""
      if libraryQuery.isEmpty {
        echoAlbumGeneration &+= 1
        selectedCollectionId = ""
        echoAlbumBusy = false
      }
      libraryPage = 0
      scheduleStreamingSearchIfNeeded()
      renderPages()
    case "libraryPage", "libraryIndex":
      if let index = payload["index"] as? Int {
        libraryPage = max(0, index)
        if action == "libraryIndex" { libraryExpanded = true }
        renderPages()
      }
    case "libraryExpand":
      libraryExpanded = payload["enabled"] as? Bool ?? true
      libraryPage = 0
      renderPages()
    case "libraryAlbumSort":
      albumTrackSort = payload["selection"] as? String ?? "default"
      libraryPage = 0
      renderPages()
    case "librarySort":
      librarySort = payload["selection"] as? String ?? "default"
      libraryPage = 0
      renderPages()
    case "libraryCollectionSelect": selectCollection(payload)
    case "collectionPlay": playCollection(payload)
    case "libraryRefresh":
      resetLibraryArtworkLookup()
      refreshVisibleLibrary()
    case "libraryImport": importLocalMusic()
    case "libraryPlayFirst":
      if let first = localTracks.first {
        activeQueuePlaylistId = ""; queue = localTracks; play(first, forcedMode: .local)
        playerModel.activePage = "control"; renderPages()
      }
    case "trackQueue":
      if let id = payload["id"] as? String,
        let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:)),
        let value = track(id: id, source: source),
        !queue.contains(where: { trackKey($0) == trackKey(value) }) {
        activeQueuePlaylistId = ""
        queue.append(value)
        if source == .remote { powerampQueueManagedLocally = true }
        updateQueueModel(); persistQueue(); synchronizeControlledQueue()
      }
    case "trackNext": insertTrackNext(payload)
    case "trackLyrics": importLocalLyrics(payload)
    case "trackDelete": deleteLocalTrack(payload)
    case "trackFavorite":
      if let id = payload["id"] as? String,
        let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:)),
        let value = track(id: id, source: source) { toggleFavorite(value) }
    case "remoteTrackControl":
      if let id = payload["id"] as? String, let value = track(id: id, source: .remote) {
        play(value, forcedMode: .remoteControl); playerModel.activePage = "control"; renderPages()
      }
    case "remoteTrackStream":
      if let id = payload["id"] as? String, let value = track(id: id, source: .remote) {
        play(value, forcedMode: .remoteStream); playerModel.activePage = "control"; renderPages()
      }
    case "playlistCreate": createPlaylist(payload)
    case "playlistRename": renamePlaylist(payload)
    case "playlistDelete": deletePlaylist(payload)
    case "playlistOpen":
      selectedPlaylistId = payload["playlistId"] as? String ?? ""
      renderPages()
    case "playlistClose": selectedPlaylistId = ""; renderPages()
    case "playlistPin": mutatePlaylist(payload) { $0.pinned.toggle() }
    case "playlistFavorite": mutatePlaylist(payload) { $0.favorite.toggle() }
    case "playlistAddTrack": addTrackToPlaylist(payload)
    case "playlistRemoveTrack": removeTrackFromPlaylist(payload)
    case "playlistPlay": playPlaylist(payload)
    case "collectionPlaylistAdd": addCollectionToPlaylist(payload)
    case "collectionPlaylistCreate": createPlaylistFromCollection(payload)
    case "connectMode":
      connectMode = payload["selection"] as? String ?? "echo"
      renderPages()
    case "connectionField": updateConnectionField(payload, remote: false)
    case "powerampRemoteField": updateConnectionField(payload, remote: true)
    case "connectionSave": saveConnection(remote: false)
    case "powerampRemoteSave": savePowerampConnection(payload)
    case "connectionTest": testConnection(remote: false)
    case "powerampRemoteTest": testConnection(remote: true)
    case "echoConnectionEnabled": setConnectionEnabled(payload, remote: false)
    case "powerampRemoteEnabled": setConnectionEnabled(payload, remote: true)
    case "pairingText": pairingText = payload["text"] as? String ?? ""
    case "pairConnection": applyPairing(pairingText, remote: false)
    case "pairScanned": applyPairing(payload["text"] as? String ?? "", remote: false)
    case "powerampPairScanned": applyPairing(payload["text"] as? String ?? "", remote: true)
    case "streamingWebLogin": acceptNeteaseCookie(payload["text"] as? String ?? "")
    case "streamingAccessMode":
      guard let selection = payload["selection"] as? String, selection == "direct" || selection == "selfHosted" else { return }
      clearNeteaseQrLogin()
      persistent.settings.neteaseAccessMode = selection
      if selection == "direct" { persistent.settings.neteaseApiBaseUrl = "https://music.163.com" }
      persist(); configureClients(); renderPages()
    case "streamingApiUrl":
      clearNeteaseQrLogin()
      persistent.settings.neteaseApiBaseUrl = payload["text"] as? String ?? ""
      persist(); configureClients(); renderPages()
    case "streamingLogout":
      clearNeteaseQrLogin()
      EchoNativePersistence.setNeteaseCookie("")
      neteaseClient = nil; neteaseClientConfiguration = ""; neteaseProfile = nil; neteasePlaylists = []; neteaseTracks = []; neteaseSearchTracks = []; persistent.streamingRecommendedTracks = []; persistent.streamingRecommendationDate = ""; streamingStatus = ""; streamingSearchStatus = ""; persist(); renderPages()
    case "streamingLogin": startNeteaseQrLogin()
    case "streamingQrResume": resumeNeteaseQrLogin()
    case "streamingLibraryMode":
      searchTask?.cancel()
      streamingLibraryMode = payload["selection"] as? String ?? "search"
      selectedStreamingPlaylistId = ""
      libraryQuery = ""
      neteaseTracks = []
      libraryPage = 0
      libraryExpanded = false
      streamingStatus = ""
      streamingSearchStatus = ""
      renderPages()
    case "streamingPlaylistOpen": openStreamingPlaylist(payload)
    case "streamingPlaylistClose":
      selectedStreamingPlaylistId = ""
      neteaseTracks = []
      libraryPage = 0
      libraryExpanded = false
      streamingStatus = ""
      renderPages()
    case "streamingPlaylistPin": toggleStreamingPlaylist(payload, pinned: true)
    case "streamingPlaylistFavorite": toggleStreamingPlaylist(payload, pinned: false)
    case "streamingRecommendationsRefresh":
      Task { await refreshDailyRecommendations(force: true) }
    case "streamingConnect": connectMode = "streaming"; playerModel.activePage = "connect"; renderPages()
    case "desktopLyricsBackgroundImage": importDesktopLyricsBackground(payload["data"] as? Data)
    case "appearanceBackgroundImage": importAppearanceBackground(payload["data"] as? Data)
    case "appearanceFont": importAppearanceFont(payload["data"] as? Data)
    case "settingToggle": updateSettingToggle(payload)
    case "settingSelect": updateSettingSelection(payload)
    case "settingNumber": updateSettingNumber(payload)
    case "settingResetSection": resetSettingsSection(payload["section"] as? String ?? "")
    case "settingAction": performSettingAction(payload)
    default: break
    }
  }

  private func applySettings() {
    let settings = persistent.settings
    playerModel.activePage = settings.defaultPage
    applyAppearanceSettings()
    playerModel.artworkBackgroundEnabled = settings.artworkBackgroundEnabled
    playerModel.darkModeEnabled = settings.darkModeEnabled
    playerModel.desktopLyricsEnabled = settings.desktopLyricsEnabled
    playerModel.followSystemAppearance = settings.followSystemAppearance
    playerModel.language = settings.language
    playerModel.playbackMode = settings.playbackMode
    playerModel.showArtworkGlow = settings.showArtworkGlow
    playerModel.showPlayerOutputInMenu = settings.showPlayerOutputInMenu
    playerModel.equalizer.gains = normalizedGains(settings.eqGains)
    playerModel.equalizer.language = settings.language
    playerModel.equalizer.preset = settings.eqPreset
    pagesModel.equalizer.gains = normalizedGains(settings.eqGains)
    pagesModel.equalizer.language = settings.language
    pagesModel.equalizer.preset = settings.eqPreset
    playerModel.eqEnabled = settings.eqGains.contains { abs($0) > 0.01 }
    playerModel.loudnessEnabled = settings.loudnessEnabled
    librarySource = settings.defaultLibrarySource
    if librarySource == "echo", !persistent.echoConnection.enabled { librarySource = "local" }
    if librarySource == "remote", !persistent.powerampConnection.enabled { librarySource = "local" }
    libraryView = librarySource == "local" ? settings.defaultLocalLibraryView : "songs"
    audioEngine.setEq(gains: settings.eqGains)
    audioEngine.setLoudness(settings.loudnessEnabled)
    configureDesktopLyrics()
  }

  private func configureClients() {
    let nextEchoClient = try? EchoNativeRemoteClient(connection: persistent.echoConnection, kind: .echo)
    let nextPowerampClient = try? EchoNativeRemoteClient(connection: persistent.powerampConnection, kind: .poweramp)
    if echoClient?.connection != nextEchoClient?.connection {
      echoBusy = false
      echoStatus = nil
      echoOnline = false
      echoError = ""
    }
    if powerampClient?.connection != nextPowerampClient?.connection {
      powerampBusy = false
      powerampQueueManagedLocally = false
      powerampStatus = nil
      powerampOnline = false
      powerampError = ""
    }
    echoClient = nextEchoClient
    powerampClient = nextPowerampClient
    let storedCookie = EchoNativePersistence.neteaseCookie()
    let cookie = hasNeteaseAccountCookie(storedCookie) ? storedCookie : ""
    let baseUrl = persistent.settings.neteaseAccessMode == "direct"
      ? "https://music.163.com"
      : persistent.settings.neteaseApiBaseUrl
    let configuration = cookie.isEmpty ? "" : "\(baseUrl)\u{0}\(cookie)"
    let metadataConfiguration = "\(baseUrl)\u{0}\(cookie)"
    if metadataConfiguration != metadataNeteaseClientConfiguration {
      metadataNeteaseClientConfiguration = metadataConfiguration
      metadataNeteaseClient = URL(string: baseUrl)?.host == nil
        ? nil
        : EchoNativeNeteaseClient(baseUrl: baseUrl, cookie: cookie)
    }
    if configuration != neteaseClientConfiguration || (!configuration.isEmpty && neteaseClient == nil) {
      streamingBusy = false
      if configuration != neteaseClientConfiguration {
        searchTask?.cancel()
        neteaseProfile = nil
        neteasePlaylists = []
        neteaseTracks = []
        neteaseSearchTracks = []
        selectedStreamingPlaylistId = ""
        streamingStatus = ""
        streamingSearchStatus = ""
      }
      neteaseClientConfiguration = configuration
      neteaseClient = configuration.isEmpty || URL(string: baseUrl)?.host == nil
        ? nil
        : EchoNativeNeteaseClient(baseUrl: baseUrl, cookie: cookie)
    }
  }

  private func startProgressClock() {
    progressTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard let self else { return }
        self.tickPlayback()
      }
    }
  }

  private func startPolling() {
    echoPollTask?.cancel()
    powerampPollTask?.cancel()
    echoPollTask = echoClient == nil ? nil : Task { [weak self] in
      while !Task.isCancelled, self?.echoClient != nil {
        await self?.refreshEcho(loadLibrary: false)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
    powerampPollTask = powerampClient == nil ? nil : Task { [weak self] in
      while !Task.isCancelled, self?.powerampClient != nil {
        await self?.refreshPoweramp(loadLibrary: false)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  func refreshEcho(loadLibrary: Bool) async {
    guard let echoClient else {
      if echoOnline { echoOnline = false; renderPages() }
      return
    }
    let wasOnline = echoOnline
    let previousError = echoError
    if loadLibrary { echoBusy = true; renderPages() }
    do {
      if loadLibrary {
        async let status = echoClient.status()
        async let tracks = echoClient.allTracks()
        async let albums = echoClient.allAlbums()
        let values = try await (status, tracks, albums)
        guard self.echoClient === echoClient else { return }
        echoAlbums = values.2
        let loadedAlbumTracks = collectionTrackKeys
          .filter { $0.key.hasPrefix("echo:album-id:") }
          .flatMap { $0.value.compactMap(track(forKey:)) }
        let refreshedTracks = values.1.map { resolvedTrack($0, includeLibraryFallback: false) }
        var refreshedIds = Set(refreshedTracks.map(\.id))
        echoTracks = refreshedTracks + loadedAlbumTracks.filter { refreshedIds.insert($0.id).inserted }
        applyRemoteStatus(values.0, kind: .echo)
      } else {
        let status = try await echoClient.status()
        guard self.echoClient === echoClient else { return }
        applyRemoteStatus(status, kind: .echo)
      }
      echoOnline = true
      echoError = ""
    } catch {
      guard self.echoClient === echoClient else { return }
      echoOnline = false
      echoError = errorMessage(error)
    }
    if loadLibrary { echoBusy = false }
    if loadLibrary || wasOnline != echoOnline || previousError != echoError { renderPages() }
  }

  func refreshPoweramp(loadLibrary: Bool) async {
    guard let powerampClient else {
      if powerampOnline { powerampOnline = false; renderPages() }
      return
    }
    let wasOnline = powerampOnline
    let previousError = powerampError
    if loadLibrary { powerampBusy = true; renderPages() }
    do {
      if loadLibrary {
        async let status = powerampClient.status()
        async let tracks = powerampClient.allTracks()
        async let albums = powerampClient.allAlbums()
        let values = try await (status, tracks, albums)
        guard self.powerampClient === powerampClient else { return }
        powerampAlbums = values.2
        powerampTracks = values.1
        powerampTracks = powerampTracks.map { resolvedTrack($0, includeLibraryFallback: false) }
        applyRemoteStatus(values.0, kind: .poweramp)
      } else {
        let status = try await powerampClient.status()
        guard self.powerampClient === powerampClient else { return }
        applyRemoteStatus(status, kind: .poweramp)
      }
      powerampOnline = true
      powerampError = ""
    } catch {
      guard self.powerampClient === powerampClient else { return }
      powerampOnline = false
      powerampError = errorMessage(error)
    }
    if loadLibrary { powerampBusy = false }
    if loadLibrary || wasOnline != powerampOnline || previousError != powerampError { renderPages() }
  }

  func refreshLocalLibrary() async {
    localBusy = true
    renderPages()
    let scannedTracks = await EchoNativeLocalLibrary.scan()
    localTracks = scannedTracks.map { resolvedTrack($0, includeLibraryFallback: false) }
    localTracks.filter(EchoNativeLocalLibrary.needsExternalMetadataEmbedding).forEach(scheduleLocalMetadataEmbedding)
    localBusy = false
    renderPages()
  }

  private func applyRemoteStatus(_ status: EchoNativePlaybackStatus, kind: EchoNativeRemoteKind) {
    if kind == .echo {
      guard echoStatus.map({ status.playback.updatedAtEpochMs >= $0.playback.updatedAtEpochMs }) ?? true else { return }
      echoStatus = status
      echoStatusReceivedAt = Date()
      if outputMode == .pc { applyControlledPlayback(status, source: .echo) }
    } else {
      guard powerampStatus.map({ status.playback.updatedAtEpochMs >= $0.playback.updatedAtEpochMs }) ?? true else { return }
      powerampStatus = status
      powerampStatusReceivedAt = Date()
      if outputMode == .remoteControl { applyControlledPlayback(status, source: .remote) }
    }
  }

  private func applyControlledPlayback(_ status: EchoNativePlaybackStatus, source: EchoNativeTrackSource) {
    var trackChanged = false
    var trackIdentityChanged = false
    var clearedTrack = false
    if var track = status.playback.track {
      track.source = source
      let baseUrl = source == .echo ? echoClient?.baseUrl : powerampClient?.baseUrl
      if let artwork = track.artworkUrl, let baseUrl {
        track.artworkUrl = URL(string: artwork, relativeTo: baseUrl)?.absoluteURL.absoluteString
      }
      track = resolvedTrack(track)
      if let currentTrack, trackKey(currentTrack) == trackKey(track) {
        if track.artworkUrl?.isEmpty != false { track.artworkUrl = currentTrack.artworkUrl }
        if track.artist.isEmpty { track.artist = currentTrack.artist }
        if track.album.isEmpty { track.album = currentTrack.album }
      }
      if currentTrack != track {
        trackIdentityChanged = currentTrack.map(trackKey) != trackKey(track)
        currentTrack = track
        updatePlayerTrack(track)
        trackChanged = true
      }
    } else if currentTrack != nil {
      clearCurrentPlayback()
      clearedTrack = true
    }
    if currentTrack == nil {
      setIfChanged(playerModel, \.isPlaying, false)
      playerModel.positionMs = 0
      setIfChanged(playerModel, \.durationMs, 0)
    } else {
      setIfChanged(playerModel, \.isPlaying, status.playback.state == "playing")
      playerModel.positionMs = status.playback.positionMs
      setIfChanged(playerModel, \.durationMs, status.playback.durationMs)
    }
    setIfChanged(playerModel, \.volume, max(0, min(1, status.playback.volume)))
    if let currentTrack {
      setIfChanged(playerModel, \.tags, tags(for: currentTrack))
      updateSignalPath(for: currentTrack)
    }
    var queueChanged = false
    if activeQueuePlaylistId.isEmpty,
      (source == .echo || !powerampQueueManagedLocally),
      let items = status.playback.queue?.items {
      let baseUrl = source == .echo ? echoClient?.baseUrl : powerampClient?.baseUrl
      let nextQueue = items.map { item in
        var value = item
        value.source = source
        if let artwork = value.artworkUrl, let baseUrl {
          value.artworkUrl = URL(string: artwork, relativeTo: baseUrl)?.absoluteURL.absoluteString
        }
        return value
      }
      if queue != nextQueue { queue = nextQueue; queueChanged = true }
      if source == .remote { powerampQueueManagedLocally = true }
    }
    if trackChanged || queueChanged || clearedTrack { updateQueueModel() }
    if trackIdentityChanged {
      loadLyricsForCurrentTrack()
      if persistent.settings.externalMetadataEnabled { refreshExternalMetadata(manual: false) }
    }
    publishNowPlaying()
  }

  private func tickPlayback() {
    switch outputMode {
    case .local, .phone, .remoteStream, .streaming:
      if audioLoading {
        setIfChanged(playerModel, \.isPlaying, false)
        setIfChanged(playerModel, \.signalEngineRunning, false)
      } else {
        let status = audioEngine.playbackStatus()
        playerModel.positionMs = status.currentTime * 1000
        setIfChanged(playerModel, \.durationMs, status.duration * 1000)
        setIfChanged(playerModel, \.isPlaying, status.playing)
        refreshEngineSignalMetrics(
          status,
          includeLevels: signalPathVisible
            || persistent.settings.desktopLyricsEnabled && persistent.settings.desktopLyricsVisualizer != "off"
        )
        if status.didJustFinish, let currentTrack {
          let key = trackKey(currentTrack)
          if handledFinishedTrackKey != key {
            handledFinishedTrackKey = key
            playNext(automatic: true)
          }
        }
      }
    case .pc:
      updateEstimatedRemotePosition(status: echoStatus, receivedAt: echoStatusReceivedAt)
    case .remoteControl:
      updateEstimatedRemotePosition(status: powerampStatus, receivedAt: powerampStatusReceivedAt)
    }
    updateActiveLyricIndex()
    updateDesktopLyrics()
    publishNowPlaying()
  }

  private func updateEstimatedRemotePosition(status: EchoNativePlaybackStatus?, receivedAt: Date) {
    guard let status else { return }
    let elapsed = status.playback.state == "playing" ? Date().timeIntervalSince(receivedAt) * 1000 : 0
    playerModel.positionMs = min(status.playback.durationMs, max(0, status.playback.positionMs + elapsed))
  }

  private func togglePlayPause() {
    switch outputMode {
    case .local, .phone, .remoteStream, .streaming:
      do {
        let status = audioEngine.playbackStatus()
        if status.duration <= 0, let currentTrack {
          play(currentTrack, forcedMode: outputMode, positionMs: playerModel.positionMs)
          return
        }
        if status.playing {
          audioEngine.pause()
        } else {
          handledFinishedTrackKey = ""
          try audioEngine.resume()
        }
        playerModel.isPlaying = audioEngine.playbackStatus().playing
      } catch { showError(error) }
    case .pc:
      sendRemoteCommand(["command": "playPause"], client: echoClient, source: .echo)
    case .remoteControl:
      sendRemoteCommand(["command": "playPause"], client: powerampClient, source: .remote)
    }
  }

  private func play(
    _ requestedTrack: EchoNativeCoreTrack,
    forcedMode: EchoNativeOutputMode? = nil,
    positionMs: Double = 0,
    pauseRemoteAfterStart: Bool = false
  ) {
    let track = resolvedTrack(requestedTrack)
    if !externalMetadataTrackKey.isEmpty, externalMetadataTrackKey != trackKey(track) {
      clearExternalMetadataPicker()
    }
    playbackGeneration &+= 1
    let generation = playbackGeneration
    playbackLoadTask?.cancel()
    playbackLoadTask = nil
    audioLoading = false
    lyricsGeneration &+= 1
    lyricsTask?.cancel()
    lyricsTask = nil
    metadataGeneration &+= 1
    metadataTask?.cancel()
    metadataTask = nil
    metadataRetryTask?.cancel()
    metadataRetryTask = nil
    metadataRetryAttempts[trackKey(track)] = 0
    externalMetadataLoading = false
    updateLoadingState()
    let mode = forcedMode ?? modeForTrack(track)
    outputMode = mode
    playerModel.outputMode = mode.rawValue
    currentTrack = track
    playerModel.positionMs = max(0, positionMs)
    handledFinishedTrackKey = ""
    if let index = queue.firstIndex(where: { trackKey($0) == trackKey(track) }) {
      queue[index] = track
    } else {
      queue = resolvedTracks(libraryTracks(for: track.source))
      activeQueuePlaylistId = ""
    }
    if track.source == .remote { powerampQueueManagedLocally = true }
    updatePlayerTrack(track)
    if mode != .streaming { addRecent(track) }
    switch mode {
    case .local:
      guard let uri = track.localUrl else { showError(EchoNativeNetworkError.invalidResponse); return }
      playFile(uri: uri, track: track, positionMs: positionMs)
    case .pc:
      audioEngine.stop()
      sendRemoteCommand(["command": "playTrack", "trackId": track.id, "output": "pc"], client: echoClient, source: .echo, expectedGeneration: generation)
    case .remoteControl:
      audioEngine.stop()
      sendRemoteCommand(["command": "playTrack", "trackId": track.id], client: powerampClient, source: .remote, expectedGeneration: generation)
    case .phone:
      audioEngine.stop()
      playerModel.isPlaying = false
      stream(track, client: echoClient, positionMs: positionMs, generation: generation, pauseRemoteAfterStart: pauseRemoteAfterStart)
    case .remoteStream:
      audioEngine.stop()
      playerModel.isPlaying = false
      stream(track, client: powerampClient, positionMs: positionMs, generation: generation, pauseRemoteAfterStart: pauseRemoteAfterStart)
    case .streaming:
      audioEngine.stop()
      playerModel.isPlaying = false
      streamNetease(track, positionMs: positionMs, generation: generation)
    }
    updateQueueModel()
    persistQueue()
    loadLyricsForCurrentTrack()
    if track.source == .local, persistent.settings.autoOpenLyricsForLocalTracks, track.hasLyrics {
      playerModel.lyricsVisible = true
    }
    if persistent.settings.externalMetadataEnabled { refreshExternalMetadata(manual: false) }
  }

  private func playFile(uri: String, track: EchoNativeCoreTrack, positionMs: Double = 0) {
    do {
      try audioEngine.playFile(
        uri: uri,
        positionMs: positionMs,
        volume: playerModel.volume,
        gains: playerModel.equalizer.gains,
        loudnessEnabled: persistent.settings.loudnessEnabled
      )
      let status = audioEngine.playbackStatus()
      playerModel.isPlaying = status.playing
      refreshEngineSignalMetrics(status, includeLevels: signalPathVisible)
      updateSignalPath(for: track)
      publishNowPlaying()
    } catch {
      playerModel.isPlaying = false
      showError(error)
    }
  }

  private func stream(
    _ track: EchoNativeCoreTrack,
    client: EchoNativeRemoteClient?,
    positionMs: Double = 0,
    generation: Int,
    pauseRemoteAfterStart: Bool
  ) {
    guard let client else { showError(EchoNativeNetworkError.invalidConnection); return }
    audioLoading = true
    updateLoadingState()
    playbackLoadTask = Task {
      defer {
        if playbackGeneration == generation {
          playbackLoadTask = nil
          audioLoading = false
          updateLoadingState()
        }
      }
      do {
        let response = try await client.stream(trackId: track.id)
        guard let remoteUrl = URL(string: response.streamUrl) else { throw EchoNativeNetworkError.invalidResponse }
        var streamedTrack = response.track
        streamedTrack.source = track.source
        if streamedTrack.artworkUrl?.isEmpty != false { streamedTrack.artworkUrl = track.artworkUrl }
        let file = try await EchoNativeStreamCache.file(for: remoteUrl, track: streamedTrack)
        guard isCurrentRemoteClient(client, source: track.source), playbackGeneration == generation,
          currentTrack.map({ trackKey($0) }) == trackKey(track) else { return }
        replaceTrack(streamedTrack)
        currentTrack = streamedTrack
        updatePlayerTrack(streamedTrack)
        playFile(uri: file.absoluteString, track: streamedTrack, positionMs: positionMs)
        if pauseRemoteAfterStart {
          let status = track.source == .echo ? echoStatus : powerampStatus
          if status?.playback.state == "playing" || status?.playback.state == "loading" {
            sendRemoteCommand(["command": "playPause"], client: client, source: track.source, expectedGeneration: generation)
          }
        }
      } catch {
        if isCurrentRemoteClient(client, source: track.source), playbackGeneration == generation { showError(error) }
      }
    }
  }

  private func streamNetease(_ track: EchoNativeCoreTrack, positionMs: Double = 0, generation: Int) {
    guard let neteaseClient else { showError(EchoNativeNetworkError.invalidConnection); return }
    audioLoading = true
    updateLoadingState()
    playbackLoadTask = Task {
      defer {
        if playbackGeneration == generation {
          playbackLoadTask = nil
          audioLoading = false
          updateLoadingState()
        }
      }
      do {
        let detailedTrack = try? await neteaseClient.trackDetail(trackId: track.id)
        var playbackTrack = detailedTrack.map { resolvedTrack($0) } ?? track
        if playbackTrack.artworkUrl?.isEmpty != false { playbackTrack.artworkUrl = track.artworkUrl }
        guard self.neteaseClient === neteaseClient, playbackGeneration == generation,
          currentTrack.map({ trackKey($0) }) == trackKey(track) else { return }
        replaceTrack(playbackTrack)
        currentTrack = playbackTrack
        updatePlayerTrack(playbackTrack)
        let remoteUrl = try await neteaseClient.playbackUrl(trackId: track.id)
        let file = try await EchoNativeStreamCache.file(for: remoteUrl, track: playbackTrack)
        guard self.neteaseClient === neteaseClient, playbackGeneration == generation,
          currentTrack.map({ trackKey($0) }) == trackKey(playbackTrack) else { return }
        playFile(uri: file.absoluteString, track: playbackTrack, positionMs: positionMs)
        if playerModel.isPlaying, let currentTrack { addRecent(currentTrack) }
      } catch {
        if self.neteaseClient === neteaseClient, playbackGeneration == generation { showError(error) }
      }
    }
  }

  private func sendRemoteCommand(
    _ command: [String: Any],
    client: EchoNativeRemoteClient?,
    source: EchoNativeTrackSource,
    expectedGeneration: Int? = nil
  ) {
    guard let client else { showError(EchoNativeNetworkError.invalidConnection); return }
    Task {
      do {
        let status = try await client.command(command)
        guard isCurrentRemoteClient(client, source: source), expectedGeneration.map({ $0 == playbackGeneration }) ?? true else { return }
        applyRemoteStatus(status, kind: source == .echo ? .echo : .poweramp)
      }
      catch {
        if isCurrentRemoteClient(client, source: source), expectedGeneration.map({ $0 == playbackGeneration }) ?? true { showError(error) }
      }
    }
  }

  private func isCurrentRemoteClient(_ client: EchoNativeRemoteClient, source: EchoNativeTrackSource) -> Bool {
    source == .echo ? echoClient === client : powerampClient === client
  }

  private func playNext(automatic: Bool = false) {
    switch persistent.settings.playbackMode {
    case .normal:
      playAdjacent(1, wraps: false)
    case .repeatAll:
      playAdjacent(1)
    case .repeatOne:
      if automatic {
        if let currentTrack { play(currentTrack) }
      } else {
        playAdjacent(1, wraps: false)
      }
    case .shuffle:
      guard !queue.isEmpty else { playAdjacent(1, wraps: false); return }
      let currentKey = currentTrack.map(trackKey)
      let candidates = queue.filter { trackKey($0) != currentKey }
      if let track = candidates.randomElement() ?? queue.first { play(track) }
    }
  }

  private func playAdjacent(_ direction: Int, wraps: Bool = true) {
    guard !queue.isEmpty else {
      if outputMode == .pc { sendRemoteCommand(["command": direction > 0 ? "next" : "previous"], client: echoClient, source: .echo) }
      if outputMode == .remoteControl { sendRemoteCommand(["command": direction > 0 ? "next" : "previous"], client: powerampClient, source: .remote) }
      return
    }
    let index = currentTrack.flatMap { value in queue.firstIndex(where: { trackKey($0) == trackKey(value) }) } ?? (direction > 0 ? -1 : 0)
    let nextIndex = index + direction
    if queue.indices.contains(nextIndex) {
      play(queue[nextIndex])
    } else if wraps {
      play(queue[(nextIndex + queue.count) % queue.count])
    }
  }

  private func seek(toMilliseconds value: Double) {
    let position = max(0, min(value, playerModel.durationMs))
    playerModel.positionMs = position
    switch outputMode {
    case .local, .phone, .remoteStream, .streaming:
      do { try audioEngine.seekTo(seconds: position / 1000) } catch { showError(error) }
    case .pc:
      sendRemoteCommand(["command": "seekTo", "positionMs": position], client: echoClient, source: .echo)
    case .remoteControl:
      sendRemoteCommand(["command": "seekTo", "positionMs": position], client: powerampClient, source: .remote)
    }
  }

  private func setVolume(_ value: Double) {
    let volume = max(0, min(1, value))
    playerModel.volume = volume
    switch outputMode {
    case .local, .phone, .remoteStream, .streaming: audioEngine.setVolume(volume)
    case .pc: sendRemoteCommand(["command": "setVolume", "volume": volume], client: echoClient, source: .echo)
    case .remoteControl: sendRemoteCommand(["command": "setVolume", "volume": volume], client: powerampClient, source: .remote)
    }
  }

  private func switchOutput(_ rawMode: String) {
    let previousMode = outputMode
    let mapped: EchoNativeOutputMode?
    switch rawMode {
    case "echo": mapped = .pc
    case "remote": mapped = .remoteControl
    default: mapped = EchoNativeOutputMode(rawValue: rawMode)
    }
    guard let mode = mapped else { return }
    if mode == previousMode { return }
    if (mode == .pc || mode == .phone), echoClient == nil {
      connectMode = "echo"
      playerModel.activePage = "connect"
      renderPages()
      return
    }
    if (mode == .remoteControl || mode == .remoteStream), powerampClient == nil {
      connectMode = "remote"
      playerModel.activePage = "connect"
      renderPages()
      return
    }
    if previousMode == .pc, mode != .pc, mode != .phone,
      echoStatus?.playback.state == "playing" || echoStatus?.playback.state == "loading" {
      sendRemoteCommand(["command": "playPause"], client: echoClient, source: .echo)
    }
    if previousMode == .remoteControl, mode != .remoteControl, mode != .remoteStream,
      powerampStatus?.playback.state == "playing" || powerampStatus?.playback.state == "loading" {
      sendRemoteCommand(["command": "playPause"], client: powerampClient, source: .remote)
    }
    if mode == .local {
      guard let track = (currentTrack?.source == .local ? currentTrack : nil) ?? localTracks.first else {
        librarySource = "local"; playerModel.activePage = "library"; renderPages(); return
      }
      activeQueuePlaylistId = ""
      play(track, forcedMode: .local)
      return
    }
    if mode == .streaming {
      guard let track = (currentTrack?.source == .streaming ? currentTrack : nil) ?? neteaseTracks.first else {
        librarySource = "streaming"; playerModel.activePage = "library"; renderPages(); return
      }
      activeQueuePlaylistId = ""
      play(track, forcedMode: .streaming)
      return
    }
    if mode == .phone {
      var track = echoStatus?.playback.track ?? (currentTrack?.source == .echo ? currentTrack : nil) ?? echoTracks.first
      track?.source = .echo
      guard let track else { connectMode = "echo"; playerModel.activePage = "connect"; renderPages(); return }
      let position = echoStatus?.playback.track?.id == track.id ? echoStatus?.playback.positionMs ?? 0 : 0
      activeQueuePlaylistId = ""
      play(track, forcedMode: .phone, positionMs: position, pauseRemoteAfterStart: previousMode == .pc)
      return
    }
    if mode == .remoteStream {
      var track = powerampStatus?.playback.track ?? (currentTrack?.source == .remote ? currentTrack : nil) ?? powerampTracks.first
      track?.source = .remote
      guard let track else { connectMode = "remote"; playerModel.activePage = "connect"; renderPages(); return }
      let position = powerampStatus?.playback.track?.id == track.id ? powerampStatus?.playback.positionMs ?? 0 : 0
      activeQueuePlaylistId = ""
      play(track, forcedMode: .remoteStream, positionMs: position, pauseRemoteAfterStart: previousMode == .remoteControl)
      return
    }
    playbackGeneration &+= 1
    let generation = playbackGeneration
    if mode == .pc || mode == .remoteControl {
      switch previousMode {
      case .local, .phone, .remoteStream, .streaming: audioEngine.pause()
      case .pc, .remoteControl: break
      }
    }
    outputMode = mode
    playerModel.outputMode = mode.rawValue
    if let currentTrack {
      playerModel.tags = tags(for: currentTrack)
      updateSignalPath(for: currentTrack)
    } else {
      clearSignalPath()
    }
    if mode == .pc, previousMode == .phone, let currentTrack, currentTrack.source == .echo {
      audioEngine.pause()
      sendRemoteCommand([
        "command": "handoff",
        "trackId": currentTrack.id,
        "positionMs": playerModel.positionMs,
        "target": "pc",
      ], client: echoClient, source: .echo, expectedGeneration: generation)
      return
    }
    if mode == .pc, let echoStatus { applyControlledPlayback(echoStatus, source: .echo); return }
    if mode == .pc, let track = echoTracks.first { play(track, forcedMode: .pc); return }
    if mode == .remoteControl, previousMode == .remoteStream, let currentTrack, currentTrack.source == .remote {
      audioEngine.pause()
      handoffToPoweramp(currentTrack, positionMs: playerModel.positionMs, generation: generation)
      return
    }
    if mode == .remoteControl, let powerampStatus { applyControlledPlayback(powerampStatus, source: .remote); return }
    if mode == .remoteControl, let track = powerampTracks.first { play(track, forcedMode: .remoteControl) }
  }

  private func handoffToPoweramp(_ track: EchoNativeCoreTrack, positionMs: Double, generation: Int) {
    guard let client = powerampClient else { showError(EchoNativeNetworkError.invalidConnection); return }
    Task {
      do {
        var status = try await client.command(["command": "playTrack", "trackId": track.id])
        guard powerampClient === client, playbackGeneration == generation else { return }
        if positionMs > 0 {
          status = try await client.command(["command": "seekTo", "positionMs": positionMs])
        }
        guard powerampClient === client, playbackGeneration == generation else { return }
        applyRemoteStatus(status, kind: .poweramp)
      } catch {
        if powerampClient === client, playbackGeneration == generation { showError(error) }
      }
    }
  }

  private func clearCurrentPlayback() {
    playbackGeneration &+= 1
    playbackLoadTask?.cancel()
    playbackLoadTask = nil
    lyricsGeneration &+= 1
    lyricsTask?.cancel()
    lyricsTask = nil
    metadataGeneration &+= 1
    metadataTask?.cancel()
    metadataTask = nil
    metadataRetryTask?.cancel()
    metadataRetryTask = nil
    audioLoading = false
    externalMetadataLoading = false
    audioEngine.stop()
    currentTrack = nil
    playerModel.album = ""
    playerModel.artist = ""
    playerModel.artworkUrl = ""
    playerModel.controlsEnabled = false
    playerModel.durationMs = 0
    playerModel.isFavorite = false
    playerModel.isPlaying = false
    playerModel.activeLyricIndex = 0
    playerModel.lyricLines = []
    playerModel.positionMs = 0
    playerModel.tags = []
    playerModel.title = ""
    clearSignalPath()
    clearExternalMetadataPicker()
    updateLoadingState()
    nowPlayingController.clear()
    lastNowPlayingTrackKey = ""
    EchoNativeWidgetBridge.clear()
    updateDesktopLyrics()
  }

  private func updatePlayerTrack(_ track: EchoNativeCoreTrack) {
    playerModel.title = track.title
    playerModel.album = track.album
    playerModel.artist = track.artist
    playerModel.artworkUrl = track.artworkUrl ?? ""
    playerModel.durationMs = track.durationMs
    playerModel.controlsEnabled = true
    playerModel.isFavorite = persistent.favoriteTrackKeys.contains(trackKey(track))
    playerModel.outputMode = outputMode.rawValue
    playerModel.tags = tags(for: track)
    updateSignalPath(for: track)
  }

  private func publishNowPlaying() {
    guard let track = currentTrack else { return }
    let position = playerModel.positionMs / 1000
    let key = trackKey(track)
    guard lastNowPlayingTrackKey != key || lastNowPlayingState != playerModel.isPlaying
      || abs(position - lastNowPlayingPosition) >= 0.9 else { return }
    lastNowPlayingTrackKey = key
    lastNowPlayingState = playerModel.isPlaying
    lastNowPlayingPosition = position
    nowPlayingController.update(
      title: track.title,
      artist: track.artist,
      album: track.album,
      artworkURL: track.artworkUrl ?? "",
      duration: playerModel.durationMs / 1000,
      position: position,
      isPlaying: playerModel.isPlaying
    )
    EchoNativeWidgetBridge.publish(title: track.title, artist: track.artist, isPlaying: playerModel.isPlaying)
  }

  private func handleRemoteCommand(_ command: NowPlayingRemoteCommand, position: Double?) {
    switch command {
    case .next: playNext()
    case .previous: playAdjacent(-1)
    case .pause: if playerModel.isPlaying { togglePlayPause() }
    case .play: if !playerModel.isPlaying { togglePlayPause() }
    case .toggle: togglePlayPause()
    case .seek: if let position { seek(toMilliseconds: position * 1000) }
    }
  }

  private func updateQueueModel() {
    let source = currentTrack?.source.rawValue ?? "local"
    let payload: [String: Any] = [
      "canEdit": true,
      "clearLabel": localized("Clear", "清空"),
      "emptyLabel": localized("The queue is empty.", "当前播放列表暂无内容。"),
      "items": queue.enumerated().map { index, track in [
        "artist": track.artist,
        "current": currentTrack.map({ trackKey($0) }) == trackKey(track),
        "id": "\(trackKey(track)):\(index)",
        "meta": track.album.isEmpty ? track.sourceLabel : track.album,
        "source": track.source.rawValue,
        "title": track.title,
        "trackId": track.id,
      ] as [String: Any] },
      "moveDownLabel": localized("Move down", "下移"),
      "moveUpLabel": localized("Move up", "上移"),
      "playlistId": activeQueuePlaylistId,
      "removeLabel": localized("Remove", "移除"),
      "source": source,
      "subtitle": localized("\(queue.count) tracks", "\(queue.count) 首歌曲"),
      "title": localized("Queue", "播放列表"),
    ]
    playerModel.updateQueue(payloadJSON: json(payload))
  }

  private func moveQueueItem(_ payload: [String: Any]) {
    guard let index = payload["index"] as? Int, let direction = payload["value"] as? Int else { return }
    let destination = index + direction
    guard queue.indices.contains(index), queue.indices.contains(destination) else { return }
    queue.swapAt(index, destination)
    if outputMode == .remoteControl || outputMode == .remoteStream { powerampQueueManagedLocally = true }
    synchronizeActivePlaylist()
    updateQueueModel(); persistQueue()
    synchronizeControlledQueue()
  }

  private func removeQueueItem(_ payload: [String: Any]) {
    guard let index = payload["index"] as? Int, queue.indices.contains(index) else { return }
    queue.remove(at: index)
    if outputMode == .remoteControl || outputMode == .remoteStream { powerampQueueManagedLocally = true }
    synchronizeActivePlaylist()
    updateQueueModel(); persistQueue()
    synchronizeControlledQueue()
  }

  private func clearQueue(_ payload: [String: Any]) {
    let playlistId = payload["playlistId"] as? String ?? activeQueuePlaylistId
    queue = []
    if outputMode == .remoteControl || outputMode == .remoteStream { powerampQueueManagedLocally = true }
    if !playlistId.isEmpty,
      let index = persistent.playlists.firstIndex(where: { $0.id == playlistId }) {
      persistent.playlists[index].tracks.removeAll()
    }
    updateQueueModel(); persistQueue(); persist(); synchronizeControlledQueue()
  }

  private func synchronizeControlledQueue() {
    guard outputMode == .pc else { return }
    let controlledQueue = queue.filter { $0.source == .echo }
    if controlledQueue.isEmpty {
      sendRemoteCommand(["command": "queueClear", "output": "pc"], client: echoClient, source: .echo)
      return
    }
    sendRemoteCommand([
      "command": "queueReorder",
      "trackIds": controlledQueue.map(\.id),
      "startTrackId": currentTrack.flatMap { current in
        current.source == .echo && controlledQueue.contains(where: { $0.id == current.id }) ? current.id : nil
      } ?? controlledQueue[0].id,
      "output": "pc",
    ], client: echoClient, source: .echo)
  }

  private func restoreQueue() {
    var playlistsChanged = false
    for index in persistent.playlists.indices {
      let tracks = resolvedTracks(persistent.playlists[index].tracks)
      if tracks != persistent.playlists[index].tracks {
        persistent.playlists[index].tracks = tracks
        playlistsChanged = true
      }
    }
    let streamingSnapshots = Dictionary(
      persistent.streamingQueueTracks.map { (trackKey($0), $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let values = persistent.queueTrackKeys.compactMap { key in
      streamingSnapshots[key] ?? track(forKey: key)
    }
    queue = values
    powerampQueueManagedLocally = values.contains { $0.source == .remote }
    updateQueueModel()
    if playlistsChanged || values.count != persistent.queueTrackKeys.count {
      persistQueue()
    }
  }

  private func synchronizeActivePlaylist() {
    guard !activeQueuePlaylistId.isEmpty,
      let index = persistent.playlists.firstIndex(where: { $0.id == activeQueuePlaylistId })
    else { return }
    persistent.playlists[index].tracks = queue
  }

  private func persistQueue() {
    persistent.queueTrackKeys = queue.map { trackKey($0) }
    persistent.streamingQueueTracks = queue.filter { $0.source == .streaming }
    persist()
  }

  private func applyEqPreset(_ preset: String) {
    let gains: [Double]
    switch preset {
    case "bass": gains = [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]
    case "clarity": gains = [-1, -1, 0, 1, 2, 3, 4, 4, 3, 2]
    case "lateNight": gains = [2, 2, 1, 0, -1, -1, 0, 1, 2, 2]
    case "vocal": gains = [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
    case "warm": gains = [3, 2, 2, 1, 0, -1, -1, 0, 1, 1]
    default: gains = Array(repeating: 0, count: 10)
    }
    playerModel.equalizer.gains = gains
    playerModel.equalizer.preset = preset
    pagesModel.equalizer.gains = gains
    pagesModel.equalizer.preset = preset
    persistent.settings.eqGains = gains
    persistent.settings.eqPreset = preset
    playerModel.eqEnabled = gains.contains { abs($0) > 0.01 }
    audioEngine.setEq(gains: gains)
    persist(); renderPages()
  }

  private func toggleFavorite(_ track: EchoNativeCoreTrack) {
    let key = trackKey(track)
    if persistent.favoriteTrackKeys.contains(key) { persistent.favoriteTrackKeys.remove(key) }
    else { persistent.favoriteTrackKeys.insert(key) }
    playerModel.isFavorite = persistent.favoriteTrackKeys.contains(key)
    persist(); renderPages()
  }

  private func addRecent(_ track: EchoNativeCoreTrack) {
    let key = trackKey(track)
    persistent.recentTrackKeys.removeAll { $0 == key }
    persistent.recentTrackKeys.insert(key, at: 0)
    persistent.recentTrackKeys = Array(persistent.recentTrackKeys.prefix(100))
    persistent.recentTracks.removeAll { trackKey($0) == key }
    persistent.recentTracks.insert(track, at: 0)
    persistent.recentTracks = Array(persistent.recentTracks.prefix(100))
    persist()
  }

  private func playPlaylist(_ payload: [String: Any]) {
    guard let id = payload["playlistId"] as? String,
      let playlist = persistent.playlists.first(where: { $0.id == id }) else { return }
    queue = sortedPlaylistTracks(resolvedTracks(playlist.tracks), by: payload["sort"] as? String)
    guard let first = queue.first else { return }
    activeQueuePlaylistId = id
    play(first)
    playerModel.activePage = "control"
    renderPages()
  }

  private func sortedPlaylistTracks(_ tracks: [EchoNativeCoreTrack], by sort: String?) -> [EchoNativeCoreTrack] {
    switch sort {
    case "title": return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    case "artist": return tracks.sorted {
      let order = $0.artist.localizedStandardCompare($1.artist)
      return order == .orderedAscending
        || (order == .orderedSame && $0.title.localizedStandardCompare($1.title) == .orderedAscending)
    }
    case "duration": return tracks.sorted {
      $0.durationMs == $1.durationMs
        ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
        : $0.durationMs < $1.durationMs
    }
    default: return tracks
    }
  }

  private func createPlaylist(_ payload: [String: Any]) {
    guard let name = payload["text"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    var tracks: [EchoNativeCoreTrack] = []
    if let id = payload["id"] as? String,
      let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:)),
      let value = track(id: id, source: source) { tracks = [value] }
    persistent.playlists.append(EchoNativeSavedPlaylist(
      createdAt: Date().timeIntervalSince1970,
      favorite: false,
      id: UUID().uuidString,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines),
      pinned: false,
      tracks: tracks
    ))
    persist(); renderPages()
  }

  private func renamePlaylist(_ payload: [String: Any]) {
    guard let id = payload["playlistId"] as? String, let name = payload["text"] as? String,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      let index = persistent.playlists.firstIndex(where: { $0.id == id }) else { return }
    persistent.playlists[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    persist(); renderPages()
  }

  private func deletePlaylist(_ payload: [String: Any]) {
    guard let id = payload["playlistId"] as? String else { return }
    persistent.playlists.removeAll { $0.id == id }
    if selectedPlaylistId == id { selectedPlaylistId = "" }
    if activeQueuePlaylistId == id { activeQueuePlaylistId = "" }
    persist(); renderPages()
  }

  private func mutatePlaylist(_ payload: [String: Any], mutation: (inout EchoNativeSavedPlaylist) -> Void) {
    guard let id = payload["playlistId"] as? String, let index = persistent.playlists.firstIndex(where: { $0.id == id }) else { return }
    mutation(&persistent.playlists[index]); persist(); renderPages()
  }

  private func addTrackToPlaylist(_ payload: [String: Any]) {
    guard let playlistId = payload["playlistId"] as? String,
      let id = payload["id"] as? String,
      let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:)),
      let value = track(id: id, source: source),
      let index = persistent.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    if !persistent.playlists[index].tracks.contains(where: { trackKey($0) == trackKey(value) }) {
      persistent.playlists[index].tracks.append(value)
      if activeQueuePlaylistId == playlistId {
        queue.append(value); updateQueueModel(); synchronizeControlledQueue(); persistQueue()
      } else {
        persist()
      }
      renderPages()
    }
  }

  private func removeTrackFromPlaylist(_ payload: [String: Any]) {
    guard let playlistId = payload["playlistId"] as? String,
      let id = payload["trackId"] as? String,
      let source = payload["source"] as? String,
      let index = persistent.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    persistent.playlists[index].tracks.removeAll { $0.id == id && $0.source.rawValue == source }
    if activeQueuePlaylistId == playlistId {
      queue.removeAll { $0.id == id && $0.source.rawValue == source }
      updateQueueModel(); synchronizeControlledQueue(); persistQueue()
    } else {
      persist()
    }
    renderPages()
  }

  private func addCollectionToPlaylist(_ payload: [String: Any]) {
    guard let playlistId = payload["playlistId"] as? String,
      let index = persistent.playlists.firstIndex(where: { $0.id == playlistId }) else { return }
    let tracks = selectedCollectionTracks()
    let existing = Set(persistent.playlists[index].tracks.map { trackKey($0) })
    let additions = tracks.filter { !existing.contains(trackKey($0)) }
    persistent.playlists[index].tracks.append(contentsOf: additions)
    if activeQueuePlaylistId == playlistId {
      queue.append(contentsOf: additions); updateQueueModel(); synchronizeControlledQueue(); persistQueue()
    } else {
      persist()
    }
    renderPages()
  }

  private func createPlaylistFromCollection(_ payload: [String: Any]) {
    let name = payload["text"] as? String ?? localized("New playlist", "新建歌单")
    persistent.playlists.append(EchoNativeSavedPlaylist(
      createdAt: Date().timeIntervalSince1970,
      favorite: false,
      id: UUID().uuidString,
      name: name,
      pinned: false,
      tracks: selectedCollectionTracks()
    ))
    persist(); renderPages()
  }

  private func insertTrackNext(_ payload: [String: Any]) {
    guard let id = payload["id"] as? String,
      let source = (payload["source"] as? String).flatMap(EchoNativeTrackSource.init(rawValue:)),
      let value = track(id: id, source: source)
    else { return }
    let index = currentTrack.flatMap { current in queue.firstIndex(where: { trackKey($0) == trackKey(current) }) } ?? -1
    activeQueuePlaylistId = ""
    queue.removeAll { trackKey($0) == trackKey(value) }
    queue.insert(value, at: min(queue.count, index + 1))
    if source == .remote { powerampQueueManagedLocally = true }
    updateQueueModel(); persistQueue(); synchronizeControlledQueue()
  }

  private func deleteLocalTrack(_ payload: [String: Any]) {
    guard let id = payload["id"] as? String, let value = track(id: id, source: .local) else { return }
    let key = trackKey(value)
    let wasCurrent = currentTrack.map(trackKey) == key
    do { try EchoNativeLocalLibrary.delete(value) } catch { showError(error); return }
    localTracks.removeAll { $0.id == id }
    queue.removeAll { trackKey($0) == key }
    for index in persistent.playlists.indices {
      persistent.playlists[index].tracks.removeAll { trackKey($0) == key }
    }
    persistent.favoriteTrackKeys.remove(key)
    persistent.recentTrackKeys.removeAll { $0 == key }
    persistent.recentTracks.removeAll { trackKey($0) == key }
    if wasCurrent { clearCurrentPlayback() }
    synchronizeActivePlaylist()
    persistQueue(); updateQueueModel(); renderPages()
  }

  private func importLocalMusic() {
    guard let presenter else { return }
    let existingKeys = Set(localTracks.map(trackKey))
    localBusy = true; renderPages()
    Task {
      do { _ = try await EchoNativeLocalLibrary.importFiles(from: presenter) }
      catch { showError(error) }
      await refreshLocalLibrary()
      if persistent.settings.autoQueueImportedLocalTracks {
        let additions = localTracks.filter { !existingKeys.contains(trackKey($0)) }
        let queued = Set(queue.map(trackKey))
        queue.append(contentsOf: additions.filter { !queued.contains(trackKey($0)) })
        updateQueueModel(); persistQueue()
      }
    }
  }

  private func importLocalLyrics(_ payload: [String: Any]) {
    guard let presenter, let id = payload["id"] as? String, let track = track(id: id, source: .local) else { return }
    Task {
      do {
        let imported = try await EchoNativeLocalLibrary.importLyrics(for: track, from: presenter)
        if imported {
          await refreshLocalLibrary()
          if currentTrack.map({ trackKey($0) }) == trackKey(track) { loadLyricsForCurrentTrack() }
        }
      } catch { showError(error) }
    }
  }

  private func updateConnectionField(_ payload: [String: Any], remote: Bool) {
    guard let field = payload["field"] as? String else { return }
    let value = payload["text"] as? String ?? ""
    if remote {
      switch field {
      case "host": persistent.powerampConnection.host = value
      case "name": persistent.powerampConnection.name = value
      case "port": if let port = Int(value) { persistent.powerampConnection.port = port }
      case "token": persistent.powerampConnection.token = value
      default: break
      }
    } else {
      switch field {
      case "host": persistent.echoConnection.host = value
      case "port": if let port = Int(value) { persistent.echoConnection.port = port }
      case "token": persistent.echoConnection.token = value
      default: break
      }
    }
  }

  private func saveConnection(remote: Bool) {
    let connection = remote ? persistent.powerampConnection : persistent.echoConnection
    guard !connection.host.isEmpty, !connection.token.isEmpty, (1...65535).contains(connection.port) else {
      showConnectionError(errorMessage(EchoNativeNetworkError.invalidConnection)); return
    }
    persist(); configureClients(); startPolling()
    Task {
      if remote { await refreshPoweramp(loadLibrary: true) }
      else { await refreshEcho(loadLibrary: true) }
    }
  }

  private func testConnection(remote: Bool) {
    guard (remote ? powerampClient != nil : echoClient != nil) else {
      showConnectionError(errorMessage(EchoNativeNetworkError.invalidConnection))
      return
    }
    Task {
      if remote { await refreshPoweramp(loadLibrary: true) }
      else { await refreshEcho(loadLibrary: true) }
      let message = remote ? powerampError : echoError
      if !message.isEmpty { showConnectionError(message) }
    }
  }

  private func savePowerampConnection(_ payload: [String: Any]) {
    if let host = payload["host"] as? String { persistent.powerampConnection.host = host }
    if let name = payload["name"] as? String { persistent.powerampConnection.name = name }
    if let port = (payload["port"] as? String).flatMap(Int.init) { persistent.powerampConnection.port = port }
    if let token = payload["token"] as? String { persistent.powerampConnection.token = token }
    persistent.powerampConnection.enabled = true
    saveConnection(remote: true)
  }

  private func setConnectionEnabled(_ payload: [String: Any], remote: Bool) {
    let enabled = payload["enabled"] as? Bool ?? false
    if remote {
      persistent.powerampConnection.enabled = enabled
      if !enabled {
        powerampOnline = false; powerampStatus = nil; powerampError = ""
        if librarySource == "remote" { librarySource = "local" }
        if outputMode == .remoteControl || outputMode == .remoteStream { resetDisconnectedPlayback() }
      }
    } else {
      persistent.echoConnection.enabled = enabled
      if !enabled {
        echoOnline = false; echoStatus = nil; echoError = ""
        if librarySource == "echo" { librarySource = "local" }
        if outputMode == .pc || outputMode == .phone { resetDisconnectedPlayback() }
      }
    }
    persist(); configureClients(); startPolling(); renderPages()
  }

  private func resetDisconnectedPlayback() {
    clearCurrentPlayback()
    outputMode = .local
    playerModel.outputMode = EchoNativeOutputMode.local.rawValue
  }

  private func applyPairing(_ raw: String, remote: Bool) {
    guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      showConnectionError(errorMessage(EchoNativeNetworkError.invalidConnection)); return
    }
    var values: [String: String] = [:]
    for item in components.queryItems ?? [] {
      if let value = item.value { values[item.name] = value }
    }
    let scheme = components.scheme?.lowercased() ?? ""
    let validScheme = remote
      ? scheme == "echo-poweramp"
      : scheme == "echo" || scheme == "http" || scheme == "https"
    let host = values["host"] ?? ((scheme == "http" || scheme == "https") ? components.host : nil)
    let port = values["port"].flatMap(Int.init) ?? components.port ?? (remote ? 27806 : 26789)
    guard validScheme, let host, !host.isEmpty, (1...65535).contains(port), let token = values["token"], !token.isEmpty else {
      showConnectionError(errorMessage(EchoNativeNetworkError.invalidConnection)); return
    }
    if remote {
      persistent.powerampConnection.host = host; persistent.powerampConnection.port = port; persistent.powerampConnection.token = token
      persistent.powerampConnection.name = values["name"] ?? "Poweramp"; persistent.powerampConnection.enabled = true
    } else {
      persistent.echoConnection.host = host; persistent.echoConnection.port = port; persistent.echoConnection.token = token
      persistent.echoConnection.name = values["name"] ?? "PC ECHO"; persistent.echoConnection.enabled = true
      persistent.echoConnection.scheme = scheme == "https" || values["scheme"] == "https" ? "https" : "http"
    }
    pairingText = raw; saveConnection(remote: remote)
  }

  private func acceptNeteaseCookie(_ cookie: String) {
    guard hasNeteaseAccountCookie(cookie) else {
      streamingStatus = localized("Invalid NetEase session.", "网易云登录凭据无效")
      renderPages()
      return
    }
    clearNeteaseQrLogin()
    EchoNativePersistence.setNeteaseCookie(cookie)
    configureClients()
    Task { await loadNeteaseAccount() }
  }

  private func startNeteaseQrLogin() {
    guard persistent.settings.neteaseAccessMode == "selfHosted" else {
      streamingStatus = localized("Use official web sign in.", "请使用官方网页登录")
      renderPages()
      return
    }
    let rawBaseUrl = persistent.settings.neteaseApiBaseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let components = URLComponents(string: rawBaseUrl),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      components.host?.isEmpty == false
    else {
      showConnectionError(localized("Enter a valid self-hosted API URL.", "请输入有效的自托管 API 地址"))
      return
    }

    clearNeteaseQrLogin()
    streamingQrGeneration &+= 1
    let generation = streamingQrGeneration
    let client = EchoNativeNeteaseClient(baseUrl: rawBaseUrl, cookie: "")
    streamingBusy = true
    streamingStatus = localized("Creating QR code...", "正在生成二维码...")
    renderPages()
    streamingQrTask = Task {
      defer {
        if streamingQrGeneration == generation {
          streamingQrTask = nil
          streamingBusy = false
          renderPages()
        }
      }
      do {
        let login = try await client.createQrLogin()
        guard streamingQrGeneration == generation else { return }
        streamingQrKey = login.key
        streamingQrUrl = login.url
        streamingStatus = localized("Scan with NetEase Cloud Music.", "请使用网易云音乐扫码")
        renderPages()

        while !Task.isCancelled, streamingQrGeneration == generation {
          do {
            let result = try await client.checkQrLogin(key: login.key)
            guard streamingQrGeneration == generation else { return }
            if result.code == 803 {
              guard let cookie = result.cookie, hasNeteaseAccountCookie(cookie)
              else {
                streamingQrKey = ""
                streamingQrUrl = ""
                streamingStatus = localized(
                  "Signed in, but the API did not return a session cookie.",
                  "已确认登录，但 API 未返回会话凭据"
                )
                return
              }
              streamingQrKey = ""
              streamingQrUrl = ""
              EchoNativePersistence.setNeteaseCookie(cookie)
              configureClients()
              streamingStatus = localized("Signed in.", "登录成功")
              await loadNeteaseAccount()
              return
            }
            if result.code == 800 {
              streamingQrKey = ""
              streamingQrUrl = ""
              streamingStatus = localized("QR code expired.", "二维码已过期，请重新生成")
              return
            }
            let status = result.code == 802
              ? localized("Confirm sign in on your phone.", "请在手机上确认登录")
              : localized("Waiting for scan.", "等待扫码")
            if streamingStatus != status { streamingStatus = status; renderPages() }
          } catch is CancellationError {
            return
          } catch {
            guard streamingQrGeneration == generation else { return }
            let status = errorMessage(error)
            if streamingStatus != status { streamingStatus = status; renderPages() }
          }
          do { try await Task.sleep(nanoseconds: 2_000_000_000) }
          catch { return }
        }
      } catch is CancellationError {
        return
      } catch {
        if streamingQrGeneration == generation {
          streamingStatus = errorMessage(error)
        }
      }
    }
  }

  private func resumeNeteaseQrLogin() {
    if streamingQrTask == nil, !streamingQrKey.isEmpty { startNeteaseQrLogin() }
  }

  private func clearNeteaseQrLogin() {
    streamingQrGeneration &+= 1
    streamingQrTask?.cancel()
    streamingQrTask = nil
    streamingQrKey = ""
    streamingQrUrl = ""
    streamingBusy = false
  }

  private func loadNeteaseAccount() async {
    guard let neteaseClient else { return }
    streamingBusy = true; renderPages()
    defer {
      if self.neteaseClient === neteaseClient {
        streamingBusy = false
        renderPages()
      }
    }
    let profile: EchoNativeNeteaseClient.Profile
    do {
      profile = try await neteaseClient.profile()
      guard self.neteaseClient === neteaseClient else { return }
      if neteaseProfile?.userId != profile.userId { neteasePlaylists = [] }
      neteaseProfile = profile
      streamingStatus = ""
      renderPages()
      scheduleStreamingSearchIfNeeded()
      await refreshDailyRecommendations(force: false)
    } catch {
      if self.neteaseClient === neteaseClient { streamingStatus = errorMessage(error) }
      return
    }
    do {
      let playlists = try await neteaseClient.playlists(userId: profile.userId)
      guard self.neteaseClient === neteaseClient else { return }
      neteasePlaylists = playlists
      streamingStatus = ""
    } catch {
      if self.neteaseClient === neteaseClient { streamingStatus = errorMessage(error) }
    }
  }

  private func refreshDailyRecommendations(force: Bool) async {
    guard let neteaseClient, neteaseProfile != nil else { return }
    let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let today = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    guard force || persistent.streamingRecommendationDate != today
      || persistent.streamingRecommendedTracks.isEmpty else { return }
    if force { streamingBusy = true; renderPages() }
    defer {
      if force, self.neteaseClient === neteaseClient { streamingBusy = false; renderPages() }
    }
    do {
      let tracks = try await neteaseClient.dailyRecommendations()
      guard self.neteaseClient === neteaseClient, !tracks.isEmpty else { return }
      persistent.streamingRecommendedTracks = tracks
      persistent.streamingRecommendationDate = today
      persist()
      renderPages()
    } catch {
      if force, self.neteaseClient === neteaseClient { streamingStatus = errorMessage(error) }
    }
  }

  private func openStreamingPlaylist(_ payload: [String: Any]) {
    guard let id = payload["id"] as? String, let neteaseClient else { return }
    let playWhenLoaded = payload["play"] as? Bool ?? false
    searchTask?.cancel()
    libraryQuery = ""
    neteaseTracks = []
    libraryPage = 0
    libraryExpanded = false
    streamingStatus = ""
    streamingSearchStatus = ""
    selectedStreamingPlaylistId = id
    streamingBusy = true
    renderPages()
    Task {
      defer {
        if self.neteaseClient === neteaseClient,
          selectedStreamingPlaylistId == id || selectedStreamingPlaylistId.isEmpty {
          streamingBusy = false
          renderPages()
        }
      }
      do {
        let tracks = try await neteaseClient.playlistTracks(id: id)
        guard self.neteaseClient === neteaseClient, selectedStreamingPlaylistId == id else { return }
        neteaseTracks = tracks
        libraryPage = 0
        streamingStatus = ""
        if playWhenLoaded, let first = tracks.first {
          activeQueuePlaylistId = ""
          queue = tracks
          play(first, forcedMode: .streaming)
          playerModel.activePage = "control"
        }
      }
      catch {
        if self.neteaseClient === neteaseClient, selectedStreamingPlaylistId == id {
          streamingStatus = errorMessage(error)
        }
      }
    }
  }

  private func toggleStreamingPlaylist(_ payload: [String: Any], pinned: Bool) {
    guard let id = payload["id"] as? String else { return }
    if pinned {
      if streamingPinnedPlaylistIds.contains(id) { streamingPinnedPlaylistIds.remove(id) } else { streamingPinnedPlaylistIds.insert(id) }
    } else {
      if streamingFavoritePlaylistIds.contains(id) { streamingFavoritePlaylistIds.remove(id) } else { streamingFavoritePlaylistIds.insert(id) }
    }
    persist(); renderPages()
  }

  private func scheduleStreamingSearchIfNeeded() {
    searchTask?.cancel()
    let globalSearch = playerModel.activePage == "search"
    let streamingSearch = playerModel.activePage == "library"
      && librarySource == "streaming" && streamingLibraryMode == "search"
    guard globalSearch || streamingSearch, let neteaseClient else { return }
    let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      if globalSearch { neteaseSearchTracks = [] } else { neteaseTracks = [] }
      streamingSearchStatus = ""
      return
    }
    searchTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }
      do {
        let tracks = try await neteaseClient.search(query)
        let contextValid = globalSearch
          ? playerModel.activePage == "search"
          : playerModel.activePage == "library"
            && librarySource == "streaming" && streamingLibraryMode == "search"
        guard self.neteaseClient === neteaseClient,
          contextValid,
          libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
        else { return }
        if globalSearch { neteaseSearchTracks = tracks } else { neteaseTracks = tracks }
        streamingSearchStatus = ""
        renderPages()
      }
      catch {
        let contextValid = globalSearch
          ? playerModel.activePage == "search"
          : playerModel.activePage == "library"
            && librarySource == "streaming" && streamingLibraryMode == "search"
        if self.neteaseClient === neteaseClient,
          contextValid,
          libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query {
          streamingSearchStatus = errorMessage(error)
          renderPages()
        }
      }
    }
  }

  private func updateSettingToggle(_ payload: [String: Any]) {
    guard let key = payload["key"] as? String, let enabled = payload["enabled"] as? Bool else { return }
    switch key {
    case "followSystemAppearance": persistent.settings.followSystemAppearance = enabled; playerModel.followSystemAppearance = enabled
    case "haptics": persistent.settings.hapticsEnabled = enabled
    case "loudness": persistent.settings.loudnessEnabled = enabled; playerModel.loudnessEnabled = enabled; audioEngine.setLoudness(enabled)
    case "autoLyrics": persistent.settings.autoOpenLyricsForLocalTracks = enabled
    case "desktopLyricsEnabled": persistent.settings.desktopLyricsEnabled = enabled; playerModel.desktopLyricsEnabled = enabled
    case "desktopLyricsOnlyWhilePlaying": persistent.settings.desktopLyricsOnlyWhilePlaying = enabled
    case "desktopLyricsProgressBarEnabled": persistent.settings.desktopLyricsProgressBarEnabled = enabled
    case "desktopLyricsProgressRainbow": persistent.settings.desktopLyricsProgressRainbow = enabled
    case "desktopLyricsShowMetadata": persistent.settings.desktopLyricsShowMetadata = enabled
    case "desktopLyricsRainbowGradient": persistent.settings.desktopLyricsRainbowGradient = enabled
    case "desktopLyricsTransitionAnimation": persistent.settings.desktopLyricsTransitionAnimation = enabled
    case "desktopLyricsTimedReveal": persistent.settings.desktopLyricsTimedReveal = enabled
    case "autoQueueImports": persistent.settings.autoQueueImportedLocalTracks = enabled
    case "confirmDelete": persistent.settings.confirmBeforeDeletingLocalTracks = enabled
    case "artworkGlow": persistent.settings.showArtworkGlow = enabled; playerModel.showArtworkGlow = enabled
    case "artworkBackground": persistent.settings.artworkBackgroundEnabled = enabled; playerModel.artworkBackgroundEnabled = enabled
    case "playerOutputInMenu": persistent.settings.showPlayerOutputInMenu = enabled; playerModel.showPlayerOutputInMenu = enabled
    case "externalMetadataSearch":
      persistent.settings.externalMetadataEnabled = enabled
      if enabled {
        refreshExternalMetadata(manual: false)
      } else {
        metadataGeneration &+= 1
        metadataTask?.cancel()
        metadataTask = nil
        metadataRetryTask?.cancel()
        metadataRetryTask = nil
        externalMetadataLoading = false
        updateLoadingState()
      }
      resetLibraryArtworkLookup()
    case "externalMetadataSkipExisting": persistent.settings.externalMetadataSkipExisting = enabled
    case "lrcapi":
      persistent.settings.lrcApiExternalDataEnabled = enabled
      resetLibraryArtworkLookup()
    case "lrclib": persistent.settings.lrclibExternalDataEnabled = enabled
    case "netease":
      persistent.settings.neteaseExternalDataEnabled = enabled
      resetLibraryArtworkLookup()
    case "showPowerampRemoteConnection":
      persistent.settings.showPowerampRemote = enabled
      if !enabled, connectMode == "remote" { connectMode = "echo" }
    default:
      if key.hasPrefix("audioTag.") {
        persistent.settings.audioTagVisibility[String(key.dropFirst(9))] = enabled
        if let currentTrack { playerModel.tags = tags(for: currentTrack) }
      }
    }
    applyAppearanceSettings()
    configureDesktopLyrics()
    persist(); renderPages()
  }

  private func updateSettingSelection(_ payload: [String: Any]) {
    guard let key = payload["key"] as? String, let selection = payload["selection"] as? String else { return }
    switch key {
    case "language":
      persistent.settings.language = selection
      playerModel.language = selection
      playerModel.equalizer.language = selection
      pagesModel.equalizer.language = selection
    case "defaultPage": persistent.settings.defaultPage = selection
    case "appearanceBackground": persistent.settings.appearanceBackground = selection
    case "motionStyle": persistent.settings.motionStyle = selection
    case "themeColor": persistent.settings.themeColorHex = selection
    case "desktopLyricsProgressColor": persistent.settings.desktopLyricsProgressColorHex = selection
    case "defaultLibrarySource": persistent.settings.defaultLibrarySource = selection; librarySource = selection; resetLibraryPosition()
    case "defaultLocalView":
      persistent.settings.defaultLocalLibraryView = selection
      if librarySource == "local" { libraryView = selection; resetLibraryPosition() }
    case "externalSelectionMode": persistent.settings.externalDataSelectionMode = selection
    case "neteaseAccessMode":
      clearNeteaseQrLogin()
      persistent.settings.neteaseAccessMode = selection
      if selection == "direct" { persistent.settings.neteaseApiBaseUrl = "https://music.163.com" }
      configureClients()
    case "manualAppearance": persistent.settings.darkModeEnabled = selection == "dark"; playerModel.darkModeEnabled = selection == "dark"
    case "desktopLyricsAnimation": persistent.settings.desktopLyricsAnimation = selection
    case "desktopLyricsBackground": persistent.settings.desktopLyricsBackground = selection
    case "desktopLyricsPosition": persistent.settings.desktopLyricsPosition = selection
    case "desktopLyricsSize": persistent.settings.desktopLyricsSize = selection
    case "desktopLyricsVisualizer": persistent.settings.desktopLyricsVisualizer = selection
    default: break
    }
    applyAppearanceSettings()
    configureDesktopLyrics()
    persist(); renderPages()
  }

  private func updateSettingNumber(_ payload: [String: Any]) {
    guard let key = payload["key"] as? String, let value = number(payload["value"]) else { return }
    switch key {
    case "desktopLyricsSize": persistent.settings.desktopLyricsFontSize = max(18, min(48, value))
    case "desktopLyricsWidth": persistent.settings.desktopLyricsWidthScale = max(0.2, min(1.0, value))
    case "desktopLyricsHeight": persistent.settings.desktopLyricsHeightScale = max(0.33, min(1.0, value))
    case "fontScale": persistent.settings.fontScale = max(0.85, min(1.25, value))
    default: return
    }
    applyAppearanceSettings()
    configureDesktopLyrics()
    if payload["commit"] as? Bool == true {
      persist()
      renderPages()
    }
  }

  private func performSettingAction(_ payload: [String: Any]) {
    switch payload["key"] as? String {
    case "rescanMetadata": Task { await refreshLocalLibrary() }
    case "clearLocalQueue": activeQueuePlaylistId = ""; queue.removeAll { $0.source == .local }; updateQueueModel(); persistQueue()
    case "clearRecent": persistent.recentTrackKeys = []; persistent.recentTracks = []; persist(); renderPages()
    default: break
    }
  }

  private func resetSettingsSection(_ section: String) {
    let defaults = EchoNativeCoreSettings()
    switch section {
    case "interface":
      persistent.settings.language = defaults.language
      persistent.settings.defaultPage = defaults.defaultPage
      persistent.settings.followSystemAppearance = defaults.followSystemAppearance
      persistent.settings.darkModeEnabled = defaults.darkModeEnabled
    case "appearance":
      persistent.settings.appearanceBackground = defaults.appearanceBackground
      persistent.settings.themeColorHex = defaults.themeColorHex
      persistent.settings.customFontName = defaults.customFontName
      persistent.settings.fontScale = defaults.fontScale
    case "motion":
      persistent.settings.motionStyle = defaults.motionStyle
      persistent.settings.hapticsEnabled = defaults.hapticsEnabled
    case "desktopLyrics":
      persistent.settings.desktopLyricsAnimation = defaults.desktopLyricsAnimation
      persistent.settings.desktopLyricsBackground = defaults.desktopLyricsBackground
      persistent.settings.desktopLyricsEnabled = defaults.desktopLyricsEnabled
      persistent.settings.desktopLyricsFontSize = defaults.desktopLyricsFontSize
      persistent.settings.desktopLyricsHeightScale = defaults.desktopLyricsHeightScale
      persistent.settings.desktopLyricsOnlyWhilePlaying = defaults.desktopLyricsOnlyWhilePlaying
      persistent.settings.desktopLyricsPosition = defaults.desktopLyricsPosition
      persistent.settings.desktopLyricsProgressBarEnabled = defaults.desktopLyricsProgressBarEnabled
      persistent.settings.desktopLyricsProgressColorHex = defaults.desktopLyricsProgressColorHex
      persistent.settings.desktopLyricsProgressRainbow = defaults.desktopLyricsProgressRainbow
      persistent.settings.desktopLyricsRainbowGradient = defaults.desktopLyricsRainbowGradient
      persistent.settings.desktopLyricsShowMetadata = defaults.desktopLyricsShowMetadata
      persistent.settings.desktopLyricsSize = defaults.desktopLyricsSize
      persistent.settings.desktopLyricsTimedReveal = defaults.desktopLyricsTimedReveal
      persistent.settings.desktopLyricsTransitionAnimation = defaults.desktopLyricsTransitionAnimation
      persistent.settings.desktopLyricsVisualizer = defaults.desktopLyricsVisualizer
      persistent.settings.desktopLyricsWidthScale = defaults.desktopLyricsWidthScale
    case "playback":
      persistent.settings.eqGains = defaults.eqGains
      persistent.settings.eqPreset = defaults.eqPreset
      persistent.settings.loudnessEnabled = defaults.loudnessEnabled
      persistent.settings.autoOpenLyricsForLocalTracks = defaults.autoOpenLyricsForLocalTracks
      persistent.settings.showArtworkGlow = defaults.showArtworkGlow
      persistent.settings.showPlayerOutputInMenu = defaults.showPlayerOutputInMenu
      playerModel.equalizer.gains = defaults.eqGains
      playerModel.equalizer.preset = defaults.eqPreset
      pagesModel.equalizer.gains = defaults.eqGains
      pagesModel.equalizer.preset = defaults.eqPreset
      playerModel.eqEnabled = false
      audioEngine.setEq(gains: defaults.eqGains)
      audioEngine.setLoudness(defaults.loudnessEnabled)
    case "externalData":
      persistent.settings.externalDataSelectionMode = defaults.externalDataSelectionMode
      persistent.settings.externalMetadataEnabled = defaults.externalMetadataEnabled
      persistent.settings.externalMetadataSkipExisting = defaults.externalMetadataSkipExisting
      persistent.settings.lrcApiExternalDataEnabled = defaults.lrcApiExternalDataEnabled
      persistent.settings.lrclibExternalDataEnabled = defaults.lrclibExternalDataEnabled
      persistent.settings.neteaseAccessMode = defaults.neteaseAccessMode
      persistent.settings.neteaseApiBaseUrl = defaults.neteaseApiBaseUrl
      persistent.settings.neteaseExternalDataEnabled = defaults.neteaseExternalDataEnabled
      metadataGeneration &+= 1
      metadataTask?.cancel()
      metadataTask = nil
      metadataRetryTask?.cancel()
      metadataRetryTask = nil
      externalMetadataLoading = false
      updateLoadingState()
      clearExternalMetadataPicker()
      resetLibraryArtworkLookup()
      clearNeteaseQrLogin()
      configureClients()
    case "library":
      persistent.settings.defaultLibrarySource = defaults.defaultLibrarySource
      persistent.settings.defaultLocalLibraryView = defaults.defaultLocalLibraryView
      persistent.settings.autoQueueImportedLocalTracks = defaults.autoQueueImportedLocalTracks
      persistent.settings.confirmBeforeDeletingLocalTracks = defaults.confirmBeforeDeletingLocalTracks
      librarySource = defaults.defaultLibrarySource
      libraryView = defaults.defaultLocalLibraryView
      resetLibraryPosition()
    case "remote":
      persistent.settings.showPowerampRemote = defaults.showPowerampRemote
      if !defaults.showPowerampRemote, connectMode == "remote" { connectMode = "echo" }
    case "audioTags":
      persistent.settings.audioTagVisibility = defaults.audioTagVisibility
      if let currentTrack { playerModel.tags = tags(for: currentTrack) }
    default: return
    }
    applyAppearanceSettings()
    let settings = persistent.settings
    playerModel.darkModeEnabled = settings.darkModeEnabled
    playerModel.desktopLyricsEnabled = settings.desktopLyricsEnabled
    playerModel.followSystemAppearance = settings.followSystemAppearance
    playerModel.language = settings.language
    playerModel.loudnessEnabled = settings.loudnessEnabled
    playerModel.showArtworkGlow = settings.showArtworkGlow
    playerModel.showPlayerOutputInMenu = settings.showPlayerOutputInMenu
    playerModel.equalizer.language = settings.language
    pagesModel.equalizer.language = settings.language
    configureDesktopLyrics()
    persist()
    renderPages()
  }

  private func refreshVisibleLibrary() {
    Task {
      switch librarySource {
      case "echo": await refreshEcho(loadLibrary: true)
      case "remote": await refreshPoweramp(loadLibrary: true)
      case "local": await refreshLocalLibrary()
      case "streaming": await loadNeteaseAccount()
      default:
        await refreshLocalLibrary()
        await refreshEcho(loadLibrary: true)
        await refreshPoweramp(loadLibrary: true)
      }
    }
  }

  private func refreshVisibleLibraryIfNeeded() {
    refreshVisibleLibrary()
    renderPages()
  }

  private func selectCollection(_ payload: [String: Any]) {
    selectedCollectionId = payload["id"] as? String ?? ""
    libraryQuery = payload["text"] as? String ?? ""
    albumTrackSort = payload["selection"] as? String ?? albumTrackSort
    libraryPage = 0
    guard let albumId = echoAlbumId(from: selectedCollectionId), let echoClient else {
      renderPages()
      return
    }
    let collectionId = selectedCollectionId
    echoAlbumGeneration &+= 1
    let generation = echoAlbumGeneration
    collectionTrackKeys[collectionId] = []
    echoAlbumBusy = true
    renderPages()
    Task {
      defer {
        if echoAlbumGeneration == generation, selectedCollectionId == collectionId {
          echoAlbumBusy = false
          renderPages()
        }
      }
      do {
        let fetched = try await echoClient.albumTracks(albumId: albumId).map {
          resolvedTrack($0, includeLibraryFallback: false)
        }
        guard echoAlbumGeneration == generation, self.echoClient === echoClient else { return }
        let replacements = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        let existingIds = Set(echoTracks.map(\.id))
        let merged = echoTracks.map { replacements[$0.id] ?? $0 } + fetched.filter { !existingIds.contains($0.id) }
        if merged != echoTracks { echoTracks = merged }
        let keys = fetched.map(trackKey)
        collectionTrackKeys[collectionId] = keys
        libraryCollectionsCacheTrackKeys[collectionId] = keys
        echoError = ""
      } catch {
        guard echoAlbumGeneration == generation, self.echoClient === echoClient else { return }
        echoError = errorMessage(error)
      }
    }
  }

  private func echoAlbumId(from collectionId: String) -> String? {
    let prefix = "echo:album-id:"
    guard collectionId.hasPrefix(prefix) else { return nil }
    return String(collectionId.dropFirst(prefix.count))
  }

  private func playCollection(_ payload: [String: Any]) {
    var values = selectedCollectionTracks()
    let sort = payload["selection"] as? String ?? albumTrackSort
    values = sort == "default" || sort == "track"
      ? albumOrdered(values)
      : sortedPlaylistTracks(values, by: sort)
    guard let first = values.first else { return }
    activeQueuePlaylistId = ""
    queue = values
    play(first)
    playerModel.activePage = "control"
    renderPages()
  }

  private func selectedCollectionTracks() -> [EchoNativeCoreTrack] {
    let keys = collectionTrackKeys[selectedCollectionId] ?? []
    return keys.compactMap(track(forKey:))
  }

  private func loadLyricsForCurrentTrack() {
    guard let track = currentTrack else { return }
    lyricsGeneration &+= 1
    lyricsTask?.cancel()
    let generation = lyricsGeneration
    playerModel.activeLyricIndex = 0
    playerModel.lyricLines = []
    updateDesktopLyrics()
    lyricsTask = Task {
      var lyrics = ""
      lyrics = track.externalLyrics ?? ""
      if lyrics.isEmpty, let raw = track.externalLyricsUrl, let url = URL(string: raw) {
        lyrics = await EchoNativeMetadataService.text(from: url)
      }
      if lyrics.isEmpty, let raw = track.lyricsUrl, let url = URL(string: raw) {
        lyrics = await EchoNativeMetadataService.text(from: url)
      }
      if lyrics.isEmpty, track.source == .echo { lyrics = (try? await echoClient?.lyrics(trackId: track.id)) ?? "" }
      if lyrics.isEmpty, track.source == .remote { lyrics = (try? await powerampClient?.lyrics(trackId: track.id)) ?? "" }
      if lyrics.isEmpty, track.source == .streaming { lyrics = (try? await neteaseClient?.lyrics(trackId: track.id)) ?? "" }
      guard lyricsGeneration == generation, currentTrack.map({ trackKey($0) }) == trackKey(track) else { return }
      let lines = EchoNativeMetadataService.parseLyrics(lyrics)
      playerModel.lyricLines = lines
      updateActiveLyricIndex()
      updateDesktopLyrics()
      if lyricsGeneration == generation { lyricsTask = nil }
      if lyrics.isEmpty, metadataTask == nil, persistent.settings.externalMetadataEnabled {
        refreshExternalMetadata(manual: false, forceMissing: true)
      }
    }
  }

  private func refreshExternalMetadata(manual: Bool, forceMissing: Bool = false) {
    guard let track = currentTrack else { return }
    guard track.source != .streaming else { return }
    let key = trackKey(track)
    let settings = persistent.settings
    let hasArtwork = track.artworkUrl?.isEmpty == false
    let hasLyrics = track.hasLyrics || track.externalLyrics?.isEmpty == false
      || track.externalLyricsUrl?.isEmpty == false || !playerModel.lyricLines.isEmpty
    let hasCompleteMetadata = hasArtwork && hasLyrics && !track.artist.isEmpty
    guard manual || settings.externalMetadataEnabled else { return }
    guard settings.lrcApiExternalDataEnabled || settings.lrclibExternalDataEnabled || settings.neteaseExternalDataEnabled else { return }
    guard manual || forceMissing || !settings.externalMetadataSkipExisting || !hasCompleteMetadata else { return }
    guard manual || !ignoredExternalMetadataTrackKeys.contains(key) else { return }
    if manual {
      ignoredExternalMetadataTrackKeys.remove(key)
      metadataRetryAttempts[key] = 0
    }
    metadataRetryTask?.cancel()
    metadataRetryTask = nil
    metadataTask?.cancel()
    metadataGeneration &+= 1
    let generation = metadataGeneration
    externalMetadataLoading = true
    updateLoadingState()
    metadataTask = Task {
      defer {
        if metadataGeneration == generation {
          metadataTask = nil
          externalMetadataLoading = false
          updateLoadingState()
        }
      }
      do {
        let candidates = try await EchoNativeMetadataService.candidates(
          for: track,
          sources: EchoNativeMetadataService.Sources(
            lrcApi: settings.lrcApiExternalDataEnabled,
            lrclib: settings.lrclibExternalDataEnabled,
            netease: settings.neteaseExternalDataEnabled
          ),
          neteaseClient: metadataNeteaseClient
        )
        guard metadataGeneration == generation, currentTrack.map({ trackKey($0) }) == trackKey(track) else { return }
        if settings.externalDataSelectionMode == "ask" {
          if candidates.isEmpty {
            scheduleExternalMetadataRetry(for: track)
          } else {
            metadataRetryAttempts[key] = 0
            externalMetadataCandidates = candidates
            externalMetadataTrackKey = key
            playerModel.updateExternalSourcePicker(payloadJSON: externalMetadataPickerJSON(candidates, track: track, generation: generation))
          }
        } else {
          applyExternalMetadata(
            EchoNativeMetadataService.automaticResult(from: candidates),
            to: track,
            fillMissingOnly: settings.externalMetadataSkipExisting
          )
          if let currentTrack,
            currentTrack.artworkUrl?.isEmpty != false || currentTrack.artist.isEmpty
              || !currentTrack.hasLyrics && playerModel.lyricLines.isEmpty {
            scheduleExternalMetadataRetry(for: currentTrack)
          } else {
            metadataRetryAttempts[key] = 0
          }
        }
      } catch {
        guard metadataGeneration == generation else { return }
        if manual { showError(error) }
        else { scheduleExternalMetadataRetry(for: track) }
      }
    }
  }

  private func scheduleExternalMetadataRetry(for track: EchoNativeCoreTrack) {
    let key = trackKey(track)
    guard currentTrack.map(trackKey) == key, persistent.settings.externalMetadataEnabled else { return }
    let attempt = metadataRetryAttempts[key, default: 0]
    let delays: [UInt64] = [2, 8, 30]
    guard delays.indices.contains(attempt) else { return }
    metadataRetryAttempts[key] = attempt + 1
    metadataRetryTask?.cancel()
    metadataRetryTask = Task {
      do { try await Task.sleep(nanoseconds: delays[attempt] * 1_000_000_000) }
      catch { return }
      guard currentTrack.map(trackKey) == key else { return }
      metadataRetryTask = nil
      refreshExternalMetadata(manual: false, forceMissing: true)
    }
  }

  func scheduleLibraryArtworkLookup(_ tracks: [EchoNativeCoreTrack]) {
    let settings = persistent.settings
    guard libraryArtworkTask == nil,
      playerModel.activePage == "library" || playerModel.activePage == "search",
      settings.externalMetadataEnabled,
      settings.lrcApiExternalDataEnabled || settings.neteaseExternalDataEnabled
    else { return }

    let pending = tracks.map { resolvedTrack($0) }.filter { track in
      let key = trackKey(track)
      guard track.source != .streaming else { return false }
      guard track.artworkUrl?.isEmpty != false, !libraryArtworkLookupKeys.contains(key) else { return false }
      return true
    }
    guard !pending.isEmpty else { return }
    pending.forEach { libraryArtworkLookupKeys.insert(trackKey($0)) }
    libraryArtworkGeneration &+= 1
    let generation = libraryArtworkGeneration
    libraryArtworkTask = Task {
      var changed = false
      for requestedTrack in pending {
        guard !Task.isCancelled, libraryArtworkGeneration == generation else { return }
        guard let candidates = try? await EchoNativeMetadataService.candidates(
          for: requestedTrack,
          sources: EchoNativeMetadataService.Sources(
            lrcApi: settings.lrcApiExternalDataEnabled,
            lrclib: false,
            netease: settings.neteaseExternalDataEnabled
          ),
          includeNeteaseLyrics: false,
          neteaseClient: metadataNeteaseClient
        ), let artwork = EchoNativeMetadataService.automaticResult(from: candidates).artworkUrl,
          !artwork.isEmpty,
          libraryArtworkGeneration == generation
        else { continue }
        var updated = resolvedTrack(requestedTrack)
        guard updated.artworkUrl?.isEmpty != false else { continue }
        updated.externalArtworkUrl = artwork
        updated.artworkUrl = artwork
        replaceTrack(updated)
        if updated.source == .local { scheduleLocalMetadataEmbedding(updated) }
        if currentTrack.map(trackKey) == trackKey(updated) {
          currentTrack = updated
          updatePlayerTrack(updated)
          lastNowPlayingTrackKey = ""
          publishNowPlaying()
        }
        changed = true
      }
      guard libraryArtworkGeneration == generation else { return }
      libraryArtworkTask = nil
      if changed { persist() }
      if changed || playerModel.activePage == "library" || playerModel.activePage == "search" {
        renderPages()
      }
    }
  }

  private func resetLibraryArtworkLookup() {
    libraryArtworkGeneration &+= 1
    libraryArtworkTask?.cancel()
    libraryArtworkTask = nil
    libraryArtworkLookupKeys.removeAll()
  }

  private func scheduleLocalMetadataEmbedding(_ track: EchoNativeCoreTrack) {
    guard track.source == .local else { return }
    pendingLocalMetadataEmbeddings[trackKey(track)] = track
    guard localMetadataEmbeddingTask == nil else { return }
    localMetadataEmbeddingTask = Task {
      defer { localMetadataEmbeddingTask = nil }
      var changed = false
      while !Task.isCancelled, let entry = pendingLocalMetadataEmbeddings.first {
        pendingLocalMetadataEmbeddings.removeValue(forKey: entry.key)
        guard let embedded = try? await EchoNativeLocalLibrary.embedExternalMetadata(for: entry.value),
          !Task.isCancelled
        else { continue }
        replaceTrack(embedded)
        changed = true
        if currentTrack.map(trackKey) == entry.key {
          currentTrack = embedded
          updatePlayerTrack(embedded)
          updateDesktopLyrics()
        }
      }
      if changed {
        updateQueueModel()
        persist()
        renderPages()
      }
    }
  }

  private func externalMetadataPickerJSON(
    _ candidates: [EchoNativeMetadataService.Candidate],
    track: EchoNativeCoreTrack,
    generation: Int
  ) -> String {
    let payload: [String: Any] = [
      "artistLabel": localized("Artist", "艺术家"),
      "artworkLabel": localized("Artwork", "封面"),
      "cancelLabel": localized("Cancel", "取消"),
      "candidates": candidates.map { candidate in
        let available = [
          candidate.lyrics.isEmpty ? nil : localized("Lyrics", "歌词"),
          candidate.artist?.isEmpty == false ? localized("Artist", "艺术家") : nil,
          candidate.artworkUrl?.isEmpty == false ? localized("Artwork", "封面") : nil,
        ].compactMap { $0 }
        return [
          "albumArt": candidate.artworkUrl ?? "",
          "artist": candidate.artist ?? "",
          "availableLabel": available.joined(separator: "/"),
          "hasArtist": candidate.artist?.isEmpty == false,
          "hasArtwork": candidate.artworkUrl?.isEmpty == false,
          "hasLyrics": !candidate.lyrics.isEmpty,
          "id": candidate.id,
          "source": candidate.source,
          "sourceLabel": candidate.sourceLabel,
          "title": candidate.title,
        ] as [String: Any]
      },
      "doneLabel": localized("Use selection", "使用所选来源"),
      "id": "\(trackKey(track)):\(generation)",
      "ignoreLabel": localized("Do not use", "不使用"),
      "lyricsLabel": localized("Lyrics", "歌词"),
      "selectedLabel": localized("Selected", "已选择"),
      "subtitle": localized("Choose a source for each available field.", "分别选择歌词、艺术家和封面的来源。"),
      "title": track.title,
      "unavailableLabel": localized("Unavailable", "无此数据"),
      "useSourceLabel": localized("Use", "使用此来源"),
    ]
    return json(payload)
  }

  private func applyExternalMetadataSelection(_ payload: [String: Any]) {
    guard externalMetadataTrackKey == currentTrack.map(trackKey),
      let track = currentTrack,
      let selections = payload["selections"] as? [String: String]
    else { clearExternalMetadataPicker(); return }
    func candidate(_ field: String) -> EchoNativeMetadataService.Candidate? {
      guard let id = selections[field] else { return nil }
      return externalMetadataCandidates.first { $0.id == id }
    }
    applyExternalMetadata(EchoNativeMetadataService.Result(
      artist: candidate("artist")?.artist,
      artworkUrl: candidate("albumArt")?.artworkUrl,
      lyrics: candidate("lyrics")?.lyrics ?? ""
    ), to: track)
    clearExternalMetadataPicker()
  }

  private func applyExternalMetadata(
    _ result: EchoNativeMetadataService.Result,
    to track: EchoNativeCoreTrack,
    fillMissingOnly: Bool = false
  ) {
    guard currentTrack.map(trackKey) == trackKey(track) else { return }
    var updated = track
    if let artwork = result.artworkUrl, !artwork.isEmpty,
      !fillMissingOnly || updated.artworkUrl?.isEmpty != false {
      updated.externalArtworkUrl = artwork
      updated.artworkUrl = artwork
    }
    if let artist = result.artist, !artist.isEmpty, !fillMissingOnly || updated.artist.isEmpty {
      updated.externalArtist = artist
      updated.artist = artist
    }
    let shouldApplyLyrics = !result.lyrics.isEmpty && (!fillMissingOnly || !updated.hasLyrics && playerModel.lyricLines.isEmpty)
    if shouldApplyLyrics {
      if let lyricsUrl = EchoNativeMetadataService.cacheLyrics(result.lyrics, for: updated) {
        updated.externalLyrics = nil
        updated.externalLyricsUrl = lyricsUrl.absoluteString
      } else {
        updated.externalLyrics = result.lyrics
      }
      updated.hasLyrics = true
    }
    replaceTrack(updated)
    addRecent(updated)
    currentTrack = updated
    updatePlayerTrack(updated)
    if shouldApplyLyrics {
      lyricsGeneration &+= 1
      lyricsTask?.cancel()
      lyricsTask = nil
      let lines = EchoNativeMetadataService.parseLyrics(result.lyrics)
      playerModel.lyricLines = lines
      updateActiveLyricIndex()
    }
    if updated.source == .local { scheduleLocalMetadataEmbedding(updated) }
    updateQueueModel()
    updateDesktopLyrics()
    renderPages()
    lastNowPlayingTrackKey = ""
    publishNowPlaying()
  }

  private func replaceTrack(_ updated: EchoNativeCoreTrack) {
    let key = trackKey(updated)
    func replace(in values: inout [EchoNativeCoreTrack]) {
      if let index = values.firstIndex(where: { trackKey($0) == key }) { values[index] = updated }
    }
    replace(in: &localTracks)
    replace(in: &echoTracks)
    replace(in: &powerampTracks)
    replace(in: &neteaseTracks)
    replace(in: &neteaseSearchTracks)
    replace(in: &persistent.streamingRecommendedTracks)
    replace(in: &persistent.recentTracks)
    replace(in: &queue)
  }

  private func clearExternalMetadataPicker() {
    externalMetadataCandidates = []
    externalMetadataTrackKey = ""
    playerModel.updateExternalSourcePicker(payloadJSON: "")
  }

  private func ignoreExternalMetadataPicker() {
    if !externalMetadataTrackKey.isEmpty { ignoredExternalMetadataTrackKeys.insert(externalMetadataTrackKey) }
    clearExternalMetadataPicker()
  }

  private func updateLoadingState() {
    playerModel.playbackLoading = audioLoading
    playerModel.metadataLoading = audioLoading || externalMetadataLoading
  }

  private func track(id: String, source: EchoNativeTrackSource?) -> EchoNativeCoreTrack? {
    let values = source.map { libraryTracks(for: $0) } ?? allTracks()
    return values.first { $0.id == id }
      ?? persistent.streamingRecommendedTracks.first { track in
        track.id == id && (source.map { track.source == $0 } ?? true)
      }
      ?? queue.first { track in track.id == id && (source.map { track.source == $0 } ?? true) }
      ?? persistent.recentTracks.first { track in track.id == id && (source.map { track.source == $0 } ?? true) }
  }

  private func resolvedTrack(_ track: EchoNativeCoreTrack, includeLibraryFallback: Bool = true) -> EchoNativeCoreTrack {
    var value = track
    if includeLibraryFallback, let libraryTrack = self.track(id: track.id, source: track.source) {
      if value.album.isEmpty { value.album = libraryTrack.album }
      if value.albumArtist.isEmpty { value.albumArtist = libraryTrack.albumArtist }
      if value.artist.isEmpty { value.artist = libraryTrack.artist }
      if value.artworkUrl?.isEmpty != false { value.artworkUrl = libraryTrack.artworkUrl }
      if value.bitDepth == nil { value.bitDepth = libraryTrack.bitDepth }
      if value.bitrate == nil { value.bitrate = libraryTrack.bitrate }
      value.canPlayOnPhone = value.canPlayOnPhone || libraryTrack.canPlayOnPhone
      if value.codec?.isEmpty != false { value.codec = libraryTrack.codec }
      if value.discNo == nil { value.discNo = libraryTrack.discNo }
      if value.durationMs <= 0 { value.durationMs = libraryTrack.durationMs }
      if value.fileName?.isEmpty != false { value.fileName = libraryTrack.fileName }
      if value.fileSize <= 0 { value.fileSize = libraryTrack.fileSize }
      value.hasLyrics = value.hasLyrics || libraryTrack.hasLyrics
      if value.lyricsUrl?.isEmpty != false { value.lyricsUrl = libraryTrack.lyricsUrl }
      if value.localUrl?.isEmpty != false { value.localUrl = libraryTrack.localUrl }
      if value.sampleRate == nil { value.sampleRate = libraryTrack.sampleRate }
      if value.sourceLabel.isEmpty { value.sourceLabel = libraryTrack.sourceLabel }
      if value.title.isEmpty { value.title = libraryTrack.title }
      if value.trackNo == nil { value.trackNo = libraryTrack.trackNo }
    }
    if let cached = persistent.recentTracks.first(where: { trackKey($0) == trackKey(value) }) {
      if value.externalArtist?.isEmpty != false { value.externalArtist = cached.externalArtist }
      if value.externalArtworkUrl?.isEmpty != false { value.externalArtworkUrl = cached.externalArtworkUrl }
      if value.externalLyrics?.isEmpty != false { value.externalLyrics = cached.externalLyrics }
      if value.externalLyricsUrl?.isEmpty != false { value.externalLyricsUrl = cached.externalLyricsUrl }
      if value.artworkUrl?.isEmpty != false { value.artworkUrl = cached.artworkUrl }
    }
    if let artist = value.externalArtist, !artist.isEmpty { value.artist = artist }
    if let artwork = value.externalArtworkUrl, !artwork.isEmpty { value.artworkUrl = artwork }
    if value.externalLyricsUrl?.isEmpty != false, let lyrics = value.externalLyrics, !lyrics.isEmpty,
      let lyricsUrl = EchoNativeMetadataService.cacheLyrics(lyrics, for: value) {
      value.externalLyrics = nil
      value.externalLyricsUrl = lyricsUrl.absoluteString
    }
    if value.externalLyricsUrl?.isEmpty == false { value.hasLyrics = true }
    if value.artworkUrl?.isEmpty != false { value.artworkUrl = albumArtwork(for: value) }
    return value
  }

  private func resolvedTracks(_ tracks: [EchoNativeCoreTrack]) -> [EchoNativeCoreTrack] {
    tracks.map { resolvedTrack($0) }
  }

  func track(forKey key: String) -> EchoNativeCoreTrack? {
    guard let separator = key.firstIndex(of: ":"), let source = EchoNativeTrackSource(rawValue: String(key[..<separator])) else { return nil }
    return track(id: String(key[key.index(after: separator)...]), source: source)
  }

  func libraryTracks(for source: EchoNativeTrackSource) -> [EchoNativeCoreTrack] {
    switch source {
    case .echo: return echoTracks
    case .local: return localTracks
    case .remote: return powerampTracks
    case .streaming:
      if playerModel.activePage == "search" { return neteaseSearchTracks }
      if streamingLibraryMode == "history" { return persistent.recentTracks.filter { $0.source == .streaming } }
      return neteaseTracks
    }
  }

  private func allTracks() -> [EchoNativeCoreTrack] {
    localTracks + echoTracks + powerampTracks + libraryTracks(for: .streaming)
  }

  func trackKey(_ track: EchoNativeCoreTrack) -> String { "\(track.source.rawValue):\(track.id)" }

  private func albumArtwork(for track: EchoNativeCoreTrack) -> String? {
    guard !track.album.isEmpty else { return nil }
    let albums = track.source == .echo ? echoAlbums : track.source == .remote ? powerampAlbums : []
    let title = normalizedMetadataValue(track.album)
    return albums.first {
      normalizedMetadataValue($0.title) == title && $0.artworkUrl?.isEmpty == false
    }?.artworkUrl
  }

  private func normalizedMetadataValue(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func modeForTrack(_ track: EchoNativeCoreTrack) -> EchoNativeOutputMode {
    switch track.source {
    case .local: return .local
    case .echo: return outputMode == .phone ? .phone : .pc
    case .remote: return outputMode == .remoteStream ? .remoteStream : .remoteControl
    case .streaming: return .streaming
    }
  }


  private func updateSignalPath(for track: EchoNativeCoreTrack) {
    setIfChanged(playerModel, \.eqEnabled, playerModel.equalizer.gains.contains { abs($0) > 0.01 })
    setIfChanged(playerModel, \.loudnessEnabled, persistent.settings.loudnessEnabled)
    setIfChanged(playerModel, \.signalCodec, track.codec?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "")
    setIfChanged(playerModel, \.signalSampleRate, track.sampleRate.flatMap(sampleRateTag) ?? "")
    setIfChanged(playerModel, \.signalBitDepth, track.bitDepth.map { "\($0)Bit" } ?? "")
    if let bitrate = track.bitrate, bitrate > 0 {
      setIfChanged(playerModel, \.signalBitrate, "\(bitrate >= 1000 ? bitrate / 1000 : bitrate)kbps")
    } else {
      setIfChanged(playerModel, \.signalBitrate, "")
    }
    setIfChanged(playerModel, \.signalChannelCount, "")
    let sourceLabel = track.sourceLabel.isEmpty
      ? (track.source == .local
        ? localized("Local", "本地")
        : track.source == .echo
          ? "ECHO"
          : track.source == .remote
            ? "Poweramp"
            : localized("NetEase", "网易云"))
      : track.sourceLabel
    setIfChanged(playerModel, \.signalSourceLabel, sourceLabel)
    switch outputMode {
    case .pc:
      setIfChanged(playerModel, \.signalDeviceName, echoStatus?.device.name ?? "")
      setIfChanged(playerModel, \.signalRemoteOutput, echoStatus?.playback.outputMode ?? "")
    case .phone:
      setIfChanged(playerModel, \.signalDeviceName, echoStatus?.device.name ?? "")
      setIfChanged(playerModel, \.signalRemoteOutput, localized("Streaming", "串流"))
    case .remoteControl:
      setIfChanged(playerModel, \.signalDeviceName, powerampStatus?.device.name ?? "")
      setIfChanged(playerModel, \.signalRemoteOutput, powerampStatus?.playback.outputMode ?? "Poweramp")
    case .remoteStream:
      setIfChanged(playerModel, \.signalDeviceName, powerampStatus?.device.name ?? "")
      setIfChanged(playerModel, \.signalRemoteOutput, localized("Poweramp Stream", "Poweramp 串流"))
    case .streaming:
      setIfChanged(playerModel, \.signalDeviceName, neteaseProfile?.name ?? localized("NetEase", "网易云"))
      setIfChanged(playerModel, \.signalRemoteOutput, localized("NetEase", "网易云"))
    case .local:
      setIfChanged(playerModel, \.signalDeviceName, localized("This iPhone", "本机 iPhone"))
      setIfChanged(playerModel, \.signalRemoteOutput, "AVAudioEngine")
    }
    if usesLocalEngineOutput {
      refreshEngineSignalMetrics(audioEngine.playbackStatus())
    } else {
      let telemetry = outputMode == .pc ? echoStatus?.audio : powerampStatus?.audio
      refreshRemoteSignalMetrics(telemetry)
    }
    recordSignalRouteObservation(for: track)
    setIfChanged(playerModel, \.signalRouteEvents, signalRouteEvents)
  }

  private func clearSignalPath() {
    playerModel.signalBitDepth = ""
    playerModel.signalBitrate = ""
    playerModel.signalChannelCount = ""
    playerModel.signalCodec = ""
    playerModel.signalDacProfile = nil
    playerModel.signalDeviceChannelCount = ""
    playerModel.signalDeviceIOBufferMs = 0
    playerModel.signalDeviceLatencyMs = 0
    playerModel.signalDeviceName = ""
    playerModel.signalDevicePortType = ""
    playerModel.signalDeviceSampleRate = ""
    playerModel.signalDeviceUID = ""
    playerModel.signalEngineRunning = false
    playerModel.signalEngineSampleRate = ""
    playerModel.signalExclusive = nil
    playerModel.signalFileLoaded = false
    playerModel.signalMeter.clipping = false
    playerModel.signalMeter.lufsMomentary = nil
    playerModel.signalMeter.peakDb = -120
    playerModel.signalMeter.rmsDb = -120
    playerModel.signalOutputBitDepth = ""
    playerModel.signalOutputVolume = 0
    playerModel.signalRemoteOutput = ""
    playerModel.signalSampleRate = ""
    playerModel.signalSourceLabel = ""
    playerModel.signalTelemetrySource = "unverified"
    playerModel.signalRouteEvents = signalRouteEvents
  }

  private var usesLocalEngineOutput: Bool {
    switch outputMode {
    case .local, .phone, .remoteStream, .streaming: return true
    default: return false
    }
  }

  private func refreshEngineSignalMetrics(_ status: DspPlaybackStatus, includeLevels: Bool = false) {
    setIfChanged(playerModel, \.signalTelemetrySource, status.fileLoaded ? "observed" : "unverified")
    setIfChanged(playerModel, \.signalEngineRunning, status.engineRunning)
    setIfChanged(playerModel, \.signalFileLoaded, status.fileLoaded)
    setIfChanged(playerModel, \.signalExclusive, nil)
    let engineRate = status.fileLoaded && status.sampleRate > 0 ? sampleRateTag(status.sampleRate) ?? "" : ""
    setIfChanged(playerModel, \.signalEngineSampleRate, engineRate)
    let deviceRate = status.fileLoaded && status.deviceSampleRate > 0 ? sampleRateTag(status.deviceSampleRate) ?? "" : ""
    setIfChanged(playerModel, \.signalDeviceSampleRate, deviceRate)
    setIfChanged(playerModel, \.signalDeviceChannelCount, status.fileLoaded && status.deviceChannelCount > 0 ? "\(status.deviceChannelCount)ch" : "")
    setIfChanged(playerModel, \.signalDeviceName, status.fileLoaded && !status.deviceName.isEmpty ? status.deviceName : playerModel.signalDeviceName)
    setIfChanged(playerModel, \.signalDevicePortType, status.fileLoaded ? status.devicePortType : "")
    setIfChanged(playerModel, \.signalDeviceUID, status.fileLoaded ? status.deviceUID : "")
    setIfChanged(playerModel, \.signalDeviceIOBufferMs, status.fileLoaded ? status.ioBufferDurationMs : 0)
    setIfChanged(playerModel, \.signalDeviceLatencyMs, status.fileLoaded ? status.outputLatencyMs : 0)
    setIfChanged(playerModel, \.signalOutputBitDepth, "")
    setIfChanged(playerModel, \.signalOutputVolume, status.fileLoaded ? status.outputVolume : 0)
    if includeLevels {
      setIfChanged(playerModel.signalMeter, \.peakDb, status.peakDb)
      setIfChanged(playerModel.signalMeter, \.rmsDb, status.rmsDb)
      setIfChanged(playerModel.signalMeter, \.clipping, status.peakDb >= -0.1)
      setIfChanged(playerModel.signalMeter, \.lufsMomentary, nil)
    }
    if status.channelCount > 0 {
      setIfChanged(playerModel, \.signalChannelCount, "\(status.channelCount)ch")
    } else {
      setIfChanged(playerModel, \.signalChannelCount, "")
    }
    recordDacObservation(status)
  }

  private func refreshRemoteSignalMetrics(_ telemetry: EchoNativePlaybackStatus.AudioTelemetry?) {
    setIfChanged(playerModel, \.signalDacProfile, nil)
    setIfChanged(playerModel, \.signalDeviceChannelCount, telemetry?.channels.map { "\($0)ch" } ?? "")
    setIfChanged(playerModel, \.signalDeviceIOBufferMs, 0)
    setIfChanged(playerModel, \.signalDeviceLatencyMs, telemetry?.outputLatencyMs ?? 0)
    if let name = telemetry?.outputDeviceName, !name.isEmpty { setIfChanged(playerModel, \.signalDeviceName, name) }
    setIfChanged(playerModel, \.signalDevicePortType, telemetry?.outputDeviceType ?? "")
    setIfChanged(playerModel, \.signalDeviceSampleRate, telemetry?.sampleRate.flatMap(sampleRateTag) ?? "")
    setIfChanged(playerModel, \.signalDeviceUID, telemetry?.outputDeviceId ?? "")
    setIfChanged(playerModel, \.signalEngineRunning, false)
    setIfChanged(playerModel, \.signalEngineSampleRate, "")
    setIfChanged(playerModel, \.signalExclusive, telemetry?.exclusive)
    setIfChanged(playerModel, \.signalFileLoaded, false)
    setIfChanged(playerModel, \.signalOutputBitDepth, telemetry?.bitDepth.map { "\($0)Bit" } ?? "")
    setIfChanged(playerModel, \.signalOutputVolume, 0)
    setIfChanged(playerModel, \.signalTelemetrySource, telemetry == nil ? "unverified" : "reported")
    if signalPathVisible || persistent.settings.desktopLyricsEnabled && persistent.settings.desktopLyricsVisualizer != "off" {
      setIfChanged(playerModel.signalMeter, \.clipping, telemetry?.clipping ?? false)
      setIfChanged(playerModel.signalMeter, \.lufsMomentary, telemetry?.lufsMomentary)
      setIfChanged(playerModel.signalMeter, \.peakDb, telemetry?.peakDb ?? -120)
      setIfChanged(playerModel.signalMeter, \.rmsDb, telemetry?.rmsDb ?? -120)
    }
  }

  private func recordDacObservation(_ status: DspPlaybackStatus) {
    guard status.fileLoaded else { return }
    let id = status.deviceUID.isEmpty ? "\(status.devicePortType)|\(status.deviceName)" : status.deviceUID
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let sampleRate = status.deviceSampleRate.rounded()
    let observationKey = "\(id)|\(Int(sampleRate))|\(status.deviceChannelCount)"
    if let profile = dacProfiles[id] { setIfChanged(playerModel, \.signalDacProfile, profile) }
    guard observationKey != lastDacObservationKey else { return }
    lastDacObservationKey = observationKey

    let now = Date()
    var profile = dacProfiles[id] ?? EchoNativeDacObservation(
      id: id,
      channelCounts: [],
      firstSeenAt: now,
      lastSeenAt: now,
      name: status.deviceName.isEmpty ? localized("System output", "系统输出") : status.deviceName,
      observationCount: 0,
      portType: status.devicePortType,
      sampleRates: []
    )
    if sampleRate > 0, !profile.sampleRates.contains(sampleRate) { profile.sampleRates.append(sampleRate) }
    if status.deviceChannelCount > 0, !profile.channelCounts.contains(status.deviceChannelCount) {
      profile.channelCounts.append(status.deviceChannelCount)
    }
    profile.sampleRates.sort()
    profile.channelCounts.sort()
    profile.lastSeenAt = now
    profile.name = status.deviceName.isEmpty ? profile.name : status.deviceName
    profile.portType = status.devicePortType.isEmpty ? profile.portType : status.devicePortType
    profile.observationCount += 1
    dacProfiles[id] = profile
    setIfChanged(playerModel, \.signalDacProfile, profile)
    EchoNativeDacObservation.save(dacProfiles)
  }

  private func recordSignalRouteObservation(for track: EchoNativeCoreTrack) {
    let engineStatus = audioEngine.playbackStatus()
    guard !usesLocalEngineOutput || engineStatus.fileLoaded else { return }
    let routeLabel = signalRouteLabel()
    let deviceName = playerModel.signalDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceRate = track.sampleRate.map { Int($0.rounded()) }
    let deviceRateValue = usesLocalEngineOutput ? engineStatus.deviceSampleRate : 0
    let outputRate = deviceRateValue > 0 ? Int(deviceRateValue.rounded()) : sourceRate
    let routeKey = [
      outputMode.rawValue,
      deviceName.lowercased(),
      playerModel.signalRemoteOutput.lowercased(),
      sourceRate.map(String.init) ?? "",
      outputRate.map(String.init) ?? "",
      trackKey(track),
    ].joined(separator: "|")
    guard routeKey != lastSignalRouteKey else { return }

    let previous = lastSignalRouteKey
    lastSignalRouteKey = routeKey
    let rateMismatch = sourceRate != nil && outputRate != nil && sourceRate != outputRate
    let tone: String
    let title: String
    let detail: String
    if previous.isEmpty {
      tone = "good"
      title = localized("Route engaged", "路径接入")
      detail = routeLabel
    } else if rateMismatch {
      tone = "process"
      title = localized("Rate conversion", "采样率转换")
      let sourceText = sourceRate.map { "\($0) Hz" } ?? localized("unknown", "未知")
      let outputText = outputRate.map { "\($0) Hz" } ?? localized("unknown", "未知")
      detail = "\(sourceText) → \(outputText) · \(routeLabel)"
    } else {
      tone = playerModel.eqEnabled || playerModel.loudnessEnabled ? "process" : "good"
      title = localized("Route changed", "路径变更")
      detail = routeLabel
    }

    let event = EchoNativeSignalRouteEvent(
      id: UUID().uuidString,
      tone: tone,
      title: title,
      detail: detail,
      trackTitle: track.title,
      at: Date()
    )
    signalRouteEvents.insert(event, at: 0)
    if signalRouteEvents.count > 20 {
      signalRouteEvents = Array(signalRouteEvents.prefix(20))
    }
    EchoNativeSignalRouteEvent.save(signalRouteEvents)
  }

  private func signalRouteLabel() -> String {
    let mode: String
    switch outputMode {
    case .local: mode = localized("Local", "本机")
    case .pc: mode = localized("ECHO control", "ECHO 控制")
    case .phone: mode = localized("ECHO stream", "ECHO 串流")
    case .remoteControl: mode = localized("Poweramp control", "Poweramp 控制")
    case .remoteStream: mode = localized("Poweramp stream", "Poweramp 串流")
    case .streaming: mode = localized("NetEase stream", "网易云串流")
    }
    var parts = [mode]
    let remote = playerModel.signalRemoteOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    let device = playerModel.signalDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !remote.isEmpty { parts.append(remote) }
    if !device.isEmpty { parts.append(device) }
    if playerModel.eqEnabled { parts.append("EQ") }
    if playerModel.loudnessEnabled { parts.append(localized("Loudness", "响度")) }
    return parts.joined(separator: " / ")
  }

  func tags(
    for track: EchoNativeCoreTrack,
    includeDuration: Bool = false,
    includeOutput: Bool = true
  ) -> [String] {
    let visible = persistent.settings.audioTagVisibility
    var values: [String] = []
    if includeOutput, visible["output"] != false, let output = playbackOutputTag(), !output.isEmpty {
      values.append(output)
    }
    if visible["codec"] != false, let codec = track.codec, !codec.isEmpty { values.append(codec.uppercased()) }
    let sampleRate = visible["sampleRate"] != false ? track.sampleRate.flatMap(sampleRateTag) : nil
    let bitDepth = visible["bitDepth"] != false ? track.bitDepth.map { "\($0)Bit" } : nil
    if let sampleRate, let bitDepth { values.append("\(sampleRate)/\(bitDepth)") }
    else if let sampleRate { values.append(sampleRate) }
    else if let bitDepth { values.append(bitDepth) }
    if visible["bitrate"] != false, let bitrate = track.bitrate, bitrate > 0 {
      values.append("\(bitrate >= 1000 ? bitrate / 1000 : bitrate)kbps")
    }
    if visible["source"] != false {
      let fallback = track.source == .local ? "Local" : track.source == .echo ? "ECHO" : track.source == .remote ? "Poweramp" : localized("NetEase", "网易云")
      values.append(track.sourceLabel.isEmpty ? fallback : track.sourceLabel)
    }
    if visible["streamable"] != false {
      values.append(track.canPlayOnPhone ? localized("Streamable", "可串流") : localized("Control only", "仅控制"))
    }
    if includeDuration, visible["duration"] != false, track.durationMs > 0 {
      let seconds = Int(track.durationMs / 1000)
      values.append(String(format: "%d:%02d", seconds / 60, seconds % 60))
    }
    var seen = Set<String>()
    return values.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
  }

  private func sampleRateTag(_ rate: Double) -> String? {
    guard rate > 0 else { return nil }
    let khz = rate >= 1000 ? rate / 1000 : rate
    return String(format: khz.rounded() == khz ? "%.0fkHz" : "%.1fkHz", khz)
  }

  private func playbackOutputTag() -> String? {
    let raw: String
    switch outputMode {
    case .local: raw = "Local"
    case .pc: raw = echoStatus?.playback.outputMode ?? ""
    case .phone: raw = localized("Streaming", "串流")
    case .remoteControl: raw = powerampStatus?.playback.outputMode ?? "Poweramp"
    case .remoteStream: raw = localized("Poweramp Stream", "Poweramp 串流")
    case .streaming: raw = localized("NetEase", "网易云")
    }
    let normalized = raw.lowercased()
    if normalized.contains("asio") { return "ASIO" }
    if normalized.contains("wasapi") || normalized.contains("shared") || normalized.contains("exclusive") { return "WASAPI" }
    if normalized.contains("system") { return "System" }
    return raw
  }

  func albumOrdered(_ tracks: [EchoNativeCoreTrack]) -> [EchoNativeCoreTrack] {
    tracks.sorted {
      let leftDisc = ($0.discNo ?? 1) > 0 ? ($0.discNo ?? 1) : 1
      let rightDisc = ($1.discNo ?? 1) > 0 ? ($1.discNo ?? 1) : 1
      if leftDisc != rightDisc { return leftDisc < rightDisc }
      let leftTrack = ($0.trackNo ?? 0) > 0 ? ($0.trackNo ?? 0) : Int.max
      let rightTrack = ($1.trackNo ?? 0) > 0 ? ($1.trackNo ?? 0) : Int.max
      if leftTrack != rightTrack { return leftTrack < rightTrack }
      let titleOrder = $0.title.localizedStandardCompare($1.title)
      if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
      return $0.id < $1.id
    }
  }

  private func normalizedGains(_ values: [Double]) -> [Double] {
    (0..<10).map { index in values.indices.contains(index) ? min(12, max(-12, values[index])) : 0 }
  }

  private func resetLibraryPosition() {
    searchTask?.cancel()
    echoAlbumGeneration &+= 1
    echoAlbumBusy = false
    libraryPage = 0
    libraryExpanded = false
    selectedCollectionId = ""
    selectedPlaylistId = ""
    selectedStreamingPlaylistId = ""
  }

  private func updateActiveLyricIndex() {
    let position = playerModel.positionMs
    guard let index = playerModel.lyricLines.lastIndex(where: { $0.milliseconds >= 0 && $0.milliseconds <= position }) else {
      if playerModel.activeLyricIndex != 0 { playerModel.activeLyricIndex = 0 }
      return
    }
    if playerModel.activeLyricIndex != index { playerModel.activeLyricIndex = index }
  }

  private func configureDesktopLyrics() {
    let settings = persistent.settings
    desktopLyricsController.configure(.init(
      animation: settings.desktopLyricsAnimation,
      background: settings.desktopLyricsBackground,
      enabled: settings.desktopLyricsEnabled,
      fontName: settings.customFontName,
      fontSize: settings.desktopLyricsFontSize,
      heightScale: settings.desktopLyricsHeightScale,
      language: settings.language,
      onlyWhilePlaying: settings.desktopLyricsOnlyWhilePlaying,
      position: settings.desktopLyricsPosition,
      progressBarEnabled: settings.desktopLyricsProgressBarEnabled,
      progressColorHex: settings.desktopLyricsProgressColorHex,
      progressRainbow: settings.desktopLyricsProgressRainbow,
      rainbowGradient: settings.desktopLyricsRainbowGradient,
      showMetadata: settings.desktopLyricsShowMetadata,
      themeColorHex: settings.themeColorHex,
      timedReveal: settings.desktopLyricsTimedReveal,
      transitionAnimation: settings.desktopLyricsTransitionAnimation,
      visualizer: settings.desktopLyricsVisualizer,
      widthScale: settings.desktopLyricsWidthScale
    ), importedBackgroundImage: desktopLyricsBackgroundImage)
    updateDesktopLyrics()
  }

  private func updateDesktopLyrics() {
    desktopLyricsController.update(
      trackKey: currentTrack.map(trackKey) ?? "",
      title: playerModel.title,
      artist: playerModel.artist,
      artworkURL: playerModel.artworkUrl,
      lines: playerModel.lyricLines,
      activeIndex: playerModel.activeLyricIndex,
      isPlaying: playerModel.isPlaying,
      peakDb: playerModel.signalMeter.peakDb,
      rmsDb: playerModel.signalMeter.rmsDb,
      durationMs: playerModel.durationMs,
      positionMs: playerModel.positionMs
    )
  }

  private var desktopLyricsBackgroundURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("desktop-lyrics-background.jpg")
  }

  private var appearanceBackgroundURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("appearance-background.jpg")
  }

  private var appearanceFontURL: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("appearance-font")
  }

  private func applyAppearanceSettings() {
    let settings = persistent.settings
    playerModel.appearanceBackground = settings.appearanceBackground
    playerModel.appearanceImageUrl = appearanceBackgroundURL.flatMap {
      FileManager.default.fileExists(atPath: $0.path) ? $0.absoluteString : nil
    } ?? ""
    playerModel.customFontName = settings.customFontName
    playerModel.fontScale = settings.fontScale
    playerModel.hapticsEnabled = settings.hapticsEnabled
    playerModel.motionStyle = settings.motionStyle
    playerModel.themeColorHex = settings.themeColorHex
    UserDefaults.standard.set(settings.customFontName, forKey: "echo.appearance.fontName")
    UserDefaults.standard.set(settings.fontScale, forKey: "echo.appearance.fontScale")
  }

  private func loadDesktopLyricsBackgroundImage() -> UIImage? {
    desktopLyricsBackgroundURL.flatMap { try? Data(contentsOf: $0) }.flatMap(UIImage.init(data:))
  }

  private func importDesktopLyricsBackground(_ data: Data?) {
    guard let data, let image = UIImage(data: data), let url = desktopLyricsBackgroundURL else {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = localized("The selected image could not be read.", "无法读取所选图片。")
      return
    }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      desktopLyricsBackgroundImage = image
      persistent.settings.desktopLyricsBackground = "custom"
      configureDesktopLyrics()
      persist()
      renderPages()
    } catch {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = error.localizedDescription
    }
  }

  private func importAppearanceBackground(_ data: Data?) {
    guard let data, let image = UIImage(data: data), image.size.width > 0,
      let url = appearanceBackgroundURL else {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = localized("The selected image could not be read.", "无法读取所选图片。")
      return
    }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      persistent.settings.appearanceBackground = "custom"
      applyAppearanceSettings()
      persist()
      renderPages()
    } catch {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = error.localizedDescription
    }
  }

  private func registerStoredAppearanceFont() {
    guard let url = appearanceFontURL, let data = try? Data(contentsOf: url) else { return }
    _ = registerAppearanceFont(data)
  }

  private func registerAppearanceFont(_ data: Data) -> String? {
    guard let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
      let name = font.postScriptName as String? else { return nil }
    var error: Unmanaged<CFError>?
    _ = CTFontManagerRegisterGraphicsFont(font, &error)
    return name
  }

  private func importAppearanceFont(_ data: Data?) {
    guard let data, data.count <= 20 * 1_024 * 1_024,
      let name = registerAppearanceFont(data), let url = appearanceFontURL else {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = localized("Choose a valid TTF or OTF font file.", "请选择有效的 TTF 或 OTF 字体文件。")
      return
    }
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      persistent.settings.customFontName = name
      applyAppearanceSettings()
      configureDesktopLyrics()
      persist()
      renderPages()
    } catch {
      playerModel.alertTitle = localized("Import failed", "导入失败")
      playerModel.alertMessage = error.localizedDescription
    }
  }

  private func persist() { EchoNativePersistence.save(persistent) }

  private func number(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? NSNumber { return value.doubleValue }
    return nil
  }

  private func hasNeteaseAccountCookie(_ cookie: String) -> Bool {
    cookie.split(separator: ";").contains { part in
      let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
      return value.hasPrefix("MUSIC_U=") && value.count > "MUSIC_U=".count
    }
  }

  func localized(_ english: String, _ chinese: String) -> String {
    persistent.settings.language == "en" ? english : chinese
  }

  func json(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return "{}" }
    return String(data: data, encoding: .utf8) ?? "{}"
  }

  private func showError(_ error: Error) {
    playerModel.alertTitle = localized("Playback error", "播放异常")
    playerModel.alertMessage = errorMessage(error)
  }

  private func showConnectionError(_ message: String) {
    playerModel.alertTitle = localized("Connection error", "连接异常")
    playerModel.alertMessage = message
  }

  private func errorMessage(_ error: Error) -> String {
    guard persistent.settings.language == "en", let networkError = error as? EchoNativeNetworkError else {
      return error.localizedDescription
    }
    switch networkError {
    case .invalidConnection: return "The address, port, or pairing token is invalid."
    case .invalidResponse: return "The remote service returned an unsupported response."
    case let .server(code, message): return "\(code) \(message)"
    }
  }
}
