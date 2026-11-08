import XCTest
@testable import FairyLogic

final class MarioTests: XCTestCase {
    func newGame(_ lvl: Level? = nil, seed: UInt64 = 1) -> Mario {
        let g = Mario(rng: GameRNG(seed: seed), clock: { 0 })
        g.loadLevel(lvl ?? flat(), banner: false)
        g.banners.clear()
        return g
    }

    func flat(_ width: Int = 60) -> Level {
        let l = Level(width: width, cols: Level.ground(width))
        l.poleX = width - 4
        l.castleX = width - 8
        return l
    }

    // MARK: generator

    func testGeneratorRules() {
        for cycle in [0, 1, 3] {
            for num in 1...4 {
                for seed in 0..<15 {
                    let lvl = generateLevel(num: num, cycle: cycle, rng: GameRNG(seed: UInt64(seed)))
                    XCTAssertEqual(lvl.cols.count, lvl.width)
                    XCTAssertTrue(lvl.cols.allSatisfy { $0.count == 20 })
                    // sicherer flacher start
                    for x in 0..<14 {
                        XCTAssertEqual(lvl.cols[x][Mar.groundY], Mar.ground)
                        XCTAssertTrue(lvl.cols[x][0..<Mar.groundY].allSatisfy { $0 == 0 })
                    }
                    let pits = (0..<lvl.width).filter { lvl.cols[$0][Mar.groundY] != Mar.ground }
                    var runs: [[Int]] = []
                    var cur: [Int] = []
                    for x in pits {
                        if let last = cur.last, x != last + 1 { runs.append(cur); cur = [] }
                        cur.append(x)
                    }
                    if !cur.isEmpty { runs.append(cur) }
                    XCTAssertTrue(runs.allSatisfy { $0.count <= 3 }, "pit breite \(num) \(cycle) \(seed)")
                    XCTAssertTrue(runs.allSatisfy { $0.last! < lvl.poleX - 8 })
                    // rohre: 2-3 hoch, mind. 4 spalten von jeder grube weg
                    let pipeCols = (0..<lvl.width).filter { lvl.cols[$0][Mar.stand] == Mar.pipe }
                    for x in pipeCols {
                        let h = (0..<20).filter { lvl.cols[x][$0] == Mar.pipe }.count
                        XCTAssertTrue(h == 2 || h == 3)
                        XCTAssertTrue(pits.allSatisfy { abs(x - $0) >= 4 }, "rohr nah an grube \(num) \(cycle) \(seed)")
                    }
                    // die erste ?-box hat einen pilz
                    XCTAssertEqual(lvl.contents[Cell(x: 14, y: Mar.blockRow)], "mushroom")
                }
            }
        }
    }

    func testBossLevel() {
        let lvl = generateLevel(num: 5, cycle: 0, rng: GameRNG(seed: 1))
        XCTAssertTrue(lvl.boss)
        XCTAssertEqual(lvl.width, W)
        XCTAssertTrue(lvl.spawns.contains { $0.kind == "boss" })
    }

    // MARK: physik

    func testWalkAndJump() {
        let g = newGame()
        let x0 = g.mx
        g.key(.right)
        XCTAssertEqual(g.mx, x0 + 1)
        let y0 = g.my
        g.key(.up)
        g.step()
        XCTAssertLessThan(g.my, y0)
        for _ in 0..<20 { g.step() }
        XCTAssertEqual(g.my, y0)            // wieder gelandet
    }

    func testFallsIntoPitAndDies() {
        let l = flat()
        for dx in 0..<3 { l.cols[6 + dx][Mar.groundY] = 0; l.cols[6 + dx][Mar.groundY + 1] = 0 }
        let g = newGame(l)
        var died = false
        for _ in 0..<60 {
            g.key(.right)
            g.step()
            if g.phase == "dead" { died = true; break }
        }
        XCTAssertTrue(died)
    }

    func testMushroomMakesMarioBig() {
        let g = newGame()
        g.items.append(Item("mushroom", g.mx, g.my))
        g.step()
        XCTAssertEqual(g.power, 1)
        XCTAssertEqual(g.h, 3)
    }

