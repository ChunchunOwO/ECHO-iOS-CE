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
    var style = "glass"
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
  private var artworkURL = ""
  private var artworkTask: Task<Void, Never>?
  private let imageContext = CIContext(options: [.cacheIntermediates: false])
  private var title = ""
  private var artist = ""
  private var previousLyric = ""
  private var currentLyric = ""
  private var nextLyric = ""
  private var activeLyricIndex = 0
  private var currentLineStartMs = -1.0
  private var nextLineStartMs = -1.0
  private var positionMs = 0.0
  private var isPlaying = false
  private var durationMs = 0.0
  private var frameIndex: Int64 = 0
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
      artworkTask?.cancel()
      artworkTask = nil
      loadArtworkIfNeeded()
    }
    self.isPlaying = isPlaying
    self.durationMs = durationMs
    self.positionMs = positionMs
    if activeLyricIndex != activeIndex {
      activeLyricIndex = activeIndex
      lyricTransitionStartedAt = CACurrentMediaTime()
    }
    previousLyric = activeIndex > 0 && lines.indices.contains(activeIndex - 1) ? lines[activeIndex - 1].text : ""
    currentLyric = lines.indices.contains(activeIndex) ? lines[activeIndex].text : ""
    nextLyric = lines.indices.contains(activeIndex + 1) ? lines[activeIndex + 1].text : ""
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
    renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
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
    frameIndex &+= 1
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
      duration: CMTime(value: 1, timescale: 15),
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
    let phase = sin(Double(frameIndex) * 0.12)
    let transitionProgress = min(1, max(0, (CACurrentMediaTime() - lyricTransitionStartedAt) / 0.28))
    let animated = configuration.transitionAnimation
    let motionOffset = animated
      ? (configuration.animation == "flow" ? CGFloat(phase * 4) : CGFloat((1 - transitionProgress) * 12))
      : 0
    let motionScale = animated && configuration.animation == "pulse" ? CGFloat(1 + phase * 0.012) : 1
    drawBackground(in: context, bounds: bounds)
    let horizontalInset = min(54, max(18, CGFloat(width) * 0.055))
    let panelHeight = min(244, max(140, CGFloat(height) - 28))
    let panel = CGRect(
      x: horizontalInset,
      y: panelY(height: height, panelHeight: panelHeight) + motionOffset,
      width: max(40, CGFloat(width) - horizontalInset * 2),
      height: panelHeight
    )

    context.saveGState()
    context.translateBy(x: bounds.midX, y: panel.midY)
    context.scaleBy(x: motionScale, y: motionScale)
    context.translateBy(x: -bounds.midX, y: -panel.midY)
    context.setFillColor(panelColor.cgColor)
    context.addPath(CGPath(roundedRect: panel, cornerWidth: 34, cornerHeight: 34, transform: nil))
    context.fillPath()

    if configuration.style == "glass" {
      let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [UIColor.white.withAlphaComponent(0.16).cgColor, UIColor.systemPink.withAlphaComponent(0.06).cgColor] as CFArray,
        locations: [0, 1]
      )
      if let gradient {
        context.saveGState()
        context.addPath(CGPath(roundedRect: panel, cornerWidth: 34, cornerHeight: 34, transform: nil))
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: panel.minX, y: panel.minY), end: CGPoint(x: panel.maxX, y: panel.maxY), options: [])
        context.restoreGState()
      }
    }

    context.setFillColor(UIColor.systemPink.withAlphaComponent(0.8).cgColor)
    context.fill(CGRect(x: panel.minX + 32, y: panel.maxY - 12, width: panel.width - 64, height: 3))
    context.restoreGState()

    context.saveGState()
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    let textPanel = CGRect(x: panel.minX + 24, y: CGFloat(height) - panel.maxY + 18, width: panel.width - 48, height: panel.height - 30)
    var textY = textPanel.minY
    if configuration.showMetadata && !currentLyric.isEmpty {
      let metadata = [title, artist].filter { !$0.isEmpty }.joined(separator: "  ·  ")
      if !metadata.isEmpty {
        drawText(metadata, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 28), font: .systemFont(ofSize: 18, weight: .semibold), color: .white.withAlphaComponent(0.58), context: context)
        textY += 30
      }
    }
    let showPreviousLyric = panel.height >= 220
    if showPreviousLyric, !previousLyric.isEmpty {
      drawText(previousLyric, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 30), font: .systemFont(ofSize: fontSize * 0.62, weight: .medium), color: .white.withAlphaComponent(0.36), context: context)
      textY += 34
    }
    let currentText = currentLyric.isEmpty ? title : currentLyric
    let nextTextHeight: CGFloat = nextLyric.isEmpty ? 0 : 34
    let currentTextHeight = max(54, min(86, textPanel.maxY - textY - nextTextHeight))
    if configuration.timedReveal, !currentLyric.isEmpty {
      drawTimedText(currentText, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: currentTextHeight), progress: lyricProgress, alpha: animated ? transitionProgress : 1, font: .systemFont(ofSize: fontSize, weight: .bold), context: context)
    } else {
      drawText(currentText, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: currentTextHeight), font: .systemFont(ofSize: fontSize, weight: .bold), color: .white.withAlphaComponent(animated ? transitionProgress : 1), context: context)
    }
    textY += currentTextHeight + 6
    if !nextLyric.isEmpty {
      drawText(nextLyric, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 30), font: .systemFont(ofSize: fontSize * 0.62, weight: .medium), color: .white.withAlphaComponent(0.36), context: context)
    }
    context.restoreGState()
  }

  private var panelColor: UIColor {
    switch configuration.style {
    case "minimal": return UIColor.black.withAlphaComponent(0.28)
    case "solid": return UIColor.black.withAlphaComponent(0.88)
    default: return UIColor(red: 0.08, green: 0.07, blue: 0.11, alpha: 0.58)
    }
  }

  private func loadArtworkIfNeeded() {
    guard configuration.background == "artwork", artworkImage == nil, !artworkURL.isEmpty, artworkTask == nil,
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
      let image = data.flatMap(UIImage.init(data:)).flatMap { self?.blurredImage($0) }
      guard let self, self.artworkURL == expectedURL else { return }
      self.artworkImage = image
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
    if configuration.background == "artwork", let image = artworkImage?.cgImage {
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
    return max(0, min(1, (positionMs - currentLineStartMs) / (end - currentLineStartMs)))
  }

  private func panelY(height: Int, panelHeight: CGFloat) -> CGFloat {
    let inset = max(14, min(34, (CGFloat(height) - panelHeight) / 2))
    switch configuration.position {
    case "top": return inset
    case "center": return CGFloat(height) / 2 - panelHeight / 2
    default: return CGFloat(height) - panelHeight - inset
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
      .foregroundColor: UIColor.white.withAlphaComponent(0.24 * alpha),
      .paragraphStyle: paragraph,
    ])
    if prefixLength > 0 {
      let shadow = NSShadow()
      shadow.shadowColor = UIColor.systemPink.withAlphaComponent(0.9 * alpha)
      shadow.shadowBlurRadius = 10
      attributed.addAttributes([
        .foregroundColor: UIColor.white.withAlphaComponent(alpha),
        .shadow: shadow,
      ], range: NSRange(location: 0, length: prefixLength))
    }
    UIGraphicsPushContext(context)
    defer { UIGraphicsPopContext() }
    attributed.draw(in: rect)
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
