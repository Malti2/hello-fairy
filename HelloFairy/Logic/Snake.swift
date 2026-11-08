import Foundation

struct Cell: Hashable {
    var x: Int
    var y: Int
}

/// snake auf dem inneren 18x18 feld, aussenrand ist eine weisse wand
final class Snake: CurtainApp {
    static let head: UInt8 = 30, body: UInt8 = 60, food: UInt8 = 0, dead: UInt8 = 0
    static let dirs: [Key: (Int, Int)] = [.up: (0, -1), .down: (0, 1), .left: (-1, 0), .right: (1, 0)]
    static let opposite: [Key: Key] = [.up: .down, .down: .up, .left: .right, .right: .left]

    let w: Int, h: Int
    let wrap: Bool
    let border: Bool
    let rng: GameRNG
    let clock: () -> Double
    let baseTick: Double
    let speedup: Double

    private(set) var cells: [Cell] = []        // kopf zuerst
    private(set) var dir: Key = .right
    private var queue: [Key] = []
    private(set) var alive = true
    private(set) var score = 0
    private(set) var foodCell: Cell?
    private var banners = BannerQueue()
    private var currentTick: Double

    var tick: Double { currentTick }
    var hint: String { "wischen oder d-pad lenkt · pause · neustart" }

    init(w: Int = W - 2, h: Int = H - 2, wrap: Bool = false, border: Bool = true, tick: Double = 0.22,
         speedup: Double = 0.004, rng: GameRNG = GameRNG(), clock: @escaping () -> Double = monotonicNow) {
        self.w = w; self.h = h; self.wrap = wrap; self.border = border
        self.rng = rng; self.clock = clock
        self.baseTick = tick; self.speedup = speedup
        self.currentTick = tick
        reset()
    }

    func reset() {
        let cx = w / 2, cy = h / 2
        cells = (0..<3).map { Cell(x: cx - $0, y: cy) }
        dir = .right
        queue = []
        alive = true
        score = 0
        currentTick = baseTick
        banners.clear()
        foodCell = placeFood()
    }

    private func placeFood() -> Cell? {
        let taken = Set(cells)
        var free: [Cell] = []
        for x in 0..<w { for y in 0..<h where !taken.contains(Cell(x: x, y: y)) { free.append(Cell(x: x, y: y)) } }
        return free.isEmpty ? nil : rng.choice(free)
    }

    func turn(_ d: Key) {
        let last = queue.last ?? dir
        if d != last, d != Snake.opposite[last], queue.count < 2 { queue.append(d) }
    }

    func key(_ key: Key) {
        if Snake.dirs[key] != nil { turn(key) }
    }

    func status() -> String {
        "score \(score)" + (alive ? "" : "   GAME OVER")
    }

    func step() {
        guard alive else { return }
        if !queue.isEmpty { dir = queue.removeFirst() }
        let (dx, dy) = Snake.dirs[dir] ?? (1, 0)
        var nx = cells[0].x + dx, ny = cells[0].y + dy
        if wrap {
            nx = ((nx % w) + w) % w
            ny = ((ny % h) + h) % h
        } else if !(0 <= nx && nx < w && 0 <= ny && ny < h) {
            die()
            return
        }
        let next = Cell(x: nx, y: ny)
        let eating = next == foodCell
        let bodyCells = eating ? cells : Array(cells.dropLast())
        if bodyCells.contains(next) {
            die()
            return
        }
        cells.insert(next, at: 0)
        if eating {
            score += 1
            foodCell = placeFood()
            currentTick = max(0.08, currentTick - speedup * 5)
            if foodCell == nil { die() }   // brett voll: gewonnen
        } else {
            cells.removeLast()
        }
    }

    private func die() {
        alive = false
        banners.set(Snake.gameOverFrames(dead: board()))
    }

    private func board() -> Frame {
        let o = border ? (W - w) / 2 : 0
        var f = blankFrame()
        if border {
            for i in 0..<W {
                f[i] = Px.white
                f[(H - 1) * W + i] = Px.white
                f[i * W] = Px.white
                f[i * W + W - 1] = Px.white
            }
        }
        if let fc = foodCell { f[(fc.y + o) * W + fc.x + o] = Snake.food }
        for (i, c) in cells.enumerated() {
            f[(c.y + o) * W + c.x + o] = alive ? (i == 0 ? Snake.head : Snake.body) : Snake.dead
        }
        return f
    }

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        return board()
    }

    /// game over: blinken, rote welle runter, wieder raus, dann "GAME OVER"
    static func gameOverFrames(dead: Frame) -> [(frame: Frame, secs: Double)] {
        let live = dead.map { $0 == Px.white ? Px.white : Px.off }
        var seq: [(frame: Frame, secs: Double)] = []
        for _ in 0..<3 {
            seq.append((dead, 0.22))
            seq.append((live, 0.18))
        }
        for r in 1..<(H - 1) {
            var f = live
            for y in 1...r { for x in 1..<(W - 1) { f[y * W + x] = Snake.dead } }
            seq.append((f, 0.045))
        }
        for r in 1..<(H - 1) {
            var f = live
            if r + 1 <= H - 2 {
                for y in (r + 1)...(H - 2) { for x in 1..<(W - 1) { f[y * W + x] = Snake.dead } }
            }
            seq.append((f, 0.045))
        }
        seq.append((stackedTextFrame(["GAME"], color: Snake.dead), 0.6))
        seq.append((gameOverText(), .infinity))
        return seq
    }
}
