import SwiftUI
import UIKit
import Observation

/// haelt verbindung, runner und menue zusammen (kein server noetig: alles laeuft direkt auf dem iPhone)
@MainActor
@Observable
final class AppModel {
    let link = FairyLink()
    let runner = ArcadeRunner()
    let curtain: Curtain

    var tab = 0
    /// false = es wurde noch nie ein geraet gewaehlt: dann zuerst die auswahl
    var onboarded: Bool
    var menuIndex = 0
    var activeApp: String?
    var launching = false
    var notice: String?

    @ObservationIgnored private var ambientTask: Task<Void, Never>?

    init() {
        curtain = Curtain(link: link)
        onboarded = Settings.deviceID != nil
    }

    /// wenn schon mal ein geraet gekoppelt war: still im hintergrund verbinden
    func autoConnect() async {
        guard Settings.deviceID != nil, link.phase == .idle else { return }
        try? await link.connect()
    }

    // MARK: startseite + aus-zustand

    /// startseite (menue) auf den vorhang
    func pushMenu() {
        guard tab == 0, activeApp == nil, link.isReady else { return }
        ambientTask?.cancel()
        let idx = menuIndex
        ambientTask = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.curtain.ensureDrawMode()
                try await self.curtain.sendChanges(CurtainMenu.frame(index: idx))
            } catch is CancellationError {
            } catch {
                self.notice = error.localizedDescription
            }
        }
    }

    /// alles aus (tv-effekt), bis der nutzer wieder etwas einstellt
    func lightsOff() {
        ambientTask?.cancel()
        guard link.isReady else { return }
        let idx = menuIndex
        ambientTask = Task { [weak self] in
            guard let self else { return }
            await self.curtain.tvOff(CurtainMenu.frame(index: idx))
            if Task.isCancelled { return }
            try? await self.link.setPower(false)
            self.link.screenState = nil
        }
    }

    func tabChanged(from old: Int, to new: Int) {
        if new == 0 { pushMenu() } else if old == 0 { lightsOff() }
    }

    func linkBecameReady() {
        onboarded = true
        pushMenu()
    }

    func becameActive() { pushMenu() }

    func wentToBackground() {
        guard tab == 0 else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.close()
            self.lightsOff()
        }
    }

    // MARK: apps

    func makeApp(_ id: String) -> CurtainApp {
        let d = UserDefaults.standard
        switch id {
        case "snake": return Snake()
        case "pong": return Pong(points: Settings.pongPoints, difficulty: Settings.pongDifficulty)
        case "tetris": return Tetris()
        case "mario": return Mario()
        case "breakout": return Breakout()
        case "flappy": return Flappy()
        case "life": return Life()
        case "paint": return PaintApp()
        case "show": return ShowApp()
        case "marquee":
            return MarqueeApp(text: Settings.marqueeText, big: Settings.marqueeBig, rainbow: Settings.marqueeRainbow,
                              tick: Settings.marqueeTick)
        case "timer":
            let t = CountdownApp(minutes: Settings.timerMinutes)
            t.onFinish = { UINotificationFeedbackGenerator().notificationOccurred(.success) }
            return t
        case "sound":
            if d.bool(forKey: "hf.demoAudio") { return SoundApp(source: DemoAudio()) }
            return SoundApp(makeSource: { () async throws -> LevelSource in try await MicSource.make() })
        case "clock": return ClockApp()
        case "weather":
            let typed = Settings.city.trimmingCharacters(in: .whitespaces)
            let saved = Settings.location?.name ?? ""
            let useTyped = !typed.isEmpty && typed.caseInsensitiveCompare(saved) != .orderedSame
            return WeatherApp(city: useTyped ? typed : nil)
        case "mirror":
            if d.bool(forKey: "hf.demoCamera") { return MirrorApp(source: DemoSource()) }
            return MirrorApp(makeSource: { () async throws -> FrameSource in try await CameraSource.make() })
        default: return Snake()
        }
    }

    /// einstellungen aus dem app-sheet auf die laufende app anwenden
    func applySettings() {
        runner.setInterval(Settings.minInterval)
        switch runner.app {
        case let p as Pong:
            p.configure(points: Settings.pongPoints, difficulty: Settings.pongDifficulty)
        case let w as WeatherApp:
            w.setCity(Settings.city)
        case let m as MarqueeApp:
            m.configure(text: Settings.marqueeText, big: Settings.marqueeBig, rainbow: Settings.marqueeRainbow,
                        tick: Settings.marqueeTick)
        case let t as CountdownApp:
            t.setMinutes(Settings.timerMinutes)
        case let s as SoundApp:
            if UserDefaults.standard.bool(forKey: "hf.demoAudio") {
                s.replaceSource(DemoAudio())
            } else {
                s.replaceSource(nil)
                Task { await s.start() }
            }
        case let m as MirrorApp:
            if UserDefaults.standard.bool(forKey: "hf.demoCamera") {
                m.replaceSource(DemoSource())
            } else {
                m.replaceSource(nil)
                Task { await m.start() }
            }
        default:
            break
        }
    }

    func launch(_ id: String) async {
        guard activeApp == nil, !launching else { return }
        launching = true
        defer { launching = false }
        notice = nil
        ambientTask?.cancel()
        await ambientTask?.value
        let app = makeApp(id)
        let lights = link.isReady
        if lights {
            await curtain.transition(from: CurtainMenu.frame(index: menuIndex), to: app.frame())     // menue schliesst, app oeffnet
        }
        UIApplication.shared.isIdleTimerDisabled = true
        activeApp = id
        await runner.run(app, on: lights ? curtain : nil, minInterval: Settings.minInterval)
    }

    func close() async {
        guard activeApp != nil else { return }
        let last = runner.app?.frame() ?? blankFrame()
        await runner.stop()
        if link.isReady {
            await curtain.transition(from: last, to: CurtainMenu.frame(index: menuIndex))           // app schliesst, menue oeffnet
        }
        UIApplication.shared.isIdleTimerDisabled = false
        activeApp = nil
    }
}
