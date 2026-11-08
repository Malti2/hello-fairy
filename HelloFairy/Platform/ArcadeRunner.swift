import Foundation
import Observation

/// fuehrt eine CurtainApp aus: spiel-ticks + vorschau fuer die UI + delta-updates zum vorhang
@MainActor
@Observable
final class ArcadeRunner {
    private(set) var frame: Frame = blankFrame()
    private(set) var statusText = ""
    private(set) var hintText = ""
    private(set) var note: String?
    private(set) var running = false
    var paused = false

    @ObservationIgnored private(set) var app: CurtainApp?
    @ObservationIgnored private var curtain: Curtain?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var writerTask: Task<Void, Never>?
    @ObservationIgnored private var minInterval = 0.06

    /// startet die app. curtain = nil -> nur vorschau auf dem handy
    func run(_ app: CurtainApp, on curtain: Curtain?, minInterval: Double) async {
        await stop()
        self.app = app
        self.curtain = curtain
        self.minInterval = minInterval
        paused = false
        note = nil
        hintText = app.hint
        app.reset()                // timer/banner neu starten
        await app.start()
        refresh()
        running = true

        tickTask = Task { [weak self] in
            var next = monotonicNow()
            while !Task.isCancelled {
                guard let self else { return }
                let now = monotonicNow()
                if now >= next {
                    if !self.paused { app.step() }
                    next = now + app.tick
                }
                self.refresh()
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        if let curtain {
            writerTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    do {
                        _ = try await curtain.ensureDrawMode()      // nach reconnect neu initialisieren
                        try await curtain.sendChanges(self.frame)
                    } catch is CancellationError {
                        return
                    } catch {
                        self.note = error.localizedDescription
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(self.minInterval * 1_000_000_000))
                }
            }
        }
    }

    func stop() async {
        tickTask?.cancel()
        writerTask?.cancel()
        let t1 = tickTask, t2 = writerTask
        tickTask = nil
        writerTask = nil
        await t1?.value
        await t2?.value            // erst wenn kein write mehr laeuft, darf der naechste starten
        app?.stop()
        running = false
    }

    func press(_ key: Key) {
        app?.key(key)
        refresh()
    }

    func touch(x: Double, y: Double) {
        app?.touch(x: x, y: y)
        refresh()
    }

    func setInterval(_ seconds: Double) { minInterval = seconds }

    func restart() {
        app?.reset()
        refresh()
    }

    private func refresh() {
        guard let app else { return }
        let f = app.frame()
        if f != frame { frame = f }
        var text = app.status() + (paused ? "  PAUSE" : "")
        if let c = curtain, c.link.reconnects > 0 { text += "  (neu verbunden \(c.link.reconnects)x)" }
        if text != statusText { statusText = text }
    }
}