    func testStompGoomba() {
        let g = newGame()
        let e = Enemy("goomba", g.mx + 1, Mar.stand)
        e.active = true
        g.enemies = [e]
        g.my = Mar.stand - 2
        g.vy = 1
        g.mx = e.x
        g.step()
        XCTAssertTrue(g.enemies.isEmpty)
        XCTAssertGreaterThanOrEqual(g.score, 100)
    }

    func testHurtShrinksBeforeDeath() {
        let g = newGame()
        g.items.append(Item("mushroom", g.mx, g.my))
        g.step()
        XCTAssertEqual(g.power, 1)
        let e = Enemy("goomba", g.mx, Mar.stand)
        e.active = true
        g.enemies = [e]
        g.step()
        XCTAssertEqual(g.power, 0)
        XCTAssertEqual(g.phase, "play")
    }

    func testFrameShapeAndHud() {
        let g = newGame()
        let f = g.frame()
        XCTAssertEqual(f.count, 400)
        XCTAssertEqual(f[0 * W + 1], Mar.cMario)         // leben links oben
        XCTAssertTrue(f.allSatisfy { Proto.isValidColor($0) })
    }

    func testLevelClearAdvances() {
        let g = newGame()
        g.mx = g.lvl.poleX
        g.step()
        XCTAssertEqual(g.phase, "clear")
        for _ in 0..<60 { g.step() }
        XCTAssertEqual(g.num, 2)
        XCTAssertEqual(g.phase, "play")
    }

    func testGameOverWhenLastLifeIsLost() {
        let l = flat()
        for x in 5..<60 { l.cols[x][Mar.groundY] = 0; l.cols[x][Mar.groundY + 1] = 0 }
        let g = newGame(l)
        g.lives = 1
        var n = 0
        while !g.over && n < 500 {
            g.key(.right)
            g.step()
            n += 1
        }
        XCTAssertTrue(g.over)
        XCTAssertEqual(g.lives, 0)
    }

    // MARK: bot

    final class BotClock { var t = 0.0 }

    func playLevel(num: Int, cycle: Int, seed: UInt64, enemies: Bool = true, maxTicks: Int = 4000) -> String {
        let g = Mario(rng: GameRNG(seed: seed), clock: { 0 })
        let lvl = generateLevel(num: num, cycle: cycle, rng: GameRNG(seed: seed))
        if !enemies { lvl.spawns = [] }
        g.loadLevel(lvl, banner: false)
        g.banners.clear()
        for _ in 0..<maxTicks {
            if g.phase == "clear" { return "cleared" }
            if g.phase != "play" { return "dead" }
            let feet = g.my + g.h - 1
            let wall = [1, 2].contains { g.solid(g.mx + $0, feet) }
            let pit = [1, 2].contains { !g.solid(g.mx + $0, Mar.groundY) && g.mx + $0 < g.lvl.width }
            let foe = g.enemies.contains { $0.active && $0.y == feet && 0 < $0.x - g.mx && $0.x - g.mx <= 3 }
            g.key(.right)
            if g.onGround() && (wall || pit || foe) { g.key(.up) }
            g.step()
        }
        return "timeout"
    }

    func testObstacleOnlyLevelsAlwaysBeatable() {
        for cycle in 0..<3 {
            for num in 1...4 {
                for seed in 0..<12 {
                    XCTAssertEqual(playLevel(num: num, cycle: cycle, seed: UInt64(seed), enemies: false), "cleared",
                                   "level \(num) cycle \(cycle) seed \(seed)")
                }
            }
        }
    }

    func testLevelsWithEnemiesMostlyBeatableByDumbBot() {
        var wins = 0
        for n in 1...2 { for s in 0..<20 where playLevel(num: n, cycle: 0, seed: UInt64(s)) == "cleared" { wins += 1 } }
        XCTAssertGreaterThanOrEqual(wins, 28, "of 40: \(wins)")
    }
}
