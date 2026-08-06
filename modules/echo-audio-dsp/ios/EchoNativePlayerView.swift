import Combine
import ExpoModulesCore
import Foundation
import ImageIO
import SwiftUI
import UIKit

func setIfChanged<Root: AnyObject, Value: Equatable>(
  _ root: Root,
  _ keyPath: ReferenceWritableKeyPath<Root, Value>,
  _ value: Value
) {
  if root[keyPath: keyPath] != value {
    root[keyPath: keyPath] = value
  }
}

extension UIView {
  func findHostingViewController() -> UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let controller = current as? UIViewController {
        return controller
      }
      responder = current.next
    }
    return nil
  }
}

private func echoAdaptiveColor(light: UIColor, dark: UIColor) -> Color {
  Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark ? dark : light
  })
}

let echoInk = Color.primary
let echoAccent = Color(red: 0.67, green: 0.12, blue: 0.14)
let echoGold = Color(red: 0.82, green: 0.55, blue: 0.08)
let echoPageHeaderBackground = echoAdaptiveColor(
  light: UIColor(red: 0.97, green: 0.79, blue: 0.73, alpha: 1),
  dark: UIColor(red: 0.13, green: 0.09, blue: 0.13, alpha: 1)
)
var echoWarmBackground: LinearGradient {
  LinearGradient(
    colors: [
      echoAdaptiveColor(
        light: UIColor(red: 0.97, green: 0.79, blue: 0.73, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.09, blue: 0.13, alpha: 1)
      ),
      echoAdaptiveColor(
        light: UIColor(red: 0.99, green: 0.88, blue: 0.69, alpha: 1),
        dark: UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1)
      ),
      echoAdaptiveColor(
        light: UIColor(red: 0.96, green: 0.82, blue: 0.80, alpha: 1),
        dark: UIColor(red: 0.10, green: 0.11, blue: 0.16, alpha: 1)
      ),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )
}

extension View {
  @ViewBuilder
  func echoGlass<S: Shape>(
    tint: Color? = nil,
    clear: Bool = true,
    interactive: Bool = true,
    in shape: S
  ) -> some View {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      if clear {
        if interactive {
          glassEffect(.clear.tint(tint).interactive(), in: shape)
        } else {
          glassEffect(.clear.tint(tint), in: shape)
        }
      } else {
        if interactive {
          glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
          glassEffect(.regular.tint(tint), in: shape)
        }
      }
    } else {
      echoLegacyGlass(tint: tint, clear: clear, in: shape)
    }
    #else
    echoLegacyGlass(tint: tint, clear: clear, in: shape)
    #endif
  }

  @ViewBuilder
  func echoLegacyGlass<S: Shape>(tint: Color? = nil, clear: Bool, in shape: S) -> some View {
    if clear {
      background(Color.white.opacity(0.11), in: shape)
        .overlay(shape.stroke(Color.white.opacity(0.52), lineWidth: 0.8))
    } else {
      background(tint ?? Color.clear, in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(Color.white.opacity(0.48), lineWidth: 0.8))
    }
  }

  @ViewBuilder
  func echoScrollClipDisabled() -> some View {
    if #available(iOS 17.0, *) {
      scrollClipDisabled()
    } else {
      self
    }
  }

  @ViewBuilder
  func echoCompactSheet(height: CGFloat) -> some View {
    if #available(iOS 16.4, *) {
      presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .presentationBackground(echoWarmBackground)
        .presentationCornerRadius(28)
    } else if #available(iOS 16.0, *) {
      presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
    } else {
      self
    }
  }

  @ViewBuilder
  func echoMediumSheet() -> some View {
    if #available(iOS 16.4, *) {
      presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(echoWarmBackground)
        .presentationCornerRadius(28)
    } else if #available(iOS 16.0, *) {
      presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    } else {
      self
    }
  }

  @ViewBuilder
  func echoLargeSheet() -> some View {
    if #available(iOS 16.4, *) {
      presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(echoWarmBackground)
        .presentationCornerRadius(28)
    } else if #available(iOS 16.0, *) {
      presentationDetents([.large])
        .presentationDragIndicator(.visible)
    } else {
      self
    }
  }

  @ViewBuilder
  func echoBlurredSheet() -> some View {
    if #available(iOS 16.4, *) {
      presentationBackground(.regularMaterial)
    } else {
      background(.regularMaterial)
    }
  }
}

@ViewBuilder
func echoGlassGroup<Content: View>(
  spacing: CGFloat,
  @ViewBuilder content: () -> Content
) -> some View {
  #if compiler(>=6.2)
  if #available(iOS 26.0, *) {
    GlassEffectContainer(spacing: spacing) {
      content()
    }
  } else {
    content()
  }
  #else
  content()
  #endif
}

private let nativeEqFrequencies = ["31", "63", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

final class EchoNativeEqualizerModel: ObservableObject {
  @Published var gains = Array(repeating: 0.0, count: 10)
  @Published var language = "zh"
  @Published var preset = "flat"
}

final class EchoNativePlaybackClockModel: ObservableObject {
  @Published var positionMs = 0.0
}

final class EchoNativeSignalMeterModel: ObservableObject {
  @Published var clipping = false
  @Published var lufsMomentary: Double?
  @Published var peakDb = -120.0
  @Published var rmsDb = -120.0
}

struct EchoNativeQueueItem: Decodable, Identifiable {
  let artist: String
  let current: Bool
  let id: String
  let meta: String
  let source: String
  let title: String
  let trackId: String
}

struct EchoNativeQueuePayload: Decodable {
  let canEdit: Bool
  let clearLabel: String
  let emptyLabel: String
  let items: [EchoNativeQueueItem]
  let moveDownLabel: String
  let moveUpLabel: String
  let playlistId: String
  let removeLabel: String
  let source: String
  let subtitle: String
  let title: String
}

struct EchoNativeExternalSourceCandidate: Decodable, Identifiable {
  let albumArt: String?
  let artist: String?
  let availableLabel: String
  let hasArtist: Bool
  let hasArtwork: Bool
  let hasLyrics: Bool
  let id: String
  let source: String
  let sourceLabel: String
  let title: String
}

struct EchoNativeExternalSourcePickerPayload: Decodable, Identifiable {
  let artworkLabel: String
  let artistLabel: String
  let cancelLabel: String
  let candidates: [EchoNativeExternalSourceCandidate]
  let doneLabel: String
  let id: String
  let ignoreLabel: String
  let lyricsLabel: String
  let selectedLabel: String
  let subtitle: String
  let title: String
  let unavailableLabel: String
  let useSourceLabel: String
}

final class EchoNativePlayerModel: ObservableObject {
  let clock = EchoNativePlaybackClockModel()
  let equalizer = EchoNativeEqualizerModel()
  let signalMeter = EchoNativeSignalMeterModel()
  @Published var activePage = "control"
  @Published var activeLyricIndex = 0
  @Published var album = ""
  @Published var alertMessage = ""
  @Published var alertTitle = ""
  @Published var artist = ""
  @Published var artworkBackgroundEnabled = true
  @Published var artworkUrl = ""
  @Published var connectionLabel = "ECHO未连接"
  @Published var connectionOnline = false
  @Published var controlsEnabled = false
  @Published var darkModeEnabled = false
  @Published var durationMs = 0.0
  @Published var eqEnabled = false
  @Published var externalSourcePicker: EchoNativeExternalSourcePickerPayload?
  @Published var followSystemAppearance = true
  @Published var isFavorite = false
  @Published var isPlaying = false
  @Published var language = "zh"
  @Published var loudnessEnabled = false
  @Published var lyricLines: [EchoNativeMetadataService.LyricLine] = []
  @Published var lyricsVisible = false
  @Published var metadataLoading = false
  @Published var outputMode = "local"
  @Published var playbackMode = EchoNativePlaybackMode.normal
  @Published var playbackLoading = false
  @Published var queuePayload: EchoNativeQueuePayload?
  @Published var showArtworkGlow = true
  @Published var showPlayerOutputInMenu = true
  @Published var signalBitDepth = ""
  @Published var signalBitrate = ""
  @Published var signalChannelCount = ""
  @Published var signalCodec = ""
  @Published var signalDacProfile: EchoNativeDacObservation?
  @Published var signalDeviceChannelCount = ""
  @Published var signalDeviceIOBufferMs = 0.0
  @Published var signalDeviceLatencyMs = 0.0
  @Published var signalDeviceName = ""
  @Published var signalDevicePortType = ""
  @Published var signalDeviceSampleRate = ""
  @Published var signalDeviceUID = ""
  @Published var signalEngineRunning = false
  @Published var signalEngineSampleRate = ""
  @Published var signalExclusive: Bool?
  @Published var signalFileLoaded = false
  @Published var signalOutputBitDepth = ""
  @Published var signalOutputVolume = 0.0
  @Published var signalRemoteOutput = ""
  @Published var signalRouteEvents = EchoNativeSignalRouteEvent.load()
  @Published var signalSampleRate = ""
  @Published var signalSourceLabel = ""
  @Published var signalTelemetrySource = "unverified"
  @Published var tags: [String] = []
  @Published var title = ""
  @Published var volume = 1.0
  private var lastExternalSourcePickerJSON = ""
  private var lastQueuePayloadJSON = ""

  var positionMs: Double {
    get { clock.positionMs }
    set { clock.positionMs = newValue }
  }

  func updateQueue(payloadJSON: String) {
    guard payloadJSON != lastQueuePayloadJSON else { return }
    guard
      let data = payloadJSON.data(using: .utf8),
      let payload = try? JSONDecoder().decode(EchoNativeQueuePayload.self, from: data)
    else {
      return
    }
    lastQueuePayloadJSON = payloadJSON
    queuePayload = payload
  }

  func updateExternalSourcePicker(payloadJSON: String) {
    guard payloadJSON != lastExternalSourcePickerJSON else { return }
    lastExternalSourcePickerJSON = payloadJSON
    guard !payloadJSON.isEmpty else {
      externalSourcePicker = nil
      return
    }
    guard
      let data = payloadJSON.data(using: .utf8),
      let payload = try? JSONDecoder().decode(EchoNativeExternalSourcePickerPayload.self, from: data),
      !payload.candidates.isEmpty
    else {
      externalSourcePicker = nil
      return
    }
    if externalSourcePicker?.id != payload.id {
      externalSourcePicker = payload
    }
  }
}

public final class EchoNativeAppView: ExpoView {
  private let store = EchoNativeAppStore()
  private var appearanceCancellable: AnyCancellable?

  private lazy var hostingController = UIHostingController(
    rootView: EchoNativeAppScreen(
      playerModel: store.playerModel,
      pagesModel: store.pagesModel,
      onAction: store.handle
    )
  )

  public required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    hostingController.view.backgroundColor = .clear
    hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    appearanceCancellable = store.playerModel.$followSystemAppearance
      .combineLatest(store.playerModel.$darkModeEnabled)
      .sink { [weak self] followsSystem, darkMode in
        let style: UIUserInterfaceStyle = followsSystem ? .unspecified : (darkMode ? .dark : .light)
        self?.hostingController.overrideUserInterfaceStyle = style
      }
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    hostingController.view.frame = bounds
  }

  func migrateLegacy(_ payloadJSON: String) {
    store.migrateLegacy(payloadJSON: payloadJSON)
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { store.start() }
    if window != nil, hostingController.view.superview == nil, let parent = findHostingViewController() {
      store.presenter = parent
      parent.addChild(hostingController)
      addSubview(hostingController.view)
      hostingController.didMove(toParent: parent)
      hostingController.view.frame = bounds
    } else if window == nil {
      store.presenter = nil
      hostingController.view.removeFromSuperview()
      hostingController.removeFromParent()
    }
  }
}

