import Foundation
import WidgetKit

@MainActor
enum EchoNativeWidgetBridge {
  private static let kind = "EchoNowPlayingWidget"
  private static let suiteName = "group.app.echo.next.ios"
  private static let stateKey = "echo.widget.nowPlaying"
  private static var lastSignature = ""

  static func publish(title: String, artist: String, isPlaying: Bool) {
    let signature = "\(title)\u{0}\(artist)\u{0}\(isPlaying)"
    guard signature != lastSignature else { return }
    lastSignature = signature
    let state: [String: Any] = ["artist": artist, "isPlaying": isPlaying, "title": title]
    guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
    UserDefaults(suiteName: suiteName)?.set(data, forKey: stateKey)
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }

  static func clear() {
    lastSignature = ""
    UserDefaults(suiteName: suiteName)?.removeObject(forKey: stateKey)
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }
}
