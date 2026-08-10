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
let echoAccent = Color.accentColor
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

func echoColor(hex: String) -> Color {
  let value = UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0x69508F
  return Color(
    red: Double((value >> 16) & 0xff) / 255,
    green: Double((value >> 8) & 0xff) / 255,
    blue: Double(value & 0xff) / 255
  )
}

func echoHex(color: Color) -> String? {
  var red: CGFloat = 0
  var green: CGFloat = 0
  var blue: CGFloat = 0
  var alpha: CGFloat = 0
  guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
  return String(
    format: "%02X%02X%02X",
    Int((red * 255).rounded()),
    Int((green * 255).rounded()),
    Int((blue * 255).rounded())
  )
}

func echoFont(
  size: CGFloat,
  weight: Font.Weight = .regular,
  design: Font.Design = .default
) -> Font {
  let scale = max(0.85, min(1.25, UserDefaults.standard.double(forKey: "echo.appearance.fontScale") == 0
    ? 1
    : UserDefaults.standard.double(forKey: "echo.appearance.fontScale")))
  let adjustedSize = size * scale
  let name = UserDefaults.standard.string(forKey: "echo.appearance.fontName") ?? ""
  return name.isEmpty
    ? .system(size: adjustedSize, weight: weight, design: design)
    : .custom(name, size: adjustedSize).weight(weight)
}

