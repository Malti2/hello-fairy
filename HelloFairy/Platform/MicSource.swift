import Foundation
import AVFoundation

enum MicError: Error, LocalizedError {
    case denied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .denied: return "mikrofon nicht erlaubt: einstellungen > Hello Fairy > mikrofon"
        case .failed(let s): return "mikrofon: \(s)"
        }
    }
}

/// mikrofon -> lautstaerke (rms) + grobe tonhoehe (nulldurchgaenge)
final class MicSource: NSObject, LevelSource, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var latest: AudioSample?
    private var running = false

    static func make() async throws -> MicSource {
        guard await AVAudioApplication.requestRecordPermission() else { throw MicError.denied }
        let src = MicSource()
        try src.start()
        return src
    }

    private func start() throws {
        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers: die Musik laeuft weiter, waehrend das Mikro mithoert (und die App im Hintergrund wach bleibt)
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw MicError.failed("kein eingang") }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.process(buffer)
            }
            try engine.start()
            running = true
        } catch let e as MicError {
            throw e
        } catch {
            throw MicError.failed(error.localizedDescription)
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 1 else { return }
        var sum: Float = 0
        var crossings = 0
        var prev = data[0]
        for i in 0..<n {
            let v = data[i]
            sum += v * v
            if (v >= 0) != (prev >= 0) { crossings += 1 }
            prev = v
        }
        let rms = (sum / Float(n)).squareRoot()
        let freq = Float(crossings) / (2 * Float(n)) * Float(buffer.format.sampleRate)
        // 80 Hz ... 4 kHz logarithmisch auf 0...1
        let pitch = max(0, min(1, log2(max(freq, 80) / 80) / log2(50)))
        let level = max(0, min(1, rms * 6))
        lock.lock()
        latest = AudioSample(level: level, pitch: pitch)
        lock.unlock()
    }

    func read() -> AudioSample? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func close() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
