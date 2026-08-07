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
    var background = "theme"
    var enabled = false
    var fontSize = 26.0
    var heightScale = 0.36
    var onlyWhilePlaying = true
    var position = "bottom"
    var showMetadata = true
    var timedReveal = false
    var transitionAnimation = false
    var widthScale = 1.0
  }

  private let displayLayer = AVSampleBufferDisplayLayer()
  private let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 108, height: 32))
  private var pictureInPictureController: AVPictureInPictureController?
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private var renderTimer: Timer?
  private var configuration = Configuration()
  private var importedBackgroundImage: UIImage?
  private var artworkImage: UIImage?
  private var artworkBackgroundImage: UIImage?
  private var artworkURL = ""
  private var artworkTask: Task<Void, Never>?
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var title = ""
  private var artist = ""
  private var previousLyric = ""
  private var currentLyric = ""
  private var activeLyricIndex = 0
  private var currentLineStartMs = -1.0
  private var nextLineStartMs = -1.0
  private var positionMs = 0.0
  private var positionUpdatedAt = CACurrentMediaTime()
  private var isPlaying = false
  private var durationMs = 0.0
  private var userDismissed = false
  private var programmaticStopPending = false
  private var startRequested = false
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
    title: String,
    artist: String,
    artworkURL: String,
    lines: [EchoNativeMetadataService.LyricLine],
    activeIndex: Int,
    isPlaying: Bool,
    durationMs: Double,
    positionMs: Double
  ) {
    self.title = title
    self.artist = artist
    if self.artworkURL != artworkURL {
      self.artworkURL = artworkURL
      artworkImage = nil
      artworkBackgroundImage = nil
      artworkTask?.cancel()
      artworkTask = nil
      loadArtworkIfNeeded()
    }
    self.isPlaying = isPlaying
    self.durationMs = durationMs
    self.positionMs = positionMs
    positionUpdatedAt = CACurrentMediaTime()
    if activeLyricIndex != activeIndex {
      previousLyric = currentLyric
      activeLyricIndex = activeIndex
      lyricTransitionStartedAt = CACurrentMediaTime()
    }
    currentLyric = lines.indices.contains(activeIndex) ? lines[activeIndex].text : ""
    currentLineStartMs = lines.indices.contains(activeIndex) ? lines[activeIndex].milliseconds : -1
    nextLineStartMs = lines.dropFirst(max(0, activeIndex + 1)).first(where: { $0.milliseconds >= 0 })?.milliseconds ?? -1

    refreshPresentation()
  }

  func stop() {
    userDismissed = false
    stopPresentation()
  }

  private var hasContent: Bool {
    !currentLyric.isEmpty || !title.isEmpty
  }

  private var shouldPresent: Bool {
    configuration.enabled
      && hasContent
      && (!configuration.onlyWhilePlaying || isPlaying)
  }

  private func refreshPresentation() {
    guard shouldPresent, !userDismissed else {
      stopPresentation()
      return
    }
    startRenderTimer()
    renderFrame()
    activateAudioSession()
    startIfNeeded()
  }

  private func stopPresentation() {
    renderTimer?.invalidate()
    renderTimer = nil
    if pictureInPictureController?.isPictureInPictureActive == true {
      programmaticStopPending = true
      pictureInPictureController?.stopPictureInPicture()
    }
    displayLayer.flushAndRemoveImage()
  }

  private func startIfNeeded() {
    guard configuration.enabled,
      !userDismissed,
      hasContent,
      !(configuration.onlyWhilePlaying && !isPlaying),
      let pictureInPictureController,
      !pictureInPictureController.isPictureInPictureActive,
      !startRequested,
      pictureInPictureController.isPictureInPicturePossible
    else { return }
    startRequested = true
    activateAudioSession()
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

  private func startRenderTimer() {
    guard renderTimer == nil else { return }
    renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPresentation() }
    }
  }

  private func renderFrame() {
    guard hasContent, let sampleBuffer = makeSampleBuffer() else { return }
    if displayLayer.status == .failed {
      pictureInPictureController?.invalidatePlaybackState()
      displayLayer.flushAndRemoveImage()
    }
    displayLayer.enqueue(sampleBuffer)
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
      duration: CMTime(value: 1, timescale: 30),
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
    return context
  }

  private func drawFrame(in context: CGContext, width: Int, height: Int) {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let transitionProgress = min(1, max(0, (CACurrentMediaTime() - lyricTransitionStartedAt) / 0.28))
    drawBackground(in: context, bounds: bounds)
    let inset = max(18, min(52, CGFloat(width) * 0.055))
    let coverSize = max(64, min(CGFloat(height) - inset * 2, CGFloat(width) * 0.38))
    let gap = max(18, min(36, CGFloat(width) * 0.035))
    let contentY = contentY(height: height, contentHeight: coverSize)
    let cover = CGRect(x: inset, y: contentY, width: coverSize, height: coverSize)
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
    let currentText = currentLyric.isEmpty ? title : currentLyric
    let metadata = [title, artist].filter { !$0.isEmpty }.joined(separator: "  /  ")
    let metadataFont = UIFont.systemFont(ofSize: min(18, max(11, coverSize * 0.09)), weight: .semibold)
    let metadataHeight: CGFloat = configuration.showMetadata && !metadata.isEmpty ? metadataFont.lineHeight + 4 : 0
    let metadataGap: CGFloat = metadataHeight > 0 ? min(8, coverSize * 0.04) : 0
    let availableLyricHeight = max(24, textPanel.height - metadataHeight - metadataGap)
    let lyricLineCount = max(1, currentText.components(separatedBy: .newlines).count)
    let lyricFontSize = min(fontSize, max(12, availableLyricHeight / (CGFloat(lyricLineCount) * 1.22)))
    let lyricFont = UIFont.systemFont(ofSize: lyricFontSize, weight: .bold)
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
        alpha: lyricAlpha,
        font: lyricFont,
        context: context
      )
    } else {
      drawCenteredText(
        currentText,
        in: lyricRect.offsetBy(dx: 0, dy: incomingOffset),
        font: lyricFont,
        color: .white.withAlphaComponent(lyricAlpha),
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
      context.setFillColor(UIColor.black.withAlphaComponent(0.34).cgColor)
      context.fill(rect)
    }
    context.restoreGState()
    context.setStrokeColor(UIColor.white.withAlphaComponent(0.2).cgColor)
    context.setLineWidth(1)
    context.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.strokePath()
  }

  private func loadArtworkIfNeeded() {
    guard artworkImage == nil, !artworkURL.isEmpty, artworkTask == nil,
      let url = URL(string: artworkURL) else { return }
    let expectedURL = artworkURL
    artworkTask = Task { [weak self] in
      let data: Data?
      if url.isFileURL {
        data = try? Data(contentsOf: url)
      } else {
        data = try? await URLSession.shared.data(from: url).0
      }
      guard !Task.isCancelled else { return }
      guard let self, self.artworkURL == expectedURL else { return }
      let image = data.flatMap(UIImage.init(data:))
      self.artworkImage = image
      self.artworkBackgroundImage = image.flatMap(self.blurredImage)
      self.artworkTask = nil
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
    let gradient = CGGradient(
      colorsSpace: CGColorSpaceCreateDeviceRGB(),
      colors: [
        UIColor(red: 0.11, green: 0.04, blue: 0.08, alpha: 1).cgColor,
        UIColor(red: 0.46, green: 0.06, blue: 0.09, alpha: 1).cgColor,
      ] as CFArray,
      locations: [0, 1]
    )
    if let gradient {
      context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: bounds.minY), end: CGPoint(x: bounds.maxX, y: bounds.maxY), options: [])
    }
  }

  private func drawAspectFill(_ image: CGImage, in bounds: CGRect, context: CGContext) {
    let imageSize = CGSize(width: image.width, height: image.height)
    let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    context.draw(image, in: CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height))
  }

  private var fontSize: CGFloat {
    CGFloat(max(18, min(34, configuration.fontSize)))
  }

  private var lyricProgress: Double {
    guard currentLineStartMs >= 0 else { return 1 }
    let end = nextLineStartMs > currentLineStartMs ? nextLineStartMs : durationMs
    guard end > currentLineStartMs else { return 1 }
    let interpolatedPosition = min(durationMs, positionMs + (isPlaying ? (CACurrentMediaTime() - positionUpdatedAt) * 1000 : 0))
    return max(0, min(1, (interpolatedPosition - currentLineStartMs) / (end - currentLineStartMs)))
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
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    (text as NSString).draw(in: rect, withAttributes: [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraph,
    ])
  }

  private func drawTimedText(_ text: String, in rect: CGRect, progress: Double, alpha: Double, font: UIFont, context: CGContext) {
    let characters = Array(text)
    let prefixCount = Int((Double(characters.count) * progress).rounded(.down))
    let prefixLength = String(characters.prefix(prefixCount)).utf16.count
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byTruncatingTail
    let attributed = NSMutableAttributedString(string: text, attributes: [
      .font: font,
      .foregroundColor: UIColor(white: 0.52, alpha: alpha),
      .paragraphStyle: paragraph,
    ])
    if prefixLength > 0 {
      attributed.addAttributes([
        .foregroundColor: UIColor.white.withAlphaComponent(alpha),
      ], range: NSRange(location: 0, length: prefixLength))
    }
    let measured = attributed.boundingRect(
      with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let height = min(rect.height, max(font.lineHeight, measured.height))
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    attributed.draw(in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height))
  }

  func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    startRequested = false
    programmaticStopPending = false
    userDismissed = false
    if !shouldPresent { stopPresentation() }
  }

  func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    let shouldRestart = programmaticStopPending && shouldPresent
    startRequested = false
    userDismissed = !programmaticStopPending
    programmaticStopPending = false
    renderTimer?.invalidate()
    renderTimer = nil
    displayLayer.flushAndRemoveImage()
    if shouldRestart {
      refreshPresentation()
    }
  }

  func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    startRequested = false
    userDismissed = true
    stopPresentation()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
  ) {
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