private func echoThemeBackground(_ hex: String) -> some View {
  let color = echoColor(hex: hex)
  return ZStack {
    echoWarmBackground
    LinearGradient(
      colors: [color.opacity(0.72), color.opacity(0.36), Color.white.opacity(0.08)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
  }
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
  @Published var appearanceBackground = "theme"
  @Published var appearanceImageUrl = ""
  @Published var artworkBackgroundEnabled = true
  @Published var artworkUrl = ""
  @Published var connectionLabel = "ECHO???"
  @Published var connectionOnline = false
  @Published var controlsEnabled = false
  @Published var customFontName = ""
  @Published var darkModeEnabled = false
  @Published var desktopLyricsEnabled = false
  @Published var durationMs = 0.0
  @Published var eqEnabled = false
  @Published var externalSourcePicker: EchoNativeExternalSourcePickerPayload?
  @Published var followSystemAppearance = true
  @Published var fontScale = 1.0
  @Published var hapticsEnabled = true
  @Published var isFavorite = false
  @Published var isPlaying = false
  @Published var language = "zh"
  @Published var loudnessEnabled = false
  @Published var lyricLines: [EchoNativeMetadataService.LyricLine] = []
  @Published var lyricsVisible = false
  @Published var metadataLoading = false
  @Published var motionStyle = "subtle"
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
  @Published var themeColorHex = "69508F"
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
    backgroundColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 0.13, green: 0.09, blue: 0.13, alpha: 1)
        : UIColor(red: 0.97, green: 0.79, blue: 0.73, alpha: 1)
    }
    hostingController.view.backgroundColor = .clear
    hostingController.view.isOpaque = false
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
    if window != nil {
      store.attachDesktopLyrics(to: self)
      store.start()
    }
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
  @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
  @ObservedObject var playerModel: EchoNativePlayerModel
  @ObservedObject var pagesModel: EchoNativePagesModel
  let onAction: ([String: Any]) -> Void
  @State private var showingSplash = true
  @State private var stableArtworkIdentity = ""
  @State private var stableArtworkUrl = ""
  @State private var stableCustomIdentity = ""
  @State private var stableCustomUrl = ""

  var body: some View {
    ZStack {
      echoThemeBackground(playerModel.themeColorHex).ignoresSafeArea()
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
      .tint(echoColor(hex: playerModel.themeColorHex))
      .environment(\.font, echoFont(size: 17))
      if showingSplash {
        EchoNativeSplashView(forceReduceMotion: playerModel.motionStyle == "off")
          .transition(.opacity)
          .zIndex(100)
      }
    }
    .sheet(item: $playerModel.externalSourcePicker) { payload in
      EchoNativeExternalSourcePicker(payload: payload, onAction: onAction)
        .echoMediumSheet()
    }
    .alert(playerModel.alertTitle, isPresented: Binding(
      get: { !playerModel.alertMessage.isEmpty },
      set: { if !$0 { playerModel.alertMessage = "" } }
    )) {
      Button(playerModel.language == "en" ? "OK" : "?", role: .cancel) {
        playerModel.alertMessage = ""
      }
    } message: {
      Text(playerModel.alertMessage)
    }
    .task {
      guard showingSplash else { return }
      try? await Task.sleep(nanoseconds: 2_000_000_000)
      withAnimation(.easeOut(duration: 0.55)) { showingSplash = false }
    }
  }

  @ViewBuilder
  private var appBackground: some View {
    ZStack {
      if (playerModel.activePage == "control" || playerModel.appearanceBackground == "artwork")
        && !playerModel.artworkUrl.isEmpty {
        EchoNativeArtworkBackdrop(
          enabled: true,
          identity: "\(playerModel.title)::\(playerModel.artist)",
          urlString: playerModel.artworkUrl,
          stableIdentity: $stableArtworkIdentity,
          stableUrl: $stableArtworkUrl
        ) {
          onAction(["action": "artworkError", "url": playerModel.artworkUrl])
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
      } else if playerModel.activePage != "control"
        && playerModel.appearanceBackground == "custom"
        && !playerModel.appearanceImageUrl.isEmpty {
        EchoNativeArtworkBackdrop(
          enabled: true,
          identity: playerModel.appearanceImageUrl,
          urlString: playerModel.appearanceImageUrl,
          stableIdentity: $stableCustomIdentity,
          stableUrl: $stableCustomUrl,
          onError: {}
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
      } else {
        echoThemeBackground(playerModel.themeColorHex).ignoresSafeArea()
      }
      EchoNativeSakuraBackdrop(color: echoColor(hex: playerModel.themeColorHex))
        .ignoresSafeArea()
    }
    .allowsHitTesting(false)
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
        themedTab {
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
      themedTab {
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
    @ViewBuilder content: () -> Content
  ) -> some View {
    ZStack {
      appBackground
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func title(_ page: String) -> String {
    let english = playerModel.language == "en"
    switch page {
    case "control": return english ? "Playback" : "??"
    case "library": return english ? "Library" : "??"
    case "search": return english ? "Search" : "??"
    case "connect": return english ? "Connect" : "??"
    default: return english ? "Settings" : "??"
    }
  }
}

private struct EchoNativeSakuraBackdrop: View {
  let color: Color
  var body: some View {
    GeometryReader { geometry in
      let blossomSize = min(380, max(220, geometry.size.width * 0.72))
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.44
        for index in 0..<5 {
          context.drawLayer { petal in
            petal.translateBy(x: center.x, y: center.y)
            petal.rotate(by: .degrees(Double(index) * 72))
            var path = Path()
            path.move(to: .zero)
            path.addCurve(
              to: CGPoint(x: 0, y: -radius),
              control1: CGPoint(x: radius * 0.5, y: -radius * 0.2),
              control2: CGPoint(x: radius * 0.42, y: -radius * 0.78)
            )
            path.addCurve(
              to: .zero,
              control1: CGPoint(x: -radius * 0.42, y: -radius * 0.78),
              control2: CGPoint(x: -radius * 0.5, y: -radius * 0.2)
            )
            petal.fill(path, with: .color(Color.white.opacity(0.1)))
            petal.stroke(path, with: .color(color.opacity(0.2)), lineWidth: 1.4)
          }
        }
        let core = CGRect(x: center.x - radius * 0.12, y: center.y - radius * 0.12, width: radius * 0.24, height: radius * 0.24)
        context.fill(Path(ellipseIn: core), with: .color(echoGold.opacity(0.18)))
      }
      .frame(width: blossomSize, height: blossomSize)
      .rotationEffect(.degrees(-18))
      .position(
        x: geometry.size.width - blossomSize * 0.18,
        y: geometry.size.height - blossomSize * 0.12
      )
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct EchoNativeArtworkMotion: ViewModifier {
  let enabled: Bool
  let style: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !enabled || reduceMotion || style == "off")) { timeline in
      let phase = timeline.date.timeIntervalSinceReferenceDate * (style == "fluid" ? 0.7 : 0.42)
      content
        .scaleEffect(enabled && !reduceMotion ? 1 + sin(phase) * (style == "fluid" ? 0.018 : 0.008) : 1)
        .rotationEffect(.degrees(enabled && !reduceMotion ? sin(phase * 0.7) * (style == "fluid" ? 0.9 : 0.32) : 0))
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
          .font(echoFont(size: compact ? 17 : 20, weight: .bold))
          .foregroundColor(echoInk)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
        HStack(spacing: 5) {
          Image(systemName: "rectangle.stack.fill")
            .accessibilityHidden(true)
          Text(albumLabel)
            .lineLimit(1)
        }
        .font(echoFont(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.56))
        HStack(spacing: 5) {
          Image(systemName: "person.fill")
            .accessibilityHidden(true)
          Text(artistLabel)
            .lineLimit(1)
        }
        .font(echoFont(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.56))
        if !model.tags.isEmpty {
          HStack(alignment: .top, spacing: 5) {
            Image(systemName: "waveform")
              .accessibilityHidden(true)
            Text(model.tags.joined(separator: "  ?  "))
              .lineLimit(compact ? 2 : 3)
              .minimumScaleFactor(0.72)
              .fixedSize(horizontal: false, vertical: true)
          }
          .font(echoFont(size: 9, weight: .bold))
          .foregroundColor(echoInk.opacity(0.62))
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        onAction(["action": "lyricsClose"])
      } label: {
        Image(systemName: "xmark")
          .font(echoFont(size: 13, weight: .bold))
          .foregroundColor(echoInk)
          .frame(width: 36, height: 36)
          .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(model.language == "en" ? "Close lyrics" : "????")
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
                  .font(echoFont(
                    size: active ? (compact ? 20 : 24) : (distance == 1 ? 18 : 16),
                    weight: active ? .bold : .semibold
                  ))
                  .foregroundColor(active ? echoInk : echoInk.opacity(distance == 1 ? 0.56 : 0.3))
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)
                  .shadow(color: active ? Color.white.opacity(0.7) : .clear, radius: 8)
                if timeMs >= 0 {
                  Text(formatTime(timeMs))
                    .font(echoFont(size: 9, weight: .medium, design: .monospaced))
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
      .font(echoFont(size: 13, weight: .semibold))
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
      .modifier(EchoNativeArtworkMotion(
        enabled: model.motionStyle != "off",
        style: model.motionStyle
      ))
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
        .font(echoFont(size: compact ? 9 : 10, weight: .semibold))
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
        .font(echoFont(size: compact ? 18 : 21, weight: .bold))
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
        .font(echoFont(size: 12, weight: .medium))
        .foregroundColor(echoInk.opacity(0.58))
      if !model.tags.isEmpty {
        HStack(spacing: 5) {
          Image(systemName: "waveform")
            .accessibilityHidden(true)
          Text(model.tags.joined(separator: "  ?  "))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
          .font(echoFont(size: 10, weight: .semibold))
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
          label: model.language == "en" ? "Previous" : "???",
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
          .font(echoFont(size: compact ? 26 : 30, weight: .bold))
          .foregroundColor(echoInk)
          .frame(width: compact ? 66 : 76, height: compact ? 66 : 76)
          .echoGlass(tint: Color.white.opacity(0.2), clear: false, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!model.controlsEnabled || model.playbackLoading)
        .opacity(model.controlsEnabled && !model.playbackLoading ? 1 : 0.5)
        .accessibilityLabel(model.playbackLoading
          ? (model.language == "en" ? "Loading audio" : "??????")
          : (model.language == "en" ? (model.isPlaying ? "Pause" : "Play") : (model.isPlaying ? "??" : "??")))
        roundButton(
          symbol: "forward.end.fill",
          label: model.language == "en" ? "Next" : "???",
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
          label: model.language == "en" ? "Playback mode" : "????",
          active: model.playbackMode != .normal,
          value: playbackModeLabel
        ) {
          onAction(["action": "playbackMode"])
        }
        .frame(maxWidth: .infinity)
        iconButton(
          symbol: lyricsMode ? "quote.bubble.fill" : "quote.bubble",
          label: model.language == "en" ? (lyricsMode ? "Close lyrics" : "Lyrics") : (lyricsMode ? "????" : "??"),
          active: lyricsMode
        ) {
          onAction(["action": lyricsMode ? "lyricsClose" : "lyrics"])
        }
        .frame(maxWidth: .infinity)
        iconButton(symbol: "list.bullet", label: model.language == "en" ? "Queue" : "????", active: false) {
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
    case .normal: return english ? "Play once" : "????"
    case .repeatAll: return english ? "Repeat all" : "????"
    case .repeatOne: return english ? "Repeat one" : "????"
    case .shuffle: return english ? "Shuffle" : "????"
    }
  }

  private var volumeControl: some View {
    HStack(spacing: 9) {
      Image(systemName: "speaker.wave.1.fill")
        .font(echoFont(size: 11, weight: .semibold))
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
      .accessibilityLabel(model.language == "en" ? "Volume" : "??")
      .accessibilityValue("\(Int((volumeValue * 100).rounded()))%")
      Text("\(Int((volumeValue * 100).rounded()))%")
        .font(echoFont(size: 10, weight: .bold, design: .monospaced))
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
          model.language == "en" ? (model.isFavorite ? "Remove favorite" : "Favorite") : (model.isFavorite ? "????" : "??"),
          systemImage: model.isFavorite ? "heart.fill" : "heart"
        )
      }
      .disabled(!model.controlsEnabled)

      Divider()
      Toggle(isOn: Binding(
        get: { model.desktopLyricsEnabled },
        set: { enabled in
          onAction(["action": "settingToggle", "key": "desktopLyricsEnabled", "enabled": enabled])
        }
      )) {
        Label(
          model.language == "en" ? "Desktop lyrics" : "????",
          systemImage: model.desktopLyricsEnabled ? "captions.bubble.fill" : "captions.bubble"
        )
      }
      .tint(echoAccent)
      Button {
        onAction(["action": "externalMetadataRefresh"])
      } label: {
        Label(
          model.language == "en" ? "Refresh external metadata" : "????????",
          systemImage: "arrow.clockwise"
        )
      }
      .disabled(model.metadataLoading)
      Button {
        showSignalPath = true
      } label: {
        Label(model.language == "en" ? "Signal path" : "????", systemImage: "waveform.path.ecg")
      }
      Button {
        showEqualizer = true
      } label: {
        Label(model.language == "en" ? "Equalizer" : "???", systemImage: "slider.horizontal.3")
      }

      if model.showPlayerOutputInMenu {
        Divider()
        Picker(selection: Binding(
          get: { outputSource },
          set: { onAction(["action": "outputSource", "mode": $0]) }
        )) {
          Text(model.language == "en" ? "Local" : "??").tag("local")
          Text(model.language == "en" ? "Media" : "???").tag("streaming")
          Text("ECHO").tag("echo")
          Text(model.language == "en" ? "Remote" : "??").tag("remote")
        } label: {
          Label(model.language == "en" ? "Music source" : "???", systemImage: "music.note.list")
        }
        if outputSource == "echo" || outputSource == "remote" {
          Picker(selection: Binding(
            get: { model.outputMode },
            set: { onAction(["action": "output", "mode": $0]) }
          )) {
            Text(model.language == "en" ? "Control" : "??")
              .tag(outputSource == "echo" ? "pc" : "remoteControl")
            Text(model.language == "en" ? "Stream" : "??")
              .tag(outputSource == "echo" ? "phone" : "remoteStream")
          } label: {
            Label(model.language == "en" ? "Output mode" : "????", systemImage: "waveform")
          }
        }
      }
    } label: {
      Image(systemName: "ellipsis")
        .font(echoFont(size: 17, weight: .bold))
        .foregroundColor(echoInk)
        .frame(width: 44, height: 44)
        .echoGlass(tint: Color.white.opacity(0.12), in: Circle())
    }
    .accessibilityLabel(model.language == "en" ? "More playback controls" : "??????")
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
    .accessibilityLabel(model.language == "en" ? "Playback output" : "????")
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: outputSource)
  }

  private var outputSourcePicker: some View {
    Picker("", selection: Binding(
      get: { outputSource },
      set: { onAction(["action": "outputSource", "mode": $0]) }
    )) {
      Text(model.language == "en" ? "Local" : "??").tag("local")
      Text(model.language == "en" ? "Media" : "??").tag("streaming")
      Text("ECHO").tag("echo")
      Text(model.language == "en" ? "Remote" : "??").tag("remote")
    }
    .pickerStyle(.segmented)
    .frame(maxWidth: .infinity)
  }

  private var outputModePicker: some View {
    Picker("", selection: Binding(
      get: { model.outputMode },
      set: { onAction(["action": "output", "mode": $0]) }
    )) {
      Text(model.language == "en" ? "Control" : "??")
        .tag(outputSource == "echo" ? "pc" : "remoteControl")
      Text(model.language == "en" ? "Stream" : "??")
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
        .font(echoFont(size: size * 0.34, weight: .bold))
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
      .font(echoFont(size: 16, weight: .semibold))
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
      ? (model.language == "en" ? "On" : "???")
      : (model.language == "en" ? "Off" : "???")))
  }

  private func formatTime(_ milliseconds: Double) -> String {
    let seconds = max(0, Int(milliseconds / 1000))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private var artistLabel: String {
    let artist = model.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    return artist.isEmpty ? (model.language == "en" ? "Unknown Artist" : "?????") : artist
  }

  private var albumLabel: String {
    let album = model.album.trimmingCharacters(in: .whitespacesAndNewlines)
    return album.isEmpty ? (model.language == "en" ? "Unknown Album" : "????") : album
  }

  private var titleLabel: String {
    let title = model.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? (model.language == "en" ? "No song is playing" : "?????????") : title
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
      .accessibilityLabel(language == "en" ? "Playback position" : "????")
      .accessibilityValue("\(formatTime(seekValue)) / \(formatTime(durationMs))")
      HStack {
        Text(formatTime(seekValue))
        Spacer()
        Text(formatTime(durationMs))
      }
      .font(echoFont(size: 10, weight: .medium, design: .monospaced))
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
      .accessibilityLabel(language == "en" ? "Loading artwork and lyrics" : "?????????")
  }
}

private struct EchoNativeArtworkBackdrop: View {
  let enabled: Bool
  let identity: String
  let urlString: String
  @Binding var stableIdentity: String
  @Binding var stableUrl: String
  let onError: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

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
            .font(echoFont(size: 24, weight: .bold, design: .rounded))
          Text(payload.subtitle)
            .font(echoFont(size: 13, weight: .medium))
            .foregroundColor(echoInk.opacity(0.56))
        }
        Spacer(minLength: 8)
        Button {
          onAction(["action": "externalSourcePickerDismiss"])
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(echoFont(size: 13, weight: .bold))
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
                  .font(echoFont(size: 15, weight: .bold))
                  .foregroundColor(echoInk)
                  .lineLimit(1)
                Text([candidate.artist ?? "", candidate.sourceLabel]
                  .filter { !$0.isEmpty }
                  .joined(separator: " ? "))
                  .font(echoFont(size: 12, weight: .semibold))
                  .foregroundColor(echoInk.opacity(0.5))
                  .lineLimit(1)
              }
              Spacer(minLength: 8)
              Text(candidate.availableLabel)
                .font(echoFont(size: 11, weight: .semibold))
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
            .font(echoFont(size: 14, weight: .bold))
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
            .font(echoFont(size: 15, weight: .bold))
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
          .font(echoFont(size: 12, weight: .bold))
        Text(available ? (selected ? payload.selectedLabel : payload.useSourceLabel) : payload.unavailableLabel)
          .font(echoFont(size: 9, weight: .semibold))
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
          Text(model.queuePayload?.title ?? (model.language == "en" ? "Queue" : "????"))
            .font(echoFont(size: 24, weight: .bold, design: .rounded))
          if let subtitle = model.queuePayload?.subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(echoFont(size: 11, weight: .semibold))
              .foregroundColor(echoInk.opacity(0.5))
              .lineLimit(1)
          }
        }
        Spacer()
        if model.queuePayload?.canEdit == true, !(model.queuePayload?.items.isEmpty ?? true) {
          Button(model.queuePayload?.clearLabel ?? (model.language == "en" ? "Clear" : "??")) {
            if model.queuePayload?.playlistId.isEmpty == false {
              showClearConfirmation = true
            } else {
              clearQueue()
            }
          }
          .font(echoFont(size: 12, weight: .bold))
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
            .font(echoFont(size: 13, weight: .bold))
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
                          .font(echoFont(size: 19, weight: .bold))
                      } else {
                        Text(String(format: "%02d", index + 1))
                          .font(echoFont(size: 11, weight: .bold, design: .monospaced))
                      }
                    }
                    .foregroundColor(item.current ? echoAccent : echoInk.opacity(0.36))
                    .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(item.title)
                        .font(echoFont(size: 14, weight: .bold))
                        .foregroundColor(item.current ? echoAccent : echoInk)
                        .lineLimit(1)
                      Text(item.meta.isEmpty ? item.artist : "\(item.artist) ? \(item.meta)")
                        .font(echoFont(size: 11, weight: .medium))
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
            .font(echoFont(size: 28, weight: .medium))
          Text(model.queuePayload?.emptyLabel ?? (model.language == "en" ? "The queue is empty." : "???????????"))
            .font(echoFont(size: 13, weight: .semibold))
        }
        .foregroundColor(echoInk.opacity(0.42))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(20)
    .foregroundColor(echoInk)
    .background(Color.clear)
    .confirmationDialog(
      model.language == "en" ? "Clear this playlist?" : "???????",
      isPresented: $showClearConfirmation,
      titleVisibility: .visible
    ) {
      Button(model.queuePayload?.clearLabel ?? (model.language == "en" ? "Clear" : "??"), role: .destructive) {
        clearQueue()
      }
      Button(model.language == "en" ? "Cancel" : "??", role: .cancel) {}
    } message: {
      Text(model.language == "en" ? "This removes every track from the saved playlist." : "????????????????")
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
        .font(echoFont(size: 12, weight: .bold))
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
        .font(echoFont(size: 34, weight: .medium))
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
    hasLevel ? String(format: "%.1f dBFS", model.peakDb) : (external ? (english ? "External" : "??") : "-- dBFS")
  }

  private var detail: String {
    guard hasLevel else {
      return external
        ? (english ? "The remote endpoint has not reported live levels." : "????????????")
        : (english ? "RMS -- dBFS ? meter active during playback" : "RMS -- dBFS ? ????????")
    }
    var parts = [String(format: "RMS %.1f dBFS", model.rmsDb)]
    if let lufs = model.lufsMomentary { parts.append(String(format: "LUFS-M %.1f", lufs)) }
    return parts.joined(separator: " ? ")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(english ? "LIVE OUTPUT PEAK" : "??????")
            .font(echoFont(size: 10, weight: .bold))
            .foregroundColor(echoInk.opacity(0.48))
          Text(detail)
            .font(echoFont(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        }
        Spacer(minLength: 8)
        Text(peakLabel)
          .font(echoFont(size: 14, weight: .bold, design: .monospaced))
          .foregroundColor(model.clipping || model.peakDb > -3 ? echoAccent : tone)
      }
      ProgressView(value: fill)
        .tint(model.clipping || model.peakDb > -3 ? echoAccent : echoGold)
      if hasLevel && (model.clipping || model.peakDb > -3) {
        Label(
          english ? "Low headroom: reduce positive gain if clipping is audible." : "?????????????????????",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(echoFont(size: 10, weight: .semibold))
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
    return parts.isEmpty ? (english ? "Format unknown" : "????") : parts.joined(separator: " ? ")
  }

  private var processingModules: [String] {
    guard usesLocalProcessing else { return [] }
    var modules: [String] = []
    if model.eqEnabled { modules.append(english ? "10-band EQ" : "?? EQ") }
    if model.loudnessEnabled { modules.append(english ? "Loudness" : "?????") }
    return modules
  }

  private var summaryLabel: String {
    if !hasTrack { return english ? "Waiting for playback" : "????" }
    if !pathOnline { return english ? "Path unavailable" : "?????" }
    if !processingModules.isEmpty {
      return english ? "Enhanced" : "???"
    }
    if usesLocalProcessing {
      return english ? "Native playback" : "????"
    }
    return english ? "Remote path" : "????"
  }

  private var summaryDetail: String {
    if !hasTrack {
      return english ? "Start a track to inspect source, processing, and output." : "??????????????????"
    }
    if !pathOnline {
      return model.connectionLabel
    }
    if !processingModules.isEmpty {
      return english
        ? "Active processing: \(processingModules.joined(separator: " + "))."
        : "?????\(processingModules.joined(separator: " + "))?"
    }
    return usesLocalProcessing
      ? (english ? "Direct native playback with no additional DSP." : "???????????? DSP?")
      : (english ? "Decode and processing stay on the remote device." : "?????????????")
  }

  private var sourceDetail: String {
    if !hasTrack { return english ? "No current track" : "??????" }
    let artist = model.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    let source = model.signalSourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = artist.isEmpty ? model.title : "\(model.title) ? \(artist)"
    return source.isEmpty ? base : "\(base)\n\(source)"
  }

  private var processingDetail: String {
    if !hasTrack { return english ? "?" : "?" }
    if !usesLocalProcessing {
      return english ? "Remote device owns DSP" : "DSP ???????"
    }
    return processingModules.isEmpty
      ? (english ? "Direct / bypass" : "?? / ??")
      : processingModules.joined(separator: " + ")
  }

  private var decodeValue: String {
    if !hasTrack { return english ? "Waiting" : "???" }
    if !usesLocalProcessing { return english ? "Remote decoder" : "?????" }
    if model.signalFileLoaded { return "AVAudioFile ? PCM" }
    return english ? "Preparing decoder" : "???????"
  }

  private var decodeDetail: String {
    if !usesLocalProcessing {
      return english
        ? "Decoder details are owned by the remote endpoint. ? Resampling: ?"
        : "???????????? ? ?????"
    }
    let sourceRate = model.signalSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let engineRate = model.signalEngineSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    var parts: [String] = []
    if !sourceRate.isEmpty && !engineRate.isEmpty {
      parts.append(sourceRate == engineRate ? sourceRate : "\(sourceRate) ? \(engineRate)")
    } else if !engineRate.isEmpty {
      parts.append(engineRate)
    }
    if !model.signalChannelCount.isEmpty { parts.append(model.signalChannelCount) }
    parts.append(model.signalEngineRunning
      ? (english ? "Engine running" : "?????")
      : (english ? "Engine idle" : "????"))
    parts.append(resamplingLabel(decoderResampling))
    return parts.joined(separator: " ? ")
  }

  private var outputTitle: String {
    switch model.outputMode {
    case "local": return english ? "Local output" : "????"
    case "pc": return english ? "ECHO control" : "ECHO ??"
    case "phone": return english ? "ECHO stream" : "ECHO ??"
    case "remoteControl": return english ? "Poweramp control" : "Poweramp ??"
    case "remoteStream": return english ? "Poweramp stream" : "Poweramp ??"
    case "streaming": return english ? "NetEase stream" : "?????"
    default: return english ? "Output" : "??"
    }
  }

  private var outputDetail: String {
    var parts: [String] = []
    let device = model.signalDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let remote = model.signalRemoteOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    switch model.outputMode {
    case "local":
      parts.append(english ? "AVAudioEngine on this iPhone" : "?? AVAudioEngine")
    case "phone", "remoteStream", "streaming":
      parts.append(english ? "Downloaded then played locally" : "????????")
    case "pc", "remoteControl":
      parts.append(english ? "Remote device renders audio" : "????????")
    default:
      break
    }
    if !device.isEmpty { parts.append(device) }
    if !remote.isEmpty { parts.append(remote) }
    let deviceFormat = [model.signalDeviceSampleRate, model.signalOutputBitDepth, model.signalDeviceChannelCount]
      .filter { !$0.isEmpty }
      .joined(separator: " ? ")
    if !deviceFormat.isEmpty { parts.append(deviceFormat) }
    if model.signalDeviceLatencyMs > 0 {
      parts.append(String(format: english ? "%.1f ms latency" : "%.1f ms ??", model.signalDeviceLatencyMs))
    }
    if remoteMode {
      parts.append(model.connectionLabel)
    }
    return parts.isEmpty ? (english ? "Route unknown" : "????") : parts.joined(separator: " ? ")
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
    if !hasTrack { return english ? "No signal" : "???" }
    if !pathOnline { return english ? "Disconnected" : "????" }
    if !usesLocalProcessing { return english ? "Remote active" : "??????" }
    if model.signalEngineRunning { return english ? "Live" : "????" }
    if model.signalFileLoaded { return english ? "Ready" : "???" }
    return english ? "Preparing" : "???"
  }

  private var clockValue: String {
    let source = model.signalSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let engine = model.signalEngineSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    let device = model.signalDeviceSampleRate.trimmingCharacters(in: .whitespacesAndNewlines)
    var rates: [String] = []
    for rate in [source, engine, device] where !rate.isEmpty && rates.last != rate {
      rates.append(rate)
    }
    return rates.isEmpty ? (english ? "Unknown" : "??") : rates.joined(separator: " ? ")
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
    case true: return english ? "Resampling: active" : "??????"
    case false: return english ? "Resampling: bypassed" : "??????"
    case nil: return english ? "Resampling: ?" : "?????"
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
        Text(english ? "Signal path" : "????")
          .font(echoFont(size: 25, weight: .bold, design: .rounded))
        Text(english ? "\(summaryLabel) ? 4 stages" : "\(summaryLabel) ? 4 ?")
          .font(echoFont(size: 12, weight: .semibold))
          .foregroundColor(tone)
      }
      Spacer(minLength: 8)
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(echoFont(size: 13, weight: .bold))
          .frame(width: 44, height: 44)
          .echoGlass(tint: Color.white.opacity(0.14), in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(english ? "Close signal path" : "??????")
    }
  }

  private var summary: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(sourceSpec)
        .font(echoFont(size: 15, weight: .bold, design: .rounded))
        .foregroundColor(tone)
      Text(summaryDetail)
        .font(echoFont(size: 12, weight: .medium))
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
      sectionTitle(english ? "Signal theater" : "????", icon: "waveform.path.ecg")
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(english ? "PATH READINESS" : "?????")
            .font(echoFont(size: 10, weight: .bold))
            .foregroundColor(echoInk.opacity(0.48))
          Text(readinessLabel)
            .font(echoFont(size: 20, weight: .bold, design: .rounded))
        }
        Spacer()
        Text("\(Int(pathReadiness * 100))%")
          .font(echoFont(size: 14, weight: .bold, design: .monospaced))
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
        metric(english ? "Source" : "??", value: model.signalSourceLabel.isEmpty ? (english ? "Unknown" : "??") : model.signalSourceLabel, detail: sourceSpec)
        metric(english ? "Processing" : "??", value: processingDetail, detail: usesLocalProcessing ? "AVAudioEngine" : (english ? "Remote endpoint" : "???"))
        metric(english ? "Output" : "??", value: outputTitle, detail: model.signalDeviceName.isEmpty ? (english ? "Unknown device" : "????") : model.signalDeviceName)
        metric(english ? "Clock" : "??", value: clockValue, detail: resamplingLabel(clockResampling))
      }
    }
  }

  private var signalChain: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle(english ? "Full chain" : "????", icon: "point.3.connected.trianglepath.dotted")
      VStack(spacing: 10) {
        signalNode(index: "01", icon: "externaldrive.fill", title: english ? "Source" : "??", value: model.signalSourceLabel.isEmpty ? (english ? "Unknown source" : "????") : model.signalSourceLabel, detail: sourceDetail, provenance: sourceProvenance, nodeTone: hasTrack ? Color.green : echoInk.opacity(0.4))
        signalNode(index: "02", icon: "cpu", title: english ? "Decode" : "??", value: decodeValue, detail: decodeDetail, provenance: usesLocalProcessing ? model.signalTelemetrySource : (model.signalTelemetrySource == "reported" ? "reported" : "unverified"), nodeTone: model.signalFileLoaded || !usesLocalProcessing ? Color.green : echoGold)
        signalNode(index: "03", icon: processingModules.isEmpty ? "checkmark.shield.fill" : "slider.horizontal.3", title: english ? "Process" : "??", value: processingDetail, detail: usesLocalProcessing ? (english ? "Local DSP chain" : "?? DSP ?") : (english ? "External processing" : "????"), provenance: usesLocalProcessing ? model.signalTelemetrySource : "unverified", nodeTone: processingModules.isEmpty ? Color.green : echoGold)
        signalNode(index: "04", icon: "hifispeaker.fill", title: english ? "Output" : "??", value: outputTitle, detail: outputDetail, provenance: model.signalTelemetrySource, nodeTone: pathOnline ? Color.green : echoAccent)
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
        english ? "Signal doctor" : "????",
        detail: english ? "Inspect path quality and blockers" : "?????????",
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
            metric(english ? "Current route" : "????", value: profile.name, detail: model.signalDevicePortType.isEmpty ? profile.portType : model.signalDevicePortType)
            metric(english ? "Current format" : "????", value: [model.signalDeviceSampleRate, model.signalDeviceChannelCount].filter { !$0.isEmpty }.joined(separator: " ? "), detail: provenanceText("observed"))
            metric(english ? "Observed rates" : "?????", value: profile.sampleRates.map(formatObservedRate).joined(separator: " ? "), detail: english ? "Seen on this route" : "???????")
            metric(english ? "Observed channels" : "????", value: profile.channelCounts.map { "\($0)ch" }.joined(separator: " ? "), detail: english ? "Seen on this route" : "???????")
            metric(english ? "Latency / buffer" : "?? / ??", value: String(format: "%.1f / %.1f ms", model.signalDeviceLatencyMs, model.signalDeviceIOBufferMs), detail: english ? "Output / I/O buffer" : "?? / I/O ??")
            metric(english ? "System volume" : "????", value: "\(Int((model.signalOutputVolume * 100).rounded()))%", detail: english ? "AVAudioSession output" : "AVAudioSession ??")
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(english ? "ROUTE UID" : "?? UID")
              .font(echoFont(size: 9, weight: .bold))
              .foregroundColor(echoInk.opacity(0.45))
            Text(model.signalDeviceUID.isEmpty ? profile.id : model.signalDeviceUID)
              .font(echoFont(size: 10, weight: .medium, design: .monospaced))
              .foregroundColor(echoInk.opacity(0.58))
              .textSelection(.enabled)
            Text(english ? "\(profile.observationCount) format observations ? last seen" : "??? \(profile.observationCount) ????? ? ????")
              .font(echoFont(size: 10, weight: .medium))
              .foregroundColor(echoInk.opacity(0.48))
            Text(profile.lastSeenAt, style: .relative)
              .font(echoFont(size: 10, weight: .semibold))
              .foregroundColor(echoInk.opacity(0.58))
          }
          Text(english ? "This atlas records formats actually observed on the route. It does not claim the DAC's advertised maximum capability." : "???????????????????? DAC ????????")
            .font(echoFont(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        } else if model.signalTelemetrySource == "reported" {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric(english ? "Remote device" : "????", value: model.signalDeviceName, detail: model.signalDevicePortType.isEmpty ? model.signalRemoteOutput : model.signalDevicePortType)
            metric(english ? "Reported format" : "????", value: [model.signalDeviceSampleRate, model.signalOutputBitDepth, model.signalDeviceChannelCount].filter { !$0.isEmpty }.joined(separator: " ? "), detail: provenanceText("reported"))
            metric(english ? "Output mode" : "????", value: model.signalExclusive.map { $0 ? "Exclusive" : "Shared" } ?? model.signalRemoteOutput, detail: english ? "Endpoint report" : "?????")
            metric(english ? "Latency" : "??", value: model.signalDeviceLatencyMs > 0 ? String(format: "%.1f ms", model.signalDeviceLatencyMs) : (english ? "Not reported" : "???"), detail: provenanceText("reported"))
          }
          Text(english ? "Remote values are accepted from the paired endpoint and are not independently measured by this iPhone." : "???????????????????????")
            .font(echoFont(size: 10, weight: .medium))
            .foregroundColor(echoInk.opacity(0.5))
        } else {
          Label(
            english ? "No verifiable DAC telemetry is available for this route." : "?????????? DAC ???",
            systemImage: "questionmark.circle"
          )
          .font(echoFont(size: 12, weight: .medium))
          .foregroundColor(echoInk.opacity(0.55))
        }
      }
      .padding(.top, 12)
    } label: {
      disclosureLabel(
        english ? "DAC capability atlas" : "DAC ????",
        detail: model.signalDeviceName.isEmpty ? (english ? "Observed route capabilities" : "???????") : model.signalDeviceName,
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
      insight(english ? "WAITING" : "??", title: english ? "No active signal" : "????????", detail: english ? "Start playback to inspect decode, DSP, and output state." : "???????????DSP ??????", advice: english ? "No action required." : "?????", insightTone: echoInk.opacity(0.48))
    } else {
      if !pathOnline {
        insight(english ? "CONNECTION" : "??", title: english ? "Remote path is unavailable" : "???????", detail: model.connectionLabel, advice: english ? "Check the paired device and network, then reconnect." : "???????????????", insightTone: echoAccent)
      }
      if usesLocalProcessing && !model.signalFileLoaded {
        insight(english ? "DECODER" : "??", title: english ? "Audio file is not loaded" : "????????", detail: english ? "The local engine has not established a PCM stream." : "???????? PCM ????", advice: english ? "Wait for caching to finish or retry playback." : "?????????????", insightTone: echoGold)
      }
      if !model.signalSampleRate.isEmpty && !model.signalEngineSampleRate.isEmpty && model.signalSampleRate != model.signalEngineSampleRate {
        insight(english ? "CLOCK" : "??", title: english ? "Sample-rate conversion is active" : "????????", detail: "\(model.signalSampleRate) ? \(model.signalEngineSampleRate)", advice: english ? "This is expected when the decoded stream and engine rate differ." : "????????????????????", insightTone: echoGold)
      }
      insight(
        english ? "PROCESSING" : "??",
        title: processingModules.isEmpty ? (english ? "Direct processing path" : "??????") : (english ? "DSP modules are active" : "DSP ?????"),
        detail: processingDetail,
        advice: usesLocalProcessing ? (english ? "EQ and loudness changes are applied before the main mixer." : "EQ ??????????????") : (english ? "Detailed remote DSP telemetry is not exposed by this endpoint." : "?????????? DSP ???"),
        insightTone: processingModules.isEmpty ? Color.green : echoGold
      )
      insight(english ? "INTEGRITY" : "???", title: english ? "Bit-perfect status is not asserted" : "??? Bit-perfect ??", detail: english ? "iOS shared output and remote endpoints do not expose enough telemetry to prove a bit-perfect route." : "iOS ???????????????????????? Bit-perfect?", advice: english ? "Treat the displayed format as observed metadata, not a bit-perfect guarantee." : "?????????????????? Bit-perfect ???", insightTone: echoInk.opacity(0.58))
    }
  }

  private var flightRecorder: some View {
    DisclosureGroup(isExpanded: $flightRecorderExpanded) {
      VStack(spacing: 0) {
        if model.signalRouteEvents.isEmpty {
          Text(english ? "Route events will appear after a playback path is established." : "??????????????????")
            .font(echoFont(size: 12, weight: .medium))
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
        english ? "Route flight recorder" : "???????",
        detail: english ? "\(model.signalRouteEvents.count) recent events" : "?? \(model.signalRouteEvents.count) ???",
        icon: "clock.arrow.circlepath"
      )
    }
    .tint(echoAccent)
    .padding(15)
    .echoGlass(tint: Color.white.opacity(0.06), clear: false, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private func sectionTitle(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(echoFont(size: 15, weight: .bold, design: .rounded))
      .foregroundColor(echoInk.opacity(0.78))
  }

  private func metric(_ title: String, value: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title.uppercased())
        .font(echoFont(size: 9, weight: .bold))
        .foregroundColor(echoInk.opacity(0.45))
      Text(value)
        .font(echoFont(size: 13, weight: .bold, design: .rounded))
        .lineLimit(2)
        .minimumScaleFactor(0.75)
      Text(detail)
        .font(echoFont(size: 10, weight: .medium))
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
          .font(echoFont(size: 15, weight: .semibold))
          .foregroundColor(nodeTone)
      }
      .frame(width: 38, height: 38)
      .anchorPreference(key: EchoNativeSignalIconAnchorKey.self, value: .center) { [$0] }
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 7) {
          Text(index)
            .font(echoFont(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(nodeTone)
          Text(title)
            .font(echoFont(size: 11, weight: .bold))
            .foregroundColor(echoInk.opacity(0.55))
          Spacer(minLength: 4)
          provenanceMark(provenance)
        }
        Text(value)
          .font(echoFont(size: 14, weight: .bold, design: .rounded))
          .fixedSize(horizontal: false, vertical: true)
        Text(detail)
          .font(echoFont(size: 11, weight: .medium))
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
        Text(title).font(echoFont(size: 14, weight: .bold, design: .rounded))
        Text(detail)
          .font(echoFont(size: 10, weight: .medium))
          .foregroundColor(echoInk.opacity(0.5))
      }
    } icon: {
      Image(systemName: icon).foregroundColor(echoAccent)
    }
  }

  private func provenanceMark(_ kind: String) -> some View {
    Label(provenanceText(kind), systemImage: provenanceIcon(kind))
      .font(echoFont(size: 9, weight: .bold))
      .foregroundColor(provenanceColor(kind))
      .lineLimit(1)
      .minimumScaleFactor(0.72)
  }

  private func provenanceText(_ kind: String) -> String {
    switch kind {
    case "observed": return english ? "Observed" : "???"
    case "reported": return english ? "Remote reported" : "????"
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
        .font(echoFont(size: 9, weight: .bold))
        .foregroundColor(insightTone)
      Text(title).font(echoFont(size: 13, weight: .bold, design: .rounded))
      Text(detail)
        .font(echoFont(size: 11, weight: .medium))
        .foregroundColor(echoInk.opacity(0.62))
      Text(advice)
        .font(echoFont(size: 10, weight: .medium))
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
          Text(event.title).font(echoFont(size: 12, weight: .bold))
          Spacer()
          Text(event.at, style: .relative)
            .font(echoFont(size: 9, weight: .medium))
            .foregroundColor(echoInk.opacity(0.42))
        }
        Text(event.detail)
          .font(echoFont(size: 10, weight: .medium))
          .foregroundColor(echoInk.opacity(0.58))
        Text(event.trackTitle)
          .font(echoFont(size: 9, weight: .semibold))
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
            .font(echoFont(size: 24, weight: .bold))
          Text(model.language == "en" ? "10-band equalizer" : "?????")
            .font(echoFont(size: 12, weight: .medium))
            .foregroundColor(echoInk.opacity(0.52))
        }
        Spacer()
        Text(presetLabel(model.preset))
          .font(echoFont(size: 11, weight: .bold))
          .foregroundColor(echoAccent)
          .padding(.horizontal, 10)
          .frame(height: 28)
          .overlay(Capsule().stroke(echoAccent.opacity(0.36), lineWidth: 1))
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(echoFont(size: 13, weight: .bold))
            .frame(width: 44, height: 44)
            .echoGlass(tint: Color.white.opacity(0.14), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.language == "en" ? "Close equalizer" : "?????")
      }

      HStack(alignment: .firstTextBaseline) {
        Text(frequencyLabel(activeBand))
          .font(echoFont(size: 13, weight: .semibold))
          .foregroundColor(echoInk.opacity(0.58))
        Spacer()
        Text(String(format: "%+.1f dB", model.gains[activeBand]))
          .font(echoFont(size: 23, weight: .bold, design: .monospaced))
      }
      .padding(.bottom, 10)
      .overlay(alignment: .bottom) { Rectangle().fill(echoInk.opacity(0.1)).frame(height: 1) }

      GeometryReader { geometry in
        let plotHeight = geometry.size.height - 24
        HStack(alignment: .top, spacing: 8) {
          VStack {
            ForEach([12, 6, 0, -6, -12], id: \.self) { gain in
              Text("\(gain > 0 ? "+" : "")\(gain)dB")
                .font(echoFont(size: 9, weight: .semibold, design: .monospaced))
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
                  .font(echoFont(size: 12, weight: .bold))
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
    let chinese = ["flat": "??", "bass": "??", "vocal": "??", "clarity": "??", "warm": "??", "lateNight": "??", "custom": "??"]
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
        .font(echoFont(size: 9, weight: .bold, design: .monospaced))
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
