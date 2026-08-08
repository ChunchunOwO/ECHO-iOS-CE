import Foundation

extension EchoNativeAppStore {
  func renderPages() {
    let connectionStatus = activeConnectionStatus()
    playerModel.connectionLabel = connectionStatus.label
    playerModel.connectionOnline = connectionStatus.online
    playerModel.artworkBackgroundEnabled = persistent.settings.artworkBackgroundEnabled
    playerModel.darkModeEnabled = persistent.settings.darkModeEnabled
    playerModel.desktopLyricsEnabled = persistent.settings.desktopLyricsEnabled
    playerModel.followSystemAppearance = persistent.settings.followSystemAppearance
    playerModel.language = persistent.settings.language
    playerModel.playbackMode = persistent.settings.playbackMode
    playerModel.showArtworkGlow = persistent.settings.showArtworkGlow
    playerModel.showPlayerOutputInMenu = persistent.settings.showPlayerOutputInMenu
    let page = playerModel.activePage
    let payload: [String: Any] = [
      "connection": page == "connect" ? connectionPayload() : NSNull(),
      "language": persistent.settings.language,
      "library": page == "library" || page == "search" ? libraryPayload(searchOnly: page == "search") : NSNull(),
      "page": page,
      "settings": page == "settings" ? settingsPayload() : NSNull(),
      "status": ["broken": connectionStatus.broken, "label": connectionStatus.label, "online": connectionStatus.online],
      "title": pageTitle(page),
    ]
    pagesModel.update(payloadJSON: json(payload))
  }

  private func activeConnectionStatus() -> (broken: Bool, label: String, online: Bool) {
    if outputMode == .remoteControl || outputMode == .remoteStream {
      if powerampOnline { return (false, localized("Poweramp connected", "Poweramp 已连接"), true) }
      return (!powerampError.isEmpty, localized("Remote disconnected", "远程未连接"), false)
    }
    if echoOnline { return (false, localized("ECHO connected", "ECHO已连接"), true) }
    return (!echoError.isEmpty, localized("ECHO disconnected", "ECHO未连接"), false)
  }

  private func pageTitle(_ page: String) -> String {
    switch page {
    case "control": return localized("Playback", "播放")
    case "library": return localized("Library", "曲库")
    case "search": return localized("Search", "搜索")
    case "connect": return localized("Connect", "连接")
    default: return localized("Settings", "设置")
    }
  }

  private func connectionPayload() -> [String: Any] {
    let echo = persistent.echoConnection
    let remote = persistent.powerampConnection
    return [
      "busy": connectMode == "remote" ? powerampBusy : connectMode == "streaming" ? streamingBusy : echoBusy,
      "enabled": echo.enabled,
      "host": echo.host,
      "labels": [
        "connect": localized("Connect", "连接"),
        "connectionDescription": localized("Connect this iPhone with ECHO.", "连接这台 iPhone 与 ECHO。"),
        "echoConnection": "ECHO",
        "enabled": localized("ECHO connection", "ECHO 连接"),
        "host": localized("Address", "地址"),
        "hostPlaceholder": "192.168.1.12",
        "library": localized("Library", "曲库"),
        "manual": localized("Manual connection", "手动连接"),
        "pairLink": localized("Pairing", "配对连接"),
        "scanPairing": localized("Scan QR Code", "扫描二维码"),
        "port": localized("Port", "端口"),
        "save": localized("Save", "保存"),
        "streamable": localized("Streamable", "可串流"),
        "streamingComingSoon": "",
        "streamingReserved": "",
        "test": localized("Test", "测试"),
        "token": "Token",
      ],
      "libraryCount": String(echoTracks.count),
      "mode": connectMode,
      "modeOptions": connectionModeOptions(),
      "pairingText": pairingText,
      "port": String(echo.port),
      "powerampRemote": [
        "enabled": remote.enabled,
        "host": remote.host,
        "name": remote.name,
        "port": String(remote.port),
        "token": remote.token,
      ],
      "streamableCount": String(echoTracks.filter(\.canPlayOnPhone).count),
      "streaming": [
        "accessMode": persistent.settings.neteaseAccessMode,
        "accessModeOptions": [
          option("direct", localized("Direct Web API", "直连 Web 接口")),
          option("selfHosted", localized("Self-hosted API", "自托管接口")),
        ],
        "apiBaseUrl": persistent.settings.neteaseApiBaseUrl,
        "busy": streamingBusy,
        "loggedIn": neteaseProfile != nil,
        "playlistCount": neteasePlaylists.count,
        "profileAvatarUrl": neteaseProfile?.avatarUrl ?? "",
        "profileName": neteaseProfile?.name ?? "",
        "qrUrl": streamingQrUrl,
        "status": streamingStatus,
      ],
      "token": echo.token,
    ]
  }

  private func connectionModeOptions() -> [[String: Any]] {
    var values = [option("echo", "ECHO"), option("streaming", localized("Media", "流媒体"))]
    if persistent.settings.showPowerampRemote { values.append(option("remote", localized("Remote", "远程"))) }
    return values
  }

