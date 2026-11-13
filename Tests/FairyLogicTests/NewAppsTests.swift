import XCTest
@testable import FairyLogic

final class NewAppsTests: XCTestCase {
    func validFrame(_ f: Frame, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(f.count, 400, file: file, line: line)
        XCTAssertTrue(f.allSatisfy { Proto.isValidColor($0) }, "ungueltige farbe", file: file, line: line)
    }

    // MARK: glyphs

    func testAlphabetComplete() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 !?.,'+/%<>#:-" {
            let g = Glyphs.glyph(ch)
            XCTAssertEqual(g.count, 5, "\(ch)")
            XCTAssertTrue(g.allSatisfy { $0.count == g[0].count }, "\(ch) ungleiche breite")
            XCTAssertNotNil(Glyphs.table[ch], "\(ch) fehlt")
        }
    }

    func testBitmapAndUmlauts() {
        XCTAssertEqual(Glyphs.normalize("Käse über"), "KAESE UEBER")
        let cols = Glyphs.bitmap("HI")
        XCTAssertEqual(cols.count, 3 + 1 + 3 + 1)
        XCTAssertTrue(cols.allSatisfy { $0.count == 5 })
    }

    // MARK: breakout

    func testBreakoutLaunchAndBounce() {
        let g = Breakout(rng: GameRNG(seed: 1), clock: { 0 })
        XCTAssertFalse(g.launched)
        let bx0 = g.bx
        g.step()
        XCTAssertEqual(g.bx, bx0)               // klebt am schlaeger
        g.key(.space)
        XCTAssertTrue(g.launched)
        for _ in 0..<400 {
            g.touch(x: Double(g.bx) / 20, y: 0)      // schlaeger folgt dem ball
            g.step()
            if g.over { break }
        }
        XCTAssertGreaterThan(g.score, 0)
        validFrame(g.frame())
    }

    func testBreakoutLosesLivesAndEnds() {
        var t = 0.0
        let g = Breakout(rng: GameRNG(seed: 2), clock: { t })
        for _ in 0..<5000 {
            g.touch(x: g.bx < 10 ? 0.95 : 0.05, y: 0)      // schlaeger weg vom ball
            g.key(.space)
            g.step()
            t += 1
            if g.over { break }
        }
        XCTAssertTrue(g.over)
        XCTAssertEqual(g.lives, 0)
    }

    func testBreakoutPaddleBounds() {
        let g = Breakout(rng: GameRNG(seed: 3), clock: { 0 })
        g.touch(x: -1, y: 0)
        XCTAssertEqual(g.px, 1)
        g.touch(x: 2, y: 0)
        XCTAssertEqual(g.px, 20 - 1 - Breakout.paddleLen)
    }

    // MARK: flappy

    func testFlappyWaitsForFirstTapAndFalls() {
        let g = Flappy(rng: GameRNG(seed: 4), clock: { 0 })
        let y0 = g.y
        g.step()
        XCTAssertEqual(g.y, y0)                 // vor dem ersten tippen passiert nichts
        g.key(.space)
        g.step()
        XCTAssertLessThan(g.y, y0)
        var n = 0
        while !g.over && n < 200 { g.step(); n += 1 }      // ohne flattern faellt der vogel
        XCTAssertTrue(g.over)
        validFrame(g.frame())
    }

    func testFlappyBotCanScore() {
        // einfacher bot: flattert, wenn der vogel unter der luecken-mitte ist
        var t = 0.0
        let g = Flappy(rng: GameRNG(seed: 5), clock: { t })
        g.key(.space)
        for _ in 0..<600 {
            if g.over { break }
            if let p = g.pipes.first(where: { $0.x + 1 >= Flappy.birdX }) {
                if g.y > p.gapTop + Flappy.gap - 2 { g.key(.space) }
            }
            g.step()
        }
        XCTAssertGreaterThanOrEqual(g.score, 3)
    }

    // MARK: life

    func testLifeBlinkerOscillates() {
        let g = Life(rng: GameRNG(seed: 6))
        g.load([(5, 5), (6, 5), (7, 5)])
        g.step()
        XCTAssertEqual(g.population, 3)
        XCTAssertTrue(g.alive[4 * 20 + 6] && g.alive[5 * 20 + 6] && g.alive[6 * 20 + 6])   // senkrecht
        g.step()
        XCTAssertTrue(g.alive[5 * 20 + 5] && g.alive[5 * 20 + 6] && g.alive[5 * 20 + 7])   // wieder waagerecht
        validFrame(g.frame())
    }

    func testLifeRuleAndReseed() {
        let g = Life(rng: GameRNG(seed: 8))
        for _ in 0..<5 { g.step() }
        XCTAssertEqual(g.generation, 5)
        // alles tot -> automatisch neu gemischt
        for _ in 0..<400 { g.step() }
        XCTAssertGreaterThan(g.population, 0)
    }

    func testLifeTouchDraws() {
        let g = Life(rng: GameRNG(seed: 9))
        g.key(.space)
        g.touch(x: 0.5, y: 0.5)
        XCTAssertTrue(g.alive[10 * 20 + 10])
        g.key(.up)
        XCTAssertLessThan(g.tick, 0.16)
    }

    // MARK: paint

    func testPaintDrawsLinesAndErases() {
        let p = PaintApp(persist: false)
        p.select(0)
        p.touch(x: 0.025, y: 0.025)
        p.touch(x: 0.975, y: 0.025)          // schnelle bewegung: linie ohne luecken
        for x in 0..<20 { XCTAssertEqual(p.canvas[x], 0) }
        p.touchEnded()
        p.select(PaintApp.palette.count - 1)
        p.touch(x: 0.525, y: 0.025)
        XCTAssertEqual(p.canvas[10], Px.off)
        p.clear()
        XCTAssertTrue(p.canvas.allSatisfy { $0 == Px.off })
        validFrame(p.frame())
    }

    func testPaintPersistence() {
        let suite = UserDefaults(suiteName: "hf.test.paint")!
        suite.removePersistentDomain(forName: "hf.test.paint")
        let old = Settings.defaults
        Settings.defaults = suite
        defer { Settings.defaults = old }
        let p = PaintApp()
        p.select(1)
        p.touch(x: 0.5, y: 0.5)
        p.touchEnded()
        let again = PaintApp()
        XCTAssertEqual(again.canvas[10 * 20 + 10], 15)
    }

    // MARK: show

    func testAllShowModesRender() {
        for m in ShowApp.Mode.allCases {
            let s = ShowApp(mode: m, rng: GameRNG(seed: 10))
            for _ in 0..<40 { s.step() }
            validFrame(s.frame())
            XCTAssertTrue(s.frame().contains { $0 != Px.off }, "\(m) leer")
        }
        let s = ShowApp(rng: GameRNG(seed: 11))
        s.key(.right)
        XCTAssertEqual(s.mode, .rainbow)
        s.key(.left)
        s.key(.left)
        XCTAssertEqual(s.mode, .stars)
    }

    // MARK: laufschrift

    func testMarqueeScrollsAndWraps() {
        let m = MarqueeApp(text: "HI", big: true, rainbow: false)
        XCTAssertFalse(m.frame().contains { $0 != Px.off })      // startet ausserhalb
        var seen = false
        for _ in 0..<200 {
            m.step()
            if m.frame().contains(where: { $0 != Px.off }) { seen = true }
            validFrame(m.frame())
        }
        XCTAssertTrue(seen)
        XCTAssertLessThanOrEqual(m.offset, 8 * 2 + 20)
        m.configure(text: "NEU", big: false, rainbow: true, tick: 0.05)
        XCTAssertEqual(m.offset, 0)
        XCTAssertEqual(m.tick, 0.05)
    }

    // MARK: sound

    final class FakeAudio: LevelSource {
        var level: Float = 0.5
        func read() -> AudioSample? { AudioSample(level: level, pitch: 0.3) }
        func close() {}
    }

    func testSoundBarsFollowLevel() {
        let a = FakeAudio()
        let s = SoundApp(source: a)
        a.level = 0.01
        for _ in 0..<30 { s.step() }
        let quiet = s.frame().filter { $0 != Px.off }.count
        a.level = 0.9
        for _ in 0..<30 { s.step() }
        let loud = s.frame().filter { $0 != Px.off }.count
        XCTAssertGreaterThan(loud, quiet)
        validFrame(s.frame())
        XCTAssertEqual(s.mode, .cover)          // ohne cover: saeulen
        s.key(.right)
        XCTAssertEqual(s.mode, .bars)
        s.key(.right)
        XCTAssertEqual(s.mode, .mirror)
        for _ in 0..<5 { s.step() }
        validFrame(s.frame())
    }

    func testSoundShowsCoverWhenAvailable() {
        let s = SoundApp(source: FakeAudio())
        var art = blankFrame()
        art[5] = 60
        s.setCover(art, title: "Song - Artist")
        XCTAssertEqual(s.frame(), art)
        XCTAssertEqual(s.status(), "Song - Artist")
        s.key(.right)                                    // saeulen
        XCTAssertNotEqual(s.frame(), art)
        s.key(.right); s.key(.right)                     // zurueck auf cover
        XCTAssertEqual(s.frame(), art)
        s.setCover(nil, title: nil)
        validFrame(s.frame())
    }

    func testSoundWithoutSourceWaits() {
        let s = SoundApp()
        s.step()
        XCTAssertFalse(s.haveAudio)
        validFrame(s.frame())
    }

    // MARK: timer

    func testCountdownRunsAndFinishes() {
        var t = 100.0
        let c = CountdownApp(minutes: 1, clock: { t })
        var fired = 0
        c.onFinish = { fired += 1 }
        c.key(.enter)
        XCTAssertTrue(c.running)
        t += 30
        XCTAssertEqual(c.remaining, 30, accuracy: 0.001)
        c.key(.enter)                                    // pause
        t += 100
        XCTAssertEqual(c.remaining, 30, accuracy: 0.001)
        c.key(.enter)
        t += 31
        c.step()
        XCTAssertTrue(c.finished)
        XCTAssertEqual(fired, 1)
        c.step()
        XCTAssertEqual(fired, 1)
        validFrame(c.frame())
        c.key(.enter)
        XCTAssertFalse(c.finished)
    }

    func testCountdownMinutesAndStopwatch() {
        var t = 0.0
        let c = CountdownApp(minutes: 5, clock: { t })
        c.key(.up)
        XCTAssertEqual(c.minutes, 6)
        c.key(.down); c.key(.down)
        XCTAssertEqual(c.minutes, 4)
        c.key(.right)
        XCTAssertEqual(c.mode, .stopwatch)
        c.key(.enter)
        t += 75
        XCTAssertEqual(c.elapsed, 75, accuracy: 0.001)
        validFrame(c.frame())
        c.setMinutes(200)
        XCTAssertEqual(c.minutes, 99)
    }

    // MARK: pixel art + menue

    func testPixelArtFits() {
        for art in PixelArt.all {
            let w = art.rows.map { $0.count }
            XCTAssertEqual(Set(w).count, 1, "\(art.id) unterschiedliche zeilenbreite")
            XCTAssertLessThanOrEqual(art.rows.count, 20)
            XCTAssertLessThanOrEqual(w[0], 20)
            validFrame(art.frame())
            XCTAssertTrue(art.frame().contains { $0 != Px.off })
        }
        validFrame(PixelArt.rainbow())
    }

    func testMenuHasAllAppsAndIcons() {
        XCTAssertEqual(CurtainMenu.items.count, 15)
        for (i, item) in CurtainMenu.items.enumerated() {
            let icon = CurtainMenu.icons[item.id]
            XCTAssertNotNil(icon, item.id)
            XCTAssertTrue(Set(icon!.map { $0.count }).count == 1, "\(item.id) unregelmaessig")
            validFrame(CurtainMenu.frame(index: i))
            // alle positionspunkte sichtbar
            let dots = (1..<(W - 1)).filter { CurtainMenu.frame(index: i)[17 * W + $0] != Px.off }
            XCTAssertEqual(dots.count, 15)
        }
        XCTAssertEqual(Set(CurtainMenu.items.map { $0.id }).count, 15)
    }
}
