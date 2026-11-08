import Foundation

/// pong gegen die ai. du bist links (gruen), die ai rechts (rot)
final class Pong: CurtainApp {
    static let playerColor: UInt8 = 60, aiColor: UInt8 = 0, ballColor: UInt8 = 30
    static let playerX = 1, aiX = 18
    static let paddleLen = 4
    static let maxPY = H - 1 - paddleLen
    static let difficulty: [String: Double] = ["easy": 0.45, "normal": 0.72, "hard": 0.9]

    let points: Int
    let skill: Double
    let baseTick: Double
    let rng: GameRNG
    let clock: () -> Double

    private(set) var score = [0, 0]      // spieler, ai
    private(set) var over = false
    private var banners = BannerQueue()
    private(set) var py = 8, ay = 8
    private(set) var bx = 10, by = 10
    private(set) var vx = 1, vy = 0
    private(set) var rally = 0
    private var aim = 0

    var hint: String { "d-pad hoch/runter bewegt den schlaeger" }

    init(points: Int = 5, difficulty: String = "normal", tick: Double = 0.14, rng: GameRNG = GameRNG(),
         clock: @escaping () -> Double = monotonicNow) {
        self.points = points
        self.skill = Pong.difficulty[difficulty] ?? 0.72
        self.baseTick = tick
        self.rng = rng
        self.clock = clock
        reset()
    }

    func reset() {
        score = [0, 0]
        over = false
        banners.clear()
        serve(rng.choice([-1, 1]))
    }

    func serve(_ direction: Int) {
        py = (H - Pong.paddleLen) / 2
        ay = py
        bx = W / 2
        by = rng.int(5...14)
        vx = direction
        vy = rng.choice([-1, 0, 1])
        rally = 0
        aim = 0
    }

    var tick: Double { max(0.06, baseTick - 0.006 * Double(rally)) }

    func status() -> String { "du \(score[0]) : \(score[1]) ai   (first to \(points))" }

    func key(_ key: Key) {
        if key == .up { py = max(1, py - 1) }
        else if key == .down { py = min(Pong.maxPY, py + 1) }
    }

    private func predictY() -> Int {
        var x = bx, y = by, vy = self.vy
        while x < Pong.aiX - 1 {
            x += 1
            y += vy
            if y < 1 || y > H - 2 {
                vy = -vy
                y += 2 * vy
            }
        }
        return y
    }

    private func aiMove() {
        let target: Int
        if vx > 0 && bx >= 6 { target = predictY() + aim } else { target = (H - 1) / 2 }
        let raw = (Double(target) - Double(Pong.paddleLen - 1) / 2).rounded(.toNearestOrEven)
        let want = max(1, min(Pong.maxPY, Int(raw)))
        if want != ay && rng.double() < skill { ay += want > ay ? 1 : -1 }
    }

    func step() {
        if over || banners.current(now: clock()) != nil { return }
        aiMove()
        let nx = bx + vx
        var ny = by + vy
        if ny < 1 || ny > H - 2 {
            vy = -vy
            ny = by + vy
        }
        for (xPad, top, isPlayer) in [(Pong.playerX, py, true), (Pong.aiX, ay, false)] {
            if nx == xPad, top <= ny, ny < top + Pong.paddleLen, (vx < 0) == isPlayer {
                let off = ny - top
                if off == 0 { vy = -1 }
                else if off == Pong.paddleLen - 1 { vy = 1 }
                else if vy == 0 { vy = rng.double() < 0.3 ? rng.choice([-1, 1]) : 0 }
                vx = -vx
                rally += 1
                if isPlayer { aim = rng.choice([-1, 0, 0, 1, 2]) }
                by = ny
                return
            }
        }
        bx = nx
        by = ny
        if nx <= 0 { point(1) } else if nx >= W - 1 { point(0) }
    }

    private func point(_ scorer: Int) {
        score[scorer] += 1
        if score[scorer] >= points {
            over = true
            let win = scorer == 0
            banners.set([
                (textFrame("\(score[0]):\(score[1])", color: Pong.ballColor), 1.2),
                (textFrame(win ? "WIN" : "LOSE", color: win ? Pong.playerColor : Pong.aiColor), .infinity),
            ])
        } else {
            banners.set([(textFrame("\(score[0]):\(score[1])", color: Pong.ballColor), 1.0)])
            serve(scorer == 0 ? 1 : -1)
        }
    }

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        var f = blankWithBorder()
        for i in 0..<Pong.paddleLen {
            f[(py + i) * W + Pong.playerX] = Pong.playerColor
            f[(ay + i) * W + Pong.aiX] = Pong.aiColor
        }
        if (1...(W - 2)).contains(bx), f[by * W + bx] == Px.off { f[by * W + bx] = Pong.ballColor }
        return f
    }
}