  private func libraryPayload(searchOnly: Bool) -> [String: Any] {
    let source = searchOnly ? "all" : normalizedLibrarySource()
    let sourceTracks = tracksForLibrarySource(source)
    let selectedTracks = selectedCollectionId.isEmpty ? nil : collectionTrackKeys[selectedCollectionId]?.compactMap(track(forKey:))
    let showingCollections = selectedTracks == nil
      && source != "all"
      && source != "streaming"
      && (libraryView == "albums" || libraryView == "artists")
    let collections = showingCollections ? collectionsForCurrentView(sourceTracks, source: source) : []
    if selectedTracks == nil && !showingCollections { collectionTrackKeys = [:] }
    let shouldShowTracks = selectedTracks != nil || libraryView == "songs" || libraryView == "favorites" || libraryView == "recent" || libraryView == "formats" || source == "all" || source == "streaming"
    let fullTracks: [EchoNativeCoreTrack]
    if let selectedTracks {
      fullTracks = libraryView == "recent" || (source == "streaming" && streamingLibraryMode == "history")
        ? selectedTracks
        : sortLibraryTracks(selectedTracks)
    } else if shouldShowTracks {
      fullTracks = derivedLibraryTracks(sourceTracks, source: source)
    } else {
      fullTracks = []
    }
    let allStreamingPlaylists = sortedStreamingPlaylists()
    let showingStreamingPlaylists = source == "streaming"
      && streamingLibraryMode == "playlists"
      && selectedStreamingPlaylistId.isEmpty
    let pageSize = 20
    let totalCount = showingStreamingPlaylists
      ? allStreamingPlaylists.count
      : collections.isEmpty ? fullTracks.count : collections.count
    let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
    libraryPage = min(max(0, libraryPage), totalPages - 1)
    let rangeStart = min(totalCount, libraryExpanded ? libraryPage * pageSize : 0)
    let rangeEnd = min(totalCount, rangeStart + pageSize)
    let pagedTracks = !showingStreamingPlaylists && collections.isEmpty ? Array(fullTracks[rangeStart..<rangeEnd]) : []
    let pagedCollections = showingStreamingPlaylists || collections.isEmpty ? [] : Array(collections[rangeStart..<rangeEnd])
    let pagedStreamingPlaylists = showingStreamingPlaylists
      ? Array(allStreamingPlaylists[rangeStart..<rangeEnd])
      : []
    let artworkLookupTracks = collections.isEmpty
      ? pagedTracks
      : pagedCollections.compactMap { collection in
        guard let id = collection["id"] as? String else { return nil }
        return collectionTrackKeys[id]?.lazy.compactMap(track(forKey:)).first
      }
    scheduleLibraryArtworkLookup(artworkLookupTracks)
    let activeSort = activeLibrarySort()
    let indexTitles = showingStreamingPlaylists
      ? allStreamingPlaylists.map(\.name)
      : collections.isEmpty
        ? fullTracks.map { activeSort == "artist" ? $0.artist : $0.title }
        : collections.map { $0["indexTitle"] as? String ?? $0["title"] as? String ?? "" }
    let paginationScope = "\(source):\(libraryView):\(libraryFilter):\(selectedCollectionId):\(streamingLibraryMode):\(selectedStreamingPlaylistId):\(activeSort):\(libraryQuery)"
    let indexTitlesPayload: Any
    if paginationScope != libraryIndexPayloadScope || indexTitles != libraryIndexPayloadTitles {
      libraryIndexPayloadScope = paginationScope
      libraryIndexPayloadTitles = indexTitles
      indexTitlesPayload = indexTitles
    } else {
      indexTitlesPayload = NSNull()
    }
    let selectedPlaylist = persistent.playlists.first { $0.id == selectedPlaylistId }
    return [
      "busy": source == "all"
        ? localBusy || echoBusy || echoAlbumBusy || powerampBusy || streamingBusy
        : source == "local" ? localBusy : source == "remote" ? powerampBusy : source == "streaming" ? streamingBusy : echoBusy || echoAlbumBusy,
      "canPlayLocal": !localTracks.isEmpty,
      "confirmDelete": persistent.settings.confirmBeforeDeletingLocalTracks,
      "collections": pagedCollections,
      "filter": libraryFilter,
      "filterOptions": filterOptions(source: source, tracks: sourceTracks),
      "indexTitles": indexTitlesPayload,
      "labels": libraryLabels(source: source),
      "pagination": [
        "expanded": libraryExpanded,
        "page": libraryPage + 1,
        "pageSize": pageSize,
        "totalCount": totalCount,
        "totalPages": totalPages,
      ],
      "paginationScope": paginationScope,
      "playlists": sortedPlaylists().map { playlistPayload($0, includeTracks: false) },
      "query": libraryQuery,
      "selectedPlaylist": selectedPlaylist.map { playlistPayload($0, includeTracks: true) as Any } ?? NSNull(),
      "source": source,
      "sourceOptions": librarySourceOptions(),
      "streaming": streamingLibraryPayload(playlists: pagedStreamingPlaylists),
      "totalLabel": localized("\(totalCount) items", "共 \(totalCount) 项"),
      "tracks": pagedTracks.map(libraryTrackPayload),
      "view": libraryView,
      "viewOptions": libraryViewOptions(source: source),
    ]
  }

  private func normalizedLibrarySource() -> String {
    if librarySource == "echo", !persistent.echoConnection.enabled { return "local" }
    if librarySource == "remote", !persistent.powerampConnection.enabled { return "local" }
    return librarySource
  }

  private func tracksForLibrarySource(_ source: String) -> [EchoNativeCoreTrack] {
    switch source {
    case "echo": return echoTracks
    case "local": return localTracks
    case "remote": return powerampTracks
    case "streaming": return libraryTracks(for: .streaming)
    default: return localTracks + echoTracks + powerampTracks + libraryTracks(for: .streaming)
    }
  }

  private func filteredTracks(_ tracks: [EchoNativeCoreTrack], source: String) -> [EchoNativeCoreTrack] {
    let query = normalized(libraryQuery)
    var values = tracks
    if libraryView == "recent" {
      let snapshots = persistent.recentTracks.filter { source == "all" || $0.source.rawValue == source }
      values = deduplicated(values + snapshots)
    }
    if !query.isEmpty {
      values = values.filter { track in
        [track.title, track.artist, track.album, track.albumArtist, track.codec ?? ""]
          .contains { normalized($0).contains(query) }
      }
    }
    if source == "echo" || source == "remote" {
      if libraryFilter == "streamable" { values = values.filter(\.canPlayOnPhone) }
      if libraryFilter == "local" { values = values.filter { normalized($0.sourceLabel).contains("local") } }
    }
    if libraryView == "favorites" { values = values.filter { persistent.favoriteTrackKeys.contains(trackKey($0)) } }
    if libraryView == "recent" {
      var order: [String: Int] = [:]
      for (index, key) in persistent.recentTrackKeys.enumerated() where order[key] == nil {
        order[key] = index
      }
      values = values.filter { order[trackKey($0)] != nil }.sorted { order[trackKey($0), default: .max] < order[trackKey($1), default: .max] }
    }
    if libraryView == "formats" { values = values.sorted { ($0.codec ?? "").localizedStandardCompare($1.codec ?? "") == .orderedAscending } }
    return deduplicated(values)
  }

