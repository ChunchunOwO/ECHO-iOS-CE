import AVFoundation
import AudioToolbox
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

enum EchoNativeLocalLibrary {
  private struct EmbeddedMetadata: Codable, Sendable {
    var artist: String?
    var artworkFile: String?
    var artworkRemoteUrl: String?
    var lyricsEmbedded = false
  }

  private static let audioExtensions = Set(["aac", "aiff", "alac", "caf", "flac", "m4a", "mp3", "mp4", "wav"])

  static var directory: URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documents.appendingPathComponent("local-music", isDirectory: true)
  }

  static func scan() async -> [EchoNativeCoreTrack] {
    await Task.detached(priority: .utility) {
      let manager = FileManager.default
      try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
      let urls = (try? manager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )) ?? []
      return urls
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .map(track)
    }.value
  }

  @MainActor
  static func importFiles(from presenter: UIViewController) async throws -> Int {
    let importer = EchoNativeDocumentImporter(presenter: presenter)
    let urls = await importer.pickAudioFiles()
    guard !urls.isEmpty else { return 0 }
    return try await Task.detached(priority: .utility) {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var count = 0
      for source in urls where audioExtensions.contains(source.pathExtension.lowercased()) {
        let accessed = source.startAccessingSecurityScopedResource()
        defer { if accessed { source.stopAccessingSecurityScopedResource() } }
        let destination = uniqueDestination(for: sanitized(source.lastPathComponent))
        try FileManager.default.copyItem(at: source, to: destination)
        count += 1
      }
      return count
    }.value
  }

  static func delete(_ track: EchoNativeCoreTrack) throws {
    guard let raw = track.localUrl, let url = URL(string: raw), url.isFileURL,
      url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    else {
      return
    }
    try FileManager.default.removeItem(at: url)
    try? FileManager.default.removeItem(at: url.deletingPathExtension().appendingPathExtension("lrc"))
    try? FileManager.default.removeItem(at: embeddedMetadataUrl(for: url))
    try? FileManager.default.removeItem(at: embeddedArtworkUrl(for: url, extensionName: "jpg"))
    try? FileManager.default.removeItem(at: embeddedArtworkUrl(for: url, extensionName: "png"))
  }

  static func needsExternalMetadataEmbedding(_ track: EchoNativeCoreTrack) -> Bool {
    guard track.source == .local, let raw = track.localUrl, let audioUrl = URL(string: raw), audioUrl.isFileURL else {
      return false
    }
    let embedded = embeddedMetadata(for: audioUrl)
    if let artist = track.externalArtist, !artist.isEmpty, embedded?.artist != artist { return true }
    if let artwork = track.externalArtworkUrl, !artwork.isEmpty {
      guard let file = embedded?.artworkFile else { return true }
      if !FileManager.default.fileExists(atPath: audioUrl.deletingLastPathComponent().appendingPathComponent(file).path) {
        return true
      }
    }
    let lyricsUrl = audioUrl.deletingPathExtension().appendingPathExtension("lrc")
    return (track.externalLyrics?.isEmpty == false || track.externalLyricsUrl?.isEmpty == false)
      && !FileManager.default.fileExists(atPath: lyricsUrl.path)
  }

  static func embedExternalMetadata(for track: EchoNativeCoreTrack) async throws -> EchoNativeCoreTrack {
    guard track.source == .local, let raw = track.localUrl, let audioUrl = URL(string: raw), audioUrl.isFileURL,
      audioUrl.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    else { return track }

    var artworkData: Data?
    if let rawArtworkUrl = track.externalArtworkUrl, !rawArtworkUrl.isEmpty {
      artworkData = try? await EchoNativeMetadataService.artworkData(from: rawArtworkUrl)
    }
    var cachedLyrics = track.externalLyrics
    if let rawLyricsUrl = track.externalLyricsUrl, let lyricsUrl = URL(string: rawLyricsUrl) {
      let value = await EchoNativeMetadataService.text(from: lyricsUrl)
      if !value.isEmpty { cachedLyrics = value }
    }

    return try await Task.detached(priority: .utility) {
      let manager = FileManager.default
      var embedded = embeddedMetadata(for: audioUrl) ?? EmbeddedMetadata()
      if let artist = track.externalArtist, !artist.isEmpty { embedded.artist = artist }

      if let artworkData,
        let source = CGImageSourceCreateWithData(artworkData as CFData, nil),
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 1_600,
        ] as CFDictionary) {
        let artworkUrl = embeddedArtworkUrl(for: audioUrl, extensionName: "jpg")
        if let normalizedData = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.9) {
          try normalizedData.write(to: artworkUrl, options: .atomic)
          embedded.artworkFile = artworkUrl.lastPathComponent
          embedded.artworkRemoteUrl = track.externalArtworkUrl
          let obsolete = embeddedArtworkUrl(for: audioUrl, extensionName: "png")
          try? manager.removeItem(at: obsolete)
        }
      }

      let lyricsUrl = audioUrl.deletingPathExtension().appendingPathExtension("lrc")
      if !manager.fileExists(atPath: lyricsUrl.path), let cachedLyrics, !cachedLyrics.isEmpty {
        try Data(cachedLyrics.utf8).write(to: lyricsUrl, options: .atomic)
        embedded.lyricsEmbedded = true
      }
      let metadataData = try JSONEncoder().encode(embedded)
      try metadataData.write(to: embeddedMetadataUrl(for: audioUrl), options: .atomic)
      return EchoNativeLocalLibrary.track(url: audioUrl)
    }.value
  }

  @MainActor
  static func importLyrics(for track: EchoNativeCoreTrack, from presenter: UIViewController) async throws -> Bool {
    guard let raw = track.localUrl, let audioUrl = URL(string: raw), audioUrl.isFileURL else { return false }
    let importer = EchoNativeDocumentImporter(presenter: presenter)
    let type = UTType(filenameExtension: "lrc") ?? .plainText
    guard let source = await importer.pickFiles(contentTypes: [type, .plainText], allowsMultipleSelection: false).first else {
      return false
    }
    let accessed = source.startAccessingSecurityScopedResource()
    defer { if accessed { source.stopAccessingSecurityScopedResource() } }
    let destination = audioUrl.deletingPathExtension().appendingPathExtension("lrc")
    if source.standardizedFileURL == destination.standardizedFileURL { return true }
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.copyItem(at: source, to: destination)
    return true
  }

  private static func track(url: URL) -> EchoNativeCoreTrack {
    let asset = AVURLAsset(url: url)
    let metadata = asset.commonMetadata
    let embedded = embeddedMetadata(for: url)
    let duration = CMTimeGetSeconds(asset.duration)
    let title = stringValue(.commonIdentifierTitle, in: metadata)
      ?? url.deletingPathExtension().lastPathComponent.replacingOccurrences(
        of: #"^\d+[\s._-]+"#,
        with: "",
        options: .regularExpression
      )
    let nativeArtist = stringValue(.commonIdentifierArtist, in: metadata) ?? ""
    let artist = nativeArtist.isEmpty ? embedded?.artist ?? "" : nativeArtist
    let album = stringValue(.commonIdentifierAlbumName, in: metadata) ?? ""
    let albumArtist = stringValue(markers: ["albumartist", "album artist", "tpe2", "aart"], in: asset.metadata) ?? ""
    let audioTrack = asset.tracks(withMediaType: .audio).first
    let sampleRate = streamDescription(audioTrack)?.mSampleRate
    let bitDepthValue = streamDescription(audioTrack)?.mBitsPerChannel ?? 0
    let resources = try? url.resourceValues(forKeys: [.fileSizeKey])
    let lyricsUrl = url.deletingPathExtension().appendingPathExtension("lrc")
    let embeddedArtworkUrl = embedded?.artworkFile.map {
      url.deletingLastPathComponent().appendingPathComponent($0).absoluteString
    }
    let nativeArtworkUrl = artwork(in: metadata, sourceUrl: url)
    let artworkUrl = nativeArtworkUrl ?? embeddedArtworkUrl
    return EchoNativeCoreTrack(
      album: album,
      albumArtist: albumArtist,
      artist: artist,
      artworkUrl: artworkUrl,
      bitDepth: bitDepthValue > 0 ? Int(bitDepthValue) : nil,
      bitrate: audioTrack.map { Int($0.estimatedDataRate.rounded()) },
      canPlayOnPhone: true,
      codec: url.pathExtension.uppercased(),
      discNo: numberValue(markers: ["disk", "disc", "tpos"], in: asset.metadata),
      durationMs: duration.isFinite && duration > 0 ? duration * 1000 : 0,
      externalArtist: nativeArtist.isEmpty ? embedded?.artist : nil,
      externalArtworkUrl: nativeArtworkUrl == nil ? (embeddedArtworkUrl ?? embedded?.artworkRemoteUrl) : nil,
      externalLyricsUrl: embedded?.lyricsEmbedded == true && FileManager.default.fileExists(atPath: lyricsUrl.path)
        ? lyricsUrl.absoluteString
        : nil,
      fileName: url.lastPathComponent,
      fileSize: Int64(resources?.fileSize ?? 0),
      hasLyrics: FileManager.default.fileExists(atPath: lyricsUrl.path),
      id: "local:\(url.lastPathComponent)",
      lyricsUrl: FileManager.default.fileExists(atPath: lyricsUrl.path) ? lyricsUrl.absoluteString : nil,
      localUrl: url.absoluteString,
      sampleRate: sampleRate.flatMap { $0 > 0 ? $0 : nil },
      source: .local,
      sourceLabel: "Local",
      title: title,
      trackNo: numberValue(markers: ["trkn", "track", "trck"], in: asset.metadata)
    )
  }

  private static func stringValue(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) -> String? {
    metadata.first(where: { $0.identifier == identifier })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func stringValue(markers: [String], in metadata: [AVMetadataItem]) -> String? {
    metadata.first(where: { item in
      let identifier = item.identifier?.rawValue.lowercased() ?? ""
      let key = item.key.map { String(describing: $0).lowercased() } ?? ""
      return markers.contains { identifier.contains($0) || key.contains($0) }
    })?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func streamDescription(_ track: AVAssetTrack?) -> AudioStreamBasicDescription? {
    guard let description = track?.formatDescriptions.first,
      let pointer = CMAudioFormatDescriptionGetStreamBasicDescription(description as! CMAudioFormatDescription)
    else {
      return nil
    }
    return pointer.pointee
  }

  private static func numberValue(markers: [String], in metadata: [AVMetadataItem]) -> Int? {
    guard let item = metadata.first(where: { item in
      let identifier = item.identifier?.rawValue.lowercased() ?? ""
      let key = item.key.map { String(describing: $0).lowercased() } ?? ""
      return markers.contains { identifier.contains($0) || key.contains($0) }
    }) else {
      return nil
    }
    if let value = item.numberValue?.intValue, value > 0 { return value }
    if let raw = item.stringValue?.split(separator: "/").first, let value = Int(raw), value > 0 { return value }
    guard let data = item.dataValue, data.count >= 4 else { return nil }
    let bytes = [UInt8](data)
    let value = Int(bytes[2]) << 8 | Int(bytes[3])
    return value > 0 ? value : nil
  }

  private static func artwork(in metadata: [AVMetadataItem], sourceUrl: URL) -> String? {
    guard let data = metadata.first(where: { $0.identifier == .commonIdentifierArtwork })?.dataValue,
      UIImage(data: data) != nil
    else {
      return nil
    }
    let digest = SHA256.hash(data: Data(sourceUrl.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("echo-native-artwork", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let extensionName = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
    let destination = directory.appendingPathComponent(digest).appendingPathExtension(extensionName)
    if !FileManager.default.fileExists(atPath: destination.path) {
      try? data.write(to: destination, options: .atomic)
    }
    return destination.absoluteString
  }

  private static func embeddedMetadata(for audioUrl: URL) -> EmbeddedMetadata? {
    guard let data = try? Data(contentsOf: embeddedMetadataUrl(for: audioUrl)) else { return nil }
    return try? JSONDecoder().decode(EmbeddedMetadata.self, from: data)
  }

  private static func embeddedMetadataUrl(for audioUrl: URL) -> URL {
    audioUrl.appendingPathExtension("echo-metadata.json")
  }

  private static func embeddedArtworkUrl(for audioUrl: URL, extensionName: String) -> URL {
    audioUrl.appendingPathExtension("echo-artwork.\(extensionName)")
  }

  private static func sanitized(_ name: String) -> String {
    let value = name.replacingOccurrences(of: #"[\\/:*?\"<>|#%]"#, with: "_", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? "track-\(Int(Date().timeIntervalSince1970))" : value
  }

  private static func uniqueDestination(for fileName: String) -> URL {
    let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    let ext = URL(fileURLWithPath: fileName).pathExtension
    var destination = directory.appendingPathComponent(fileName)
    var index = 2
    while FileManager.default.fileExists(atPath: destination.path) {
      let next = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
      destination = directory.appendingPathComponent(next)
      index += 1
    }
    return destination
  }
}

@MainActor
private final class EchoNativeDocumentImporter: NSObject, UIDocumentPickerDelegate {
  private weak var presenter: UIViewController?
  private var continuation: CheckedContinuation<[URL], Never>?

  init(presenter: UIViewController) {
    self.presenter = presenter
  }

  func pickAudioFiles() async -> [URL] {
    await pickFiles(contentTypes: [.audio], allowsMultipleSelection: true)
  }

  func pickFiles(contentTypes: [UTType], allowsMultipleSelection: Bool) async -> [URL] {
    guard presenter != nil else { return [] }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
      picker.allowsMultipleSelection = allowsMultipleSelection
      picker.delegate = self
      presenter?.present(picker, animated: true)
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    continuation?.resume(returning: urls)
    continuation = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    continuation?.resume(returning: [])
    continuation = nil
  }
}

enum EchoNativeStreamCache {
  private static let audioExtensions = ["aac", "aiff", "caf", "flac", "m4a", "mp3", "mp4", "wav"]

  static func file(for remoteUrl: URL, track: EchoNativeCoreTrack) async throws -> URL {
    let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("echo-native-streams", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let cacheKey = "v3|\(track.source.rawValue)|\(remoteUrl.host ?? "")|\(remoteUrl.port ?? 0)|\(track.id)"
    let digest = SHA256.hash(data: Data(cacheKey.utf8)).prefix(16)
      .map { String(format: "%02x", $0) }
      .joined()
    let base = directory.appendingPathComponent(digest)
    for ext in audioExtensions {
      let cached = base.appendingPathExtension(ext)
      if FileManager.default.fileExists(atPath: cached.path), (try? AVAudioFile(forReading: cached)) != nil {
        return cached
      }
    }
    let (temporary, response) = try await URLSession.shared.download(from: remoteUrl)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw EchoNativeNetworkError.invalidResponse
    }
    guard let ext = detectedExtension(
      file: temporary,
      mimeType: response.mimeType?.lowercased() ?? "",
      remoteExtension: remoteUrl.pathExtension.lowercased(),
      codec: track.codec?.lowercased()
    ) else {
      throw EchoNativeNetworkError.invalidResponse
    }
    let destination = base.appendingPathExtension(ext)
    try? FileManager.default.removeItem(at: destination)
    try FileManager.default.moveItem(at: temporary, to: destination)
    guard (try? AVAudioFile(forReading: destination)) != nil else {
      try? FileManager.default.removeItem(at: destination)
      throw EchoNativeNetworkError.invalidResponse
    }
    return destination
  }

  private static func detectedExtension(
    file: URL,
    mimeType: String,
    remoteExtension: String,
    codec: String?
  ) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    let header = (try? handle.read(upToCount: 16)) ?? Data()
    try? handle.close()
    let bytes = [UInt8](header)
    if bytes.starts(with: [0x66, 0x4c, 0x61, 0x43]) { return "flac" }
    if bytes.starts(with: [0x63, 0x61, 0x66, 0x66]) { return "caf" }
    if bytes.count >= 12, Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46],
      Array(bytes[8..<12]) == [0x57, 0x41, 0x56, 0x45] { return "wav" }
    if bytes.count >= 12, Array(bytes[0..<4]) == [0x46, 0x4f, 0x52, 0x4d],
      ["AIFF", "AIFC"].contains(String(bytes: bytes[8..<12], encoding: .ascii) ?? "") { return "aiff" }
    if bytes.count >= 8, Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] { return "m4a" }
    if bytes.count >= 2, bytes[0] == 0xff, bytes[1] & 0xf6 == 0xf0 { return "aac" }
    if bytes.count >= 2, bytes[0] == 0xff, bytes[1] & 0xe0 == 0xe0 { return "mp3" }
    let mimeExtensions = [
      "audio/aac": "aac", "audio/aiff": "aiff", "audio/flac": "flac", "audio/mp4": "m4a",
      "audio/mpeg": "mp3", "audio/wav": "wav", "audio/x-aiff": "aiff", "audio/x-caf": "caf",
      "audio/x-flac": "flac", "audio/x-m4a": "m4a", "audio/x-wav": "wav",
    ]
    if let ext = mimeExtensions[mimeType.components(separatedBy: ";")[0]] { return ext }
    if let ext = [remoteExtension, codec].compactMap({ $0 }).first(where: { audioExtensions.contains($0) }) { return ext }
    return nil
  }
}
