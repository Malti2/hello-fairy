import Foundation

/// 20x20 rgb raster (0...1), zeilenweise r,g,b
struct RGBGrid {
    var v: [Float]
    init(_ v: [Float]) { self.v = v }
    init() { v = [Float](repeating: 0, count: PIXELS * 3) }
    func r(_ i: Int) -> Float { v[i * 3] }
    func g(_ i: Int) -> Float { v[i * 3 + 1] }
    func b(_ i: Int) -> Float { v[i * 3 + 2] }
}

protocol FrameSource: AnyObject {
    /// letztes kamerabild als 20x20 raster (schon gespiegelt + quadratisch beschnitten) oder nil
    func read() -> RGBGrid?
    func close()
}

/// kunstkamera: heller bunter klecks hopst ueber einen dunklen verlauf
final class DemoSource: FrameSource {
    private let t0 = monotonicNow()

    func read() -> RGBGrid? {
        let t = monotonicNow() - t0
        let w = 160.0, h = 120.0
        let cx = w / 2 + 50 * sin(t * 1.3), cy = h / 2 + 35 * cos(t * 0.9)
        var out = RGBGrid()
        for gy in 0..<H {
            for gx in 0..<W {
                let xx = 20 + (Double(gx) + 0.5) * 6, yy = (Double(gy) + 0.5) * 6
                var r = (30 + 40 * yy / h), g = 0.0, b = (40 + 60 * xx / w)
                let d = hypot(xx - cx, yy - cy)
                let blob = max(0, min(1, 1 - d / 28))
                r = r * (1 - blob) + 255 * blob
                g = g * (1 - blob) + 220 * blob
                b = b * (1 - blob) + 40 * blob
                let i = gy * W + gx
                out.v[i * 3] = Float(r / 255)
                out.v[i * 3 + 1] = Float(g / 255)
                out.v[i * 3 + 2] = Float(b / 255)
            }
        }
        return out
    }

    func close() {}
}

enum MirrorMaps {
    static let threshold = 6

    static func gray(_ g: RGBGrid) -> [Float] {
        (0..<PIXELS).map { 0.299 * g.r($0) + 0.587 * g.g($0) + 0.114 * g.b($0) }
    }

    /// numpy percentile (lineare interpolation)
    static func percentile(_ values: [Float], _ p: Double) -> Float {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        let pos = p / 100 * Double(s.count - 1)
        let lo = Int(floor(pos)), hi = min(s.count - 1, lo + 1)
        let frac = Float(pos - Double(lo))
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    private static func rnd(_ v: Float) -> Int { Int(v.rounded(.toNearestOrEven)) }

    /// helligkeit -> farbe: dunkel aus, dann blau, cyan, gruen, gelb, rot, hellstes weiss
    static func thermal(_ gray: [Float], gain: Float = 1.0) -> [UInt8] {
        let lo = percentile(gray, 3), hi = percentile(gray, 97)
        let span = max(hi - lo, 0.2)
        return gray.map { g in
            let v = max(0, min(1, (g - lo) / span)) * gain
            if v >= 0.97 { return Px.white }
            if v < 0.1 { return Px.off }
            let t = max(0, min(1, (v - 0.1) / 0.87))
            return UInt8(rnd(120 * (1 - t)))
        }
    }

    /// echte farbtoene (saettigung verstaerkt); dunkle pixel aus, blasse weiss
    static func color(_ g: RGBGrid, boost: Float = 1.6) -> [UInt8] {
        (0..<PIXELS).map { i in
            let r8 = Int(max(0, min(1, g.r(i))) * 255)
            let g8 = Int(max(0, min(1, g.g(i))) * 255)
            let b8 = Int(max(0, min(1, g.b(i))) * 255)
            let mx = max(r8, g8, b8), mn = min(r8, g8, b8)
            let delta = Float(mx - mn)
            let val = Float(mx) / 255
            let sat: Float = mx == 0 ? 0 : max(0, min(1, (delta / Float(mx)) * boost))
            var hue: Float = 0
            if delta > 0 {
                let rf = Float(r8), gf = Float(g8), bf = Float(b8)
                if mx == r8 { hue = 60 * (gf - bf) / delta }
                else if mx == g8 { hue = 120 + 60 * (bf - rf) / delta }
                else { hue = 240 + 60 * (rf - gf) / delta }
                if hue < 0 { hue += 360 }
            }
            let hb = max(0, min(180, rnd(hue / 2)))
            if val < 0.18 { return Px.off }
            if sat < 0.25 { return Px.white }
            return UInt8(hb)
        }
    }

    /// du in farbe, hintergrund aus. vergleicht volles rgb, damit gleich helle farben zaehlen
    static func silhouette(_ g: RGBGrid, background: RGBGrid, thr: Float = 0.18) -> [UInt8] {
        var out = color(g)
        for i in 0..<PIXELS {
            let dr = g.r(i) - background.r(i), dg = g.g(i) - background.g(i), db = g.b(i) - background.b(i)
            if (dr * dr + dg * dg + db * db).squareRoot() < thr { out[i] = Px.off }
        }
        return out
    }

    static func motion(_ gray: [Float], previous: [Float], gain: Float = 6.0) -> [UInt8] {
        (0..<PIXELS).map { i in
            let d = max(0, min(1, abs(gray[i] - previous[i]) * gain))
            if d < 0.15 { return Px.off }
            return UInt8(rnd(120 * (1 - d)))      // kleine bewegung blau ... grosse rot
        }
    }

    /// wie unterschiedlich zwei farbbytes aussehen (0 = gleich, 90 = gegensaetzlich)
    static func distance(_ a: UInt8, _ b: UInt8) -> Int {
        if a == b { return 0 }
        if a == Px.off || a == Px.white || b == Px.off || b == Px.white { return 90 }
        let d = abs(Int(a) - Int(b))
        return min(d, 180 - d)
    }
}

final class MirrorApp: CurtainApp {
    enum Mode: String, CaseIterable { case thermal, color, silhouette, motion }

