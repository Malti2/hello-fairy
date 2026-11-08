import Foundation

/// tetris: 10x18 feld links, naechster stein + level rechts
final class Tetris: CurtainApp {
    static let cols = 10, rows = 18
    static let fieldX = 1, fieldY = 1
    static let dividerX = 11
    static let panelX = 12

    struct Piece {
        let cells: [(Int, Int)]
        let n: Int
        let color: UInt8
    }

    static let kinds = ["I", "O", "T", "S", "Z", "J", "L"]
    static let pieces: [String: Piece] = [
        "I": Piece(cells: [(0, 1), (1, 1), (2, 1), (3, 1)], n: 4, color: 90),
        "O": Piece(cells: [(0, 0), (1, 0), (0, 1), (1, 1)], n: 2, color: 30),
        "T": Piece(cells: [(1, 0), (0, 1), (1, 1), (2, 1)], n: 3, color: 140),
        "S": Piece(cells: [(1, 0), (2, 0), (0, 1), (1, 1)], n: 3, color: 60),
        "Z": Piece(cells: [(0, 0), (1, 0), (1, 1), (2, 1)], n: 3, color: 0),
        "J": Piece(cells: [(0, 0), (0, 1), (1, 1), (2, 1)], n: 3, color: 120),
        "L": Piece(cells: [(2, 0), (0, 1), (1, 1), (2, 1)], n: 3, color: 15),
    ]
    static let kicks = [(0, 0), (-1, 0), (1, 0), (-2, 0), (2, 0), (0, -1)]
    static let linePoints = [0, 100, 300, 500, 800]

    static func rotated(_ kind: String, _ rot: Int) -> [(Int, Int)] {
        guard let p = pieces[kind] else { return [] }
        var cells = p.cells
        for _ in 0..<(((rot % 4) + 4) % 4) {
            cells = cells.map { (p.n - 1 - $0.1, $0.0) }      // 90 grad im uhrzeigersinn
        }
        return cells
    }

    let rng: GameRNG
    let clock: () -> Double

    private(set) var board: [[UInt8?]] = []
    private var bag: [String] = []
    private(set) var score = 0
    private(set) var lines = 0
    private(set) var over = false
    private var banners = BannerQueue()
    private(set) var kind = "T"
    private(set) var nextKind = "T"
    private(set) var rot = 0
    private(set) var x = 0
    private(set) var y = 0

    var hint: String { "links/rechts bewegen · hoch oder B drehen · runter soft drop · A hard drop" }

    init(rng: GameRNG = GameRNG(), clock: @escaping () -> Double = monotonicNow) {
        self.rng = rng
        self.clock = clock
        reset()
    }

    func reset() {
        board = Array(repeating: Array(repeating: nil, count: Tetris.cols), count: Tetris.rows)
        bag = []
        score = 0
        lines = 0
        over = false
        banners.clear()
        nextKind = draw()
        spawn()
    }

    private func draw() -> String {
        if bag.isEmpty { bag = rng.shuffled(Tetris.kinds) }
        return bag.removeLast()
    }

    private func spawn() {
        kind = nextKind
        nextKind = draw()
        rot = 0
        let piece = Tetris.pieces[kind]!
        x = (Tetris.cols - piece.n) / 2
        y = -(piece.cells.map { $0.1 }.min() ?? 0)
        if collides(kind, rot, x, y) { gameOver() }
    }

    var level: Int { lines / 10 + 1 }
    var tick: Double { max(0.08, 0.7 * pow(0.85, Double(level - 1))) }

    func status() -> String {
        "score \(score)   lines \(lines)   level \(level)" + (over ? "   GAME OVER" : "")
    }

    // MARK: geometrie

    func cellsOf(_ kind: String, _ rot: Int, _ x: Int, _ y: Int) -> [(Int, Int)] {
        Tetris.rotated(kind, rot).map { (x + $0.0, y + $0.1) }
    }

