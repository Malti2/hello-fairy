import Foundation

// Mario fuer den 20x20 vorhang. Mario ist 2 pixel gross (3 mit pilz), kamera folgt nach rechts.
// Vier generierte level (je mit fahnenmast, schloss, feuerwerk), dann ein Bowser-level, danach wieder von vorn.

enum Mar {
    static let groundY = 18
    static let stand = groundY - 1
    static let blockRow = 14
    static let jumpVY = [-2, -1, -1]
    static let camTrigger = 9
    static let moveCooldown = 2
    static let airCooldown = 1

    // tile ids
    static let empty = 0, ground = 1, pipe = 2, qblock = 3, used = 4, pole = 5, castle = 6, flag = 7
    static let solid: Set<Int> = [ground, pipe, qblock, used]
    static let tileColor: [Int: UInt8] = [ground: 15, pipe: 60, qblock: 30, used: 15, pole: 255, castle: 255, flag: 0]

    static let cMario: UInt8 = 0, cFireHead: UInt8 = 255
    static let cGoomba: UInt8 = 140, cKoopa: UInt8 = 90, cShell: UInt8 = 120
    static let cMushroom: UInt8 = 165, cFlower: UInt8 = 45, cFireball: UInt8 = 255
    static let cBowser: UInt8 = 60, cFlame: UInt8 = 30, cBossHit: UInt8 = 255, cBossHP: UInt8 = 165
}

// MARK: level

final class Level {
    var width: Int
    var cols: [[Int]]
    var contents: [Cell: String] = [:]
    var spawns: [(kind: String, x: Int, y: Int)] = []
    var poleX = -1
    var castleX = -1
    var boss = false

    init(width: Int, cols: [[Int]], boss: Bool = false) {
        self.width = width
        self.cols = cols
        self.boss = boss
    }

    var camMax: Int { max(0, width - W) }

    static func ground(_ width: Int) -> [[Int]] {
        (0..<width).map { _ in (0..<H).map { $0 >= Mar.groundY ? Mar.ground : Mar.empty } }
    }
}

@discardableResult
private func placeQBlocks(_ lvl: Level, x: Int, n: Int, rng: GameRNG, first: Bool = false) -> Int {
    for i in 0..<n {
        lvl.cols[x + i][Mar.blockRow] = Mar.qblock
        let content = (first && i == 0) ? "mushroom" : rng.weighted([("mushroom", 4), ("flower", 3), ("coin", 3)])
        lvl.contents[Cell(x: x + i, y: Mar.blockRow)] = content
    }
    return x + n
}