private struct EchoNativeAppScreen: View {
  @ObservedObject var playerModel: EchoNativePlayerModel
  @ObservedObject var pagesModel: EchoNativePagesModel
  let onAction: ([String: Any]) -> Void

  var body: some View {
    ZStack {
      echoWarmBackground.ignoresSafeArea()
      Group {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
          adaptiveTabView
        } else {
          legacyTabView
        }
        #else
        legacyTabView
        #endif
      }
      .tint(echoAccent)
    }
    .sheet(item: $playerModel.externalSourcePicker) { payload in
      EchoNativeExternalSourcePicker(payload: payload, onAction: onAction)
        .echoMediumSheet()
    }
    .alert(playerModel.alertTitle, isPresented: Binding(
      get: { !playerModel.alertMessage.isEmpty },
      set: { if !$0 { playerModel.alertMessage = "" } }
    )) {
      Button(playerModel.language == "en" ? "OK" : "好", role: .cancel) {
        playerModel.alertMessage = ""
      }
    } message: {
      Text(playerModel.alertMessage)
    }
  }

  private var selection: Binding<String> {
    Binding(
      get: { playerModel.activePage },
      set: { page in
        guard page != playerModel.activePage else { return }
        playerModel.activePage = page
        onAction(["action": "page", "page": page])
      }
    )
  }

  #if compiler(>=6.0)
  @available(iOS 18.0, *)
  private var adaptiveTabView: some View {
    TabView(selection: selection) {
      Tab(title("control"), systemImage: "headphones", value: "control") {
        themedTab(playerBackground: true) {
          EchoNativePlayerScreen(model: playerModel, onAction: onAction)
        }
      }
      Tab(title("library"), systemImage: "music.note.list", value: "library") {
        themedTab {
          EchoNativePagesScreen(model: pagesModel, page: "library", onAction: onAction)
        }
      }
      Tab(title("search"), systemImage: "magnifyingglass", value: "search", role: .search) {
        themedTab {
          EchoNativePagesScreen(model: pagesModel, page: "search", onAction: onAction)
        }
      }
      Tab(title("connect"), systemImage: "link", value: "connect") {
        themedTab {
          EchoNativePagesScreen(model: pagesModel, page: "connect", onAction: onAction)
        }
      }
      Tab(title("settings"), systemImage: "gearshape", value: "settings") {
        themedTab {
          EchoNativePagesScreen(model: pagesModel, page: "settings", onAction: onAction)
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .background(Color.clear)
  }
  #endif

  private var legacyTabView: some View {
    TabView(selection: selection) {
      themedTab(playerBackground: true) {
        EchoNativePlayerScreen(model: playerModel, onAction: onAction)
      }
        .tag("control")
        .tabItem { Label(title("control"), systemImage: "headphones") }
      themedTab {
        EchoNativePagesScreen(model: pagesModel, page: "library", onAction: onAction)
      }
        .tag("library")
        .tabItem { Label(title("library"), systemImage: "music.note.list") }
      themedTab {
        EchoNativePagesScreen(model: pagesModel, page: "search", onAction: onAction)
      }
        .tag("search")
        .tabItem { Label(title("search"), systemImage: "magnifyingglass") }
      themedTab {
        EchoNativePagesScreen(model: pagesModel, page: "connect", onAction: onAction)
      }
        .tag("connect")
        .tabItem { Label(title("connect"), systemImage: "link") }
      themedTab {
        EchoNativePagesScreen(model: pagesModel, page: "settings", onAction: onAction)
      }
        .tag("settings")
        .tabItem { Label(title("settings"), systemImage: "gearshape") }
    }
    .background(Color.clear)
  }

  private func themedTab<Content: View>(
    playerBackground: Bool = false,
    @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack {
      if playerBackground {
        EchoNativeArtworkBackdrop(
          enabled: playerModel.artworkBackgroundEnabled,
          identity: "\(playerModel.title)::\(playerModel.artist)",
          urlString: playerModel.artworkBackgroundEnabled ? playerModel.artworkUrl : ""
        ) {
          onAction(["action": "artworkError", "url": playerModel.artworkUrl])
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      } else {
        echoWarmBackground.ignoresSafeArea()
      }

      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func title(_ page: String) -> String {
    let english = playerModel.language == "en"
    switch page {
    case "control": return english ? "Playback" : "播放"
    case "library": return english ? "Library" : "曲库"
    case "search": return english ? "Search" : "搜索"
    case "connect": return english ? "Connect" : "连接"
    default: return english ? "Settings" : "设置"
    }
  }
}

struct EchoNativePlayerScreen: View {
  @ObservedObject var model: EchoNativePlayerModel
  let onAction: ([String: Any]) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var isSettingVolume = false
  @State private var lastLyricsInteraction = Date.distantPast
  @State private var showEqualizer = false
  @State private var showQueue = false
  @State private var showSignalPath = false
  @State private var volumeValue = 1.0

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        if model.lyricsVisible {
          lyricsLayout(geometry: geometry)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
          playerLayout(geometry: geometry)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .background(Color.clear)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: model.lyricsVisible)
    .sheet(isPresented: $showEqualizer) {
      EchoNativeEqualizerSheet(model: model.equalizer, onAction: onAction)
    }
    .sheet(isPresented: $showQueue) {
      EchoNativeQueueSheet(model: model, onAction: onAction)
        .echoMediumSheet()
        .echoBlurredSheet()
    }
    .sheet(isPresented: $showSignalPath) {
      EchoNativeSignalPathSheet(model: model, onAction: onAction)
        .echoMediumSheet()
        .echoBlurredSheet()
    }
    .onAppear {
      volumeValue = model.volume
    }
    .onChange(of: model.volume) { value in
      if !isSettingVolume { volumeValue = value }
    }
  }

  private func playerLayout(geometry: GeometryProxy) -> some View {
    let compact = geometry.size.height < 680
    let coverScale: CGFloat = compact ? 0.34 : 0.40
    let coverMinimum: CGFloat = compact ? 138 : 210
    let coverMaximum: CGFloat = compact ? 200 : 310
    let coverSize = min(
      geometry.size.width - 48,
      max(coverMinimum, min(coverMaximum, geometry.size.height * coverScale))
    )

    return VStack(spacing: 0) {
      statusHeader
      artwork(size: coverSize, compact: compact)
        .padding(.top, compact ? 6 : 10)
      trackDetails(compact: compact)
        .padding(.top, compact ? 7 : 12)
      progressControl
        .padding(.top, compact ? 7 : 12)
      transportControls(compact: compact)
        .padding(.top, compact ? 5 : 8)
      secondaryControls(lyricsMode: false)
        .padding(.top, compact ? 4 : 8)
      volumeControl
        .padding(.top, compact ? 3 : 6)
      if !model.showPlayerOutputInMenu {
        outputControl
          .padding(.top, compact ? 4 : 8)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, compact ? 6 : 12)
    .frame(maxWidth: 460)
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
  }

  private func lyricsLayout(geometry: GeometryProxy) -> some View {
    let compact = geometry.size.height < 600

    return VStack(spacing: compact ? 7 : 11) {
      lyricsHeader(compact: compact)
      lyricsScroller(compact: compact)
      VStack(spacing: compact ? 6 : 9) {
        progressControl
        transportControls(compact: true)
        secondaryControls(lyricsMode: true)
        volumeControl
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, compact ? 8 : 12)
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
  }

  private func lyricsHeader(compact: Bool) -> some View {
    let artworkSize: CGFloat = compact ? 76 : 96

    return HStack(alignment: .top, spacing: 12) {
      VStack(spacing: 5) {
        ZStack {
          EchoNativeArtwork(urlString: model.artworkUrl) {
            onAction(["action": "artworkError", "url": model.artworkUrl])
          }
          if model.metadataLoading {
            EchoNativeArtworkLoadingBadge(language: model.language, compact: true)
              .transition(.opacity)
          }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.metadataLoading)
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 17 : 21, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: compact ? 17 : 21, style: .continuous)
            .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }

        if showsConnectionStatus {
          connectionStatus(compact: true)
        }
      }
      .frame(width: artworkSize)

      VStack(alignment: .leading, spacing: compact ? 3 : 5) {
        Text(titleLabel)
          .font(.system(size: compact ? 17 : 20, weight: .bold))
          .foregroundColor(echoInk)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
        HStack(spacing: 5) {
          Image(systemName: "rectangle.stack.fill")
            .accessibilityHidden(true)
          Text(albumLabel)
            .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.56))
        HStack(spacing: 5) {
          Image(systemName: "person.fill")
            .accessibilityHidden(true)
          Text(artistLabel)
            .lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.56))
        if !model.tags.isEmpty {
          HStack(alignment: .top, spacing: 5) {
            Image(systemName: "waveform")
              .accessibilityHidden(true)
            Text(model.tags.joined(separator: "  ·  "))
              .lineLimit(compact ? 2 : 3)
              .minimumScaleFactor(0.72)
              .fixedSize(horizontal: false, vertical: true)
          }
          .font(.system(size: 9, weight: .bold))
          .foregroundColor(echoInk.opacity(0.62))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        onAction(["action": "lyricsClose"])
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(echoInk)
          .frame(width: 36, height: 36)
          .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.language == "en" ? "Close lyrics" : "关闭歌词")
    }
  }

  private func lyricsScroller(compact: Bool) -> some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(alignment: .leading, spacing: compact ? 12 : 18) {
          ForEach(Array(model.lyricLines.enumerated()), id: \.offset) { index, line in
            let active = index == model.activeLyricIndex
            let distance = abs(index - model.activeLyricIndex)
            let timeMs = line.milliseconds
            Button {
              guard timeMs >= 0 else { return }
              onAction(["action": "seek", "value": timeMs])
            } label: {
              VStack(alignment: .leading, spacing: 3) {
                Text(line.text)
                  .font(.system(
                    size: active ? (compact ? 20 : 24) : (distance == 1 ? 18 : 16),
                    weight: active ? .bold : .semibold
                  ))
                  .foregroundColor(active ? echoInk : echoInk.opacity(distance == 1 ? 0.56 : 0.3))
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)
                  .shadow(color: active ? Color.white.opacity(0.7) : .clear, radius: 8)
                if timeMs >= 0 {
                  Text(formatTime(timeMs))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(echoInk.opacity(0.32))
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(timeMs < 0)
            .id(index)
            .accessibilityLabel(lyricAccessibilityLabel(line: line, timeMs: timeMs))
          }
        }
        .padding(.vertical, compact ? 56 : 76)
      }
      .simultaneousGesture(
        DragGesture(minimumDistance: 4)
          .onChanged { _ in lastLyricsInteraction = Date() }
          .onEnded { _ in lastLyricsInteraction = Date() }
      )
      .onAppear {
        scrollToActiveLyric(proxy, index: model.activeLyricIndex, animated: false)
      }
      .onChange(of: model.activeLyricIndex) { index in
        guard Date().timeIntervalSince(lastLyricsInteraction) > 1.5 else { return }
        scrollToActiveLyric(proxy, index: index, animated: true)
      }
    }
    .frame(maxHeight: .infinity)
  }

  private func lyricAccessibilityLabel(line: EchoNativeMetadataService.LyricLine, timeMs: Double) -> String {
    guard timeMs >= 0 else { return line.text }
    return "\(formatTime(timeMs)), \(line.text)"
  }

  private func scrollToActiveLyric(_ proxy: ScrollViewProxy, index: Int, animated: Bool) {
    guard model.lyricLines.indices.contains(index) else { return }
    if animated && !reduceMotion {
      withAnimation(.easeOut(duration: 0.3)) {
        proxy.scrollTo(index, anchor: .center)
      }
    } else {
      proxy.scrollTo(index, anchor: .center)
    }
  }

  private var statusHeader: some View {
    HStack(spacing: 6) {
      Image(systemName: "rectangle.stack.fill")
        .accessibilityHidden(true)
      Text(albumLabel)
        .lineLimit(1)
    }
      .font(.system(size: 13, weight: .semibold))
      .foregroundColor(echoInk)
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity, alignment: .center)
  }

  @ViewBuilder
  private func artwork(size: CGFloat, compact: Bool) -> some View {
    let cornerRadius: CGFloat = compact ? 20 : 28
    VStack(spacing: compact ? 4 : 6) {
      ZStack {
        if model.showArtworkGlow {
          RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(echoGold.opacity(0.22))
            .frame(width: size * 0.94, height: size * 0.94)
            .blur(radius: 30)
        }
        EchoNativeArtwork(urlString: model.artworkUrl) {
          onAction(["action": "artworkError", "url": model.artworkUrl])
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Color.white.opacity(0.58), lineWidth: 1)
        }
        if model.metadataLoading {
          EchoNativeArtworkLoadingBadge(language: model.language, compact: compact)
            .transition(.opacity)
        }
      }
      .frame(height: size)
      .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.metadataLoading)

      if showsConnectionStatus {
        connectionStatus(compact: compact)
      }
    }
    .frame(width: size)
  }

  private func connectionStatus(compact: Bool) -> some View {
    HStack(spacing: 5) {
      Circle()
        .fill(model.connectionOnline ? echoGold : echoAccent)
        .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)
      Text(model.connectionLabel)
        .font(.system(size: compact ? 9 : 10, weight: .semibold))
        .foregroundColor(model.connectionOnline ? echoInk.opacity(0.66) : echoAccent)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(.horizontal, compact ? 7 : 9)
    .frame(maxWidth: .infinity, minHeight: compact ? 22 : 25)
    .echoGlass(tint: Color.white.opacity(0.12), interactive: false, in: Capsule())
    .accessibilityLabel(model.connectionLabel)
  }

  private func trackDetails(compact: Bool) -> some View {
    VStack(spacing: compact ? 4 : 7) {
      Text(titleLabel)
        .font(.system(size: compact ? 18 : 21, weight: .bold))
        .foregroundColor(echoInk)
        .lineLimit(compact ? 1 : 2)
        .minimumScaleFactor(0.8)
        .multilineTextAlignment(.center)
      HStack(spacing: 5) {
        Image(systemName: "person.fill")
          .accessibilityHidden(true)
        Text(artistLabel)
          .lineLimit(1)
      }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(echoInk.opacity(0.58))
      if !model.tags.isEmpty {
        HStack(spacing: 5) {
          Image(systemName: "waveform")
            .accessibilityHidden(true)
          Text(model.tags.joined(separator: "  •  "))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(echoInk.opacity(0.62))
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, alignment: .center)
      }
    }
  }

  private var progressControl: some View {
    EchoNativeProgressControl(
      clock: model.clock,
      controlsEnabled: model.controlsEnabled,
      durationMs: model.durationMs,
      language: model.language
    ) { value in
      onAction(["action": "seek", "value": value])
    }
  }

  private func transportControls(compact: Bool) -> some View {
    echoGlassGroup(spacing: 10) {
      HStack(spacing: compact ? 24 : 34) {
        roundButton(
          symbol: "backward.end.fill",
          label: model.language == "en" ? "Previous" : "上一首",
          size: compact ? 48 : 54
        ) {
          onAction(["action": "previous"])
        }
        Button {
          onAction(["action": "playPause"])
        } label: {
          Group {
            if model.playbackLoading {
              ProgressView().controlSize(.regular)
            } else {
              Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                .offset(x: model.isPlaying ? 0 : 2)
            }
          }
          .font(.system(size: compact ? 26 : 30, weight: .bold))
          .foregroundColor(echoInk)
          .frame(width: compact ? 66 : 76, height: compact ? 66 : 76)
          .echoGlass(tint: Color.white.opacity(0.2), clear: false, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.controlsEnabled || model.playbackLoading)
        .opacity(model.controlsEnabled && !model.playbackLoading ? 1 : 0.5)
        .accessibilityLabel(model.playbackLoading
          ? (model.language == "en" ? "Loading audio" : "正在加载音频")
          : (model.language == "en" ? (model.isPlaying ? "Pause" : "Play") : (model.isPlaying ? "暂停" : "播放")))
        roundButton(
          symbol: "forward.end.fill",
          label: model.language == "en" ? "Next" : "下一首",
          size: compact ? 48 : 54
        ) {
          onAction(["action": "next"])
        }
      }
    }
  }

  private func secondaryControls(lyricsMode: Bool) -> some View {
    echoGlassGroup(spacing: 8) {
      HStack(spacing: 0) {
        iconButton(
          symbol: playbackModeSymbol,
          label: model.language == "en" ? "Playback mode" : "播放模式",
          active: model.playbackMode != .normal,
          value: playbackModeLabel
        ) {
          onAction(["action": "playbackMode"])
        }
        .frame(maxWidth: .infinity)
        iconButton(
          symbol: lyricsMode ? "quote.bubble.fill" : "quote.bubble",
          label: model.language == "en" ? (lyricsMode ? "Close lyrics" : "Lyrics") : (lyricsMode ? "关闭歌词" : "歌词"),
          active: lyricsMode
        ) {
          onAction(["action": lyricsMode ? "lyricsClose" : "lyrics"])
        }
        .frame(maxWidth: .infinity)
        iconButton(symbol: "list.bullet", label: model.language == "en" ? "Queue" : "播放列表", active: false) {
          showQueue = true
        }
        .frame(maxWidth: .infinity)
        moreControls
          .frame(maxWidth: .infinity)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private var playbackModeSymbol: String {
    switch model.playbackMode {
    case .normal: return "arrow.right.to.line"
    case .repeatAll: return "repeat"
    case .repeatOne: return "repeat.1"
    case .shuffle: return "shuffle"
    }
  }

  private var playbackModeLabel: String {
    let english = model.language == "en"
    switch model.playbackMode {
    case .normal: return english ? "Play once" : "正常播放"
    case .repeatAll: return english ? "Repeat all" : "列表循环"
    case .repeatOne: return english ? "Repeat one" : "单曲循环"
    case .shuffle: return english ? "Shuffle" : "随机播放"
    }
  }

  private var volumeControl: some View {
    HStack(spacing: 9) {
      Image(systemName: "speaker.wave.1.fill")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(echoInk.opacity(0.52))
      Slider(
        value: $volumeValue,
        in: 0...1,
        onEditingChanged: { editing in
          isSettingVolume = editing
          onAction(["action": "volume", "value": volumeValue, "commit": !editing])
        }
      )
      .tint(echoAccent)
      .disabled(!model.controlsEnabled)
      .accessibilityLabel(model.language == "en" ? "Volume" : "音量")
      .accessibilityValue("\(Int((volumeValue * 100).rounded()))%")
      Text("\(Int((volumeValue * 100).rounded()))%")
        .font(.system(size: 10, weight: .bold, design: .monospaced))
        .foregroundColor(echoInk.opacity(0.58))
        .frame(width: 34, alignment: .trailing)
    }
    .onChange(of: volumeValue) { value in
      if isSettingVolume {
        onAction(["action": "volume", "value": value, "commit": false])
      }
    }
  }

  private var moreControls: some View {
    Menu {
      Button {
        onAction(["action": "trackFavoriteCurrent"])
      } label: {
        Label(
          model.language == "en" ? (model.isFavorite ? "Remove favorite" : "Favorite") : (model.isFavorite ? "取消收藏" : "收藏"),
          systemImage: model.isFavorite ? "heart.fill" : "heart"
        )
      }
      .disabled(!model.controlsEnabled)
      Button {
        showSignalPath = true
      } label: {
        Label(model.language == "en" ? "Signal path" : "信号路径", systemImage: "waveform.path.ecg")
      }
      Button {
        showEqualizer = true
      } label: {
        Label(model.language == "en" ? "Equalizer" : "均衡器", systemImage: "slider.horizontal.3")
      }
      Button {
        onAction(["action": "externalMetadataRefresh"])
      } label: {
        Label(
          model.language == "en" ? "Refresh external metadata" : "重新获取外源数据",
          systemImage: "arrow.clockwise"
        )
      }
      .disabled(model.metadataLoading)

      if model.showPlayerOutputInMenu {
        Divider()
        Picker(selection: Binding(
          get: { outputSource },
          set: { onAction(["action": "outputSource", "mode": $0]) }
        )) {
          Text(model.language == "en" ? "Local" : "本地").tag("local")
          Text(model.language == "en" ? "Media" : "流媒体").tag("streaming")
          Text("ECHO").tag("echo")
          Text(model.language == "en" ? "Remote" : "远程").tag("remote")
        } label: {
          Label(model.language == "en" ? "Music source" : "音乐源", systemImage: "music.note.list")
        }
        if outputSource == "echo" || outputSource == "remote" {
          Picker(selection: Binding(
            get: { model.outputMode },
            set: { onAction(["action": "output", "mode": $0]) }
          )) {
            Text(model.language == "en" ? "Control" : "控制")
              .tag(outputSource == "echo" ? "pc" : "remoteControl")
            Text(model.language == "en" ? "Stream" : "串流")
              .tag(outputSource == "echo" ? "phone" : "remoteStream")
          } label: {
            Label(model.language == "en" ? "Output mode" : "输出模式", systemImage: "waveform")
          }
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(.system(size: 17, weight: .bold))
        .foregroundColor(echoInk)
        .frame(width: 44, height: 44)
        .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
    }
    .accessibilityLabel(model.language == "en" ? "More playback controls" : "更多播放控制")
  }

  private var outputControl: some View {
    Group {
      if outputSource == "echo" || outputSource == "remote" {
        GeometryReader { geometry in
          HStack(spacing: 8) {
            outputSourcePicker
              .frame(width: max(0, geometry.size.width * 0.62 - 4))
            outputModePicker
          }
        }
        .frame(height: 32)
      } else {
        outputSourcePicker
          .frame(height: 32)
      }
    }
    .controlSize(.small)
    .tint(echoAccent)
    .accessibilityLabel(model.language == "en" ? "Playback output" : "播放输出")
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: outputSource)
  }

  private var outputSourcePicker: some View {
    Picker("", selection: Binding(
      get: { outputSource },
      set: { onAction(["action": "outputSource", "mode": $0]) }
    )) {
      Text(model.language == "en" ? "Local" : "本地").tag("local")
      Text(model.language == "en" ? "Media" : "流媒").tag("streaming")
      Text("ECHO").tag("echo")
      Text(model.language == "en" ? "Remote" : "远程").tag("remote")
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: .infinity)
  }

  private var outputModePicker: some View {
    Picker("", selection: Binding(
      get: { model.outputMode },
      set: { onAction(["action": "output", "mode": $0]) }
    )) {
      Text(model.language == "en" ? "Control" : "控制")
        .tag(outputSource == "echo" ? "pc" : "remoteControl")
      Text(model.language == "en" ? "Stream" : "串流")
        .tag(outputSource == "echo" ? "phone" : "remoteStream")
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: .infinity)
  }

  private var outputSource: String {
    switch model.outputMode {
    case "local": return "local"
    case "streaming": return "streaming"
    case "remoteControl", "remoteStream": return "remote"
    default: return "echo"
    }
  }

  private var showsConnectionStatus: Bool {
    outputSource == "echo" || outputSource == "remote"
  }

  private func roundButton(symbol: String, label: String, size: CGFloat, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: size * 0.34, weight: .bold))
        .foregroundColor(echoInk)
        .frame(width: size, height: size)
        .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
    }
    .buttonStyle(.plain)
    .disabled(!model.controlsEnabled)
    .opacity(model.controlsEnabled ? 1 : 0.35)
    .accessibilityLabel(label)
  }

  private func iconButton(
    symbol: String,
    label: String,
    active: Bool,
    value: String? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      ZStack {
        Image(systemName: symbol)
          .id(symbol)
          .transition(.asymmetric(
            insertion: .scale(scale: 0.62).combined(with: .opacity),
            removal: .scale(scale: 1.28).combined(with: .opacity)
          ))
      }
      .font(.system(size: 16, weight: .semibold))
      .foregroundColor(active ? echoAccent : echoInk)
      .frame(width: 44, height: 44)
      .echoGlass(
        tint: active ? Color.black.opacity(0.14) : Color.white.opacity(0.12),
        clear: !active,
        in: Circle()
      )
    }
    .buttonStyle(.plain)
    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: symbol)
    .accessibilityLabel(label)
    .accessibilityValue(value ?? (active
      ? (model.language == "en" ? "On" : "已开启")
      : (model.language == "en" ? "Off" : "已关闭")))
  }

  private func formatTime(_ milliseconds: Double) -> String {
    let seconds = max(0, Int(milliseconds / 1000))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private var artistLabel: String {
    let artist = model.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    return artist.isEmpty ? (model.language == "en" ? "Unknown Artist" : "未知艺术家") : artist
  }

  private var albumLabel: String {
    let album = model.album.trimmingCharacters(in: .whitespacesAndNewlines)
    return album.isEmpty ? (model.language == "en" ? "Unknown Album" : "未知专辑") : album
  }

  private var titleLabel: String {
    let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? (model.language == "en" ? "No song is playing" : "没有正在播放的歌曲") : title
  }
}

