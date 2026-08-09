import SwiftUI

struct EchoNativeSplashView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let forceReduceMotion: Bool
  @State private var entered = false
  @State private var breathing = false

  private var motionReduced: Bool { reduceMotion || forceReduceMotion }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [
          Color(red: 0.12, green: 0.04, blue: 0.22),
          Color(red: 0.34, green: 0.11, blue: 0.38),
          Color(red: 0.94, green: 0.74, blue: 0.82),
          Color(red: 1.0, green: 0.93, blue: 0.94),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      EchoSplashGlow(reduceMotion: motionReduced)
        .ignoresSafeArea()
      EchoSplashSakuraField(count: 100, reduceMotion: motionReduced)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        Spacer()

        VStack(spacing: 15) {
          ZStack {
            Text("ECHO")
              .font(.custom("Didot-Bold", fixedSize: 82))
              .foregroundStyle(Color.white.opacity(0.94))
              .shadow(color: Color(red: 1, green: 0.68, blue: 0.84).opacity(breathing ? 0.8 : 0.34), radius: breathing ? 26 : 12)
              .minimumScaleFactor(0.7)
              .lineLimit(1)
            EchoSplashTitleShine(reduceMotion: motionReduced)
          }
          .minimumScaleFactor(0.7)
          .lineLimit(1)
          .scaleEffect(breathing && !motionReduced ? 1.018 : 0.99)
          .opacity(entered ? 1 : 0)
          .offset(y: entered ? 0 : 20)
          .animation(motionReduced ? nil : .easeOut(duration: 0.8), value: entered)

          HStack(spacing: 12) {
            EchoSplashDecorationLine()
            Text("ささやき")
              .font(.system(size: 16, weight: .medium, design: .serif))
              .tracking(6)
              .foregroundStyle(Color.white.opacity(0.82))
            EchoSplashDecorationLine()
          }
          .opacity(entered ? 1 : 0)
          .offset(y: entered ? 0 : 14)
          .animation(motionReduced ? nil : .easeOut(duration: 0.8).delay(0.16), value: entered)
        }
        .padding(.horizontal, 28)

        Spacer()

        HStack(spacing: 8) {
          Circle()
            .fill(Color.white.opacity(0.86))
            .frame(width: 6, height: 6)
            .shadow(color: .white.opacity(0.8), radius: breathing ? 9 : 3)
          Text("正在启动")
            .font(.system(size: 13, weight: .semibold))
            .tracking(3)
        }
        .foregroundStyle(Color.white.opacity(breathing ? 0.9 : 0.56))
        .opacity(entered ? 1 : 0)
        .offset(y: entered ? 0 : 12)
        .animation(motionReduced ? nil : .easeOut(duration: 0.75).delay(0.34), value: entered)
        .padding(.bottom, 42)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("ECHO 正在启动")
    .onAppear {
      withAnimation(motionReduced ? nil : .easeOut(duration: 0.9)) { entered = true }
      breathing = true
    }
    .animation(
      motionReduced ? nil : .easeInOut(duration: 1.7).repeatForever(autoreverses: true),
      value: breathing
    )
  }
}

private struct EchoSplashDecorationLine: View {
  var body: some View {
    LinearGradient(
      colors: [.clear, Color.white.opacity(0.72), .clear],
      startPoint: .leading,
      endPoint: .trailing
    )
    .frame(maxWidth: 64, minHeight: 1, maxHeight: 1)
  }
}

private struct EchoSplashTitleShine: View {
  let reduceMotion: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { timeline in
      GeometryReader { geometry in
        let progress = reduceMotion
          ? 0.5
          : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.8) / 2.8
        LinearGradient(
          colors: [.clear, Color.white.opacity(0.88), .clear],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: max(80, geometry.size.width * 0.34))
        .offset(x: -geometry.size.width * 0.4 + geometry.size.width * 1.4 * progress)
      }
      .mask {
        Text("ECHO")
          .font(.custom("Didot-Bold", fixedSize: 82))
          .minimumScaleFactor(0.7)
          .lineLimit(1)
      }
      .blendMode(.screen)
      .frame(maxWidth: 300)
      .frame(height: 108)
    }
  }
}

private struct EchoSplashGlow: View {
  let reduceMotion: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
      EchoSplashGlowCanvas(time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
    }
    .blendMode(.screen)
  }
}

private struct EchoSplashGlowCanvas: View {
  let time: TimeInterval

  var body: some View {
    Canvas { context, size in
      context.drawLayer { glow in
        glow.addFilter(.blur(radius: 54))
        for index in 0..<3 {
          let phase = time * (0.09 + Double(index) * 0.025) + Double(index) * 2.1
          let center = CGPoint(
            x: size.width * (0.5 + sin(phase) * 0.34),
            y: size.height * (0.42 + cos(phase * 0.78) * 0.28)
          )
          let radius = min(size.width, size.height) * CGFloat(0.24 + Double(index) * 0.035)
          let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
          glow.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
              Gradient(colors: [Color.white.opacity(0.2), Color.pink.opacity(0.08), .clear]),
              center: center,
              startRadius: 0,
              endRadius: radius
            )
          )
        }
      }
    }
  }
}

private struct EchoSplashSakuraField: View {
  let count: Int
  let reduceMotion: Bool

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
      Canvas { context, size in
        let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
        for index in 0..<max(80, min(120, count)) {
          drawBlossom(index: index, time: time, size: size, context: &context)
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func drawBlossom(
    index: Int,
    time: TimeInterval,
    size: CGSize,
    context: inout GraphicsContext
  ) {
    let seed = fraction(index * 79 + 17)
    let speed = 22 + fraction(index * 43 + 11) * 48
    let cycle = size.height + 100
    let y = (CGFloat(time) * speed + fraction(index * 61 + 29) * cycle).truncatingRemainder(dividingBy: cycle) - 50
    let baseX = fraction(index * 97 + 37) * size.width
    let sway = 12 + fraction(index * 31 + 7) * 38
    let x = baseX + sin(CGFloat(time) * (0.55 + seed) + seed * 12) * sway
    let scale = 0.52 + fraction(index * 53 + 3) * 0.92
      + sin(CGFloat(time) * 0.8 + seed * 9) * 0.08
    let rotation = Angle.radians(Double(seed * 6.28) + time * Double(0.5 + fraction(index * 19 + 5) * 1.8))
    let edgeFade = max(0, min(1, y / 80, (size.height - y) / 130))
    let alpha = edgeFade * (0.3 + fraction(index * 71 + 13) * 0.58)

    context.drawLayer { blossom in
      blossom.opacity = Double(alpha)
      blossom.translateBy(x: x, y: y)
      blossom.rotate(by: rotation)
      blossom.scaleBy(x: scale, y: scale)
      for petal in 0..<5 {
        blossom.drawLayer { layer in
          layer.rotate(by: .degrees(Double(petal) * 72))
          layer.fill(
            Path(ellipseIn: CGRect(x: -3.8, y: -12, width: 7.6, height: 13)),
            with: .color(petal.isMultiple(of: 2)
              ? Color(red: 1, green: 0.82, blue: 0.9)
              : Color(red: 1, green: 0.93, blue: 0.96))
          )
        }
      }
      blossom.fill(Path(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4)), with: .color(Color.white.opacity(0.9)))
    }
  }

  private func fraction(_ value: Int) -> CGFloat {
    CGFloat(abs(value * 1_103_515_245 &+ 12_345) % 10_000) / 10_000
  }
}
