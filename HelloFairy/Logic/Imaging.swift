import Foundation

enum FitMode: String, CaseIterable, Identifiable {
    case contain, cover, stretch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .contain: return "einpassen"
        case .cover: return "fuellen"
        case .stretch: return "strecken"
        }
    }
}

enum Imaging {
    /// farbname -> pixel-farbbyte (hue 0-180, 255 = weiss, 254 = aus)
    static let colorNames: [(name: String, byte: UInt8)] = [
        ("rot", 0), ("orange", 15), ("gelb", 30), ("lime", 45), ("gruen", 60), ("cyan", 90),
        ("blau", 120), ("lila", 140), ("magenta", 150), ("pink", 165), ("weiss", Px.white),
    ]

    /// 20x20 rgb (8 bit, r,g,b hintereinander) -> frame. boost skaliert die helligkeit wie PIL ImageEnhance
    static func frame(fromRGB rgb: [UInt8], dark: Double = 0.18, white: Double = 0.18, boost: Double = 1.0) -> Frame {
        precondition(rgb.count == PIXELS * 3)
        func scale(_ v: UInt8) -> Int { min(255, Int((Double(v) * boost).rounded(.toNearestOrEven))) }
        return (0..<PIXELS).map { i in
            Proto.rgbToPixelByte(r: scale(rgb[i * 3]), g: scale(rgb[i * 3 + 1]), b: scale(rgb[i * 3 + 2]),
                                 dark: dark, white: white)
        }
    }

    /// farbbyte -> hsv (h 0-359, s/v 0-100) fuer die lichterketten-kommandos
    static func hsv(r: Int, g: Int, b: Int) -> (h: Int, s: Int, v: Int) {
        let (h, s, v) = Proto.rgbToHSV(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        return (Int(h * 360) % 360, Int((s * 100).rounded(.toNearestOrEven)), Int((v * 100).rounded(.toNearestOrEven)))
    }
}