private struct EchoNativeProgressControl: View {
  @ObservedObject var clock: EchoNativePlaybackClockModel
  let controlsEnabled: Bool
  let durationMs: Double
  let language: String
  let onSeek: (Double) -> Void
  @State private var isSeeking = false
  @State private var seekValue = 0.0

  var body: some View {
    VStack(spacing: 4) {
      Slider(
        value: $seekValue,
        in: 0...max(1, durationMs),
        onEditingChanged: { editing in
          isSeeking = editing
          if !editing { onSeek(seekValue) }
        }
      )
      .tint(echoAccent)
      .disabled(!controlsEnabled || durationMs <= 0)
      .accessibilityLabel(language == "en" ? "Playback position" : "播放进度")
      .accessibilityValue("\(formatTime(seekValue)) / \(formatTime(durationMs))")
      HStack {
        Text(formatTime(seekValue))
        Spacer()
        Text(formatTime(durationMs))
      }
      .font(.system(size: 10, weight: .medium, design: .monospaced))
      .foregroundColor(echoInk.opacity(0.48))
    }
    .onAppear { seekValue = min(clock.positionMs, max(0, durationMs)) }
    .onChange(of: clock.positionMs) { value in
      if !isSeeking { seekValue = min(value, max(0, durationMs)) }
    }
    .onChange(of: durationMs) { value in
      if !isSeeking { seekValue = min(clock.positionMs, max(0, value)) }
    }
  }

