import Foundation

struct AudioSample {
    var level: Float        // 0...1 lautstaerke
    var pitch: Float        // 0...1 tonhoehe (tief ... hoch)
}

protocol LevelSource: AnyObject {
    func read() -> AudioSample?
    func close()
}

/// kuenstliches audio fuer tests und den simulator: takt mit wandernder tonhoehe
final class DemoAudio: LevelSource {
    private let t0 = monotonicNow()

    func read() -> AudioSample? {
        let t = monotonicNow() - t0
        let beat = pow(max(0, sin(t * 6.0)), 3)
        return AudioSample(level: Float(0.15 + 0.8 * beat * (0.6 + 0.4 * sin(t * 1.7))),
                           pitch: Float(0.5 + 0.5 * sin(t * 0.9)))
    }

    func close() {}
}

/// musik/ton als leuchtende saeulen: verlauf von links nach rechts, hoehe = lautstaerke, farbe = tonhoehe
final class SoundApp: CurtainApp {
    enum Mode: String, CaseIterable {
        case bars, mirror

        var title: String { self == .bars ? "Saeulen" : "Spiegel" }
    }

    private var source: LevelSource?
    private let makeSource: (() async throws -> LevelSource)?
    private(set) var mode: Mode = .bars
    private(set) var error: String?
    private(set) var history: [Float] = Array(repeating: 0, count: W)
    private(set) var pitches: [Float] = Array(repeating: 0.5, count: W)
    private var peak: Float = 0.05
    private(set) var haveAudio = false

    let tick = 0.05
    var hint: String { "wischen oder tippen wechselt die darstellung" }

    init(source: LevelSource? = nil, makeSource: (() async throws -> LevelSource)? = nil) {
        self.source = source
        self.makeSource = makeSource
    }

    func start() async {
        guard source == nil, let make = makeSource else { return }
        error = nil
        do { source = try await make() } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() {
        source?.close()
        source = nil
    }

    func replaceSource(_ new: LevelSource?) {
        source?.close()
        source = new
        error = nil
    }

    func reset() {
        history = Array(repeating: 0, count: W)
        pitches = Array(repeating: 0.5, count: W)
        peak = 0.05
    }

    func status() -> String {
        if let e = error { return e }
        if !haveAudio { return "warte auf mikrofon..." }
        return mode.title
    }

    func key(_ key: Key) {
        let all = Mode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        switch key {
        case .right, .left, .enter, .space, .up, .down: mode = all[(i + 1) % all.count]
        default: break
        }
    }

    func step() {
        guard let s = source?.read() else { return }
        haveAudio = true
        peak = max(0.05, peak * 0.995, s.level)          // automatische verstaerkung
        let norm = min(1, s.level / peak)
        history.removeFirst()
        history.append(norm)
        pitches.removeFirst()
        pitches.append(s.pitch)
    }

    func frame() -> Frame {
        if error != nil { return WeatherFace.errorFrame() }
        var f = blankFrame()
        for x in 0..<W {
            let level = history[x]
            let hue = UInt8(max(0, min(180, Int(pitches[x] * 150))))
            switch mode {
            case .bars:
                let h = Int((level * Float(H - 1)).rounded()) + (level > 0.02 ? 1 : 0)
                for k in 0..<min(H, h) { f[(H - 1 - k) * W + x] = k >= H - 3 ? Px.white : hue }
            case .mirror:
                let half = Int((level * Float(H / 2)).rounded())
                for k in 0..<half {
                    f[(H / 2 - 1 - k) * W + x] = hue
                    f[(H / 2 + k) * W + x] = hue
                }
                if level > 0.02 { f[(H / 2) * W + x] = Px.white }
            }
        }
        return f
    }
}
