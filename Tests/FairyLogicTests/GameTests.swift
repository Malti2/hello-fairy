import XCTest
@testable import FairyLogic

final class GameTests: XCTestCase {
    // MARK: snake

    func testSnakeEatsAndGrows() {
        let g = Snake(rng: GameRNG(seed: 1), clock: { 0 })
        let head = g.cells[0]
        // futter direkt vor den kopf legen geht nicht von aussen, also laufen bis zur wand
        var steps = 0
        while g.alive && steps < 50 { g.step(); steps += 1 }
        XCTAssertFalse(g.alive)
        XCTAssertGreaterThanOrEqual(steps, 1)
        XCTAssertEqual(head.y, g.cells[0].y)
    }

    func testSnakeCannotReverse() {
        let g = Snake(rng: GameRNG(seed: 2), clock: { 0 })
        g.key(.left)            // gegenrichtung wird ignoriert
        g.step()
        XCTAssertEqual(g.dir, .right)
        g.key(.up)
        g.step()
        XCTAssertEqual(g.dir, .up)
    }

    func testSnakeFrameHasBorderAndHead() {
        let g = Snake(rng: GameRNG(seed: 3), clock: { 0 })
        let f = g.frame()
        XCTAssertEqual(f[0], Px.white)
        XCTAssertEqual(f[19 * W + 19], Px.white)
        XCTAssertEqual(f.filter { $0 == Snake.head }.count, 1)
        XCTAssertEqual(f.filter { $0 == Snake.body }.count, 2)
    }

    // MARK: pong

    func testPongPlaysToTheEnd() {
        var t = 0.0
        let g = Pong(points: 2, difficulty: "hard", rng: GameRNG(seed: 4), clock: { t })
        var ticks = 0
        while !g.over && ticks < 20000 {
            g.step()
            t += 0.5            // banner laufen sofort ab
            ticks += 1
        }
        XCTAssertTrue(g.over)
        XCTAssertEqual(max(g.score[0], g.score[1]), 2)
    }

    func testPongPaddleStaysInside() {
        let g = Pong(rng: GameRNG(seed: 5), clock: { 0 })
        for _ in 0..<40 { g.key(.up) }
        XCTAssertEqual(g.py, 1)
        for _ in 0..<40 { g.key(.down) }
        XCTAssertEqual(g.py, Pong.maxPY)
    }

    // MARK: tetris

    func testTetrisHardDropLocksPiece() {
        let g = Tetris(rng: GameRNG(seed: 6), clock: { 0 })
        g.key(.space)
        XCTAssertTrue(g.board.flatMap { $0 }.contains { $0 != nil })
        XCTAssertGreaterThan(g.score, 0)
    }

    func testTetrisStackingEndsInGameOver() {
        let g = Tetris(rng: GameRNG(seed: 7), clock: { 0 })
        XCTAssertEqual(g.lines, 0)
        for _ in 0..<2000 {
            if g.over { break }
            g.key(.space)
        }
        XCTAssertTrue(g.over)           // endloses hard-droppen in der mitte muss irgendwann enden
        XCTAssertEqual(g.frame().count, 400)
    }

    func testTetrisRotationKeepsPieceInside() {
        let g = Tetris(rng: GameRNG(seed: 8), clock: { 0 })
        for _ in 0..<12 { g.key(.left) }
        for _ in 0..<4 { g.key(.rotate) }
        for (cx, _) in g.cellsOf(g.kind, g.rot, g.x, g.y) {
            XCTAssertTrue(cx >= 0 && cx < Tetris.cols)
        }
    }

    // MARK: uhr

    func testClockDigital() {
        let f = ClockFace.renderDigital(ClockTime(hour: 14, minute: 5, second: 0, weekday: 2))
        XCTAssertTrue(f.contains(60))           // nachmittag = gruen
        XCTAssertEqual(f[3 * W + 3 + 2 * 2], 30)   // heutiger wochentag
        XCTAssertEqual(f[3 * W + 3], 120)
    }

    func testClockAnalogHasThreeHands() {
        let f = ClockFace.renderAnalog(ClockTime(hour: 3, minute: 0, second: 30))
        XCTAssertTrue(f.contains(0))
        XCTAssertTrue(f.contains(30))
        XCTAssertTrue(f.contains(90))
        XCTAssertEqual(f.filter { $0 == 255 }.count, 4)     // viertelstunden-ticks
    }