  private func formatTime(_ milliseconds: Double) -> String {
    let seconds = max(0, Int(milliseconds / 1000))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

private struct EchoNativeArtworkLoadingBadge: View {
  let language: String
  let compact: Bool

  var body: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .tint(echoInk)
      .scaleEffect(compact ? 0.82 : 1)
      .frame(width: compact ? 36 : 46, height: compact ? 36 : 46)
      .echoGlass(
        tint: Color.white.opacity(0.18),
        clear: false,
        interactive: false,
        in: Circle()
      )
      .shadow(color: Color.black.opacity(0.1), radius: 10, y: 4)
      .accessibilityLabel(language == "en" ? "Loading artwork and lyrics" : "正在加载封面和歌词")
  }
}

private struct EchoNativeArtworkBackdrop: View {
  let enabled: Bool
  let identity: String
  let urlString: String
  let onError: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @State private var stableIdentity = ""
  @State private var stableUrl = ""

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        echoWarmBackground

        if !stableUrl.isEmpty {
          artworkLayer(url: stableUrl, size: geometry.size, showsPlaceholder: false)
            .transition(.opacity)
        }

        if !urlString.isEmpty && (urlString != stableUrl || identity != stableIdentity) {
          artworkLayer(
            url: urlString,
            size: geometry.size,
            showsPlaceholder: false,
            onLoad: {
              stableIdentity = identity
              stableUrl = urlString
            },
            onFailure: {
              if stableIdentity != identity {
                stableIdentity = identity
                stableUrl = ""
              }
              onError()
            }
          )
          .id("\(identity)::\(urlString)")
        }

        LinearGradient(
          colors: colorScheme == .dark
            ? [Color.black.opacity(0.3), Color.black.opacity(0.18), Color.black.opacity(0.24)]
            : [
              Color.white.opacity(0.18),
              Color(red: 0.98, green: 0.90, blue: 0.86).opacity(0.12),
              Color.white.opacity(0.1),
            ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .frame(width: geometry.size.width, height: geometry.size.height)
      .clipped()
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: stableUrl)
    .onChange(of: identity) { _ in
      if urlString.isEmpty {
        stableIdentity = identity
        stableUrl = ""
      }
    }
    .onChange(of: urlString) { value in
      if value.isEmpty && (!enabled || stableIdentity != identity) {
        stableIdentity = identity
        stableUrl = ""
      }
    }
    .onChange(of: enabled) { value in
      if !value {
        stableIdentity = identity
        stableUrl = ""
      }
    }
  }

  private func artworkLayer(
    url: String,
    size: CGSize,
    showsPlaceholder: Bool,
    onLoad: @escaping () -> Void = {},
    onFailure: @escaping () -> Void = {}
  ) -> some View {
    EchoNativeArtwork(
      urlString: url,
      squarePreview: false,
      showsPlaceholder: showsPlaceholder,
      onLoad: onLoad,
      onError: onFailure
    )
    .frame(width: size.width, height: size.height)
    .scaledToFill()
    .scaleEffect(1.06)
    .saturation(1.04)
    .blur(radius: 14, opaque: true)
    .clipped()
  }
}

private struct EchoNativeExternalSourcePicker: View {
  let payload: EchoNativeExternalSourcePickerPayload
  let onAction: ([String: Any]) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var selectedSources: [String: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(payload.title)
            .font(.system(size: 24, weight: .bold, design: .rounded))
          Text(payload.subtitle)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(echoInk.opacity(0.56))
        }
        Spacer(minLength: 8)
        Button {
          onAction(["action": "externalSourcePickerDismiss"])
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 44, height: 44)
            .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(payload.cancelLabel)
      }

