import Foundation

// Hello Fairy BLE protokoll. Packets: AA <cmd> <len> <payload...> <checksum>, checksum = sum(prev) & 0xFF
// Protokollwissen: nzrutman/hello_fairy_ble + die offizielle app

let W = 20
let H = 20
let PIXELS = W * H

typealias Frame = [UInt8]

enum Px {
    static let off: UInt8 = 0xFE
    static let white: UInt8 = 0xFF
}

func blankFrame() -> Frame { Frame(repeating: Px.off, count: PIXELS) }

struct SeqStep {
    let label: String
    let packet: [UInt8]
    let delay: Double
}

struct DeviceInfo: Equatable {
    var firmware: String
    var model: String
    var ledCount: Int
    var columns: Int
    var rows: Int
    var diyType: Int

    var isCurtain: Bool { ledCount == 400 && columns == 20 && rows == 20 && diyType == 3 }
}

struct DeviceStatus: Equatable {
    var power: Bool
    var mode: Int           // 1 = farbe, 2 = preset
    var countdownSeconds: Int
    var hue: Int = 0
    var saturation: Double = 0
    var brightness: Double = 0
    var preset: Int = 0
}

enum ProtoError: Error, LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let s): return s }
    }
}

enum Proto {
    static let serviceUUID = "49535343-FE7D-4AE5-8FA9-9FAFD205E455"
    static let commandUUID = "49535343-8841-43F4-A8D4-ECBE34729BB3"
    static let notifyUUID = "49535343-1E4D-4BD9-BA61-23C647249616"
    static let namePrefix = "Hello Fairy"

    static let header: UInt8 = 0xAA
    static let maxPixelsPerPacket = 79      // 242 byte GATT value
    static let daPacketBytes = 242

    static let presets: [(name: String, id: Int)] = [
        ("blue-white-dissolve", 41), ("blue-sparkle", 56), ("white-sparkle", 57),
        ("blue-pink-sparkle", 8), ("fireworks", 17), ("xmas", 18), ("candy-cane", 50),
        ("halloween", 20), ("red-gold", 40), ("july-4th", 39), ("valentine", 46),
        ("st-patrick", 47), ("may-day", 48), ("snow-day", 54),
    ]

    static let movements: [(name: String, id: Int)] = [
        ("still", 0), ("up", 1), ("down", 2), ("left", 3), ("right", 4),
        ("blink", 5), ("breathe", 6),
        ("loop-up", 7), ("loop-down", 8), ("loop-left", 9), ("loop-right", 10),
    ]

    // MARK: basics

    static func checksum(_ data: [UInt8]) -> UInt8 {
        UInt8(truncatingIfNeeded: data.reduce(0) { $0 + Int($1) })
    }

    static func build(_ cmd: UInt8, _ payload: [UInt8] = []) -> [UInt8] {
        precondition(payload.count <= 0xFF, "payload too long")
        let body: [UInt8] = [header, cmd, UInt8(payload.count)] + payload
        return body + [checksum(body)]
    }

    static func fromHex(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            out.append(UInt8(hex[idx..<next], radix: 16) ?? 0)
            idx = next
        }
        return out
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: lichterketten-kommandos

    static func power(_ on: Bool) -> [UInt8] { build(0x02, [on ? 1 : 0]) }

    /// h 0-359, s/v 0-100 prozent
    static func color(h: Int, s: Int, v: Int) -> [UInt8] {
        let hh = max(0, min(359, h))
        let ss = max(0, min(100, s)) * 10
        let vv = max(0, min(100, v)) * 10
        return build(0x03, [0x01, UInt8(hh >> 8), UInt8(hh & 0xFF), UInt8(ss >> 8), UInt8(ss & 0xFF),
                            UInt8(vv >> 8), UInt8(vv & 0xFF)])
    }

    static func preset(_ n: Int, brightness: Int) throws -> [UInt8] {
        guard (1...58).contains(n) else { throw ProtoError.invalid("preset muss 1..58 sein") }
        let b = max(0, min(100, brightness)) * 10
        return build(0x03, [0x02, UInt8(n), UInt8(b >> 8), UInt8(b & 0xFF)])
    }

    static func infoRequest() -> [UInt8] { build(0x00) }
    static func statusRequest() -> [UInt8] { build(0x01) }

    // MARK: pixel (DIY) kommandos

    static func d0(_ action: UInt8) -> [UInt8] {
        precondition([0x00, 0x01, 0x03, 0x04].contains(action), "unsupported D0 sub-command")
        return build(0xD0, [0x00, 0x64, 0x64, action])
    }

    /// geraet ist column-major
    static func pixelIndex(x: Int, y: Int) -> Int { x * H + y }

    static func isValidColor(_ c: UInt8) -> Bool { c <= 180 || c == Px.off || c == Px.white }

    /// kaputte werte werden zu "aus" statt zu crashen
    static func sanitize(_ c: UInt8) -> UInt8 { isValidColor(c) ? c : Px.off }

