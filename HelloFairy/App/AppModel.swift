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

    var menuIndex = 0
    var activeApp: String?
    var launching = false
    var notice: String?

    @ObservationIgnored private var menuTask: Task<Void, Never>?

    init() {
        curtain = Curtain(link: link)
    }

    /// wenn schon mal ein geraet gekoppelt war: still im hintergrund verbinden
    func autoConnect() async {
        guard Settings.deviceID != nil, link.phase == .idle else { return }
        try? await link.connect()
    }

    // MARK: menue auf dem vorhang

    func pushMenu() {
        menuTask?.cancel()
        let idx = menuIndex
        menuTask = Task { [weak self] in
            guard let self, self.link.isReady else { return }
            do {
                _ = try await self.curtain.ensureDrawMode()
                try await self.curtain.sendChanges(CurtainMenu.frame(index: idx))
            } catch {
                self.notice = error.localizedDescription
            }
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

    func launch(_ id: String) async {
        guard activeApp == nil, !launching else { return }
        launching = true
        defer { launching = false }
        notice = nil
        menuTask?.cancel()
        await menuTask?.value
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

    /// wie "quit" im terminal: tv-aus-effekt, dann alles aus
    func switchOffWithEffect() async {
        guard link.isReady else { return }
        await curtain.tvOff(CurtainMenu.frame(index: menuIndex))
        try? await link.setPower(false)
        link.screenState = nil
    }
}