      ScrollView(showsIndicators: false) {
        LazyVStack(spacing: 0) {
          ForEach(Array(payload.candidates.enumerated()), id: \.element.id) { index, candidate in
          VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 13) {
              EchoNativeArtwork(urlString: candidate.albumArt ?? "", onError: {})
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

              VStack(alignment: .leading, spacing: 5) {
                Text(candidate.title)
                  .font(.system(size: 15, weight: .bold))
                  .foregroundColor(echoInk)
                  .lineLimit(1)
                Text([candidate.artist ?? "", candidate.sourceLabel]
                  .filter { !$0.isEmpty }
                  .joined(separator: " · "))
                  .font(.system(size: 12, weight: .semibold))
                  .foregroundColor(echoInk.opacity(0.5))
                  .lineLimit(1)
              }
              Spacer(minLength: 8)
              Text(candidate.availableLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(echoInk.opacity(0.46))
                .multilineTextAlignment(.trailing)
            }

            HStack(spacing: 8) {
              fieldButton(
                field: "lyrics",
                label: payload.lyricsLabel,
                available: candidate.hasLyrics,
                candidate: candidate
              )
              fieldButton(
                field: "artist",
                label: payload.artistLabel,
                available: candidate.hasArtist,
                candidate: candidate
              )
              fieldButton(
                field: "albumArt",
                label: payload.artworkLabel,
                available: candidate.hasArtwork,
                candidate: candidate
              )
            }
          }
          .padding(.vertical, 12)

          if index < payload.candidates.count - 1 {
            Divider().opacity(0.45)
          }
          }
        }
      }
      .frame(maxHeight: .infinity, alignment: .top)

      HStack(spacing: 10) {
        Button {
          onAction(["action": "externalSourcePickerIgnore"])
          dismiss()
        } label: {
          Text(payload.ignoreLabel)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(echoInk.opacity(0.68))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .echoGlass(tint: Color.white.opacity(0.1), clear: false, in: Capsule())
        }
        .buttonStyle(.plain)

        Button {
          onAction([
            "action": "externalFieldSourcesSelect",
            "selections": selectedSources,
          ])
          dismiss()
        } label: {
          Text(payload.doneLabel)
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .echoGlass(tint: echoAccent.opacity(0.72), clear: false, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!selectionComplete)
        .opacity(selectionComplete ? 1 : 0.38)
      }
    }
    .padding(22)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundColor(echoInk)
    .background(echoWarmBackground.ignoresSafeArea())
    .interactiveDismissDisabled()
    .onAppear {
      for field in requiredFields where selectedSources[field] == nil {
        selectedSources[field] = preferredCandidate(for: field)?.id
      }
    }
  }

  private var requiredFields: [String] {
    var fields: [String] = []
    if payload.candidates.contains(where: { $0.hasLyrics }) { fields.append("lyrics") }
    if payload.candidates.contains(where: { $0.hasArtist }) { fields.append("artist") }
    if payload.candidates.contains(where: { $0.hasArtwork }) { fields.append("albumArt") }
    return fields
  }

  private var selectionComplete: Bool {
    requiredFields.allSatisfy { selectedSources[$0] != nil }
  }

  private func preferredCandidate(for field: String) -> EchoNativeExternalSourceCandidate? {
    let sources = field == "lyrics"
      ? ["lrclib", "lrcapi", "netease"]
      : field == "albumArt" ? ["netease", "lrcapi", "lrclib"] : ["lrcapi", "netease", "lrclib"]
    let available: (EchoNativeExternalSourceCandidate) -> Bool = { candidate in
      field == "lyrics" ? candidate.hasLyrics : field == "artist" ? candidate.hasArtist : candidate.hasArtwork
    }
    for source in sources {
      if let candidate = payload.candidates.first(where: { $0.source == source && available($0) }) {
        return candidate
      }
    }
    return payload.candidates.first(where: available)
  }

  private func fieldButton(
    field: String,
    label: String,
    available: Bool,
    candidate: EchoNativeExternalSourceCandidate
  ) -> some View {
    let selected = selectedSources[field] == candidate.id
    return Button {
      selectedSources[field] = candidate.id
    } label: {
      VStack(spacing: 3) {
        Text(label)
          .font(.system(size: 12, weight: .bold))
        Text(available ? (selected ? payload.selectedLabel : payload.useSourceLabel) : payload.unavailableLabel)
          .font(.system(size: 9, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      .foregroundColor(selected ? Color.white : echoInk.opacity(available ? 0.72 : 0.28))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .background(selected ? echoAccent : Color.clear, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(echoInk.opacity(available ? 0.14 : 0.06), lineWidth: 0.8))
    }
    .buttonStyle(.plain)
    .disabled(!available)
    .accessibilityLabel("\(label), \(available ? payload.useSourceLabel : payload.unavailableLabel), \(candidate.sourceLabel)")
  }
}

private struct EchoNativeQueueSheet: View {
  @ObservedObject var model: EchoNativePlayerModel
  let onAction: ([String: Any]) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showClearConfirmation = false

  var body: some View {
    VStack(spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(model.queuePayload?.title ?? (model.language == "en" ? "Queue" : "播放列表"))
            .font(.system(size: 24, weight: .bold, design: .rounded))
          if let subtitle = model.queuePayload?.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(echoInk.opacity(0.5))
              .lineLimit(1)
          }
        }
        Spacer()
        if model.queuePayload?.canEdit == true, !(model.queuePayload?.items.isEmpty ?? true) {
          Button(model.queuePayload?.clearLabel ?? (model.language == "en" ? "Clear" : "清空")) {
            if model.queuePayload?.playlistId.isEmpty == false {
              showClearConfirmation = true
            } else {
              clearQueue()
            }
          }
          .font(.system(size: 12, weight: .bold))
          .foregroundColor(echoAccent)
          .padding(.horizontal, 12)
          .frame(minHeight: 44)
          .contentShape(Capsule())
          .echoGlass(tint: Color.white.opacity(0.1), in: Capsule())
          .buttonStyle(.plain)
        }
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 44, height: 44)
            .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(.plain)
      }

      if let payload = model.queuePayload, !payload.items.isEmpty {
        ScrollView(.vertical, showsIndicators: true) {
          LazyVStack(spacing: 0) {
            ForEach(Array(payload.items.enumerated()), id: \.element.id) { index, item in
              HStack(spacing: 10) {
                Button {
                  dismiss()
                  onAction([
                    "action": "queuePlay",
                    "id": item.trackId,
                    "playlistId": payload.playlistId,
                    "source": item.source,
                  ])
                } label: {
                  HStack(spacing: 11) {
                    Group {
                      if item.current {
                        Image(systemName: "play.circle.fill")
                          .font(.system(size: 19, weight: .bold))
                      } else {
                        Text(String(format: "%02d", index + 1))
                          .font(.system(size: 11, weight: .bold, design: .monospaced))
                      }
                    }
                    .foregroundColor(item.current ? echoAccent : echoInk.opacity(0.36))
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(item.current ? echoAccent : echoInk)
                        .lineLimit(1)
                      Text(item.meta.isEmpty ? item.artist : "\(item.artist) · \(item.meta)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(echoInk.opacity(0.48))
                        .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if payload.canEdit {
                  queueButton(
                    symbol: "chevron.up",
                    label: payload.moveUpLabel,
                    disabled: index == 0
                  ) {
                    onAction([
                      "action": "queueMove",
                      "id": item.trackId,
                      "index": index,
                      "playlistId": payload.playlistId,
                      "source": item.source,
                      "value": -1,
                    ])
                  }
                  queueButton(
                    symbol: "chevron.down",
                    label: payload.moveDownLabel,
                    disabled: index == payload.items.count - 1
                  ) {
                    onAction([
                      "action": "queueMove",
                      "id": item.trackId,
                      "index": index,
                      "playlistId": payload.playlistId,
                      "source": item.source,
                      "value": 1,
                    ])
                  }
                  queueButton(symbol: "xmark", label: payload.removeLabel) {
                    onAction([
                      "action": "queueRemove",
                      "id": item.trackId,
                      "index": index,
                      "playlistId": payload.playlistId,
                      "source": item.source,
                    ])
                  }
                }
              }
              .padding(.vertical, 11)
              .padding(.horizontal, 7)
              .background(item.current ? echoAccent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 13))
              .overlay(alignment: .bottom) {
                Rectangle().fill(echoInk.opacity(0.08)).frame(height: 0.7)
              }
            }
          }
        }
        .frame(maxHeight: .infinity)
      } else {
        VStack(spacing: 12) {
          Image(systemName: "music.note.list")
            .font(.system(size: 28, weight: .medium))
          Text(model.queuePayload?.emptyLabel ?? (model.language == "en" ? "The queue is empty." : "当前播放列表暂无内容。"))
            .font(.system(size: 13, weight: .semibold))
        }
        .foregroundColor(echoInk.opacity(0.42))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(20)
    .foregroundColor(echoInk)
    .background(Color.clear)
    .confirmationDialog(
      model.language == "en" ? "Clear this playlist?" : "清空这个歌单？",
      isPresented: $showClearConfirmation,
      titleVisibility: .visible
    ) {
      Button(model.queuePayload?.clearLabel ?? (model.language == "en" ? "Clear" : "清空"), role: .destructive) {
        clearQueue()
      }
      Button(model.language == "en" ? "Cancel" : "取消", role: .cancel) {}
    } message: {
      Text(model.language == "en" ? "This removes every track from the saved playlist." : "这会从已保存歌单中移除全部歌曲。")
    }
  }

  private func clearQueue() {
    onAction([
      "action": "queueClear",
      "playlistId": model.queuePayload?.playlistId ?? "",
      "source": model.queuePayload?.source ?? "echo",
    ])
  }

  private func queueButton(
    symbol: String,
    label: String,
    disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .bold))
        .frame(width: 44, height: 44)
        .echoGlass(tint: Color.white.opacity(0.1), in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.3 : 1)
    .accessibilityLabel(label)
  }
}

struct EchoNativeArtwork: View {
  let urlString: String
  var squarePreview = true
  var showsPlaceholder = true
  var onLoad: () -> Void = {}
  let onError: () -> Void
  @StateObject private var localLoader = EchoNativeLocalArtworkLoader()

  @ViewBuilder
  var body: some View {
    if squarePreview {
      GeometryReader { geometry in
        artworkContent
          .frame(width: geometry.size.width, height: geometry.size.height)
          .clipped()
      }
      .aspectRatio(1, contentMode: .fit)
      .clipped()
    } else {
      artworkContent
    }
  }

  @ViewBuilder
  private var artworkContent: some View {
    if let url = URL(string: urlString), url.isFileURL {
      Group {
        if let image = localLoader.image {
          Image(uiImage: image).resizable().scaledToFill().onAppear(perform: onLoad)
        } else {
          fallback
        }
      }
      .onAppear { localLoader.load(url, maxPixelSize: localArtworkPixelSize) }
      .onChange(of: urlString) { _ in localLoader.load(url, maxPixelSize: localArtworkPixelSize) }
      .onChange(of: localLoader.failed) { failed in
        if failed { onError() }
      }
    } else if let url = URL(string: urlString), !urlString.isEmpty {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill().onAppear(perform: onLoad)
        case .failure:
          fallback.onAppear(perform: onError)
        default:
          fallback
        }
      }
    } else {
      fallback
    }
  }

  private var localArtworkPixelSize: CGFloat { squarePreview ? 900 : 1_600 }

  @ViewBuilder
  private var fallback: some View {
    if showsPlaceholder { placeholder } else { Color.clear }
  }

  private var placeholder: some View {
    ZStack {
      LinearGradient(
        colors: [Color.white.opacity(0.32), echoGold.opacity(0.22)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Image(systemName: "waveform")
        .font(.system(size: 34, weight: .medium))
        .foregroundColor(echoInk.opacity(0.3))
    }
  }
}

private final class EchoNativeLocalArtworkLoader: ObservableObject {
  private static let cache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 60
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()
  @Published var failed = false
  @Published var image: UIImage?
  private var requestedKey = ""

  func load(_ url: URL, maxPixelSize: CGFloat) {
    let path = url.path
    let pixelSize = max(1, Int(maxPixelSize.rounded()))
    let key = "\(path)::\(pixelSize)"
    guard key != requestedKey || image == nil else { return }
    requestedKey = key
    failed = false
    if let cached = Self.cache.object(forKey: key as NSString) {
      image = cached
      return
    }
    image = nil
    DispatchQueue.global(qos: .userInitiated).async {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: pixelSize,
      ]
      let decoded = CGImageSourceCreateWithURL(url as CFURL, nil)
        .flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
        .map { UIImage(cgImage: $0) }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.requestedKey == key else { return }
        if let decoded {
          let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
          Self.cache.setObject(decoded, forKey: key as NSString, cost: cost)
          self.image = decoded
        } else {
          self.failed = true
        }
      }
    }
  }
}


struct EchoNativeDacObservation: Codable, Identifiable, Equatable {
  private static let storageKey = "echo.native.dac-observations.v1"

  let id: String
  var channelCounts: [Int]
  var firstSeenAt: Date
  var lastSeenAt: Date
  var name: String
  var observationCount: Int
  var portType: String
  var sampleRates: [Double]

  static func load() -> [String: EchoNativeDacObservation] {
    guard let data = UserDefaults.standard.data(forKey: storageKey),
      let values = try? JSONDecoder().decode([EchoNativeDacObservation].self, from: data)
    else { return [:] }
    return values.reduce(into: [:]) { profiles, value in profiles[value.id] = value }
  }

  static func save(_ profiles: [String: EchoNativeDacObservation]) {
    let values = profiles.values.sorted { $0.lastSeenAt > $1.lastSeenAt }.prefix(24)
    guard let data = try? JSONEncoder().encode(Array(values)) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}

struct EchoNativeSignalRouteEvent: Codable, Identifiable, Equatable {
  private static let storageKey = "echo.native.signal-route-events.v1"

  let id: String
  let tone: String
  let title: String
  let detail: String
  let trackTitle: String
  let at: Date

  static func load() -> [EchoNativeSignalRouteEvent] {
    guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
    return (try? JSONDecoder().decode([EchoNativeSignalRouteEvent].self, from: data)).map { Array($0.prefix(20)) } ?? []
  }