    /// wie viele pixel passen in ein paket, abhaengig von der BLE schreibkapazitaet
    static func pixelsPerPacket(writeCapacity: Int?) -> Int {
        guard let cap = writeCapacity, cap > 0 else { return maxPixelsPerPacket }
        return max(1, min(maxPixelsPerPacket, (cap - 5) / 3))
    }

    static func daPacket(_ items: ArraySlice<(Int, UInt8)>, slot: UInt8) -> [UInt8] {
        var payload: [UInt8] = [slot]
        payload.reserveCapacity(1 + items.count * 3)
        for (idx, col) in items {
            payload.append(UInt8(idx >> 8))
            payload.append(UInt8(idx & 0xFF))
            payload.append(sanitize(col))
        }
        return build(0xDA, payload)
    }

    /// 400 row-major farbbytes -> DA pakete (5x79 + 5 pixel bei vollem durchsatz)
    static func frameToDAPackets(_ frame: Frame, slot: UInt8 = 1,
                                 perPacket: Int = maxPixelsPerPacket) -> [[UInt8]] {
        precondition(frame.count == PIXELS, "frame must have 400 pixels")
        var entries: [(Int, UInt8)] = []
        entries.reserveCapacity(PIXELS)
        for x in 0..<W {
            for y in 0..<H {
                entries.append((pixelIndex(x: x, y: y), frame[y * W + x]))   // index steigt monoton
            }
        }
        return chunk(entries, perPacket, slot)
    }

    /// nur geaenderte pixel, bereits nach geraete-index sortiert
    static func deltaPackets(_ sorted: [(Int, UInt8)], slot: UInt8 = 1,
                             perPacket: Int = maxPixelsPerPacket) -> [[UInt8]] {
        chunk(sorted, perPacket, slot)
    }

    private static func chunk(_ entries: [(Int, UInt8)], _ per: Int, _ slot: UInt8) -> [[UInt8]] {
        let n = max(1, min(maxPixelsPerPacket, per))
        var out: [[UInt8]] = []
        var i = 0
        while i < entries.count {
            let j = min(entries.count, i + n)
            out.append(daPacket(entries[i..<j], slot: slot))
            i = j
        }
        return out
    }

    /// {device index: farbe} fuer ein ganzes frame
    static func frameToIndexColors(_ frame: Frame) -> [UInt8] {
        var out = [UInt8](repeating: Px.off, count: PIXELS)
        for y in 0..<H {
            for x in 0..<W { out[pixelIndex(x: x, y: y)] = frame[y * W + x] }
        }
        return out
    }

    /// wie die offizielle app: clear, draw mode, pixel, finish, apply
    static func singleImageSequence(_ frame: Frame, perPacket: Int = maxPixelsPerPacket) -> [SeqStep] {
        var seq = [
            SeqStep(label: "clear", packet: d0(0x03), delay: 0.0165),
            SeqStep(label: "draw mode", packet: d0(0x00), delay: 0.25),
        ]
        let packets = frameToDAPackets(frame, perPacket: perPacket)
        for (n, p) in packets.enumerated() {
            seq.append(SeqStep(label: "pixel \(n + 1)/\(packets.count)", packet: p,
                               delay: n + 1 < packets.count ? 0.30 : 1.20))
        }
        seq.append(SeqStep(label: "finish", packet: d0(0x04), delay: 0.02))
        seq.append(SeqStep(label: "apply", packet: d0(0x01), delay: 0.20))
        return seq
    }

    /// experimentell: blink/breathe zwischen zwei bildern (mitgeschnittene sequenz)
    static func twoPictureSequence(_ frames: [Frame], perPacket: Int = maxPixelsPerPacket) throws -> [SeqStep] {
        guard frames.count == 2 else { throw ProtoError.invalid("genau zwei bilder noetig") }
        var seq = [SeqStep(label: "init", packet: fromHex("aad0040564640752"), delay: 0.025)]
        for (i, frame) in frames.enumerated() {
            let slot = UInt8(i + 1)
            seq.append(SeqStep(label: "slot \(slot) begin", packet: build(0xD7, [slot, 0]), delay: 0.025))
            if slot == 1 {
                seq.append(SeqStep(label: "upload settings", packet: fromHex("aad004056464004b"), delay: 0.25))
            }
            let packets = frameToDAPackets(frame, slot: slot, perPacket: perPacket)
            for (n, p) in packets.enumerated() {
                seq.append(SeqStep(label: "slot \(slot) pixel \(n + 1)/\(packets.count)", packet: p, delay: 0.30))
            }
            seq.append(SeqStep(label: "slot \(slot) end", packet: build(0xD7, [slot, 2]), delay: 0.025))
        }
        seq.append(SeqStep(label: "playback", packet: fromHex("aad004056464024d"), delay: 0.025))
        seq.append(SeqStep(label: "trailing", packet: fromHex("aadc010087"), delay: 0.20))
        return seq
    }

