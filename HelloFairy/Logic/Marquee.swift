import Foundation

/// laufschrift: dein text scrollt ueber den vorhang
final class MarqueeApp: CurtainApp {
    private(set) var text: String
    private(set) var big: Bool
    private(set) var rainbow: Bool
    private(set) var hue: UInt8 = 90
    private var cols: [[Bool]] = []
    private(set) var offset = 0
    private var currentTick: Double

    var tick: Double { currentTick }
    var hint: String { "hoch/runter wischen = tempo · tippen wechselt regenbogen" }

    init(text: String = "HELLO FAIRY", big: Bool = true, rainbow: Bool = true, tick: Double = 0.09) {
        self.text = text
        self.big = big
        self.rainbow = rainbow
        self.currentTick = tick
        rebuild()
    }

    private func rebuild() {
        let t = text.trimmingCharacters(in: .whitespaces)
        cols = Glyphs.bitmap(t.isEmpty ? "HELLO" : t)
        offset = 0
    }

    func configure(text: String, big: Bool, rainbow: Bool, tick: Double) {
        let changed = text != self.text
        self.text = text
        self.big = big
        self.rainbow = rainbow
        self.currentTick = tick
        if changed { rebuild() }
    }

    private var scale: Int { big ? 2 : 1 }
    private var totalWidth: Int { cols.count * scale + W }

    func reset() { offset = 0 }

    func status() -> String { "\"\(text)\"" }

    func key(_ key: Key) {
        switch key {
        case .up: currentTick = max(0.03, currentTick - 0.015)
        case .down: currentTick = min(0.3, currentTick + 0.015)
        case .enter, .space: rainbow.toggle()
        case .left: hue = UInt8((Int(hue) + 170) % 181)
        case .right: hue = UInt8((Int(hue) + 10) % 181)
        default: break
        }
    }

    func step() {
        offset += 1
        if offset > totalWidth { offset = 0 }
    }

    func frame() -> Frame {
        var f = blankFrame()
        let s = scale
        let y0 = (H - 5 * s) / 2
        for (i, col) in cols.enumerated() {
            for dx in 0..<s {
                let x = W - offset + i * s + dx
                guard (0..<W).contains(x) else { continue }
                let color: UInt8 = rainbow ? UInt8((x * 9 + offset * 3) % 181) : hue
                for (r, on) in col.enumerated() where on {
                    for dy in 0..<s { f[(y0 + r * s + dy) * W + x] = color }
                }
            }
        }
        return f
    }
}