  static func save(_ events: [EchoNativeSignalRouteEvent]) {
    guard let data = try? JSONEncoder().encode(Array(events.prefix(20))) else { return }
    UserDefaults.standard.set(data, forKey: storageKey)
  }
}

private struct EchoNativeSignalLiveMeter: View {
  @ObservedObject var model: EchoNativeSignalMeterModel
  let external: Bool
  let english: Bool
  let tone: Color

  private var hasLevel: Bool { model.peakDb > -120 }

  private var fill: Double {
    hasLevel ? max(0, min(1, (model.peakDb + 60) / 60)) : 0
  }

  private var peakLabel: String {
    hasLevel ? String(format: "%.1f dBFS", model.peakDb) : (external ? (english ? "External" : "外部") : "-- dBFS")
  }

  private var detail: String {
    guard hasLevel else {
      return external
        ? (english ? "The remote endpoint has not reported live levels." : "远程端尚未上报实时电平。")
        : (english ? "RMS -- dBFS · meter active during playback" : "RMS -- dBFS · 播放时启用电平表")
    }
    var parts = [String(format: "RMS %.1f dBFS", model.rmsDb)]
    if let lufs = model.lufsMomentary { parts.append(String(format: "LUFS-M %.1f", lufs)) }
    return parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(english ? "LIVE OUTPUT PEAK" : "实时输出峰值")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(echoInk.opacity(0.48))
          Text(detail)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        }
        Spacer(minLength: 8)
        Text(peakLabel)
          .font(.system(size: 14, weight: .bold, design: .monospaced))
          .foregroundColor(model.clipping || model.peakDb > -3 ? echoAccent : tone)
      }
      ProgressView(value: fill)
        .tint(model.clipping || model.peakDb > -3 ? echoAccent : echoGold)
      if hasLevel && (model.clipping || model.peakDb > -3) {
        Label(
          english ? "Low headroom: reduce positive gain if clipping is audible." : "输出余量偏低；如出现削波，请降低正向增益。",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(echoAccent)
      }
    }
  }
}

private struct EchoNativeSignalIconAnchorKey: PreferenceKey {
  static var defaultValue: [Anchor<CGPoint>] = []

  static func reduce(value: inout [Anchor<CGPoint>], nextValue: () -> [Anchor<CGPoint>]) {
    value.append(contentsOf: nextValue())
  }
}

private struct EchoNativeSignalPathSheet: View {
  @ObservedObject var model: EchoNativePlayerModel
  let onAction: ([String: Any]) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dacAtlasExpanded = false
  @State private var doctorExpanded = false
  @State private var flightRecorderExpanded = false

  private var english: Bool { model.language == "en" }

