import AVFoundation
import AVKit
import CoreMedia
import CoreVideo
import Foundation
import UIKit

@MainActor
final class EchoNativeDesktopLyricsController: NSObject, @preconcurrency AVPictureInPictureControllerDelegate, @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
  struct Configuration: Equatable {
    var animation = "flow"
    var enabled = false
    var fontSize = 26.0
    var opacity = 0.66
    var onlyWhilePlaying = true
    var position = "bottom"
    var showMetadata = true
    var style = "glass"
    var widthScale = 0.5
  }

  private let displayLayer = AVSampleBufferDisplayLayer()
  private let hostView = UIView(frame: CGRect(x: 0, y: 0, width: 108, height: 32))
  private var pictureInPictureController: AVPictureInPictureController?
  private var pictureInPicturePossibleObservation: NSKeyValueObservation?
  private var renderTimer: Timer?
  private var configuration = Configuration()
  private var title = ""
  private var artist = ""
  private var previousLyric = ""
  private var currentLyric = ""
  private var nextLyric = ""
  private var isPlaying = false
  private var durationMs = 0.0
  private var frameIndex: Int64 = 0
  private var userDismissed = false
  private var programmaticStopPending = false
  private var startRequested = false

  override init() {
    super.init()
    displayLayer.videoGravity = .resizeAspect
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
  }

  func attach(to container: UIView) {
    if hostView.superview !== container {
      hostView.removeFromSuperview()
      container.insertSubview(hostView, at: 0)
    }
    hostView.isUserInteractionEnabled = false
    hostView.backgroundColor = .clear
    hostView.frame = CGRect(x: 0, y: 0, width: 108, height: 32)
    if displayLayer.superlayer !== hostView.layer {
      displayLayer.removeFromSuperlayer()
      hostView.layer.addSublayer(displayLayer)
    }
    displayLayer.frame = hostView.bounds
    installControlTimebase()
  }

  func configure(_ next: Configuration) {
    let wasEnabled = configuration.enabled
    let appearanceChanged = configuration != next
    let canvasSizeChanged = canvasWidth(for: configuration.widthScale) != canvasWidth(for: next.widthScale)
    configuration = next
    if !next.enabled {
      stop()
      return
    }
    if !wasEnabled || appearanceChanged { userDismissed = false }
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
    lines: [EchoNativeMetadataService.LyricLine],
    activeIndex: Int,
    isPlaying: Bool,
    durationMs: Double
  ) {
    self.title = title
    self.artist = artist
    self.isPlaying = isPlaying
    self.durationMs = durationMs
    previousLyric = activeIndex > 0 && lines.indices.contains(activeIndex - 1) ? lines[activeIndex - 1].text : ""
    currentLyric = lines.indices.contains(activeIndex) ? lines[activeIndex].text : ""
    nextLyric = lines.indices.contains(activeIndex + 1) ? lines[activeIndex + 1].text : ""

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
      displayLayer.flush()
    }
    displayLayer.enqueue(sampleBuffer)
    frameIndex &+= 1
  }

  private func makeSampleBuffer() -> CMSampleBuffer? {
    let width = canvasWidth(for: configuration.widthScale)
    let height = 540
    var pixelBuffer: CVPixelBuffer?
    let attributes: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
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
    let motionOffset = configuration.animation == "flow" ? CGFloat(phase * 4) : 0
    let motionScale = configuration.animation == "pulse" ? CGFloat(1 + phase * 0.012) : 1
    let panel = CGRect(x: 54, y: panelY(height: height) + motionOffset, width: CGFloat(width - 108), height: 244)

    // PiP video frames are opaque; leaving the pixel buffer transparent renders as black.
    context.setFillColor(backgroundColor.withAlphaComponent(1).cgColor)
    context.fill(bounds)

    context.saveGState()
    context.translateBy(x: bounds.midX, y: panel.midY)
    context.scaleBy(x: motionScale, y: motionScale)
    context.translateBy(x: -bounds.midX, y: -panel.midY)
    context.setFillColor(backgroundColor.cgColor)
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
    let textPanel = CGRect(x: panel.minX + 32, y: CGFloat(height) - panel.maxY + 24, width: panel.width - 64, height: panel.height - 38)
    var textY = textPanel.minY
    if configuration.showMetadata && !currentLyric.isEmpty {
      let metadata = [title, artist].filter { !$0.isEmpty }.joined(separator: "  ·  ")
      if !metadata.isEmpty {
        drawText(metadata, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 28), font: .systemFont(ofSize: 18, weight: .semibold), color: .white.withAlphaComponent(0.58), context: context)
        textY += 34
      }
    }
    if !previousLyric.isEmpty {
      drawText(previousLyric, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 30), font: .systemFont(ofSize: fontSize * 0.62, weight: .medium), color: .white.withAlphaComponent(0.36), context: context)
      textY += 34
    }
    drawText(currentLyric.isEmpty ? title : currentLyric, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 86), font: .systemFont(ofSize: fontSize, weight: .bold), color: .white, context: context)
    textY += 92
    if !nextLyric.isEmpty {
      drawText(nextLyric, in: CGRect(x: textPanel.minX, y: textY, width: textPanel.width, height: 30), font: .systemFont(ofSize: fontSize * 0.62, weight: .medium), color: .white.withAlphaComponent(0.36), context: context)
    }
    context.restoreGState()
  }

  private var backgroundColor: UIColor {
    let alpha = CGFloat(max(0.2, min(0.95, configuration.opacity)))
    switch configuration.style {
    case "minimal": return UIColor.black.withAlphaComponent(alpha * 0.38)
    case "solid": return UIColor.black.withAlphaComponent(alpha)
    default: return UIColor(red: 0.08, green: 0.07, blue: 0.11, alpha: alpha)
    }
  }

  private var fontSize: CGFloat {
    CGFloat(max(18, min(34, configuration.fontSize)))
  }

  private func panelY(height: Int) -> CGFloat {
    switch configuration.position {
    case "top": return 34
    case "center": return CGFloat(height / 2 - 122)
    default: return CGFloat(height - 278)
    }
  }

  private func canvasWidth(for scale: Double) -> Int {
    let clamped = max(0.2, min(1.0, scale))
    return max(192, min(960, Int((960 * clamped).rounded()) / 2 * 2))
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
