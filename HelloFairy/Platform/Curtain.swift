import Foundation

/// bildschirmzustand des vorhangs (draw mode) + nur geaenderte pixel senden, wie effects.py
@MainActor
final class Curtain {
    let link: FairyLink

    init(link: FairyLink) { self.link = link }

    /// vorhang einmal pro verbindung in draw mode bringen; liefert den gemeinsamen bildschirmzustand
    func ensureDrawMode() async throws -> [UInt8] {
        if let s = link.screenState { return s }
        try await link.requireCurtain(force: false)
        try await link.setPower(true)
        for pkt in [Proto.d0(0x03), Proto.d0(0x00)] {
            try await link.write(pkt)
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        let s = [UInt8](repeating: Px.off, count: PIXELS)
        link.screenState = s
        return s
    }

    /// sendet nur geaenderte pixel. false = nichts geaendert oder link neu aufgebaut (dann neu initialisieren)
    @discardableResult
    func sendChanges(_ frame: Frame) async throws -> Bool {
        guard var state = link.screenState else { return false }
        let want = Proto.frameToIndexColors(frame)
        var items: [(Int, UInt8)] = []
        for i in 0..<PIXELS where state[i] != want[i] { items.append((i, want[i])) }
        if items.isEmpty { return false }
        let generation = link.reconnects
        let per = Proto.pixelsPerPacket(writeCapacity: link.writeCapacity)
        var k = 0
        while k < items.count {
            let batch = Array(items[k..<min(items.count, k + per)])
            for pkt in Proto.deltaPackets(batch, perPacket: per) { try await link.write(pkt) }
            if link.reconnects != generation { return false }       // link neu: zustand veraltet
            for (i, c) in batch { state[i] = c }
            link.screenState = state           // pro paket nachziehen, damit ein abbruch nichts verschiebt
            k += per
        }
        return true
    }

    func play(_ frames: [Effects.Timed]) async {
        do {
            _ = try await ensureDrawMode()
            for (frame, delay) in frames {
                if Task.isCancelled { return }
                try await sendChanges(frame)
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        } catch {
            // animation ist nur deko: fehler zeigt spaeter der runner
        }
    }

    private func current(fallback: Frame) -> Frame {
        link.screenState.map { Effects.frame(fromState: $0) } ?? fallback
    }

    func tvOn(_ frame: Frame) async { await play(Effects.tvOnFrames(frame)) }
    func tvOff(_ fallback: Frame) async { await play(Effects.tvOffFrames(current(fallback: fallback))) }
    func transition(from old: Frame, to new: Frame) async {
        await play(Effects.transitionFrames(old: current(fallback: old), new: new))
    }
}