    let tick = 0.12
    var hint: String { "wischen wechselt den look · tippen nimmt den hintergrund neu auf" }

    private var source: FrameSource?
    private let makeSource: (() async throws -> FrameSource)?
    let budget: Int
    private(set) var mode: Mode
    private(set) var error: String?
    private var shown = blankFrame()
    private var smooth: RGBGrid?
    private var background: RGBGrid?
    private var previous: [Float]?
    private(set) var steps = 0
    private(set) var changed = 0
    private(set) var haveFrame = false

    init(source: FrameSource? = nil, makeSource: (() async throws -> FrameSource)? = nil,
         mode: Mode = .thermal, budget: Int = Proto.maxPixelsPerPacket) {
        self.source = source
        self.makeSource = makeSource
        self.mode = mode
        self.budget = budget
    }

    /// quelle tauschen (z.b. demo-kamera an/aus)
    func replaceSource(_ new: FrameSource?) {
        source?.close()
        source = new
        error = nil
        reset()
    }

    func start() async {
        guard source == nil, let make = makeSource else { return }
        error = nil
        do { source = try await make() } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func stop() {
        source?.close()
        source = nil
    }

    func reset() {
        shown = blankFrame()
        smooth = nil
        background = nil
        previous = nil
        steps = 0
        changed = 0
        haveFrame = false
    }

    func key(_ key: Key) {
        let all = Mode.allCases
        guard let i = all.firstIndex(of: mode) else { return }
        switch key {
        case .right, .down: mode = all[(i + 1) % all.count]
        case .left, .up: mode = all[(i + all.count - 1) % all.count]
        case .space, .rotate: background = nil          // wird beim naechsten bild neu aufgenommen
        default: break
        }
    }

    func status() -> String {
        if let e = error { return e }
        if !haveFrame { return "warte auf kamera..." }
        return "look \(mode.rawValue)  \(changed) pixel/schritt"
    }

    private func target() -> [UInt8]? {
        guard let rgb0 = source?.read() else { return nil }
        haveFrame = true
        // etwas ueber die zeit mitteln gegen sensorrauschen
        var sm = rgb0
        if let old = smooth { for i in 0..<sm.v.count { sm.v[i] = 0.5 * old.v[i] + 0.5 * rgb0.v[i] } }
        smooth = sm
        let gray = MirrorMaps.gray(sm)
        if background == nil { background = sm }
        let prev = previous ?? gray
        previous = gray
        switch mode {
        case .thermal: return MirrorMaps.thermal(gray)
        case .color: return MirrorMaps.color(sm)
        case .silhouette: return MirrorMaps.silhouette(sm, background: background ?? sm)
        case .motion: return MirrorMaps.motion(gray, previous: prev)
        }
    }

    func step() {
        steps += 1
        guard let tgt = target() else { return }
        let ranked = (0..<PIXELS).map { (dist: MirrorMaps.distance(shown[$0], tgt[$0]), idx: $0) }
            .sorted { $0.dist != $1.dist ? $0.dist > $1.dist : $0.idx > $1.idx }
        var n = 0
        for r in ranked.prefix(budget) {
            if r.dist < MirrorMaps.threshold { break }
            shown[r.idx] = tgt[r.idx]
            n += 1
        }
        changed = n
    }

    func frame() -> Frame {
        error != nil ? WeatherFace.errorFrame() : shown
    }
}
