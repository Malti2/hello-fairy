import Foundation

/// game of life auf dem vorhang: malen mit dem finger, wischen = tempo, tippen = neu mischen
final class Life: CurtainApp {
    let rng: GameRNG
    private(set) var alive: [Bool] = []
    private(set) var age: [Int] = []
    private(set) var generation = 0
    private var history: [Int] = []
    private var stale = 0
    private var currentTick = 0.16

    var tick: Double { currentTick }
    var hint: String { "mit dem finger malen · tippen mischt neu · hoch/runter wischen = tempo" }

    init(rng: GameRNG = GameRNG()) {
        self.rng = rng
        reset()
    }

    func reset() {
        reseed()
        currentTick = 0.16
    }

    func reseed() {
        alive = (0..<PIXELS).map { _ in rng.double() < 0.3 }
        age = alive.map { $0 ? 1 : 0 }
        generation = 0
        history = []
        stale = 0
    }

    /// nur diese zellen leben (fuer tests und muster)
    func load(_ cells: [(Int, Int)]) {
        alive = [Bool](repeating: false, count: PIXELS)
        age = [Int](repeating: 0, count: PIXELS)
        for (x, y) in cells { alive[y * W + x] = true; age[y * W + x] = 1 }
        history = []
        stale = 0
    }

    var population: Int { alive.filter { $0 }.count }

    func status() -> String { "generation \(generation)  zellen \(population)" }

    func touch(x: Double, y: Double) {
        let cx = max(0, min(W - 1, Int(x * Double(W)))), cy = max(0, min(H - 1, Int(y * Double(H))))
        let i = cy * W + cx
        if !alive[i] { alive[i] = true; age[i] = 1 }
        stale = 0
    }

    func key(_ key: Key) {
        switch key {
        case .space, .enter: reseed()
        case .up: currentTick = max(0.04, currentTick - 0.03)
        case .down: currentTick = min(0.5, currentTick + 0.03)
        default: break
        }
    }

    private func neighbors(_ x: Int, _ y: Int) -> Int {
        var n = 0
        for dy in -1...1 {
            for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = (x + dx + W) % W, yy = (y + dy + H) % H
                if alive[yy * W + xx] { n += 1 }
            }
        }
        return n
    }

    func step() {
        var next = alive
        var nextAge = age
        for y in 0..<H {
            for x in 0..<W {
                let i = y * W + x
                let n = neighbors(x, y)
                if alive[i] {
                    next[i] = n == 2 || n == 3
                    nextAge[i] = next[i] ? age[i] + 1 : 0
                } else {
                    next[i] = n == 3
                    nextAge[i] = next[i] ? 1 : 0
                }
            }
        }
        alive = next
        age = nextAge
        generation += 1
        let h = alive.hashValue
        if history.contains(h) { stale += 1 } else { stale = 0 }
        history.append(h)
        if history.count > 12 { history.removeFirst() }
        if population == 0 || stale >= 10 { reseed() }
    }

    func frame() -> Frame {
        (0..<PIXELS).map { i in
            guard alive[i] else { return Px.off }
            switch age[i] {
            case 1: return Px.white
            case 2...3: return 90
            case 4...8: return 120
            default: return 140
            }
        }
    }
}