/// num 1-4 = normale level, 5 = Bowser.
/// regeln: die ersten 14 spalten sind flach und sicher; nach jedem hindernis mind. 4 spalten boden;
/// rohre 2 breit und 2-3 hoch (nicht betretbar); gruben 2 breit (ab schwierigkeit 3 auch 3), max eine pro 14 spalten;
/// ?-bloecke 3 reihen ueber dem boden; die ersten enthalten immer einen pilz; koopas ab schwierigkeit 2.
func generateLevel(num: Int, cycle: Int, rng: GameRNG) -> Level {
    if num == 5 {
        let lvl = Level(width: W, cols: Level.ground(W), boss: true)
        for x in [5, 6] {
            lvl.cols[x][Mar.blockRow] = Mar.qblock
            lvl.contents[Cell(x: x, y: Mar.blockRow)] = "flower"
        }
        lvl.spawns.append((kind: "boss", x: 15, y: 15))
        return lvl
    }
    let diff = cycle * 4 + num
    let length = min(150, 76 + 8 * diff)
    let lvl = Level(width: length + 16, cols: Level.ground(length + 16))
    var x = placeQBlocks(lvl, x: 14, n: 1, rng: rng, first: true) + 6
    var lastPitEnd = -99
    while x < length - 8 {
        var options: [(String, Int)] = [("goomba", 3), ("qblock", 3), ("pipe", 3)]
        if diff >= 2 { options.append(("koopa", 2)) }
        if x - lastPitEnd >= 14 { options.append(("pit", 2)) }
        let kind = rng.weighted(options)
        var end: Int
        switch kind {
        case "pipe":
            let h = rng.choice([2, 3])
            for dx in 0..<2 {
                for y in (Mar.groundY - h)..<Mar.groundY { lvl.cols[x + dx][y] = Mar.pipe }
            }
            end = x + 2
        case "pit":
            let w = diff >= 3 ? rng.choice([2, 3]) : 2
            for dx in 0..<w {
                lvl.cols[x + dx][Mar.groundY] = Mar.empty
                lvl.cols[x + dx][Mar.groundY + 1] = Mar.empty
            }
            lastPitEnd = x + w
            end = lastPitEnd
        case "goomba":
            let n = rng.int(1...(1 + diff / 4))
            for i in 0..<n { lvl.spawns.append((kind: "goomba", x: x + 3 * i, y: Mar.stand)) }
            end = x + 3 * n
        case "koopa":
            lvl.spawns.append((kind: "koopa", x: x, y: Mar.stand))
            end = x + 1
        default:
            end = placeQBlocks(lvl, x: x, n: rng.int(1...3), rng: rng)
        }
        x = end + rng.int(max(4, 8 - diff / 3)...9)
    }
    for i in 0..<4 {                                   // treppe
        for y in (Mar.stand - i)..<Mar.groundY { lvl.cols[length + i][y] = Mar.ground }
    }
    lvl.poleX = length + 5
    for y in 9..<Mar.groundY { lvl.cols[lvl.poleX][y] = Mar.pole }
    lvl.cols[lvl.poleX - 1][9] = Mar.flag
    lvl.castleX = length + 8
    for dx in 0..<5 {
        for y in 14..<Mar.groundY { lvl.cols[lvl.castleX + dx][y] = Mar.castle }
        if dx % 2 == 0 { lvl.cols[lvl.castleX + dx][13] = Mar.castle }
    }
    for y in [16, 17] { lvl.cols[lvl.castleX + 2][y] = Mar.empty }   // tuer
    return lvl
}

// MARK: entities

final class Enemy {
    var kind: String          // goomba | koopa | shell
    var x: Int
    var y: Int
    var vx = -1
    var timer = 0
    var active = false
    var grace = 0
    init(_ kind: String, _ x: Int, _ y: Int) { self.kind = kind; self.x = x; self.y = y }
}

final class Item {
    var kind: String          // mushroom | flower
    var x: Int
    var y: Int
    var vx = 1
    var timer = 0
    init(_ kind: String, _ x: Int, _ y: Int) { self.kind = kind; self.x = x; self.y = y }
}

final class Fireball {
    var x: Int
    var y: Int
    var age = 0
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

final class Flame {
    var x: Int
    var y: Int
    var timer = 0
    init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

final class Boss {
    var x: Int
    var y: Int
    var hp: Int
    var dir = -1
    var timer = 0
    var flash = 0
    init(_ x: Int, _ y: Int, hp: Int) { self.x = x; self.y = y; self.hp = hp }
}

struct Burst {
    var x: Int
    var y: Int
    var age: Int
    var hue: UInt8
}

// MARK: das spiel

final class Mario: CurtainApp {
    let rng: GameRNG
    let clock: () -> Double

    var tick: Double { 0.1 }
    var hint: String { "links/rechts laufen · A springen · B feuerball" }

    var cycle = 0, num = 1, lives = 3, score = 0, power = 0
    private(set) var over = false
    private var seeds: [Int: UInt64] = [:]
    var banners = BannerQueue()