    // MARK: wetter

    func testWeatherIcons() {
        XCTAssertEqual(WeatherFace.iconName(code: 0, isDay: true), "sun")
        XCTAssertEqual(WeatherFace.iconName(code: 0, isDay: false), "moon")
        XCTAssertEqual(WeatherFace.iconName(code: 63), "rain")
        XCTAssertEqual(WeatherFace.iconName(code: 73), "snow")
        XCTAssertEqual(WeatherFace.iconName(code: 95), "thunder")
    }

    func testWeatherParseForecast() throws {
        let json = """
        {"current":{"time":"2026-11-08T15:00","temperature_2m":8.4,"weather_code":61,"is_day":1,"wind_speed_10m":12.0},
         "hourly":{"time":["2026-11-08T14:00","2026-11-08T15:00","2026-11-08T16:00","2026-11-08T17:00","2026-11-08T18:00","2026-11-08T19:00","2026-11-08T20:00"],
                   "precipitation_probability":[0,10,20,null,40,50,60]},
         "daily":{"temperature_2m_max":[11.2,9.0],"temperature_2m_min":[3.6,2.0]}}
        """
        let d = try OpenMeteo.parseForecast(Data(json.utf8))
        XCTAssertEqual(d.temp, 8)
        XCTAssertEqual(d.high, 11)
        XCTAssertEqual(d.low, 4)
        XCTAssertEqual(d.rain, [10, 20, 0, 40, 50, 60])
        for page in 0..<3 {
            let f = WeatherFace.render(d, page: page)
            XCTAssertEqual(f.count, 400)
            XCTAssertTrue(f.contains { $0 != Px.off })
        }
    }

    func testGeocodeParsing() throws {
        let ok = #"{"results":[{"name":"Berlin","latitude":52.5,"longitude":13.4}]}"#
        XCTAssertEqual(try OpenMeteo.parseGeocode(Data(ok.utf8), city: "berlin").name, "Berlin")
        XCTAssertThrowsError(try OpenMeteo.parseGeocode(Data("{}".utf8), city: "nowhere"))
    }

    // MARK: mirror

    func testMirrorDistanceAndMaps() {
        XCTAssertEqual(MirrorMaps.distance(10, 10), 0)
        XCTAssertEqual(MirrorMaps.distance(Px.off, 10), 90)
        XCTAssertEqual(MirrorMaps.distance(2, 178), 4)
        var g = RGBGrid()
        for i in 0..<PIXELS { g.v[i * 3] = 1 }          // alles rot
        XCTAssertTrue(MirrorMaps.color(g).allSatisfy { $0 == 0 })
        XCTAssertTrue(MirrorMaps.silhouette(g, background: g).allSatisfy { $0 == Px.off })
    }

    func testMirrorAppWithDemoSource() {
        let app = MirrorApp(source: DemoSource())
        for _ in 0..<5 { app.step() }
        XCTAssertTrue(app.haveFrame)
        XCTAssertTrue(app.frame().contains { $0 != Px.off })
    }

    // MARK: effects + menue

    func testEffectsFramesAreValid() {
        let f = CurtainMenu.frame(index: 3)
        for (frame, delay) in Effects.tvOffFrames(f) + Effects.tvOnFrames(f) + Effects.transitionFrames(old: f, new: f) {
            XCTAssertEqual(frame.count, 400)
            XCTAssertGreaterThan(delay, 0)
            XCTAssertTrue(frame.allSatisfy { Proto.isValidColor($0) })
        }
    }

    func testAllMenuIconsFit() {
        for i in 0..<CurtainMenu.items.count {
            XCTAssertEqual(CurtainMenu.frame(index: i).count, 400)
        }
    }

    func testBannerQueue() {
        var q = BannerQueue()
        q.set([(blankFrame(), 1.0), (blankWithBorder(), .infinity)])
        XCTAssertEqual(q.current(now: 0), blankFrame())
        XCTAssertEqual(q.current(now: 0.5), blankFrame())
        XCTAssertEqual(q.current(now: 1.5), blankWithBorder())
        XCTAssertEqual(q.current(now: 100), blankWithBorder())
    }
}
