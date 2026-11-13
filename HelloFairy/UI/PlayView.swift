import SwiftUI
import UIKit

struct PlayView: View {
    @Environment(AppModel.self) private var model
    @Environment(ArcadeRunner.self) private var runner
    @Environment(\.scenePhase) private var scenePhase

    let appID: String
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 12) {
                header
                InputSurface(appID: appID) {
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)
                        CurtainView(frame: runner.frame)
                            .overlay { if InputSurface<EmptyView>.directTouch(appID) { touchPad } }
                            .padding(14)
                            .glassEffect(.regular, in: .rect(cornerRadius: 30))
                        info
                        Spacer(minLength: 0)
                    }
                }
                buttons
            }
            .padding(16)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && appID != "sound" { runner.paused = true }
        }
        .sheet(isPresented: $showSettings, onDismiss: { model.applySettings() }) {
            AppSettingsSheet(appID: appID)
                .presentationDetents([.medium, .large])
        }
    }

    private var title: String {
        CurtainMenu.items.first { $0.id == appID }?.title ?? appID
    }

    // MARK: kopfzeile

    private func round(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var header: some View {
        HStack(spacing: 8) {
            round("xmark") { Task { await model.close() } }
            Spacer()
            Text(title).font(.title3.weight(.bold))
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    round(runner.paused ? "play.fill" : "pause.fill") { runner.paused.toggle() }
                    round("arrow.counterclockwise") { runner.restart() }
                    round("gearshape.fill") { showSettings = true }
                }
            }
        }
    }

    private var info: some View {
        VStack(spacing: 4) {
            Text(runner.statusText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            Text(runner.hintText)
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            if let note = runner.note {
                Text(note).font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            } else if !model.link.isReady {
                Text("nur vorschau: vorhang nicht verbunden").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// finger direkt auf dem vorhang (zeichnen, life): position = pixel
    private var touchPad: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            runner.touch(x: v.location.x / max(1, geo.size.width), y: v.location.y / max(1, geo.size.height))
                        }
                        .onEnded { _ in runner.touchEnded() }
                )
        }
    }

    private func chip(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }

    // MARK: tasten (nur wo wischen/tippen nicht reicht)

    @ViewBuilder
    private var buttons: some View {
        switch appID {
        case "mario":
            HStack {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        PadButton(symbol: "chevron.left", repeats: true, size: 78) { runner.press(.left) }
                        PadButton(symbol: "chevron.right", repeats: true, size: 78) { runner.press(.right) }
                    }
                }
                Spacer()
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        PadButton(label: "Feuer", repeats: false, size: 70) { runner.press(.rotate) }
                        PadButton(label: "Sprung", repeats: false, size: 86) { runner.press(.space) }
                    }
                }
            }
        case "tetris":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { runner.press(.rotate) } label: {
                        Label("Drehen", systemImage: "rotate.right").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    Button { runner.press(.space) } label: {
                        Label("Drop", systemImage: "arrow.down.to.line").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
            }
        case "mirror":
            Button { runner.press(.space) } label: {
                Label("Hintergrund neu aufnehmen", systemImage: "camera.metering.center.weighted")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.glass)
        case "paint":
            PaintTools()
        case "life":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    chip("Zufall", "dice.fill") { runner.press(.space) }
                    chip("Langsamer", "tortoise.fill") { runner.press(.down) }
                    chip("Schneller", "hare.fill") { runner.press(.up) }
                }
            }
        case "show", "sound":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    chip("Zurueck", "chevron.left") { runner.press(.left) }
                    chip("Weiter", "chevron.right") { runner.press(.right) }
                }
            }
        case "marquee":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    chip("Langsamer", "tortoise.fill") { runner.press(.down) }
                    chip("Farbe", "paintpalette.fill") { runner.press(.enter) }
                    chip("Schneller", "hare.fill") { runner.press(.up) }
                }
            }
        case "timer":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    chip("Minute", "minus") { runner.press(.down) }
                    Button { runner.press(.enter) } label: {
                        Label("Start / Pause", systemImage: "playpause.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    chip("Minute", "plus") { runner.press(.up) }
                    chip("Modus", "arrow.left.arrow.right") { runner.press(.right) }
                }
            }
        default:
            EmptyView()
        }
    }
}

// MARK: - eingabe per finger

/// legt die touch-steuerung der jeweiligen app ueber den inhalt
/// pong: schlaeger folgt dem finger · snake/tetris/...: wischen und tippen
struct InputSurface<Content: View>: View {
    @Environment(ArcadeRunner.self) private var runner
    let appID: String
    let content: Content

    @State private var last: CGPoint?
    @State private var moved = false

    init(appID: String, @ViewBuilder content: () -> Content) {
        self.appID = appID
        self.content = content()
    }

    /// diese apps lesen die position direkt auf dem vorhang (siehe PlayView.touchPad)
    static func directTouch(_ id: String) -> Bool { id == "paint" || id == "life" }

    private var threshold: CGFloat {
        switch appID {
        case "snake": return 22
        case "tetris": return 30
        default: return 44
        }
    }