  private var hasTrack: Bool {
    !model.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var usesLocalProcessing: Bool {
    switch model.outputMode {
    case "local", "phone", "remoteStream", "streaming": return true
    default: return false
    }
  }

  private var remoteMode: Bool {
    ["pc", "phone", "remoteControl", "remoteStream"].contains(model.outputMode)
  }

  private var pathOnline: Bool {
    !remoteMode || model.connectionOnline
  }

  private var sourceProvenance: String {
    model.outputMode == "local" ? "observed" : "reported"
  }

  private var sourceSpec: String {
    let parts = [model.signalCodec, model.signalSampleRate, model.signalBitDepth, model.signalBitrate, model.signalChannelCount]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return parts.isEmpty ? (english ? "Format unknown" : "格式未知") : parts.joined(separator: " · ")
  }

  private var processingModules: [String] {
    guard usesLocalProcessing else { return [] }
    var modules: [String] = []
    if model.eqEnabled { modules.append(english ? "10-band EQ" : "十段 EQ") }
    if model.loudnessEnabled { modules.append(english ? "Loudness" : "响度归一化") }
    return modules
  }

  private var summaryLabel: String {
    if !hasTrack { return english ? "Waiting for playback" : "等待播放" }
    if !pathOnline { return english ? "Path unavailable" : "链路不可用" }
    if !processingModules.isEmpty {
      return english ? "Enhanced" : "已增强"
    }
    if usesLocalProcessing {
      return english ? "Native playback" : "原生播放"
    }
    return english ? "Remote path" : "远程链路"
  }

  private var summaryDetail: String {
    if !hasTrack {
      return english ? "Start a track to inspect source, processing, and output." : "开始播放后，可查看音源、处理和输出。"
    }
    if !pathOnline {
      return model.connectionLabel
    }
    if !processingModules.isEmpty {
      return english
        ? "Active processing: \(processingModules.joined(separator: " + "))."
        : "当前处理：\(processingModules.joined(separator: " + "))。"
    }
    return usesLocalProcessing
      ? (english ? "Direct native playback with no additional DSP." : "原生直通播放，未启用额外 DSP。")
      : (english ? "Decode and processing stay on the remote device." : "解码与处理由远程设备负责。")
  }

  private var sourceDetail: String {
    if !hasTrack { return english ? "No current track" : "当前没有歌曲" }
    let artist = model.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = model.signalSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = artist.isEmpty ? model.title : "\(model.title) · \(artist)"
    return source.isEmpty ? base : "\(base)\n\(source)"
  }

  private var processingDetail: String {
    if !hasTrack { return english ? "—" : "—" }
    if !usesLocalProcessing {
      return english ? "Remote device owns DSP" : "DSP 由远程设备负责"
    }
    return processingModules.isEmpty
      ? (english ? "Direct / bypass" : "直通 / 旁路")
      : processingModules.joined(separator: " + ")
  }

  private var decodeValue: String {
    if !hasTrack { return english ? "Waiting" : "等待中" }
    if !usesLocalProcessing { return english ? "Remote decoder" : "远程解码器" }
    if model.signalFileLoaded { return "AVAudioFile → PCM" }
    return english ? "Preparing decoder" : "正在准备解码器"
  }

  private var decodeDetail: String {
    if !usesLocalProcessing {
      return english
        ? "Decoder details are owned by the remote endpoint. · Resampling: ?"
        : "解码器详情由远程端提供。 · 重采样：?"
    }
    let sourceRate = model.signalSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let engineRate = model.signalEngineSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    if !sourceRate.isEmpty && !engineRate.isEmpty {
      parts.append(sourceRate == engineRate ? sourceRate : "\(sourceRate) → \(engineRate)")
    } else if !engineRate.isEmpty {
      parts.append(engineRate)
    }
    if !model.signalChannelCount.isEmpty { parts.append(model.signalChannelCount) }
    parts.append(model.signalEngineRunning
      ? (english ? "Engine running" : "引擎运行中")
      : (english ? "Engine idle" : "引擎空闲"))
    parts.append(resamplingLabel(decoderResampling))
    return parts.joined(separator: " · ")
  }

  private var outputTitle: String {
    switch model.outputMode {
    case "local": return english ? "Local output" : "本机输出"
    case "pc": return english ? "ECHO control" : "ECHO 控制"
    case "phone": return english ? "ECHO stream" : "ECHO 串流"
    case "remoteControl": return english ? "Poweramp control" : "Poweramp 控制"
    case "remoteStream": return english ? "Poweramp stream" : "Poweramp 串流"
    case "streaming": return english ? "NetEase stream" : "网易云串流"
    default: return english ? "Output" : "输出"
    }
  }

  private var outputDetail: String {
    var parts: [String] = []
    let device = model.signalDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let remote = model.signalRemoteOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    switch model.outputMode {
    case "local":
      parts.append(english ? "AVAudioEngine on this iPhone" : "本机 AVAudioEngine")
    case "phone", "remoteStream", "streaming":
      parts.append(english ? "Downloaded then played locally" : "先缓存再本机播放")
    case "pc", "remoteControl":
      parts.append(english ? "Remote device renders audio" : "远程设备负责发声")
    default:
      break
    }
    if !device.isEmpty { parts.append(device) }
    if !remote.isEmpty { parts.append(remote) }
    let deviceFormat = [model.signalDeviceSampleRate, model.signalOutputBitDepth, model.signalDeviceChannelCount]
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
    if !deviceFormat.isEmpty { parts.append(deviceFormat) }
    if model.signalDeviceLatencyMs > 0 {
      parts.append(String(format: english ? "%.1f ms latency" : "%.1f ms 延迟", model.signalDeviceLatencyMs))
    }
    if remoteMode {
      parts.append(model.connectionLabel)
    }
    return parts.isEmpty ? (english ? "Route unknown" : "路径未知") : parts.joined(separator: " · ")
  }

  private var tone: Color {
    if !hasTrack { return echoInk.opacity(0.45) }
    if !pathOnline {
      return echoAccent
    }
    if !processingModules.isEmpty {
      return echoGold
    }
    return Color.green.opacity(0.85)
  }

  private var pathReadiness: Double {
    if !hasTrack { return 0 }
    if !pathOnline { return 0.15 }
    if !usesLocalProcessing { return 1 }
    if model.signalEngineRunning { return 1 }
    if model.signalFileLoaded { return 0.72 }
    return 0.35
  }

  private var readinessLabel: String {
    if !hasTrack { return english ? "No signal" : "无信号" }
    if !pathOnline { return english ? "Disconnected" : "连接中断" }
    if !usesLocalProcessing { return english ? "Remote active" : "远程链路活动" }
    if model.signalEngineRunning { return english ? "Live" : "实时运行" }
    if model.signalFileLoaded { return english ? "Ready" : "已就绪" }
    return english ? "Preparing" : "准备中"
  }

  private var clockValue: String {
    let source = model.signalSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let engine = model.signalEngineSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let device = model.signalDeviceSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    var rates: [String] = []
    for rate in [source, engine, device] where !rate.isEmpty && rates.last != rate {
      rates.append(rate)
    }
    return rates.isEmpty ? (english ? "Unknown" : "未知") : rates.joined(separator: " → ")
  }

  private var decoderResampling: Bool? {
    let source = model.signalSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let engine = model.signalEngineSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, !engine.isEmpty else { return nil }
    return source != engine
  }

  private var clockResampling: Bool? {
    let rates = [model.signalSampleRate, model.signalEngineSampleRate, model.signalDeviceSampleRate]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard rates.count > 1 else { return nil }
    return Set(rates).count > 1
  }

  private func resamplingLabel(_ active: Bool?) -> String {
    switch active {
    case true: return english ? "Resampling: active" : "重采样：启用"
    case false: return english ? "Resampling: bypassed" : "重采样：旁路"
    case nil: return english ? "Resampling: ?" : "重采样：?"
    }
  }

  var body: some View {
    ZStack {
      echoWarmBackground.ignoresSafeArea()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          header
          summary
          theater
          signalChain
          doctor
          dacAtlas
          flightRecorder
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 32)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
      }
    }
    .onAppear { onAction(["action": "signalPathVisible", "visible": true]) }
    .onDisappear { onAction(["action": "signalPathVisible", "visible": false]) }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(english ? "Signal path" : "信号路径")
          .font(.system(size: 25, weight: .bold, design: .rounded))
        Text(english ? "\(summaryLabel) · 4 stages" : "\(summaryLabel) · 4 层")
          .font(.system(size: 12, weight: .semibold))
          .foregroundColor(tone)
      }
      Spacer(minLength: 8)
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .bold))
          .frame(width: 44, height: 44)
          .echoGlass(tint: Color.white.opacity(0.14), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(english ? "Close signal path" : "关闭信号路径")
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(sourceSpec)
        .font(.system(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(tone)
      Text(summaryDetail)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(echoInk.opacity(0.62))
        .fixedSize(horizontal: false, vertical: true)
      Divider()
      HStack(spacing: 12) {
        provenanceMark("observed")
        provenanceMark("reported")
        provenanceMark("unverified")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(15)
    .echoGlass(tint: tone.opacity(0.08), clear: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var theater: some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionTitle(english ? "Signal theater" : "信号剧场", icon: "waveform.path.ecg")
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(english ? "PATH READINESS" : "链路就绪度")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(echoInk.opacity(0.48))
          Text(readinessLabel)
            .font(.system(size: 20, weight: .bold, design: .rounded))
        }
        Spacer()
        Text("\(Int(pathReadiness * 100))%")
          .font(.system(size: 14, weight: .bold, design: .monospaced))
          .foregroundColor(tone)
      }
      ProgressView(value: pathReadiness)
        .tint(tone)
      Divider()
      EchoNativeSignalLiveMeter(
        model: model.signalMeter,
        external: !usesLocalProcessing,
        english: english,
        tone: tone
      )
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        metric(english ? "Source" : "音源", value: model.signalSourceLabel.isEmpty ? (english ? "Unknown" : "未知") : model.signalSourceLabel, detail: sourceSpec)
        metric(english ? "Processing" : "处理", value: processingDetail, detail: usesLocalProcessing ? "AVAudioEngine" : (english ? "Remote endpoint" : "远程端"))
        metric(english ? "Output" : "输出", value: outputTitle, detail: model.signalDeviceName.isEmpty ? (english ? "Unknown device" : "未知设备") : model.signalDeviceName)
        metric(english ? "Clock" : "时钟", value: clockValue, detail: resamplingLabel(clockResampling))
      }
    }
  }

  private var signalChain: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle(english ? "Full chain" : "完整链路", icon: "point.3.connected.trianglepath.dotted")
      VStack(spacing: 10) {
        signalNode(index: "01", icon: "externaldrive.fill", title: english ? "Source" : "音源", value: model.signalSourceLabel.isEmpty ? (english ? "Unknown source" : "未知音源") : model.signalSourceLabel, detail: sourceDetail, provenance: sourceProvenance, nodeTone: hasTrack ? Color.green : echoInk.opacity(0.4))
        signalNode(index: "02", icon: "cpu", title: english ? "Decode" : "解码", value: decodeValue, detail: decodeDetail, provenance: usesLocalProcessing ? model.signalTelemetrySource : (model.signalTelemetrySource == "reported" ? "reported" : "unverified"), nodeTone: model.signalFileLoaded || !usesLocalProcessing ? Color.green : echoGold)
        signalNode(index: "03", icon: processingModules.isEmpty ? "checkmark.shield.fill" : "slider.horizontal.3", title: english ? "Process" : "处理", value: processingDetail, detail: usesLocalProcessing ? (english ? "Local DSP chain" : "本机 DSP 链") : (english ? "External processing" : "外部处理"), provenance: usesLocalProcessing ? model.signalTelemetrySource : "unverified", nodeTone: processingModules.isEmpty ? Color.green : echoGold)
        signalNode(index: "04", icon: "hifispeaker.fill", title: english ? "Output" : "输出", value: outputTitle, detail: outputDetail, provenance: model.signalTelemetrySource, nodeTone: pathOnline ? Color.green : echoAccent)
      }
      .backgroundPreferenceValue(EchoNativeSignalIconAnchorKey.self) { anchors in
        GeometryReader { proxy in
          if anchors.count >= 4 {
            let points = anchors.prefix(4).map { proxy[$0] }
            let start = points[0]
            let end = points[3]
            Path { path in
              path.move(to: start)
              for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(tone.opacity(0.24), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
              let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 2.4) / 2.4
              let position = CGFloat(progress)
              Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
                .shadow(color: tone.opacity(0.45), radius: 4)
                .opacity(reduceMotion ? 0 : sin(progress * .pi))
                .position(
                  x: start.x + (end.x - start.x) * position,
                  y: start.y + (end.y - start.y) * position
                )
            }
          }
        }
      }
    }
  }

  private var doctor: some View {
    DisclosureGroup(isExpanded: $doctorExpanded) {
      VStack(spacing: 10) {
        doctorInsights
      }
      .padding(.top, 12)
    } label: {
      disclosureLabel(
        english ? "Signal doctor" : "信号医生",
        detail: english ? "Inspect path quality and blockers" : "检查链路质量与限制",
        icon: "stethoscope"
      )
    }
    .tint(echoAccent)
    .padding(15)
    .echoGlass(tint: Color.white.opacity(0.06), clear: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var dacAtlas: some View {
    DisclosureGroup(isExpanded: $dacAtlasExpanded) {
      VStack(alignment: .leading, spacing: 12) {
        if usesLocalProcessing, let profile = model.signalDacProfile {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric(english ? "Current route" : "当前路由", value: profile.name, detail: model.signalDevicePortType.isEmpty ? profile.portType : model.signalDevicePortType)
            metric(english ? "Current format" : "当前格式", value: [model.signalDeviceSampleRate, model.signalDeviceChannelCount].filter { !$0.isEmpty }.joined(separator: " · "), detail: provenanceText("observed"))
            metric(english ? "Observed rates" : "观测采样率", value: profile.sampleRates.map(formatObservedRate).joined(separator: " · "), detail: english ? "Seen on this route" : "此路由历史观测")
            metric(english ? "Observed channels" : "观测声道", value: profile.channelCounts.map { "\($0)ch" }.joined(separator: " · "), detail: english ? "Seen on this route" : "此路由历史观测")
            metric(english ? "Latency / buffer" : "延迟 / 缓冲", value: String(format: "%.1f / %.1f ms", model.signalDeviceLatencyMs, model.signalDeviceIOBufferMs), detail: english ? "Output / I/O buffer" : "输出 / I/O 缓冲")
            metric(english ? "System volume" : "系统音量", value: "\(Int((model.signalOutputVolume * 100).rounded()))%", detail: english ? "AVAudioSession output" : "AVAudioSession 输出")
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(english ? "ROUTE UID" : "路由 UID")
              .font(.system(size: 9, weight: .bold))
              .foregroundColor(echoInk.opacity(0.45))
            Text(model.signalDeviceUID.isEmpty ? profile.id : model.signalDeviceUID)
              .font(.system(size: 10, weight: .medium, design: .monospaced))
              .foregroundColor(echoInk.opacity(0.58))
              .textSelection(.enabled)
            Text(english ? "\(profile.observationCount) format observations · last seen" : "已记录 \(profile.observationCount) 次格式观测 · 最近出现")
              .font(.system(size: 10, weight: .medium))
              .foregroundColor(echoInk.opacity(0.48))
            Text(profile.lastSeenAt, style: .relative)
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(echoInk.opacity(0.58))
          }
          Text(english ? "This atlas records formats actually observed on the route. It does not claim the DAC's advertised maximum capability." : "图谱只记录此路由实际出现过的格式，不代表 DAC 宣称的最高能力。")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        } else if model.signalTelemetrySource == "reported" {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric(english ? "Remote device" : "远程设备", value: model.signalDeviceName, detail: model.signalDevicePortType.isEmpty ? model.signalRemoteOutput : model.signalDevicePortType)
            metric(english ? "Reported format" : "上报格式", value: [model.signalDeviceSampleRate, model.signalOutputBitDepth, model.signalDeviceChannelCount].filter { !$0.isEmpty }.joined(separator: " · "), detail: provenanceText("reported"))
            metric(english ? "Output mode" : "输出模式", value: model.signalExclusive.map { $0 ? "Exclusive" : "Shared" } ?? model.signalRemoteOutput, detail: english ? "Endpoint report" : "远程端上报")
            metric(english ? "Latency" : "延迟", value: model.signalDeviceLatencyMs > 0 ? String(format: "%.1f ms", model.signalDeviceLatencyMs) : (english ? "Not reported" : "未上报"), detail: provenanceText("reported"))
          }
          Text(english ? "Remote values are accepted from the paired endpoint and are not independently measured by this iPhone." : "远程数据来自配对端上报，本机无法独立测量验证。")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        } else {
          Label(
            english ? "No verifiable DAC telemetry is available for this route." : "当前链路没有可验证的 DAC 遥测。",
            systemImage: "questionmark.circle"
          )
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(echoInk.opacity(0.55))
        }
      }
      .padding(.top, 12)
    } label: {
      disclosureLabel(
        english ? "DAC capability atlas" : "DAC 能力图谱",
        detail: model.signalDeviceName.isEmpty ? (english ? "Observed route capabilities" : "已观测路由能力") : model.signalDeviceName,
        icon: "waveform.path.ecg"
      )
    }
    .tint(echoAccent)
    .padding(15)
    .echoGlass(tint: Color.white.opacity(0.06), clear: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  @ViewBuilder
  private var doctorInsights: some View {
    if !hasTrack {
      insight(english ? "WAITING" : "等待", title: english ? "No active signal" : "当前没有活动信号", detail: english ? "Start playback to inspect decode, DSP, and output state." : "开始播放后可检查解码、DSP 与输出状态。", advice: english ? "No action required." : "无需操作。", insightTone: echoInk.opacity(0.48))
    } else {
      if !pathOnline {
        insight(english ? "CONNECTION" : "连接", title: english ? "Remote path is unavailable" : "远程链路不可用", detail: model.connectionLabel, advice: english ? "Check the paired device and network, then reconnect." : "检查配对设备和网络后重新连接。", insightTone: echoAccent)
      }
      if usesLocalProcessing && !model.signalFileLoaded {
        insight(english ? "DECODER" : "解码", title: english ? "Audio file is not loaded" : "音频文件尚未加载", detail: english ? "The local engine has not established a PCM stream." : "本机引擎尚未建立 PCM 音频流。", advice: english ? "Wait for caching to finish or retry playback." : "等待缓存完成，或重试播放。", insightTone: echoGold)
      }
      if !model.signalSampleRate.isEmpty && !model.signalEngineSampleRate.isEmpty && model.signalSampleRate != model.signalEngineSampleRate {
        insight(english ? "CLOCK" : "时钟", title: english ? "Sample-rate conversion is active" : "采样率转换已启用", detail: "\(model.signalSampleRate) → \(model.signalEngineSampleRate)", advice: english ? "This is expected when the decoded stream and engine rate differ." : "解码流与引擎采样率不同时，这是正常行为。", insightTone: echoGold)
      }
      insight(
        english ? "PROCESSING" : "处理",
        title: processingModules.isEmpty ? (english ? "Direct processing path" : "处理链为直通") : (english ? "DSP modules are active" : "DSP 模块已介入"),
        detail: processingDetail,
        advice: usesLocalProcessing ? (english ? "EQ and loudness changes are applied before the main mixer." : "EQ 与响度处理位于主混音器之前。") : (english ? "Detailed remote DSP telemetry is not exposed by this endpoint." : "当前远程端未提供详细 DSP 遥测。"),
        insightTone: processingModules.isEmpty ? Color.green : echoGold
      )
      insight(english ? "INTEGRITY" : "完整性", title: english ? "Bit-perfect status is not asserted" : "未声明 Bit-perfect 状态", detail: english ? "iOS shared output and remote endpoints do not expose enough telemetry to prove a bit-perfect route." : "iOS 共享输出与远程端没有提供足够遥测，无法证明链路为 Bit-perfect。", advice: english ? "Treat the displayed format as observed metadata, not a bit-perfect guarantee." : "当前格式仅代表观测到的元数据，不代表 Bit-perfect 保证。", insightTone: echoInk.opacity(0.58))
    }
  }

  private var flightRecorder: some View {
    DisclosureGroup(isExpanded: $flightRecorderExpanded) {
      VStack(spacing: 0) {
        if model.signalRouteEvents.isEmpty {
          Text(english ? "Route events will appear after a playback path is established." : "播放链路建立后会在这里记录路径事件。")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(echoInk.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
        } else {
          ForEach(Array(model.signalRouteEvents.prefix(8)).indices, id: \.self) { index in
            routeEvent(model.signalRouteEvents[index])
            if index < min(model.signalRouteEvents.count, 8) - 1 { Divider() }
          }
        }
      }
      .padding(.top, 4)
    } label: {
      disclosureLabel(
        english ? "Route flight recorder" : "路径飞行记录器",
        detail: english ? "\(model.signalRouteEvents.count) recent events" : "最近 \(model.signalRouteEvents.count) 条事件",
        icon: "clock.arrow.circlepath"
      )
    }
    .tint(echoAccent)
    .padding(15)
    .echoGlass(tint: Color.white.opacity(0.06), clear: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func sectionTitle(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.system(size: 15, weight: .bold, design: .rounded))
      .foregroundColor(echoInk.opacity(0.78))
  }

  private func metric(_ title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title.uppercased())
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(echoInk.opacity(0.45))
      Text(value)
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .lineLimit(2)
        .minimumScaleFactor(0.75)
      Text(detail)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(echoInk.opacity(0.52))
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
    .padding(11)
    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func signalNode(index: String, icon: String, title: String, value: String, detail: String, provenance: String, nodeTone: Color) -> some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle().fill(nodeTone.opacity(0.14))
        Image(systemName: icon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundColor(nodeTone)
      }
      .frame(width: 38, height: 38)
      .anchorPreference(key: EchoNativeSignalIconAnchorKey.self, value: .center) { [$0] }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 7) {
          Text(index)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(nodeTone)
          Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(echoInk.opacity(0.55))
          Spacer(minLength: 4)
          provenanceMark(provenance)
        }
        Text(value)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(echoInk.opacity(0.58))
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func disclosureLabel(_ title: String, detail: String, icon: String) -> some View {
    Label {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.system(size: 14, weight: .bold, design: .rounded))
        Text(detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(echoInk.opacity(0.5))
      }
    } icon: {
      Image(systemName: icon).foregroundColor(echoAccent)
    }
  }

  private func provenanceMark(_ kind: String) -> some View {
    Label(provenanceText(kind), systemImage: provenanceIcon(kind))
      .font(.system(size: 9, weight: .bold))
      .foregroundColor(provenanceColor(kind))
      .lineLimit(1)
      .minimumScaleFactor(0.72)
  }

  private func provenanceText(_ kind: String) -> String {
    switch kind {
    case "observed": return english ? "Observed" : "已观测"
    case "reported": return english ? "Remote reported" : "远程上报"
    default: return "?"
    }
  }

  private func provenanceIcon(_ kind: String) -> String {
    switch kind {
    case "observed": return "eye.fill"
    case "reported": return "antenna.radiowaves.left.and.right"
    default: return "questionmark.circle"
    }
  }

  private func provenanceColor(_ kind: String) -> Color {
    switch kind {
    case "observed": return Color.green
    case "reported": return echoGold
    default: return echoInk.opacity(0.45)
    }
  }

  private func formatObservedRate(_ rate: Double) -> String {
    let khz = rate >= 1_000 ? rate / 1_000 : rate
    return String(format: khz.rounded() == khz ? "%.0f kHz" : "%.1f kHz", khz)
  }

  private func insight(_ eyebrow: String, title: String, detail: String, advice: String, insightTone: Color) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(eyebrow)
        .font(.system(size: 9, weight: .bold))
        .foregroundColor(insightTone)
      Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
      Text(detail)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.62))
      Text(advice)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(echoInk.opacity(0.48))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, 10)
    .overlay(alignment: .leading) {
      Rectangle().fill(insightTone).frame(width: 3)
    }
  }

  private func routeEvent(_ event: EchoNativeSignalRouteEvent) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Circle()
        .fill(routeTone(event.tone))
        .frame(width: 8, height: 8)
        .padding(.top, 6)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(event.title).font(.system(size: 12, weight: .bold))
          Spacer()
          Text(event.at, style: .relative)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(echoInk.opacity(0.42))
        }
        Text(event.detail)
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(echoInk.opacity(0.58))
        Text(event.trackTitle)
          .font(.system(size: 9, weight: .semibold))
          .foregroundColor(echoInk.opacity(0.42))
          .lineLimit(1)
      }
    }
    .padding(.vertical, 10)
  }

  private func routeTone(_ tone: String) -> Color {
    switch tone {
    case "danger": return echoAccent
    case "process", "warning": return echoGold
    case "good": return Color.green
    default: return echoInk.opacity(0.4)
    }
  }
}

