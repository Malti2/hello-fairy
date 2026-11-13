import Foundation

/// breakout: schlaeger per finger, ball bleibt kleben bis du loslaesst
final class Breakout: CurtainApp {
    static let paddleLen = 4
    static let paddleY = 18
    static let rowColors: [UInt8] = [0, 15, 30, 60, 90, 120]
    static let cols = 18

    let rng: GameRNG
    let clock: () -> Double

    private(set) var bricks: [[UInt8?]] = []     // zeilen ab y = 2, spalten ab x = 1
    private(set) var px = 8                       // linke kante des schlaegers
    private(set) var bx = 9, by = 17
    private(set) var vx = 1, vy = -1
    private(set) var lives = 3
    private(set) var score = 0
    private(set) var level = 1
    private(set) var launched = false
    private(set) var over = false
    private var banners = BannerQueue()

    var tick: Double { max(0.05, 0.1 - 0.008 * Double(level - 1)) }
    var hint: String { "finger links/rechts bewegt den schlaeger · loslassen startet den ball" }

    init(rng: GameRNG = GameRNG(), clock: @escaping () -> Double = monotonicNow) {
        self.rng = rng
        self.clock = clock
        reset()
    }

    func reset() {
        lives = 3; score = 0; level = 1; over = false
        banners.clear()
        buildBricks()
        stick()
    }

    private func buildBricks() {
        let rows = min(Breakout.rowColors.count, 3 + level)
        bricks = (0..<rows).map { r in Array(repeating: Breakout.rowColors[r], count: Breakout.cols) }
    }

    private func stick() {
        launched = false
        vx = rng.choice([-1, 1])
        vy = -1
        bx = px + Breakout.paddleLen / 2
        by = Breakout.paddleY - 1
    }

    var bricksLeft: Int { bricks.reduce(0) { $0 + $1.filter { $0 != nil }.count } }

    func status() -> String {
        "level \(level)  score \(score)  leben \(lives)" + (over ? "  GAME OVER" : "")
    }

    func touch(x: Double, y: Double) {
        setPaddle(Int((x * Double(W)).rounded()) - Breakout.paddleLen / 2)
    }

    private func setPaddle(_ left: Int) {
        px = max(1, min(W - 1 - Breakout.paddleLen, left))
        if !launched { bx = px + Breakout.paddleLen / 2 }
    }

    func key(_ key: Key) {
        if over || banners.current(now: clock()) != nil { return }
        switch key {
        case .left: setPaddle(px - 1)
        case .right: setPaddle(px + 1)
        case .space, .enter, .up: launched = true
        default: break
        }
    }

    private func brick(_ x: Int, _ y: Int) -> Bool {
        let r = y - 2, c = x - 1
        return r >= 0 && r < bricks.count && c >= 0 && c < Breakout.cols && bricks[r][c] != nil
    }

    private func removeBrick(_ x: Int, _ y: Int) {
        bricks[y - 2][x - 1] = nil
        score += 10 * level
    }

    func step() {
        if over || banners.current(now: clock()) != nil { return }
        if !launched {
            bx = px + Breakout.paddleLen / 2
            return
        }
        var nx = bx + vx, ny = by + vy
        if nx < 1 || nx > W - 2 { vx = -vx; nx = bx + vx }
        if ny < 1 { vy = -vy; ny = by + vy }
        if brick(nx, ny) {
            removeBrick(nx, ny)
            vy = -vy
            ny = by + vy
            if ny < 1 { vy = 1; ny = by + 1 }
        } else if brick(nx, by) {          // seitlich in einen stein
            removeBrick(nx, by)
            vx = -vx
            nx = bx + vx
        }
        if ny == Breakout.paddleY && vy > 0 {
            let off = nx - px
            let hit = (0..<Breakout.paddleLen).contains(off)
                || (off == -1 && vx > 0) || (off == Breakout.paddleLen && vx < 0)
            if hit {
                vy = -1
                if off <= 0 { vx = -1 } else if off >= Breakout.paddleLen - 1 { vx = 1 }
                ny = by + vy
            }
        }
        bx = max(1, min(W - 2, nx))
        by = ny
        if by >= Breakout.paddleY + 1 { loseLife(); return }
        if bricksLeft == 0 { nextLevel() }
    }

    private func loseLife() {
        lives -= 1
        if lives <= 0 {
            over = true
            banners.set([(textFrame("\(score)", color: 30), 1.5), (gameOverText(), .infinity)])
        } else {
            stick()
        }
    }

    private func nextLevel() {
        level += 1
        banners.set([(textFrame("L\(level)", color: 30), 1.0)])
        buildBricks()
        stick()
    }

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        var f = blankFrame()
        for i in 0..<W { f[i] = Px.white }                     // decke + seitenwaende
        for y in 0..<H { f[y * W] = Px.white; f[y * W + W - 1] = Px.white }
        for (r, row) in bricks.enumerated() {
            for (c, v) in row.enumerated() { if let v { f[(2 + r) * W + 1 + c] = v } }
        }
        for i in 0..<Breakout.paddleLen { f[Breakout.paddleY * W + px + i] = 60 }
        if (0..<H).contains(by), (0..<W).contains(bx) { f[by * W + bx] = Px.white }
        for i in 0..<lives { f[(H - 1) * W + 1 + 2 * i] = 0 }
        return f
    }
}