    var body: some View {
        GeometryReader { geo in
            if Self.directTouch(appID) {
                content.frame(width: geo.size.width, height: geo.size.height)
            } else {
                content
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in handleChange(v, size: geo.size) }
                            .onEnded { v in handleEnd(v) }
                    )
            }
        }
    }

    private func handleChange(_ v: DragGesture.Value, size: CGSize) {
        if appID == "pong" {
            let ny = (v.location.y / max(1, size.height) - 0.1) / 0.8        // ränder frei, damit der schläger die enden erreicht
            runner.touch(x: v.location.x / max(1, size.width), y: max(0, min(1, ny)))
            return
        }
        if appID == "breakout" {
            let nx = (v.location.x / max(1, size.width) - 0.1) / 0.8
            runner.touch(x: max(0, min(1, nx)), y: 0.5)
            return
        }
        if appID == "flappy" {
            if last == nil { last = v.startLocation; runner.press(.space); UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            return
        }
        if last == nil { last = v.startLocation; moved = false }
        guard let l = last else { return }
        let dx = v.location.x - l.x, dy = v.location.y - l.y
        guard max(abs(dx), abs(dy)) >= threshold else { return }
        let key: Key = abs(dx) > abs(dy) ? (dx > 0 ? .right : .left) : (dy > 0 ? .down : .up)
        last = v.location
        moved = true
        if appID == "mario", key == .left || key == .right { return }       // laufen laeuft ueber die tasten
        runner.press(key)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
    }

    private func handleEnd(_ v: DragGesture.Value) {
        defer { last = nil; moved = false }
        if appID == "pong" || appID == "flappy" { return }
        if appID == "breakout" { runner.press(.space); return }           // loslassen startet den ball
        if !moved {
            switch appID {          // tippen
            case "tetris": runner.press(.rotate)
            case "mario": runner.press(.space)
            case "mirror": runner.press(.space)
            case "clock", "weather", "show", "marquee", "timer", "sound": runner.press(.enter)
            default: break
            }
        } else if appID == "tetris" {
            // schneller wisch nach unten = hard drop
            let extra = v.predictedEndTranslation.height - v.translation.height
            if extra > 250 && v.translation.height > 40 && abs(v.translation.height) > abs(v.translation.width) {
                runner.press(.space)
            }
        }
    }
}

// MARK: - einstellungen pro app

struct AppSettingsSheet: View {
    let appID: String
    @Environment(\.dismiss) private var dismiss

    @AppStorage("hf.city") private var city = ""
    @AppStorage("hf.pong.difficulty") private var difficulty = "normal"
    @AppStorage("hf.pong.points") private var points = 5
    @AppStorage("hf.minInterval") private var minInterval = 0.06
    @AppStorage("hf.demoCamera") private var demoCamera = false
    @AppStorage("hf.demoAudio") private var demoAudio = false
    @AppStorage("hf.marquee.text") private var marqueeText = "HELLO FAIRY"
    @AppStorage("hf.marquee.big") private var marqueeBig = true
    @AppStorage("hf.marquee.rainbow") private var marqueeRainbow = true
    @AppStorage("hf.marquee.tick") private var marqueeTick = 0.09
    @AppStorage("hf.timer.minutes") private var timerMinutes = 5

    var body: some View {
        NavigationStack {
            Form {
                switch appID {
                case "pong":
                    Section("Pong") {
                        Picker("Gegner", selection: $difficulty) {
                            Text("leicht").tag("easy")
                            Text("normal").tag("normal")
                            Text("hart").tag("hard")
                        }
                        Stepper("Bis \(points) Punkte", value: $points, in: 1...15)
                    }
                case "weather":
                    Section("Wetter") {
                        TextField("Stadt (z.B. Berlin)", text: $city)
                            .submitLabel(.done)
                            .autocorrectionDisabled()
                    }
                case "mirror":
                    Section("Kamera") {
                        Toggle("Demo-Kamera statt echter Kamera", isOn: $demoCamera)
                    }
                case "sound":
                    Section("Mikrofon") {
                        Toggle("Demo-Ton statt Mikrofon", isOn: $demoAudio)
                    }
                case "marquee":
                    Section("Laufschrift") {
                        TextField("Text", text: $marqueeText)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                        Toggle("Gross (2x)", isOn: $marqueeBig)
                        Toggle("Regenbogen", isOn: $marqueeRainbow)
                        VStack(alignment: .leading) {
                            Text("Tempo")
                            Slider(value: $marqueeTick, in: 0.03...0.25) { Text("Tempo") }
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                    }
                case "timer":
                    Section("Timer") {
                        Stepper("\(timerMinutes) Minuten", value: $timerMinutes, in: 1...99)
                    }
                default:
                    EmptyView()
                }
                Section("Vorhang") {
                    VStack(alignment: .leading) {
                        Text("Sendetakt \(Int(minInterval * 1000)) ms")
                        Slider(value: $minInterval, in: 0.03...0.2, step: 0.01)
                        Text("Hakelt das Bild auf dem Vorhang, den Takt erhoehen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}

// MARK: - knopf

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

// MARK: - zeichnen: farbpalette

struct PaintTools: View {
    @Environment(ArcadeRunner.self) private var runner
    @State private var selected = 3

    private var paint: PaintApp? { runner.app as? PaintApp }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(PaintApp.palette.indices, id: \.self) { i in
                            Button {
                                selected = i
                                paint?.select(i)
                            } label: {
                                swatch(i)
                            }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: Circle())
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { paint?.fill() } label: {
                        Label("Fuellen", systemImage: "drop.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    Button { paint?.clear() } label: {
                        Label("Leeren", systemImage: "trash").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .onAppear { selected = paint?.selected ?? 3 }
    }

    @ViewBuilder
    private func swatch(_ i: Int) -> some View {
        let c = PaintApp.palette[i]
        ZStack {
            if c == Px.off {
                Image(systemName: "eraser.fill").font(.body)
            } else {
                Circle().fill(CurtainPalette.color(c)).frame(width: 30, height: 30)
            }
            if selected == i { Circle().strokeBorder(.white, lineWidth: 3).frame(width: 40, height: 40) }
        }
        .frame(width: 48, height: 48)
    }
}
