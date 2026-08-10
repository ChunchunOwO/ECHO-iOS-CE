import AVFoundation
import AVKit
import CoreMedia
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import QuartzCore
import UIKit

@MainActor
final class EchoNativeDesktopLyricsController: NSObject, @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
  struct Configuration: Equatable {
    var animation = "flow"
    var background = "artwork"
    var enabled = false
    var fontName = ""
    var fontSize = 32.0
    var heightScale = 0.36
    var language = "zh"
    var onlyWhilePlaying = true
    var position = "bottom"
    var rainbowGradient = false
    var showMetadata = true
    var themeColorHex = "69508F"
    var timedReveal = true
    var transitionAnimation = true
    var visualizer = "off"
    var widthScale = 1.0
  }

  private static let artworkCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 12
    cache.totalCostLimit = 48 * 1_024 * 1_024
    return cache
  }()
  private let displayLayer = AVSampleBufferDisplayLayer()
  private let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 108, height: 32))
  private var pictureInPictureController: AVPictureInPictureController?
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private var renderTimer: Timer?
  private var renderTimerInterval = 0.0
  private var configuration = Configuration()
  private var importedBackgroundImage: UIImage?
  private var artworkImage: UIImage?
  private var artworkBackgroundImage: UIImage?
  private var artworkURL = ""
  private var artworkTask: Task<Void, Never>?
  private var artworkRetryAfter = 0.0
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var title = ""
  private var artist = ""
  private var trackKey = ""
  private var previousLyric = ""
  private var currentLyric = ""
  private var activeLyricIndex = 0
  private var currentLineStartMs = -1.0
  private var nextLineStartMs = -1.0
  private var positionMs = 0.0
  private var positionUpdatedAt = CACurrentMediaTime()
  private var isPlaying = false
  private var peakDb = -120.0
  private var rmsDb = -120.0
  private var durationMs = 0.0
  private var userDismissed = false
  private var programmaticStopPending = false
  private var restoreRequested = false
  private var startRequested = false
  private var startRetryAfter = 0.0
  private var hasRenderedFrame = false
  private var lyricTransitionStartedAt = CACurrentMediaTime()

  override init() {
    super.init()
    displayLayer.videoGravity = .resizeAspectFill
    guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.requiresLinearPlayback = true
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    pictureInPictureController = controller
    pictureInPicturePossibleObservation = controller.observe(\AVPictureInPictureController.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
      guard controller.isPictureInPicturePossible else { return }
      Task { @MainActor in self?.startIfNeeded() }
    }
  }

  deinit {
    renderTimer?.invalidate()
    pictureInPicturePossibleObservation?.invalidate()
    artworkTask?.cancel()
  }

  func attach(to container: UIView) {
    if hostView.superview !== container {
      hostView.removeFromSuperview()
      container.insertSubview(hostView, at: 0)
    }
    hostView.isUserInteractionEnabled = false
    hostView.backgroundColor = .clear
    updateHostGeometry()
    if displayLayer.superlayer !== hostView.layer {
      displayLayer.removeFromSuperlayer()
      hostView.layer.addSublayer(displayLayer)
    }
    displayLayer.frame = hostView.bounds
    installControlTimebase()
    refreshPresentation()
  }

  func configure(_ next: Configuration, importedBackgroundImage: UIImage?) {
    let wasEnabled = configuration.enabled
    let appearanceChanged = configuration != next
    let canvasSizeChanged = canvasWidth(for: configuration.widthScale) != canvasWidth(for: next.widthScale)
      || canvasHeight(for: configuration.heightScale) != canvasHeight(for: next.heightScale)
    let imageChanged = self.importedBackgroundImage !== importedBackgroundImage
    configuration = next
    self.importedBackgroundImage = importedBackgroundImage
    if next.background == "artwork" { loadArtworkIfNeeded() }
    updateHostGeometry()
    if !next.enabled {
      stop()
      return
    }
    if !wasEnabled || appearanceChanged || imageChanged { userDismissed = false }
    if canvasSizeChanged, pictureInPictureController?.isPictureInPictureActive == true {
      programmaticStopPending = true
      pictureInPictureController?.stopPictureInPicture()
      return
    }
    refreshPresentation()
  }

  func update(
    trackKey: String,
    title: String,
    artist: String,
    artworkURL: String,
    lines: [EchoNativeMetadataService.LyricLine],
    activeIndex: Int,
    isPlaying: Bool,
    peakDb: Double,
    rmsDb: Double,
    durationMs: Double,
    positionMs: Double
  ) {
    if self.trackKey != trackKey {
      self.trackKey = trackKey
      userDismissed = false
    }
    self.title = title
    self.artist = artist
    if self.artworkURL != artworkURL {
      self.artworkURL = artworkURL
      artworkImage = nil
      artworkBackgroundImage = nil
      artworkTask?.cancel()
      artworkTask = nil
      artworkRetryAfter = 0
      loadArtworkIfNeeded()
    }
    self.isPlaying = isPlaying
    self.peakDb = peakDb
    self.rmsDb = rmsDb
    self.durationMs = durationMs
    self.positionMs = positionMs
    positionUpdatedAt = CACurrentMediaTime()
    let nextLyric = lines.indices.contains(activeIndex) ? lines[activeIndex].text : ""
    if activeLyricIndex != activeIndex || currentLyric != nextLyric {
      previousLyric = currentLyric
      activeLyricIndex = activeIndex
      lyricTransitionStartedAt = CACurrentMediaTime()
    }
    currentLyric = nextLyric
    currentLineStartMs = lines.indices.contains(activeIndex) ? lines[activeIndex].milliseconds : -1
    nextLineStartMs = lines.dropFirst(max(0, activeIndex + 1)).first(where: { $0.milliseconds >= 0 })?.milliseconds ?? -1

    loadArtworkIfNeeded()
    refreshPresentation()
  }

  func stop() {
    userDismissed = false
    stopPresentation()
  }

  private var hasTrack: Bool {
    !trackKey.isEmpty || !currentLyric.isEmpty || !title.isEmpty
  }

  private var shouldPresent: Bool {
    configuration.enabled
      && (!configuration.onlyWhilePlaying || isPlaying || !hasTrack)
  }

  private var needsContinuousRendering: Bool {
    if !hasRenderedFrame || pictureInPictureController?.isPictureInPictureActive != true { return true }
    let continuousEffect = isPlaying && (
      configuration.timedReveal
        || configuration.rainbowGradient
        || configuration.visualizer != "off"
        || currentLineStartMs < 0
    )
    let lyricTransition = configuration.transitionAnimation && CACurrentMediaTime() - lyricTransitionStartedAt < 0.35
    return hasTrack && (continuousEffect || lyricTransition)
  }

  private func refreshPresentation() {
    guard shouldPresent, !userDismissed else {
      stopPresentation()
      return
    }
    startRenderTimer(interval: needsContinuousRendering ? 1.0 / 30.0 : 0.5)
    renderFrame()
    startIfNeeded()
  }

  private func stopPresentation() {
    renderTimer?.invalidate()
    renderTimer = nil
    renderTimerInterval = 0
    if pictureInPictureController?.isPictureInPictureActive == true {
      programmaticStopPending = true
      pictureInPictureController?.stopPictureInPicture()
    } else {
      startRequested = false
    }
    displayLayer.flushAndRemoveImage()
    hasRenderedFrame = false
  }

  private func startIfNeeded() {
    guard configuration.enabled,
      !userDismissed,
      shouldPresent,
      let pictureInPictureController,
      !pictureInPictureController.isPictureInPictureActive,
      !startRequested,
      hasRenderedFrame,
      CACurrentMediaTime() >= startRetryAfter,
      pictureInPictureController.isPictureInPicturePossible
    else { return }
    startRequested = true
    activateAudioSession()
    pictureInPictureController.invalidatePlaybackState()
    CATransaction.flush()
    pictureInPictureController.startPictureInPicture()
  }

  private func installControlTimebase() {
    guard displayLayer.controlTimebase == nil else { return }
    var timebase: CMTimebase?
    let clock = CMClockGetHostTimeClock()
    guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: clock, timebaseOut: &timebase) == noErr,
      let timebase
    else { return }
    CMTimebaseSetTime(timebase, time: CMClockGetTime(clock))
    CMTimebaseSetRate(timebase, rate: 1)
    displayLayer.controlTimebase = timebase
  }

  private func activateAudioSession() {
    let session = AVAudioSession.sharedInstance()
    if session.category != .playback {
      try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
    }
    try? session.setActive(true)
  }

  private func startRenderTimer(interval: TimeInterval) {
    if renderTimer != nil, abs(renderTimerInterval - interval) < 0.001 { return }
    renderTimer?.invalidate()
    renderTimerInterval = interval
    let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPresentation() }
    }
    timer.tolerance = interval >= 0.5 ? 0.05 : 1.0 / 120.0
    RunLoop.main.add(timer, forMode: .common)
    renderTimer = timer
  }

  private func renderFrame() {
    guard shouldPresent else { return }
    if displayLayer.status == .failed {
      pictureInPictureController?.invalidatePlaybackState()
      displayLayer.flushAndRemoveImage()
      hasRenderedFrame = false
    }
    guard displayLayer.isReadyForMoreMediaData, let sampleBuffer = makeSampleBuffer() else { return }
    displayLayer.enqueue(sampleBuffer)
    hasRenderedFrame = true
  }

  private func makeSampleBuffer() -> CMSampleBuffer? {
    let width = canvasWidth(for: configuration.widthScale)
    let height = canvasHeight(for: configuration.heightScale)
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    guard CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &pixelBuffer
    ) == kCVReturnSuccess,
      let pixelBuffer,
      let context = makeContext(for: pixelBuffer, width: width, height: height)
    else { return nil }

    drawFrame(in: context, width: width, height: height)
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0))

    var formatDescription: CMVideoFormatDescription?
    guard CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    ) == noErr,
      let formatDescription
    else { return nil }

    var timing = CMSampleTimingInfo(
      duration: CMTime(seconds: max(1.0 / 30.0, renderTimerInterval * 2), preferredTimescale: 600),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    ) == noErr else { return nil }
    if let sampleBuffer,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
      CFArrayGetCount(attachments) > 0 {
      let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        attachment,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
      )
    }
    return sampleBuffer
  }

  private func makeContext(for pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> CGContext? {
    CVPixelBufferLockBaseAddress(pixelBuffer, .init(rawValue: 0))
    guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0))
      return nil
    }
    guard let context = CGContext(
      data: baseAddress,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .init(rawValue: 0))
      return nil
    }
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setAllowsFontSmoothing(true)
    context.setShouldSmoothFonts(true)
    return context
  }

  private func drawFrame(in context: CGContext, width: Int, height: Int) {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let transitionProgress = min(1, max(0, (CACurrentMediaTime() - lyricTransitionStartedAt) / 0.28))
    drawBackground(in: context, bounds: bounds)
    guard hasTrack else {
      drawEmptyState(in: context, bounds: bounds)
      return
    }
    drawVisualizer(in: context, bounds: bounds)
    let inset = max(18, min(52, CGFloat(width) * 0.055))
    let coverSize = max(72, min(CGFloat(height) * 0.74, CGFloat(width) * 0.42))
    let gap = max(12, min(22, CGFloat(width) * 0.022))
    let contentY = contentY(height: height, contentHeight: coverSize)
    let cover = CGRect(x: max(8, inset - 8), y: contentY, width: coverSize, height: coverSize)
    let text = CGRect(
      x: cover.maxX + gap,
      y: contentY,
      width: max(40, CGFloat(width) - cover.maxX - gap - inset),
      height: coverSize
    )
    drawCover(in: cover, context: context)

    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    let textPanel = CGRect(x: text.minX, y: CGFloat(height) - text.maxY, width: text.width, height: text.height)
    let currentText = currentLyric.isEmpty
      ? (configuration.language == "en" ? "No lyric data" : "暂无歌曲数据")
      : currentLyric
    let metadata = [title, artist].filter { !$0.isEmpty }.joined(separator: "  /  ")
    let metadataFont = displayFont(size: min(24, max(14, coverSize * 0.11)), weight: .semibold)
    let metadataHeight: CGFloat = configuration.showMetadata && !metadata.isEmpty ? metadataFont.lineHeight + 4 : 0
    let metadataGap: CGFloat = metadataHeight > 0 ? min(8, coverSize * 0.04) : 0
    let availableLyricHeight = max(24, textPanel.height - metadataHeight - metadataGap)
    let lyricLineCount = max(1, currentText.components(separatedBy: .newlines).count)
    let lyricFontSize = min(fontSize, max(12, availableLyricHeight / (CGFloat(lyricLineCount) * 1.22)))
    let lyricFont = displayFont(size: lyricFontSize, weight: .bold)
    let lyricHeight = min(availableLyricHeight, lyricFont.lineHeight * CGFloat(lyricLineCount) + 12)
    let groupHeight = metadataHeight + metadataGap + lyricHeight
    let groupY = textPanel.midY - groupHeight / 2
    if metadataHeight > 0 {
      drawCenteredText(
        metadata,
        in: CGRect(x: textPanel.minX, y: groupY, width: textPanel.width, height: metadataHeight),
        font: metadataFont,
        color: .white.withAlphaComponent(0.68),
        context: context
      )
    }
    let lyricRect = CGRect(
      x: textPanel.minX,
      y: groupY + metadataHeight + metadataGap,
      width: textPanel.width,
      height: lyricHeight
    )
    let transitionDistance: CGFloat = configuration.transitionAnimation && configuration.animation == "flow" ? 18 : 0
    let outgoingOffset = CGFloat(transitionProgress) * transitionDistance
    let incomingOffset = CGFloat(1 - transitionProgress) * transitionDistance
    if configuration.transitionAnimation, !previousLyric.isEmpty, transitionProgress < 1 {
      let scale = configuration.animation == "pulse" ? CGFloat(1 - transitionProgress * 0.04) : 1
      context.saveGState()
      context.translateBy(x: lyricRect.midX, y: lyricRect.midY)
      context.scaleBy(x: scale, y: scale)
      context.translateBy(x: -lyricRect.midX, y: -lyricRect.midY)
      drawCenteredText(
        previousLyric,
        in: lyricRect.offsetBy(dx: 0, dy: -outgoingOffset),
        font: lyricFont,
        color: .white.withAlphaComponent(1 - transitionProgress),
        context: context
      )
      context.restoreGState()
    }
    let lyricAlpha = configuration.transitionAnimation ? transitionProgress : 1
    let incomingScale = configuration.transitionAnimation && configuration.animation == "pulse"
      ? CGFloat(0.96 + transitionProgress * 0.04)
      : 1
    context.saveGState()
    context.translateBy(x: lyricRect.midX, y: lyricRect.midY)
    context.scaleBy(x: incomingScale, y: incomingScale)
    context.translateBy(x: -lyricRect.midX, y: -lyricRect.midY)
    if configuration.timedReveal, !currentLyric.isEmpty {
      drawTimedText(
        currentText,
        in: lyricRect.offsetBy(dx: 0, dy: incomingOffset),
        progress: lyricProgress,
        scrollProgress: lyricScrollProgress,
        rainbow: configuration.rainbowGradient,
        rainbowPhase: rainbowPhase,
        alpha: lyricAlpha,
        font: lyricFont,
        context: context
      )
    } else {
      drawScrollingText(
        currentText,
        in: lyricRect.offsetBy(dx: 0, dy: incomingOffset),
        progress: lyricScrollProgress,
        font: lyricFont,
        color: .white.withAlphaComponent(lyricAlpha),
        rainbow: configuration.rainbowGradient,
        rainbowPhase: rainbowPhase,
        context: context
      )
    }
    context.restoreGState()
    context.restoreGState()
  }

  private func drawCover(in rect: CGRect, context: CGContext) {
    let radius = min(24, rect.width * 0.12)
    context.saveGState()
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    if let image = artworkImage?.cgImage {
      drawAspectFill(image, in: rect, context: context)
    } else {
      let colors = [
        UIColor(red: 0.78, green: 0.22, blue: 0.34, alpha: 1).cgColor,
        UIColor(red: 0.12, green: 0.49, blue: 0.54, alpha: 1).cgColor,
        UIColor(red: 0.95, green: 0.64, blue: 0.32, alpha: 1).cgColor,
      ] as CFArray
      if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.56, 1]) {
        context.drawLinearGradient(
          gradient,
          start: CGPoint(x: rect.minX, y: rect.minY),
          end: CGPoint(x: rect.maxX, y: rect.maxY),
          options: []
        )
      }
      context.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
      context.setLineWidth(max(2, rect.width * 0.025))
      for ring in 1...3 {
        context.strokeEllipse(in: rect.insetBy(dx: rect.width * CGFloat(ring) * 0.12, dy: rect.height * CGFloat(ring) * 0.12))
      }
      let bars: [CGFloat] = [0.42, 0.7, 1.0, 0.64, 0.48]
      let barWidth = rect.width * 0.055
      let gap = barWidth * 0.72
      let totalWidth = CGFloat(bars.count) * barWidth + CGFloat(bars.count - 1) * gap
      context.setFillColor(UIColor.white.withAlphaComponent(0.88).cgColor)
      for (index, heightScale) in bars.enumerated() {
        let height = rect.height * 0.34 * heightScale
        let bar = CGRect(
          x: rect.midX - totalWidth / 2 + CGFloat(index) * (barWidth + gap),
          y: rect.midY - height / 2,
          width: barWidth,
          height: height
        )
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        context.fillPath()
      }
    }
    context.restoreGState()
    context.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
    context.setLineWidth(1)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()
  }

  private func drawEmptyState(in context: CGContext, bounds: CGRect) {
    context.saveGState()
    context.translateBy(x: 0, y: bounds.height)
    context.scaleBy(x: 1, y: -1)
    let font = displayFont(size: min(30, max(20, bounds.height * 0.12)), weight: .bold)
    drawCenteredText(
      configuration.language == "en" ? "No song is playing" : "没有歌曲正在播放",
      in: bounds.insetBy(dx: max(24, bounds.width * 0.08), dy: 0),
      font: font,
      color: .white.withAlphaComponent(0.9),
      context: context
    )
    context.restoreGState()
  }

  private func loadArtworkIfNeeded() {
    guard artworkImage == nil, !artworkURL.isEmpty, artworkTask == nil,
      CACurrentMediaTime() >= artworkRetryAfter else { return }
    let expectedURL = artworkURL
    if let cached = Self.artworkCache.object(forKey: expectedURL as NSString) {
      artworkImage = cached
      artworkBackgroundImage = blurredImage(cached)
      return
    }
    artworkTask = Task { [weak self] in
      let data = try? await EchoNativeMetadataService.artworkData(from: expectedURL)
      guard !Task.isCancelled else { return }
      guard let self, self.artworkURL == expectedURL else { return }
      let image = data.flatMap(UIImage.init(data:))
      self.artworkImage = image
      self.artworkBackgroundImage = image.flatMap(self.blurredImage)
      self.artworkTask = nil
      if let image {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        Self.artworkCache.setObject(image, forKey: expectedURL as NSString, cost: cost)
      } else {
        self.artworkRetryAfter = CACurrentMediaTime() + 5
      }
      self.renderFrame()
    }
  }

  private func blurredImage(_ image: UIImage) -> UIImage? {
    guard let input = CIImage(image: image) else { return image }
    let filter = CIFilter.gaussianBlur()
    filter.inputImage = input.clampedToExtent()
    filter.radius = 28
    guard let output = filter.outputImage?.cropped(to: input.extent),
      let cgImage = imageContext.createCGImage(output, from: input.extent)
    else { return image }
    return UIImage(cgImage: cgImage)
  }

  private func drawBackground(in context: CGContext, bounds: CGRect) {
    if !hasTrack {
      drawThemeBackground(in: context, bounds: bounds)
      drawSakuraScattering(in: context, bounds: bounds)
      return
    }
    if configuration.background == "custom", let image = importedBackgroundImage?.cgImage {
      drawAspectFill(image, in: bounds, context: context)
      context.setFillColor(UIColor.black.withAlphaComponent(0.2).cgColor)
      context.fill(bounds)
      return
    }
    if configuration.background == "artwork", let image = artworkBackgroundImage?.cgImage {
      drawAspectFill(image, in: bounds, context: context)
      context.setFillColor(UIColor.black.withAlphaComponent(0.26).cgColor)
      context.fill(bounds)
      return
    }
    drawThemeBackground(in: context, bounds: bounds)
  }

  private func drawThemeBackground(in context: CGContext, bounds: CGRect) {
    let base = themeUIColor
    context.setFillColor(base.cgColor)
    context.fill(bounds)
    var hue: CGFloat = 0
    var saturation: CGFloat = 0
    var brightness: CGFloat = 0
    var alpha: CGFloat = 1
    base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        UIColor(hue: hue, saturation: min(1, saturation * 1.08), brightness: max(0.12, brightness * 0.42), alpha: 1).cgColor,
        UIColor(hue: hue, saturation: min(1, saturation * 1.02), brightness: max(0.2, brightness * 0.88), alpha: 1).cgColor,
      ] as CFArray,
      locations: [0, 1]
    )
    if let gradient {
      context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
    }
  }

  private var themeUIColor: UIColor {
    let value = UInt64(configuration.themeColorHex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x69508F
    return UIColor(
      red: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }

  private func drawSakuraScattering(in context: CGContext, bounds: CGRect) {
    let points: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
      (0.12, 0.18, 0.7, 0.8), (0.28, 0.76, -0.4, 0.62), (0.48, 0.23, 0.2, 0.48),
      (0.68, 0.72, -0.7, 0.7), (0.86, 0.2, 0.45, 0.56), (0.9, 0.84, -0.2, 0.42),
    ]
    let petalColor = themeUIColor.withAlphaComponent(0.36)
    for (x, y, angle, scale) in points {
      let radius = max(8, min(bounds.width, bounds.height) * 0.045 * scale)
      context.saveGState()
      context.translateBy(x: bounds.width * x, y: bounds.height * y)
      context.rotate(by: angle)
      for index in 0..<5 {
        context.saveGState()
        context.rotate(by: CGFloat(index) * (.pi * 2 / 5))
        context.setFillColor(petalColor.cgColor)
        context.fillEllipse(in: CGRect(x: -radius * 0.32, y: -radius * 0.95, width: radius * 0.64, height: radius * 0.9))
        context.restoreGState()
      }
      context.setFillColor(UIColor.white.withAlphaComponent(0.62).cgColor)
      context.fillEllipse(in: CGRect(x: -radius * 0.18, y: -radius * 0.18, width: radius * 0.36, height: radius * 0.36))
      context.restoreGState()
    }
  }

  private func drawVisualizer(in context: CGContext, bounds: CGRect) {
    guard configuration.visualizer != "off" else { return }
    let time = CACurrentMediaTime()
    let level = visualizationLevel
    context.saveGState()
    context.setBlendMode(.screen)
    switch configuration.visualizer {
    case "wave":
      for layer in 0..<2 {
        let path = CGMutablePath()
        let amplitude = bounds.height * (0.06 + level * 0.12) * (layer == 0 ? 1 : 0.65)
        for step in 0...72 {
          let progress = CGFloat(step) / 72
          let x = bounds.minX + bounds.width * progress
          let phase = CGFloat(time * (layer == 0 ? 2.2 : -1.6)) + progress * .pi * (layer == 0 ? 4 : 6)
          let y = bounds.midY + sin(phase) * amplitude
          if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
          else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.addPath(path)
        context.setStrokeColor(
          (layer == 0 ? UIColor(red: 0.58, green: 0.94, blue: 1, alpha: 0.2) : UIColor(red: 1, green: 0.66, blue: 0.83, alpha: 0.14)).cgColor
        )
        context.setLineWidth(layer == 0 ? 3 : 2)
        context.strokePath()
      }
    case "pulse":
      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      for ring in 0..<4 {
        let cycle = CGFloat((time * 0.45 + Double(ring) * 0.22).truncatingRemainder(dividingBy: 1))
        let radius = min(bounds.width, bounds.height) * (0.15 + cycle * (0.32 + level * 0.12))
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.setStrokeColor(UIColor(red: 0.68, green: 0.94, blue: 0.82, alpha: (1 - cycle) * 0.16).cgColor)
        context.setLineWidth(2 + level * 3)
        context.strokeEllipse(in: rect)
      }
    default:
      let count = 28
      let gap = max(3, bounds.width * 0.006)
      let width = (bounds.width - gap * CGFloat(count + 1)) / CGFloat(count)
      for index in 0..<count {
        let phase = CGFloat(time * 3.2) + CGFloat(index) * 0.62
        let energy = 0.25 + abs(sin(phase)) * 0.75
        let height = bounds.height * (0.08 + level * 0.32 * energy)
        let rect = CGRect(
          x: bounds.minX + gap + CGFloat(index) * (width + gap),
          y: bounds.minY + gap,
          width: width,
          height: height
        )
        let color = index.isMultiple(of: 3)
          ? UIColor(red: 1, green: 0.72, blue: 0.84, alpha: 0.14)
          : UIColor(red: 0.62, green: 0.92, blue: 1, alpha: 0.16)
        context.setFillColor(color.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: width / 2, cornerHeight: width / 2, transform: nil))
        context.fillPath()
      }
    }
    context.restoreGState()
  }

  private var visualizationLevel: CGFloat {
    guard isPlaying else { return 0.05 }
    if rmsDb > -119 {
      let rms = max(0.08, min(1, (rmsDb + 60) / 60))
      let peak = max(0.08, min(1, (peakDb + 60) / 60))
      return CGFloat(rms * 0.72 + peak * 0.28)
    }
    return 0.24
  }

  private func drawAspectFill(_ image: CGImage, in bounds: CGRect, context: CGContext) {
    let imageSize = CGSize(width: image.width, height: image.height)
    let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    context.draw(image, in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
  }

  private var fontSize: CGFloat {
    CGFloat(max(18, min(48, configuration.fontSize)))
  }

  private func displayFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    guard !configuration.fontName.isEmpty, let font = UIFont(name: configuration.fontName, size: size) else {
      return UIFont.systemFont(ofSize: size, weight: weight)
    }
    return font
  }

  private var lyricProgress: Double {
    guard currentLineStartMs >= 0 else { return 1 }
    let end = nextLineStartMs > currentLineStartMs ? nextLineStartMs : durationMs
    guard end > currentLineStartMs else { return 1 }
    let interpolatedPosition = min(durationMs, positionMs + (isPlaying ? (CACurrentMediaTime() - positionUpdatedAt) * 1000 : 0))
    return max(0, min(1, (interpolatedPosition - currentLineStartMs) / (end - currentLineStartMs)))
  }

  private var lyricScrollProgress: Double {
    guard currentLineStartMs < 0 else { return lyricProgress }
    return min(1, max(0, (CACurrentMediaTime() - lyricTransitionStartedAt) / 8))
  }

  private var rainbowPhase: CGFloat {
    CGFloat((CACurrentMediaTime() * 0.12).truncatingRemainder(dividingBy: 1))
  }

  private func drawCenteredText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, context: CGContext) {
    let measured = (text as NSString).boundingRect(
      with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font],
      context: nil
    )
    let height = min(rect.height, max(font.lineHeight, measured.height))
    drawText(text, in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height), font: font, color: color, context: context)
  }

  private func contentY(height: Int, contentHeight: CGFloat) -> CGFloat {
    let inset = max(14, min(34, (CGFloat(height) - contentHeight) / 2))
    switch configuration.position {
    case "top": return inset
    case "center": return CGFloat(height) / 2 - contentHeight / 2
    default: return CGFloat(height) - contentHeight - inset
    }
  }

  private func canvasWidth(for scale: Double) -> Int {
    let clamped = max(0.2, min(1.0, scale))
    return max(192, min(960, Int((960 * clamped).rounded()) / 2 * 2))
  }

  private func canvasHeight(for scale: Double) -> Int {
    let clamped = max(0.33, min(1.0, scale))
    return max(180, min(540, Int((540 * clamped).rounded()) / 2 * 2))
  }

  private func updateHostGeometry() {
    let width = CGFloat(canvasWidth(for: configuration.widthScale))
    let height = CGFloat(canvasHeight(for: configuration.heightScale))
    let hostHeight: CGFloat = 36
    hostView.frame = CGRect(x: 0, y: 0, width: hostHeight * width / height, height: hostHeight)
    displayLayer.frame = hostView.bounds
  }

  private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, context: CGContext) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .left
    paragraph.lineBreakMode = .byTruncatingTail
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    (text as NSString).draw(in: rect, withAttributes: [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ])
  }

  private func drawScrollingText(
    _ text: String,
    in rect: CGRect,
    progress: Double,
    font: UIFont,
    color: UIColor,
    rainbow: Bool,
    rainbowPhase: CGFloat,
    context: CGContext
  ) {
    let lines = text.components(separatedBy: .newlines)
    let height = min(rect.height, font.lineHeight * CGFloat(max(1, lines.count)))
    let originY = rect.midY - height / 2
    for (index, line) in lines.enumerated() {
      let lineRect = CGRect(
        x: rect.minX,
        y: originY + CGFloat(index) * font.lineHeight,
        width: rect.width,
        height: font.lineHeight
      )
      let measuredWidth = ceil((line as NSString).size(withAttributes: [.font: font]).width) + 2
      let offset = lyricScrollOffset(lineWidth: measuredWidth, viewportWidth: lineRect.width, progress: progress)
      context.saveGState()
      context.clip(to: lineRect)
      context.translateBy(x: -offset, y: 0)
      let contentRect = CGRect(x: lineRect.minX, y: lineRect.minY, width: max(lineRect.width, measuredWidth), height: lineRect.height)
      if rainbow {
        drawRainbowText(line, in: contentRect, lineWidth: measuredWidth, phase: rainbowPhase, alpha: color.cgColor.alpha, font: font, context: context)
      } else {
        drawText(line, in: contentRect, font: font, color: color, context: context)
      }
      context.restoreGState()
    }
  }

  private func drawTimedText(
    _ text: String,
    in rect: CGRect,
    progress: Double,
    scrollProgress: Double,
    rainbow: Bool,
    rainbowPhase: CGFloat,
    alpha: Double,
    font: UIFont,
    context: CGContext
  ) {
    let lines = text.components(separatedBy: .newlines)
    let height = min(rect.height, font.lineHeight * CGFloat(max(1, lines.count)))
    let originY = rect.midY - height / 2
    for (index, line) in lines.enumerated() {
      let lineRect = CGRect(
        x: rect.minX,
        y: originY + CGFloat(index) * font.lineHeight,
        width: rect.width,
        height: font.lineHeight
      )
      let lineWidth = ceil((line as NSString).size(withAttributes: [.font: font]).width) + 2
      let contentRect = CGRect(x: lineRect.minX, y: lineRect.minY, width: max(lineRect.width, lineWidth), height: lineRect.height)
      let offset = lyricScrollOffset(lineWidth: lineWidth, viewportWidth: lineRect.width, progress: scrollProgress)
      context.saveGState()
      context.clip(to: lineRect)
      context.translateBy(x: -offset, y: 0)
      drawText(line, in: contentRect, font: font, color: UIColor(white: 0.52, alpha: alpha), context: context)
      context.clip(to: CGRect(x: contentRect.minX, y: contentRect.minY, width: lineWidth * CGFloat(progress), height: contentRect.height))
      if rainbow {
        drawRainbowText(line, in: contentRect, lineWidth: lineWidth, phase: rainbowPhase, alpha: alpha, font: font, context: context)
      } else {
        drawText(line, in: contentRect, font: font, color: .white.withAlphaComponent(alpha), context: context)
      }
      context.restoreGState()
    }
  }

  private func drawRainbowText(_ text: String, in rect: CGRect, lineWidth: CGFloat, phase: CGFloat, alpha: CGFloat, font: UIFont, context: CGContext) {
    let stops = 0...8
    guard let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: stops.map { rainbowColor(position: CGFloat($0) / 8, phase: phase, alpha: alpha).cgColor } as CFArray,
      locations: stops.map { CGFloat($0) / 8 }
    ) else { return }
    context.saveGState()
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    drawText(text, in: rect, font: font, color: .white.withAlphaComponent(alpha), context: context)
    context.setBlendMode(.sourceIn)
    context.drawLinearGradient(
      gradient,
      start: CGPoint(x: rect.minX, y: rect.midY),
      end: CGPoint(x: rect.minX + max(1, lineWidth), y: rect.midY),
      options: [.drawsAfterEndLocation]
    )
    context.endTransparencyLayer()
    context.restoreGState()
  }

  private func rainbowColor(position: CGFloat, phase: CGFloat, alpha: CGFloat) -> UIColor {
    let hue = (position + phase).truncatingRemainder(dividingBy: 1)
    return UIColor(hue: hue < 0 ? hue + 1 : hue, saturation: 0.38, brightness: 1, alpha: alpha)
  }

  private func lyricScrollOffset(lineWidth: CGFloat, viewportWidth: CGFloat, progress: Double) -> CGFloat {
    let maximum = max(0, lineWidth - viewportWidth)
    return min(maximum, max(0, lineWidth * CGFloat(progress) - viewportWidth * 0.78))
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    startRequested = false
    programmaticStopPending = false
    userDismissed = false
    if !hasTrack {
      hasRenderedFrame = false
      renderFrame()
    }
    if !shouldPresent { stopPresentation() }
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let shouldRestart = (programmaticStopPending || restoreRequested) && shouldPresent
    startRequested = false
    userDismissed = !programmaticStopPending && !restoreRequested
    programmaticStopPending = false
    restoreRequested = false
    renderTimer?.invalidate()
    renderTimer = nil
    displayLayer.flushAndRemoveImage()
    hasRenderedFrame = false
    if shouldRestart {
      refreshPresentation()
    }
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    startRequested = false
    startRetryAfter = CACurrentMediaTime() + 1
    stopPresentation()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
    restoreRequested = true
    completionHandler(true)
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {}

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

  func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
    !isPlaying
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}
