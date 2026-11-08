import Foundation

/// kleiner seedbarer zufall (splitmix64), damit level/tests reproduzierbar sind
final class GameRNG {
    private var state: UInt64

    init(seed: UInt64? = nil) {
        state = seed ?? UInt64.random(in: UInt64.min...UInt64.max)
    }

    func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0..<n
    func below(_ n: Int) -> Int {
        precondition(n > 0)
        return Int(next() % UInt64(n))
    }

    /// inklusive wie python randint
    func int(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + below(r.upperBound - r.lowerBound + 1)
    }

    /// 0..<1
    func double() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    func choice<T>(_ items: [T]) -> T {
        items[below(items.count)]
    }

    func weighted<T>(_ items: [(T, Int)]) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var roll = below(total)
        for (item, w) in items {
            if roll < w { return item }
            roll -= w
        }
        return items[items.count - 1].0
    }

    func shuffled<T>(_ items: [T]) -> [T] {
        var a = items
        if a.count > 1 {
            for i in stride(from: a.count - 1, to: 0, by: -1) {
                a.swapAt(i, below(i + 1))
            }
        }
        return a
    }
}

/// monotone uhr in sekunden
func monotonicNow() -> Double {
    ProcessInfo.processInfo.systemUptime
}
