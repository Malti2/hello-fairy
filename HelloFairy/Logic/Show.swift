import Foundation

/// lichtshow: plasma, regenbogen, feuer, matrix, sterne. wischen/tippen wechselt den look
final class ShowApp: CurtainApp {
    enum Mode: String, CaseIterable {
        case plasma, rainbow, fire, matrix, stars

        var title: String {
            switch self {
            case .plasma: return "Plasma"
            case .rainbow: return "Regenbogen"
            case .fire: return "Feuer"
            case .matrix: return "Matrix"
            case .stars: return "Sterne"
            }
        }
    }

    struct Drop { var y: Double; var speed: Double; var len: Int }
    struct Star { var angle: Double; var r: Double; var speed: Double }

    let rng: GameRNG
    private(set) var mode: Mode
    private(set) var t = 0
    private var heat = [Int](repeating: 0, count: PIXELS)
    private var drops: [Drop] = []
    private var stars: [Star] = []

    var tick: Double { mode == .fire ? 0.07 : 0.09 }
    var hint: String { "wischen oder tippen wechselt den look" }

    init(mode: Mode = .plasma, rng: GameRNG = GameRNG()) {
        self.mode = mode
        self.rng = rng
        reset()
    }

    func reset() {
        t = 0
        heat = [Int](repeating: 0, count: PIXELS)
        drops = (0..<W).map { _ in newDrop(initial: true) }
        stars = (0..<26).map { _ in newStar(initial: true) }
    }

    func status() -> String { mode.title }

    func key(_ key: Key) {
        let all = Mode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        switch key {
        case .right, .down, .enter, .space: mode = all[(i + 1) % all.count]
        case .left, .up: mode = all[(i + all.count - 1) % all.count]
        default: break
        }
    }

    private func newDrop(initial: Bool) -> Drop {
        Drop(y: initial ? -Double(rng.below(H * 2)) : -Double(rng.below(8)),
             speed: 0.4 + rng.double() * 0.9, len: rng.int(3...9))
    }

    private func newStar(initial: Bool) -> Star {
        Star(angle: rng.double() * 2 * Double.pi, r: initial ? rng.double() * 10 : 0.5, speed: 0.15 + rng.double() * 0.25)
    }

    func step() {
        t += 1
        switch mode {
        case .fire: stepFire()
        case .matrix:
            for i in drops.indices {
                drops[i].y += drops[i].speed
                if drops[i].y - Double(drops[i].len) > Double(H) { drops[i] = newDrop(initial: false) }
            }
        case .stars:
            for i in stars.indices {
                stars[i].r += stars[i].speed * (1 + stars[i].r / 5)
                if stars[i].r > 15 { stars[i] = newStar(initial: false) }
            }
        default: break
        }
    }

    private func stepFire() {
        for x in 0..<W { heat[(H - 1) * W + x] = rng.int(140...255) }
        for y in 0..<(H - 1) {
            for x in 0..<W {
                let l = heat[(y + 1) * W + max(0, x - 1)], c = heat[(y + 1) * W + x], r = heat[(y + 1) * W + min(W - 1, x + 1)]
                let d = heat[min(H - 1, y + 2) * W + x]
                heat[y * W + x] = max(0, (l + c + r + d) * 100 / 420 - rng.int(0...9))
            }
        }
    }

    func frame() -> Frame {
        switch mode {
        case .rainbow:
            return (0..<PIXELS).map { i in
                let x = i % W, y = i / W
                return UInt8((x * 4 + y * 4 + t * 5) % 181)
            }
        case .plasma:
            let tt = Double(t)
            return (0..<PIXELS).map { i in
                let x = Double(i % W), y = Double(i / W)
                let v = sin(x / 3 + tt / 10) + sin(y / 4 + tt / 13) + sin((x + y) / 5 + tt / 7)
                    + sin(hypot(x - 10, y - 10) / 3 - tt / 8)
                if v < -2.4 { return Px.off }
                return UInt8(min(180, Int((v + 4) / 8 * 180)))
            }
        case .fire:
            return heat.map { h in
                if h < 38 { return Px.off }
                if h < 85 { return 0 }
                if h < 135 { return 15 }
                if h < 190 { return 30 }
                return Px.white
            }
        case .matrix:
            var f = blankFrame()
            for (x, d) in drops.enumerated() {
                let head = Int(d.y.rounded(.down))
                for k in 0..<d.len {
                    let y = head - k
                    guard (0..<H).contains(y) else { continue }
                    f[y * W + x] = k == 0 ? Px.white : 60
                }
            }
            return f
        case .stars:
            var f = blankFrame()
            for s in stars {
                let x = Int((9.5 + cos(s.angle) * s.r).rounded()), y = Int((9.5 + sin(s.angle) * s.r).rounded())
                guard (0..<W).contains(x), (0..<H).contains(y) else { continue }
                f[y * W + x] = s.r > 7 ? Px.white : (s.r > 3 ? 90 : 120)
            }
            return f
        }
    }
}