struct EchoNativeEqualizerSheet: View {
  @ObservedObject var model: EchoNativeEqualizerModel
  let onAction: ([String: Any]) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var activeBand = 4

  private var presetKeys: [String] { ["flat", "bass", "vocal", "clarity", "warm", "lateNight"] }

  var body: some View {
    VStack(spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("EQ")
            .font(.system(size: 24, weight: .bold))
          Text(model.language == "en" ? "10-band equalizer" : "十段均衡器")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(echoInk.opacity(0.52))
        }
        Spacer()
        Text(presetLabel(model.preset))
          .font(.system(size: 11, weight: .bold))
          .foregroundColor(echoAccent)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .overlay(Capsule().stroke(echoAccent.opacity(0.36), lineWidth: 1))
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 13, weight: .bold))
            .frame(width: 44, height: 44)
            .echoGlass(tint: Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.language == "en" ? "Close equalizer" : "关闭均衡器")
      }

      HStack(alignment: .firstTextBaseline) {
        Text(frequencyLabel(activeBand))
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(echoInk.opacity(0.58))
        Spacer()
        Text(String(format: "%+.1f dB", model.gains[activeBand]))
          .font(.system(size: 23, weight: .bold, design: .monospaced))
      }
      .padding(.bottom, 10)
      .overlay(alignment: .bottom) { Rectangle().fill(echoInk.opacity(0.1)).frame(height: 1) }

      GeometryReader { geometry in
        let plotHeight = geometry.size.height - 24
        HStack(alignment: .top, spacing: 8) {
          VStack {
            ForEach([12, 6, 0, -6, -12], id: \.self) { gain in
              Text("\(gain > 0 ? "+" : "")\(gain)dB")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(echoInk.opacity(0.42))
              if gain != -12 { Spacer() }
            }
          }
          .frame(width: 40, height: plotHeight)

          ZStack(alignment: .top) {
            VStack(spacing: 0) {
              ForEach(0..<5, id: \.self) { index in
                Rectangle().fill(echoInk.opacity(0.1)).frame(height: 1)
                if index < 4 { Spacer() }
              }
            }
            .frame(height: plotHeight)

            HStack(spacing: 2) {
              ForEach(nativeEqFrequencies.indices, id: \.self) { index in
                EchoNativeEqBand(
                  gain: model.gains[index],
                  label: nativeEqFrequencies[index],
                  plotHeight: plotHeight,
                  onChange: { gain, commit in
                    activeBand = index
                    model.preset = "custom"
                    model.gains[index] = gain
                    onAction(["action": "eqChange", "commit": commit, "index": index, "value": gain])
                  }
                )
                .onTapGesture { activeBand = index }
              }
            }
          }
        }
      }
      .frame(minHeight: 230)

      ScrollView(.horizontal, showsIndicators: false) {
        echoGlassGroup(spacing: 4) {
          HStack(spacing: 8) {
            ForEach(presetKeys, id: \.self) { key in
              Button {
                model.preset = key
                onAction(["action": "eqPreset", "preset": key])
              } label: {
                Text(presetLabel(key))
                  .font(.system(size: 12, weight: .bold))
                  .foregroundColor(model.preset == key ? echoAccent : echoInk.opacity(0.58))
                  .padding(.horizontal, 13)
                  .frame(height: 36)
                  .echoGlass(
                    tint: model.preset == key ? Color.black.opacity(0.12) : Color.white.opacity(0.1),
                    clear: model.preset != key,
                    in: Capsule()
                  )
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(20)
    .foregroundColor(echoInk)
    .background(echoWarmBackground.ignoresSafeArea())
  }

  private func frequencyLabel(_ index: Int) -> String {
    let label = nativeEqFrequencies[index]
    return label.hasSuffix("k") ? "\(label.dropLast()) kHz" : "\(label) Hz"
  }

  private func presetLabel(_ key: String) -> String {
    let english = ["flat": "Flat", "bass": "Bass", "vocal": "Vocal", "clarity": "Clarity", "warm": "Warm", "lateNight": "Late Night", "custom": "Custom"]
    let chinese = ["flat": "平直", "bass": "低频", "vocal": "人声", "clarity": "清晰", "warm": "暖声", "lateNight": "夜间", "custom": "手动"]
    return (model.language == "en" ? english : chinese)[key] ?? key
  }
}

private struct EchoNativeEqBand: View {
  let gain: Double
  let label: String
  let plotHeight: CGFloat
  let onChange: (Double, Bool) -> Void

  var body: some View {
    VStack(spacing: 7) {
      GeometryReader { geometry in
        let y = CGFloat((12 - gain) / 24) * geometry.size.height
        let center = geometry.size.height / 2
        ZStack(alignment: .top) {
          Rectangle()
            .fill(echoInk.opacity(0.2))
            .frame(width: 2)
          Rectangle()
            .fill(echoAccent)
            .frame(width: 2, height: max(2, abs(y - center)))
            .offset(y: min(y, center))
          Circle()
            .fill(echoAccent)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .frame(width: 12, height: 12)
            .offset(y: y - 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
          .onChanged { value in onChange(gain(at: value.location.y, height: geometry.size.height), false) }
          .onEnded { value in onChange(gain(at: value.location.y, height: geometry.size.height), true) }
        )
      }
      .frame(height: plotHeight)
      Text(label)
        .font(.system(size: 9, weight: .bold, design: .monospaced))
        .foregroundColor(echoInk.opacity(0.54))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement()
    .accessibilityLabel("\(label) \(String(format: "%+.1f dB", gain))")
    .accessibilityAdjustableAction { direction in
      let delta = direction == .increment ? 0.5 : -0.5
      onChange(min(12, max(-12, gain + delta)), true)
    }
  }

  private func gain(at y: CGFloat, height: CGFloat) -> Double {
    let ratio = min(1, max(0, y / max(1, height)))
    return ((12 - Double(ratio) * 24) * 2).rounded() / 2
  }
}