    private(set) var lvl: Level = Level(width: W, cols: Level.ground(W))
    var cam = 0, t = 0, vy = 0, invuln = 0, cd = 0, airDir = 0
    var jumpI: Int?
    var hdir = 0, hdirAge = 99
    var phase = "play"
    var movedDown = false
    var hidden = false
    var enemies: [Enemy] = []
    var items: [Item] = []
    var fireballs: [Fireball] = []
    var flames: [Flame] = []
    var bursts: [Burst] = []
    var boss: Boss?
    var mx = 3, my = 0
    var deadT = 0
    var clearT = 0

    init(rng: GameRNG = GameRNG(), clock: @escaping () -> Double = monotonicNow) {
        self.rng = rng
        self.clock = clock
        reset()
    }

    func reset() {
        cycle = 0; num = 1; lives = 3; score = 0; power = 0
        over = false
        seeds = [:]
        banners.clear()
        loadLevel()
    }

    var h: Int { power == 0 ? 2 : 3 }

    private func levelForCurrent() -> Level {
        let key = cycle * 10 + num
        let seed: UInt64
        if let s = seeds[key] { seed = s } else {
            seed = rng.next() >> 34
            seeds[key] = seed
        }
        return generateLevel(num: num, cycle: cycle, rng: GameRNG(seed: seed))   // gleiches layout beim retry
    }

    func loadLevel(_ custom: Level? = nil, banner: Bool = true) {
        lvl = custom ?? levelForCurrent()
        cam = 0; t = 0; vy = 0; invuln = 0; cd = 0; airDir = 0
        jumpI = nil
        hdir = 0; hdirAge = 99
        phase = "play"
        movedDown = false
        hidden = false
        enemies = []; items = []; fireballs = []; flames = []; bursts = []
        boss = nil
        if lvl.boss { power = 2 }          // Bowser braucht feuerbaelle
        mx = lvl.boss ? 2 : 3
        my = Mar.stand - (h - 1)
        for s in lvl.spawns {
            if s.kind == "boss" { boss = Boss(s.x, s.y, hp: min(12, 5 + 2 * cycle)) }
            else { enemies.append(Enemy(s.kind, s.x, s.y)) }
        }
        if banner {
            let label = lvl.boss ? "BOSS" : "\(cycle + 1)-\(num)"
            banners.set([(textFrame(label, color: 30), 1.0)])
        }
    }

    func status() -> String {
        let world = lvl.boss ? "BOSS" : "\(cycle + 1)-\(num)"
        let extra = boss.map { "  bowser hp \($0.hp)" } ?? ""
        return "world \(world)  score \(score)  leben \(lives)  \(["klein", "gross", "feuer"][power])\(extra)"
            + (over ? "  GAME OVER" : "")
    }

    // MARK: welt

    func solid(_ x: Int, _ y: Int) -> Bool {
        if x >= lvl.width { return true }
        if x < 0 || y < 0 || y >= H { return false }
        return Mar.solid.contains(lvl.cols[x][y])
    }

    func collide(_ x: Int, _ yTop: Int, _ h: Int) -> Bool {
        (yTop..<(yTop + h)).contains { solid(x, $0) }
    }

    func onGround() -> Bool { solid(mx, my + h) }

    private func hits(_ x: Int, _ y: Int, w: Int = 1, h: Int = 1) -> Bool {
        x <= mx && mx < x + w && y < my + self.h && y + h > my
    }

    // MARK: eingabe

    func key(_ key: Key) {
        if over || phase != "play" || banners.current(now: clock()) != nil { return }
        switch key {
        case .left, .right:
            let d = key == .left ? -1 : 1
            hdir = d; hdirAge = 0
            if !onGround() { airDir = d }
            if cd <= 0 && moveX(d) {
                cd = onGround() ? Mar.moveCooldown : Mar.airCooldown
                followCamera()
            }
        case .up, .space:
            if onGround() && vy >= 0 && jumpI == nil {
                jumpI = 0
                airDir = hdirAge <= 6 ? hdir : 0       // gehaltene richtung beim absprung behalten
            }
        case .rotate:
            if power == 2 && fireballs.count < 2 { fireballs.append(Fireball(mx + 1, my + h - 1)) }
        default:
            break
        }
    }