    func collides(_ kind: String, _ rot: Int, _ x: Int, _ y: Int) -> Bool {
        for (cx, cy) in cellsOf(kind, rot, x, y) {
            if cx < 0 || cx >= Tetris.cols || cy >= Tetris.rows { return true }
            if cy >= 0 && board[cy][cx] != nil { return true }
        }
        return false
    }

    @discardableResult
    private func tryMove(_ nrot: Int, _ nx: Int, _ ny: Int) -> Bool {
        if collides(kind, nrot, nx, ny) { return false }
        rot = nrot; x = nx; y = ny
        return true
    }

    private func gameOver() {
        over = true
        let base = compose(active: false)
        var seq: [(frame: Frame, secs: Double)] = []
        for k in 1...Tetris.rows {          // rot wischt von unten nach oben
            var f = base
            for r in (Tetris.rows - k)..<Tetris.rows {
                for c in 0..<Tetris.cols { f[(Tetris.fieldY + r) * W + Tetris.fieldX + c] = 0 }
            }
            seq.append((f, 0.05))
        }
        seq.append((gameOverText(), .infinity))
        banners.set(seq)
    }

    // MARK: eingabe

    func key(_ key: Key) {
        if over || banners.current(now: clock()) != nil { return }
        switch key {
        case .left: tryMove(rot, x - 1, y)
        case .right: tryMove(rot, x + 1, y)
        case .down:
            if tryMove(rot, x, y + 1) { score += 1 }
        case .up, .rotate, .rotateCCW:
            let new = (rot + (key == .rotateCCW ? 3 : 1)) % 4
            for (dx, dy) in Tetris.kicks where tryMove(new, x + dx, y + dy) { break }
        case .space:
            var dist = 0
            while tryMove(rot, x, y + 1) { dist += 1 }
            score += 2 * dist
            lock()
        case .enter:
            break
        }
    }

    func step() {
        if over || banners.current(now: clock()) != nil { return }
        if !tryMove(rot, x, y + 1) { lock() }
    }

    private func lock() {
        let color = Tetris.pieces[kind]!.color
        for (cx, cy) in cellsOf(kind, rot, x, y) {
            if cy < 0 {
                gameOver()
                return
            }
            board[cy][cx] = color
        }
        let full = (0..<Tetris.rows).filter { r in board[r].allSatisfy { $0 != nil } }
        for r in full {   // aufsteigend wie im original: die zeilen darueber rutschen je einmal nach
            board.remove(at: r)
            board.insert(Array(repeating: nil, count: Tetris.cols), at: 0)
        }
        lines += full.count
        score += Tetris.linePoints[full.count] * level
        spawn()
    }

    // MARK: darstellung

    func compose(active: Bool = true) -> Frame {
        var f = blankWithBorder()
        for yy in 1..<(H - 1) { f[yy * W + Tetris.dividerX] = Px.white }
        for r in 0..<Tetris.rows {
            for c in 0..<Tetris.cols {
                if let v = board[r][c] { f[(Tetris.fieldY + r) * W + Tetris.fieldX + c] = v }
            }
        }
        if active {
            let color = Tetris.pieces[kind]!.color
            for (cx, cy) in cellsOf(kind, rot, x, y) where cy >= 0 {
                f[(Tetris.fieldY + cy) * W + Tetris.fieldX + cx] = color
            }
        }
        // naechster stein, zentriert im 7 breiten panel
        let cells = Tetris.rotated(nextKind, 0)
        let minx = cells.map { $0.0 }.min() ?? 0, maxx = cells.map { $0.0 }.max() ?? 0
        let miny = cells.map { $0.1 }.min() ?? 0
        let px = Tetris.panelX + (7 - (maxx - minx + 1)) / 2 - minx
        let ncolor = Tetris.pieces[nextKind]!.color
        for (cx, cy) in cells { f[(2 + cy - miny) * W + px + cx] = ncolor }
        // level-ziffer
        if let digit = String(min(level, 9)).first { Glyphs.draw(digit, into: &f, x: 14, y: 9, color: 30) }
        return f
    }

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        return compose()
    }
}
