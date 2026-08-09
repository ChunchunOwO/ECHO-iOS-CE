import SwiftUI
import WidgetKit

private let suiteName = "group.app.echo.next.ios"
private let stateKey = "echo.widget.nowPlaying"

private struct EchoWidgetState: Decodable {
  let artist: String
  let isPlaying: Bool
  let title: String
}

private struct EchoWidgetEntry: TimelineEntry {
  let date: Date
  let state: EchoWidgetState?
}

private struct EchoWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> EchoWidgetEntry {
    EchoWidgetEntry(date: Date(), state: EchoWidgetState(artist: "ECHO", isPlaying: true, title: "正在播放"))
  }

  func getSnapshot(in context: Context, completion: @escaping (EchoWidgetEntry) -> Void) {
    completion(EchoWidgetEntry(date: Date(), state: load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<EchoWidgetEntry>) -> Void) {
    completion(Timeline(entries: [EchoWidgetEntry(date: Date(), state: load())], policy: .never))
  }

  private func load() -> EchoWidgetState? {
    guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: stateKey) else { return nil }
    return try? JSONDecoder().decode(EchoWidgetState.self, from: data)
  }
}

private struct EchoWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: EchoWidgetEntry

  private var artistLabel: String {
    let artist = entry.state?.artist ?? ""
    return artist.isEmpty ? "打开 ECHO 开始播放" : artist
  }

  var body: some View {
    Link(destination: URL(string: "echo://now-playing")!) {
      ZStack(alignment: .bottomLeading) {
        LinearGradient(
          colors: [Color(red: 0.68, green: 0.12, blue: 0.15), Color(red: 0.08, green: 0.43, blue: 0.45), Color(red: 0.95, green: 0.58, blue: 0.24)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        pattern
        VStack(alignment: .leading, spacing: family == .systemSmall ? 7 : 9) {
          HStack {
            Image(systemName: entry.state?.isPlaying == true ? "waveform" : "pause.fill")
            Text("ECHO").font(.caption.bold())
            Spacer()
          }
          Spacer(minLength: 8)
          Text(entry.state?.title ?? "暂无歌曲数据")
            .font(family == .systemSmall ? .headline : .title3.bold())
            .lineLimit(2)
            .minimumScaleFactor(0.72)
          Text(artistLabel)
            .font(.caption)
            .lineLimit(1)
            .opacity(0.78)
        }
        .padding(16)
        .foregroundStyle(.white)
      }
    }
    .echoWidgetBackground()
  }

  private var pattern: some View {
    GeometryReader { geometry in
      ForEach(0..<10, id: \.self) { index in
        Image(systemName: "camera.macro")
          .font(.system(size: CGFloat(10 + index % 3 * 3)))
          .foregroundStyle(.white.opacity(0.1))
          .position(
            x: CGFloat((index * 47) % 100) / 100 * geometry.size.width,
            y: CGFloat((index * 71) % 100) / 100 * geometry.size.height
          )
      }
    }
  }
}

private extension View {
  @ViewBuilder
  func echoWidgetBackground() -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { Color.clear }
    } else {
      background(Color.clear)
    }
  }
}

@main
struct EchoWidgetBundle: WidgetBundle {
  var body: some Widget {
    EchoNowPlayingWidget()
  }
}

private struct EchoNowPlayingWidget: Widget {
  let kind = "EchoNowPlayingWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: EchoWidgetProvider()) { entry in
      EchoWidgetView(entry: entry)
    }
    .configurationDisplayName("ECHO 正在播放")
    .description("查看当前播放的歌曲。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