    static func playbackPackets(kind: String, movement: String, speed: Int, brightness: Int) throws -> [[UInt8]] {
        guard let mv = movements.first(where: { $0.name == movement }) else {
            throw ProtoError.invalid("movement muss eins von \(movements.map { $0.name }.joined(separator: ", ")) sein")
        }
        guard (0...100).contains(speed), (0...100).contains(brightness) else {
            throw ProtoError.invalid("speed/helligkeit muessen 0..100 sein")
        }
        if kind == "animation" {
            guard movement == "blink" || movement == "breathe" else {
                throw ProtoError.invalid("animation geht nur mit blink oder breathe")
            }
            let d: UInt8 = movement == "breathe" ? 1 : 0
            return [build(0xD0, [d, UInt8(brightness), UInt8(speed), 2]), build(0xDC, [d])]
        }
        return [build(0xD0, [UInt8(mv.id), UInt8(brightness), UInt8(speed), 1])]
    }

    // MARK: farbumrechnung

    static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let v = mx
        if mx == mn { return (0, 0, v) }
        let d = mx - mn
        let s = d / mx
        let rc = (mx - r) / d, gc = (mx - g) / d, bc = (mx - b) / d
        var h: Double
        if r == mx { h = bc - gc } else if g == mx { h = 2.0 + rc - bc } else { h = 4.0 + gc - rc }
        h = (h / 6.0).truncatingRemainder(dividingBy: 1.0)
        if h < 0 { h += 1 }
        return (h, s, v)
    }

    static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (r: Double, g: Double, b: Double) {
        if s == 0 { return (v, v, v) }
        let i = Int(floor(h * 6.0))
        let f = h * 6.0 - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }

    static func hueByteToRGB(_ c: UInt8) -> (Int, Int, Int) {
        if c == Px.off { return (0, 0, 0) }
        if c == Px.white { return (255, 255, 255) }
        let (r, g, b) = hsvToRGB(Double(min(c, 180)) * 2 / 360, 1, 1)
        return (Int((r * 255).rounded(.toNearestOrEven)), Int((g * 255).rounded(.toNearestOrEven)),
                Int((b * 255).rounded(.toNearestOrEven)))
    }

    /// pro pixel gibt es nur hue / weiss / aus; helligkeit & saettigung gehen verloren
    static func rgbToPixelByte(r: Int, g: Int, b: Int, dark: Double = 0.18, white: Double = 0.18) -> UInt8 {
        let (h, s, v) = rgbToHSV(Double(r) / 255, Double(g) / 255, Double(b) / 255)
        if v < dark { return Px.off }
        if s < white { return Px.white }
        return UInt8(min(180, Int((h * 360 / 2).rounded(.toNearestOrEven))))
    }

    // MARK: notifications

    private static func isValid(_ d: [UInt8], cmd: UInt8) -> Bool {
        d.count >= 4 && d[0] == header && d[1] == cmd && Int(d[2]) == d.count - 4
            && checksum(Array(d.dropLast())) == d[d.count - 1]
    }

    /// liefert das bestaetigte kommando oder nil
    static func ackedCommand(_ d: [UInt8]) -> UInt8? {
        if d.count == 4, d[0] == header, d[2] == 0, checksum(Array(d[0..<3])) == d[3] { return d[1] }
        return nil
    }

    static func decodeStatus(_ d: [UInt8]) -> DeviceStatus? {
        guard d.count >= 9, isValid(d, cmd: 0x01) else { return nil }
        let p = Array(d[3..<(d.count - 1)])
        guard p.count >= 5, p[3] == 0 || p[3] == 1 else { return nil }
        let mode = Int(p[4])
        if (mode == 1 && p.count < 11) || (mode == 2 && p.count < 8) { return nil }
        func u16(_ i: Int) -> Int { Int(p[i]) << 8 | Int(p[i + 1]) }
        var out = DeviceStatus(power: p[3] == 1, mode: mode,
                               countdownSeconds: Int(p[0]) << 16 | Int(p[1]) << 8 | Int(p[2]))
        if mode == 1 {
            out.hue = u16(5)
            out.saturation = Double(u16(7)) / 10
            out.brightness = Double(u16(9)) / 10
        } else if mode == 2 {
            out.preset = Int(p[5])
            out.brightness = Double(u16(6)) / 10
        }
        return out
    }

    static func decodeDeviceInfo(_ d: [UInt8]) -> DeviceInfo? {
        guard d.count >= 31, isValid(d, cmd: 0x00) else { return nil }
        let p = Array(d[3..<(d.count - 1)])
        guard p.count >= 27 else { return nil }
        let fw = String(bytes: p[0..<5], encoding: .ascii)
        let modelBytes = p[5..<20].prefix { $0 != 0 }
        let model = String(bytes: modelBytes, encoding: .ascii)
        guard let fw, let model else { return nil }
        return DeviceInfo(firmware: fw, model: model, ledCount: Int(p[20]) << 8 | Int(p[21]),
                          columns: Int(p[22]), rows: Int(p[24]), diyType: Int(p[26]))
    }
}
