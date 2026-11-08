import Foundation

/// anzeige-effekte: alter roehrenfernseher an/aus, fenster-uebergang zwischen apps
enum Effects {
    static let lineColor: UInt8 = 255
    static let bandHeights = [18, 15, 12, 9, 7, 5, 3, 2]
    static let lineWidths = [20, 16, 12, 8, 6, 4, 2]
    static let dotFade: [UInt8] = [255, 120, Px.off]
    static let frameDelay = 0.06

    typealias Timed = (frame: Frame, delay: Double)

    static func squash(_ frame: Frame, band: Int) -> Frame {
        let top = (H - band) / 2
        var out = blankFrame()
        for y in 0..<band {
            let src = min(H - 1, Int((Double(y) + 0.5) * Double(H) / Double(band)))
            for x in 0..<W { out[(top + y) * W + x] = frame[src * W + x] }
        }
        return out
    }

    static func tvOffFrames(_ frame: Frame) -> [Timed] {
        var seq: [Timed] = [(frame, frameDelay)]
        for band in bandHeights { seq.append((squash(frame, band: band), frameDelay)) }
        let rows = [(H - 2) / 2, (H - 2) / 2 + 1]
        for width in lineWidths {
            var f = blankFrame()
            let x0 = (W - width) / 2
            for y in rows { for x in x0..<(x0 + width) { f[y * W + x] = lineColor } }
            seq.append((f, frameDelay))
        }
        for color in dotFade {
            var f = blankFrame()
            if color != Px.off {
                for y in rows { for x in [W / 2 - 1, W / 2] { f[y * W + x] = color } }
            }
            seq.append((f, 0.12))
        }
        return seq
    }

    /// einschalten = ausschalt-animation rueckwaerts
    static func tvOnFrames(_ frame: Frame) -> [Timed] { Array(tvOffFrames(frame).reversed()) }

    static let windowClose = [20, 16, 12, 8, 6, 4, 2]
    static let windowOpen = [4, 6, 8, 12, 16, 20]
    static let windowDelay = 0.04

    static func box(_ frame: Frame, size: Int) -> Frame {
        let lo = (W - size) / 2
        let hi = lo + size
        var out = blankFrame()
        for y in lo..<hi {
            for x in lo..<hi {
                let edge = size < W && (y == lo || y == hi - 1 || x == lo || x == hi - 1)
                out[y * W + x] = edge ? lineColor : frame[y * W + x]
            }
        }
        return out
    }

    static func transitionFrames(old: Frame, new: Frame) -> [Timed] {
        windowClose.map { (box(old, size: $0), windowDelay) } + windowOpen.map { (box(new, size: $0), windowDelay) }
    }

    /// frame aus dem zustand des vorhangs (index = geraete-index)
    static func frame(fromState state: [UInt8]) -> Frame {
        var f = blankFrame()
        for y in 0..<H { for x in 0..<W { f[y * W + x] = state[Proto.pixelIndex(x: x, y: y)] } }
        return f
    }
}
