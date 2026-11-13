import Foundation

/// flappy: tippen = flattern, durch die luecken zwischen den rohren
final class Flappy: CurtainApp {
    static let birdX = 4
    static let gap = 6
    static let spacing = 9
    static let flapVY = -2

    struct Pipe {
        var x: Int
        var gapTop: Int
        var scored = false
    }

    let rng: GameRNG
    let clock: () -> Double

    private(set) var y = 9
    private(set) var vy = 0
    private(set) var pipes: [Pipe] = []
    private(set) var score = 0
    private(set) var best = 0
    private(set) var started = false
    private(set) var over = false
    private var banners = BannerQueue()

    var tick: Double { max(0.07, 0.13 - 0.003 * Double(score)) }
    var hint: String { "tippen = flattern" }

    init(rng: GameRNG = GameRNG(), clock: @escaping () -> Double = monotonicNow) {
        self.rng = rng
        self.clock = clock
        reset()
    }

    func reset() {
        y = 9; vy = 0; score = 0
        started = false; over = false
        banners.clear()
        pipes = [Pipe(x: 22, gapTop: rng.int(4...10))]
    }

    func status() -> String {
        started || over ? "score \(score)  best \(best)" : "tippen zum start"
    }

    func key(_ key: Key) {
        guard !over, banners.current(now: clock()) == nil else { return }
        switch key {
        case .space, .up, .enter:
            started = true
            vy = Flappy.flapVY
        default: break
        }
    }

    func step() {
        if over || banners.current(now: clock()) != nil || !started { return }
        y += vy
        vy = min(2, vy + 1)
        for i in pipes.indices { pipes[i].x -= 1 }
        pipes.removeAll { $0.x < -2 }
        if let last = pipes.last, last.x <= W - Flappy.spacing {
            let next = max(2, min(H - 2 - Flappy.gap, last.gapTop + rng.int(-4...4)))
            pipes.append(Pipe(x: W + 1, gapTop: next))
        }
        for i in pipes.indices where !pipes[i].scored && pipes[i].x + 1 < Flappy.birdX {
            pipes[i].scored = true
            score += 1
        }
        if y < 0 || y >= H { die(); return }
        for p in pipes where Flappy.birdX >= p.x && Flappy.birdX <= p.x + 1 {
            if y < p.gapTop || y >= p.gapTop + Flappy.gap { die(); return }
        }
    }

    private func die() {
        over = true
        best = max(best, score)
        banners.set([(textFrame("\(score)", color: 30), 1.5), (gameOverText(), .infinity)])
    }

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        var f = blankFrame()
        for p in pipes {
            for x in [p.x, p.x + 1] where (0..<W).contains(x) {
                for yy in 0..<H where yy < p.gapTop || yy >= p.gapTop + Flappy.gap {
                    let cap = yy == p.gapTop - 1 || yy == p.gapTop + Flappy.gap
                    f[yy * W + x] = cap ? 45 : 60
                }
            }
        }
        if (0..<H).contains(y) { f[y * W + Flappy.birdX] = 30 }
        return f
    }
}
