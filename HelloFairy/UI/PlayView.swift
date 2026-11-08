import SwiftUI
import UIKit

/// was die beiden aktions-knoepfe in welcher app tun
private struct PadLayout {
    var a: String?
    var b: String?
    var upRepeats = false
    var dpad = true
}

private func layout(for id: String) -> PadLayout {
    switch id {
    case "tetris": return PadLayout(a: "drop", b: "dreh")
    case "mario": return PadLayout(a: "sprung", b: "feuer")
    case "mirror": return PadLayout(a: "bg", b: nil)
    case "pong": return PadLayout(upRepeats: true)
    case "clock", "weather": return PadLayout(a: "ok", b: nil)
    default: return PadLayout()
    }
}

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ArcadeRunner.self) private var runner
    @Environment(\.scenePhase) private var scenePhase

    let appID: String

    var body: some View {
        let pad = layout(for: appID)
        ZStack {
            Backdrop()
            VStack(spacing: 14) {
                header
                curtain
                Text(runner.statusText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity)
                if let note = runner.note {
                    Text(note).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
                } else if !model.link.isReady {
                    Text("nur vorschau: vorhang nicht verbunden").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                controls(pad)
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { runner.paused = true }
        }
    }

    private var title: String {
        CurtainMenu.items.first { $0.id == appID }?.title ?? appID
    }

    private var header: some View {
        HStack {
            Button {
                Task { await model.close() }
            } label: {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Spacer()
            Text(title).font(.title3.weight(.bold))
            Spacer()

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { runner.paused.toggle() } label: {
                        Image(systemName: runner.paused ? "play.fill" : "pause.fill")
                            .font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)

                    Button { runner.restart() } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.title3.weight(.semibold)).frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                }
            }
        }
    }

    /// vorhang gross + wischgesten (snake, tetris, ...)
    private var curtain: some View {
        CurtainView(frame: runner.frame)
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 30))
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        if abs(dx) > abs(dy) { runner.press(dx > 0 ? .right : .left) }
                        else { runner.press(dy > 0 ? .down : .up) }
                    }
            )
    }

    private func controls(_ pad: PadLayout) -> some View {
        HStack(alignment: .bottom) {
            GlassEffectContainer(spacing: 10) {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        Color.clear.frame(width: 64, height: 64)
                        PadButton(symbol: "chevron.up", repeats: pad.upRepeats) { runner.press(.up) }
                        Color.clear.frame(width: 64, height: 64)
                    }
                    GridRow {
                        PadButton(symbol: "chevron.left", repeats: true) { runner.press(.left) }
                        Color.clear.frame(width: 64, height: 64)
                        PadButton(symbol: "chevron.right", repeats: true) { runner.press(.right) }
                    }
                    GridRow {
                        Color.clear.frame(width: 64, height: 64)
                        PadButton(symbol: "chevron.down", repeats: true) { runner.press(.down) }
                        Color.clear.frame(width: 64, height: 64)
                    }
                }
            }
            Spacer()
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    if let b = pad.b {
                        PadButton(label: b, repeats: false, size: 76) { runner.press(.rotate) }
                    }
                    if let a = pad.a {
                        PadButton(label: a, repeats: false, size: 76) { runner.press(.space) }
                    }
                }
            }
        }
    }
}

/// glas-knopf mit druck-sofort-reaktion und optionalem halten-zum-wiederholen
struct PadButton: View {
    var symbol: String?
    var label: String?
    var repeats: Bool
    var size: CGFloat = 64
    let action: () -> Void

    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?

    init(symbol: String, repeats: Bool, size: CGFloat = 64, action: @escaping () -> Void) {
        self.symbol = symbol
        self.repeats = repeats
        self.size = size
        self.action = action
    }

    init(label: String, repeats: Bool, size: CGFloat = 64, action: @escaping () -> Void) {
        self.label = label
        self.repeats = repeats
        self.size = size
        self.action = action
    }

    var body: some View {
        Group {
            if let symbol {
                Image(systemName: symbol).font(.title.weight(.bold))
            } else {
                Text(label ?? "").font(.subheadline.weight(.bold))
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.interactive(), in: Circle())
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    action()
                    if repeats {
                        repeater = Task {
                            try? await Task.sleep(nanoseconds: 260_000_000)
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(nanoseconds: 90_000_000)
                            }
                        }
                    }
                }
                .onEnded { _ in
                    pressed = false
                    repeater?.cancel()
                    repeater = nil
                }
        )
    }
}