    // MARK: bewegung

    @discardableResult
    func moveX(_ dx: Int) -> Bool {
        let nx = mx + dx
        if !(0 <= nx - cam && nx - cam < W) { return false }
        if collide(nx, my, h) {
            // eine stufe hoch (treppe, kleine bloecke)
            if onGround() && !collide(nx, my - 1, h) && !solid(mx, my - 1) {
                mx = nx; my -= 1
                return true
            }
            return false
        }
        mx = nx
        return true
    }

    private func marioVertical() {
        movedDown = false
        if let ji = jumpI {
            vy = Mar.jumpVY[ji]
            jumpI = ji + 1
            if ji + 1 >= Mar.jumpVY.count { jumpI = nil }
        }
        let d = vy > 0 ? 1 : -1
        for _ in 0..<abs(vy) {
            let ny = my + d
            if collide(mx, ny, h) {
                if d < 0 { hitBlock(mx, ny) }
                vy = 0
                jumpI = nil
                break
            }
            my = ny
            if d > 0 { movedDown = true }
        }
        if jumpI == nil { vy = min(2, vy + 1) }
        if vy > 0 && onGround() {
            vy = 0
            airDir = 0
        }
    }

    private func hitBlock(_ x: Int, _ y: Int) {
        guard 0 <= x, x < lvl.width, 0 <= y, y < H, lvl.cols[x][y] == Mar.qblock else { return }
        lvl.cols[x][y] = Mar.used
        let content = lvl.contents.removeValue(forKey: Cell(x: x, y: y)) ?? "coin"
        for e in enemies where e.x == x && e.y == y - 1 {      // gegner auf dem block fliegen runter
            enemies.removeAll { $0 === e }
            score += 100
        }
        if content == "coin" {
            score += 200
        } else if !solid(x, y - 1) {
            let kind = (content == "mushroom" || power == 0) ? "mushroom" : "flower"
            items.append(Item(kind, x, y - 1))
        }
    }

    private func followCamera() {
        if !lvl.boss {
            let target = min(lvl.camMax, mx - Mar.camTrigger)
            if target > cam { cam = target }       // scrollt nie zurueck wie im original
        }
    }

    private func grow(to: Int) {
        if power == 0 && to >= 1 {
            if solid(mx, my - 1) { return }
            my -= 1
        }
        power = max(power, to)
    }

    private func hurt() {
        if invuln > 0 || phase != "play" { return }
        if power > 0 {
            power = 0
            my += 1
            invuln = 20
        } else {
            die()
        }
    }

    private func die() {
        if phase == "play" { phase = "dead"; deadT = 0 }
    }

    // MARK: tick

    func step() {
        if over || banners.current(now: clock()) != nil { return }
        t += 1
        switch phase {
        case "play": playTick()
        case "dead": deadTick()
        default: clearTick()
        }
    }

    private func playTick() {
        invuln = max(0, invuln - 1)
        cd = max(0, cd - 1)
        hdirAge += 1
        if airDir != 0 && !onGround() && cd <= 0 {
            if moveX(airDir) {
                cd = Mar.airCooldown
                followCamera()
            } else {
                airDir = 0
            }
        }
        marioVertical()
        updateEnemies()
        updateItems()
        updateFireballs()
        updateBoss()
        contacts()
        if phase != "play" { return }
        if my >= H { die(); return }
        if !lvl.boss && mx >= lvl.poleX { startClear() }
    }

