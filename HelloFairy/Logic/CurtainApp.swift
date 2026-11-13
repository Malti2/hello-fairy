import Foundation

enum Key: String {
    case up, down, left, right, enter, space, rotate, rotateCCW
}

/// alles was auf dem vorhang laeuft: frame() liefert 400 farbbytes, step() einen spielschritt
protocol CurtainApp: AnyObject {
    var tick: Double { get }
    var hint: String { get }
    func frame() -> Frame
    func step()
    func key(_ key: Key)
    /// beruehrung auf dem vorhang, x/y normiert 0...1 (z.b. pong: schlaeger folgt dem finger)
    func touch(x: Double, y: Double)
    func touchEnded()
    func reset()
    func status() -> String
    /// z.b. kamera starten
    func start() async
    func stop()
}

extension CurtainApp {
    func touch(x: Double, y: Double) {}
    func touchEnded() {}
    func start() async {}
    func stop() {}
}

/// banner/animations-queue, getrieben von der uhr (score flash, game over, ...)
struct BannerQueue {
    var items: [(frame: Frame, secs: Double)] = []
    private var started: Double?

    var isEmpty: Bool { items.isEmpty }

    mutating func set(_ new: [(frame: Frame, secs: Double)]) {
        items = new
        started = nil
    }

    mutating func clear() { set([]) }

    mutating func current(now: Double) -> Frame? {
        while let first = items.first {
            if started == nil { started = now }
            if first.secs == .infinity || now - (started ?? now) < first.secs { return first.frame }
            items.removeFirst()
            started = nil
        }
        return nil
    }
}
