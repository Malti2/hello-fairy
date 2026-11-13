import Foundation

/// timer und stoppuhr. tippen = start/pause, hoch/runter = minuten, links/rechts = timer <-> stoppuhr
final class CountdownApp: CurtainApp {
    enum Mode: String { case timer, stopwatch }

    private(set) var mode: Mode = .timer
    private(set) var minutes: Int
    private(set) var running = false
    private var accumulated = 0.0
    private var startedAt = 0.0
    private(set) var finished = false
    private let clock: () -> Double
    var onFinish: (() -> Void)?

    let tick = 0.1
    var hint: String { "tippen startet/pausiert · hoch/runter = minuten · links/rechts = timer / stoppuhr" }

    init(minutes: Int = 5, clock: @escaping () -> Double = monotonicNow) {
        self.minutes = max(1, minutes)
        self.clock = clock
    }

    var total: Double { Double(minutes * 60) }

    var elapsed: Double {
        accumulated + (running ? clock() - startedAt : 0)
    }

    var remaining: Double { max(0, total - elapsed) }

    func reset() {
        running = false
        finished = false
        accumulated = 0
    }

    func setMinutes(_ m: Int) {
        guard m != minutes else { return }
        minutes = max(1, min(99, m))
        if mode == .timer && !running { reset() }
    }

    func key(_ key: Key) {
        switch key {
        case .enter, .space:
            if finished { reset(); return }
            if running {
                accumulated = elapsed
                running = false
            } else {
                startedAt = clock()
                running = true
            }
        case .up:
            if mode == .timer && !running { minutes = min(99, minutes + 1); reset() }
        case .down:
            if mode == .timer && !running { minutes = max(1, minutes - 1); reset() }
        case .left, .right:
            mode = mode == .timer ? .stopwatch : .timer
            reset()
        default: break
        }
    }

    func step() {
        if mode == .timer && running && remaining <= 0 {
            running = false
            finished = true
            accumulated = total
            onFinish?()
        }
    }

    func status() -> String {
        let name = mode == .timer ? "timer \(minutes) min" : "stoppuhr"
        if finished { return "\(name)  FERTIG" }
        return "\(name)  " + (running ? "laeuft" : "pausiert")
    }

    private var shownSeconds: Int {
        switch mode {
        case .timer: return Int(remaining.rounded(.up))
        case .stopwatch: return min(99 * 60 + 59, Int(elapsed))
        }
    }

    func frame() -> Frame {
        var f = blankFrame()
        if finished && Int(clock() * 2) % 2 == 0 {                // fertig: blinken
            for i in 0..<PIXELS { f[i] = 0 }
            return f
        }
        let sec = shownSeconds
        let text = String(format: "%02d:%02d", sec / 60, sec % 60)
        let fraction = mode == .timer ? remaining / total : Double(Int(elapsed) % 60) / 60
        let color: UInt8
        if mode == .stopwatch { color = 90 }
        else if fraction > 0.5 { color = 60 }
        else if fraction > 0.2 { color = 30 }
        else { color = 0 }
        var x = (W - Glyphs.textWidth(text)) / 2
        for ch in text {
            if ch == ":" && running && Int(clock()) % 2 == 1 {
                x += Glyphs.width(ch) + 1
                continue
            }
            x = Glyphs.draw(ch, into: &f, x: x, y: 7, color: ch == ":" ? Px.white : color)
        }
        let bar = Int((fraction * 18).rounded())
        for i in 0..<bar { f[17 * W + 1 + i] = color }
        // modus-punkte oben: timer = 1 punkt, stoppuhr = 2
        f[3 * W + 9] = mode == .timer ? 30 : 90
        if mode == .stopwatch { f[3 * W + 11] = 90 }
        return f
    }
}