    private func updateEnemies() {
        for e in enemies {
            if !e.active {
                if e.x - cam <= W + 1 { e.active = true } else { continue }
            }
            if e.x < cam - 2 {
                enemies.removeAll { $0 === e }
                continue
            }
            e.grace = max(0, e.grace - 1)
            if !solid(e.x, e.y + 1) {
                e.y += 1
                if e.y >= H { enemies.removeAll { $0 === e } }
                continue
            }
            e.timer += 1
            let period = (e.kind == "shell" && e.vx != 0) ? 1 : 4
            if e.vx != 0 && e.timer % period == 0 {
                if solid(e.x + e.vx, e.y) { e.vx = -e.vx } else { e.x += e.vx }
            }
            if e.kind == "shell" && e.vx != 0 {         // rutschender panzer maeht andere um
                for o in enemies where o !== e && o.x == e.x && o.y == e.y {
                    enemies.removeAll { $0 === o }
                    score += 200
                }
            }
        }
    }

    private func updateItems() {
        for it in items {
            if it.x < cam - 2 {
                items.removeAll { $0 === it }
                continue
            }
            if !solid(it.x, it.y + 1) {
                it.y += 1
                if it.y >= H { items.removeAll { $0 === it } }
                continue
            }
            it.timer += 1
            if it.kind == "mushroom" && it.timer % 4 == 0 {
                if solid(it.x + it.vx, it.y) { it.vx = -it.vx } else { it.x += it.vx }
            }
        }
    }

    private func updateFireballs() {
        for fb in fireballs {
            fb.age += 1
            var gone = fb.age > 12
            for _ in 0..<2 {
                let nx = fb.x + 1
                if gone || nx >= cam + W || solid(nx, fb.y) {
                    gone = true
                    break
                }
                fb.x = nx
                if fireballHit(fb) {
                    gone = true
                    break
                }
            }
            if !gone && !solid(fb.x, fb.y + 1) {
                fb.y += 1
                gone = fb.y >= H
            }
            if gone { fireballs.removeAll { $0 === fb } }
        }
    }

    private func fireballHit(_ fb: Fireball) -> Bool {
        for e in enemies where e.x == fb.x && e.y == fb.y {
            enemies.removeAll { $0 === e }
            score += 100
            return true
        }
        if let b = boss, b.x <= fb.x, fb.x < b.x + 3, b.y <= fb.y, fb.y < b.y + 3 {
            b.hp -= 1
            b.flash = 3
            score += 200
            if b.hp <= 0 {
                score += 3000
                boss = nil
                startClear()
            }
            return true
        }
        return false
    }

    private func updateBoss() {
        if let b = boss {
            b.timer += 1
            b.flash = max(0, b.flash - 1)
            if b.timer % 6 == 0 {
                if b.x <= 11 { b.dir = 1 } else if b.x >= 17 { b.dir = -1 }
                b.x += b.dir
            }
            if b.timer % max(14, 30 - 3 * cycle) == 0 {
                flames.append(Flame(b.x - 1, rng.choice([17, 15])))
            }
        }
        for f in flames {
            f.timer += 1
            if f.timer % 2 == 0 { f.x -= 1 }
            if f.x < 0 { flames.removeAll { $0 === f } }
        }
    }

    private func contacts() {
        let feet = my + h - 1
        for e in enemies {
            if !hits(e.x, e.y) { continue }
            let stomping = (movedDown || vy > 0) && feet <= e.y
            if e.kind == "shell" {
                if e.grace != 0 { continue }
                if e.vx == 0 {
                    e.vx = mx <= e.x ? 1 : -1       // wegkicken
                    e.grace = 4
                } else if stomping {
                    e.vx = 0
                    e.grace = 4
                } else {
                    hurt()
                    continue
                }
                if stomping { vy = -2 }
            } else if stomping {
                score += e.kind == "goomba" ? 100 : 200
                vy = -2
                if e.kind == "koopa" {
                    e.kind = "shell"; e.vx = 0; e.grace = 4
                } else {
                    enemies.removeAll { $0 === e }
                }
            } else {
                hurt()
            }
        }
        for it in items where hits(it.x, it.y) {
            items.removeAll { $0 === it }
            score += 1000
            grow(to: it.kind == "mushroom" ? 1 : 2)
        }
        if let b = boss, hits(b.x, b.y, w: 3, h: 3) { hurt() }
        for f in flames where hits(f.x, f.y) { hurt() }
    }