  private func sortLibraryTracks(_ tracks: [EchoNativeCoreTrack]) -> [EchoNativeCoreTrack] {
    func sortedByText(
      _ primary: KeyPath<EchoNativeCoreTrack, String>,
      tie secondary: KeyPath<EchoNativeCoreTrack, String>
    ) -> [EchoNativeCoreTrack] {
      var keys: [String: (String, String)] = [:]
      for track in tracks {
        keys[trackKey(track)] = (
          libraryTextSortKey(track[keyPath: primary]),
          libraryTextSortKey(track[keyPath: secondary])
        )
      }
      return tracks.sorted {
        let left = keys[trackKey($0)] ?? ("", "")
        let right = keys[trackKey($1)] ?? ("", "")
        let order = left.0.localizedStandardCompare(right.0)
        return order == .orderedAscending
          || (order == .orderedSame && left.1.localizedStandardCompare(right.1) == .orderedAscending)
      }
    }
    switch activeLibrarySort() {
    case "default": return tracks
    case "track": return albumOrdered(tracks)
    case "title": return sortedByText(\.title, tie: \.artist)
    case "artist": return sortedByText(\.artist, tie: \.title)
    case "duration": return tracks.sorted {
      $0.durationMs == $1.durationMs
        ? compareLibraryText($0.title, $1.title)
        : $0.durationMs < $1.durationMs
    }
    default: return tracks
    }
  }

  private func activeLibrarySort() -> String {
    !selectedCollectionId.isEmpty && !selectedCollectionId.contains("-artist:")
      ? albumTrackSort
      : librarySort
  }

  private func compareLibraryText(_ left: String, _ right: String, tie leftTie: String = "", _ rightTie: String = "") -> Bool {
    let leftKey = libraryTextSortKey(left)
    let rightKey = libraryTextSortKey(right)
    let order = leftKey.localizedStandardCompare(rightKey)
    if order != .orderedSame { return order == .orderedAscending }
    return leftTie.localizedStandardCompare(rightTie) == .orderedAscending
  }

  private func libraryTextSortKey(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if let cached = libraryTextSortKeyCache.object(forKey: normalized as NSString) { return cached as String }
    let key = NSMutableString(string: normalized)
    CFStringTransform(key, nil, kCFStringTransformToLatin, false)
    CFStringTransform(key, nil, kCFStringTransformStripCombiningMarks, false)
    let raw = key as String
    let first = raw.uppercased().unicodeScalars.first
    let isLetter = first.map { (65...90).contains(Int($0.value)) } ?? false
    let result = (isLetter ? "0" : "1") + raw
    libraryTextSortKeyCache.setObject(result as NSString, forKey: normalized as NSString)
    return result
  }

  private func derivedLibraryTracks(_ tracks: [EchoNativeCoreTrack], source: String) -> [EchoNativeCoreTrack] {
    let cacheable = selectedCollectionId.isEmpty
      && (source == "local" || source == "echo" || source == "remote")
      && libraryView != "favorites"
      && libraryView != "recent"
    let cacheKey = libraryCacheKey(source: source)
    if cacheable, libraryTracksCacheKey == cacheKey { return libraryTracksCache }
    let filtered = filteredTracks(tracks, source: source)
    let values = libraryView == "recent" || (source == "streaming" && streamingLibraryMode == "history")
      ? filtered
      : sortLibraryTracks(filtered)
    if cacheable {
      libraryTracksCacheKey = cacheKey
      libraryTracksCache = values
    }
    return values
  }

  private func libraryCacheKey(source: String) -> EchoNativeLibraryCollectionsCacheKey {
    EchoNativeLibraryCollectionsCacheKey(
      revision: libraryCollectionsRevision,
      source: source,
      view: libraryView,
      filter: libraryFilter,
      query: libraryQuery,
      sort: activeLibrarySort(),
      language: persistent.settings.language
    )
  }

