import Foundation

/// zeichnen direkt auf dem vorhang. das bild bleibt gespeichert
final class PaintApp: CurtainApp {
    /// farbpalette, die letzte ist der radierer
    static let palette: [UInt8] = [0, 15, 30, 60, 90, 120, 140, 165, Px.white, Px.off]

    private(set) var canvas: Frame
    private(set) var selected = 3
    private var lastCell: (Int, Int)?
    private let persist: Bool

    let tick = 0.25
    var hint: String { "mit dem finger malen · farbe unten waehlen" }

    init(persist: Bool = true) {
        self.persist = persist
        if persist, let data = Settings.paintData, data.count == PIXELS, data.allSatisfy(Proto.isValidColor) {
            canvas = data
        } else {
            canvas = blankFrame()
        }
    }

    func reset() { clear() }
    func step() {}
    func stop() { save() }

    func status() -> String {
        let c = PaintApp.palette[selected]
        return c == Px.off ? "radierer" : "farbe \(selected + 1)/\(PaintApp.palette.count - 1)"
    }

    func select(_ index: Int) {
        selected = max(0, min(PaintApp.palette.count - 1, index))
    }

    func clear() {
        canvas = blankFrame()
        lastCell = nil
        save()
    }

    func fill() {
        canvas = Frame(repeating: PaintApp.palette[selected], count: PIXELS)
        save()
    }

    func key(_ key: Key) {
        switch key {
        case .right: select((selected + 1) % PaintApp.palette.count)
        case .left: select((selected + PaintApp.palette.count - 1) % PaintApp.palette.count)
        default: break
        }
    }

    func touch(x: Double, y: Double) {
        let cx = max(0, min(W - 1, Int(x * Double(W)))), cy = max(0, min(H - 1, Int(y * Double(H))))
        let color = PaintApp.palette[selected]
        if let (lx, ly) = lastCell {
            // linie vom letzten punkt, damit schnelles wischen keine luecken laesst
            let steps = max(abs(cx - lx), abs(cy - ly), 1)
            for s in 0...steps {
                let px = lx + Int((Double(cx - lx) * Double(s) / Double(steps)).rounded())
                let py = ly + Int((Double(cy - ly) * Double(s) / Double(steps)).rounded())
                canvas[py * W + px] = color
            }
        } else {
            canvas[cy * W + cx] = color
        }
        lastCell = (cx, cy)
    }

    func touchEnded() {
        lastCell = nil
        save()
    }

    func save() {
        if persist { Settings.paintData = canvas }
    }

    func frame() -> Frame { canvas }
}