    // MARK: tod / level geschafft

    private func deadTick() {
        deadT += 1
        my += deadT <= 3 ? -1 : 1
        if deadT >= 14 {
            lives -= 1
            power = 0
            if lives <= 0 {
                over = true
                banners.set([(gameOverText(), .infinity)])
            } else {
                loadLevel()
            }
        }
    }

    private func startClear() {
        phase = "clear"
        clearT = 0
        score += 1000
        flames.removeAll()
    }

    private func clearTick() {
        clearT += 1
        if clearT % 3 == 1 {
            let cx = lvl.boss ? W / 2 : (lvl.castleX + 2 - cam)
            let sx = max(2, min(W - 3, cx + rng.int(-4...4)))
            bursts.append(Burst(x: sx, y: rng.int(2...8), age: 0, hue: UInt8(rng.int(0...180))))
        }
        for i in bursts.indices { bursts[i].age += 1 }
        bursts = bursts.filter { $0.age < 8 }
        marioVertical()
        if !lvl.boss && clearT % 2 == 0 && !hidden {
            if mx >= lvl.castleX + 2 { hidden = true } else { moveX(1) }    // Mario geht ins schloss
        }
        if clearT >= 40 { nextLevel() }
    }

    private func nextLevel() {
        if num == 4 { num = 5 }                 // Bowser nach vier leveln
        else if num == 5 { cycle += 1; num = 1 }
        else { num += 1 }
        loadLevel()
    }

    // MARK: darstellung

    func frame() -> Frame {
        if let b = banners.current(now: clock()) { return b }
        var f = blankFrame()

        func put(_ sx: Int, _ y: Int, _ color: UInt8) {
            if 0 <= sx && sx < W && 0 <= y && y < H { f[y * W + sx] = color }
        }

        for sx in 0..<W {
            let x = cam + sx
            if x < lvl.width {
                let col = lvl.cols[x]
                for y in 0..<H where col[y] != 0 { f[y * W + sx] = Mar.tileColor[col[y]] ?? Px.off }
            }
        }
        for it in items { put(it.x - cam, it.y, it.kind == "mushroom" ? Mar.cMushroom : Mar.cFlower) }
        for e in enemies {
            let c: UInt8 = e.kind == "goomba" ? Mar.cGoomba : (e.kind == "koopa" ? Mar.cKoopa : Mar.cShell)
            put(e.x - cam, e.y, c)
        }
        if let bs = boss {
            for dx in 0..<3 { for dy in 0..<3 { put(bs.x + dx, bs.y + dy, bs.flash != 0 ? Mar.cBossHit : Mar.cBowser) } }
        }
        for fl in flames { put(fl.x, fl.y, Mar.cFlame) }
        for fb in fireballs { put(fb.x - cam, fb.y, Mar.cFireball) }
        if !hidden && !(invuln != 0 && t % 2 == 1) {
            let sx = mx - cam
            for i in 0..<h {
                let head = i == 0 && power == 2
                put(sx, my + i, head ? Mar.cFireHead : Mar.cMario)
            }
        }
        for b in bursts {
            let r = b.age / 2 + 1
            for (dx, dy) in [(r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)] {
                put(b.x + dx, b.y + dy, b.hue)
            }
            if b.age < 2 { put(b.x, b.y, Px.white) }
        }
        for i in 0..<lives { put(1 + 2 * i, 0, Mar.cMario) }       // HUD: leben oben links
        if let bs = boss {                                          // HUD: Bowser hp oben rechts
            for i in 0..<max(0, bs.hp) { put(W - 1 - i, 1, Mar.cBossHP) }
        }
        return f
    }
}