  private func collectionsForCurrentView(_ sourceTracks: [EchoNativeCoreTrack], source: String) -> [[String: Any]] {
    guard libraryView == "albums" || libraryView == "artists" else { collectionTrackKeys = [:]; return [] }
    let cacheKey = libraryCacheKey(source: source)
    if libraryCollectionsCacheKey == cacheKey {
      collectionTrackKeys = libraryCollectionsCacheTrackKeys
      return libraryCollectionsCache
    }
    if source == "echo", libraryView == "albums" {
      let query = normalized(libraryQuery)
      let allowedTitles: Set<String>? = libraryFilter == "streamable"
        ? Set(sourceTracks.filter(\.canPlayOnPhone).map { normalized($0.album) })
        : libraryFilter == "local"
          ? Set(sourceTracks.filter { normalized($0.sourceLabel).contains("local") }.map { normalized($0.album) })
          : nil
      let tracksByAlbumTitle = Dictionary(grouping: sourceTracks) { normalized($0.album) }
      let previousKeys = collectionTrackKeys
      var nextKeys: [String: [String]] = [:]
      let values = sortLibraryCollections(echoAlbums.filter { album in
        (query.isEmpty || [album.title, album.sourceLabel].contains { normalized($0).contains(query) })
          && (allowedTitles?.contains(normalized(album.title)) ?? true)
      }.map { album in
        let id = "echo:album-id:\(album.id)"
        let albumTracks = tracksByAlbumTitle[normalized(album.title)] ?? []
        let sortArtist = albumTracks.map(\.artist).filter { !$0.isEmpty }
          .sorted { compareLibraryText($0, $1) }.first ?? ""
        nextKeys[id] = previousKeys[id] ?? []
        return [
          "artworkUrl": album.artworkUrl ?? "",
          "id": id,
          "indexTitle": librarySort == "artist" && !sortArtist.isEmpty ? sortArtist : album.title,
          "query": album.title,
          "sortArtist": sortArtist,
          "sortDuration": album.durationMs > 0 ? album.durationMs : albumTracks.reduce(0) { $0 + $1.durationMs },
          "subtitle": localized("\(album.trackCount) tracks", "\(album.trackCount) 首"),
          "title": album.title,
        ]
      })
      collectionTrackKeys = nextKeys
      libraryCollectionsCacheKey = cacheKey
      libraryCollectionsCache = values
      libraryCollectionsCacheTrackKeys = nextKeys
      return values
    }
    let tracks = filteredTracks(sourceTracks, source: source)
    let albums = source == "echo" ? echoAlbums : source == "remote" ? powerampAlbums : []
    var albumsByTitle: [String: [EchoNativeCoreAlbum]] = [:]
    for album in albums {
      albumsByTitle[normalized(album.title), default: []].append(album)
    }
    var groups: [String: [EchoNativeCoreTrack]] = [:]
    var groupTitles: [String: String] = [:]
    var groupArtists: [String: Set<String>] = [:]
    for track in tracks {
      let fallback = localized("Unknown Artist", "未知艺术家")
      let titles = libraryView == "artists"
        ? artistNames(track.artist, fallback: fallback)
        : [track.album.isEmpty ? localized("Uncategorized", "未归类专辑") : track.album]
      for title in titles {
        let key = normalized(title)
        groups[key, default: []].append(track)
        if let currentTitle = groupTitles[key] {
          let order = title.localizedStandardCompare(currentTitle)
          if order == .orderedAscending || (order == .orderedSame && title < currentTitle) {
            groupTitles[key] = title
          }
        } else {
          groupTitles[key] = title
        }
        if libraryView == "albums" {
          groupArtists[key, default: []].formUnion(trackArtistComparisonValues(track.artist))
        }
      }
    }
    var groupTitleKeys = groups.keys.reduce(into: [String: [String]]()) { $0[$1] = [$1] }
    if libraryView == "albums" {
      let exactGroups = groups
      let exactTitles = groupTitles
      let exactArtists = groupArtists.mapValues { $0.sorted() }
      let exactOrder = exactGroups.keys.sorted()
      var parent = Array(exactOrder.indices)
      func root(_ index: Int) -> Int {
        var value = index
        while parent[value] != value { value = parent[value] }
        var current = index
        while parent[current] != current {
          let next = parent[current]
          parent[current] = value
          current = next
        }
        return value
      }
      if exactOrder.count > 1 {
        // ponytail: This pairwise scan runs only on cache misses; bucket titles if first-load profiling shows it matters.
        for leftIndex in 0..<(exactOrder.count - 1) {
          let leftKey = exactOrder[leftIndex]
          for rightIndex in (leftIndex + 1)..<exactOrder.count {
            let rightKey = exactOrder[rightIndex]
            guard albumsMatch(
              title: exactTitles[leftKey] ?? leftKey,
              artists: exactArtists[leftKey] ?? [],
              otherTitle: exactTitles[rightKey] ?? rightKey,
              otherArtists: exactArtists[rightKey] ?? []
            ) else { continue }
            let leftRoot = root(leftIndex)
            let rightRoot = root(rightIndex)
            if leftRoot != rightRoot { parent[max(leftRoot, rightRoot)] = min(leftRoot, rightRoot) }
          }
        }
      }
      var components: [Int: [String]] = [:]
      for index in exactOrder.indices {
        components[root(index), default: []].append(exactOrder[index])
      }
      groups = [:]
      groupTitles = [:]
      groupTitleKeys = [:]
      for component in components.values.map({ $0.sorted() }).sorted(by: { $0[0] < $1[0] }) {
        let seed = component[0]
        groups[seed] = component.flatMap { exactGroups[$0] ?? [] }
        groupTitles[seed] = exactTitles[seed]
        groupTitleKeys[seed] = component
      }
    }
    var nextKeys: [String: [String]] = [:]
    let values = sortLibraryCollections(groups.map { key, values in
      let first = values[0]
      let title = groupTitles[key] ?? (libraryView == "artists"
        ? localized("Unknown Artist", "未知艺术家")
        : localized("Uncategorized", "未归类专辑"))
      let sortArtist = libraryView == "artists"
        ? title
        : values.map(\.artist).filter { !$0.isEmpty }.sorted { compareLibraryText($0, $1) }.first ?? ""
      let sourcePrefix = values.allSatisfy { $0.source == first.source } ? first.source.rawValue : source
      let matchingAlbums = (groupTitleKeys[key] ?? [normalized(title)]).flatMap { albumsByTitle[$0] ?? [] }
      let album = matchingAlbums.first { $0.artworkUrl?.isEmpty == false } ?? matchingAlbums.first
      let id = libraryView == "artists"
        ? "\(sourcePrefix)-artist:\(normalized(title))"
        : "\(sourcePrefix):album:\(key)"
      nextKeys[id] = values.map { trackKey($0) }
      return [
        "artworkUrl": album?.artworkUrl ?? values.first(where: { $0.artworkUrl?.isEmpty == false })?.artworkUrl ?? "",
        "id": id,
        "indexTitle": librarySort == "artist" && !sortArtist.isEmpty ? sortArtist : title,
        "query": title,
        "sortArtist": sortArtist,
        "sortDuration": values.reduce(0) { $0 + $1.durationMs },
        "subtitle": localized("\(values.count) tracks", "\(values.count) 首"),
        "title": title,
      ]
    })
    collectionTrackKeys = nextKeys
    libraryCollectionsCacheKey = cacheKey
    libraryCollectionsCache = values
    libraryCollectionsCacheTrackKeys = nextKeys
    return values
  }

  private func sortLibraryCollections(_ collections: [[String: Any]]) -> [[String: Any]] {
    guard librarySort != "default" else { return collections }
    return collections.sorted { left, right in
      let leftTitle = left["title"] as? String ?? ""
      let rightTitle = right["title"] as? String ?? ""
      switch librarySort {
      case "artist":
        return compareLibraryText(
          left["sortArtist"] as? String ?? leftTitle,
          right["sortArtist"] as? String ?? rightTitle,
          tie: leftTitle,
          rightTitle
        )
      case "duration":
        let leftDuration = left["sortDuration"] as? Double ?? 0
        let rightDuration = right["sortDuration"] as? Double ?? 0
        return leftDuration == rightDuration
          ? compareLibraryText(leftTitle, rightTitle)
          : leftDuration < rightDuration
      default:
        return compareLibraryText(leftTitle, rightTitle)
      }
    }
  }

  private func artistNames(_ value: String, fallback: String) -> [String] {
    let names = value
      .replacingOccurrences(of: #"\s*(?:,|;|，|；|、)\s*|\s+/\s+"#, with: "\u{0}", options: .regularExpression)
      .components(separatedBy: "\u{0}")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var seen = Set<String>()
    let unique = names.filter { seen.insert(normalized($0)).inserted }
    return unique.isEmpty ? [fallback] : unique
  }

  private func libraryTrackPayload(_ track: EchoNativeCoreTrack) -> [String: Any] {
    [
      "artworkUrl": track.artworkUrl ?? "",
      "artist": track.artist.isEmpty ? localized("Unknown Artist", "未知艺术家") : track.artist,
      "canPlayOnPhone": track.canPlayOnPhone,
      "discNo": track.discNo.map { $0 as Any } ?? NSNull(),
      "durationMs": track.durationMs,
      "favorite": persistent.favoriteTrackKeys.contains(trackKey(track)),
      "group": libraryView == "formats" ? track.codec?.uppercased() ?? "" : "",
      "hasLyrics": track.hasLyrics,
      "id": track.id,
      "isLocal": track.source == .local,
      "source": track.source.rawValue,
      "tags": tags(for: track, includeDuration: true, includeOutput: false),
      "title": track.title,
      "trackNo": track.trackNo.map { $0 as Any } ?? NSNull(),
    ]
  }

  private func filterOptions(source: String, tracks: [EchoNativeCoreTrack]) -> [[String: Any]] {
    [
      option("all", "\(localized("All", "全部")) \(tracks.count)"),
      option("streamable", "\(localized("Streamable", "可串流")) \(tracks.filter(\.canPlayOnPhone).count)"),
      option("local", "Local \(tracks.filter { normalized($0.sourceLabel).contains("local") }.count)"),
    ]
  }

  private func libraryLabels(source: String) -> [String: Any] {
    [
      "addToQueue": localized("Add to queue", "加入队列"),
      "addToPlaylist": localized("Add to playlist", "加入歌单"),
      "cancel": localized("Cancel", "取消"),
      "collections": libraryView == "artists" ? localized("Artists", "艺术家") : localized("Albums", "专辑"),
      "createPlaylist": localized("Create playlist", "创建歌单"),
      "deleteTrack": localized("Delete track", "删除歌曲"),
      "deletePlaylist": localized("Delete playlist", "删除歌单"),
      "empty": emptyLibraryMessage(source),
      "favorite": localized("Favorite", "收藏"),
      "favoritePlaylist": localized("Favorite playlist", "收藏歌单"),
      "importLyrics": localized("Import lyrics", "导入歌词"),
      "importMusic": localized("Import music", "导入音乐"),
      "localPlay": localized("Play", "播放"),
      "playNext": localized("Play next", "下一首播放"),
      "playlistName": localized("Playlist name", "歌单名称"),
      "playlists": localized("Playlists", "歌单"),
      "pinPlaylist": localized("Pin playlist", "置顶歌单"),
      "removeFromPlaylist": localized("Remove from playlist", "从歌单移除"),
      "renamePlaylist": localized("Rename playlist", "重命名歌单"),
      "refresh": localized("Refresh", "刷新"),
      "searchPlaceholder": localized("Search songs, albums, or artists", "搜索歌曲、专辑或艺术家"),
      "songs": localized("Songs", "歌曲"),
      "unFavoritePlaylist": localized("Remove favorite", "取消收藏"),
      "unpinPlaylist": localized("Unpin playlist", "取消置顶"),
      "unfavorite": localized("Remove favorite", "取消收藏"),
    ]
  }

  private func emptyLibraryMessage(_ source: String) -> String {
    if source == "echo", !echoError.isEmpty { return echoError }
    if source == "remote", !powerampError.isEmpty { return powerampError }
    if source == "streaming", neteaseProfile == nil { return localized("Sign in from Connect first.", "请先在连接页登录网易云音乐") }
    return localized("No matching music.", "没有匹配的音乐")
  }

  private func librarySourceOptions() -> [[String: Any]] {
    var values = [option("all", localized("All", "全部")), option("local", localized("Local", "本地"))]
    if persistent.echoConnection.enabled { values.insert(option("echo", "ECHO"), at: 1) }
    if persistent.powerampConnection.enabled { values.append(option("remote", localized("Remote", "远程"))) }
    values.append(option("streaming", localized("Media", "流媒体")))
    return values
  }

  private func libraryViewOptions(source: String) -> [[String: Any]] {
    var values = [
      option("songs", localized("Songs", "歌曲")),
      option("albums", localized("Albums", "专辑")),
      option("artists", localized("Artists", "艺术家")),
      option("favorites", localized("Favorites", "收藏")),
      option("recent", localized("Recent", "最近")),
    ]
    if source == "local" { values.append(option("formats", localized("Formats", "格式"))) }
    return values
  }

  private func playlistPayload(_ playlist: EchoNativeSavedPlaylist, includeTracks: Bool) -> [String: Any] {
    [
      "artworkUrl": playlist.tracks.first(where: { $0.artworkUrl != nil })?.artworkUrl ?? "",
      "favorite": playlist.favorite,
      "id": playlist.id,
      "name": playlist.name,
      "pinned": playlist.pinned,
      "subtitle": localized("\(playlist.tracks.count) tracks", "\(playlist.tracks.count) 首"),
      "trackCount": playlist.tracks.count,
      "tracks": includeTracks ? playlist.tracks.map(libraryTrackPayload) : [],
    ]
  }

  private func sortedPlaylists() -> [EchoNativeSavedPlaylist] {
    persistent.playlists.sorted {
      if $0.pinned != $1.pinned { return $0.pinned }
      if $0.favorite != $1.favorite { return $0.favorite }
      return $0.createdAt > $1.createdAt
    }
  }

  private func sortedStreamingPlaylists() -> [EchoNativeNeteaseClient.Playlist] {
    neteasePlaylists.sorted {
      let nameOrder = libraryTextSortKey($0.name).localizedStandardCompare(libraryTextSortKey($1.name))
      if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
      let leftPinned = streamingPinnedPlaylistIds.contains($0.id)
      let rightPinned = streamingPinnedPlaylistIds.contains($1.id)
      return leftPinned == rightPinned ? $0.id < $1.id : leftPinned
    }
  }

  private func streamingLibraryPayload(playlists: [EchoNativeNeteaseClient.Playlist]) -> [String: Any] {
    let status = playerModel.activePage == "search" || streamingLibraryMode == "search"
      ? streamingSearchStatus
      : streamingStatus
    return [
      "libraryMode": streamingLibraryMode,
      "libraryModeOptions": [
        option("search", localized("Search", "搜索")),
        option("playlists", localized("Playlists", "歌单")),
        option("history", localized("History", "历史")),
      ],
      "loggedIn": neteaseProfile != nil,
      "playlistCount": neteasePlaylists.count,
      "playlists": playlists.map { playlist in [
        "artworkUrl": playlist.artworkUrl,
        "favorite": streamingFavoritePlaylistIds.contains(playlist.id),
        "id": playlist.id,
        "name": playlist.name,
        "pinned": streamingPinnedPlaylistIds.contains(playlist.id),
        "sourceLabel": localized("NetEase", "网易云"),
        "trackCount": playlist.trackCount,
      ] as [String: Any] },
      "profileAvatarUrl": neteaseProfile?.avatarUrl ?? "",
      "profileName": neteaseProfile?.name ?? "",
      "selectedPlaylistId": selectedStreamingPlaylistId,
      "selectedPlaylistName": neteasePlaylists.first(where: { $0.id == selectedStreamingPlaylistId })?.name ?? "",
      "status": status,
    ]
  }

  private func settingsPayload() -> [String: Any] {
    let settings = persistent.settings
    let defaultSourceUnavailable = (settings.defaultLibrarySource == "echo" && !persistent.echoConnection.enabled)
      || (settings.defaultLibrarySource == "remote" && !persistent.powerampConnection.enabled)
    let defaultLibrarySource = defaultSourceUnavailable ? "local" : settings.defaultLibrarySource
    let desktopLyricsSection = section("desktopLyrics", localized("Desktop lyrics", "桌面歌词"), localized("Native Picture in Picture lyrics with artwork and line transitions.", "带封面与逐句动效的原生画中画歌词。"), "quote.bubble.fill", [
      toggle("desktopLyricsEnabled", localized("Enable desktop lyrics", "启用桌面歌词"), localized("Show lyrics in a floating Picture in Picture window over other apps.", "通过悬浮的画中画窗口在其他应用上方显示歌词。"), settings.desktopLyricsEnabled),
      toggle("desktopLyricsOnlyWhilePlaying", localized("Only while playing", "仅播放时显示"), localized("Hide desktop lyrics when playback is paused.", "暂停播放时隐藏桌面歌词。"), settings.desktopLyricsOnlyWhilePlaying, disabled: !settings.desktopLyricsEnabled),
      toggle("desktopLyricsShowMetadata", localized("Show track details", "显示歌曲信息"), localized("Include title and artist above the lyric.", "在歌词上方显示标题和艺术家。"), settings.desktopLyricsShowMetadata, disabled: !settings.desktopLyricsEnabled),
      picker("desktopLyricsBackground", localized("Background", "背景"), localized("Use the ECHO theme, the current artwork with blur, or an imported image.", "使用 ECHO 主题色、模糊歌曲封面或导入图片。"), settings.desktopLyricsBackground, [
        option("theme", localized("Theme", "主题色")), option("artwork", localized("Artwork glass", "封面玻璃")), option("custom", localized("Imported image", "导入图片")),
      ], disabled: !settings.desktopLyricsEnabled),
      action("desktopLyricsImportBackground", localized("Import background image", "导入背景图片"), localized("Choose and crop an image for the desktop lyric background.", "选择并裁剪桌面歌词背景图片。"), disabled: !settings.desktopLyricsEnabled || settings.desktopLyricsBackground != "custom"),
      picker("desktopLyricsAnimation", localized("Line transition", "逐句动效"), localized("Choose how the previous lyric changes into the next lyric.", "选择上一句歌词切换到下一句歌词的动效。"), settings.desktopLyricsAnimation, [
        option("calm", localized("Fade", "淡入淡出")), option("flow", localized("Flow", "流动")), option("pulse", localized("Pulse", "呼吸")),
      ], disabled: !settings.desktopLyricsEnabled || !settings.desktopLyricsTransitionAnimation),
      toggle("desktopLyricsTransitionAnimation", localized("Lyric transition", "歌词切换动效"), localized("Animate when the active lyric changes.", "切换当前歌词时播放动效。"), settings.desktopLyricsTransitionAnimation, disabled: !settings.desktopLyricsEnabled),
      toggle("desktopLyricsTimedReveal", localized("Timed fill", "逐字填充动效"), localized("Fill every lyric line smoothly from left to right in white.", "每行歌词同时从左向右平滑填充为白色。"), settings.desktopLyricsTimedReveal, disabled: !settings.desktopLyricsEnabled),
      toggle("desktopLyricsRainbowGradient", localized("Rainbow gradient", "彩虹渐变歌词"), localized("Animate lyric colors across the spectrum; timed fill colors only the highlighted text.", "让歌词颜色沿彩虹动态变化；开启逐字填充时仅高亮部分着色。"), settings.desktopLyricsRainbowGradient, disabled: !settings.desktopLyricsEnabled),
      slider("desktopLyricsSize", localized("Text size", "文字大小"), localized("Tune the desktop lyric text size.", "调整桌面歌词的字号。"), settings.desktopLyricsFontSize, min: 18, max: 48, step: 1, disabled: !settings.desktopLyricsEnabled),
      slider("desktopLyricsWidth", localized("PiP width", "画中画宽度"), localized("Adjust the floating window width.", "调整悬浮画中画窗口的宽度。"), settings.desktopLyricsWidthScale, min: 0.2, max: 1.0, step: 0.01, disabled: !settings.desktopLyricsEnabled),
      slider("desktopLyricsHeight", localized("PiP height", "画中画长度"), localized("Adjust the floating window length vertically.", "调整悬浮画中画窗口的纵向长度。"), settings.desktopLyricsHeightScale, min: 0.33, max: 1.0, step: 0.01, disabled: !settings.desktopLyricsEnabled),
      picker("desktopLyricsPosition", localized("Position", "显示位置"), localized("Place lyrics at the top, center, or bottom of the Picture in Picture window.", "将歌词放在画中画窗口的顶部、中央或底部。"), settings.desktopLyricsPosition, [
        option("top", localized("Top", "顶部")), option("center", localized("Center", "居中")), option("bottom", localized("Bottom", "底部")),
      ], disabled: !settings.desktopLyricsEnabled),
    ])
    let sections: [[String: Any]] = [
      section("interface", localized("Interface", "界面"), localized("Language and appearance", "语言与外观"), "paintbrush", [
        picker("language", localized("Language", "语言"), localized("Changes the entire app language.", "更改整个应用的显示语言。"), settings.language, [option("zh", "中文"), option("en", "English")]),
        picker("defaultPage", localized("Launch page", "启动页面"), localized("The tab shown when the app starts.", "应用启动时显示的页面。"), settings.defaultPage, [
          option("control", localized("Playback", "播放")), option("library", localized("Library", "曲库")),
          option("search", localized("Search", "搜索")), option("connect", localized("Connect", "连接")),
          option("settings", localized("Settings", "设置")),
        ]),
        toggle("followSystemAppearance", localized("Follow system appearance", "跟随系统外观"), localized("Use the iOS light or dark appearance automatically.", "自动使用 iOS 的浅色或深色外观。"), settings.followSystemAppearance),
        picker("manualAppearance", localized("Manual appearance", "手动外观"), localized("Used when following the system is off.", "关闭跟随系统后使用。"), settings.darkModeEnabled ? "dark" : "light", [option("light", localized("Light", "浅色")), option("dark", localized("Dark", "深色"))], disabled: settings.followSystemAppearance),
      ]),
      desktopLyricsSection,
      section("playback", localized("Playback", "播放"), localized("DSP and playback behavior", "DSP 与播放行为"), "waveform", [
        row("eq", localized("Equalizer", "均衡器"), localized("Ten-band native DSP equalizer.", "十段原生 DSP 均衡器。"), kind: "eq", value: settings.eqPreset),
        toggle("loudness", localized("Loudness normalization", "响度归一化"), localized("Reduces large volume differences between tracks.", "减小歌曲之间过大的响度差异。"), settings.loudnessEnabled),
        toggle("autoLyrics", localized("Open local lyrics automatically", "自动打开本地歌词"), localized("Opens lyrics when a local track has an imported LRC file.", "本地歌曲存在已导入的 LRC 文件时自动打开歌词。"), settings.autoOpenLyricsForLocalTracks),
        toggle("artworkGlow", localized("Artwork glow", "封面光效"), localized("Shows a restrained glow around artwork.", "在封面周围显示克制的光效。"), settings.showArtworkGlow),
        toggle("artworkBackground", localized("Artwork background", "封面动态背景"), localized("Uses current artwork behind playback and lyrics.", "在播放页与歌词页使用当前封面背景。"), settings.artworkBackgroundEnabled),
        toggle("playerOutputInMenu", localized("Source and output controls in more menu", "音乐源与输出选择放入三点菜单"), localized("Move music source and control/stream selectors into the player more menu.", "把音乐源与控制/串流选择收进播放页三点菜单。"), settings.showPlayerOutputInMenu),
      ]),
      section("externalData", localized("External data", "外源数据"), localized("Artwork and lyrics lookup", "封面与歌词查询"), "globe", [
        toggle("externalMetadataSearch", localized("Search metadata online", "从网络搜索元数据"), localized("Uses LRCLIB for lyrics and NetEase for artwork when needed.", "需要时使用 LRCLIB 获取歌词、网易云补充封面。"), settings.externalMetadataEnabled),
        toggle("externalMetadataSkipExisting", localized("Keep existing metadata", "已有数据时跳过"), localized("Skips automatic lookup when artwork or lyrics already exist.", "已有封面或歌词时跳过自动联网查询；手动刷新仍可查询。"), settings.externalMetadataSkipExisting),
        picker("externalSelectionMode", localized("Match selection", "匹配方式"), localized("Choose each source or apply the recommended match automatically.", "手动选择每项来源，或自动使用推荐匹配。"), settings.externalDataSelectionMode, [option("ask", localized("Always ask", "每次询问")), option("automatic", localized("Automatic", "自动匹配"))]),
        toggle("lrcapi", "LrcAPI", localized("Can provide artwork, lyrics, and artist metadata.", "可获取封面、歌词与艺术家等信息。"), settings.lrcApiExternalDataEnabled),
        toggle("lrclib", "LRCLIB", localized("Preferred source for synchronized lyrics.", "优先用于获取同步歌词。"), settings.lrclibExternalDataEnabled),
        toggle("netease", localized("NetEase Cloud Music", "网易云音乐"), localized("Preferred artwork supplement for Chinese music.", "优先补充中文曲库封面。"), settings.neteaseExternalDataEnabled),
        picker("neteaseAccessMode", localized("NetEase access", "网易云访问方式"), localized("Use the official web API or a configured self-hosted endpoint.", "使用官方 Web 接口或连接页配置的自托管接口。"), settings.neteaseAccessMode, [option("direct", localized("Direct Web API", "直连 Web 接口")), option("selfHosted", localized("Self-hosted API", "自托管接口"))]),
      ]),
      section("library", localized("Library", "曲库"), localized("Default source and organization", "默认来源与整理方式"), "music.note.list", [
        picker("defaultLibrarySource", localized("Default source", "默认曲库来源"), localized("The source opened on launch.", "启动时默认打开的曲库来源。"), defaultLibrarySource, librarySourceOptions()),
        picker("defaultLocalView", localized("Default local view", "本地默认分类"), localized("The local library category used on launch.", "启动时使用的本地曲库分类。"), settings.defaultLocalLibraryView, [
          option("songs", localized("Songs", "歌曲")), option("albums", localized("Albums", "专辑")),
          option("artists", localized("Artists", "艺术家")), option("favorites", localized("Favorites", "收藏")),
          option("recent", localized("Recent", "最近")), option("formats", localized("Formats", "格式")),
        ]),
        toggle("autoQueueImports", localized("Queue imported music", "导入后加入队列"), localized("Adds newly imported local tracks to the current queue.", "将新导入的本地歌曲加入当前播放队列。"), settings.autoQueueImportedLocalTracks),
        toggle("confirmDelete", localized("Confirm before deleting", "删除前确认"), localized("Requires confirmation before deleting a local file.", "删除本地音乐文件前要求确认。"), settings.confirmBeforeDeletingLocalTracks),
      ]),
      section("remote", localized("Remote", "远程"), localized("Remote entry visibility", "远程入口开关"), "dot.radiowaves.left.and.right", [
        toggle("showPowerampRemoteConnection", localized("Show Poweramp Remote", "显示 Poweramp 远程"), localized("Shows the Remote connection entry.", "显示连接页中的远程入口。"), settings.showPowerampRemote),
      ]),
      section("audioTags", localized("Audio tags", "音频标签"), localized("Choose visible technical tags", "选择显示的技术标签"), "tag", tagSettingRows()),
      section("storage", localized("Storage", "存储"), localized("Local files and playback history", "本地文件与播放历史"), "internaldrive", [
        row("storageUsed", localized("Local music", "本地音乐"), "", kind: "info", value: storageText()),
        action("rescanMetadata", localized("Rescan metadata", "重新扫描元数据"), localized("Rebuilds local tags and artwork.", "重新读取本地标签与封面。"), disabled: localBusy),
        action("clearLocalQueue", localized("Clear local queue", "清空本地队列"), localized("Removes local tracks from the queue.", "从播放队列移除本地歌曲。"), disabled: queue.allSatisfy { $0.source != .local }),
        action("clearRecent", localized("Clear recent", "清空最近播放"), localized("Clears local playback history.", "清除本机播放历史。"), disabled: persistent.recentTrackKeys.isEmpty),
      ]),
    ]
    return ["sections": sections, "subtitle": localized("Settings are stored on this iPhone.", "设置保存在此 iPhone 的个人数据中。")]
  }

  private func tagSettingRows() -> [[String: Any]] {
    let values: [(String, String, String)] = [
      ("codec", "Format", "格式"), ("sampleRate", "Sample rate", "采样率"), ("bitDepth", "Bit depth", "位深"),
      ("bitrate", "Bitrate", "码率"), ("output", "Output", "输出模式"), ("source", "Source", "来源"),
      ("streamable", "Streamable", "可串流"), ("duration", "Duration", "时长"),
    ]
    var rows = values.map { key, english, chinese in
      toggle("audioTag.\(key)", localized(english, chinese), localized("Show this tag when available.", "可用时显示此标签。"), persistent.settings.audioTagVisibility[key] != false)
    }
    rows.append(action("resetTags", localized("Reset tags", "重置标签"), localized("Restores the default tag selection.", "恢复默认标签选择。")))
    return rows
  }

  private func section(_ id: String, _ title: String, _ description: String, _ symbol: String, _ rows: [[String: Any]]) -> [String: Any] {
    ["description": description, "id": id, "rows": rows, "summary": "\(rows.count)", "symbol": symbol, "title": title]
  }

  private func row(
    _ id: String,
    _ title: String,
    _ description: String,
    kind: String,
    value: String = "",
    boolValue: Any = NSNull(),
    numberValue: Any = NSNull(),
    minimumValue: Any = NSNull(),
    maximumValue: Any = NSNull(),
    stepValue: Any = NSNull(),
    options: [[String: Any]] = [],
    selection: Any = NSNull(),
    disabled: Bool = false
  ) -> [String: Any] {
    ["boolValue": boolValue, "description": description, "disabled": disabled, "id": id, "kind": kind, "maximumValue": maximumValue, "minimumValue": minimumValue, "numberValue": numberValue, "options": options, "selection": selection, "stepValue": stepValue, "title": title, "value": value]
  }

  private func toggle(_ id: String, _ title: String, _ description: String, _ value: Bool, disabled: Bool = false) -> [String: Any] {
    row(id, title, description, kind: "toggle", boolValue: value, disabled: disabled)
  }

  private func picker(_ id: String, _ title: String, _ description: String, _ selection: String, _ options: [[String: Any]], disabled: Bool = false) -> [String: Any] {
    row(id, title, description, kind: "picker", options: options, selection: selection, disabled: disabled)
  }

  private func slider(
    _ id: String,
    _ title: String,
    _ description: String,
    _ value: Double,
    min: Double,
    max: Double,
    step: Double,
    disabled: Bool = false
  ) -> [String: Any] {
    let label: String
    if id == "desktopLyricsWidth" || id == "desktopLyricsHeight" {
      label = "\(Int((value * 100).rounded()))%"
    } else {
      label = "\(Int(value.rounded())) pt"
    }
    return row(
      id,
      title,
      description,
      kind: "slider",
      value: label,
      numberValue: value,
      minimumValue: min,
      maximumValue: max,
      stepValue: step,
      disabled: disabled
    )
  }

  private func action(_ id: String, _ title: String, _ description: String, disabled: Bool = false) -> [String: Any] {
    row(id, title, description, kind: "action", disabled: disabled)
  }

  private func option(_ id: String, _ label: String) -> [String: Any] { ["id": id, "label": label] }

  private func storageText() -> String {
    let bytes = localTracks.reduce(Int64(0)) { $0 + $1.fileSize }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  private func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func albumsMatch(
    title: String,
    artists: [String],
    otherTitle: String,
    otherArtists: [String]
  ) -> Bool {
    guard textSimilarity(title, otherTitle) >= 0.9 else { return false }
    return artistSetSimilarity(artists, otherArtists) >= 0.9
  }

  private func artistSetSimilarity(_ leftArtists: [String], _ rightArtists: [String]) -> Double {
    guard !leftArtists.isEmpty, !rightArtists.isEmpty else { return 0 }
    let longestCount = max(leftArtists.count, rightArtists.count)
    guard Double(min(leftArtists.count, rightArtists.count)) / Double(longestCount) >= 0.9 else { return 0 }
    let requiredArtists = leftArtists.count <= rightArtists.count ? leftArtists : rightArtists
    let availableArtists = leftArtists.count <= rightArtists.count ? rightArtists : leftArtists
    var requiredByAvailable = Array<Int?>(repeating: nil, count: availableArtists.count)
    func assign(_ requiredIndex: Int, seen: inout Set<Int>) -> Bool {
      for availableIndex in availableArtists.indices {
        guard textSimilarity(requiredArtists[requiredIndex], availableArtists[availableIndex]) >= 0.9,
          seen.insert(availableIndex).inserted else { continue }
        if let previous = requiredByAvailable[availableIndex], !assign(previous, seen: &seen) { continue }
        requiredByAvailable[availableIndex] = requiredIndex
        return true
      }
      return false
    }
    var matches = 0
    for requiredIndex in requiredArtists.indices {
      var seen = Set<Int>()
      if assign(requiredIndex, seen: &seen) { matches += 1 }
    }
    return Double(matches) / Double(longestCount)
  }

  private func trackArtistComparisonValues(_ value: String) -> [String] {
    let names = value
      .replacingOccurrences(
        of: #"\s*(?:,|;|，|；|、|/|／|&|＆|\+|\||｜)\s*|\s+(?:feat\.?|ft\.?|featuring|x|×)\s+"#,
        with: "\u{0}",
        options: [.regularExpression, .caseInsensitive]
      )
      .components(separatedBy: "\u{0}")
    return Array(Set(names
      .map(albumComparisonValue)
      .filter { !$0.isEmpty }))
      .sorted()
  }

  private func textSimilarity(_ leftValue: String, _ rightValue: String) -> Double {
    let left = Array(albumComparisonValue(leftValue))
    let right = Array(albumComparisonValue(rightValue))
    if left == right { return 1 }
    guard !left.isEmpty, !right.isEmpty else { return 0 }
    let longestCount = max(left.count, right.count)
    guard Double(abs(left.count - right.count)) / Double(longestCount) <= 0.1 else { return 0 }
    var previous = Array(0...right.count)
    for (leftIndex, leftCharacter) in left.enumerated() {
      var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
      for (rightIndex, rightCharacter) in right.enumerated() {
        let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
        current[rightIndex + 1] = min(min(current[rightIndex] + 1, previous[rightIndex + 1] + 1), substitution)
      }
      previous = current
    }
    return 1 - Double(previous[right.count]) / Double(max(left.count, right.count))
  }

  private func albumComparisonValue(_ value: String) -> String {
    normalized(value).filter { $0.isLetter || $0.isNumber }
  }

  private func deduplicated(_ tracks: [EchoNativeCoreTrack]) -> [EchoNativeCoreTrack] {
    echoDeduplicatedTracks(tracks)
  }
}
